extends SceneTree
## Run with --headless --script res://tools/bake_quarter.gd before Web export.
## Only the local, ignored Assets directory receives derived pack geometry.
const SOURCE := "res://Assets/Synty/PolygonCity/Scenes/Demo.tscn"
const OUTPUT := "res://Assets/WebQuarter/"
const CENTER := Vector3(30,0,-90)
const HALF := 50.0
var batches := {}
var collision := PackedVector3Array()
var finishes := {}
var textures := {}
var bounds := AABB(Vector3(-HALF,-.6,-HALF),Vector3(2*HALF,86,2*HALF))

func _initialize() -> void:
	build.call_deferred()

func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var map: Node3D = load(SOURCE).instantiate()
	map.position = -CENTER
	root.add_child(map)
	var graph: Node3D = load("res://town/traffic/traffic_world.gd").new()
	graph.city_map = map
	graph._extract_surfaces()
	var district := Node3D.new()
	district.name = "District"
	district.set_meta("road_cells", cells_inside(graph.road_cells,graph.CELL))
	district.set_meta("sidewalk_cells", cells_inside(graph.sidewalk_cells,graph.WALK_CELL))
	var cars := map.get_node("Road_Cars")
	for node: MeshInstance3D in map.find_children("*","MeshInstance3D",true,false):
		if not node.mesh or not node.is_visible_in_tree() or cars.is_ancestor_of(node): continue
		if "Ocean_" in str(node.get_path()) or "Skydome" in str(node.get_path()) or "Skyline" in str(node.get_path()): continue
		var box: AABB = node.global_transform * node.get_aabb()
		if not bounds.grow(.01).intersects(box): continue
		var solid := str(node.name).begins_with("SM_Bld_") or str(node.name).begins_with("SM_Env_Sidewalk_")
		for i in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES: continue
			var finish := web_material(node.get_active_material(i))
			if not batches.has(finish):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				st.set_material(finish)
				batches[finish] = st
			append_triangles(batches[finish],node.mesh.surface_get_arrays(i),node.global_transform,solid)
	var combined := ArrayMesh.new()
	for st: SurfaceTool in batches.values():
		st.index()
		st.commit(combined)
	var visual := MeshInstance3D.new()
	visual.mesh = combined
	district.add_child(visual)
	visual.owner = district
	var body := StaticBody3D.new()
	district.add_child(body)
	body.owner = district
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision)
	shape.backface_collision = true
	collider.shape = shape
	body.add_child(collider)
	collider.owner = district
	var pavement := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(100,1,100)
	pavement.shape = slab
	pavement.position.y = -.5
	body.add_child(pavement)
	pavement.owner = district
	var packed := PackedScene.new()
	var status := packed.pack(district)
	if status == OK: status = ResourceSaver.save(packed,OUTPUT+"district.scn",ResourceSaver.FLAG_COMPRESS)
	print("District: ",combined.get_aabb()," / ",combined.get_surface_count()," material batches, ",collision.size()/3," collision faces. ", error_string(status))
	district.free()
	graph.free()
	map.free()
	quit(status)

func cells_inside(cells: Dictionary, step: float) -> Dictionary:
	var result := {}
	for c: Vector2i in cells:
		if maxf(absf((c.x+.5)*step),absf((c.y+.5)*step)) < HALF-1: result[c]=cells[c]
	return result

func web_material(src: Material) -> StandardMaterial3D:
	if finishes.has(src): return finishes[src]
	var m := StandardMaterial3D.new()
	if src is BaseMaterial3D:
		m.albedo_color=src.albedo_color
		m.transparency=src.transparency
		m.cull_mode=src.cull_mode
		m.uv1_scale=src.uv1_scale
		m.uv1_offset=src.uv1_offset
		var tex: Texture2D = src.albedo_texture
		if tex:
			if not textures.has(tex):
				var img := Image.load_from_file(ProjectSettings.globalize_path(tex.resource_path))
				var scale := minf(1,1024.0/maxi(img.get_width(),img.get_height()))
				img.resize(maxi(1,roundi(img.get_width()*scale)),maxi(1,roundi(img.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
				img.generate_mipmaps()
				var compact := PortableCompressedTexture2D.new()
				compact.keep_compressed_buffer=true
				compact.create_from_image(img,PortableCompressedTexture2D.COMPRESSION_MODE_LOSSY,false,.86)
				textures[tex]=compact
			m.albedo_texture=textures[tex]
	m.roughness=.83
	finishes[src]=m
	return m

# Clip only boundary triangles. Interpolate their UVs and normals to keep painted
# lane markings, windows and shop signs aligned up to the glass.
func append_triangles(st: SurfaceTool, arrays: Array, pose: Transform3D, solid: bool) -> void:
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else PackedInt32Array()
	var normal_basis := pose.basis.inverse().transposed()
	for i in points.size():
		points[i] = pose*points[i]
		normals[i] = (normal_basis*normals[i]).normalized()
	var count := indices.size() if indices.size()>0 else points.size()
	for start in range(0,count,3):
		var poly := []
		for k in 3:
			var i := indices[start+k] if indices.size()>0 else start+k
			poly.append([points[i],normals[i],uvs[i] if uvs.size()>i else Vector2.ZERO])
		for axis in [0,2]:
			for sign_dir in [-1,1]:
				if poly.is_empty(): break
				var out := []
				var a: Array = poly.back()
				for b: Array in poly:
					var da: float = HALF-a[0][axis]*sign_dir
					var db: float = HALF-b[0][axis]*sign_dir
					if (da<0)!=(db<0):
						var t := da/(da-db)
						out.append([a[0].lerp(b[0],t),a[1].lerp(b[1],t).normalized(),a[2].lerp(b[2],t)])
					if db>=0: out.append(b)
					a=b
				poly=out
		for k in range(1,poly.size()-1):
			var tri := [poly[0],poly[k],poly[k+1]]
			if pose.basis.determinant()<0: tri.reverse()
			var contact := solid and minf(tri[0][0].y,minf(tri[1][0].y,tri[2][0].y))<2.5
			for v: Array in tri:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
				if contact: collision.append(v[0])
