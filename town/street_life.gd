extends Node3D

# Fixed audio pool, shared streams and a single world-space particle emitter.
const ENGINE = preload("res://vehicles/engine.wav")
const HORNS = [preload("res://vehicles/honk_1.wav"), preload("res://vehicles/honk_3.wav")]
const PROPS = [
	preload("res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Newspaper_01.tscn"),
	preload("res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_TrashBag_02.tscn")
]
var world: Node3D
var motor: AudioStreamPlayer3D
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
	motor = _voice(30, -18)
	motor.stream = ENGINE
	horn = _voice(32, -13)
	speech = _voice(16, -9)
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
	voice.unit_size = 4
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
	if timer > 0 or not is_instance_valid(world.subject): return
	timer = 0.25
	var origin: Vector3 = world.subject.global_position
	paper.global_position = origin + Vector3.UP
	var budget: int = [8, 20, 32][CityPerformance.quality]
	if paper.amount != budget:
		paper.amount = budget
		paper.fixed_fps = 12 if CityPerformance.quality == 0 else 20
	var closest: RigidBody3D
	var best := 900.0
	for car in world.nearby_drivers(origin, 32.0):
		var d: float = origin.distance_squared_to(car.global_position)
		if d < best and car.speed > 1.0:
			closest = car
			best = d
		if d < 900 and horn_wait <= 0 and car.blocked_seconds > 3.5:
			horn.global_position = car.global_position
			horn.stream = HORNS.pick_random()
			horn.pitch_scale = randf_range(0.93,1.08)
			horn.play()
			horn_wait = randf_range(9,16)
	if closest:
		motor.global_position = closest.global_position
		motor.pitch_scale = 0.74 + minf(closest.speed,16) * 0.045
		if not motor.playing: motor.play()
	elif motor.playing: motor.stop()
	if chat_wait <= 0 and not speech.playing: _conversation(origin)

func _conversation(origin: Vector3) -> void:
	if is_instance_valid(reply_from):
		if origin.distance_squared_to(reply_from.global_position) < 225:
			_speak(reply_from, reply_line)
		reply_from = null
		chat_wait = randf_range(10,20)
		return
	chat_wait = 2
	var first: CharacterBody3D
	for person in world.citizens:
		if origin.distance_squared_to(person.global_position) > 144 or person.velocity.length() > 2.2: continue
		if not first:
			first = person
		elif first.global_position.distance_squared_to(person.global_position) < 25:
			last_pair = (last_pair + randi_range(1,2)) % 3
			_speak(first, last_pair * 2)
			reply_from = person
			reply_line = last_pair * 2 + 1
			chat_wait = lines[last_pair * 2].get_length() + 0.35
			return

func _speak(person: Node3D, line: int) -> void:
	speech.global_position = person.global_position + Vector3.UP * 1.5
	speech.stream = lines[line]
	speech.play()
