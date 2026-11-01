extends Node3D

signal wanted_changed(level: int)
signal busted
signal notification(text: String)

const PoliceCar = preload("res://town/gameplay/police_car.gd")
const MODEL = preload("res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_Police_01.tscn")
const SEARCH_SECONDS := 18.0
const ARREST_SECONDS := 4.0
var town: Node3D
var units: Array[CharacterBody3D] = []
var level := 0
var seen := false
var last_known := Vector3.ZERO
var unseen_time := 0.0
var arrest_time := 0.0
var response_age := 0.0
var _sense_tick := 0.0
var _route_tick := 0.0
var _spawn_tick := 0.0
var _search_index := 0
var _busted_emitted := false
var _was_seen := false
var rng := RandomNumberGenerator.new()


func configure(scene: Node3D) -> void:
	town = scene
	rng.randomize()


func report_crime(severity: int, origin: Vector3) -> void:
	if severity <= 0 or not is_instance_valid(town): return
	var previous := level
	level = clampi(level + severity, 1, 3)
	last_known = origin
	unseen_time = 0
	if previous == 0:
		arrest_time = 0
		response_age = 0
		_busted_emitted = false
	_route_tick = 0
	_spawn_tick = 0
	if level != previous: wanted_changed.emit(level)
	if previous == 0: notification.emit("Сообщение о преступлении. Уходите из поля зрения полиции")


func clear_wanted() -> void:
	var changed := level != 0
	level = 0
	seen = false
	_was_seen = false
	unseen_time = 0
	arrest_time = 0
	_busted_emitted = false
	for unit in units:
		if not is_instance_valid(unit): continue
		if is_instance_valid(town) and is_instance_valid(town.traffic): town.traffic.drivers.erase(unit)
		unit.queue_free()
	units.clear()
	if changed: wanted_changed.emit(0)


func get_state() -> Dictionary:
	var positions: Array[Vector3] = []
	for unit in units:
		if is_instance_valid(unit) and unit.damage <= 70: positions.append(unit.global_position)
	var status := "Нет розыска"
	if level > 0:
		status = "Уходите! Вас задерживают" if arrest_time > 0 else ("Погоня — оторвитесь от полиции" if seen else "Поиск — оставайтесь вне поля зрения")
	return {"level": level, "status": status, "search_progress": clampf(unseen_time / SEARCH_SECONDS, 0, 1) if level > 0 and not seen else 0.0,
		"arrest_progress": clampf(arrest_time / ARREST_SECONDS, 0, 1), "blips": positions, "seen": seen}


func _physics_process(delta: float) -> void:
	if level <= 0 or not is_instance_valid(town) or not is_instance_valid(town.traffic) or not town.traffic.initialized: return
	response_age += delta
	_sense_tick -= delta
	_route_tick -= delta
	_spawn_tick -= delta
	if _spawn_tick <= 0:
		_spawn_tick = 3.0
		if units.size() < level: _spawn_unit()
	if _sense_tick <= 0:
		_sense_tick = 0.15
		_sense_subject()
	if seen:
		unseen_time = 0
	else:
		unseen_time += delta
		if unseen_time >= SEARCH_SECONDS:
			level -= 1
			unseen_time = 0
			wanted_changed.emit(level)
			if level == 0:
				notification.emit("Вы скрылись от полиции")
				clear_wanted()
				return
			_retire_extra_units()
	if _route_tick <= 0:
		_route_tick = 1.2
		for unit in units:
			if not is_instance_valid(unit) or unit.damage > 70: continue
			var destination := last_known
			if not seen and unit.global_position.distance_to(last_known) < 13:
				destination = _search_destination(unit)
			unit.set_route(_route_to(unit.next_state if not unit.route.is_empty() else unit.state, destination))
	var subject := _subject()
	var stationary := false
	if is_instance_valid(subject):
		stationary = town.player_body.linear_velocity.length() < 1.2 if town.driving else town.character.velocity.length() < 1.0
	var close_officer := false
	if stationary and response_age > 3.0:
		for unit in units:
			if not is_instance_valid(unit) or unit.damage > 70: continue
			if unit.global_position.distance_to(subject.global_position) < (8.0 if town.driving else 6.0) and _can_see(unit, subject):
				close_officer = true
				break
	arrest_time = minf(ARREST_SECONDS, arrest_time + delta) if close_officer else maxf(0.0, arrest_time - delta * 2.0)
	if arrest_time >= ARREST_SECONDS and not _busted_emitted:
		_busted_emitted = true
		busted.emit()
		clear_wanted()


func _subject() -> Node3D:
	if not is_instance_valid(town): return null
	return town.player_body if town.driving else town.character


func _retire_extra_units() -> void:
	var subject := _subject()
	while units.size() > level:
		var furthest: CharacterBody3D
		var distance := -1.0
		for unit in units:
			if not is_instance_valid(unit): continue
			var candidate := unit.global_position.distance_squared_to(subject.global_position)
			if candidate > distance:
				furthest = unit
				distance = candidate
		if not is_instance_valid(furthest): break
		town.traffic.drivers.erase(furthest)
		units.erase(furthest)
		furthest.queue_free()


func _sense_subject() -> void:
	var subject := _subject()
	seen = false
	var closest: CharacterBody3D
	var closest_distance := INF
	for unit in units:
		if not is_instance_valid(unit) or unit.damage > 70: continue
		var distance := unit.global_position.distance_squared_to(subject.global_position)
		if distance < closest_distance:
			closest = unit
			closest_distance = distance
		if _can_see(unit, subject): seen = true
	if seen:
		last_known = subject.global_position
		if not _was_seen and response_age > 4: notification.emit("Полиция заметила вас")
	elif _was_seen:
		notification.emit("Полиция потеряла вас. Не возвращайтесь к патрулям")
	_was_seen = seen
	for unit in units:
		if not is_instance_valid(unit): continue
		unit.audible = unit == closest and closest_distance < 75 * 75
		unit.near_player = unit == closest and closest_distance < 30 * 30


func _can_see(unit: CharacterBody3D, subject: Node3D) -> bool:
	if not is_instance_valid(subject) or unit.damage > 70: return false
	var from := unit.global_position + Vector3.UP * 1.2
	var to := subject.global_position + Vector3.UP * 0.9
	if from.distance_squared_to(to) > (80.0 * 80.0 if town.driving else 58.0 * 58.0): return false
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 4 | 8, [unit.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == subject


func _spawn_unit() -> void:
	var world: Node3D = town.traffic
	var subject := _subject()
	var camera := get_viewport().get_camera_3d()
	var candidates: Array = world.lanes.keys()
	var best_path: Array[Vector3i] = []
	var best_state := Vector3i.ZERO
	var best_point := Vector3.ZERO
	var considered := 0
	for index in range(candidates.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap = candidates[index]
		candidates[index] = candidates[other]
		candidates[other] = swap
	for candidate: Vector3i in candidates:
		if world.junction_cells.has(Vector2i(candidate.x, candidate.y)): continue
		var point: Vector3 = world.lane_position(candidate)
		var distance := point.distance_to(subject.global_position)
		if distance < 48 or distance > 110: continue
		var occupied := false
		for other in world.drivers:
			if is_instance_valid(other) and other.global_position.distance_to(point) < 11:
				occupied = true
				break
		if occupied or not world._spawn_clear(point, Vector3(2.0, 1.8, 4.6), candidate.z * PI / 2): continue
		if is_instance_valid(camera) and camera.is_position_in_frustum(point + Vector3.UP):
			var obstruction := PhysicsRayQueryParameters3D.create(camera.global_position, point + Vector3.UP, 1, [town.player_body.get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(obstruction).is_empty(): continue
		var path := _route_to(candidate, last_known)
		if path.size() < 2 or world.lane_position(path[-1]).distance_to(last_known) > 25: continue
		considered += 1
		if best_path.is_empty() or path.size() < best_path.size():
			best_path = path
			best_state = candidate
			best_point = point
		if considered >= 12: break
	if best_path.is_empty(): return
	var unit := PoliceCar.new()
	unit.world = world
	unit.controller = self
	unit.state = best_state
	unit.model_scene = MODEL
	unit.position = best_point + Vector3.UP * 0.03
	add_child(unit)
	units.append(unit)
	world.drivers.append(unit)
	unit.cruise_speed = 12.0 + level * 1.5
	unit.set_route(best_path)


func _route_to(start: Vector3i, destination: Vector3) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var world: Node3D = town.traffic
	if not world.lanes.has(start): return result
	var queue: Array[Vector3i] = [start]
	var previous := {start: start}
	var cursor := 0
	var closest := start
	var nearest: float = world.lane_position(start).distance_squared_to(destination)
	while cursor < queue.size():
		var current := queue[cursor]
		cursor += 1
		var distance: float = world.lane_position(current).distance_squared_to(destination)
		if distance < nearest:
			nearest = distance
			closest = current
		for next: Vector3i in world.lanes.get(current, []):
			if previous.has(next): continue
			previous[next] = current
			queue.append(next)
	var step := closest
	result.append(step)
	while step != start:
		step = previous[step]
		result.append(step)
	result.reverse()
	return result


func _search_destination(unit: CharacterBody3D) -> Vector3:
	var options: Array[Vector3] = []
	for state: Vector3i in town.traffic.lanes:
		var point: Vector3 = town.traffic.lane_position(state)
		var distance := point.distance_to(last_known)
		if distance > 15 and distance < 35 and point.distance_to(unit.global_position) > 12: options.append(point)
	if options.is_empty(): return last_known
	_search_index += 1
	return options[_search_index % options.size()]


func _exit_tree() -> void:
	if not is_instance_valid(town) or not is_instance_valid(town.traffic): return
	for unit in units: town.traffic.drivers.erase(unit)
