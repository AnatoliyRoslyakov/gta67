extends "res://town/traffic/traffic_world.gd"

# The same lane builder, Jolt drivers, signals and citizen controllers as 3.0.
# Their input cells are baked from this slice of the original map.
func _extract_surfaces() -> void:
	road_cells = city_map.get_meta("road_cells")
	sidewalk_cells = city_map.get_meta("sidewalk_cells")

func _stream_street_population() -> void:
	# The whole district fits inside the case. Never relocate visible actors.
	pass
