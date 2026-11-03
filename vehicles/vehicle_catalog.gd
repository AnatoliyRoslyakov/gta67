extends RefCounted

const RUSSIAN_KINDS := ["UAZ469"]


static func model_path(kind: String) -> String:
	if kind in RUSSIAN_KINDS:
		return "res://vehicles/russian/%s.tscn" % kind
	return "res://Assets/Synty/PolygonCity/Prefabs/Vehicles/SM_Veh_Car_%s_01.tscn" % kind
