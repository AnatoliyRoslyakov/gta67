extends "res://vehicles/vehicle.gd"

const TIRE_CONTACT_CLEARANCE := 0.004

var vehicle_scene: PackedScene
var wheel_reference_centers: Dictionary = {}
var wheel_visible_radii: Dictionary = {}
var wheel_visuals: Array[Dictionary] = []
var steering_mesh: MeshInstance3D
var steering_reference := Transform3D.IDENTITY
var cabin: Node3D
var dashboard_speed: Label3D
var dashboard_tick := 0.0


func _ready() -> void:
	var model := vehicle_scene.instantiate() as MeshInstance3D
	_remove_static_bodies(model)
	$Body.free()
	add_child(model)
	model.name = "PolygonModel"
	position = Vector3.ZERO
	var profile := _profile(vehicle_scene.resource_path)
	mass = profile.mass
	engine_force_value = profile.force
	max_forward_speed = profile.speed
	linear_damp = 0.08
	angular_damp = 0.6
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.38, 0.1)
	var bounds := model.transform * model.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = Vector3(bounds.size.x * 0.86, bounds.size.y * 0.78, bounds.size.z * 0.91)
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position = bounds.get_center()
	var wheel_names := ["Wheel1", "Wheel2", "Wheel3", "Wheel4"]
	var suffixes := ["_Wheel_fl", "_Wheel_rl", "_Wheel_fr", "_Wheel_rr"]
	var front_axle := -INF
	var rear_axle := INF
	for part in model.get_children():
		if part is MeshInstance3D and "_Wheel_" in str(part.name):
			var center: Vector3 = model.transform * part.transform * part.get_aabb().get_center()
			front_axle = maxf(front_axle, center.z)
			rear_axle = minf(rear_axle, center.z)
	var front_load := clampf((center_of_mass.z - rear_axle) / (front_axle - rear_axle), 0.3, 0.7)
	for i in wheel_names.size():
		var wheel := get_node(wheel_names[i]) as VehicleWheel3D
		# VehicleWheel3D caches its suspension connection when it enters the tree.
		# Re-enter only after the model-specific mount is configured.
		remove_child(wheel)
		for old_visual in wheel.get_children(): old_visual.free()
		wheel.use_as_steering = i == 0 or i == 2
		wheel.use_as_traction = "UAZ" in vehicle_scene.resource_path or i == 1 or i == 3
		wheel.wheel_rest_length = 0.20
		wheel.suspension_travel = 0.15
		wheel.suspension_stiffness = 32.0
		wheel.suspension_max_force = mass * 9.81 * 0.8
		wheel.damping_compression = 0.55
		wheel.damping_relaxation = 0.85
		wheel.wheel_friction_slip = 2.0
		wheel.wheel_roll_influence = 0.12
		for part in model.get_children():
			if part is MeshInstance3D and str(part.name).ends_with(suffixes[i]):
				# Mesh pivots sit on the inner wheel face, not at the tire centre.
				# Rebase around the AABB centre while preserving the original mesh basis.
				var original: Transform3D = model.transform * part.transform
				var tire_center: Vector3 = original * part.get_aabb().get_center()
				var transformed_bounds: AABB = original * part.get_aabb()
				var visible_radius := maxf(transformed_bounds.size.y, transformed_bounds.size.z) * 0.5
				var axle_load := front_load if wheel.use_as_steering else 1.0 - front_load
				var static_sag := 9.81 * axle_load / (2.0 * wheel.suspension_stiffness)
				# Godot extends the suspension ray at its source by one radius, while
				# normalizing its hit distance by rest_length + radius. Compensate
				# the resulting tire sink without scaling or moving the original mesh.
				var coefficient := wheel.wheel_rest_length - static_sag - visible_radius
				wheel.wheel_radius = (-coefficient + sqrt(coefficient * coefficient + 4.0 * visible_radius * wheel.wheel_rest_length)) * 0.5
				wheel_visible_radii[wheel.name] = visible_radius
				wheel.position = tire_center + Vector3.UP * (wheel.wheel_rest_length - static_sag)
				wheel_reference_centers[wheel.name] = tire_center
				part.reparent(wheel, false)
				part.transform = Transform3D(original.basis, original.origin - tire_center)
				wheel_visuals.append({"wheel": wheel, "mesh": part, "transform": part.transform, "radius": visible_radius, "half_width": transformed_bounds.size.x * 0.5})
				break
		add_child(wheel)
	for part in model.get_children():
		if part is MeshInstance3D and str(part.name).ends_with("_SteeringW"):
			steering_mesh = part
			steering_reference = part.transform
			break
	# Give painted body panels a restrained clear-coat response to reflection probes.
	for index in model.mesh.get_surface_count():
		var source: Material = model.get_active_material(index)
		if source is StandardMaterial3D:
			var finish := source.duplicate() as StandardMaterial3D
			finish.metallic = 0.18
			finish.roughness = 0.34
			finish.clearcoat_enabled = true
			finish.clearcoat = 0.5
			finish.clearcoat_roughness = 0.2
			model.set_surface_override_material(index, finish)
	var driver := Vector3(0.38, minf(bounds.end.y - 0.22, 1.36), 0.05)
	if is_instance_valid(steering_mesh): driver = steering_mesh.position + Vector3(0, 0.27, -0.42)
	$InteriorCameraPosition.position = driver
	$CameraBase.position = Vector3(0, minf(bounds.end.y, 1.65), 0)
	var camera := $CameraBase/Camera3D
	camera.min_distance = maxf(5.6, bounds.size.z * 1.1)
	camera.max_distance = camera.min_distance + 2
	camera.height = 2.0
	camera.far = 1500
	$TopDownCameraPosition.position = Vector3(0, 24, 0)
	$CPUParticles3D.position = Vector3(0.4, 0.26, bounds.position.z)
	$CPUParticles3D.amount = 30
	$BlobShadow.size = Vector3(bounds.size.x + 0.4, 4, bounds.size.z + 0.4)
	var lamp_height: float = model.get_meta("headlight_height", 0.7)
	$HeadlightL.position = Vector3(bounds.size.x * 0.31, lamp_height, bounds.end.z)
	$HeadlightR.position = Vector3(-bounds.size.x * 0.31, lamp_height, bounds.end.z)
	_build_cabin(driver, bounds)
	camera.update_camera()
	super._ready()


func _align_wheel_visuals() -> void:
	# The static ray radius is calibrated above. Under braking or a bump the
	# native solver still changes its radius error with suspension compression.
	# Correct that small visual remainder along the actual road contact normal.
	for visual in wheel_visuals:
		var wheel: VehicleWheel3D = visual.wheel
		var mesh: MeshInstance3D = visual.mesh
		mesh.transform = visual.transform
		if not wheel.is_in_contact(): continue
		var normal := wheel.get_contact_normal().normalized()
		var axle_tilt := absf(wheel.global_basis.x.normalized().dot(normal))
		var support: float = visual.radius * sqrt(maxf(0.0, 1.0 - axle_tilt * axle_tilt)) + visual.half_width * axle_tilt
		var gap := (wheel.global_position - wheel.get_contact_point()).dot(normal) - support
		if gap < TIRE_CONTACT_CLEARANCE:
			mesh.global_position += normal * (TIRE_CONTACT_CLEARANCE - gap)


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_align_wheel_visuals()
	if is_instance_valid(steering_mesh):
		steering_mesh.transform = steering_reference * Transform3D(Basis(Vector3.UP, -steering * 2.5), Vector3.ZERO)
	dashboard_tick -= delta
	if dashboard_tick <= 0 and is_instance_valid(dashboard_speed):
		dashboard_tick = 0.1
		dashboard_speed.text = "%03d km/h" % roundi(linear_velocity.length() * 3.6)


func _profile(path: String) -> Dictionary:
	if "VAZ2101" in path: return {"mass": 1000.0, "force": 1400.0, "speed": 37.0}
	if "VAZ2105" in path: return {"mass": 1050.0, "force": 1500.0, "speed": 40.0}
	if "VAZ2106" in path: return {"mass": 1050.0, "force": 1600.0, "speed": 42.0}
	if "UAZ469" in path: return {"mass": 1650.0, "force": 1100.0, "speed": 34.0}
	if "UAZ452" in path: return {"mass": 1900.0, "force": 1200.0, "speed": 32.0}
	if "Muscle" in path: return {"mass": 1650.0, "force": 3000.0, "speed": 54.0}
	if "Ambo" in path: return {"mass": 2550.0, "force": 3300.0, "speed": 37.0}
	if "Van" in path: return {"mass": 2050.0, "force": 2600.0, "speed": 38.0}
	if "Small" in path: return {"mass": 1050.0, "force": 1500.0, "speed": 39.0}
	if "Medium" in path: return {"mass": 1300.0, "force": 1850.0, "speed": 42.0}
	if "Police" in path: return {"mass": 1550.0, "force": 2600.0, "speed": 51.0}
	return {"mass": 1450.0, "force": 2200.0, "speed": 45.0}


func _build_cabin(driver: Vector3, bounds: AABB) -> void:
	cabin = Node3D.new()
	cabin.name = "CabinDetails"
	add_child(cabin)
	var dash_y := driver.y - 0.31
	var dash_z := driver.z + 0.82
	_cabin_part(Vector3(0, dash_y - 0.1, dash_z), Vector3(bounds.size.x * 0.72, 0.18, 0.34), Color("273039"))
	_cabin_part(Vector3(driver.x, dash_y, dash_z - 0.19), Vector3(0.42, 0.18, 0.035), Color("101d22"))
	_cabin_part(Vector3(0, dash_y - 0.22, dash_z - 0.13), Vector3(0.26, 0.32, 0.12), Color("303a42"))
	_cabin_part(Vector3(0, dash_y - 0.16, dash_z - 0.2), Vector3(0.2, 0.09, 0.015), Color("618e91"))
	for x in [-0.4, 0.4]:
		_cabin_part(Vector3(x, 0.52, driver.z - 0.2), Vector3(0.48, 0.18, 0.6), Color("343c43"))
		_cabin_part(Vector3(x, 0.83, driver.z - 0.5), Vector3(0.49, 0.6, 0.16), Color("343c43"))
		_cabin_part(Vector3(x, 1.17, driver.z - 0.49), Vector3(0.26, 0.2, 0.14), Color("343c43"))
	dashboard_speed = Label3D.new()
	dashboard_speed.position = Vector3(driver.x, dash_y + 0.01, dash_z - 0.214)
	dashboard_speed.rotation.y = PI
	dashboard_speed.font_size = 44
	dashboard_speed.pixel_size = 0.0011
	dashboard_speed.modulate = Color("a4e0c7")
	dashboard_speed.outline_size = 0
	dashboard_speed.text = "000 km/h"
	cabin.add_child(dashboard_speed)
	cabin.visible = false


func _cabin_part(p: Vector3, size: Vector3, color: Color) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	part.mesh = mesh
	part.material_override = material
	part.position = p
	cabin.add_child(part)


func set_cabin_view(value: bool) -> void:
	if is_instance_valid(cabin): cabin.visible = value


func _remove_static_bodies(node: Node) -> void:
	for child in node.get_children():
		if child is CollisionObject3D: child.free()
		else: _remove_static_bodies(child)
