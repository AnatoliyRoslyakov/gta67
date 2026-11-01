extends RefCounted

const SAVE_PATH := "user://gta67_progress.json"
var save_path := SAVE_PATH
var cash := 500
var completed_jobs := 0
var total_earned := 0
var best_circuit := 0.0
var magazine := 12
var reserve := 84
var player_health := 100.0
var vehicle_health: Dictionary = {}
var load_warning := ""


func load_progress() -> void:
	if not FileAccess.file_exists(save_path): return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != 1:
		load_warning = "Не удалось прочитать сохранение. Исходный файл сохранён."
		return
	cash = clampi(int(parsed.get("cash", 500)), 0, 99999999)
	completed_jobs = clampi(int(parsed.get("completed_jobs", 0)), 0, 999999)
	total_earned = clampi(int(parsed.get("total_earned", 0)), 0, 99999999)
	best_circuit = clampf(float(parsed.get("best_circuit", 0)), 0, 36000)
	magazine = clampi(int(parsed.get("magazine", 12)), 0, 12)
	reserve = clampi(int(parsed.get("reserve", 84)), 0, 84)
	player_health = clampf(float(parsed.get("player_health", 100)), 1, 100)
	var cars: Variant = parsed.get("vehicle_health", {})
	if cars is Dictionary:
		for key in cars:
			if cars[key] is float or cars[key] is int:
				vehicle_health[str(key)] = clampf(float(cars[key]), 0, 100)


func save_progress() -> Error:
	# Preserve a corrupt or newer-format file instead of silently replacing it.
	if not load_warning.is_empty(): return ERR_FILE_CORRUPT
	var payload := {"version": 1, "cash": cash, "completed_jobs": completed_jobs,
		"total_earned": total_earned, "best_circuit": best_circuit,
		"magazine": magazine, "reserve": reserve, "player_health": player_health,
		"vehicle_health": vehicle_health}
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(payload))
	file.flush()
	var result := file.get_error()
	file.close()
	if result != OK: return result
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path))
