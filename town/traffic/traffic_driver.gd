extends CharacterBody3D

static var lamp_mesh_cache: Dictionary = {}
var body_faces := PackedVector3Array()
var body_bounds := AABB()

var world: Node3D
var state := Vector3i.ZERO
var next_state := Vector3i.ZERO
var model_scene: PackedScene
var cruise_speed := 8.5
var speed := 0.0
var model: Node3D
var wheel_visuals: Array[Dictionary] = []
var headlights: Array[MeshInstance3D] = []
var headlight_beam: SpotLight3D
var lights_at_night := false
var light_tick := 0.0
var brake_lights: Array[MeshInstance3D] = []
var turn_lights: Array[MeshInstance3D] = []
var damage := 0.0
var wheel_distance := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	add_to_group("traffic")
	model = model_scene.instantiate()
	_remove_physics(model)
	add_child(model)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.75, 1.05, 4.3)
	collider.shape = shape
	add_child(collider)
	var tire_floor := INF
	for part in model.find_children("*Wheel_*", "MeshInstance3D", true, false):
		if str(part.name).ends_with("_fl") or str(part.name).ends_with("_fr") or str(part.name).ends_with("_rl") or str(part.name).ends_with("_rr"):
			# Imported wheel pivots sit on the tire's inner face. Spin a new
			# centred pivot, retaining the complete original mesh transform.
			var original: Transform3D = global_transform.affine_inverse() * part.global_transform
			var bounds: AABB = original * part.get_aabb()
			var center: Vector3 = original * part.get_aabb().get_center()
			var radius := maxf(bounds.size.y, bounds.size.z) * 0.5
			tire_floor = minf(tire_floor, center.y - radius)
			var front := str(part.name).ends_with("_fl") or str(part.name).ends_with("_fr")
			var pivot := Node3D.new()
			pivot.position = center
			add_child(pivot)
			part.reparent(pivot, false)
			part.transform = Transform3D(original.basis, original.origin - center)
			wheel_visuals.append({"pivot": pivot, "mesh": part, "radius": radius, "front": front})
	# The original collider bottom was 0.325 m above the tire bottoms,
	# making CharacterBody3D settle the visible wheels beneath the road.
	collider.position.y = (tire_floor if is_finite(tire_floor) else 0.0) + shape.size.y * 0.5
	next_state = world.choose_lane(state)
	var direction: Vector3 = world.lane_position(next_state) - position
	rotation.y = atan2(direction.x, direction.z)
	var body_mesh := model as MeshInstance3D
	body_bounds = model.transform * body_mesh.get_aabb()
	body_faces = body_mesh.mesh.get_faces()
	for index in body_faces.size(): body_faces[index] = model.transform * body_faces[index]
	var lamp_height := 0.72
	var tail_height := 0.83
	var tail_width_fraction := 0.27
	var path := model_scene.resource_path
	if "Small" in path:
		lamp_height = 0.68
		tail_height = 0.80
	elif "Medium" in path:
		lamp_height = 0.84
		tail_height = 0.92
	elif "Van" in path:
		lamp_height = 0.95
		tail_height = 0.95
		tail_width_fraction = 0.37
	elif "Muscle" in path:
		lamp_height = 0.68
		tail_height = 0.75
	for side in [-1, 1]:
		var x: float = body_bounds.get_center().x + side * body_bounds.size.x * 0.27
		var tail_x: float = body_bounds.get_center().x + side * body_bounds.size.x * tail_width_fraction
		brake_lights.append(_lamp(Vector2(tail_x, tail_height), false, Color("b81e24")))
		headlights.append(_lamp(Vector2(x, lamp_height), true, Color("fff0ce")))
		var turn_x: float = body_bounds.get_center().x + side * body_bounds.size.x * 0.34
		turn_lights.append(_lamp(Vector2(turn_x, lamp_height), true, Color("e99a31"), Vector2(0.095, 0.07)))
	headlight_beam = SpotLight3D.new()
	headlight_beam.position = (headlights[0].get_aabb().get_center() + headlights[1].get_aabb().get_center()) * 0.5 + Vector3(0, 0, 0.08)
	headlight_beam.rotation = Vector3(-0.07, PI, 0)
	headlight_beam.light_color = Color("fff1d4")
	headlight_beam.light_energy = 1.4
	headlight_beam.spot_range = 22
	headlight_beam.spot_angle = 42
	headlight_beam.shadow_enabled = false
	headlight_beam.distance_fade_enabled = true
	headlight_beam.distance_fade_begin = 20
	headlight_beam.distance_fade_length = 10
	headlight_beam.visible = false
	add_child(headlight_beam)
	light_tick = float(get_instance_id() % 17) * 0.03
	_update_night_lights()


func _physics_process(delta: float) -> void:
	var target: Vector3 = world.lane_position(next_state)
	var offset := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if offset.length() < 0.45:
		state = next_state
		next_state = world.choose_lane(state)
		target = world.lane_position(next_state)
		offset = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	var direction := offset.normalized()
	var desired := cruise_speed
	if next_state.z != state.z: desired = minf(desired, 4.0)
	desired = minf(desired, world.approach_speed(self, state, next_state))
	var lookahead := maxf(9, speed * 2.2)
	for other in world.drivers:
		if other == self: continue
		var relative: Vector3 = other.global_position - global_position
		var ahead := relative.dot(direction)
		var lateral := absf(relative.x * direction.z - relative.z * direction.x)
		if ahead > 0 and ahead < lookahead and lateral < 2.1:
			desired = minf(desired, maxf(0, (ahead - 6) / 1.7))
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.UP + direction * lookahead, 1 | 2 | 4 | 8, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var gap: float = global_position.distance_to(hit.position)
		desired = minf(desired, maxf(0, (gap - 3.5) / 1.5))
	if damage > 70: desired = 0
	var braking := desired < speed - 0.5
	speed = move_toward(speed, desired, delta * (6.5 if braking else 2.0))
	if direction.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 5, 1))
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not is_on_floor(): velocity.y -= 20 * delta
	else: velocity.y = 0
	move_and_slide()
	speed = Vector2(velocity.x, velocity.z).length()
	wheel_distance += velocity.dot(global_basis.z) * delta
	var wheel_steer := clampf(angle_difference(rotation.y, atan2(direction.x, direction.z)), -0.5, 0.5)
	for wheel in wheel_visuals:
		var steering_basis := Basis(Vector3.UP, wheel_steer if wheel.front else 0.0)
		wheel.pivot.basis = steering_basis * Basis(Vector3.RIGHT, fmod(wheel_distance / wheel.radius, TAU))
	light_tick -= delta
	if light_tick <= 0:
		light_tick = 0.5
		_update_night_lights()
	for lamp in brake_lights:
		var material := lamp.material_override as StandardMaterial3D
		material.emission_energy_multiplier = 2.5 if braking or desired < 0.1 else (0.65 if lights_at_night else 0.0)
	for i in turn_lights.size():
		var material := turn_lights[i].material_override as StandardMaterial3D
		var turn_direction := posmod(next_state.z - state.z, 4)
		var turning := ((turn_direction == 1 and i == 1) or (turn_direction == 3 and i == 0)) and fmod(world.elapsed, 0.8) < 0.4
		material.emission_energy_multiplier = 2 if turning else 0


func _update_night_lights() -> void:
	var atmosphere: Node = world.get_parent().get("atmosphere") if world.get_parent() else null
	lights_at_night = is_instance_valid(atmosphere) and atmosphere.has_method("is_night") and atmosphere.is_night()
	for lamp in headlights:
		var material := lamp.material_override as StandardMaterial3D
		material.emission_energy_multiplier = 2.0 if lights_at_night else 0.0
	# Emissive lamps remain visible on every car; only four nearest cars
	# illuminate the road, without shadows or per-frame ranking work.
	var subject: Node3D = world.subject
	if not lights_at_night or not is_instance_valid(subject):
		headlight_beam.visible = false
		return
	var distance := global_position.distance_squared_to(subject.global_position)
	if distance > 30.0 * 30.0:
		headlight_beam.visible = false
		return
	var nearer := 0
	for other in world.drivers:
		if other == self or not is_instance_valid(other): continue
		var other_distance: float = other.global_position.distance_squared_to(subject.global_position)
		if other_distance < distance or (is_equal_approx(other_distance, distance) and other.get_instance_id() < get_instance_id()): nearer += 1
		if nearer >= 4: break
	headlight_beam.visible = nearer < 4


func receive_hit(amount: float, _direction: Vector3) -> void:
	damage += amount


func _lamp(center: Vector2, front: bool, color: Color, size: Vector2 = Vector2(0.22, 0.11)) -> MeshInstance3D:
	# Clip the actual body triangles into a lens-shaped patch. Every vertex
	# stays on its original panel: bounding boxes include mirrors and cannot
	# locate the bumper surface, particularly on the rounded compact model.
	var key := "%s:%s:%s:%s" % [model_scene.resource_path, center, front, size]
	if not lamp_mesh_cache.has(key):
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var end_limit := body_bounds.get_center().z + body_bounds.size.z * (0.40 if front else -0.40)
		for index in range(0, body_faces.size(), 3):
			var a := body_faces[index]
			var b := body_faces[index + 1]
			var c := body_faces[index + 2]
			if maxf(a.x, maxf(b.x, c.x)) < center.x - size.x * 0.5: continue
			if minf(a.x, minf(b.x, c.x)) > center.x + size.x * 0.5: continue
			if maxf(a.y, maxf(b.y, c.y)) < center.y - size.y * 0.5: continue
			if minf(a.y, minf(b.y, c.y)) > center.y + size.y * 0.5: continue
			var normal := (c - a).cross(b - a).normalized()
			if normal.z * (1.0 if front else -1.0) < 0.2: continue
			var polygon := PackedVector3Array([a, b, c])
			polygon = _clip_lens(polygon, 2, end_limit, front)
			polygon = _clip_lens(polygon, 0, center.x - size.x * 0.5, true)
			polygon = _clip_lens(polygon, 0, center.x + size.x * 0.5, false)
			polygon = _clip_lens(polygon, 1, center.y - size.y * 0.5, true)
			polygon = _clip_lens(polygon, 1, center.y + size.y * 0.5, false)
			for triangle in range(1, polygon.size() - 1):
				for point in [polygon[0], polygon[triangle], polygon[triangle + 1]]:
					vertices.append(point + normal * 0.002)
					normals.append(normal)
		var mesh := ArrayMesh.new()
		if not vertices.is_empty():
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		lamp_mesh_cache[key] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = lamp_mesh_cache[key]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	material.roughness = 0.3
	instance.material_override = material
	add_child(instance)
	return instance


func _clip_lens(polygon: PackedVector3Array, axis: int, boundary: float, keep_above: bool) -> PackedVector3Array:
	var result := PackedVector3Array()
	if polygon.is_empty(): return result
	var previous := polygon[polygon.size() - 1]
	var previous_inside: bool = previous[axis] >= boundary if keep_above else previous[axis] <= boundary
	for point in polygon:
		var inside: bool = point[axis] >= boundary if keep_above else point[axis] <= boundary
		if inside != previous_inside:
			result.append(previous.lerp(point, (boundary - previous[axis]) / (point[axis] - previous[axis])))
		if inside: result.append(point)
		previous = point
		previous_inside = inside
	return result


func _remove_physics(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D: child.free()
		else: _remove_physics(child)
