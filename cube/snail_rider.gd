extends "res://town/traffic/citizen.gd"

const SNAIL = preload("res://Assets/Characters/Gary/gary.glb")
const RIDER = preload("res://Assets/Characters/CJ/cj.glb")

func _build_model() -> void:
	model = SNAIL.instantiate()
	add_child(model)
	var seat := model.find_child("RideSeat",true,false) as Node3D
	var cj := RIDER.instantiate() as Node3D
	model.add_child(cj)
	var rig: Skeleton3D = cj.find_children("*","Skeleton3D",true,false)[0]
	motion = Motion.new()
	motion.bind(rig)
	cj.global_position = seat.global_position - Vector3.UP*motion.hip_position.y
	var left := model.find_child("LeftGrip",true,false) as Node3D
	var right := model.find_child("RightGrip",true,false) as Node3D
	motion.ride(left.global_position,right.global_position)

func _update_animation(delta: float, actual_speed: float) -> void:
	# Both models move as a unit. The rider's seated pose only needs solving once.
	if actual_speed > .1:
		animation_elapsed += delta*actual_speed
		model.position.y = .018*sin(animation_elapsed*4)

func can_chat() -> bool:
	return false
