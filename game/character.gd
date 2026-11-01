extends CharacterBody3D

const Visual = preload("res://game/car_visual.gd")
var active := true
var pivot: Node3D
var camera: Camera3D
var model: Node3D
var left_leg: Node3D
var right_leg: Node3D
var stride := 0.0


func _ready() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = 0.9
	add_child(collider)
	model = make_person(Color("d8a991"), Color("e9ddd0"), Color("41687b"))
	Visual.part(model, Vector3(0.37, 0.91, -0.23), Vector3(0.09, 0.13, 0.32), Color("4e575b"))
	add_child(model)
	left_leg = model.get_node("LeftLeg")
	right_leg = model.get_node("RightLeg")
	pivot = Node3D.new()
	pivot.position.y = 1.5
	add_child(pivot)
	var arm := SpringArm3D.new()
	arm.spring_length = 5.5
	arm.rotation.x = -0.15
	arm.margin = 0.25
	arm.add_excluded_object(get_rid())
	pivot.add_child(arm)
	camera = Camera3D.new()
	camera.fov = 72
	camera.far = 1800
	arm.add_child(camera)
	camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if active and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pivot.rotation.y -= event.relative.x * 0.0025
		var arm := pivot.get_child(0) as SpringArm3D
		arm.rotation.x = clampf(arm.rotation.x - event.relative.y * 0.0025, -0.8, 0.45)


func _physics_process(delta: float) -> void:
	if not active: return
	var input := Input.get_vector("turn_left", "turn_right", "accelerate", "reverse")
	var direction := pivot.basis * Vector3(input.x, 0, input.y)
	var speed := 8.0 if Input.is_action_pressed("boost") else 4.5
	velocity.x = move_toward(velocity.x, direction.x * speed, delta * 28)
	velocity.z = move_toward(velocity.z, direction.z * speed, delta * 28)
	if not is_on_floor(): velocity.y -= 22 * delta
	elif Input.is_action_just_pressed("jump"): velocity.y = 7
	move_and_slide()
	if direction.length() > 0.05:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-direction.x, -direction.z), delta * 12)
	stride += delta * Vector2(velocity.x, velocity.z).length() * 2.2
	var swing := sin(stride) * minf(Vector2(velocity.x, velocity.z).length() / 8, 0.7)
	left_leg.rotation.x = swing
	right_leg.rotation.x = -swing


static func make_person(skin: Color, shirt: Color, pants: Color) -> Node3D:
	var model_root := Node3D.new()
	Visual.part(model_root, Vector3(0, 1.13, 0), Vector3(0.56, 0.65, 0.3), shirt)
	Visual.part(model_root, Vector3(0, 1.65, 0), Vector3(0.34, 0.4, 0.33), skin)
	Visual.part(model_root, Vector3(0, 1.87, 0.02), Vector3(0.36, 0.13, 0.35), Color("483d39"))
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.name = "LeftLeg" if side < 0 else "RightLeg"
		leg.position = Vector3(side * 0.15, 0.81, 0)
		Visual.part(leg, Vector3(0, -0.35, 0), Vector3(0.23, 0.7, 0.26), pants)
		Visual.part(leg, Vector3(0, -0.71, -0.05), Vector3(0.25, 0.16, 0.4), Color("e2dfd1"))
		model_root.add_child(leg)
		Visual.part(model_root, Vector3(side * 0.37, 1.14, 0), Vector3(0.18, 0.55, 0.23), shirt)
		Visual.part(model_root, Vector3(side * 0.37, 0.82, 0), Vector3(0.17, 0.18, 0.19), skin)
	return model_root
