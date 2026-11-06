extends Node3D

# Fixed audio pool, shared streams and a single world-space particle emitter.
var engine: AudioStream
var horns: Array[AudioStream] = []
var steps: Array = []
const PROPS = [
	preload("res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Newspaper_01.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_TrashBag_02.tscn")
]
var world: Node3D
var motors: Array[AudioStreamPlayer3D] = []
var motor_cars: Array[RigidBody3D] = []
var footsteps: AudioStreamPlayer3D
var foot_wait := 0.0
var horn: AudioStreamPlayer3D
var speech: AudioStreamPlayer3D
var paper := CPUParticles3D.new()
var lines: Array[AudioStream] = []
var timer := 0.0
var horn_wait := 4.0
var chat_wait := 2.0
var reply_from: Node3D
var reply_line := 0
var last_pair := -1

func _ready() -> void:
	world = get_parent()
	if world.positional_audio:
		engine = load("res://vehicles/engine.wav")
		for path in ["res://vehicles/honk_1.wav","res://vehicles/honk_3.wav"]:
			horns.append(load(path))
		steps = load("res://town/player/city_audio.gd").STEPS
		for i in 3:
			var motor := _voice(52, -12)
			motor.stream = engine
			motors.append(motor)
			motor_cars.append(null)
		horn = _voice(48, -9)
		speech = _voice(23, -3)
		footsteps = _voice(8, -9)
		for i in 6:
			lines.append(load("res://town/sound/street_line_%d.wav" % i))
	_make_paper()
	var cells: Array = world.walk_neighbors.keys()
	cells.shuffle()
	for i in mini(24, cells.size()):
		var prop: MeshInstance3D = PROPS[int(i % 4 == 0)].instantiate()
		# Decorative props use only their visual geometry.
		for child in prop.get_children(): child.free()
		prop.position = world.walk_position(cells[i]) + Vector3.UP * 0.025
		prop.rotation.y = randf() * TAU
		prop.visibility_range_end = 42
		prop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(prop)

func _voice(radius: float, gain: float) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.max_distance = radius
	voice.unit_size = 8
	voice.bus = &"Ambient"
	voice.volume_db = gain
	add_child(voice)
	return voice

func _make_paper() -> void:
	paper.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	paper.emission_box_extents = Vector3(12, 0.6, 12)
	paper.direction = Vector3(1, 0.15, 0.3)
	paper.spread = 24
	paper.initial_velocity_min = 0.6
	paper.initial_velocity_max = 1.8
	paper.gravity = Vector3(0, -0.09, 0)
	paper.angular_velocity_min = -130
	paper.angular_velocity_max = 130
	paper.particle_flag_rotate_y = true
	var sheet := QuadMesh.new()
	sheet.size = Vector2(0.12, 0.075)
	var tint := StandardMaterial3D.new()
	tint.albedo_color = Color("ac966c")
	tint.cull_mode = BaseMaterial3D.CULL_DISABLED
	sheet.material = tint
	paper.mesh = sheet
	paper.amount = 32
	paper.fixed_fps = 20
	paper.lifetime = 4
	paper.local_coords = false
	paper.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(paper)

func _process(delta: float) -> void:
	timer -= delta
	horn_wait -= delta
	chat_wait -= delta
	foot_wait -= delta
	if timer > 0 or not is_instance_valid(world.subject): return
	timer = 0.25
	var origin: Vector3 = world.subject.global_position
	paper.global_position = origin + Vector3.UP
	var budget: int = [8, 20, 32][CityPerformance.quality]
	if paper.amount != budget:
		paper.amount = budget
		paper.fixed_fps = 12 if CityPerformance.quality == 0 else 20
	if not world.positional_audio:
		if chat_wait <= 0: _conversation(origin)
		return
	var nearby: Array = world.nearby_drivers(origin, 52.0)
	nearby.sort_custom(func(a, b): return a.global_position.distance_squared_to(origin) < b.global_position.distance_squared_to(origin))
	var selected := nearby.slice(0, motors.size())
	for i in motors.size():
		if is_instance_valid(motor_cars[i]) and motor_cars[i] in selected: continue
		motor_cars[i] = null
		motors[i].stop()
	for car in selected:
		var i := motor_cars.find(car)
		if i < 0:
			i = motor_cars.find(null)
			motor_cars[i] = car
		var motor := motors[i]
		motor.global_position = car.global_position
		motor.pitch_scale = 0.68 + minf(car.speed, 16) * 0.052
		motor.volume_db = lerpf(-17.0, -7.0, minf(car.speed / 9.0, 1.0))
		if not motor.playing: motor.play(i * 0.11)
		if horn_wait <= 0 and car.blocked_seconds > 1.7 and car.global_position.distance_squared_to(origin) < 38 ** 2:
			horn.global_position = car.global_position
			horn.stream = horns.pick_random()
			horn.pitch_scale = randf_range(0.92, 1.12)
			horn.play()
			horn_wait = randf_range(5, 10)
	if foot_wait <= 0:
		var nearest: CharacterBody3D
		var radius := 8.0 ** 2
		for person in world.citizens:
			var distance: float = person.global_position.distance_squared_to(origin)
			if distance < radius and person.velocity.length_squared() > 0.6 and person.is_on_floor():
				radius = distance
				nearest = person
		if nearest:
			footsteps.global_position = nearest.global_position
			footsteps.stream = steps.pick_random()
			footsteps.pitch_scale = randf_range(0.88, 1.08)
			footsteps.play()
		foot_wait = 0.42
	if chat_wait <= 0 and not speech.playing: _conversation(origin)


func _conversation(origin: Vector3) -> void:
	if is_instance_valid(reply_from):
		if reply_from.chat_time > 0 and origin.distance_squared_to(reply_from.global_position) < 23 ** 2:
			_speak(reply_from, reply_line)
		reply_from = null
		chat_wait = randf_range(3.5,7.0)
		return
	chat_wait = 2
	var listeners: Array[CharacterBody3D] = []
	for person in world.citizens:
		if origin.distance_squared_to(person.global_position) > 21 ** 2 or not person.can_chat(): continue
		for first in listeners:
			var separation := first.global_position.distance_squared_to(person.global_position)
			if separation < 1 or separation > 4.8 ** 2: continue
			var ray := PhysicsRayQueryParameters3D.create(first.global_position + Vector3.UP, person.global_position + Vector3.UP, 1 | 4)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
			if not world.positional_audio:
				first.greet(person,3.8)
				person.greet(first,3.8)
				chat_wait = 7.0
				return
			last_pair = (last_pair + randi_range(1, 2)) % 3
			reply_line = last_pair * 2 + 1
			var duration := lines[reply_line - 1].get_length() + lines[reply_line].get_length() + 1.1
			first.greet(person, duration)
			person.greet(first, duration)
			_speak(first, reply_line - 1)
			reply_from = person
			chat_wait = lines[reply_line - 1].get_length() + 0.35
			return
		listeners.append(person)


func _speak(person: Node3D, line: int) -> void:
	speech.global_position = person.global_position + Vector3.UP * 1.5
	speech.stream = lines[line]
	speech.play()
