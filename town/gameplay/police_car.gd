extends "res://town/traffic/traffic_driver.gd"

static var siren_stream: AudioStreamWAV
const SIREN_RATE := 16000
const SIREN_DURATION := 2.4
const SIREN_GAIN := 0.056234
var controller: Node3D
var route: Array[Vector3i] = []
var beacon_materials: Array[StandardMaterial3D] = []
var beacon_lights: Array[OmniLight3D] = []
var siren: AudioStreamPlayer3D
var audible := false
var near_player := false
var pursuit_enabled := true
var age := 0.0
var blocked_time := 0.0
var _siren_gain := 0.0
var _beacon_phase := -1
var _beacon_near := false
var _beacon_enabled := false
var _brake_energy := -1.0
var _pursuit_sensor_tick := 0.0
var _pursuit_obstacle_speed := INF
var _pursuit_rays: Array[PhysicsRayQueryParameters3D] = []


func _ready() -> void:
	super._ready()
	add_to_group("police")
	cruise_speed = 13.5
	for index in 3:
		_pursuit_rays.append(PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1 | 2 | 4 | 8, [get_rid()]))
	for side in [-1, 1]:
		var lamp := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.36, 0.08, 0.18)
		lamp.mesh = mesh
		lamp.position = Vector3(side * 0.23, body_bounds.end.y + 0.035, -0.05)
		lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("e83c4b") if side < 0 else Color("328cfa")
		material.emission_enabled = true
		material.emission = material.albedo_color
		lamp.material_override = material
		add_child(lamp)
		beacon_materials.append(material)
		var light := OmniLight3D.new()
		light.position = lamp.position
		light.light_color = material.albedo_color
		light.omni_range = 6
		light.omni_attenuation = 2
		light.shadow_enabled = false
		light.light_energy = 0.0
		add_child(light)
		beacon_lights.append(light)
	prepare_audio()
	siren = AudioStreamPlayer3D.new()
	siren.stream = siren_stream
	siren.volume_linear = 0.0
	siren.unit_size = 8
	siren.max_distance = 75
	siren.bus = "Ambient" if AudioServer.get_bus_index("Ambient") >= 0 else "Master"
	add_child(siren)


func set_route(points: Array[Vector3i]) -> void:
	route = points.duplicate()
	while not route.is_empty() and world.lane_position(route[0]).distance_to(global_position) < 0.6:
		state = route.pop_front()
	next_state = route[0] if not route.is_empty() else state
	_pursuit_sensor_tick = 0.0


func _physics_process(delta: float) -> void:
	age += delta
	var target: Vector3 = world.lane_position(next_state)
	var offset := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	while not route.is_empty() and offset.length() < 0.55:
		state = route.pop_front()
		next_state = route[0] if not route.is_empty() else state
		target = world.lane_position(next_state)
		offset = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var direction := offset.normalized()
	var desired := cruise_speed if not route.is_empty() and pursuit_enabled else 0.0
	if next_state.z != state.z: desired = minf(desired, 4.5)
	# An emergency response can cross a red light, but never drives through traffic or people.
	_pursuit_sensor_tick -= delta
	if _pursuit_sensor_tick <= 0.0:
		_pursuit_sensor_tick = 0.05
		_pursuit_obstacle_speed = _obstacle_speed(direction, maxf(9.0, speed * 2.1))
	desired = minf(desired, _pursuit_obstacle_speed)
	if damage > 70: desired = 0
	var braking := desired < speed - 0.3
	speed = move_toward(speed, desired, delta * (7.5 if braking else 3.0))
	if direction.length_squared() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 6, 1))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor(): velocity.y -= 20 * delta
	else: velocity.y = 0
	move_and_slide()
	speed = Vector2(velocity.x, velocity.z).length()
	blocked_time = blocked_time + delta if speed < 0.2 and not route.is_empty() else 0.0
	wheel_distance += velocity.dot(global_basis.z) * delta
	var steering := clampf(angle_difference(rotation.y, atan2(direction.x, direction.z)), -0.5, 0.5)
	for wheel in wheel_visuals:
		wheel.pivot.basis = Basis(Vector3.UP, steering if wheel.front else 0.0) * Basis(Vector3.RIGHT, fmod(wheel_distance / wheel.radius, TAU))
	light_tick -= delta
	if light_tick <= 0:
		light_tick = 0.5
		_update_night_lights()
	var brake_energy := 2.5 if braking or desired < 0.1 else (0.65 if lights_at_night else 0.0)
	if brake_energy != _brake_energy:
		_brake_energy = brake_energy
		for lamp in brake_lights: lamp.material_override.emission_energy_multiplier = brake_energy
	var beacon_phase := posmod(int(age * 7), 4)
	var beacon_enabled := pursuit_enabled and damage <= 70
	if beacon_phase != _beacon_phase or near_player != _beacon_near or beacon_enabled != _beacon_enabled:
		_beacon_phase = beacon_phase
		_beacon_near = near_player
		_beacon_enabled = beacon_enabled
		for index in beacon_materials.size():
			var flash := beacon_enabled and beacon_phase == index * 2
			beacon_materials[index].emission_energy_multiplier = 3.5 if flash else 0.05
			beacon_lights[index].light_energy = 0.9 if flash and near_player else 0.0
	var should_sound := audible and pursuit_enabled and damage <= 70
	if should_sound and not siren.playing:
		# A replacement voice joins the current wail instead of restarting it.
		siren.play(fposmod(Time.get_ticks_msec() * 0.001, SIREN_DURATION))
	if should_sound or _siren_gain > 0.0:
		_siren_gain = move_toward(_siren_gain, 1.0 if should_sound else 0.0, delta * 4.0)
		siren.volume_linear = SIREN_GAIN * _siren_gain
	if not should_sound and _siren_gain == 0.0 and siren.playing: siren.stop()


func _obstacle_speed(direction: Vector3, lookahead: float) -> float:
	if direction.length_squared() < 0.01: return 0.0
	var allowed := INF
	for other in world.nearby_drivers(global_position, lookahead + 3.0):
		if other == self or not is_instance_valid(other): continue
		var relative: Vector3 = other.global_position - global_position
		var ahead := relative.dot(direction)
		var lateral := absf(relative.x * direction.z - relative.z * direction.x)
		if ahead > 0 and ahead < lookahead and lateral < 2.0:
			allowed = minf(allowed, maxf(0.0, (ahead - 5.4) / 1.4))
	var space := get_world_3d().direct_space_state
	for index in _pursuit_rays.size():
		var origin: Vector3 = global_position + Vector3.UP + global_basis.x * ((index - 1) * 0.65)
		var ray := _pursuit_rays[index]
		ray.from = origin
		ray.to = origin + direction * lookahead
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var gap: float = origin.distance_to(hit.position)
			allowed = minf(allowed, maxf(0.0, (gap - 3.2) / 1.4))
	return allowed


static func prepare_audio() -> void:
	if siren_stream == null: siren_stream = _make_siren()


static func _make_siren() -> AudioStreamWAV:
	var pcm := PackedByteArray()
	var count := int(SIREN_RATE * SIREN_DURATION)
	pcm.resize(count * 2)
	var phase := 0.0
	# A restrained two-tone wail. An exact whole-period loop avoids buffer-edge clicks.
	for index in count:
		var t := float(index) / SIREN_RATE
		var frequency := 720.0 + sin(TAU * t / SIREN_DURATION) * 240.0
		phase += TAU * frequency / SIREN_RATE
		var sample := sin(phase) * 0.75 + sin(phase * 2) * 0.12
		pcm.encode_s16(index * 2, int(sample * 15000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SIREN_RATE
	stream.data = pcm
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	return stream
