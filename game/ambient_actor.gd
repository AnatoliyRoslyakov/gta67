extends CharacterBody3D

const Visual = preload("res://game/car_visual.gd")
const Person = preload("res://game/character.gd")
var route := PackedVector3Array()
var target_index := 0
var speed := 8.0
var police := false
var pedestrian := false
var tint := Color("9db8b3")
var model: Node3D
var stun := 0.0
var elapsed := 0.0


func _ready() -> void:
	model = Person.make_person(Color("b88871"), tint, Color("485668")) if pedestrian else Visual.build(tint, "police" if police else "sedan")
	add_child(model)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.8, 0.6) if pedestrian else Vector3(1.8, 1.1, 4.2)
	collider.position.y = 0.9 if pedestrian else 0.8
	collider.shape = shape
	add_child(collider)
	add_to_group("pedestrians" if pedestrian else "traffic")
	if route.size() > 1: look_at(Vector3(route[1].x, position.y, route[1].z), Vector3.UP, not pedestrian)


func _physics_process(delta: float) -> void:
	elapsed += delta
	stun = maxf(stun - delta, 0)
	if police:
		model.get_node("RedSiren").visible = sin(elapsed * 14) > -0.2
		model.get_node("BlueSiren").visible = sin(elapsed * 14) < 0.2
	if route.is_empty() or stun > 0:
		velocity.x = 0
		velocity.z = 0
	else:
		var target := route[target_index]
		var offset := Vector3(target.x - global_position.x, 0, target.z - global_position.z)
		if offset.length() < (1.0 if pedestrian else 3.0):
			target_index = (target_index + 1) % route.size()
		else:
			var direction := offset.normalized()
			var target_yaw: float = atan2(direction.x, direction.z) + (PI if pedestrian else 0.0)
			rotation.y = lerp_angle(rotation.y, target_yaw, minf(delta * 5, 1))
			var blocked := false
			if not pedestrian:
				var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, global_position + Vector3.UP + direction * 6, 1, [get_rid()])
				blocked = not get_world_3d().direct_space_state.intersect_ray(query).is_empty()
			var target_velocity: Vector3 = direction * (0.0 if blocked else speed)
			velocity.x = move_toward(velocity.x, target_velocity.x, delta * 10)
			velocity.z = move_toward(velocity.z, target_velocity.z, delta * 10)
	if not is_on_floor(): velocity.y -= delta * 20
	else: velocity.y = 0
	move_and_slide()
	if pedestrian:
		var stride := sin(elapsed * 5) * minf(velocity.length() * 0.3, 0.5)
		model.get_node("LeftLeg").rotation.x = stride
		model.get_node("RightLeg").rotation.x = -stride


func knock_down() -> void:
	stun = 5
	model.rotation.z = 1.3
	var tween := create_tween()
	tween.tween_interval(3)
	tween.tween_property(model, "rotation:z", 0, 1.5)
