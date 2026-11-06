extends CharacterBody3D

const Motion = preload("res://town/player/humanoid_motion.gd")
var world: Node3D
var cell := Vector2i.ZERO
var target_cell := Vector2i.ZERO
var previous_cell := Vector2i.ZERO
var walk_speed := 1.3
var model_scene: PackedScene
var model: Node3D
var motion: RefCounted
var idle_time := 0.0
var crossing_junction := -1:
	set(value):
		if value == crossing_junction: return
		world.crossing_changed(crossing_junction, value)
		crossing_junction = value
var flee_time := 0.0
var fear_origin := Vector3.ZERO
var health := 100.0
var knockdown := 0.0
var blocked_time := 0.0
var walk_steps := 0
var animation_elapsed := 0.0
var animation_interval := 1.0 / 30.0
var animation_lod_timer := 0.0
var _sensor_tick := 0.0
var _walk_direction := Vector3.ZERO
var _desired_speed := 0.0
var _can_walk := false
var _obstructed := false
var _passing_time := 0.0
var _passing_side := 1.0
var _obstacle_ray: PhysicsRayQueryParameters3D
var _crossing_target := -1


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	add_to_group("pedestrians")
	_obstacle_ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1 | 2 | 4 | 8, [get_rid()])
	var wrapper := model_scene.instantiate()
	model = wrapper.get_node("GeneralSkeleton")
	wrapper.remove_child(model)
	for mesh in model.get_children():
		if mesh is MeshInstance3D and not mesh.visible: mesh.free()
	wrapper.free()
	add_child(model)
	motion = Motion.new()
	motion.bind(model)
	# Distribute bone updates across physics frames instead of updating the crowd together.
	var phase_offset := float(get_instance_id() % 61) / 61.0
	animation_elapsed = phase_offset * animation_interval
	animation_lod_timer = phase_offset * 0.5
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 1.8
	collider.shape = shape
	collider.position.y = 0.9
	add_child(collider)
	previous_cell = cell
	_choose_next()
	_sensor_tick = phase_offset / 12.0


func _exit_tree() -> void:
	if is_instance_valid(world): crossing_junction = -1


func _choose_next() -> void:
	_sensor_tick = 0.0
	_crossing_target = -1
	var options: Array = world.walk_neighbors.get(cell, []).duplicate()
	if options.is_empty(): target_cell = cell; return
	if options.size() > 1: options.erase(previous_cell)
	if flee_time > 0:
		var best := -INF
		for option in options:
			var distance: float = world.walk_position(option).distance_to(fear_origin)
			if distance > best: best = distance; target_cell = option
	else:
		var straight := cell + (cell - previous_cell)
		if straight in options and world.rng.randf() < 0.8: target_cell = straight
		else: target_cell = options[world.rng.randi_range(0, options.size() - 1)]
	_crossing_target = world.crossing_edges.get(world._edge_key(cell, target_cell), -1)


func _physics_process(delta: float) -> void:
	idle_time = maxf(0, idle_time - delta)
	flee_time = maxf(0, flee_time - delta)
	knockdown = maxf(0, knockdown - delta)
	_passing_time = maxf(0, _passing_time - delta)
	_sensor_tick -= delta
	if _sensor_tick <= 0.0:
		_plan_walk()
		_sensor_tick += 1.0 / 12.0
	velocity.x = move_toward(velocity.x, _walk_direction.x * _desired_speed, delta * 6)
	velocity.z = move_toward(velocity.z, _walk_direction.z * _desired_speed, delta * 6)
	if not is_on_floor(): velocity.y -= 20 * delta
	else: velocity.y = 0
	if not is_on_floor() or not velocity.is_zero_approx(): move_and_slide()
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	if actual_speed > 0.1: rotation.y = lerp_angle(rotation.y, atan2(_walk_direction.x, _walk_direction.z), minf(delta * 6, 1))
	_update_animation(delta, actual_speed)
	model.rotation.z = lerpf(model.rotation.z, 1.4 if knockdown > 0 or health <= 0 else 0.0, minf(delta * 6, 1))
	if actual_speed < 0.1 and (_can_walk or _obstructed) and health > 0 and knockdown <= 0:
		blocked_time += delta
		if blocked_time > 3 and crossing_junction < 0:
			previous_cell = target_cell
			_choose_next()
			blocked_time = 0
	else: blocked_time = 0


func _plan_walk() -> void:
	var target: Vector3 = world.walk_position(target_cell)
	var offset := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	if offset.length() < 0.3:
		previous_cell = cell
		cell = target_cell
		crossing_junction = -1
		walk_steps += 1
		if walk_steps % 25 == 0 and flee_time <= 0: idle_time = world.rng.randf_range(1, 4)
		_choose_next()
		target = world.walk_position(target_cell)
		offset = Vector3(target.x - global_position.x, 0, target.z - global_position.z)
	_can_walk = idle_time <= 0 and knockdown <= 0 and health > 0
	if crossing_junction < 0 and _crossing_target >= 0:
		if not world.may_cross(cell, target_cell): _can_walk = false
		elif _can_walk: crossing_junction = _crossing_target
	_walk_direction = offset.normalized()
	_desired_speed = walk_speed * (2.6 if flee_time > 0 else 1.0)
	if _can_walk:
		var stopping_distance := _desired_speed * _desired_speed / 12.0 + _desired_speed / 12.0 + 0.35
		_obstacle_ray.from = global_position + Vector3.UP
		_obstacle_ray.to = _obstacle_ray.from + _walk_direction * maxf(0.9, stopping_distance)
		var space := get_world_3d().direct_space_state
		var hit := space.intersect_ray(_obstacle_ray)
		_obstructed = not hit.is_empty()
		if crossing_junction < 0 and _crossing_target < 0 and (_obstructed or _passing_time > 0):
			# Prefer the right side relative to travel, allowing oncoming walkers to pass.
			for side: float in [_passing_side, -_passing_side]:
				var pass_direction := _walk_direction.rotated(Vector3.UP, -side * 0.98)
				var probe := global_position + pass_direction * 1.05
				var cell_ahead := Vector2i(floori(probe.x / world.WALK_CELL), floori(probe.z / world.WALK_CELL))
				if not world.sidewalk_cells.has(cell_ahead): continue
				_obstacle_ray.to = _obstacle_ray.from + pass_direction * 1.05
				if not space.intersect_ray(_obstacle_ray).is_empty(): continue
				_walk_direction = pass_direction
				if _obstructed: _passing_time = 0.45
				_passing_side = side
				_obstructed = false
				break
	if _obstructed: _can_walk = false
	if not _can_walk: _desired_speed = 0


func _update_animation(delta: float, actual_speed: float) -> void:
	animation_elapsed += delta
	animation_lod_timer -= delta
	if animation_lod_timer <= 0.0:
		animation_lod_timer = 0.25
		var distance_squared := INF
		if is_instance_valid(world.subject):
			distance_squared = global_position.distance_squared_to(world.subject.global_position)
		var previous_interval := animation_interval
		animation_interval = 1.0 / 60.0 if distance_squared < 400.0 else (1.0 / 30.0 if distance_squared < 3025.0 else 1.0 / 15.0)
		var camera := get_viewport().get_camera_3d()
		if distance_squared >= 400.0 and camera != null and not camera.is_position_in_frustum(global_position + Vector3.UP):
			animation_interval = 0.1 if distance_squared < 1600.0 else INF
		if previous_interval > 0.09 and animation_interval < 0.09:
			motion._clear_foot_locks()
	if is_inf(animation_interval):
		animation_elapsed = 0.0
		return
	# The idle pose has no advancing gait; avoid resolving all four IK chains again.
	if actual_speed < 0.01 and float(motion.get("blend")) <= 0.001:
		animation_elapsed = 0.0
		return
	if animation_elapsed + 0.000001 < animation_interval: return
	# Pass all elapsed time so gait speed and blend timing stay the same at every LOD.
	motion.update(animation_elapsed, actual_speed, flee_time > 0)
	animation_elapsed = 0.0


func flee(origin: Vector3) -> void:
	fear_origin = origin
	flee_time = 8
	if crossing_junction < 0: _choose_next()


func receive_hit(amount: float, direction: Vector3) -> void:
	health = maxf(0, health - amount)
	knockdown = 4
	_sensor_tick = 0.0
	velocity += direction * 2
	# Preserve a live crossing reservation until a fallen pedestrian recovers.
	if health <= 0:
		collision_layer = 0
		crossing_junction = -1
