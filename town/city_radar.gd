extends Control

const MAP_SCALE := 1.15
const CENTER := Vector2(100, 100)
const MAP_RECT := Rect2(0, 0, 200, 200)
var player_body: Node3D
var map_texture: ImageTexture
var map_origin := Vector2.ZERO
var navigation: Dictionary = {}


func set_navigation(state: Dictionary) -> void:
	navigation = state
	# The HUD redraws at 20 Hz; several state updates in one frame coalesce.


func configure(city: Node3D, vehicle: Node3D) -> void:
	player_body = vehicle
	var layers: Array[Array] = [[], [], []]
	var seen: Dictionary = {}
	for node in city.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null or not mesh_node.is_visible_in_tree(): continue
		var mesh_name := str(mesh_node.name)
		var layer := -1
		if mesh_name.begins_with("SM_Env_Sidewalk_"): layer = 0
		elif mesh_name.begins_with("SM_Env_Road_Bare_") or mesh_name.begins_with("SM_Env_Road_0"): layer = 1
		elif mesh_name.begins_with("SM_Bld_") and not "Glass" in mesh_name: layer = 2
		if layer < 0: continue
		var bounds: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
		if rect.size.x < 0.5 or rect.size.y < 0.5: continue
		var key := "%d:%d:%d:%d:%d" % [layer, roundi(rect.position.x), roundi(rect.position.y), roundi(rect.size.x), roundi(rect.size.y)]
		if seen.has(key): continue
		seen[key] = true
		layers[layer].append({"rect": rect, "layer": layer})
	var bounds := Rect2()
	for layer in layers:
		for item in layer: bounds = bounds.merge(item.rect)
	map_origin = bounds.position.floor()
	var pixels := Vector2i(((bounds.end - map_origin) * MAP_SCALE).ceil())
	var baked := Image.create_empty(maxi(1, pixels.x), maxi(1, pixels.y), false, Image.FORMAT_RGB8)
	baked.fill(Color("344c49"))
	var colors := [Color("667473"), Color("a0aaaa"), Color("263b43")]
	for layer in layers:
		for item in layer:
			var area: Rect2 = item.rect
			baked.fill_rect(Rect2i(Vector2i(((area.position - map_origin) * MAP_SCALE).floor()), Vector2i((area.size * MAP_SCALE).ceil())), colors[item.layer])
	map_texture = ImageTexture.create_from_image(baked)
	queue_redraw()


func _draw() -> void:
	draw_rect(MAP_RECT, Color("344c49"))
	if is_instance_valid(player_body):
		var origin := Vector2(player_body.global_position.x, player_body.global_position.z)
		if map_texture:
			var source := Rect2((origin - map_origin) * MAP_SCALE - CENTER, MAP_RECT.size)
			var clipped := source.intersection(Rect2(Vector2.ZERO, map_texture.get_size()))
			if clipped.has_area():
				draw_texture_rect_region(map_texture, Rect2(clipped.position - source.position, clipped.size), clipped)
		_draw_navigation(origin)
		var forward := player_body.global_basis.z
		if player_body is CharacterBody3D:
			forward = Vector3(-sin(player_body.yaw), 0, -cos(player_body.yaw))
		var heading := atan2(forward.x, -forward.z)
		var arrow := PackedVector2Array([Vector2(0, -9), Vector2(-6, 7), Vector2(0, 4), Vector2(6, 7)])
		for i in arrow.size(): arrow[i] = arrow[i].rotated(heading) + CENTER
		draw_circle(CENTER, 11, Color(0.05, 0.08, 0.1, 0.5))
		draw_colored_polygon(arrow, Color("fff0d7"))
	draw_rect(MAP_RECT.grow(-1), Color("b6c7c1"), false, 2)
	draw_string(ThemeDB.fallback_font, Vector2(10, 19), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("f1eee0"))


func _draw_navigation(origin: Vector2) -> void:
	var route: Array = navigation.get("route", [])
	var points := PackedVector2Array()
	for point in route:
		if point is Vector3: points.append(_map_point(point, origin))
	if points.size() > 1:
		draw_polyline(points, Color(0.12, 0.12, 0.08, 0.7), 6, true)
		draw_polyline(points, Color("f0c574"), 3, true)
	var service: Vector3 = navigation.get("service_position", Vector3.INF)
	if service.is_finite(): _marker(_map_point(service, origin), Color("74cfc7"), "S")
	if navigation.get("on_foot", false):
		var car: Vector3 = navigation.get("car_position", Vector3.INF)
		if car.is_finite(): _marker(_map_point(car, origin), Color("dfe8ee"), "C")
	for police in navigation.get("police", []):
		if not police is Vector3: continue
		var p := _clamped_point(_map_point(police, origin))
		draw_circle(p, 5.5, Color("172531"))
		draw_circle(p, 3.5, Color("ed817b"))
		if Rect2(8, 8, 184, 184).has_point(_map_point(police, origin)):
			draw_arc(p, 6.5, -PI * 0.85, -PI * 0.15, 8, Color("95bfe4"), 1.5, true)
	if navigation.get("active", false):
		var target: Vector3 = navigation.get("target", Vector3.INF)
		if target.is_finite():
			var point := _map_point(target, origin)
			var p := _clamped_point(point)
			var diamond := PackedVector2Array([p + Vector2(0, -7), p + Vector2(7, 0), p + Vector2(0, 7), p + Vector2(-7, 0)])
			draw_colored_polygon(diamond, Color("f0c574"))
			draw_circle(p, 2, Color("283738"))
			if p.distance_to(point) > 1:
				var direction := (point - CENTER).normalized()
				draw_line(p - direction * 3, p + direction * 4, Color("283738"), 2, true)


func _map_point(point: Vector3, origin: Vector2) -> Vector2:
	return (Vector2(point.x, point.z) - origin) * MAP_SCALE + CENTER


func _clamped_point(point: Vector2) -> Vector2:
	# Radial clipping keeps the bearing correct when the objective is off-screen.
	var offset := point - CENTER
	var extent := maxf(absf(offset.x), absf(offset.y))
	return CENTER + offset * minf(1.0, 88.0 / maxf(extent, 0.001))


func _marker(point: Vector2, color: Color, letter: String) -> void:
	var p := _clamped_point(point)
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), Color("172531"))
	draw_rect(Rect2(p - Vector2(6, 6), Vector2(12, 12)), color, false, 1.5)
	draw_string(ThemeDB.fallback_font, p + Vector2(-3.5, 4), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
