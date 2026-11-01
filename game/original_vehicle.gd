extends "res://vehicles/vehicle.gd"

const Visual = preload("res://game/car_visual.gd")
var tint := Color("e88d81")
var kind := "sport"
var active := false
var display_name := "SUNLINE GT"


func _ready() -> void:
	$Body.free()
	add_child(Visual.build(tint, kind, false))
	position = Vector3.ZERO
	mass = 1000
	angular_damp = 3.0
	linear_damp = 0.08
	engine_force_value = 3600 if kind == "sport" else 2800
	center_of_mass = Vector3(0, 0.25, 0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.8, 4.2)
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = Vector3(0, 0.85, 0)
	var positions := [Vector3(0.96, 0.58, 1.45), Vector3(0.96, 0.58, -1.45), Vector3(-0.96, 0.58, 1.45), Vector3(-0.96, 0.58, -1.45)]
	for i in 4:
		var wheel := get_node("Wheel%d" % (i + 1)) as VehicleWheel3D
		for child in wheel.get_children(): child.free()
		wheel.add_child(Visual.wheel_visual())
		wheel.position = positions[i]
		wheel.wheel_radius = 0.4
		wheel.wheel_rest_length = 0.18
		wheel.suspension_travel = 0.2
		wheel.suspension_stiffness = 35
		wheel.suspension_max_force = 8000
		wheel.damping_compression = 2.3
		wheel.damping_relaxation = 2.8
		wheel.wheel_friction_slip = 2.5
		wheel.wheel_roll_influence = 0.1
	var camera := $CameraBase/Camera3D
	camera.set_as_top_level(false)
	$CameraBase.position = Vector3(0, 1.0, 0)
	camera.position = Vector3(0, 2.7, -7)
	camera.min_distance = 6
	camera.max_distance = 8
	camera.height = 2.5
	camera.far = 1800
	camera.initial_transform = camera.transform
	camera.update_camera()
	camera.set_process_input(false)
	$InteriorCameraPosition.position = Vector3(0.35, 1.25, 0.4)
	$TopDownCameraPosition.position = Vector3(0, 24, 0)
	$HeadlightL.position = Vector3(0.63, 0.85, 2.25)
	$HeadlightR.position = Vector3(-0.63, 0.85, 2.25)
	$CPUParticles3D.emitting = false
	$CPUParticles3D.position = Vector3(0.65, 0.3, -2.3)
	$BlobShadow.size = Vector3(2.4, 4, 5)
	$EngineSound.stop()
	super._ready()


func _physics_process(delta: float) -> void:
	if active:
		super._physics_process(delta)
		if linear_velocity.length() > 48: engine_force = minf(engine_force, 0)
	else:
		engine_force = 0
		constant_force = Vector3.ZERO
		brake = 30


func _input(event: InputEvent) -> void:
	if active: super._input(event)


func set_active(value: bool) -> void:
	active = value
	$CameraBase/Camera3D.set_process_input(value)
	$CPUParticles3D.emitting = value
	if value:
		$EngineSound.play()
		$CameraBase/Camera3D.update_camera()
		$CameraBase/Camera3D.make_current()
	else:
		$EngineSound.stop()
