extends Node3D

const GTAHud = preload("res://town/gta_hud.gd")
const Player = preload("res://town/player/city_player.gd")
const Atmosphere = preload("res://town/atmosphere.gd")
const CityAudio = preload("res://town/player/city_audio.gd")
const CityExperience = preload("res://town/gameplay/city_experience.gd")
enum Mood { SUNRISE, DAY, SUNSET, NIGHT }
@export var cash := 500
@export_range(0, 3) var wanted_level := 0
var mood := Mood.SUNSET
var gta_hud: GTAHud
var player_body: VehicleBody3D
var character: CharacterBody3D
var atmosphere: Node3D
var traffic: Node3D
var driving := true
var transition := false
var spawn_transform := Transform3D.IDENTITY
var vehicle_health := 100.0
var gameplay: Node
var _back_callback: Callable
var reflections_enabled := true
var status_message := ""
var status_time := 0.0
@onready var controls_sheet: Control = %Controls

func setup(car: Node3D, back_callback: Callable, reflections: bool) -> void:
	_back_callback = back_callback
	reflections_enabled = reflections
	for path in ["Camera", "WorldEnvironment", "Directional Light", "ReflectionProbe"]:
		var node := $CityMap.get_node_or_null(path)
		if node: node.free()
	for node in $CityMap/Environment.get_children():
		if "Skydome" in str(node.name): node.free()
	$CityMap/Road_Cars/SM_Veh_Car_Sedan_01.free()
	player_body = car.get_child(0)
	player_body.turbometer = %Turbometer
	player_body.turbo_animator = %TurboAnimator
	%Speedometer.car_body = player_body
	%InstancePos.add_child(car)
	%Back.text = "Пауза"
	%Back.pressed.connect(_open_game_menu)

func _ready() -> void:
	spawn_transform = %InstancePos.global_transform
	character = Player.new()
	add_child(character)
	character.fired.connect(_on_shot)
	gta_hud = GTAHud.new()
	gta_hud.city_map = $CityMap
	gta_hud.player_body = player_body
	gta_hud.cash = cash
	gta_hud.wanted_level = wanted_level
	add_child(gta_hud)
	atmosphere = Atmosphere.new()
	atmosphere.screen_space_reflections = reflections_enabled
	add_child(atmosphere)
	atmosphere.configure($CityMap, $DirectionalLight3D, $WorldEnvironment, player_body)
	atmosphere.set_hour([6.5, 12.0, 17.5, 22.0][mood])
	atmosphere.night_changed.connect(func(night: bool): player_body.set_headlights(night))
	player_body.set_headlights(atmosphere.is_night())
	var city_audio := CityAudio.new()
	add_child(city_audio)
	city_audio.configure(character, atmosphere)
	controls_sheet.hide()
	$CarUI.hide()
	$GameUI/PanelContainer/MarginContainer/VBoxContainer/Label.text = "F1 — управление"
	%Controls/Label.text = "WASD — движение • Shift — бег/ускорение\nE — сесть/выйти • C — камера • Space — прыжок/тормоз\nQ — оружие • ПКМ — прицел • ЛКМ — выстрел • R — перезарядка"
	%Controls/Label2.text = "F — действие / сервис • Tab — заказы • Esc — пауза\nM — время суток • L — фары • H — сигнал • F5 — эвакуация ($75)"
	# Runtime ownership stays outside the purchased map scene.
	if ResourceLoader.exists("res://town/traffic/traffic_world.gd"):
		traffic = load("res://town/traffic/traffic_world.gd").new()
		add_child(traffic)
		traffic.configure($CityMap, player_body)
	gameplay = CityExperience.new()
	add_child(gameplay)
	gameplay.configure(self, _back_callback)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	gta_hud.cash = cash
	gta_hud.wanted_level = wanted_level
	gta_hud.clock_text = atmosphere.get_clock_text()
	gta_hud.driving = driving
	gta_hud.weapon_drawn = character.weapon_drawn
	gta_hud.ammo_text = "%02d / %02d" % [character.magazine, character.reserve]
	gta_hud.health = character.health
	gta_hud.speed = player_body.linear_velocity.length() * 3.6
	gta_hud.boost_value = %Turbometer.value / %Turbometer.max_value
	gta_hud.hint = "E — выйти   C — камера   ПКМ + мышь — обзор" if driving else "E — сесть   C — камера   Q — оружие   ПКМ — прицел"
	if not driving and character.global_position.distance_to(player_body.global_position) >= 4:
		gta_hud.hint = "Shift — бег   C — камера   Q — оружие   ПКМ — прицел"
	if not driving and character.reload_time > 0: gta_hud.hint = "ПЕРЕЗАРЯДКА…"
	if gameplay:
		var action_hint: String = gameplay.context_hint()
		if not action_hint.is_empty(): gta_hud.hint = action_hint
	status_time = maxf(0, status_time - delta)
	if status_time > 0: gta_hud.hint = status_message
	if player_body.global_position.y < -12 or (not driving and character.global_position.y < -12):
		gameplay.recover_world_fall()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E: _interact()
		elif event.physical_keycode == KEY_F5: gameplay.recover_vehicle()
		elif event.physical_keycode == KEY_R and driving: gameplay.recover_vehicle()
	if event.is_action_pressed("cycle_mood"): atmosphere.advance_period()
	elif event.is_action_pressed("toggle_controls"): controls_sheet.visible = not controls_sheet.visible

func _interact() -> void:
	if transition: return
	if driving:
		if player_body.linear_velocity.length() > 1.5:
			_status("Сначала остановите автомобиль")
			return
		var destination := _safe_exit()
		if destination == Vector3.INF:
			_status("Выход заблокирован")
			return
		transition = true
		player_body.set_controlled(false)
		character.global_position = destination
		character.yaw = atan2(-player_body.global_basis.z.x, -player_body.global_basis.z.z)
		character.set_active(true)
		driving = false
		_set_subject(character)
		await get_tree().create_timer(0.35).timeout
		transition = false
	elif character.global_position.distance_to(player_body.global_position) < 4:
		var sight := PhysicsRayQueryParameters3D.create(character.global_position + Vector3.UP, player_body.global_position + Vector3.UP, 1 | 4 | 8, [character.get_rid(), player_body.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
			_status("Подойдите к свободной двери")
			return
		transition = true
		character.set_active(false)
		player_body.set_controlled(true)
		driving = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_set_subject(player_body)
		await get_tree().create_timer(0.35).timeout
		transition = false

func _safe_exit() -> Vector3:
	var space := get_world_3d().direct_space_state
	for side in [1.0, -1.0]:
		var destination: Vector3 = player_body.global_position + player_body.global_basis.x * side * 2.1
		var ray := PhysicsRayQueryParameters3D.create(player_body.global_position + Vector3.UP, destination + Vector3.UP, 1 | 4 | 8, [player_body.get_rid()])
		if not space.intersect_ray(ray).is_empty(): continue
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(destination + Vector3.UP * 2, destination - Vector3.UP * 3, 1, [player_body.get_rid()]))
		if ground.is_empty(): continue
		destination = ground.position + Vector3.UP * 0.08
		var check := PhysicsShapeQueryParameters3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.75
		check.shape = capsule
		check.transform.origin = destination + Vector3.UP * 0.95
		check.collision_mask = 1 | 4 | 8
		check.exclude = [player_body.get_rid()]
		if space.intersect_shape(check, 1).is_empty(): return destination
	return Vector3.INF

func _set_subject(subject: Node3D) -> void:
	gta_hud.player_body = subject
	gta_hud.radar.player_body = subject
	atmosphere.set_subject(subject)
	if traffic and traffic.has_method("set_subject"): traffic.set_subject(subject)

func _on_shot(origin: Vector3, _destination: Vector3, collider: Object) -> void:
	gameplay.report_shot(origin, collider)
	if traffic and traffic.has_method("alert_nearby"): traffic.alert_nearby(origin)

func reset_vehicle() -> bool:
	var space := get_world_3d().direct_space_state
	var collider := player_body.get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.collision_mask = 1 | 2 | 4 | 8
	query.exclude = [player_body.get_rid()]
	var reset_pose := spawn_transform
	var available := false
	var candidates: Array[Transform3D] = []
	for offset in [0.0, -8.0, 8.0, -16.0, 16.0, -24.0, 24.0]:
		var candidate := spawn_transform
		candidate.origin += candidate.basis.z * offset
		candidates.append(candidate)
	if is_instance_valid(traffic) and traffic.initialized:
		var states: Array = traffic.lanes.keys()
		states.sort_custom(func(a: Vector3i, b: Vector3i): return traffic.lane_position(a).distance_squared_to(spawn_transform.origin) < traffic.lane_position(b).distance_squared_to(spawn_transform.origin))
		for index in mini(states.size(), 96):
			var state: Vector3i = states[index]
			var forward: Vector2i = traffic.DIRECTIONS[state.z]
			candidates.append(Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.y)), traffic.lane_position(state) + Vector3.UP * 0.5))
	for candidate in candidates:
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(candidate.origin + Vector3.UP * 2, candidate.origin - Vector3.UP * 4, 1, [player_body.get_rid()]))
		if ground.is_empty() or ground.normal.y < 0.8: continue
		if absf(ground.position.y - (spawn_transform.origin.y - 0.5)) > 0.35: continue
		candidate.origin.y = ground.position.y + 0.5
		query.transform = candidate * collider.transform
		if space.intersect_shape(query, 1).is_empty():
			reset_pose = candidate
			available = true
			break
	if not available:
		_status("Место восстановления занято — попробуйте ещё раз")
		return false
	player_body.global_transform = reset_pose
	player_body.linear_velocity = Vector3.ZERO
	player_body.angular_velocity = Vector3.ZERO
	player_body.constant_force = Vector3.ZERO
	player_body.sleeping = false
	player_body.reset_physics_interpolation()
	player_body.get_node("CameraBase/Camera3D").update_camera()
	return true

func _open_game_menu() -> void:
	if gameplay: gameplay.open_menu()

func _status(message: String) -> void:
	status_message = message
	status_time = 2.0

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
