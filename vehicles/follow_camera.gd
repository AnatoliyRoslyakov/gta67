extends Camera3D

enum CameraType { EXTERIOR, INTERIOR, TOP_DOWN, MAX }
@export var min_distance := 4.0
@export var max_distance := 7.0
@export var angle_v_adjust := 0.0
@export var height := 2.3
var camera_type := CameraType.EXTERIOR
var initial_transform := Transform3D.IDENTITY
var base_fov := 74.0
var desired_fov := 74.0
var previous_position := Vector3.ZERO
var interior_look := Vector2.ZERO
var exterior_look := Vector2.ZERO
var orbit_timeout := 0.0
var body: VehicleBody3D
var planar_forward := Vector3.BACK


func _ready() -> void:
	body = get_node("../..") as VehicleBody3D
	initial_transform = transform
	base_fov = fov
	near = 0.04
	update_camera()


func _input(event: InputEvent) -> void:
	if not body.controllable: return
	if event.is_action_pressed("cycle_camera"):
		camera_type = wrapi(camera_type + 1, 0, CameraType.MAX) as CameraType
		interior_look = Vector2.ZERO
		exterior_look = Vector2.ZERO
		update_camera()
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		if camera_type == CameraType.INTERIOR:
			interior_look.x = clampf(interior_look.x - event.relative.x * 0.003, -1.35, 1.35)
			interior_look.y = clampf(interior_look.y - event.relative.y * 0.003, -0.55, 0.45)
		elif camera_type == CameraType.EXTERIOR:
			exterior_look.x -= event.relative.x * 0.003
			exterior_look.y = clampf(exterior_look.y - event.relative.y * 0.003, -0.4, 0.65)
			orbit_timeout = 2.0


func _physics_process(delta: float) -> void:
	if not body.controllable: return
	var target: Vector3 = get_parent().global_position
	var speed := body.linear_velocity.length()
	if camera_type == CameraType.EXTERIOR:
		orbit_timeout -= delta
		if orbit_timeout <= 0: exterior_look = exterior_look.lerp(Vector2.ZERO, 1 - exp(-delta * 2))
		var desired := _exterior_position(target)
		var safe_position := _avoid_obstacles(target, desired)
		# Also test the smoothed segment so interpolation cannot cut through a wall.
		var smoothed := global_position.lerp(safe_position, 1 - exp(-delta * 7))
		global_position = _avoid_obstacles(target, smoothed)
		if global_position.distance_squared_to(target) > 0.01: look_at(target, Vector3.UP)
	elif camera_type == CameraType.INTERIOR:
		_apply_interior_view()
	else:
		var desired := target + Vector3.UP * 24
		global_position = _avoid_obstacles(target, desired)
		look_at(target, Vector3.FORWARD)
	desired_fov = 72.0 if camera_type == CameraType.INTERIOR else base_fov + minf(speed * 0.28, 12)
	fov = lerpf(fov, desired_fov, 1 - exp(-delta * 4))
	previous_position = global_position


func _exterior_position(target: Vector3) -> Vector3:
	var forward := body.global_basis.z
	forward.y = 0
	# Keep the last useful heading when a crash points the car vertically.
	if forward.length_squared() > 0.001: planar_forward = forward.normalized()
	forward = planar_forward.rotated(Vector3.UP, exterior_look.x)
	var distance := lerpf(min_distance, max_distance, clampf(body.linear_velocity.length() / 25, 0, 1))
	return target - forward * distance + Vector3.UP * (height + exterior_look.y * 4)


func _apply_interior_view() -> void:
	global_transform = body.get_node("InteriorCameraPosition").global_transform
	rotate_object_local(Vector3.UP, interior_look.x)
	rotate_object_local(Vector3.RIGHT, interior_look.y)


func _avoid_obstacles(from: Vector3, to: Vector3) -> Vector3:
	if from.distance_squared_to(to) < 0.0001: return to
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4 | 8, [body.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return to
	return hit.position + hit.normal * 0.3


func update_camera() -> void:
	if not is_instance_valid(body): body = get_node("../..") as VehicleBody3D
	set_as_top_level(true)
	var target: Vector3 = get_parent().global_position
	if camera_type == CameraType.INTERIOR:
		_apply_interior_view()
	elif camera_type == CameraType.TOP_DOWN:
		global_position = _avoid_obstacles(target, target + Vector3.UP * 24)
		look_at(target, Vector3.FORWARD)
	else:
		global_position = _avoid_obstacles(target, _exterior_position(target))
		if global_position.distance_squared_to(target) > 0.01: look_at(target, Vector3.UP)
	fov = 72.0 if camera_type == CameraType.INTERIOR else base_fov + minf(body.linear_velocity.length() * 0.28, 12)
	if body.has_method("set_cabin_view"): body.set_cabin_view(camera_type == CameraType.INTERIOR)
	previous_position = global_position
	reset_physics_interpolation()
