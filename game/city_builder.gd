extends Node3D

const STREETS_X := [-300.0, -180.0, -60.0, 60.0, 180.0]
const STREETS_Z := [-300.0, -180.0, -60.0, 60.0, 180.0, 300.0]
const ASPHALT := Color("353f50")
const PAVEMENT := Color("c1b7af")
const GLASS := Color("315969")
const PALETTE := [Color("e3b0a0"), Color("e7cfaa"), Color("94b6b2"), Color("c2b6cd"), Color("e4d7c3"), Color("9caebc")]
var rng := RandomNumberGenerator.new()
var batches: Dictionary = {}
var navigation := AStar3D.new()


func _ready() -> void:
	rng.seed = 670001
	_build_land()
	_build_blocks()
	_build_coast()
	_build_details()
	_flush_batches()
	_build_navigation()


func _build_land() -> void:
	box(Vector3(-50, -1, 0), Vector3(780, 2, 840), Color("a3b591"), true)
	box(Vector3(260, -0.18, 0), Vector3(140, 0.3, 840), Color("ead4ac"))
	box(Vector3(1200, -2.1, 0), Vector3(1760, 4, 4500), Color("268d9b"))
	for i in 12:
		box(Vector3(330 + i * 2.8, -0.07 + i * 0.002, 0), Vector3(1.5, 0.015, 840), Color("78c8c4").lerp(Color("268d9b"), float(i) / 12))
	for x in STREETS_X:
		box(Vector3(x, 0.025, 0), Vector3(19, 0.05, 780), ASPHALT)
		for z in range(-384, 385, 12):
			if _near_crossing(float(z), STREETS_Z, 15): continue
			box(Vector3(x - 0.18, 0.065, z), Vector3(0.1, 0.025, 5), Color("e2c678"))
			box(Vector3(x + 0.18, 0.065, z), Vector3(0.1, 0.025, 5), Color("e2c678"))
	for z in STREETS_Z:
		box(Vector3(-60, 0.03, z), Vector3(500, 0.06, 19), ASPHALT)
		for x in range(-300, 181, 12):
			if _near_crossing(float(x), STREETS_X, 15): continue
			box(Vector3(x, 0.07, z), Vector3(5, 0.02, 0.13), Color("e2c678"))
	for x in STREETS_X:
		for z in STREETS_Z:
			for stripe in 7:
				box(Vector3(x - 6 + stripe * 2, 0.08, z + 11.5), Vector3(0.85, 0.02, 3.4), Color("e8e2d3"))
	box(Vector3(210, 0.15, 0), Vector3(40, 0.3, 780), PAVEMENT, true)
	box(Vector3(245, 0.12, 0), Vector3(12, 0.24, 810), Color("d5b99e"), true)


func _build_blocks() -> void:
	for x in [-240.0, -120.0, 0.0, 120.0]:
		for z in [-240.0, -120.0, 0.0, 120.0, 240.0]:
			box(Vector3(x, 0.15, z), Vector3(100, 0.3, 100), PAVEMENT, true)
			if x == 120 and z == 0:
				_park(Vector3(x, 0, z))
				continue
			for dx in [-27.0, 27.0]:
				for dz in [-27.0, 27.0]:
					var height := rng.randf_range(8, 24)
					if x < -100: height += rng.randf_range(10, 55)
					_building(Vector3(x + dx, 0.3, z + dz), Vector3(rng.randf_range(25, 36), height, rng.randf_range(25, 36)), PALETTE[rng.randi_range(0, PALETTE.size() - 1)])
	for z in [-260.0, -190.0, -110.0, -30.0, 80.0, 155.0, 240.0, 330.0]:
		_building(Vector3(216, 0.3, z), Vector3(23, rng.randf_range(8, 16), 33), PALETTE[rng.randi_range(0, 5)])
	_sign("PALM\nHOTEL", Vector3(230, 13, -34), Color("ff88c8"), -PI / 2, 1.5)
	_sign("COASTLINE", Vector3(202, 10, 78), Color("79eee5"), PI / 2, 1.0)
	_sign("OCEAN DRIVE", Vector3(245, 4, 40), Color("fff0ce"), PI / 2, 0.6)
	_sign("SUNSET CLUB", Vector3(-92, 10, -132), Color("ff8eaf"), 0, 1.1)


func _building(base: Vector3, dims: Vector3, tint: Color) -> void:
	box(base + Vector3(0, dims.y / 2, 0), dims, tint, true)
	box(base + Vector3(0, dims.y + 0.5, 0), Vector3(dims.x + 1.2, 1, dims.z + 1.2), tint.darkened(0.13))
	box(base + Vector3(0, 2, dims.z / 2 + 0.08), Vector3(dims.x * 0.78, 2.8, 0.13), GLASS)
	box(base + Vector3(0, 3.7, dims.z / 2 + 0.8), Vector3(dims.x + 1, 0.3, 2.1), tint.darkened(0.25))
	for y in range(6, int(dims.y) - 1, 4):
		for offset in [-0.33, -0.11, 0.11, 0.33]:
			var window_tint := GLASS if rng.randf() > 0.18 else Color("dbbc85")
			for side in [-1, 1]:
				box(base + Vector3(dims.x * offset, y, side * (dims.z / 2 + 0.06)), Vector3(dims.x * 0.12, 2.1, 0.14), window_tint)
				box(base + Vector3(side * (dims.x / 2 + 0.06), y, dims.z * offset), Vector3(0.14, 2.1, dims.z * 0.12), window_tint)
	box(base + Vector3(dims.x * 0.2, dims.y + 1.3, 0), Vector3(4, 2, 5), Color("7f8e91"))


func _park(base: Vector3) -> void:
	box(base + Vector3(0, 0.35, 0), Vector3(89, 0.15, 89), Color("749c73"))
	box(base + Vector3(0, 0.45, 0), Vector3(8, 0.1, 90), Color("d7c6ad"))
	box(base + Vector3(0, 0.46, 0), Vector3(90, 0.1, 8), Color("d7c6ad"))
	cylinder(base + Vector3(0, 0.7, 0), Vector3(12, 1.2, 12), Color("d2d7d0"), true)
	cylinder(base + Vector3(0, 1.35, 0), Vector3(10.6, 0.1, 10.6), Color("55b9bd"))
	cylinder(base + Vector3(0, 2.1, 0), Vector3(1.2, 2.5, 1.2), Color("e0ddd2"))
	for dx in [-29, 29]:
		for dz in [-30, 0, 30]: palm(base + Vector3(dx, 0.4, dz))
	for dx in [-12, 12]:
		for dz in [-22, 22]:
			box(base + Vector3(dx, 0.95, dz), Vector3(4, 0.3, 1.3), Color("886956"))
			box(base + Vector3(dx, 1.65, dz + 0.5), Vector3(4, 1.2, 0.2), Color("886956"))


func _build_coast() -> void:
	for z in range(-370, 381, 22):
		palm(Vector3(237, 0.25, z))
		if z % 2 == 0: palm(Vector3(197, 0.3, z + 8))
	for i in 24:
		var p := Vector3(rng.randf_range(270, 310), 0, rng.randf_range(-350, 350))
		cylinder(p + Vector3(0, 1.4, 0), Vector3(0.06, 2.8, 0.06), Color("eee0c6"))
		cone(p + Vector3(0, 2.7, 0), Vector3(4, 0.65, 4), Color("df876f") if i % 2 else Color("77b3bb"))
		box(p + Vector3(1.5, 0.2, 0), Vector3(0.7, 0.25, 2), Color("eee4cb"))
	box(Vector3(297, 0.65, 280), Vector3(108, 0.5, 10), Color("a58569"), true)
	for x in range(254, 345, 12):
		for z in [275.0, 285.0]:
			cylinder(Vector3(x, -0.3, z), Vector3(0.45, 3.5, 0.45), Color("765e52"))
			box(Vector3(x, 1.3, z), Vector3(0.2, 1.2, 0.2), Color("d1ba91"))
	box(Vector3(345, 2.4, 280), Vector3(12, 3, 13), Color("a3c8bf"), true)
	cone(Vector3(345, 4.3, 280), Vector3(17, 2, 17), Color("d7a497"))
	_sign("PIER 67", Vector3(246, 4.4, 280), Color("fff0d3"), PI / 2, 0.8)
	for z in [-210.0, -5.0, 190.0]:
		box(Vector3(286, 2.6, z), Vector3(5, 3, 5), Color("b7cfcb"), true)
		cone(Vector3(286, 4.8, z), Vector3(7, 1.5, 7), Color("e9b7a4"))
		box(Vector3(283, 0.65, z), Vector3(3, 1.3, 4), Color("d9b78f"))


func _build_details() -> void:
	for x in STREETS_X:
		for z in range(-330, 351, 40):
			if _near_crossing(float(z), STREETS_Z, 16): continue
			var p := Vector3(x + 12, 0, z)
			cylinder(p + Vector3(0, 3.6, 0), Vector3(0.18, 7.2, 0.18), Color("667778"))
			box(p + Vector3(-1.1, 7.1, 0), Vector3(2.4, 0.14, 0.18), Color("667778"))
			box(p + Vector3(-2.1, 7, 0), Vector3(0.8, 0.16, 0.5), Color("ffe4a6"))
	for x in [-300.0, -180.0, -60.0, 60.0, 180.0]:
		for z in [-180.0, 60.0, 300.0]:
			cylinder(Vector3(x + 12, 3, z + 12), Vector3(0.2, 6, 0.2), Color("626d70"))
			box(Vector3(x + 12, 5.8, z + 12), Vector3(0.65, 1.7, 0.6), Color("39434b"))
			box(Vector3(x + 12, 5.3, z + 12.32), Vector3(0.3, 0.3, 0.04), Color("85d1a1"))
	for z in range(-350, 350, 55):
		box(Vector3(228, 0.65, z), Vector3(0.7, 1.3, 0.7), Color("667c79"), true)
		box(Vector3(242, 0.7, z + 10), Vector3(1.2, 0.2, 3), Color("967762"))
		box(Vector3(242.5, 1.25, z + 10), Vector3(0.15, 1.1, 3), Color("967762"))


func palm(p: Vector3) -> void:
	var h := rng.randf_range(6, 10)
	cylinder(p + Vector3(0, h / 2, 0), Vector3(0.32, h, 0.32), Color("9d8062"))
	for i in 7:
		var angle := i * TAU / 7 + p.z
		var direction := Vector3(sin(angle), 0, cos(angle))
		var basis := Basis(Vector3.UP, angle) * Basis(Vector3.RIGHT, 0.15)
		_batch("leaf", p + direction * 1.7 + Vector3.UP * h, Vector3(0.65, 0.12, 5.6), Color("538b6c"), basis)


func box(p: Vector3, dims: Vector3, color: Color, solid := false) -> void:
	_batch("box", p, dims, color)
	if solid: _collider(p, dims)


func cylinder(p: Vector3, dims: Vector3, color: Color, solid := false) -> void:
	_batch("cylinder", p, dims, color)
	if solid: _collider(p, dims)


func cone(p: Vector3, dims: Vector3, color: Color) -> void:
	_batch("cone", p, dims, color)


func _batch(kind: String, p: Vector3, dims: Vector3, color: Color, basis := Basis.IDENTITY) -> void:
	var key := kind + color.to_html()
	if not batches.has(key): batches[key] = {"kind": kind, "color": color, "transforms": []}
	batches[key].transforms.append(Transform3D(basis * Basis.from_scale(dims), p))


func _collider(p: Vector3, dims: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = dims
	shape.shape = box_shape
	body.position = p
	body.add_child(shape)
	add_child(body)


func _flush_batches() -> void:
	for data in batches.values():
		var mesh: PrimitiveMesh
		if data.kind == "box" or data.kind == "leaf":
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE
			mesh = cube
		else:
			var round_mesh := CylinderMesh.new()
			round_mesh.height = 1
			round_mesh.top_radius = 0.0 if data.kind == "cone" else 0.5
			round_mesh.bottom_radius = 0.5
			round_mesh.radial_segments = 8
			mesh = round_mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = data.color
		material.roughness = 0.85
		mesh.material = material
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = data.transforms.size()
		for i in data.transforms.size(): multi.set_instance_transform(i, data.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		add_child(instance)
	batches.clear()


func _sign(caption: String, p: Vector3, color: Color, yaw: float, scale_value: float) -> void:
	var label := Label3D.new()
	label.text = caption
	label.position = p
	label.rotation.y = yaw
	label.font_size = 96
	label.pixel_size = 0.012 * scale_value
	label.modulate = color
	label.outline_size = 10
	add_child(label)


func _near_crossing(value: float, streets: Array, distance: float) -> bool:
	for street in streets:
		if absf(value - street) < distance: return true
	return false


func _build_navigation() -> void:
	for x in STREETS_X.size():
		for z in STREETS_Z.size():
			var id := x * 10 + z
			navigation.add_point(id, Vector3(STREETS_X[x], 0.5, STREETS_Z[z]))
	for id in navigation.get_point_ids():
		if navigation.has_point(id + 1) and id % 10 < 5: navigation.connect_points(id, id + 1)
		if navigation.has_point(id + 10): navigation.connect_points(id, id + 10)


func route_between(from: Vector3, to: Vector3) -> PackedVector3Array:
	return navigation.get_point_path(navigation.get_closest_point(from), navigation.get_closest_point(to))
