extends Node

## Frame pacing and rendering budgets; gameplay physics stays at 120 Hz.
signal quality_changed(level: int)

const SETTINGS_PATH := "user://gta67_graphics.cfg"
const LABELS := ["Экономия · 30 FPS", "Баланс · 60 FPS", "Качество · 60 FPS"]
var quality := 1
var loading := false
var _focused := true
var _town: Node3D
var _props: Array[MeshInstance3D] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		quality = clampi(int(settings.get_value("graphics", "quality", 1)), 0, 2)
	_apply_rendering()


func _process(_delta: float) -> void:
	var limit := 30 if quality == 0 else 60
	if not _focused: limit = 15
	elif get_tree().paused or (not is_instance_valid(_town) and not loading): limit = 30
	if Engine.max_fps != limit: Engine.max_fps = limit


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT: _focused = false
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN: _focused = true


func bind_town(scene: Node3D) -> void:
	_town = scene
	_props.clear()
	# Only small static decoration is distance-culled. Buildings, roads, cars,
	# traffic signals and collision bodies retain their original visibility.
	for node in scene.get_node("CityMap").find_children("SM_Prop_*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		if "Light" in str(mesh.name) or "Sign" in str(mesh.name): continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if bounds.size.length() < 4.0: _props.append(mesh)
	_apply_town()


func set_quality(level: int, persist := true) -> void:
	quality = clampi(level, 0, 2)
	_apply_rendering()
	_apply_town()
	if persist:
		var settings := ConfigFile.new()
		settings.set_value("graphics", "quality", quality)
		if settings.save(SETTINGS_PATH) != OK:
			push_warning("Graphics preference could not be saved")
	quality_changed.emit(quality)


func _apply_rendering() -> void:
	var viewport := get_tree().root
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][quality]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.scaling_3d_scale = 0.8 if quality == 0 else 1.0
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if quality == 0 else Viewport.SCALING_3D_MODE_BILINEAR
	RenderingServer.directional_shadow_atlas_set_size(4096 if quality == 2 else 2048, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality == 2 else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
	RenderingServer.positional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_LOW)


func _apply_town() -> void:
	if not is_instance_valid(_town): return
	if is_instance_valid(_town.atmosphere): _town.atmosphere.set_quality(quality)
	for mesh in _props:
		if not is_instance_valid(mesh): continue
		mesh.visibility_range_end = [75.0, 120.0, 180.0][quality]
		mesh.visibility_range_end_margin = 8.0
		mesh.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
