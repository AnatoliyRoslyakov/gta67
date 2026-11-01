extends "res://vehicles/vehicle.gd"

var vehicle_scene: PackedScene


func _ready() -> void:
	var model := vehicle_scene.instantiate() as MeshInstance3D
	_remove_static_bodies(model)
	$Body.free()
	add_child(model)
	model.name = "PolygonModel"
	position = Vector3.ZERO
	mass = 1000.0
	center_of_mass = Vector3(0, 0.3, 0)
	var bounds := model.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = Vector3(bounds.size.x * 0.92, bounds.size.y * 0.75, bounds.size.z * 0.9)
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = bounds.get_center()
	var wheels := ["Wheel1", "Wheel2", "Wheel3", "Wheel4"]
	var suffixes := ["_Wheel_fl", "_Wheel_rl", "_Wheel_fr", "_Wheel_rr"]
	for i in wheels.size():
		var wheel := get_node(wheels[i]) as VehicleWheel3D
		for old_visual in wheel.get_children():
			old_visual.free()
		for part in model.get_children():
			if part is MeshInstance3D and str(part.name).ends_with(suffixes[i]):
				var wheel_bounds: AABB = part.get_aabb()
				wheel.wheel_radius = maxf(wheel_bounds.size.y, wheel_bounds.size.z) * 0.5
				wheel.position = part.position + Vector3.UP * 0.18
				part.reparent(wheel, false)
				part.position = Vector3.ZERO
				break
		wheel.wheel_rest_length = 0.18
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 35.0
		wheel.suspension_max_force = 8000.0
		wheel.damping_compression = 2.3
		wheel.damping_relaxation = 2.8
		wheel.wheel_friction_slip = 2.5
		wheel.wheel_roll_influence = 0.1
	$CameraBase/Camera3D.set_as_top_level(false)
	$CameraBase.position = Vector3(0, 1.4, 0)
	$CameraBase/Camera3D.position = Vector3(0, 2.7, -7)
	$CameraBase/Camera3D.min_distance = 6.0
	$CameraBase/Camera3D.max_distance = 8.0
	$CameraBase/Camera3D.height = 2.7
	$CameraBase/Camera3D.far = 1500.0
	$CameraBase/Camera3D.initial_transform = $CameraBase/Camera3D.transform
	$CameraBase/Camera3D.update_camera()
	$CameraBase/Camera3D.make_current()
	$InteriorCameraPosition.position = Vector3(0.35, bounds.end.y * 0.8, 0.35)
	$TopDownCameraPosition.position = Vector3(0, 24, 0)
	$CPUParticles3D.position = Vector3(0.4, 0.25, bounds.position.z)
	$BlobShadow.size = Vector3(bounds.size.x + 0.4, 4, bounds.size.z + 0.4)
	$HeadlightL.position = Vector3(bounds.size.x * 0.35, 0.65, bounds.end.z)
	$HeadlightR.position = Vector3(-bounds.size.x * 0.35, 0.65, bounds.end.z)
	super._ready()


func _remove_static_bodies(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D:
			child.free()
		else:
			_remove_static_bodies(child)
