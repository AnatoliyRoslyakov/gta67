extends SceneTree
# Offline asset authoring. Run with Godot --headless --path . --script res://tools/build_russian_models.gd.
# Original geometry; no POLYGON City meshes or textures are redistributed.
var surfaces: Dictionary = {}
var mats: Dictionary = {}

func _initialize() -> void:
	# UAZ469 has its own reference-based Blender authoring pipeline.
	for kind in ["VAZ2101", "VAZ2105", "VAZ2106", "UAZ452"]:
		build(kind)
	quit()

func material(key: String, color: String, metal: float = 0.0, rough: float = 0.7) -> void:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = rough
	mats[key] = m

func begin() -> void:
	surfaces = {}

func surface(key: String) -> SurfaceTool:
	if not surfaces.has(key):
		var s := SurfaceTool.new()
		s.begin(Mesh.PRIMITIVE_TRIANGLES)
		s.set_material(mats[key])
		surfaces[key] = s
	return surfaces[key]

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	var s := surface(key)
	var n := (b-a).cross(c-a).normalized()
	var points := [a, c, b, a, d, c]
	if n.dot(outward) < 0:
		n = -n
		points = [a, b, c, a, c, d]
	for p in points:
		s.set_normal(n)
		s.add_vertex(p)

func primitive(key: String, mesh: PrimitiveMesh, p: Vector3, rotation := Vector3.ZERO) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var transform := Transform3D(Basis.from_euler(rotation), p)
	var target := surface(key)
	# Keep the entire surface unindexed until finish(): append_from() would
	# leave previously authored polygon vertices outside the primitive index buffer.
	for i in (indices.size() if not indices.is_empty() else vertices.size()):
		var index := indices[i] if not indices.is_empty() else i
		target.set_normal(transform.basis * normals[index])
		target.add_vertex(transform * vertices[index])

func box(key: String, p: Vector3, size: Vector3, rotation := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	primitive(key, mesh, p, rotation)

func cylinder(key: String, p: Vector3, radius: float, depth: float, axis: String = "z", segments: int = 16) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = segments
	mesh.rings = 0
	primitive(key, mesh, p, Vector3(PI/2, 0, 0) if axis == "z" else Vector3(0, 0, PI/2))

func finish() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for key in surfaces:
		surfaces[key].index()
		surfaces[key].commit(mesh)
	return mesh

func arch_floor(z: float, axles: Array, radius: float, floor_y: float) -> float:
	var y := floor_y
	for axle in axles:
		var dz: float = absf(z - axle)
		if dz < radius + 0.065:
			y = maxf(y, radius + sqrt(maxf(0, pow(radius + 0.065, 2) - dz*dz)))
	return y

func lower_body(w: float, back: float, front: float, belt: float, floor_y: float, axles: Array, radius: float) -> void:
	var zs: Array[float] = [back, front]
	for axle in axles:
		for i in 13:
			var z: float = axle + (radius + 0.065) * cos(PI * i / 12.0)
			if z > back and z < front: zs.append(z)
	zs.sort()
	for side in [-1.0, 1.0]:
		for i in zs.size()-1:
			var a := zs[i]
			var b := zs[i+1]
			var ya := arch_floor(a, axles, radius, floor_y)
			var yb := arch_floor(b, axles, radius, floor_y)
			quad("paint", Vector3(side*w,ya,a),Vector3(side*w,yb,b),Vector3(side*w,belt-0.08,b),Vector3(side*w,belt-0.08,a),Vector3(side,0,0))
			quad("paint", Vector3(side*w,belt-0.08,a),Vector3(side*w,belt-0.08,b),Vector3(side*(w-0.045),belt,b),Vector3(side*(w-0.045),belt,a),Vector3(side,1,0))
			# Recessed wheel-well lip follows the actual cutout.
			quad("rubber",Vector3(side*w,ya,a),Vector3(side*(w-0.075),ya,a),Vector3(side*(w-0.075),yb,b),Vector3(side*w,yb,b),Vector3(0,-1,0))
	for z in [back,front]:
		quad("paint",Vector3(-w,floor_y,z),Vector3(w,floor_y,z),Vector3(w,belt-0.08,z),Vector3(-w,belt-0.08,z),Vector3(0,0,signf(z)))
		quad("paint",Vector3(-w,belt-0.08,z),Vector3(w,belt-0.08,z),Vector3(w-0.045,belt,z),Vector3(-w+0.045,belt,z),Vector3(0,1,signf(z)))
	box("rubber",Vector3(0,floor_y+0.035,(back+front)/2),Vector3(w*1.65,0.07,front-back-0.1))

# Sloping pillar frames and inset windows, with no opaque panel behind the glass.
func window_panel(a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3, border: float = 0.065) -> void:
	var center := (a+b+c+d)*0.25
	var inner: Array[Vector3] = []
	for p in [a,b,c,d]: inner.append(p.lerp(center,border))
	quad("paint",a,b,inner[1],inner[0],n)
	quad("paint",b,c,inner[2],inner[1],n)
	quad("paint",c,d,inner[3],inner[2],n)
	quad("paint",d,a,inner[0],inner[3],n)
	var glass: Array[Vector3] = []
	for p in inner: glass.append(p.lerp(center,0.035))
	for i in 4: quad("rubber",inner[i],inner[(i+1)%4],glass[(i+1)%4],glass[i],n)
	quad("glass",glass[0],glass[1],glass[2],glass[3],n)

func cabin(w: float, belt: float, roof: float, rear_bottom: float, front_bottom: float, rear_top: float, front_top: float, segments: int, roof_mat: String = "paint") -> void:
	var rw := w-0.12
	window_panel(Vector3(-w,belt,front_bottom),Vector3(w,belt,front_bottom),Vector3(rw,roof-0.07,front_top),Vector3(-rw,roof-0.07,front_top),Vector3(0,1,1))
	window_panel(Vector3(w,belt,rear_bottom),Vector3(-w,belt,rear_bottom),Vector3(-rw,roof-0.07,rear_top),Vector3(rw,roof-0.07,rear_top),Vector3(0,1,-1))
	for side in [-1.0,1.0]:
		for i in segments:
			var t0 := float(i)/segments
			var t1 := float(i+1)/segments
			window_panel(Vector3(side*w,belt,lerpf(rear_bottom,front_bottom,t0)),Vector3(side*w,belt,lerpf(rear_bottom,front_bottom,t1)),Vector3(side*rw,roof-0.07,lerpf(rear_top,front_top,t1)),Vector3(side*rw,roof-0.07,lerpf(rear_top,front_top,t0)),Vector3(side,0,0),0.10)
		quad(roof_mat,Vector3(side*rw,roof-0.07,rear_top),Vector3(side*rw,roof-0.07,front_top),Vector3(side*(rw-0.05),roof,front_top-0.04),Vector3(side*(rw-0.05),roof,rear_top+0.04),Vector3(side,1,0))
	quad(roof_mat,Vector3(-rw+0.05,roof,rear_top+0.04),Vector3(rw-0.05,roof,rear_top+0.04),Vector3(rw-0.05,roof,front_top-0.04),Vector3(-rw+0.05,roof,front_top-0.04),Vector3.UP)
	for z in [rear_top,front_top]:
		quad(roof_mat,Vector3(-rw,roof-0.07,z),Vector3(rw,roof-0.07,z),Vector3(rw-0.05,roof,z-signf(z)*0.04),Vector3(-rw+0.05,roof,z-signf(z)*0.04),Vector3(0,1,signf(z)))

func deck(w: float, y: float, a: float, b: float) -> void:
	quad("paint",Vector3(-w,y,a),Vector3(w,y,a),Vector3(w,y,b),Vector3(-w,y,b),Vector3.UP)
	for side in [-1.0,1.0]: box("seam",Vector3(side*(w-0.10),y+0.002,(a+b)/2),Vector3(0.008,0.006,absf(b-a)*0.89))

func details(w: float, front: float, back: float, belt: float, kind: String) -> void:
	var van := kind == "UAZ452"
	var jeep := kind == "UAZ469"
	var lamp_y := 1.05 if jeep else (0.78 if van else 0.74)
	for z in [front+0.035,back-0.035]:
		box("chrome" if not jeep else "rubber",Vector3(0,0.48 if not jeep else 0.65,z),Vector3(w*1.98,0.10,0.13))
		for side in [-1.0,1.0]: box("rubber",Vector3(side*w*0.68,0.49 if not jeep else 0.66,z+signf(z)*0.055),Vector3(0.075,0.15,0.055))
	box("rubber",Vector3(0,lamp_y,front+0.012),Vector3(w*1.9,0.29,0.028))
	if jeep:
		for x in 7: box("paint",Vector3((x-3)*0.095,lamp_y,front+0.033),Vector3(0.04,0.30,0.025))
	else:
		for y in 5: box("chrome",Vector3(0,lamp_y-0.105+y*0.05,front+0.033),Vector3(w*(0.91 if kind == "VAZ2106" else 1.12),0.012,0.018))
	for side in [-1.0,1.0]:
		if kind == "VAZ2105":
			box("chrome",Vector3(side*w*0.72,lamp_y,front+0.04),Vector3(0.33,0.23,0.035))
			box("lamp",Vector3(side*w*0.72,lamp_y,front+0.064),Vector3(0.29,0.19,0.025))
		else:
			for i in (2 if kind == "VAZ2106" else 1):
				var x: float = side*(w*0.76-i*0.23)
				cylinder("chrome",Vector3(x,lamp_y,front+0.034),0.115 if kind == "VAZ2106" else 0.135,0.045)
				cylinder("lamp",Vector3(x,lamp_y,front+0.062),0.093 if kind == "VAZ2106" else 0.11,0.025)
		box("amber",Vector3(side*w*0.76,lamp_y-0.21,front+0.025),Vector3(0.16,0.065,0.035))
		var tail_width := 0.22 if kind == "VAZ2101" else (0.37 if kind == "VAZ2105" else 0.30)
		box("chrome",Vector3(side*w*0.73,0.76,back-0.02),Vector3(tail_width+0.025,0.19,0.04))
		box("red",Vector3(side*w*0.73,0.78,back-0.047),Vector3(tail_width,0.115,0.035))
		box("amber",Vector3(side*w*0.73,0.70,back-0.05),Vector3(tail_width,0.04,0.025))
		if kind == "VAZ2106" or kind == "VAZ2105":
			box("lamp",Vector3(side*(w*0.73-tail_width*0.32),0.78,back-0.069),Vector3(0.065,0.10,0.012))
		# Mirrors, stalks, side indicators and door handles.
		var mirror_z := 1.36 if van else 0.62
		box("chrome",Vector3(side*(w+0.055),belt+0.09,mirror_z),Vector3(0.15,0.03,0.035))
		box("rubber",Vector3(side*(w+0.13),belt+0.14,mirror_z),Vector3(0.085,0.14,0.20))
		box("glass",Vector3(side*(w+0.13),belt+0.14,mirror_z-0.106),Vector3(0.075,0.12,0.008))
		for z in ([0.7,-0.15] if van else [0.20,-0.70]):
			box("rubber",Vector3(side*(w+0.004),belt-0.16,z),Vector3(0.02,0.045,0.17))
			box("chrome",Vector3(side*(w+0.018),belt-0.15,z),Vector3(0.025,0.025,0.13))
		for z in ([0.48,-0.8] if van else [0.43,-0.43,-1.02]):
			box("seam",Vector3(side*(w+0.002),belt-0.28,z),Vector3(0.006,0.42,0.008))
		box("chrome" if not jeep else "rubber",Vector3(side*(w+0.006),belt-0.34,(front+back)/2),Vector3(0.025,0.025,front-back-0.15))
		box("amber",Vector3(side*(w+0.015),belt-0.18,front-0.39),Vector3(0.025,0.055,0.10))
	for z in [front+0.11,back-0.11]:
		box("rubber",Vector3(0,0.49,z),Vector3(0.48,0.115,0.02))
		box("plate",Vector3(0,0.49,z+signf(z)*0.012),Vector3(0.44,0.085,0.008))
		for i in 6: box("rubber",Vector3(-0.14+i*0.05,0.49,z+signf(z)*0.018),Vector3(0.022,0.045,0.005))
	box("chrome",Vector3(0,lamp_y+0.05,front+0.054),Vector3(0.045,0.065,0.014))
	# Exhaust, windshield wipers, bonnet vents.
	cylinder("rubber",Vector3(-w*0.55,0.29,back-0.045),0.034,0.16)
	for x in [-0.32,0.32]:
		box("rubber",Vector3(x,belt+0.075,1.75 if van else 0.92),Vector3(0.38,0.015,0.02),Vector3(0,0,-0.08))

func wheel(radius: float, width: float, jeep: bool) -> ArrayMesh:
	begin()
	var rings := [[-width/2,0.78],[-width/2+0.025,0.94],[-width/2+0.05,1.0],[width/2-0.05,1.0],[width/2-0.025,0.94],[width/2,0.78]]
	for j in rings.size()-1:
		for i in 16:
			var a := TAU*i/16
			var b := TAU*(i+1)/16
			quad("rubber",Vector3(rings[j][0],sin(a)*radius*rings[j][1],cos(a)*radius*rings[j][1]),Vector3(rings[j+1][0],sin(a)*radius*rings[j+1][1],cos(a)*radius*rings[j+1][1]),Vector3(rings[j+1][0],sin(b)*radius*rings[j+1][1],cos(b)*radius*rings[j+1][1]),Vector3(rings[j][0],sin(b)*radius*rings[j][1],cos(b)*radius*rings[j][1]),Vector3(0,sin(a+0.1),cos(a+0.1)))
	for side in [-1.0,1.0]:
		cylinder("rubber",Vector3(side*width*0.45,0,0),radius*0.79,0.024,"x")
		cylinder("chrome",Vector3(side*width*0.49,0,0),radius*0.63,0.023,"x")
		cylinder("chrome",Vector3(side*width*0.52,0,0),radius*0.30,0.045,"x")
		for i in 8:
			var a := TAU*i/8
			cylinder("rubber",Vector3(side*(width/2+0.008),sin(a)*radius*0.46,cos(a)*radius*0.46),radius*0.075,0.009,"x",8)
		for i in 5:
			var a := TAU*i/5
			cylinder("plate",Vector3(side*(width/2+0.03),sin(a)*radius*0.20,cos(a)*radius*0.20),0.012,0.012,"x",6)
	if jeep:
		for i in 16:
			var a := TAU*i/16
			box("rubber",Vector3(0,sin(a)*radius*0.98,cos(a)*radius*0.98),Vector3(width*0.7,0.04,0.045),Vector3(-a,0,0))
	return finish()

func build(kind: String) -> void:
	var jeep := kind == "UAZ469"
	var van := kind == "UAZ452"
	var w := 0.90 if jeep else (0.95 if van else 0.805)
	var radius := 0.375 if jeep else (0.3377778 if van else 0.28977272)
	var track := 0.75 if jeep else (0.8444444 if van else 0.6922349)
	var width := 0.30 if jeep else (0.2111111 if van else 0.22537878)
	var front_axle := 1.5375 if jeep else (1.2666667 if van else 1.59375)
	var rear_axle := -1.05 if jeep else (-1.1611111 if van else -1.0785985)
	var front := 2.07 if van else (2.06 if jeep else 2.24)
	var back := -2.22 if van else (-1.85 if jeep else -1.96)
	var belt := 1.25 if van else (1.22 if jeep else 0.98)
	var roof := 1.95 if jeep else (2.02 if van else (1.45 if kind == "VAZ2105" else 1.40))
	material("paint", {"VAZ2101":"d8b75d","VAZ2105":"688b70","VAZ2106":"638ca9","UAZ469":"737b51","UAZ452":"abb8ab"}[kind],0.12,0.36)
	mats.paint.clearcoat_enabled = true
	mats.paint.clearcoat = 0.35
	material("rubber","20262b",0,0.88)
	material("seam","41494a",0,0.75)
	material("chrome","bbc5c7",0.72,0.28)
	material("glass","284957",0.35,0.16)
	mats.glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mats.glass.albedo_color.a = 0.68
	material("canvas","4c5541",0,0.94)
	material("lamp","ede7c6",0.15,0.23)
	material("red","a72d29",0.1,0.28)
	material("amber","e59734",0.1,0.35)
	material("plate","e0dfcf",0,0.65)
	begin()
	lower_body(w,back,front,belt,0.45 if jeep else 0.32,[rear_axle,front_axle],radius)
	if van:
		cabin(w-0.045,belt,roof,back,front-0.08,back+0.12,front-0.29,4)
		deck(w-0.045,belt,front-0.08,front)
		for side in [-1.0,1.0]:
			box("chrome",Vector3(side*(w-0.05),roof-0.12,-0.06),Vector3(0.035,0.035,3.94))
			box("rubber",Vector3(side*(w+0.04),0.30,0.5),Vector3(0.14,0.06,0.75))
	elif jeep:
		deck(w-0.045,belt,0.67,front)
		cabin(w-0.045,belt,roof,back+0.08,0.67,back+0.12,0.43,3,"canvas")
		# Canvas cover, roof bows, hinges and rear-mounted spare.
		for side in [-1.0,1.0]:
			box("canvas",Vector3(side*(w-0.06),1.36,-1.07),Vector3(0.035,0.23,1.35))
			for z in [-1.55,-0.75]: box("canvas",Vector3(side*(w-0.12),1.63,z),Vector3(0.035,0.53,0.035))
			for z in [-0.45,0.55]: box("chrome",Vector3(side*(w+0.012),1.03,z),Vector3(0.025,0.11,0.06))
		cylinder("rubber",Vector3(0,1.08,back-0.10),radius,0.22)
		cylinder("paint",Vector3(0,1.08,back-0.22),radius*0.58,0.025)
	else:
		deck(w-0.045,belt,0.95,front)
		deck(w-0.045,belt,back,-1.15)
		cabin(w-0.045,belt,roof,-1.15,0.95,-0.78,0.49 if kind == "VAZ2105" else 0.39,2)
		if kind == "VAZ2105":
			for x in [-0.32,0.32]: box("paint",Vector3(x,belt+0.012,1.55),Vector3(0.035,0.018,0.85))
		for i in 7: box("rubber",Vector3(-0.26+i*0.085,belt+0.007,1.04),Vector3(0.04,0.012,0.075))
	# Visible cabin behind the tinted glazing; baked with the body, not extra nodes.
	var seat_front := 0.66 if van else -0.08
	for x in [-0.40,0.40]:
		box("rubber",Vector3(x,0.60,seat_front),Vector3(0.46,0.16,0.47))
		box("rubber",Vector3(x,0.83,seat_front-0.21),Vector3(0.46,0.48,0.12),Vector3(-0.10,0,0))
		box("rubber",Vector3(x,1.10,seat_front-0.24),Vector3(0.24,0.15,0.11))
	box("rubber",Vector3(0,0.62,seat_front-0.83),Vector3(w*1.6,0.18,0.46))
	box("rubber",Vector3(0,0.82,seat_front-1.02),Vector3(w*1.6,0.43,0.13))
	box("rubber",Vector3(0,belt-0.11,1.45 if van else 0.74),Vector3(w*1.75,0.15,0.25))
	details(w,front,back,belt,kind)
	var body := finish()
	var path := "res://vehicles/russian/%s_body.res" % kind.to_lower()
	ResourceSaver.save(body,path)
	body.take_over_path(path)
	var root := MeshInstance3D.new()
	root.name = kind
	root.mesh = body
	root.set_meta("headlight_height",1.05 if jeep else (0.78 if van else 0.74))
	root.set_meta("authored_materials",true)
	var tire := wheel(radius,width,jeep)
	var wheel_path := "res://vehicles/russian/%s_wheel.res" % ("uaz469" if jeep else ("uaz452" if van else "vaz"))
	ResourceSaver.save(tire,wheel_path)
	tire.take_over_path(wheel_path)
	for item in [["fl",track,front_axle],["rl",track,rear_axle],["fr",-track,front_axle],["rr",-track,rear_axle]]:
		var node := MeshInstance3D.new()
		node.name = kind+"_Wheel_"+item[0]
		node.mesh = tire
		node.position = Vector3(item[1],radius,item[2])
		root.add_child(node)
		node.owner = root
	var scene := PackedScene.new()
	scene.pack(root)
	ResourceSaver.save(scene,"res://vehicles/russian/%s.tscn" % kind)
	print("Baked ",kind," body triangles: ",body.get_faces().size()/3," wheel triangles: ",tire.get_faces().size()/3)
	root.free()
