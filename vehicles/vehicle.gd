extends VehicleBody3D

@export var engine_force_value := 1800.0
@export var max_forward_speed := 44.0
@export var max_reverse_speed := 9.0
@export var controllable := true
var turbometer: Range
var turbo_animator: AnimationPlayer
var headlights_active := false
var turbo_active := false
var previous_speed := 0.0
var desired_engine_pitch := 0.6
var is_compatibility := false
var impact_cooldown := 0.0


func _ready() -> void:
	is_compatibility = RenderingServer.get_current_rendering_method() == "gl_compatibility"
	set_controlled(controllable)


func set_controlled(value: bool) -> void:
	controllable = value
	engine_force = 0.0
	brake = 0.0 if value else 35.0 * mass / 1400.0
	constant_force = Vector3.ZERO
	turbo_active = false
	if not is_inside_tree(): return
	var camera := get_node_or_null("CameraBase/Camera3D")
	if camera:
		camera.set_process_input(value)
		camera.set_physics_process(value)
		if value:
			camera.update_camera()
			camera.make_current()
		elif camera.is_current():
			camera.clear_current(false)
	if value:
		$EngineSound.play()
		$AudioListener3D.make_current()
	else:
		$EngineSound.stop()
		$AudioListener3D.clear_current()
	$CPUParticles3D.emitting = value


func _physics_process(delta: float) -> void:
	impact_cooldown = maxf(impact_cooldown - delta, 0.0)
	if not controllable:
		engine_force = 0
		brake = 35.0 * mass / 1400.0
		constant_force = Vector3.ZERO
		return
	var speed := linear_velocity.length()
	var forward_speed := linear_velocity.dot(global_basis.z)
	var steer_limit := lerpf(0.52, 0.15, clampf(speed / 32.0, 0, 1))
	var steer_target := Input.get_axis("turn_right", "turn_left") * steer_limit
	steering = move_toward(steering, steer_target, delta * (1.8 if absf(steer_target) > 0.01 else 2.7))
	var throttle := Input.get_action_strength("accelerate")
	var reverse := Input.get_action_strength("reverse")
	var hard_brake := Input.is_physical_key_pressed(KEY_SPACE)
	brake = 0
	engine_force = 0
	var brake_force := 32.0 * mass / 1400.0
	if hard_brake:
		brake = brake_force * 1.25
	elif reverse > 0:
		if forward_speed > 0.6:
			brake = brake_force * reverse
		elif forward_speed > -max_reverse_speed:
			engine_force = -engine_force_value * 0.6 * reverse
	elif throttle > 0:
		if forward_speed < -0.6:
			brake = brake_force * throttle
		else:
			var power_falloff := 1.0 - smoothstep(max_forward_speed * 0.7, max_forward_speed, forward_speed)
			engine_force = engine_force_value * throttle * power_falloff
	elif speed < 0.25:
		brake = 3.0
	var boost_pressed := Input.is_action_pressed("boost") and throttle > 0 and not hard_brake
	var boost_available := is_instance_valid(turbometer) and turbometer.value > 0
	var new_boost := boost_pressed and boost_available
	if new_boost != turbo_active and is_instance_valid(turbo_animator):
		turbo_animator.play("TURBO" if new_boost else "Idle")
	turbo_active = new_boost
	if is_instance_valid(turbometer):
		turbometer.value += -delta * 2.0 if turbo_active else delta * 0.7
	if turbo_active: engine_force *= 1.4
	# Grounded aerodynamic load, capped to prevent suspension bottoming at speed.
	var grounded := false
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact(): grounded = true
	constant_force = -global_basis.y * minf(speed * speed * 2.5, mass * 3.0) if grounded else Vector3.ZERO
	desired_engine_pitch = 0.55 + minf(speed / 30.0, 1.3) + throttle * 0.15
	$EngineSound.pitch_scale = lerpf($EngineSound.pitch_scale, desired_engine_pitch, 1 - exp(-delta * 5))
	if previous_speed - speed > 2.5 and impact_cooldown <= 0:
		$ImpactSound.play()
		impact_cooldown = 0.3
		for joypad in Input.get_connected_joypads(): Input.start_joy_vibration(joypad, 0, 0.35, 0.12)
	previous_speed = speed


func _input(event: InputEvent) -> void:
	if not controllable: return
	if event.is_action_pressed("toggle_headlights"): toggle_headlights()
	if event.is_action_pressed("honk"): $HonkSound.play()


func toggle_headlights() -> void:
	set_headlights(not headlights_active)


func set_headlights(value: bool) -> void:
	headlights_active = value
	for node: Light3D in [$HeadlightL, $HeadlightR]:
		node.visible = value
		node.light_energy = (1.5 if is_compatibility else 3.0) if value else 0.0
