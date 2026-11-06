extends Node3D
## Repeated architectural pieces share geometry and one draw per primitive.
var groups := {}
var primitives := {}
var surface := StandardMaterial3D.new()

func _init() -> void:
	surface.vertex_color_use_as_albedo = true
	surface.vertex_color_is_srgb = true
	surface.roughness = 0.9
	var leaf := SphereMesh.new()
	leaf.radial_segments = 7
	leaf.rings = 3
	var drum := CylinderMesh.new()
	drum.top_radius = 0.5
	drum.bottom_radius = 0.5
	drum.height = 1
	drum.radial_segments = 12
	var roof := PrismMesh.new()
	roof.size = Vector3.ONE
	primitives = {"box": BoxMesh.new(), "round": drum, "leaf": leaf, "roof": roof}

func part(p: Vector3, size: Vector3, color: String, shape := "box", yaw := 0.0) -> void:
	if not groups.has(shape): groups[shape] = []
	groups[shape].append([Transform3D(Basis(Vector3.UP,yaw).scaled_local(size),p), Color(color)])

func bake() -> void:
	for shape in groups:
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = primitives[shape]
		batch.instance_count = groups[shape].size()
		for i in batch.instance_count:
			batch.set_instance_transform(i, groups[shape][i][0])
			batch.set_instance_color(i, groups[shape][i][1])
		var node := MultiMeshInstance3D.new()
		node.multimesh = batch
		node.material_override = surface
		add_child(node)
	groups.clear()
