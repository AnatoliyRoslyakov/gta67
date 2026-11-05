extends CharacterBody3D

const MODEL_PATH := "res://Assets/Characters/Gary/gary.glb"
var rider: CharacterBody3D
var model: Node3D
var seat: Node3D
var grips: Array[Node3D] = []
var eyes: Array[Node3D] = []
var speed := 0.0
var steer := 0.0
var phase := 0.0
var home := Transform3D.IDENTITY

func _ready() -> void:
	process_physics_priority = -1
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	floor_snap_length = 0.45
	floor_max_angle = deg_to_rad(42)
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.40
	shape.height = 1.8
	collider.shape = shape
	collider.rotation.x = PI / 2
	collider.position.y = 0.36
	add_child(collider)
	var shell_collider := CollisionShape3D.new()
	var shell_shape := CapsuleShape3D.new()
	shell_shape.radius = 0.44
	shell_shape.height = 1.40
	shell_collider.shape = shell_shape
	shell_collider.position = Vector3(0, 0.8, -0.14)
	add_child(shell_collider)
	model = load(MODEL_PATH).instantiate()
	add_child(model)
	seat = model.find_child("RideSeat", true, false)
	for side in ["Left", "Right"]:
		eyes.append(model.find_child(side + "EyePivot", true, false))
		grips.append(model.find_child(side + "Grip", true, false))
	var label := Label3D.new()
	label.text = "ГЭРИ\nE — сесть"
	label.position = Vector3(0, 2.2, 0)
	label.font_size = 28
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 16
	label.name = "Prompt"
	add_child(label)

func _physics_process(delta: float) -> void:
	var controlled := is_instance_valid(rider)
	var throttle := Input.get_axis("reverse", "accelerate") if controlled else 0.0
	var target_steer := Input.get_axis("turn_right", "turn_left") if controlled else 0.0
	steer = move_toward(steer, target_steer, delta * 3.5)
	var top_speed := 10.0 if controlled and Input.is_action_pressed("boost") else 6.0
	var braking := controlled and Input.is_physical_key_pressed(KEY_SPACE)
	var target_speed := throttle * (top_speed if throttle >= 0 else 2.5)
	speed = move_toward(speed, 0.0 if braking else target_speed, delta * (12.0 if braking else 4.0))
	# Turn continuously; never snap to a new compass heading.
	if absf(speed) > 0.05:
		rotation.y += steer * signf(speed) * minf(absf(speed) / 1.5, 1.0) * 1.25 * delta
	var forward := global_basis.z
	velocity.x = forward.x * speed
	velocity.z = forward.z * speed
	if not is_on_floor(): velocity.y -= 20.0 * delta
	else: velocity.y = -0.1
	move_and_slide()
	if is_on_wall(): speed = Vector2(velocity.x, velocity.z).length() * signf(speed)
	phase += delta * (1.5 + absf(speed) * 2.0)
	model.position.y = sin(phase) * minf(absf(speed) * 0.004, 0.025)
	model.rotation.z = lerpf(model.rotation.z, -steer * minf(absf(speed) * 0.008, 0.055), 1 - exp(-delta * 5))
	for index in eyes.size():
		eyes[index].rotation.z = sin(phase * 0.55 + index * 0.7) * 0.025 - steer * 0.08
	if global_position.y < -10:
		global_transform = home
		velocity = Vector3.ZERO
		speed = 0
		reset_physics_interpolation()

func can_mount(character: CharacterBody3D) -> bool:
	if is_instance_valid(rider) or character.global_position.distance_to(global_position) > 3.0: return false
	var query := PhysicsRayQueryParameters3D.create(character.global_position + Vector3.UP, global_position + Vector3.UP, 1 | 4 | 8, [get_rid(), character.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func board(character: CharacterBody3D) -> void:
	rider = character
	$Prompt.hide()
	character.mount_gary(self)

func exit_position() -> Vector3:
	var space := get_world_3d().direct_space_state
	for side in [1.0, -1.0]:
		var point: Vector3 = global_position + global_basis.x * side * 1.7
		var excluded: Array[RID] = [get_rid()]
		if is_instance_valid(rider): excluded.append(rider.get_rid())
		var passage := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, point + Vector3.UP, 1 | 4 | 8, excluded)
		if not space.intersect_ray(passage).is_empty(): continue
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2, point - Vector3.UP * 3, 1, excluded))
		if ground.is_empty() or ground.normal.y < 0.7: continue
		point = ground.position + Vector3.UP * 0.06
		var check := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.3
		shape.height = 1.8
		check.shape = shape
		check.transform.origin = point + Vector3.UP * 0.9
		check.collision_mask = 1 | 2 | 4 | 8
		check.exclude = excluded
		if space.intersect_shape(check, 1).is_empty(): return point
	return Vector3.INF

func unboard(destination: Vector3) -> void:
	if is_instance_valid(rider): rider.dismount_gary(destination)
	rider = null
	speed = 0.0
	velocity = Vector3.ZERO
	$Prompt.show()

func receive_hit(amount: float, direction: Vector3) -> void:
	if is_instance_valid(rider): rider.receive_hit(amount, direction)
