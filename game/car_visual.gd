extends RefCounted


static func build(tint: Color, kind := "sport", include_wheels := true) -> Node3D:
	var root := Node3D.new()
	var dark := Color("25333e")
	var glass := Color("426773")
	part(root, Vector3(0, 0.65, 0), Vector3(1.9, 0.42, 4.5), tint)
	part(root, Vector3(0, 0.92, 0.05), Vector3(1.84, 0.3, 4.15), tint)
	part(root, Vector3(0, 1.2, -0.25), Vector3(1.65, 0.5, 2.05), glass)
	part(root, Vector3(0, 1.49, -0.3), Vector3(1.7, 0.1, 2.1), tint)
	part(root, Vector3(0, 1.19, -0.3), Vector3(1.71, 0.58, 0.12), tint)
	for side in [-1, 1]:
		part(root, Vector3(side * 0.835, 1.2, 0.72), Vector3(0.1, 0.55, 0.13), tint)
		part(root, Vector3(side * 0.835, 1.2, -1.23), Vector3(0.1, 0.55, 0.13), tint)
		part(root, Vector3(side * 1.03, 1.04, 0.65), Vector3(0.24, 0.17, 0.35), tint)
		part(root, Vector3(side * 0.91, 0.82, -0.45), Vector3(0.04, 0.06, 0.24), Color("c9d2ce"))
		part(root, Vector3(side * 0.63, 0.87, 2.27), Vector3(0.48, 0.18, 0.04), Color("fff0cb"))
		part(root, Vector3(side * 0.63, 0.87, -2.27), Vector3(0.5, 0.16, 0.04), Color("e36a6a"))
	part(root, Vector3(0, 0.56, 2.28), Vector3(1.75, 0.13, 0.12), dark)
	part(root, Vector3(0, 0.56, -2.28), Vector3(1.75, 0.13, 0.12), dark)
	part(root, Vector3(0, 0.72, -2.29), Vector3(0.4, 0.16, 0.02), Color("eee3ce"))
	if kind == "sport":
		part(root, Vector3(0, 1.14, -1.9), Vector3(1.95, 0.1, 0.4), dark)
	if kind == "taxi":
		part(root, Vector3(0, 1.66, -0.1), Vector3(0.7, 0.25, 0.35), Color("ffe49b"))
	if kind == "police":
		for side in [-1, 1]:
			part(root, Vector3(side * 0.95, 0.91, -0.1), Vector3(0.025, 0.32, 1.7), Color("d8e2df"))
		var red := part(root, Vector3(-0.43, 1.62, -0.2), Vector3(0.7, 0.18, 0.28), Color("ff607c"))
		red.name = "RedSiren"
		var blue := part(root, Vector3(0.43, 1.62, -0.2), Vector3(0.7, 0.18, 0.28), Color("60b5ff"))
		blue.name = "BlueSiren"
	if include_wheels:
		for x in [-0.96, 0.96]:
			for z in [-1.45, 1.45]:
				var wheel := wheel_visual()
				wheel.position = Vector3(x, 0.4, z)
				root.add_child(wheel)
	return root


static func wheel_visual() -> Node3D:
	var root := Node3D.new()
	var tire := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.4
	mesh.height = 0.25
	mesh.radial_segments = 12
	tire.mesh = mesh
	tire.rotation.z = PI / 2
	tire.material_override = material(Color("263039"))
	root.add_child(tire)
	var hub := MeshInstance3D.new()
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = 0.22
	hub_mesh.bottom_radius = 0.22
	hub_mesh.height = 0.27
	hub_mesh.radial_segments = 8
	hub.mesh = hub_mesh
	hub.rotation.z = PI / 2
	hub.material_override = material(Color("a5bac0"))
	root.add_child(hub)
	return root


static func part(root: Node3D, p: Vector3, dims: Vector3, tint: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dims
	instance.mesh = mesh
	instance.material_override = material(tint)
	instance.position = p
	root.add_child(instance)
	return instance


static func material(tint: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.55
	return mat
