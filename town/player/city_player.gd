extends CharacterBody3D

signal fired(origin: Vector3, destination: Vector3, collider: Object)
signal ammunition_changed(loaded: int, reserve: int)
const STEP_HEIGHT := 0.29
const Motion = preload("res://town/player/humanoid_motion.gd")
const CHARACTER = preload("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_Male_Hoodie.tscn")
var active := false
var first_person := false
var aiming := false
var weapon_drawn := false
var magazine := 12
var reserve := 84
var reload_time := 0.0
var fire_time := 0.0
var yaw := 0.0
var pitch := -0.12
var camera: Camera3D
var pivot: Node3D
var arm: SpringArm3D
var visual: Node3D
var skeleton: Skeleton3D
var motion = Motion.new()
var weapon: Node3D
var muzzle: OmniLight3D
var world_weapon: Node3D
var world_muzzle: OmniLight3D
var hand_anchor: Node3D
var jump_buffer := 0.0
var coyote_time := 0.0
var recoil := 0.0
var head_bob := 0.0
var health := 100.0
var saved_collision_layer := 2
var _step_visual_offset := 0.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4 | 8
	floor_snap_length = 0.3
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.28
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	var imported := CHARACTER.instantiate()
	skeleton = imported.get_node("GeneralSkeleton")
	imported.remove_child(skeleton)
	imported.free()
	visual = Node3D.new()
	add_child(visual)
	visual.add_child(skeleton)
	for child in skeleton.get_children():
		if child is MeshInstance3D and not child.visible: child.free()
	motion.bind(skeleton)
	pivot = Node3D.new()
	pivot.position.y = 1.55
	add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 3.8
	arm.margin = 0.2
	arm.collision_mask = 1 | 4 | 8
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.18
	arm.shape = camera_shape
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.near = 0.06
	camera.far = 1200
	camera.fov = 72
	arm.add_child(camera)
	_build_weapon()
	set_active(false)

func set_active(value: bool) -> void:
	active = value
	visible = value
	collision_layer = 2 if value else 0
	collision_mask = (1 | 4 | 8) if value else 0
	set_physics_process(value)
	set_process_unhandled_input(value)
	if value:
		pivot.rotation = Vector3(pitch, yaw, 0.0)
		visual.rotation.y = yaw + PI
		arm.spring_length = 0.0 if first_person else (2.2 if aiming else 3.8)
		arm.position.x = 0.0 if first_person else (0.48 if aiming else 0.3)
		_update_world_weapon()
		camera.make_current()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		reset_physics_interpolation()
	velocity = Vector3.ZERO
	jump_buffer = 0.0
	coyote_time = 0.0
	_step_visual_offset = 0.0
	visual.position.y = 0.0
	if not value:
		aiming = false
		muzzle.light_energy = 0.0
		world_muzzle.light_energy = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if not active: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.0022
		pitch = clampf(pitch - event.relative.y * 0.0022, -1.1, 1.0)
	if event.is_action_pressed("cycle_camera"):
		first_person = not first_person
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_Q:
			weapon_drawn = not weapon_drawn
			if not weapon_drawn: aiming = false
		if event.physical_keycode == KEY_SPACE: jump_buffer = 0.12
		if event.physical_keycode == KEY_R and weapon_drawn: reload_weapon()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			aiming = event.pressed
			if aiming: weapon_drawn = true
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if weapon_drawn: shoot()

func _physics_process(delta: float) -> void:
	fire_time = maxf(0, fire_time - delta)
	recoil = move_toward(recoil, 0, delta * 7)
	muzzle.light_energy = 3 if fire_time > 0.18 else 0
	world_muzzle.light_energy = muzzle.light_energy
	if reload_time > 0:
		reload_time -= delta
		if reload_time <= 0:
			var count := mini(12 - magazine, reserve)
			magazine += count
			reserve -= count
			ammunition_changed.emit(magazine, reserve)
	var input := Input.get_vector("turn_left", "turn_right", "accelerate", "reverse")
	var direction := Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)
	var running := Input.is_action_pressed("boost") and not aiming
	var speed := 6.4 if running else (1.5 if aiming else 1.8)
	velocity.x = move_toward(velocity.x, direction.x * speed, 18 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 18 * delta)
	jump_buffer = maxf(0.0, jump_buffer - delta)
	coyote_time = 0.1 if is_on_floor() else maxf(0.0, coyote_time - delta)
	if not is_on_floor(): velocity.y -= 20 * delta
	if jump_buffer > 0.0 and coyote_time > 0.0:
		velocity.y = 5.7
		jump_buffer = 0.0
		coyote_time = 0.0
	_step_visual_offset = lerpf(_step_visual_offset, 0.0, 1.0 - exp(-delta * 18.0))
	_try_step_up(delta)
	move_and_slide()
	visual.position.y = _step_visual_offset
	var horizontal := Vector2(velocity.x, velocity.z).length()
	if weapon_drawn or first_person: visual.rotation.y = lerp_angle(visual.rotation.y, yaw + PI, 1.0 - exp(-delta * 14.0))
	elif horizontal > 0.1: visual.rotation.y = lerp_angle(visual.rotation.y, atan2(velocity.x, velocity.z), delta * 10)
	var local_velocity := visual.global_basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	motion.update(delta, horizontal, running, weapon_drawn, pitch, aiming, is_on_floor(), reload_time > 0.0, Vector2(local_velocity.x, local_velocity.z))
	visual.visible = not first_person
	pivot.rotation = Vector3(pitch + recoil * 0.03, yaw, 0)
	arm.spring_length = 0 if first_person else (2.2 if aiming else 3.8)
	arm.position.x = 0 if first_person else (0.48 if aiming else 0.3)
	head_bob += delta * horizontal * 1.9
	pivot.position.y = 1.62 + _step_visual_offset + (sin(head_bob) * 0.016 if first_person and is_on_floor() else 0)
	camera.fov = lerpf(camera.fov, 58 if aiming else (77 if running else 72), 1 - exp(-delta * 9))
	weapon.visible = weapon_drawn and first_person
	world_weapon.visible = weapon_drawn and not first_person
	weapon.position = Vector3(0.16 if aiming else 0.26, -0.19 - (0.15 if reload_time > 0 else 0), -0.48 + recoil * 0.07)
	weapon.rotation.x = -0.65 if reload_time > 0 else recoil * 0.1
	_update_world_weapon()

func _try_step_up(delta: float) -> void:
	if not is_on_floor() or velocity.y > 0.1: return
	var movement := Vector3(velocity.x, 0.0, velocity.z) * delta
	if movement.length_squared() < 0.00001: return
	var obstruction := KinematicCollision3D.new()
	if not test_move(global_transform, movement, obstruction, 0.001): return
	var found_step := false
	for index in obstruction.get_collision_count():
		var collider := obstruction.get_collider(index)
		# Curbs belong to static world geometry. Never climb other actors or cars.
		if not collider is StaticBody3D or (collider.collision_layer & 1) == 0: return
		if obstruction.get_normal(index).y < cos(floor_max_angle): found_step = true
	if not found_step: return
	# Check the complete upward sweep, not just a ray above the character's feet.
	if test_move(global_transform, Vector3.UP * STEP_HEIGHT, null, 0.001): return
	var raised := global_transform
	raised.origin.y += STEP_HEIGHT
	var probe := movement.normalized() * minf(movement.length() + 0.28, 0.4)
	if test_move(raised, probe, null, 0.001): return
	var landing := raised
	landing.origin += probe
	var support := KinematicCollision3D.new()
	if not test_move(landing, Vector3.DOWN * (STEP_HEIGHT + 0.04), support, 0.001): return
	var floor_body := support.get_collider()
	if not floor_body is StaticBody3D or (floor_body.collision_layer & 1) == 0: return
	if support.get_normal().y < cos(floor_max_angle): return
	var rise := STEP_HEIGHT + support.get_travel().y
	if rise < 0.02 or rise > STEP_HEIGHT: return
	# Horizontal movement is still handled by move_and_slide; only the verified lift is applied.
	global_position.y += rise + 0.001
	velocity.y = 0.0
	_step_visual_offset = maxf(_step_visual_offset - rise, -STEP_HEIGHT)


func reload_weapon() -> void:
	if reload_time > 0 or magazine == 12 or reserve <= 0: return
	reload_time = 1.35

func shoot() -> void:
	if fire_time > 0 or reload_time > 0 or not weapon_drawn: return
	if magazine == 0:
		reload_weapon()
		return
	magazine -= 1
	ammunition_changed.emit(magazine, reserve)
	fire_time = 0.23
	recoil = 1
	var space := get_world_3d().direct_space_state
	var camera_origin := camera.global_position
	var destination := camera_origin - camera.global_basis.z * 160.0
	var aim_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(camera_origin, destination, 1 | 4 | 8, [get_rid()]))
	if not aim_hit.is_empty(): destination = aim_hit.position
	var from := muzzle.global_position if first_person else world_muzzle.global_position
	# The camera chooses the target; the physical barrel must have a clear path.
	# Also check the short body-to-barrel segment when a gun pokes into a wall.
	var body_origin := global_position + Vector3.UP * 1.35
	var obstruction_query := PhysicsRayQueryParameters3D.create(body_origin, from, 1 | 4 | 8, [get_rid()])
	obstruction_query.hit_from_inside = true
	var hit := space.intersect_ray(obstruction_query)
	if hit.is_empty():
		var shot_query := PhysicsRayQueryParameters3D.create(from, destination, 1 | 4 | 8, [get_rid()])
		shot_query.hit_from_inside = true
		hit = space.intersect_ray(shot_query)
	else:
		from = hit.position - (from - body_origin).normalized() * 0.03
	var collider: Object = null
	if not hit.is_empty():
		destination = hit.position
		collider = hit.collider
		if collider.has_method("receive_hit"): collider.receive_hit(25, (destination - from).normalized())
	fired.emit(from, destination, collider)
	if from.distance_to(destination) < 0.01: return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.008, from.distance_to(destination))
	tracer.mesh = mesh
	tracer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.8, 0.5, 0.65)
	tracer.material_override = material
	get_parent().add_child(tracer)
	tracer.global_position = from.lerp(destination, 0.5)
	tracer.look_at(destination)
	get_tree().create_timer(0.045).timeout.connect(tracer.queue_free)

func _build_weapon() -> void:
	weapon = _create_pistol(camera, true)
	muzzle = weapon.get_node("Muzzle")
	hand_anchor = Node3D.new()
	hand_anchor.name = "RightHandWeapon"
	skeleton.add_child(hand_anchor)
	world_weapon = _create_pistol(hand_anchor, false)
	world_muzzle = world_weapon.get_node("Muzzle")
	weapon.hide()
	world_weapon.hide()
	_update_world_weapon()

func _update_world_weapon() -> void:
	# Use the actual animated wrist transform; no camera-mounted weapon in third person.
	var hand := skeleton.get_bone_global_pose(skeleton.find_bone("RightHand"))
	hand_anchor.transform = hand
	var gun_basis := Basis(Vector3.RIGHT, -pitch + (-0.5 if reload_time > 0.0 else 0.0)) * Basis(Vector3.UP, PI)
	var gun_transform := Transform3D(gun_basis, hand.origin + gun_basis * Vector3(0.0, 0.075, -0.09))
	world_weapon.transform = hand.affine_inverse() * gun_transform

func _create_pistol(parent: Node3D, view_model: bool) -> Node3D:
	var model := Node3D.new()
	parent.add_child(model)
	_piece(model, Vector3(0, 0, 0), Vector3(0.047, 0.052, 0.23), Color("363e45"), 0.65)
	_piece(model, Vector3(0, -0.07, 0.055), Vector3(0.04, 0.11, 0.065), Color("252b2c"))
	_piece(model, Vector3(0, 0.03, -0.09), Vector3(0.008, 0.012, 0.012), Color("bfc4bc"), 0.6)
	_piece(model, Vector3(0, 0.028, 0.09), Vector3(0.037, 0.008, 0.015), Color("181e21"), 0.6)
	_piece(model, Vector3(0.024, 0.007, 0.015), Vector3(0.002, 0.019, 0.04), Color("151a1c"), 0.7)
	_piece(model, Vector3(0, -0.058, -0.013), Vector3(0.019, 0.009, 0.07), Color("252b2c"), 0.5)
	_piece(model, Vector3(0, -0.041, -0.045), Vector3(0.019, 0.043, 0.009), Color("252b2c"), 0.5)
	if view_model:
		_piece(model, Vector3(0.014, -0.083, 0.065), Vector3(0.067, 0.09, 0.072), Color("bb8e74"))
		_piece(model, Vector3(0.025, -0.16, 0.13), Vector3(0.09, 0.14, 0.18), Color("424d55"))
	var flash := OmniLight3D.new()
	flash.name = "Muzzle"
	flash.position.z = -0.13
	flash.omni_range = 5
	flash.light_color = Color(1, 0.65, 0.3)
	flash.light_energy = 0
	model.add_child(flash)
	return model

func _piece(parent: Node3D, p: Vector3, dimensions: Vector3, tint: Color, metallic := 0.0) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	instance.mesh = mesh
	instance.position = p
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = metallic
	material.roughness = 0.4 if metallic > 0.0 else 0.85
	instance.material_override = material
	parent.add_child(instance)
