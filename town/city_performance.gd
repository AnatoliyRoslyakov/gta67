extends Node

## Frame pacing and rendering budgets; balanced and high retain the 120 Hz vehicle simulation.
signal quality_changed(level: int)

const SETTINGS_PATH := "user://gta67_graphics.cfg"
const LABELS := ["Экономия · 30 FPS", "Баланс · 60 FPS", "Качество · 60 FPS"]
var quality := 1
var loading := false
var _focused := true
var _town: Node3D
var _props: Array[MeshInstance3D] = []


func _ready() -> void:
	if ProjectSettings.get_setting("application/run/main_scene") == "res://cube/quarter.tscn":
		set_process(false)
		return
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
	_batch_static_details(scene.get_node("CityMap"))
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
	Engine.physics_ticks_per_second = 60 if quality == 0 else 120
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

# Repeated road markings and masonry share a draw per mesh, material and block.
# Keep authored nodes for the road graph, minimap, hierarchy and collisions.
func _batch_static_details(city: Node3D) -> void:
	var groups := {}
	var facade_cache := {}
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for node in city.find_children("SM_*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		var label := str(source.name)
		if not (label.begins_with("SM_Env_Road_") or label.begins_with("SM_Env_Sidewalk_") or label.begins_with("SM_Bld_")): continue
		if not source.is_visible_in_tree() or source.mesh == null or source.mesh.get_surface_count() != 1: continue
		if source.skin or source.material_overlay or source.global_basis.determinant() <= 0.0: continue
		var material := source.get_active_material(0) as StandardMaterial3D
		if not material or material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		if label.begins_with("SM_Bld_Office") or label.begins_with("SM_Bld_Apartment") or label.begins_with("SM_Bld_Shop"):
			var id := source.mesh.get_rid()
			if not facade_cache.has(id):
				var walls := PackedVector3Array()
				var faces := source.mesh.get_faces()
				for i in range(0, faces.size(), 3):
					var cross_product := (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i])
					if cross_product.length_squared() < 9.0 or absf(cross_product.normalized().y) > 0.15: continue
					walls.append(faces[i])
					walls.append(faces[i + 1])
					walls.append(faces[i + 2])
				facade_cache[id] = walls
			var local := city.global_transform.affine_inverse() * source.global_transform
			for point: Vector3 in facade_cache[id]:
				indices.append(vertices.size())
				vertices.append(local * point)
		var center := source.global_transform * source.get_aabb().get_center()
		var key := [Vector2i(floori(center.x / 36), floori(center.z / 36)), source.mesh.get_rid(), material.get_rid(), source.cast_shadow, source.layers, source.gi_mode]
		if not groups.has(key): groups[key] = []
		groups[key].append(source)
	if not vertices.is_empty():
		var occluder := ArrayOccluder3D.new()
		occluder.set_arrays(vertices, indices)
		var walls := OccluderInstance3D.new()
		walls.occluder = occluder
		city.add_child(walls)
		city.get_viewport().use_occlusion_culling = true
	for group: Array in groups.values():
		if group.size() < 4: continue
		var first: MeshInstance3D = group[0]
		var batch := MultiMeshInstance3D.new()
		var instances := MultiMesh.new()
		instances.transform_format = MultiMesh.TRANSFORM_3D
		instances.mesh = first.mesh
		instances.instance_count = group.size()
		batch.multimesh = instances
		batch.material_override = first.get_active_material(0)
		batch.cast_shadow = first.cast_shadow
		batch.layers = first.layers
		batch.gi_mode = first.gi_mode
		city.add_child(batch)
		batch.global_position = first.global_position
		var inverse := batch.global_transform.affine_inverse()
		for index in group.size():
			var source: MeshInstance3D = group[index]
			instances.set_instance_transform(index, inverse * source.global_transform)
			source.layers = 0
