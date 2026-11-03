extends SceneTree
# Run after build_uaz469.py. Keeps native Godot resources and shared wheel LODs.
func _initialize() -> void:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_file("/tmp/gta67_uaz469.glb", state)
	assert(result == OK, "Blender GLB must exist and be valid")
	var imported := document.generate_scene(state)
	var root := MeshInstance3D.new()
	root.name = "UAZ469"
	var nodes := imported.find_children("*", "", true, false)
	var wheel_mesh: ArrayMesh
	for node in nodes:
		if not (node is MeshInstance3D or node is ImporterMeshInstance3D): continue
		var source: Mesh = node.mesh.get_mesh() if node is ImporterMeshInstance3D else node.mesh
		if "Body" in str(node.name):
			root.mesh = bake(source, "res://vehicles/russian/uaz469_body.res")
			root.transform = node.transform
		elif "Wheel_" in str(node.name):
			if wheel_mesh == null: wheel_mesh = bake(source, "res://vehicles/russian/uaz469_wheel.res")
			var wheel := MeshInstance3D.new()
			wheel.name = node.name
			wheel.mesh = wheel_mesh
			wheel.transform = node.transform
			root.add_child(wheel)
			wheel.owner = root
	assert(root.mesh != null and root.get_child_count() == 4)
	root.set_meta("headlight_height", 1.083)
	root.set_meta("headlight_half_width", 0.633)
	root.set_meta("tail_light_height", 1.05)
	root.set_meta("tail_light_half_width", 0.68)
	root.set_meta("turn_light_height", 0.837)
	root.set_meta("turn_light_half_width", 0.654)
	root.set_meta("authored_materials", true)
	root.set_meta("authored_cabin", true)
	root.set_meta("wheelbase", 2.38)
	root.set_meta("driver_position", Vector3(0.42, 1.54, -0.35))
	var packed := PackedScene.new()
	packed.pack(root)
	assert(ResourceSaver.save(packed,"res://vehicles/russian/UAZ469.tscn") == OK)
	print("UAZ bounds: ",root.get_aabb(),"; wheels: ",root.get_child_count())
	root.free()
	imported.free()
	quit()

func bake(source: Mesh, path: String) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for i in source.get_surface_count():
		var material := source.surface_get_material(i) as StandardMaterial3D
		if material != null:
			if "Canvas" in material.resource_name:
				material.normal_enabled = true
				material.normal_texture = cloth_normal()
				material.normal_scale = 0.22
				material.uv1_triplanar = true
				material.uv1_scale = Vector3.ONE * 18.0
			# GLB uses alpha blending for the physically separate window surfaces.
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(i),[],{},material)
	importer.generate_lods(60.0,25.0,[])
	var mesh := importer.get_mesh()
	assert(ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS) == OK)
	mesh.take_over_path(path)
	var lod_count := 0
	for i in importer.get_surface_count(): lod_count += importer.get_surface_lod_count(i)
	print(path," triangles: ",mesh.get_faces().size()/3," LOD levels: ",lod_count)
	return mesh

func cloth_normal() -> ImageTexture:
	# Bake a tiny woven normal map; no runtime noise generation or external textures.
	var weave := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			weave.set_pixel(x, y, Color(0.5 + 0.08 * sin(x * PI * 0.5), 0.5 + 0.08 * sin(y * PI * 0.5), 0.99))
	weave.generate_mipmaps()
	return ImageTexture.create_from_image(weave)
