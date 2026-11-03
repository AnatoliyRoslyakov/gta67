extends RefCounted
# UAZ-only hover controller. Forces keep the rigid body, collisions and damage active.
var car: VehicleBody3D
var enabled := false
var amount := 0.0
var front_visuals: Array[Dictionary] = []
var rings: Array[MeshInstance3D] = []
var lights: Array[SpotLight3D] = []
var glow: Decal
var neon: StandardMaterial3D
var ray: PhysicsRayQueryParameters3D
var gravity := 9.8

func setup(vehicle: VehicleBody3D, visuals: Array[Dictionary]) -> void:
	car = vehicle
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	ray = PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1, [car.get_rid()])
	neon = StandardMaterial3D.new()
	neon.albedo_color = Color("19bfff")
	neon.emission_enabled = true
	neon.emission = Color("00bfff")
	neon.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for visual in visuals:
		if not visual.wheel.use_as_steering: continue
		front_visuals.append(visual)
		# Both rim faces and the tread edge remain visible when wheels turn horizontal.
		for band in [Vector3(-0.19, 0.184, 0.211), Vector3(0.19, 0.184, 0.211), Vector3(0, 0.382, 0.397)]:
			var ring := MeshInstance3D.new()
			var mesh := TorusMesh.new()
			mesh.inner_radius = band.y
			mesh.outer_radius = band.z
			mesh.rings = 24
			mesh.ring_segments = 8
			ring.mesh = mesh
			ring.material_override = neon
			ring.rotation.z = PI * 0.5
			ring.position.x = band.x
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.mesh.add_child(ring)
			ring.visible = false
			rings.append(ring)
	for z in [-0.85, 0.85]:
		var light := SpotLight3D.new()
		light.name = "HoverUnderglow"
		light.position = Vector3(0, 0.10, z)
		light.rotation.x = -PI * 0.5
		light.light_color = Color("00bfff")
		light.spot_range = 4.5
		light.spot_angle = 68
		light.shadow_enabled = false
		light.visible = false
		car.add_child(light)
		lights.append(light)
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var distance := Vector2((x - 31.5) / 31.5, (y - 31.5) / 31.5).length()
				var strength := pow(maxf(0.0, 1.0 - distance), 1.7)
				image.set_pixel(x, y, Color(0, strength * 0.55, strength, strength))
		image.generate_mipmaps()
		glow = Decal.new()
		glow.name = "HoverGroundGlow"
		glow.texture_emission = ImageTexture.create_from_image(image)
		glow.albedo_mix = 0.0
		glow.size = Vector3(3.4, 4.0, 5.0)
		glow.position.y = -0.8
		glow.normal_fade = 0.75
		glow.visible = false
		car.add_child(glow)

func toggle() -> void:
	if car.controllable and car.drive_condition > 0:
		enabled = not enabled
		car.sleeping = false

func update(delta: float) -> void:
	if not car.controllable or car.drive_condition <= 0: enabled = false
	amount = move_toward(amount, 1.0 if enabled else 0.0, delta / 0.9)
	var blend := smoothstep(0.0, 1.0, amount)
	for ring in rings: ring.visible = amount > 0.01
	neon.emission_energy_multiplier = blend * 4.0
	for light in lights:
		light.visible = amount > 0.01
		light.light_energy = 3.5 * blend
	if is_instance_valid(glow):
		glow.visible = amount > 0.01
		glow.emission_energy = blend * 1.4
	if amount <= 0: return
	# Rebase on the wheel's current suspension transform every frame. This overrides
	# rolling only during folding and restores normal wheels exactly on landing.
	for visual in front_visuals:
		var center: Vector3 = car.wheel_reference_centers[visual.wheel.name]
		var side := signf(center.x)
		var basis: Basis = Basis(Vector3.BACK, -side * PI * 0.5) * visual.transform.basis
		var target := car.global_transform * Transform3D(basis, center + Vector3(side * 0.12, -0.06, 0))
		visual.mesh.global_transform = visual.mesh.global_transform.interpolate_with(target, blend)
	car.engine_force *= 1.0 - blend
	car.brake *= 1.0 - blend
	car.constant_force *= 1.0 - blend
	ray.from = car.global_position + Vector3.UP * 0.30
	ray.to = car.global_position - Vector3.UP * 4.0
	var hit := car.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y < 0.45: return
	# Spring-damper suspension maintains a road-relative height, rather than locking Y.
	var height: float = car.global_position.y - hit.position.y
	var lift := clampf(gravity + (1.05 - height) * 24.0 - car.linear_velocity.y * 8.0, 0.0, gravity + 20.0)
	car.apply_central_force(Vector3.UP * car.mass * lift * blend)
	var velocity := Vector3(car.linear_velocity.x, 0, car.linear_velocity.z)
	var forward := Vector3(car.global_basis.z.x, 0, car.global_basis.z.z).normalized()
	var throttle := Input.get_axis("reverse", "accelerate") if car.controllable else 0.0
	var braking: bool = Input.is_physical_key_pressed(KEY_SPACE) or not car.controllable
	var acceleration := forward * throttle * 6.0 * clampf(car.drive_condition, 0.0, 1.0)
	acceleration -= velocity * (5.0 if braking else (1.8 if absf(throttle) < 0.01 else 0.17))
	if velocity.length() > 34.0: acceleration -= velocity.normalized() * (velocity.length() - 34.0) * 3.0
	car.apply_central_force(acceleration * car.mass * blend)
	var turn := Input.get_axis("turn_right", "turn_left") if car.controllable else 0.0
	var desired_yaw := turn * lerpf(0.65, 0.35, clampf(velocity.length() / 30.0, 0, 1))
	var upright := car.global_basis.y.cross(Vector3.UP)
	var torque := upright * 22.0 - Vector3(car.angular_velocity.x, 0, car.angular_velocity.z) * 6.0
	torque.y = (desired_yaw - car.angular_velocity.y) * 4.0
	car.apply_torque(torque * car.mass * blend)
