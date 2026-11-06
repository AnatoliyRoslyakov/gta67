extends Node3D

## Runtime lighting stays local to this scene; imported POLYGON materials are never saved or changed.
signal night_changed(is_night: bool)

@export_range(0.0, 24.0, 0.01) var time_of_day := 17.0
@export_range(120.0, 7200.0, 30.0) var day_duration_seconds := 1800.0
@export var cycle_enabled := true
@export var screen_space_reflections := true
@export_enum("Performance", "Balanced", "High") var quality := 1
@export_range(4, 24) var nearby_streetlight_budget := 14
@export_range(0, 12) var nearby_neon_budget := 6

var _city: Node3D
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _subject: Node3D
var _probe: ReflectionProbe
var _lamp_positions: Array[Vector3] = []
var _neon_sources: Array[Dictionary] = []
var _street_lights: Array[SpotLight3D] = []
var _neon_lights: Array[OmniLight3D] = []
const SIGN_LAYER := 1 << 8
var _room_masks: Array[ImageTexture] = []
var _room_materials: Array[StandardMaterial3D] = []
var _emission_materials: Array[StandardMaterial3D] = []
var _road_materials: Array[StandardMaterial3D] = []
var _cloud_materials: Array[StandardMaterial3D] = []
var _lamp_materials: Array[StandardMaterial3D] = []
var _material_cache: Dictionary = {}
var _update_timer := 0.0
var _local_timer := 0.0
var _probe_timer := 0.0
var _night_amount := 0.0
var _is_night := false
var _forward_plus := false
var _configured := false
var _time_update_interval := 0.5
var _last_applied_hour := -INF
var _last_palette := Vector2(INF, INF)
var _last_material_night := -1.0
var _selection_dirty := true
var _lights_enabled := false
var _last_selection_position := Vector3.INF
var _street_source_ids: Array[int] = []
var _neon_source_ids: Array[int] = []
var _neon_positions: Array[Vector3] = []
var _street_effective_budget := 14
var _neon_effective_budget := 6
var _street_shadow_budget := 1
var _selection_distance := 4.0
var _probe_capture_age := 1000.0
var _probe_capture_interval := 15.0
var _probe_last_hour := -100.0
var _probe_last_light := Vector2(-1.0, -1.0)
var _probe_nudge := 1.0
var _lamp_lens_transforms: Array[Transform3D] = []
var _window_signs := 0
var _window_letters: Array[TextMesh] = []
var _lamp_lenses: MultiMeshInstance3D


func configure(city_map: Node3D, sun: DirectionalLight3D, world_env: WorldEnvironment, player_body: Node3D) -> void:
	_city = city_map
	_sun = sun
	_subject = player_body
	_forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"
	_environment = world_env.environment.duplicate(true) as Environment
	world_env.environment = _environment
	_environment.background_mode = Environment.BG_SKY
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.sdfgi_enabled = false
	_environment.volumetric_fog_enabled = false
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.glow_enabled = _forward_plus
	_environment.glow_intensity = 0.35
	_environment.glow_bloom = 0.0
	_environment.glow_hdr_threshold = 1.3
	_environment.adjustment_enabled = true
	_environment.adjustment_contrast = 1.045
	_environment.adjustment_saturation = 0.96
	_environment.ssr_max_steps = 32
	_environment.ssr_depth_tolerance = 0.3
	_environment.fog_enabled = true
	_environment.fog_sky_affect = 0.35
	_environment.fog_aerial_perspective = 0.35
	var sky := Sky.new()
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_curve = 0.16
	_sky_material.ground_curve = 0.06
	_sky_material.sun_angle_max = 5.0
	_sky_material.sun_curve = 0.08
	sky.sky_material = _sky_material
	_environment.sky = sky
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	_sun.light_angular_distance = 0.7
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_moon = DirectionalLight3D.new()
	_moon.name = "Moonlight"
	_moon.light_color = Color("91a8d7")
	_moon.shadow_enabled = false
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	_discover_fixtures()
	_build_lamp_lenses()
	_create_light_pools()
	_create_probe()
	_configured = true
	_apply_quality()
	_apply_time(true)
	_update_nearby_lights(true)
	_refresh_probe(true)


func set_subject(subject: Node3D) -> void:
	_subject = subject
	_selection_dirty = true
	_local_timer = 0.0


func set_hour(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	if _configured:
		_apply_time(true)
		_update_nearby_lights(true)
		_refresh_probe(true)
		_update_timer = _time_update_interval


func advance_period() -> void:
	var periods := [6.5, 12.0, 17.5, 22.0]
	for hour in periods:
		if hour > time_of_day + 0.5:
			set_hour(hour)
			return
	set_hour(periods[0])


func get_clock_text() -> String:
	var minutes := int(time_of_day * 60.0) % 1440
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func is_night() -> bool:
	return _is_night


func _process(delta: float) -> void:
	if not _configured: return
	if cycle_enabled:
		time_of_day = fposmod(time_of_day + delta * 24.0 / day_duration_seconds, 24.0)
	_update_timer -= delta
	_local_timer -= delta
	_probe_timer -= delta
	_probe_capture_age += delta
	if _update_timer <= 0.0:
		_update_timer = _time_update_interval
		_apply_time()
	if _local_timer <= 0.0:
		_local_timer = 0.6
		_update_nearby_lights()
	if _probe_timer <= 0.0:
		_probe_timer = 1.0
		_refresh_probe()


func _apply_time(force := false) -> void:
	if not force and is_equal_approx(time_of_day, _last_applied_hour): return
	_last_applied_hour = time_of_day
	var solar_phase := (time_of_day - 6.0) / 24.0 * TAU
	var altitude := sin(solar_phase)
	var daylight := smoothstep(-0.08, 0.3, altitude)
	var golden := 1.0 - smoothstep(0.12, 0.55, maxf(altitude, 0.0))
	_night_amount = 1.0 - smoothstep(-0.12, 0.12, altitude)
	_sun.visible = daylight > 0.01
	if _sun.visible:
		_sun.rotation_degrees = Vector3(-altitude * 72.0, -115.0 + (time_of_day - 12.0) * 12.0, 0)
		_sun.light_color = Color("fff1d9").lerp(Color("ffb478"), golden)
		_sun.light_energy = daylight * lerpf(1.0, 1.65, smoothstep(0.0, 0.7, altitude))
	else:
		_sun.light_energy = 0.0
	_moon.visible = _night_amount > 0.01
	if _moon.visible:
		_moon.rotation_degrees = Vector3(-48.0, 55.0 + time_of_day * 6.0, 0)
		_moon.light_energy = _night_amount * 0.47
	var palette := Vector2(daylight, golden)
	# Constant noon/night colours must not repeatedly invalidate the sky radiance map.
	if force or palette.distance_squared_to(_last_palette) > 0.000004:
		_last_palette = palette
		_sky_material.sky_top_color = Color("101c3a").lerp(Color("426e9c"), daylight)
		var horizon := Color("bed5dc").lerp(Color("edac8d"), golden)
		_sky_material.sky_horizon_color = Color("323447").lerp(horizon, daylight)
		_sky_material.ground_horizon_color = _sky_material.sky_horizon_color
		_sky_material.ground_bottom_color = Color("192331").lerp(Color("626669"), daylight)
		_sky_material.energy_multiplier = lerpf(0.65, 1.0, daylight)
		_environment.ambient_light_color = Color("8092c2").lerp(Color("b4c4db"), daylight)
		_environment.ambient_light_energy = lerpf(0.39, 0.48, daylight)
		_environment.tonemap_exposure = lerpf(1.1, 0.95, daylight)
		_environment.fog_light_color = Color("252e48").lerp(horizon, daylight)
		_environment.fog_light_energy = lerpf(0.5, 0.85, daylight)
		_environment.fog_density = lerpf(0.0016, 0.00075, daylight) + golden * daylight * 0.0011
		for material in _cloud_materials:
			material.albedo_color = Color("56617b").lerp(Color("d9e1e5").lerp(Color("e4c8b8"), golden * 0.5), daylight)
	_environment.ssr_enabled = _forward_plus and screen_space_reflections and _night_amount > 0.15
	if force or absf(_night_amount - _last_material_night) > 0.002:
		_last_material_night = _night_amount
		for material in _emission_materials:
			material.emission_energy_multiplier = 0.54 * _night_amount
		for material in _room_materials:
			material.emission_energy_multiplier = 0.82 * _night_amount
		for material in _lamp_materials:
			material.emission_energy_multiplier = lerpf(0.0, 1.15, _night_amount)
		for material in _road_materials:
			material.roughness = lerpf(0.8, 0.38, _night_amount)
		_update_light_energy()
	if (_night_amount > 0.02) != _lights_enabled:
		_selection_dirty = true
		_local_timer = 0.0
	var night_now := _night_amount > 0.5
	if night_now != _is_night:
		_is_night = night_now
		night_changed.emit(_is_night)


func _discover_fixtures() -> void:
	var lamp_cells: Dictionary = {}
	for node in _city.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree(): continue
		var mesh_name := str(mesh.name)
		if mesh.scene_file_path.ends_with("SM_Prop_LightPole_Base_01.tscn"):
			# The actual streetlamp is part of Base_01. LightPole_Lights are
			# traffic signal housings and must not become white street lamps.
			var lamp_transform := mesh.global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 6.22, 1.9635))
			var p := lamp_transform.origin
			var cell := Vector2i(roundi(p.x / 2), roundi(p.z / 2))
			if not lamp_cells.has(cell):
				lamp_cells[cell] = true
				_lamp_positions.append(p - Vector3.UP * 0.06)
				_add_lamp_lens(lamp_transform)
		elif "SM_Env_Cloud_" in mesh_name:
			_override_materials(mesh, "cloud", Color.WHITE)
		elif _is_neon_sign(mesh_name):
			var color: Color = [Color("f08fb5"), Color("82d6df"), Color("ffc582")][_neon_sources.size() % 3]
			var center: Vector3 = mesh.global_transform * mesh.get_aabb().get_center()
			_neon_sources.append({"position": center, "color": color})
			_neon_positions.append(center)
			mesh.layers = SIGN_LAYER
			_override_materials(mesh, "neon", Color.WHITE)
		elif ("SM_Bld_Apartment" in mesh_name or "SM_Bld_Office" in mesh_name) and "Glass" not in mesh_name:
			var variant := posmod(hash(mesh.global_position.round()), 6)
			_override_materials(mesh, "rooms%d" % variant, Color.WHITE)
		elif mesh_name.begins_with("SM_Env_Road_Bare_") or mesh_name.begins_with("SM_Env_Road_0"):
			_override_materials(mesh, "road", Color.WHITE)
		elif "Glass" in mesh_name and mesh_name.begins_with("SM_Bld_"):
			var pos := mesh.global_position
			var district_tint: Color = [Color("eeb57c"), Color("9bc9d7"), Color("f4dcad"), Color("3e526a")][posmod(hash(Vector2i(roundi(pos.x), roundi(pos.z))), 4)]
			_override_materials(mesh, "glass", district_tint)
			if "Shop" in mesh_name and _window_signs < 12:
				_add_window_sign(mesh)


# Use an actual pane as the mounting plane so lettering follows rotated shops.
func _add_window_sign(window: MeshInstance3D) -> void:
	var faces := window.mesh.get_faces()
	var largest := 0.0
	var center := Vector3.ZERO
	var outward := Vector3.ZERO
	for i in range(0, faces.size(), 3):
		var a := window.global_transform * faces[i]
		var b := window.global_transform * faces[i + 1]
		var c := window.global_transform * faces[i + 2]
		var normal := (c - a).cross(b - a)
		var area := normal.length()
		if area <= largest or absf(normal.y) > area * 0.1: continue
		largest = area
		outward = normal / area
		center = (a + b + c) / 3.0
	if largest < 1.0: return
	if _window_letters.is_empty():
		for word in ["OPEN", "LATE", "24 H"]:
			var letters := TextMesh.new()
			letters.text = word
			letters.font_size = 36
			letters.pixel_size = 0.009
			letters.depth = 0.012
			var tint: Color = [Color("ff688e"), Color("51d9ef"), Color("ffbb61")][_window_letters.size()]
			var finish := StandardMaterial3D.new()
			finish.albedo_color = tint
			finish.emission_enabled = true
			finish.emission = tint
			letters.material = finish
			_emission_materials.append(finish)
			_window_letters.append(letters)
	var sign_mesh := MeshInstance3D.new()
	sign_mesh.layers = SIGN_LAYER
	sign_mesh.mesh = _window_letters[_window_signs % _window_letters.size()]
	sign_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sign_mesh.visibility_range_end = 75
	add_child(sign_mesh)
	sign_mesh.global_transform = Transform3D(Basis.looking_at(outward, Vector3.UP, true), center + outward * 0.025)
	_window_signs += 1


func _is_neon_sign(mesh_name: String) -> bool:
	if not mesh_name.begins_with("SM_Prop_"): return false
	for keyword in ["Sign_Hotel", "Sign_Cafe", "Sign_Bar_", "Sign_Pub", "Sign_Barber", "Sign_XXX", "Sign_Chinese", "Sign_Pizza", "Sign_DeliPizza", "LargeSign_"]:
		if keyword in mesh_name: return true
	return false


# Residential and office models share three pane swatches in the bottom
# strip of their UV atlas. The masonry, frames and sills sample black.
func _room_mask(variant: int) -> ImageTexture:
	if _room_masks.is_empty():
		for layout in 6:
			var mask := Image.create_empty(256, 256, false, Image.FORMAT_RGB8)
			mask.fill(Color.BLACK)
			var palette := [Color("ffd48b"), Color("e7bd8a"), Color("b2d2e1"), Color("171e2b")]
			for pane in 3:
				var color: Color = palette[(layout + pane * 3 + int(layout / 3) * pane) % 4]
				for y in range(228, 256):
					var shade := lerpf(0.48, 1.0, (y - 228) / 27.0)
					var left := 128 + 28 * pane
					mask.fill_rect(Rect2i(left, y, 28, 1), color.darkened(1.0 - shade))
					# A partly drawn curtain breaks up broad uninterrupted office panes.
					var curtain := 4 + (layout + pane) % 7
					mask.fill_rect(Rect2i(left, y, curtain, 1), color.darkened(0.75))
			mask.generate_mipmaps()
			_room_masks.append(ImageTexture.create_from_image(mask))
	return _room_masks[variant]


func _override_materials(mesh: MeshInstance3D, category: String, tint: Color) -> void:
	for surface in mesh.mesh.get_surface_count():
		var original := mesh.get_active_material(surface) as StandardMaterial3D
		if original == null: continue
		var key := "%s:%d:%s" % [category, original.get_instance_id(), tint.to_html()]
		var material: StandardMaterial3D
		if _material_cache.has(key):
			material = _material_cache[key]
		else:
			material = original.duplicate() as StandardMaterial3D
			if category == "neon":
				material.emission_enabled = true
				material.emission = Color.BLACK
				material.emission_texture = original.albedo_texture
				material.emission_energy_multiplier = 0.0
				_emission_materials.append(material)
			elif category.begins_with("rooms"):
				material.emission_enabled = true
				material.emission = Color.BLACK
				material.emission_texture = _room_mask(category.trim_prefix("rooms").to_int())
				_room_materials.append(material)
			elif category == "cloud":
				# Imported clouds have unconditional white emission, even at midnight.
				material.emission_enabled = false
				material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				material.roughness = 1.0
				_cloud_materials.append(material)
			elif category == "road":
				material.metallic = 0.05
				material.roughness = 0.8
				_road_materials.append(material)
			elif category == "glass":
				material.emission_enabled = true
				material.emission = tint
				_lamp_materials.append(material)
				material.roughness = 0.15
				material.metallic = 0.15
			_material_cache[key] = material
		mesh.set_surface_override_material(surface, material)


func _add_lamp_lens(lamp_transform: Transform3D) -> void:
	_lamp_lens_transforms.append(global_transform.affine_inverse() * lamp_transform)


func _build_lamp_lenses() -> void:
	if _lamp_lens_transforms.is_empty(): return
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff2ce")
	material.emission_enabled = true
	material.emission = Color("ffdcac")
	_lamp_materials.append(material)
	var globe := BoxMesh.new()
	globe.size = Vector3(0.15, 0.012, 0.46)
	globe.material = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.mesh = globe
	instances.instance_count = _lamp_lens_transforms.size()
	var bounds := AABB()
	for i in _lamp_lens_transforms.size():
		var transform := _lamp_lens_transforms[i]
		instances.set_instance_transform(i, transform)
		var lens_bounds: AABB = transform * globe.get_aabb()
		bounds = lens_bounds if i == 0 else bounds.merge(lens_bounds)
	instances.custom_aabb = bounds
	_lamp_lenses = MultiMeshInstance3D.new()
	_lamp_lenses.name = "StreetlampLenses"
	_lamp_lenses.multimesh = instances
	_lamp_lenses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lamp_lenses)


func _create_light_pools() -> void:
	for i in nearby_streetlight_budget:
		var light := SpotLight3D.new()
		light.rotation_degrees.x = -90.0
		light.light_color = Color("ffddad")
		light.spot_range = 16.0
		light.spot_angle = 68.0
		light.spot_attenuation = 1.0
		light.spot_angle_attenuation = 0.65
		light.shadow_enabled = false
		light.distance_fade_shadow = 30.0
		light.distance_fade_enabled = true
		light.distance_fade_begin = 65.0
		light.distance_fade_length = 20.0
		light.visible = false
		add_child(light)
		_street_lights.append(light)
		_street_source_ids.append(-1)
	for _i in nearby_neon_budget:
		var light := OmniLight3D.new()
		light.light_cull_mask &= ~SIGN_LAYER
		light.omni_range = 6.0
		light.omni_attenuation = 1.7
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 35.0
		light.distance_fade_length = 15.0
		light.visible = false
		add_child(light)
		_neon_lights.append(light)
		_neon_source_ids.append(-1)


func _update_nearby_lights(force := false) -> void:
	if not is_instance_valid(_subject): return
	var enabled := _night_amount > 0.02
	if not enabled:
		if _lights_enabled or force:
			for light in _street_lights:
				light.visible = false
				light.shadow_enabled = false
			for light in _neon_lights: light.visible = false
		_lights_enabled = false
		return
	var subject_position := _subject.global_position
	if not force and not _selection_dirty and _lights_enabled and subject_position.distance_squared_to(_last_selection_position) < _selection_distance * _selection_distance:
		return
	_selection_dirty = false
	_lights_enabled = true
	_last_selection_position = subject_position
	var streets := _nearest_sources(_lamp_positions, _street_source_ids, _street_effective_budget, 85.0, subject_position)
	var neons := _nearest_sources(_neon_positions, _neon_source_ids, _neon_effective_budget, 50.0, subject_position)
	_assign_sources(_street_lights, _street_source_ids, streets, _lamp_positions, false)
	_assign_sources(_neon_lights, _neon_source_ids, neons, _neon_positions, true)
	var shadow_distance := 45.0 if quality == 2 else 30.0
	for slot in _street_lights.size():
		var source := _street_source_ids[slot]
		var rank := streets.find(source)
		_street_lights[slot].shadow_enabled = rank >= 0 and rank < _street_shadow_budget and _lamp_positions[source].distance_squared_to(subject_position) < shadow_distance * shadow_distance
	_update_light_energy()


func _nearest_sources(positions: Array[Vector3], previous: Array[int], budget: int, radius: float, origin: Vector3) -> Array[int]:
	var selected: Array[int] = []
	var distances: Array[float] = []
	distances.resize(positions.size())
	for i in positions.size():
		var distance := positions[i].distance_squared_to(origin)
		# A small retention bias prevents pool slots swapping at distance ties.
		distances[i] = distance * (0.90 if i in previous else 1.0)
		if distance < radius * radius: selected.append(i)
	selected.sort_custom(func(a: int, b: int) -> bool: return distances[a] < distances[b])
	if selected.size() > budget: selected.resize(budget)
	return selected


func _assign_sources(lights: Array, slots: Array[int], selected: Array[int], positions: Array[Vector3], neon: bool) -> void:
	# Keep each physical lamp in its existing slot, including its cached shadow map.
	for i in slots.size():
		if slots[i] not in selected:
			slots[i] = -1
			lights[i].visible = false
	for source in selected:
		var slot := slots.find(source)
		if slot < 0:
			slot = slots.find(-1)
			if slot < 0: break
			slots[slot] = source
			lights[slot].global_position = positions[source]
			if neon: lights[slot].light_color = _neon_sources[source].color
		lights[slot].visible = true


func _update_light_energy() -> void:
	for light in _street_lights: light.light_energy = 2.6 * _night_amount
	for light in _neon_lights: light.light_energy = 0.55 * _night_amount


func _create_probe() -> void:
	_probe = ReflectionProbe.new()
	_probe.name = "LocalStreetReflections"
	_probe.size = Vector3(130, 65, 130)
	_probe.max_distance = 95.0
	_probe.box_projection = true
	_probe.enable_shadows = false
	_probe.mesh_lod_threshold = 3.0
	_probe.update_mode = ReflectionProbe.UPDATE_ONCE
	_probe.blend_distance = 15.0
	add_child(_probe)


func _refresh_probe(force := false) -> void:
	if not is_instance_valid(_subject) or not is_instance_valid(_probe): return
	if not force and _probe_capture_age < _probe_capture_interval: return
	var target := _subject.global_position + Vector3.UP * 4.0
	var moved := _probe.global_position.distance_squared_to(target) > 35.0 * 35.0
	var hour_delta := absf(wrapf(time_of_day - _probe_last_hour, -12.0, 12.0))
	var light_state := Vector2(_environment.ambient_light_energy, _night_amount)
	var lighting_changed := hour_delta >= (0.4 if quality == 2 else 0.75) or absf(light_state.y - _probe_last_light.y) > 0.12 or absf(light_state.x - _probe_last_light.x) > 0.06
	if not force and not moved and not lighting_changed: return
	_probe_capture_age = 0.0
	_probe_last_hour = time_of_day
	_probe_last_light = light_state
	# UPDATE_ONCE renders six faces. Only request them for a changed view/lighting.
	_probe_nudge = -_probe_nudge
	_probe.global_position = target + Vector3(_probe_nudge * 0.001, 0.0, 0.0)


func set_quality(level: int) -> void:
	var selected := clampi(level, 0, 2)
	if selected == quality: return
	quality = selected
	if not _configured: return
	_apply_quality()
	_apply_time(true)
	_update_nearby_lights(true)
	_refresh_probe(true)


func _apply_quality() -> void:
	quality = clampi(quality, 0, 2)
	_time_update_interval = [1.0, 0.5, 0.25][quality]
	_street_effective_budget = mini(_street_lights.size(), 8 if quality == 0 else nearby_streetlight_budget)
	_neon_effective_budget = mini(_neon_lights.size(), 3 if quality == 0 else nearby_neon_budget)
	_street_shadow_budget = [0, 1, 2][quality]
	_selection_distance = [6.0, 4.0, 3.0][quality]
	_probe_capture_interval = [25.0, 15.0, 8.0][quality]
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if quality == 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	_sun.directional_shadow_max_distance = 90.0 if quality == 0 else 150.0
	# Preserve the first 15m cascade; savings come from merging the farther cascades.
	_sun.directional_shadow_split_1 = 15.0 / _sun.directional_shadow_max_distance
	_environment.sky.radiance_size = Sky.RADIANCE_SIZE_64 if quality == 0 else Sky.RADIANCE_SIZE_128
	_environment.ssr_max_steps = [12, 24, 32][quality]
	_probe.mesh_lod_threshold = [6.0, 4.0, 3.0][quality]
	for light in _street_lights: light.distance_fade_shadow = 45.0 if quality == 2 else 30.0
	_selection_dirty = true
	_update_timer = 0.0
	_local_timer = 0.0
