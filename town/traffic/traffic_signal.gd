extends Node3D

var world: Node3D
var junction_index := 0
var lamps: Array[Array] = []
var pedestrian_labels: Array[Label3D] = []


func _ready() -> void:
	for direction in 4:
		var axis: Vector2i = world.DIRECTIONS[direction]
		var forward := Vector3(axis.x, 0, axis.y)
		var right := forward.cross(Vector3.UP)
		var head := Node3D.new()
		head.position = -forward * 8 + right * 7
		head.rotation.y = atan2(-forward.x, -forward.z)
		add_child(head)
		_box(head, Vector3(0, 2.2, 0), Vector3(0.12, 4.4, 0.12), Color("515d61"))
		_box(head, Vector3(0, 4.25, 0), Vector3(0.46, 1.45, 0.4), Color("20292e"))
		var row: Array = []
		for i in 3:
			var lens := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.135
			sphere.height = 0.27
			lens.mesh = sphere
			lens.position = Vector3(0, 4.7 - i * 0.43, 0.22)
			var material := StandardMaterial3D.new()
			material.albedo_color = [Color("e84a43"), Color("eeb649"), Color("56d796")][i]
			material.emission_enabled = true
			material.emission = material.albedo_color
			lens.material_override = material
			head.add_child(lens)
			row.append(material)
		lamps.append(row)
		_box(head, Vector3(0, 2.6, 0.12), Vector3(0.64, 0.40, 0.22), Color("151c21"))
		var sign := Label3D.new()
		sign.position = Vector3(0, 2.6, 0.24)
		sign.pixel_size = 0.009
		sign.font_size = 20
		sign.outline_size = 0
		head.add_child(sign)
		pedestrian_labels.append(sign)


func _process(_delta: float) -> void:
	for direction in 4:
		var active: int = world.light_state(junction_index, direction)
		for i in 3:
			var material: StandardMaterial3D = lamps[direction][i]
			material.emission_energy_multiplier = 3.5 if active == i else 0
			material.albedo_color = material.emission if active == i else material.emission.darkened(0.88)
	var walk := fmod(world.elapsed, 58.0) >= 30 and fmod(world.elapsed, 58.0) < 36
	for sign in pedestrian_labels:
		sign.text = "WALK" if walk else "WAIT"
		sign.modulate = Color("91efc1") if walk else Color("e78b73")


func _box(parent: Node3D, p: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = p
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.material_override = material
	parent.add_child(instance)
