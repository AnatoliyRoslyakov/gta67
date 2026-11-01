extends Node3D

signal changed
signal completed(reward: int, kind: String, bonus: int)
signal notification(text: String)
signal failed(reason: String)

const INVALID_STATE := Vector3i(2147483647, 2147483647, 2147483647)
const ARRIVAL_RADIUS := 5.5
const HANDOFF_SPEED := 1.2

var town: Node3D
var traffic: Node3D
var active := false
var kind := ""
var stage := 0
var reward := 0
var elapsed := 0.0
var time_limit := 0.0
var last_time := 0.0
var last_kind := ""
var last_result := ""
var target := Vector3.ZERO
var route: Array[Vector3] = []
var routes_ready := false
var _states: Array[Vector3i] = []
var _goals: Array[Vector3i] = []
var _circuit_goals: Array[Vector3i] = []
var _circuit_length := 0.0
var _race_started := false
var _route_timer := 0.0
var _distance := 0.0
var _initial_health := 100.0
var _minimum_health := 100.0
var _arrival_latch := false
var _route_missing := false
var _marker: Node3D
var _marker_label: Label3D
var _marker_material: StandardMaterial3D
var _rng := RandomNumberGenerator.new()


func configure(scene: Node3D) -> void:
	town = scene
	_rng.randomize()
	if is_inside_tree() and not is_instance_valid(_marker): _build_marker()


func _ready() -> void:
	if not is_instance_valid(_marker): _build_marker()


func _process(delta: float) -> void:
	if not is_instance_valid(town): return
	if not routes_ready:
		traffic = town.get("traffic")
		if not is_instance_valid(traffic) or not bool(traffic.get("initialized")): return
		for state in traffic.lanes: _states.append(state)
		routes_ready = not _states.is_empty()
		_build_fixed_circuit()
		changed.emit()
	if not active: return
	if kind != "circuit" or _race_started: elapsed += delta
	_minimum_health = minf(_minimum_health, _vehicle_health())
	if _minimum_health <= 0:
		fail_contract("Машина повреждена. Заказ отменён")
		return
	if kind == "circuit" and _race_started and elapsed >= time_limit:
		fail_contract("Время маршрута истекло. Можно попробовать снова")
		return
	_route_timer -= delta
	if _route_timer <= 0.0:
		_route_timer = 1.0
		_refresh_route()
		changed.emit()
	var near := _player_position().distance_to(target) <= ARRIVAL_RADIUS
	if kind == "circuit" and _race_started and bool(town.get("driving")) and near:
		_advance()
		return
	var can_handoff := near and _can_handoff()
	if can_handoff and not _arrival_latch:
		notification.emit("F — начать заезд" if kind == "circuit" else ("F — забрать посылку" if stage == 0 else "F — передать посылку"))
	_arrival_latch = can_handoff
	_marker_label.text = ("Забрать посылку" if stage == 0 else "Доставка") if kind == "delivery" else ("Старт заезда · F" if not _race_started else "Маршрут %d / 4" % stage)


func start_contract(requested_kind: String) -> bool:
	if active:
		notification.emit("Сначала завершите или отмените текущий заказ")
		return false
	if not routes_ready:
		notification.emit("Город загружается. Заказы скоро будут доступны")
		return false
	if requested_kind not in ["delivery", "circuit"]: return false
	if int(town.get("wanted_level")) > 0:
		notification.emit("Сначала скройтесь от полиции")
		return false
	if _vehicle_health() <= 15:
		notification.emit("Сначала отремонтируйте машину")
		return false
	var starts := _nearest_states(_player_position(), _car_forward())
	var source := INVALID_STATE
	var reach: Dictionary = {}
	for candidate in starts:
		var candidate_reach := _reachable(candidate)
		if candidate_reach.distance.size() > reach.get("distance", {}).size():
			source = candidate
			reach = candidate_reach
		if reach.distance.size() >= 60: break
	if source == INVALID_STATE:
		notification.emit("Выезжайте на городскую дорогу, чтобы принять заказ")
		return false
	_goals.clear()
	var total_length := 0.0
	var previous := source
	var count := 2 if requested_kind == "delivery" else 0
	if requested_kind == "circuit":
		if _circuit_goals.is_empty():
			notification.emit("Городской круг пока недоступен")
			return false
		_goals.assign(_circuit_goals)
		total_length = _circuit_length
	for index in count:
		var paths := _reachable(previous)
		var minimum := 45.0 if requested_kind == "delivery" and index == 0 else 80.0
		var maximum := 145.0 if requested_kind == "delivery" and index == 0 else 230.0
		var chosen := _pick_destination(paths, previous, minimum, maximum, requested_kind == "delivery")
		if chosen == INVALID_STATE:
			_goals.clear()
			notification.emit("Для заказа не найден свободный маршрут. Попробуйте с другой улицы")
			return false
		total_length += float(paths.distance[chosen])
		_goals.append(chosen)
		previous = chosen
	kind = requested_kind
	stage = 0
	active = true
	_race_started = false
	elapsed = 0.0
	_initial_health = _vehicle_health()
	_minimum_health = _initial_health
	_last_result_clear()
	reward = (180 + roundi(total_length * 0.65)) if kind == "delivery" else (320 + roundi(total_length * 0.5))
	time_limit = clampf(90.0 + total_length / 5.0, 180.0, 420.0) if kind == "circuit" else 0.0
	_set_target()
	notification.emit("Заказ принят. Заберите посылку у отметки" if kind == "delivery" else "Подъезжайте на старт. Таймер начнётся после F")
	changed.emit()
	return true


func cancel_contract() -> void:
	if active: fail_contract("Заказ отменён. Штрафа нет")


func fail_contract(reason: String) -> void:
	if not active: return
	active = false
	last_result = reason
	route.clear()
	_marker.hide()
	failed.emit(reason)
	notification.emit(reason)
	changed.emit()


func on_vehicle_reset() -> void:
	if active: fail_contract("Машина восстановлена. Текущий заказ отменён")


func interact() -> bool:
	if not active or (kind == "circuit" and _race_started): return false
	if _player_position().distance_to(target) > ARRIVAL_RADIUS: return false
	if not bool(town.get("driving")):
		notification.emit("Сядьте в машину, чтобы начать заезд" if kind == "circuit" else "Сядьте в машину для передачи посылки")
		return true
	if int(town.get("wanted_level")) > 0:
		notification.emit("Сначала скройтесь от полиции")
		return true
	if _car_speed() > HANDOFF_SPEED:
		notification.emit("Остановитесь у отметки")
		return true
	if kind == "circuit":
		_race_started = true
		elapsed = 0.0
		_initial_health = _vehicle_health()
		_minimum_health = _initial_health
		stage = 1
		_set_target()
		notification.emit("Старт! Четыре контрольные точки, финиш на месте старта")
		changed.emit()
		return true
	_advance()
	return true


func get_state() -> Dictionary:
	var title := "Городские заказы"
	var description := "Выберите доставку или маршрут в меню города"
	if active:
		if kind == "delivery":
			title = "Доставка · забрать посылку" if stage == 0 else "Доставка · передать клиенту"
			description = "Остановитесь у отметки и нажмите F. Бонус за аккуратную езду"
		else:
			title = "Городской круг · точка %d из 4" % stage if _race_started else "Городской круг · подъехать на старт"
			description = "Проезжайте через отметки. Побейте свой рекорд" if _race_started else "Остановитесь у старта и нажмите F — тогда начнётся таймер"
		if _route_missing: description = "Вернитесь на ближайшую дорогу — маршрут перестроится"
		elif int(town.get("wanted_level")) > 0 and kind == "delivery": description = "Скройтесь от полиции, чтобы встретиться с клиентом"
	elif not routes_ready: description = "Подготавливаем городские маршруты…"
	return {
		"ready": routes_ready, "active": active, "kind": kind, "title": title,
		"description": description, "stage": stage, "reward": reward,
		"distance": _distance if active else 0.0, "route": route.duplicate(),
		"target": target, "marker_visible": active, "can_interact": active and (kind == "delivery" or not _race_started) and _player_position().distance_to(target) <= ARRIVAL_RADIUS and _can_handoff(),
		"interaction": "начать заезд" if kind == "circuit" else ("забрать посылку" if stage == 0 else "передать посылку"),
		"progress": (float(stage - 1) / 4.0 if kind == "circuit" and _race_started else float(stage) / maxf(1, _goals.size())) if active else 0.0,
		"time_left": maxf(0, time_limit - elapsed) if active and kind == "circuit" and _race_started else -1.0,
		"race_started": _race_started if active and kind == "circuit" else false,
		"elapsed": elapsed, "last_time": last_time, "last_kind": last_kind, "last_result": last_result,
		"bonus_possible": active and _initial_health - _minimum_health < 4.0,
	}


func _advance() -> void:
	_minimum_health = minf(_minimum_health, _vehicle_health())
	stage += 1
	if stage >= _goals.size():
		var bonus := 100 if _initial_health - _minimum_health < 4.0 else 0
		last_time = elapsed
		last_kind = kind
		last_result = "Заказ выполнен: +$%d" % (reward + bonus)
		if bonus > 0: last_result += " · $100 за аккуратную езду"
		active = false
		route.clear()
		_marker.hide()
		completed.emit(reward + bonus, kind, bonus)
		notification.emit(last_result)
		changed.emit()
		return
	_set_target()
	notification.emit("Посылка в машине. Отвезите её клиенту" if kind == "delivery" else "Контрольная точка пройдена · осталось %d" % (_goals.size() - stage))
	changed.emit()


func _set_target() -> void:
	target = traffic.lane_position(_goals[stage])
	_marker.global_position = target + Vector3.UP * 0.06
	_marker.show()
	_marker_material.albedo_color = Color(0.94, 0.77, 0.45, 0.7)
	_arrival_latch = false
	_route_timer = 1.0
	_refresh_route()


func _build_fixed_circuit() -> void:
	# The same map always produces the same lap, so saved times are comparable.
	_states.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		if a.x != b.x: return a.x < b.x
		if a.y != b.y: return a.y < b.y
		return a.z < b.z)
	var reverse_edges: Dictionary = {}
	for state in _states:
		for next: Vector3i in traffic.lanes[state]:
			if not reverse_edges.has(next): reverse_edges[next] = []
			reverse_edges[next].append(state)
	var spawn: Variant = town.get("spawn_transform")
	var anchor: Vector3 = spawn.origin if typeof(spawn) == TYPE_TRANSFORM3D else Vector3(-2.5, 0.5, -57.5)
	var start := INVALID_STATE
	var component: Array[Vector3i] = []
	for candidate in _nearest_states(anchor, Vector3.BACK, _states.size()):
		if traffic.junction_cells.has(Vector2i(candidate.x, candidate.y)): continue
		var outward: Dictionary = _reachable(candidate).distance
		var returning := {candidate: true}
		var queue: Array[Vector3i] = [candidate]
		var index := 0
		while index < queue.size():
			var current := queue[index]
			index += 1
			for previous: Vector3i in reverse_edges.get(current, []):
				if returning.has(previous): continue
				returning[previous] = true
				queue.append(previous)
		var options: Array[Vector3i] = []
		for state in _states:
			if outward.has(state) and returning.has(state): options.append(state)
		if options.size() > component.size():
			component = options
			start = candidate
		if component.size() >= 60: break
	if start == INVALID_STATE or component.size() < 24: return
	var origin: Vector3 = traffic.lane_position(start)
	var farthest := start
	var far_distance := 0.0
	for state in component:
		var distance: float = traffic.lane_position(state).distance_squared_to(origin)
		if distance > far_distance:
			far_distance = distance
			farthest = state
	var axis: Vector3 = traffic.lane_position(farthest) - origin
	var corner := INVALID_STATE
	var area := -1.0
	for state in component:
		var offset: Vector3 = traffic.lane_position(state) - origin
		if offset.length() < 30 or (offset - axis).length() < 30: continue
		var candidate_area := absf(axis.x * offset.z - axis.z * offset.x)
		if candidate_area > area:
			area = candidate_area
			corner = state
	if corner == INVALID_STATE: return
	var closed: Array[Vector3i] = [start]
	var previous := start
	for destination in [farthest, corner, start]:
		var leg := _path_states(previous, destination)
		if leg.is_empty(): return
		leg.pop_front()
		closed.append_array(leg)
		previous = destination
	_circuit_goals = [start]
	# Three spaced gates plus the finish produce four timed checkpoints.
	for quarter in range(1, 4):
		var index := roundi(float(closed.size() - 1) * quarter / 4.0)
		var candidate := closed[index]
		for offset in range(0, 12):
			var adjusted := closed[mini(index + offset, closed.size() - 2)]
			if traffic.junction_cells.has(Vector2i(adjusted.x, adjusted.y)): continue
			var valid := true
			for goal in _circuit_goals:
				if traffic.lane_position(goal).distance_to(traffic.lane_position(adjusted)) < 25:
					valid = false
					break
			if valid:
				candidate = adjusted
				break
		_circuit_goals.append(candidate)
	_circuit_goals.append(start)
	_circuit_length = 0.0
	for index in range(1, _circuit_goals.size()):
		var leg := _reachable(_circuit_goals[index - 1], _circuit_goals[index])
		_circuit_length += float(leg.distance[_circuit_goals[index]])


func _path_states(source: Vector3i, destination: Vector3i) -> Array[Vector3i]:
	var paths := _reachable(source, destination)
	if not paths.distance.has(destination): return []
	var path: Array[Vector3i] = [destination]
	var cursor := destination
	while cursor != source:
		cursor = paths.parent[cursor]
		path.append(cursor)
	path.reverse()
	return path


func _refresh_route() -> void:
	if not active: return
	route.clear()
	var destination := _goals[stage]
	for source in _nearest_states(_player_position(), _car_forward()):
		var paths := _reachable(source, destination)
		if not paths.distance.has(destination): continue
		var reversed: Array[Vector3i] = [destination]
		var cursor := destination
		while cursor != source:
			cursor = paths.parent[cursor]
			reversed.append(cursor)
		reversed.reverse()
		for state in reversed: route.append(traffic.lane_position(state))
		_distance = float(paths.distance[destination]) + _player_position().distance_to(route[0])
		_route_missing = false
		return
	_route_missing = true
	_distance = _player_position().distance_to(target)


func _reachable(source: Vector3i, destination := INVALID_STATE) -> Dictionary:
	var parent: Dictionary = {}
	var distance := {source: 0.0}
	var queue: Array[Vector3i] = [source]
	var index := 0
	while index < queue.size():
		var state := queue[index]
		index += 1
		if state == destination: break
		for next: Vector3i in traffic.lanes.get(state, []):
			if distance.has(next): continue
			parent[next] = state
			distance[next] = float(distance[state]) + 5.0
			queue.append(next)
	return {"parent": parent, "distance": distance}


func _nearest_states(p: Vector3, forward: Vector3, limit := 8) -> Array[Vector3i]:
	var options: Array[Vector3i] = _states.duplicate()
	options.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _state_score(a, p, forward) < _state_score(b, p, forward))
	options.resize(mini(limit, options.size()))
	return options


func _state_score(state: Vector3i, p: Vector3, forward: Vector3) -> float:
	var axis: Vector2i = traffic.DIRECTIONS[state.z]
	var heading := Vector3(axis.x, 0, axis.y)
	return traffic.lane_position(state).distance_squared_to(p) + (1.0 - forward.dot(heading)) * 20.0


func _pick_destination(paths: Dictionary, source: Vector3i, minimum: float, maximum: float, require_curb: bool) -> Vector3i:
	var options: Array[Vector3i] = []
	for state: Vector3i in paths.distance:
		var distance: float = paths.distance[state]
		if distance < minimum or distance > maximum: continue
		if traffic.junction_cells.has(Vector2i(state.x, state.y)): continue
		var p: Vector3 = traffic.lane_position(state)
		if p.distance_to(traffic.lane_position(source)) < minimum * 0.55: continue
		var duplicate := false
		for goal in _goals:
			if p.distance_to(traffic.lane_position(goal)) < 30: duplicate = true; break
		if duplicate: continue
		if require_curb and not _near_sidewalk(p): continue
		options.append(state)
	if options.is_empty(): return INVALID_STATE
	return options[_rng.randi_range(0, options.size() - 1)]


func _near_sidewalk(p: Vector3) -> bool:
	var center := Vector2i(floori(p.x / 2.5), floori(p.z / 2.5))
	for x in range(-3, 4):
		for z in range(-3, 4):
			if traffic.sidewalk_cells.has(center + Vector2i(x, z)): return true
	return false


func _player_position() -> Vector3:
	if is_instance_valid(town) and is_instance_valid(town.get("player_body")):
		return town.player_body.global_position
	return Vector3.ZERO


func _car_forward() -> Vector3:
	return town.player_body.global_basis.z.normalized() if is_instance_valid(town.get("player_body")) else Vector3.BACK


func _car_speed() -> float:
	return town.player_body.linear_velocity.length() if is_instance_valid(town.get("player_body")) else 0.0


func _vehicle_health() -> float:
	var value: Variant = town.get("vehicle_health") if is_instance_valid(town) else null
	return float(value) if value != null else 100.0


func _can_handoff() -> bool:
	return is_instance_valid(town) and bool(town.get("driving")) and int(town.get("wanted_level")) == 0 and _car_speed() <= HANDOFF_SPEED


func _last_result_clear() -> void:
	last_result = ""


func _build_marker() -> void:
	_marker = Node3D.new()
	_marker.name = "ContractDestination"
	add_child(_marker)
	_marker_material = StandardMaterial3D.new()
	_marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_material.albedo_color = Color(0.94, 0.77, 0.45, 0.7)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 2.45
	mesh.outer_radius = 2.65
	mesh.rings = 32
	mesh.ring_segments = 8
	ring.mesh = mesh
	ring.material_override = _marker_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(ring)
	_marker_label = Label3D.new()
	_marker_label.position.y = 3.1
	_marker_label.pixel_size = 0.008
	_marker_label.font_size = 30
	_marker_label.outline_size = 8
	_marker_label.modulate = Color("f1f3e8")
	_marker_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.add_child(_marker_label)
	_marker.hide()
