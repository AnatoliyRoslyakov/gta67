extends Control

const MAP_SCALE := 1.15
const CENTER := Vector2(100, 100)
const MAP_RECT := Rect2(0, 0, 200, 200)
var player_body: Node3D
var footprints: Array[Dictionary] = []


func configure(city: Node3D, vehicle: Node3D) -> void:
	player_body = vehicle
	footprints.clear()
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
	for layer in layers: footprints.append_array(layer)
	queue_redraw()


func _draw() -> void:
	draw_rect(MAP_RECT, Color("344c49"))
	if is_instance_valid(player_body):
		var origin := Vector2(player_body.global_position.x, player_body.global_position.z)
		var colors := [Color("667473"), Color("a0aaaa"), Color("263b43")]
		for footprint in footprints:
			var world_rect: Rect2 = footprint.rect
			var rect := Rect2((world_rect.position - origin) * MAP_SCALE + CENTER, world_rect.size * MAP_SCALE)
			if rect.intersects(MAP_RECT): draw_rect(rect.intersection(MAP_RECT), colors[footprint.layer])
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
