extends Node3D

const City = preload("res://game/city_builder.gd")
const Person = preload("res://game/character.gd")
const Vehicle = preload("res://game/original_vehicle.gd")
const Actor = preload("res://game/ambient_actor.gd")
const Radar = preload("res://game/radar.gd")
const SPAWN := Vector3(187.1, 0.5, 31)
const DESTINATIONS := [Vector3(184, 0, 280), Vector3(64, 0, 64), Vector3(-176, 0, -176), Vector3(184, 0, -260)]
const DESTINATION_NAMES := ["Пирс 67", "Парк Пальм", "Деловой квартал", "Северный пляж"]
var city: Node3D
var player: CharacterBody3D
var driven: VehicleBody3D
var cars: Array[VehicleBody3D] = []
var officers: Array[CharacterBody3D] = []
var marker: Node3D
var radar: Control
var cash := 500
var health := 100.0
var wanted := 0
var crime_clock := 0.0
var police_clock := 0.0
var shot_clock := 0.0
var mission := 0
var paused := false
var notice_clock := 9.0
var notice := "Добро пожаловать в Coastline. Подойди к коралловой машине и нажми E."
var cash_label: Label
var wanted_label: Label
var mission_label: Label
var hint_label: Label
var speed_label: Label
var notice_label: Label
var health_bar: ProgressBar
var turbo_bar: ProgressBar
var turbo_animator: AnimationPlayer
var pause_panel: Panel
var ambience: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_key("interact", KEY_E)
	_bind_key("jump", KEY_SPACE)
	_environment()
	_build_hud()
	city = City.new()
	city.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(city)
	player = Person.new()
	player.position = SPAWN
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.pivot.rotation.y = PI
	_spawn_car(Vector3(184, 0.7, 32), Color("e99087"), "sport", "SUNLINE GT")
	_spawn_car(Vector3(184, 0.7, -14), Color("e4c477"), "taxi", "COAST CAB")
	_spawn_car(Vector3(184, 0.7, 100), Color("75b9c1"), "sedan", "BAY SEDAN")
	_spawn_traffic()
	_spawn_people()
	_build_marker()
	if DisplayServer.get_name() != "headless":
		ambience = AudioStreamPlayer.new()
		ambience.stream = preload("res://town/sound/mood_sunset.ogg")
		ambience.volume_db = -15
		ambience.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(ambience)
		ambience.play()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(ambience):
		ambience.stop()
		ambience.stream = null


func _bind_key(action: String, key: Key) -> void:
	if InputMap.has_action(action): return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)


func _environment() -> void:
	var environment := Environment.new()
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("547b9a")
	material.sky_horizon_color = Color("edc6b9")
	material.ground_horizon_color = Color("edc6b9")
	material.ground_bottom_color = Color("646b77")
	material.sun_angle_max = 12
	sky.sky_material = material
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8c6d8")
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("d4bab9")
	environment.fog_density = 0.0008
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-26, -55, 0)
	sun.light_color = Color("ffdbb5")
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220
	add_child(sun)


func _spawn_car(p: Vector3, tint: Color, kind: String, title: String) -> void:
	var root := preload("res://vehicles/car_base.tscn").instantiate()
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	root.position = p
	var body := root.get_child(0) as VehicleBody3D
	body.set_script(Vehicle)
	body.tint = tint
	body.kind = kind
	body.display_name = title
	body.turbometer = turbo_bar
	body.turbo_animator = turbo_animator
	add_child(root)
	cars.append(body)


func _spawn_traffic() -> void:
	var corners := PackedVector3Array([Vector3(184, 0.1, -284), Vector3(184, 0.1, 304), Vector3(-304, 0.1, 304), Vector3(-304, 0.1, -304), Vector3(176, 0.1, -304)])
	for i in 8:
		var actor := Actor.new()
		actor.route = corners.duplicate()
		actor.target_index = 1
		actor.position = Vector3(184, 0.1, -270 + i * 62)
		actor.speed = 8 + i % 3
		actor.tint = [Color("a4c8bd"), Color("b5abcb"), Color("e3c594"), Color("94b8c9")][i % 4]
		actor.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(actor)


func _spawn_people() -> void:
	for i in 18:
		var person := Actor.new()
		person.pedestrian = true
		person.speed = 1.1 + (i % 4) * 0.2
		person.tint = [Color("c49eab"), Color("d4bc8f"), Color("7ca49b"), Color("b5b0cb")][i % 4]
		var x := 204.0 if i % 2 else 247.0
		var z := -260.0 + i * 31
		person.route = PackedVector3Array([Vector3(x, 0.4, z), Vector3(x, 0.4, z + 65)])
		person.position = person.route[0]
		person.target_index = 1
		person.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(person)


func _build_marker() -> void:
	marker = Node3D.new()
	marker.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(marker)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 5.7
	torus.outer_radius = 6.2
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ee99c6")
	material.emission_enabled = true
	material.emission = Color("e48abb")
	material.emission_energy_multiplier = 1.4
	ring.material_override = material
	marker.add_child(ring)
	var label := Label3D.new()
	label.text = "МЕСТО НАЗНАЧЕНИЯ"
	label.position.y = 4
	label.font_size = 48
	label.pixel_size = 0.015
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.add_child(label)
	marker.position = DESTINATIONS[0] + Vector3.UP * 0.15


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back"):
		_toggle_pause()
		return
	if paused: return
	if event.is_action_pressed("interact"): _interact()
	elif event.is_action_pressed("reset_vehicle"): _respawn()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not is_instance_valid(driven): _shoot()


func _interact() -> void:
	if is_instance_valid(driven):
		if driven.linear_velocity.length() > 4:
			_message("Остановись, чтобы выйти.")
			return
		var exit_position := driven.global_position + driven.global_basis.x * 2.4 + Vector3.UP * 0.4
		var query := PhysicsRayQueryParameters3D.create(driven.global_position + Vector3.UP, exit_position + Vector3.UP, 1, [driven.get_rid()])
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			exit_position = driven.global_position - driven.global_basis.x * 2.4 + Vector3.UP * 0.4
		driven.set_active(false)
		player.global_position = exit_position
		player.velocity = Vector3.ZERO
		player.active = true
		player.visible = true
		player.collision_layer = 1
		player.collision_mask = 1
		player.pivot.rotation.y = driven.rotation.y + PI
		player.camera.make_current()
		player.reset_physics_interpolation()
		driven = null
	else:
		var nearest := _nearest_car()
		if nearest == null: return
		driven = nearest
		player.active = false
		player.visible = false
		player.collision_layer = 0
		player.collision_mask = 0
		driven.set_active(true)
		_message("%s — следуй к розовому маркеру." % driven.display_name)


func _nearest_car() -> VehicleBody3D:
	var nearest: VehicleBody3D
	var distance := 4.0
	for car in cars:
		var candidate := player.global_position.distance_to(car.global_position)
		if candidate < distance:
			distance = candidate
			nearest = car
	return nearest


func _physics_process(delta: float) -> void:
	if paused or not is_instance_valid(player): return
	shot_clock = maxf(shot_clock - delta, 0)
	notice_clock = maxf(notice_clock - delta, 0)
	var subject: Vector3 = driven.global_position if is_instance_valid(driven) else player.global_position
	if subject.y < -8 or subject.x > 370 or absf(subject.z) > 410 or subject.x < -420:
		_respawn()
	if is_instance_valid(driven):
		for person in get_tree().get_nodes_in_group("pedestrians"):
			if person.stun <= 0 and person.global_position.distance_to(subject) < 2.2 and driven.linear_velocity.length() > 4:
				person.knock_down()
				_crime(2)
		if subject.distance_to(DESTINATIONS[mission]) < 9:
			cash += 500
			mission = (mission + 1) % DESTINATIONS.size()
			marker.position = DESTINATIONS[mission] + Vector3.UP * 0.15
			_message("Доставка выполнена. +$500. Следующая точка: " + DESTINATION_NAMES[mission])
	if wanted > 0:
		crime_clock -= delta
		police_clock -= delta
		if police_clock <= 0:
			police_clock = 2
			_update_police(subject)
		for officer in officers:
			var distance: float = officer.global_position.distance_to(subject)
			if distance < 32: crime_clock = maxf(crime_clock, 8)
			if distance < 8:
				health -= delta * 9
				if health <= 0:
					cash = maxi(0, cash - 250)
					_respawn()
					_message("Задержание. Штраф $250.")
					break
		if crime_clock <= 0:
			wanted = maxi(wanted - 1, 0)
			crime_clock = 20
			if wanted == 0: _clear_police()
	_update_hud(subject)


func _shoot() -> void:
	if shot_clock > 0: return
	shot_clock = 0.3
	player.model.rotation.y = player.pivot.rotation.y
	var camera: Camera3D = player.camera
	var from := camera.global_position
	var to := from - camera.global_basis.z * 200
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		to = hit.position
		if hit.collider.has_method("knock_down"): hit.collider.knock_down()
	var start: Vector3 = player.global_position + Vector3(0, 1.25, 0) - player.pivot.global_basis.z * 0.7
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.025, start.distance_to(to))
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("ffe3a8")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.material_override = material
	add_child(tracer)
	tracer.global_position = (start + to) / 2
	tracer.look_at(to)
	get_tree().create_timer(0.07).timeout.connect(tracer.queue_free)
	_crime(1)


func _crime(level: int) -> void:
	wanted = mini(3, maxi(wanted, level) + (1 if wanted > 0 and crime_clock > 26 else 0))
	crime_clock = 30
	if officers.is_empty():
		var target: Vector3 = driven.global_position if is_instance_valid(driven) else player.global_position
		for offset in [-1, 1]:
			var officer := Actor.new()
			officer.police = true
			officer.tint = Color("354959")
			officer.speed = 13
			officer.position = Vector3(180, 0.2, clampf(target.z + offset * 130, -300, 300))
			officer.process_mode = Node.PROCESS_MODE_PAUSABLE
			add_child(officer)
			officers.append(officer)
		_update_police(target)
	_message("Розыск. Уйди от полиции, чтобы сбросить звёзды.")


func _update_police(target: Vector3) -> void:
	for officer in officers:
		officer.speed = 11 + wanted * 2
		var route: PackedVector3Array = city.route_between(officer.global_position, target)
		if officer.global_position.distance_to(target) < 45:
			route = PackedVector3Array([target])
		else:
			route.append(target)
		officer.route = route
		officer.target_index = 1 if route.size() > 1 else 0


func _clear_police() -> void:
	for officer in officers: officer.queue_free()
	officers.clear()


func _respawn() -> void:
	if is_instance_valid(driven):
		driven.global_transform = Transform3D(Basis.IDENTITY, Vector3(184, 0.7, 32))
		driven.linear_velocity = Vector3.ZERO
		driven.angular_velocity = Vector3.ZERO
		driven.constant_force = Vector3.ZERO
		driven.reset_physics_interpolation()
		driven.get_node("CameraBase/Camera3D").update_camera()
	else:
		player.global_position = SPAWN
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		var car := cars[0]
		car.global_transform = Transform3D(Basis.IDENTITY, Vector3(184, 0.7, 32))
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		car.reset_physics_interpolation()
	health = 100
	wanted = 0
	_clear_police()


func _message(text: String) -> void:
	notice = text
	notice_clock = 6


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	_hud_panel(canvas, Rect2(20, 16, 280, 78))
	_hud_panel(canvas, Rect2(1025, 16, 205, 95))
	_hud_panel(canvas, Rect2(244, 564, 770, 106))
	_hud_panel(canvas, Rect2(1025, 642, 205, 58))
	var title := _label(canvas, "COASTLINE / 67", Vector2(28, 22), 27, Color("f6e4ce"))
	title.add_theme_constant_override("outline_size", 1)
	_label(canvas, "v0.0.1   /   SUNSET COUNTY", Vector2(30, 57), 13, Color("dfb7bd"))
	cash_label = _label(canvas, "$500", Vector2(1040, 24), 28, Color("a4d3b2"))
	wanted_label = _label(canvas, "☆☆☆", Vector2(1050, 62), 30, Color("e9c5a1"))
	mission_label = _label(canvas, "", Vector2(252, 605), 22, Color("efb5d2"))
	notice_label = _label(canvas, "", Vector2(252, 570), 16, Color("fff0d9"))
	hint_label = _label(canvas, "", Vector2(252, 647), 15, Color("e5e2d7"))
	speed_label = _label(canvas, "", Vector2(1040, 650), 23, Color("fff0d9"))
	_label(canvas, "+", Vector2(634, 346), 20, Color(1, 1, 1, 0.65))
	radar = Radar.new()
	radar.position = Vector2(28, 460)
	radar.size = Vector2(200, 200)
	radar.clip_contents = true
	canvas.add_child(radar)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(28, 666)
	health_bar.size = Vector2(200, 8)
	health_bar.show_percentage = false
	_bar_colors(health_bar, Color("85bca1"))
	canvas.add_child(health_bar)
	turbo_bar = ProgressBar.new()
	turbo_bar.position = Vector2(1040, 684)
	turbo_bar.size = Vector2(180, 6)
	turbo_bar.max_value = 10
	turbo_bar.value = 10
	turbo_bar.show_percentage = false
	_bar_colors(turbo_bar, Color("e8b0cb"))
	canvas.add_child(turbo_bar)
	turbo_animator = AnimationPlayer.new()
	var library := AnimationLibrary.new()
	library.add_animation("Idle", Animation.new())
	library.add_animation("TURBO", Animation.new())
	turbo_animator.add_animation_library("", library)
	add_child(turbo_animator)
	pause_panel = Panel.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.08, 0.12, 0.94)
	pause_panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(pause_panel)
	_label(pause_panel, "COASTLINE / 67", Vector2(420, 150), 40, Color("f0c1cb"))
	_label(pause_panel, "WASD — движение     Мышь — обзор\nE — сесть / выйти     Shift — бег / ускорение\nSpace — прыжок / тормоз     ЛКМ — выстрел\nC — камера в машине     H — сигнал     L — фары\nR — вернуть персонажа или машину     Esc — пауза\n\nЗадание: сядь в машину и доедь до розового маркера.\nЗа доставку: $500. При розыске уходи от полиции.", Vector2(350, 235), 20, Color("e4ded2"))
	var resume := Button.new()
	resume.text = "ПРОДОЛЖИТЬ"
	resume.position = Vector2(520, 525)
	resume.size = Vector2(240, 50)
	resume.pressed.connect(_toggle_pause)
	pause_panel.add_child(resume)
	pause_panel.hide()


func _hud_panel(parent: Node, rect: Rect2) -> void:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = Color(0.035, 0.07, 0.09, 0.62)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)


func _bar_colors(bar: ProgressBar, tint: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("293c45")
	var fill := StyleBoxFlat.new()
	fill.bg_color = tint
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)


func _label(parent: Node, caption: String, p: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.text = caption
	label.position = p
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.1, 0.8))
	label.add_theme_constant_override("outline_size", 1)
	parent.add_child(label)
	return label


func _update_hud(subject: Vector3) -> void:
	cash_label.text = "$%d" % cash
	wanted_label.text = "★".repeat(wanted) + "☆".repeat(3 - wanted)
	mission_label.text = "ДОСТАВКА / %s   ·   %d м   ·   $500" % [DESTINATION_NAMES[mission], int(subject.distance_to(DESTINATIONS[mission]))]
	notice_label.text = notice if notice_clock > 0 else ""
	if is_instance_valid(driven):
		hint_label.text = "E — выйти   ·   WASD — ехать   ·   Space — тормоз   ·   C — камера"
		speed_label.text = "%03d км/ч" % int(driven.linear_velocity.length() * 3.6)
	else:
		var nearest := _nearest_car()
		hint_label.text = "E — сесть в " + str(nearest.display_name) if nearest != null else "WASD — идти   ·   Shift — бег   ·   E — сесть в машину   ·   Esc — управление"
		speed_label.text = "ПЕШКОМ"
	health_bar.value = health
	turbo_bar.visible = is_instance_valid(driven)
	radar.subject = subject
	radar.heading = -driven.rotation.y + PI if is_instance_valid(driven) else -player.pivot.rotation.y
	radar.destination = DESTINATIONS[mission]
	radar.police_positions.clear()
	for officer in officers: radar.police_positions.append(officer.global_position)
	radar.queue_redraw()


func _toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	pause_panel.visible = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
