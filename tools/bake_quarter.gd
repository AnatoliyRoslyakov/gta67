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
var room_finishes := {}
var room_masks: Node
var street_lamps := PackedVector3Array()
var textures := {}
var bounds := AABB(Vector3(-HALF,-.6,-HALF),Vector3(2*HALF,86,2*HALF))

func _initialize() -> void:
	build.call_deferred()

func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var map: Node3D = load(SOURCE).instantiate()
	map.position = -CENTER
	root.add_child(map)
	prepare_lots(map)
	room_masks = load("res://town/atmosphere.gd").new()
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
		if node.scene_file_path.ends_with("SM_Prop_LightPole_Base_01.tscn"):
			street_lamps.append(node.global_transform * Vector3(0,6.22,1.9635))
		var solid := str(node.name).begins_with("SM_Bld_") or str(node.name).begins_with("SM_Env_Sidewalk_")
		for i in node.mesh.get_surface_count():
			if node.mesh.surface_get_primitive_type(i) != Mesh.PRIMITIVE_TRIANGLES: continue
			var finish := web_material(node.get_active_material(i))
			if str(node.name).begins_with("SM_Bld_Office") or str(node.name).begins_with("SM_Bld_Apartment"):
				var key := [finish,posmod(hash(node.global_position.round()),3)]
				if not room_finishes.has(key):
					var rooms: StandardMaterial3D = finish.duplicate()
					rooms.emission_enabled = true
					rooms.emission = Color.BLACK
					rooms.emission_texture = room_masks._room_mask(key[1])
					rooms.emission_energy_multiplier = 0
					rooms.set_meta("rooms",true)
					room_finishes[key] = rooms
				finish = room_finishes[key]
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
	district.set_meta("lamps",street_lamps)
	var packed := PackedScene.new()
	var status := packed.pack(district)
	if status == OK: status = ResourceSaver.save(packed,OUTPUT+"district.scn",ResourceSaver.FLAG_COMPRESS)
	print("District: ",combined.get_aabb()," / ",combined.get_surface_count()," material batches, ",collision.size()/3," collision faces. ", error_string(status))
	district.free()
	graph.free()
	room_masks.free()
	map.free()
	quit(status)

# Rehouse the two modular apartment compounds as complete assemblies; the
# facade pieces and rooftop accessories must keep their relative positions.
func prepare_lots(map: Node3D) -> void:
	var block_a := map.get_node("City_Area_02/Apartment_Block_05") as Node3D
	var block_b := map.get_node("City_Area_02/Apartment_Block_06") as Node3D
	map.get_node("City_Area_02/Apartment_Block_04").free()
	fit_lot(block_a,Rect2(-22,23,32,25))
	fit_lot(block_b,Rect2(16,-48,32,16))
	var remove := []
	for n: MeshInstance3D in map.find_children("*","MeshInstance3D",true,false):
		if block_a.is_ancestor_of(n) or block_b.is_ancestor_of(n) or not n.mesh: continue
		var box := n.global_transform*n.get_aabb()
		if not bounds.grow(.1).intersects(box): continue
		# Outside the original central parcels, roofs, signs and air-conditioners
		# belong to buildings beyond the slice. Omit those assemblies together.
		if str(n.name).begins_with("SM_Bld_"):
			if box.position.x < -49 or box.end.x > 49 or box.position.z < -49 or box.end.z > 49:
				remove.append(n)
		elif str(n.name).begins_with("SM_Prop_") and box.position.y>3:
			var c := box.get_center()
			if absf(c.x)>38 or absf(c.z)>33: remove.append(n)
	for n in remove:
		if is_instance_valid(n): n.free()
	place_tower(map,"SM_Bld_OfficeRound_03",Vector2(-42.5,-37.8),.56,1.17)
	place_tower(map,"SM_Bld_OfficeSquare_03",Vector2(21.4,36.4),.97,1.30)

func footprint(group: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for n: MeshInstance3D in group.find_children("*","MeshInstance3D",true,false):
		if not n.mesh or not n.is_visible_in_tree(): continue
		var box := n.global_transform*n.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func fit_lot(group: Node3D, lot: Rect2) -> void:
	var box := footprint(group)
	var horizontal := minf(lot.size.x/box.size.x,lot.size.y/box.size.z)
	group.scale *= Vector3(horizontal,maxf(.83,horizontal),horizontal)
	box = footprint(group)
	var center := box.get_center()
	group.global_position += Vector3(lot.get_center().x-center.x,0,lot.get_center().y-center.z)

func place_tower(map: Node3D, kind: String, center: Vector2, width: float, height: float) -> void:
	var family := kind.left(kind.rfind("_"))
	var y := 0.0
	# POLYGON tower prefabs are modular. Each shaft needs its matching
	# street-level entrance and capped roof at the same horizontal pivot.
	for piece: String in [family+"_Base_01",kind,family+"_Roof_01"]:
		var mesh: MeshInstance3D = load("res://Assets/Synty/PolygonCity/Prefabs/Buildings/%s.tscn" % piece).instantiate()
		map.add_child(mesh)
		mesh.scale = Vector3(width,height if piece==kind else .95,width)
		var box := mesh.global_transform * mesh.get_aabb()
		mesh.global_position += Vector3(center.x-box.get_center().x,y-box.position.y,center.y-box.get_center().z)
		y += box.size.y-.10
	var vent: MeshInstance3D = load("res://Assets/Synty/PolygonCity/Prefabs/Props/SM_Prop_Roof_Aircon_02.tscn").instantiate()
	map.add_child(vent)
	var unit_box := vent.global_transform*vent.get_aabb()
	vent.global_position += Vector3(center.x-unit_box.get_center().x,y-unit_box.position.y,center.y-unit_box.get_center().z)

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
			if contact:
				var ab: Vector3 = tri[1][0]-tri[0][0]
				var ac: Vector3 = tri[2][0]-tri[0][0]
				contact = ab.cross(ac).length_squared()>.035 and maxf(tri[0][0].y,maxf(tri[1][0].y,tri[2][0].y))>.10
			for v: Array in tri:
				st.set_normal(v[1])
				st.set_uv(v[2])
				st.add_vertex(v[0])
				if contact: collision.append(v[0])
