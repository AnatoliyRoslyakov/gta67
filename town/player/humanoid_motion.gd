extends RefCounted

var skeleton: Skeleton3D
var neutral: Dictionary = {}
var axes: Dictionary = {}
var bones: Dictionary = {}
var original_global: Dictionary = {}
var limb_lengths: Dictionary = {}
var finger_directions: Dictionary = {}
var inverse_bone_basis: Dictionary = {}
var phase := 0.0
var blend := 0.0
var weapon_blend := 0.0
var base_position := Vector3.ZERO
var hip_position := Vector3.ZERO
var foot_height := 0.055
var leg_lengths: Dictionary = {}
var _foot_in_stance := {"Left": true, "Right": true}
var _foot_locked := {"Left": false, "Right": false}
var _foot_lock_position: Dictionary = {}
var _last_rig_origin := Vector3.ZERO

func bind(rig: Skeleton3D) -> void:
	skeleton = rig
	base_position = rig.position
	_last_rig_origin = rig.global_position
	# Extracted POLYGON meshes carry weights and a Skin, but their skeleton
	# NodePath is empty. Explicitly reconnect it after detaching the imported rig.
	for node in rig.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.skin != null:
			mesh.skeleton = mesh.get_path_to(rig)
	for index in rig.get_bone_count():
		var bone_name := rig.get_bone_name(index)
		bones[bone_name] = index
		neutral[bone_name] = rig.get_bone_pose_rotation(index)
		original_global[bone_name] = rig.get_bone_global_pose(index)
		inverse_bone_basis[bone_name] = original_global[bone_name].basis.orthonormalized().inverse()
		axes[bone_name] = inverse_bone_basis[bone_name] * Vector3.RIGHT
	hip_position = rig.get_bone_pose_position(bones["Hips"])
	foot_height = original_global["LeftFoot"].origin.y
	for side in ["Left", "Right"]:
		var shoulder: Vector3 = original_global[side + "UpperArm"].origin
		var elbow: Vector3 = original_global[side + "LowerArm"].origin
		var wrist: Vector3 = original_global[side + "Hand"].origin
		limb_lengths[side] = Vector2(shoulder.distance_to(elbow), elbow.distance_to(wrist))
		var hip: Vector3 = original_global[side + "UpperLeg"].origin
		var knee: Vector3 = original_global[side + "LowerLeg"].origin
		var ankle: Vector3 = original_global[side + "Foot"].origin
		leg_lengths[side] = Vector2(hip.distance_to(knee), knee.distance_to(ankle))
		if bones.has(side + "MiddleProximal"):
			finger_directions[side] = (original_global[side + "MiddleProximal"].origin - wrist).normalized()
	# The supplied FBX has a static T-pose, not a walk clip. Solve arms down
	# from measured joint lengths; rotating a T-pose around X only twists it.
	update(0.0, 0.0)

func update(delta: float, speed: float, running := false, armed := false, aim_pitch := 0.0, sighting := false, grounded := true, reloading := false, travel := Vector2(0.0, 1.0)) -> void:
	if not is_instance_valid(skeleton): return
	blend = move_toward(blend, clampf(speed / 0.45, 0.0, 1.0), delta * 5.0)
	weapon_blend = move_toward(weapon_blend, 1.0 if armed else 0.0, delta * 6.0)
	var run_mix := clampf((speed - 2.0) / 3.0, 0.0, 1.0) if running else 0.0
	var step_length := lerpf(0.72, 0.82, run_mix)
	var stance_fraction := lerpf(0.60, 0.28, run_mix)
	# A planted foot travels back through exactly the distance the body advances.
	# Cadence follows speed and leg reach instead of a fixed sine-wave frequency.
	phase += delta * speed * stance_fraction / maxf(step_length * blend, 0.08) * TAU
	var travel_direction := Vector3(travel.x, 0.0, travel.y).normalized() if travel.length_squared() > 0.01 else Vector3.BACK
	skeleton.position = base_position
	skeleton.set_bone_pose_position(bones["Hips"], hip_position)
	_pose("Spine", lerpf(0.025, 0.12, run_mix) * blend - aim_pitch * 0.12 * weapon_blend)
	_pose("Head", -aim_pitch * 0.18 * weapon_blend + sin(phase * 0.25) * 0.006)
	var rig_displacement := skeleton.global_position - _last_rig_origin
	# Curbs and teleports change the support plane without requiring ground raycasts.
	if rig_displacement.length_squared() > 4.0 or absf(rig_displacement.y) > 0.12:
		_clear_foot_locks()
	_last_rig_origin = skeleton.global_position
	var left_wave := cos(phase)
	var right_wave := -left_wave
	if grounded:
		var targets := {}
		for side in ["Left", "Right"]:
			var cycle := fposmod(phase / TAU + (0.5 if side == "Right" else 0.0), 1.0)
			targets[side] = _foot_target(side, cycle, stance_fraction, step_length, run_mix, travel_direction)
		var pelvis_offset := _support_pelvis(targets, stance_fraction, run_mix)
		skeleton.set_bone_pose_position(bones["Hips"], hip_position + pelvis_offset)
		for side in ["Left", "Right"]:
			var upper: String = side + "UpperLeg"
			var pole: Vector3 = original_global[upper].origin + Vector3(0.04 if side == "Left" else -0.04, -0.25, 0.75)
			_solve_limb(upper, side + "LowerLeg", side + "Foot", targets[side], pole, leg_lengths[side])
			_set_global_basis(side + "Foot", original_global[side + "Foot"].basis)
		left_wave = clampf((targets.Left - original_global["LeftFoot"].origin).dot(travel_direction) / (step_length * 0.5), -1.0, 1.0)
		right_wave = clampf((targets.Right - original_global["RightFoot"].origin).dot(travel_direction) / (step_length * 0.5), -1.0, 1.0)
	else:
		_clear_foot_locks()
		_pose("LeftUpperLeg", -0.25)
		_pose("RightUpperLeg", 0.1)
		_pose("LeftLowerLeg", 0.65)
		_pose("RightLowerLeg", 0.45)
		for side in ["Left", "Right"]:
			_set_global_basis(side + "Foot", original_global[side + "Foot"].basis)
	var arm_stride := lerpf(0.4, 0.67, run_mix) * blend
	_animate_arm("Left", left_wave, arm_stride, aim_pitch, sighting, reloading)
	_animate_arm("Right", right_wave, arm_stride, aim_pitch, sighting, reloading)

func ride(left_grip: Vector3, right_grip: Vector3) -> void:
	skeleton.position = base_position
	for bone in bones: skeleton.set_bone_pose_rotation(bones[bone], neutral[bone])
	skeleton.set_bone_pose_position(bones["Hips"], hip_position)
	_pose("Spine", 0.18)
	var world_to_rig := skeleton.global_transform.affine_inverse()
	for side in ["Left", "Right"]:
		var sign_x := 1.0 if side == "Left" else -1.0
		var foot := hip_position + Vector3(sign_x * 0.48, -0.71, 0.23)
		var knee := hip_position + Vector3(sign_x * 0.60, -0.18, 0.70)
		_solve_limb(side + "UpperLeg", side + "LowerLeg", side + "Foot", foot, knee, leg_lengths[side])
		_set_global_basis(side + "Foot", original_global[side + "Foot"].basis)
		var grip: Vector3 = world_to_rig * (left_grip if side == "Left" else right_grip)
		# Place the closed palm on the top of the eye.
		var wrist := grip + Vector3(sign_x * 0.015, 0.035, -0.045)
		_solve_arm(side, wrist, hip_position + Vector3(sign_x * 0.60, 0.12, 0.12))
		if finger_directions.has(side):
			_set_global_basis(side + "Hand", Basis(Quaternion(finger_directions[side], Vector3.BACK)) * original_global[side + "Hand"].basis)
		for finger in ["Index", "Middle", "Ring", "Little"]:
			for joint in ["Proximal", "Intermediate", "Distal"]:
				_pose(side + finger + joint, 0.85)

func _foot_target(side: String, cycle: float, stance_fraction: float, step_length: float, run_mix: float, direction: Vector3) -> Vector3:
	var neutral_foot: Vector3 = original_global[side + "Foot"].origin
	var in_stance := cycle < stance_fraction
	_foot_in_stance[side] = in_stance
	var stride_offset: float
	var lift := 0.0
	if in_stance:
		stride_offset = step_length * (0.5 - cycle / stance_fraction)
	else:
		var swing := (cycle - stance_fraction) / (1.0 - stance_fraction)
		stride_offset = step_length * (smoothstep(0.0, 1.0, swing) - 0.5)
		lift = sin(swing * PI) * lerpf(0.10, 0.27, run_mix)
	var target := neutral_foot + (direction * stride_offset + Vector3.UP * lift) * blend
	var can_lock := in_stance and blend > 0.98 and skeleton.global_basis.y.dot(Vector3.UP) > 0.85
	if can_lock:
		if not _foot_locked[side]:
			_foot_lock_position[side] = skeleton.global_transform * target
		_foot_locked[side] = true
		return skeleton.global_transform.affine_inverse() * _foot_lock_position[side]
	_foot_locked[side] = false
	return target

func _support_pelvis(targets: Dictionary, stance_fraction: float, run_mix: float) -> Vector3:
	var offset := Vector3(sin(phase) * 0.012 * blend, 0.0, 0.0)
	var supported := false
	for side in ["Left", "Right"]:
		if not _foot_in_stance[side]: continue
		supported = true
		var hip: Vector3 = original_global[side + "UpperLeg"].origin + offset
		var foot: Vector3 = targets[side]
		var lengths: Vector2 = leg_lengths[side]
		var reach := (lengths.x + lengths.y) * 0.985
		var horizontal := Vector2(foot.x - hip.x, foot.z - hip.z).length_squared()
		var height := sqrt(maxf(0.01, reach * reach - horizontal))
		offset.y = minf(offset.y, foot.y + height - original_global[side + "UpperLeg"].origin.y)
	if not supported and stance_fraction < 0.5:
		var flight := (fposmod(phase / TAU, 0.5) - stance_fraction) / (0.5 - stance_fraction)
		offset.y = sin(clampf(flight, 0.0, 1.0) * PI) * 0.035 * run_mix
	offset.y = clampf(offset.y, -0.19, 0.04) * blend
	return offset

func _clear_foot_locks() -> void:
	for side in ["Left", "Right"]:
		_foot_locked[side] = false
		_foot_in_stance[side] = false

func _animate_arm(side: String, leg_wave: float, stride: float, aim_pitch: float, sighting: bool, reloading: bool) -> void:
	var sign_x := 1.0 if side == "Left" else -1.0
	var idle_target := Vector3(sign_x * 0.245, 0.82 + absf(leg_wave) * 0.025 * blend, -leg_wave * stride * 0.5)
	var gun_target := Vector3(0.005 if side == "Left" else -0.085, 1.31 if sighting else 1.17, 0.43 if side == "Left" else 0.40)
	if reloading:
		gun_target = Vector3(0.025 if side == "Left" else -0.08, 1.04, 0.30)
	var aim_basis := Basis(Vector3.RIGHT, -aim_pitch)
	gun_target = Vector3(0.0, 1.38, 0.0) + aim_basis * (gun_target - Vector3(0.0, 1.38, 0.0))
	var target := idle_target.lerp(gun_target, weapon_blend)
	var pole := Vector3(sign_x * 0.50, 1.03, -0.08).lerp(Vector3(sign_x * 0.42, 1.03, 0.16), weapon_blend)
	_solve_arm(side, target, pole)
	# Give both palms a consistent orientation rather than inheriting elbow roll.
	var hand := side + "Hand"
	var finger := side + "MiddleProximal"
	if bones.has(finger):
		var authored_direction: Vector3 = finger_directions[side]
		var desired_direction := Vector3(0.0, -1.0, 0.12).normalized().slerp(aim_basis * Vector3.BACK, weapon_blend)
		_set_global_basis(hand, Basis(Quaternion(authored_direction, desired_direction)) * original_global[hand].basis)

func _solve_arm(side: String, target: Vector3, pole: Vector3) -> void:
	_solve_limb(side + "UpperArm", side + "LowerArm", side + "Hand", target, pole, limb_lengths[side])

func _solve_limb(upper: String, lower: String, tip: String, target: Vector3, pole: Vector3, lengths: Vector2) -> void:
	# The same analytic two-bone solution serves hands and planted feet.
	for bone in [upper, lower, tip]: skeleton.set_bone_pose_rotation(bones[bone], neutral[bone])
	var origin: Vector3 = skeleton.get_bone_global_pose(bones[upper]).origin
	var offset := target - origin
	var distance := clampf(offset.length(), 0.05, lengths.x + lengths.y - 0.002)
	var direction := offset.normalized()
	var bend := pole - origin
	bend = (bend - direction * bend.dot(direction)).normalized()
	var along := (lengths.x * lengths.x - lengths.y * lengths.y + distance * distance) / (2.0 * distance)
	var height := sqrt(maxf(0.0, lengths.x * lengths.x - along * along))
	var joint := origin + direction * along + bend * height
	_aim_bone(upper, lower, joint)
	_aim_bone(lower, tip, origin + direction * distance)

func _aim_bone(bone: String, child: String, target: Vector3) -> void:
	var transform := skeleton.get_bone_global_pose(bones[bone])
	var child_position := skeleton.get_bone_global_pose(bones[child]).origin
	var from := (child_position - transform.origin).normalized()
	var to := (target - transform.origin).normalized()
	_set_global_basis(bone, Basis(Quaternion(from, to)) * transform.basis)

func _set_global_basis(bone: String, desired_basis: Basis) -> void:
	var index: int = bones[bone]
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(index, (parent_basis.inverse() * desired_basis).orthonormalized().get_rotation_quaternion())

func _pose(bone: String, angle: float) -> void:
	if bones.has(bone): skeleton.set_bone_pose_rotation(bones[bone], neutral[bone] * Quaternion(axes[bone].normalized(), angle))
