extends "res://town/traffic/traffic_world.gd"

# The same lane builder, Jolt drivers, signals and citizen controllers as 3.0.
# Their input cells are baked from this slice of the original map.
func _extract_surfaces() -> void:
	road_cells = city_map.get_meta("road_cells")
	sidewalk_cells = city_map.get_meta("sidewalk_cells")

func _stream_street_population() -> void:
	# The whole district fits inside the case. Never relocate visible actors.
	pass

var restarting := false

func restart_cars() -> void:
	if restarting or not initialized: return
	restarting = true
	for i in junctions.size(): _release_junction(i)
	for car in drivers: car.queue_free()
	drivers.clear()
	_rebuild_driver_index()
	await get_tree().process_frame
	await get_tree().physics_frame
	await _spawn_drivers()
	_rebuild_driver_index()
	restarting = false

func spawn_snail() -> void:
	var candidates := walk_neighbors.keys()
	candidates.sort_custom(func(a,b):return walk_position(a).distance_squared_to(Vector3.ZERO)<walk_position(b).distance_squared_to(Vector3.ZERO))
	for c in candidates:
		var p := walk_position(c)
		if walk_neighbors[c].size()<2 or not _spawn_clear(p,Vector3(1.1,1.7,1.9)): continue
		var guest := preload("res://cube/snail_rider.gd").new()
		guest.world = self
		guest.cell = c
		guest.walk_speed = 1.2
		guest.position = p+Vector3.UP*.04
		add_child(guest)
		citizens.append(guest)
		return
