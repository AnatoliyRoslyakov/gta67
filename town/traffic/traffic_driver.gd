extends RigidBody3D

static var lamp_mesh_cache: Dictionary = {}
var grounded := false
var grip_recovery := 0.0
var _plan_target := Vector3.ZERO
var _plan_speed := 0.0
var _plan_turn := false
var body_faces := PackedVector3Array()
var body_bounds := AABB()

var world: Node3D
var state := Vector3i.ZERO
var next_state := Vector3i.ZERO
var model_scene: PackedScene
var paint_tint := Color.WHITE
var cruise_speed := 8.5
var following_state := Vector3i.ZERO
var steering_angle := 0.0
var wheelbase := 2.7
var acceleration := 2.0
var following_time := 1.6
var _turn_points := PackedVector3Array()
var _turn_key := Vector3i(2147483647, 0, 0)
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
var _fixed_obstruction := false
var blocked_seconds := 0.0
var queue_release_delay := 0.0
var _traffic_sensor_tick := 0.0
var _traffic_obstacle_speed := INF
var _traffic_ray: PhysicsRayQueryParameters3D
var _side_rays: Array[PhysicsRayQueryParameters3D] = []
var _traffic_visual_elapsed := 0.0
var _traffic_visual_interval := 1.0 / 30.0
var _traffic_brake_energy := -1.0
var _traffic_turn_state := -1
var _traffic_night_initialized := false


func _ready() -> void:
	mass = 2000 if "Van" in model_scene.resource_path else (1050 if "Small" in model_scene.resource_path else 1450)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.UP * 0.42
	continuous_cd = true
	max_contacts_reported = 8
	physics_material_override = PhysicsMaterial.new()
	physics_material_override.friction = 0.055
	linear_damp = 0.04
	angular_damp = 0.35
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	add_to_group("traffic")
	_traffic_ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1 | 2 | 4 | 8, [get_rid()])
	for side in 2:
		_side_rays.append(PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1 | 2 | 4 | 8, [get_rid()]))
	_traffic_sensor_tick = -float(get_instance_id() % 6) / 120.0
	_traffic_visual_elapsed = float(get_instance_id() % 4) / 120.0
	model = model_scene.instantiate()
	_remove_physics(model)
	add_child(model)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	var model_bounds: AABB = model.transform * (model as MeshInstance3D).get_aabb()
	shape.size = Vector3(model_bounds.size.x * 0.87, model_bounds.size.y * 0.75, model_bounds.size.z * 0.94)
	collider.position.x = model_bounds.get_center().x
	collider.position.z = model_bounds.get_center().z
	wheelbase = float(model.get_meta("wheelbase", clampf(model_bounds.size.z * 0.57, 2.0, 3.1)))
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
	# Put the hull underside at tire height so the visual wheels meet the street.
	collider.position.y = (tire_floor if is_finite(tire_floor) else 0.0) + shape.size.y * 0.5
	next_state = world.choose_lane(state)
	following_state = world.choose_lane(next_state)
	var direction: Vector3 = world.lane_position(next_state) - position
	rotation.y = atan2(direction.x, direction.z)
	var body_mesh := model as MeshInstance3D
	body_bounds = model.transform * body_mesh.get_aabb()
	for surface in body_mesh.mesh.get_surface_count():
		var source := body_mesh.get_active_material(surface) as StandardMaterial3D
		if source != null and paint_tint != Color.WHITE:
			var finish := source.duplicate() as StandardMaterial3D
			finish.albedo_color *= paint_tint
			finish.metallic = 0.15
			finish.roughness = 0.4
			body_mesh.set_surface_override_material(surface, finish)
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
	lamp_height = float(model.get_meta("headlight_height", lamp_height))
	tail_height = float(model.get_meta("tail_light_height", tail_height))
	for side in [-1, 1]:
		var x: float = body_bounds.get_center().x + side * float(model.get_meta("headlight_half_width", body_bounds.size.x * 0.27))
		var tail_x: float = body_bounds.get_center().x + side * float(model.get_meta("tail_light_half_width", body_bounds.size.x * tail_width_fraction))
		brake_lights.append(_lamp(Vector2(tail_x, tail_height), false, Color("b81e24")))
		headlights.append(_lamp(Vector2(x, lamp_height), true, Color("fff0ce")))
		var turn_x: float = body_bounds.get_center().x + side * float(model.get_meta("turn_light_half_width", body_bounds.size.x * 0.34))
		turn_lights.append(_lamp(Vector2(turn_x, float(model.get_meta("turn_light_height", lamp_height))), true, Color("e99a31"), Vector2(0.095, 0.07)))
	body_faces.clear()
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
	if _reached_lane(following_state):
		state = next_state
		next_state = following_state
		following_state = world.choose_lane(next_state)
		_traffic_sensor_tick = 0.0
	_traffic_sensor_tick -= delta
	if _traffic_sensor_tick <= 0.0:
		_traffic_sensor_tick += 0.05
		var target := _driving_target(following_state)
		var direction := (target - global_position).normalized()
		var desired := cruise_speed
		if following_state == next_state:
			desired = minf(desired, sqrt(maxf(0, 6.0 * (global_position.distance_to(world.lane_position(next_state)) - 1.0))))
		if state == next_state: desired = 0.0
		var turning := _is_turn(following_state)
		if turning:
			var approach_distance := maxf(0.0, global_position.distance_to(world.lane_position(next_state)) - 4.5)
			desired = minf(desired, sqrt(9.0 + 4.5 * approach_distance))
		desired = minf(desired, world.approach_speed(self, state, next_state))
		_traffic_obstacle_speed = _sense_obstacles(direction, maxf(9, speed * 2.2))
		_plan_speed = desired
		_plan_target = target
		_plan_turn = turning
	var desired := _plan_speed
	var turning := _plan_turn
	if desired > 1.5 and _traffic_obstacle_speed < 0.6 and speed < 0.8 and damage < 70:
		blocked_seconds += delta
		if blocked_seconds > 4.5 and _fixed_obstruction:
			_try_open_branch()
			blocked_seconds = 0.0
	else:
		blocked_seconds = 0.0
	desired = minf(desired, _traffic_obstacle_speed)
	if desired < 0.3 and speed < 0.4:
		queue_release_delay = 0.2 + 0.3 * following_time
	elif queue_release_delay > 0.0:
		queue_release_delay -= delta
		desired = 0.0
	if damage > 70: desired = 0
	var braking := _drive_toward(_plan_target, desired, delta)
	_traffic_visual_elapsed += delta
	if _traffic_visual_elapsed + 0.000001 >= _traffic_visual_interval:
		_traffic_visual_elapsed = fmod(_traffic_visual_elapsed, _traffic_visual_interval)
		for wheel in wheel_visuals:
			wheel.pivot.basis = Basis(Vector3.UP, steering_angle if wheel.front else 0.0) * Basis(Vector3.RIGHT, fmod(wheel_distance / wheel.radius, TAU))
	light_tick -= delta
	if light_tick <= 0:
		light_tick += 0.5
		_update_night_lights()
	var brake_energy := 2.5 if braking or desired < 0.1 else (0.65 if lights_at_night else 0.0)
	if brake_energy != _traffic_brake_energy:
		_traffic_brake_energy = brake_energy
		for lamp in brake_lights:
			(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = brake_energy
	var turn_direction := posmod(following_state.z - next_state.z, 4) if turning else posmod(next_state.z - state.z, 4)
	var turn_state := turn_direction if (turn_direction == 1 or turn_direction == 3) and fmod(world.elapsed, 0.8) < 0.4 else 0
	if turn_state != _traffic_turn_state:
		_traffic_turn_state = turn_state
		for i in turn_lights.size():
			var lit := (turn_state == 1 and i == 1) or (turn_state == 3 and i == 0)
			(turn_lights[i].material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 if lit else 0.0


func _is_turn(following: Vector3i) -> bool:
	var incoming: Vector3 = world.lane_position(next_state) - world.lane_position(state)
	var outgoing: Vector3 = world.lane_position(following) - world.lane_position(next_state)
	return incoming.length_squared() > 0.1 and outgoing.length_squared() > 0.1 and incoming.normalized().dot(outgoing.normalized()) < 0.5


func _reached_lane(following: Vector3i) -> bool:
	var corner: Vector3 = world.lane_position(next_state)
	var offset := global_position - corner
	offset.y = 0
	if not _is_turn(following):
		var incoming: Vector3 = (corner - world.lane_position(state)).normalized()
		return offset.length() < 0.8 or offset.dot(incoming) > 0.0
	var outgoing: Vector3 = (world.lane_position(following) - corner).normalized()
	return offset.dot(outgoing) > 1.5 and global_basis.z.dot(outgoing) > 0.8


func _driving_target(following: Vector3i) -> Vector3:
	var corner: Vector3 = world.lane_position(next_state)
	if not _is_turn(following): return corner
	if _turn_key != next_state or _turn_points.is_empty():
		_turn_key = next_state
		_turn_points.clear()
		var incoming: Vector3 = (corner - world.lane_position(state)).normalized()
		var outgoing: Vector3 = (world.lane_position(following) - corner).normalized()
		var entry := corner - incoming * 2.2
		var exit := corner + outgoing * 2.2
		for i in 17:
			var t := float(i) / 16.0
			_turn_points.append(entry.lerp(corner, t).lerp(corner.lerp(exit, t), t))
	var nearest := 0
	var distance := INF
	for i in _turn_points.size():
		var candidate := global_position.distance_squared_to(_turn_points[i])
		if candidate < distance:
			distance = candidate
			nearest = i
	# Aim along the fillet, rather than at the square grid corner.
	if nearest == 0 and distance > 1.8 * 1.8: return _turn_points[0]
	if nearest >= 14:
		var outgoing: Vector3 = (world.lane_position(following) - corner).normalized()
		return _turn_points[-1] + outgoing * 2.0
	return _turn_points[mini(nearest + 5, _turn_points.size() - 1)]


func _drive_toward(target: Vector3, desired: float, delta: float) -> bool:
	var offset := target - global_position
	offset.y = 0
	var error := angle_difference(rotation.y, atan2(offset.x, offset.z))
	var requested := clampf(atan2(2.0 * wheelbase * sin(error), maxf(offset.length(), 1.0)), -1.2, 1.2)
	if absf(error) > PI * 0.7: requested = signf(error) * 1.05
	steering_angle = move_toward(steering_angle, requested, delta * 1.8)
	# Bicycle steering: the velocity and body share a heading, including in turns.
	var curvature := absf(tan(steering_angle) / wheelbase)
	desired = minf(desired, sqrt(2.8 / maxf(curvature, 0.01)))
	if absf(error) > PI * 0.55: desired = minf(desired, 1.2)
	var forward := global_basis.z.slide(Vector3.UP).normalized()
	var right := forward.cross(Vector3.DOWN)
	var signed_speed := linear_velocity.dot(forward)
	speed = maxf(0.0, signed_speed)
	var braking := desired < speed - 0.3
	grip_recovery = maxf(0.0, grip_recovery - delta)
	if grounded and global_basis.y.y > 0.45:
		# Tire forces are bounded. The collision solver owns velocity and momentum.
		var grip := 0.22 if grip_recovery > 0.0 else 1.0
		var drive := clampf((desired - signed_speed) * 2.0, -6.8, acceleration)
		var side := clampf(-linear_velocity.dot(right) * 4.0, -5.2, 5.2)
		if absf(drive) + absf(side) > 0.04:
			apply_central_force((forward * drive + right * side) * mass * grip)
		var target_yaw := signed_speed / wheelbase * tan(steering_angle)
		var yaw_accel := clampf((target_yaw - angular_velocity.y) * 5.0, -2.4, 2.4)
		if absf(yaw_accel) > 0.015:
			apply_torque(Vector3.UP * yaw_accel * mass * (body_bounds.size.z ** 2 + body_bounds.size.x ** 2) / 12.0 * grip)
	wheel_distance += signed_speed * delta
	return braking


func _integrate_forces(physics: PhysicsDirectBodyState3D) -> void:
	grounded = false
	for i in physics.get_contact_count():
		var normal := physics.get_contact_local_normal(i)
		if normal.y > 0.55:
			grounded = true
		elif absf(normal.y) < 0.5:
			var impulse := physics.get_contact_impulse(i).length() / mass
			var fresh_impact := grip_recovery <= 0.0
			if impulse > 0.8: grip_recovery = 0.65
			var other := physics.get_contact_collider_object(i)
			if other is CharacterBody3D and other.has_method("receive_hit") and speed > 3.0 and fresh_impact:
				other.call_deferred("receive_hit", (speed - 2.0) * 4.0, -normal)
				grip_recovery = 0.65


func _try_open_branch() -> void:
	if global_position.distance_squared_to(world.lane_position(state)) > 3.5 ** 2: return
	for branch: Vector3i in world.lanes.get(state, []):
		if branch == next_state: continue
		var toward: Vector3 = world.lane_position(branch) - global_position
		if toward.dot(global_basis.z) < -1.0: continue
		if _sense_obstacles(toward.normalized(), 7.0) < 2.0: continue
		if not world.may_enter(self, state, branch): continue
		next_state = branch
		following_state = world.choose_lane(next_state)
		_traffic_sensor_tick = 0.0
		_turn_points.clear()
		return


func _sense_obstacles(direction: Vector3, lookahead: float) -> float:
	var limit := INF
	_fixed_obstruction = false
	var origin := global_position
	# Braking gaps include travel between sensor samples; collision movement still runs at every physics tick.
	var reaction_margin := maxf(speed, cruise_speed) * 0.05
	for other in world.nearby_drivers(origin, lookahead + 3.0):
		if other == self: continue
		var relative: Vector3 = other.global_position - origin
		var ahead := relative.dot(direction)
		var lateral := absf(relative.x * direction.z - relative.z * direction.x)
		var lead_speed := maxf(0.0, other.linear_velocity.dot(direction))
		if ahead > 0 and ahead < lookahead and lateral < 2.1:
			var gap: float = ahead - 0.5 * (body_bounds.size.z + other.body_bounds.size.z)
			var desired_gap := 2.0 + speed * following_time + reaction_margin
			limit = minf(limit, maxf(0, lead_speed + (gap - desired_gap) / following_time))
	for i in 3:
		var ray := _traffic_ray if i == 1 else _side_rays[0 if i == 0 else 1]
		ray.from = origin + Vector3.UP + global_basis.x * ((i - 1) * body_bounds.size.x * 0.35)
		ray.to = ray.from + direction * lookahead
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			var gap: float = ray.from.distance_to(hit.position)
			var obstacle := hit.collider as RigidBody3D
			if gap < body_bounds.size.z * 0.5 + 3.0 and (hit.collider is StaticBody3D or hit.collider.is_in_group("parked_vehicles")):
				_fixed_obstruction = true
			var moving_speed := maxf(0.0, obstacle.linear_velocity.dot(direction)) if obstacle else 0.0
			var room := maxf(0.0, gap - body_bounds.size.z * 0.5 - 1.6 - reaction_margin)
			limit = minf(limit, sqrt(moving_speed * moving_speed + 7.0 * room))
	return limit


func _update_night_lights() -> void:
	var atmosphere: Node = world.get_parent().get("atmosphere") if world.get_parent() else null
	var night: bool = is_instance_valid(atmosphere) and atmosphere.has_method("is_night") and atmosphere.is_night()
	if not _traffic_night_initialized or night != lights_at_night:
		_traffic_night_initialized = true
		lights_at_night = night
		for lamp in headlights:
			(lamp.material_override as StandardMaterial3D).emission_energy_multiplier = 2.0 if lights_at_night else 0.0
	_traffic_visual_interval = 1.0 / 60.0 if is_instance_valid(world.subject) and global_position.distance_squared_to(world.subject.global_position) < 625.0 else 1.0 / 30.0
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
	for other in world.nearby_drivers(subject.global_position, 30.0):
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
		if body_faces.is_empty():
			body_faces = (model as MeshInstance3D).mesh.get_faces()
			for i in body_faces.size(): body_faces[i] = model.transform * body_faces[i]
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
