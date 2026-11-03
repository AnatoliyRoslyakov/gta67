extends RefCounted

const RUSSIAN_KINDS := ["VAZ2101", "VAZ2105", "VAZ2106", "UAZ469", "UAZ452"]


static func model_path(kind: String) -> String:
	if kind in RUSSIAN_KINDS:
		return "res://vehicles/russian/%s.tscn" % kind
	return "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_%s_01.tscn" % kind
