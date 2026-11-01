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
var crossing_junction := -1
var flee_time := 0.0
var fear_origin := Vector3.ZERO
var health := 100.0
var knockdown := 0.0
var blocked_time := 0.0
var walk_steps := 0
var animation_elapsed := 0.0
var animation_interval := 1.0 / 30.0
var animation_lod_timer := 0.0


func _ready() -> void:
	collision_layer = 8
	collision_mask = 1 | 2 | 4 | 8
	add_to_group("pedestrians")
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


func _choose_next() -> void:
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


func _physics_process(delta: float) -> void:
	idle_time = maxf(0, idle_time - delta)
	flee_time = maxf(0, flee_time - delta)
	knockdown = maxf(0, knockdown - delta)
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
	var can_walk := idle_time <= 0 and knockdown <= 0 and health > 0
	var edge: String = world._edge_key(cell, target_cell)
	if crossing_junction < 0 and world.crossing_edges.has(edge):
		if not world.may_cross(cell, target_cell): can_walk = false
		elif can_walk: crossing_junction = world.crossing_edges[edge]
	var direction := offset.normalized()
	var desired_speed := walk_speed * (2.6 if flee_time > 0 else 1.0)
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.UP + direction * 0.9, 1 | 2 | 4 | 8, [get_rid()])
	var obstructed := not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
	if obstructed: can_walk = false
	if not can_walk: desired_speed = 0
	velocity.x = move_toward(velocity.x, direction.x * desired_speed, delta * 6)
	velocity.z = move_toward(velocity.z, direction.z * desired_speed, delta * 6)
	if not is_on_floor(): velocity.y -= 20 * delta
	else: velocity.y = 0
	move_and_slide()
	var actual_speed := Vector2(velocity.x, velocity.z).length()
	if actual_speed > 0.1: rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), minf(delta * 6, 1))
	_update_animation(delta, actual_speed)
	model.rotation.z = lerpf(model.rotation.z, 1.4 if knockdown > 0 or health <= 0 else 0.0, minf(delta * 6, 1))
	if actual_speed < 0.1 and (can_walk or obstructed) and health > 0 and knockdown <= 0:
		blocked_time += delta
		if blocked_time > 3 and crossing_junction < 0:
			previous_cell = target_cell
			_choose_next()
			blocked_time = 0
	else: blocked_time = 0


func _update_animation(delta: float, actual_speed: float) -> void:
	animation_elapsed += delta
	animation_lod_timer -= delta
	if animation_lod_timer <= 0.0:
		animation_lod_timer = 0.5
		var distance_squared := INF
		if is_instance_valid(world.subject):
			distance_squared = global_position.distance_squared_to(world.subject.global_position)
		animation_interval = 1.0 / 60.0 if distance_squared < 400.0 else (1.0 / 30.0 if distance_squared < 3025.0 else 1.0 / 15.0)
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
	velocity += direction * 2
	# Preserve a live crossing reservation until a fallen pedestrian recovers.
	if health <= 0:
		collision_layer = 0
		crossing_junction = -1
