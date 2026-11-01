extends Node3D

## Runtime lighting stays local to this scene; imported POLYGON materials are never saved or changed.
signal night_changed(is_night: bool)

@export_range(0.0, 24.0, 0.01) var time_of_day := 17.0
@export_range(120.0, 7200.0, 30.0) var day_duration_seconds := 1800.0
@export var cycle_enabled := true
@export var screen_space_reflections := true
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
	_create_light_pools()
	_create_probe()
	_configured = true
	_apply_time()
	_update_nearby_lights()


func set_subject(subject: Node3D) -> void:
	_subject = subject
	_local_timer = 0.0


func set_hour(hour: float) -> void:
	time_of_day = fposmod(hour, 24.0)
	if _configured:
		_apply_time()
		_update_nearby_lights()
		_refresh_probe(true)


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
	if _update_timer <= 0.0:
		_update_timer = 0.15
		_apply_time()
	if _local_timer <= 0.0:
		_local_timer = 0.6
		_update_nearby_lights()
	if _probe_timer <= 0.0:
		_probe_timer = 15.0
		_refresh_probe()


func _apply_time() -> void:
	var solar_phase := (time_of_day - 6.0) / 24.0 * TAU
	var altitude := sin(solar_phase)
	var daylight := smoothstep(-0.08, 0.3, altitude)
	var golden := 1.0 - smoothstep(0.12, 0.55, maxf(altitude, 0.0))
	_night_amount = 1.0 - smoothstep(-0.12, 0.12, altitude)
	_sun.rotation_degrees = Vector3(-altitude * 72.0, -115.0 + (time_of_day - 12.0) * 12.0, 0)
	_sun.light_color = Color("fff1d9").lerp(Color("ffb478"), golden)
	_sun.light_energy = daylight * lerpf(1.0, 1.65, smoothstep(0.0, 0.7, altitude))
	_sun.visible = daylight > 0.01
	_moon.rotation_degrees = Vector3(-48.0, 55.0 + time_of_day * 6.0, 0)
	_moon.light_energy = _night_amount * 0.24
	_moon.visible = _night_amount > 0.01
	_sky_material.sky_top_color = Color("101c3a").lerp(Color("426e9c"), daylight)
	var horizon := Color("bed5dc").lerp(Color("edac8d"), golden)
	_sky_material.sky_horizon_color = Color("323447").lerp(horizon, daylight)
	_sky_material.ground_horizon_color = _sky_material.sky_horizon_color
	_sky_material.ground_bottom_color = Color("192331").lerp(Color("626669"), daylight)
	_sky_material.energy_multiplier = lerpf(0.65, 1.0, daylight)
	_environment.ambient_light_color = Color("8092c2").lerp(Color("b4c4db"), daylight)
	_environment.ambient_light_energy = lerpf(0.18, 0.48, daylight)
	_environment.tonemap_exposure = lerpf(1.1, 0.95, daylight)
	_environment.fog_light_color = Color("252e48").lerp(horizon, daylight)
	_environment.fog_light_energy = lerpf(0.5, 0.85, daylight)
	_environment.fog_density = lerpf(0.0016, 0.00075, daylight) + golden * daylight * 0.0003
	_environment.ssr_enabled = _forward_plus and screen_space_reflections and _night_amount > 0.15
	for material in _emission_materials:
		material.emission_energy_multiplier = lerpf(0.02, 1.45, _night_amount)
	for material in _lamp_materials:
		material.emission_energy_multiplier = lerpf(0.0, 1.15, _night_amount)
	for material in _cloud_materials:
		material.albedo_color = Color("56617b").lerp(Color("d9e1e5").lerp(Color("e4c8b8"), golden * 0.5), daylight)
	for material in _road_materials:
		material.roughness = lerpf(0.8, 0.38, _night_amount)
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
			_override_materials(mesh, "neon", color)
		elif mesh_name.begins_with("SM_Env_Road_Bare_") or mesh_name.begins_with("SM_Env_Road_0"):
			_override_materials(mesh, "road", Color.WHITE)
		elif "Glass" in mesh_name and mesh_name.begins_with("SM_Bld_"):
			_override_materials(mesh, "glass", Color.WHITE)


func _is_neon_sign(mesh_name: String) -> bool:
	if not mesh_name.begins_with("SM_Prop_"): return false
	for keyword in ["Sign_Hotel", "Sign_Cafe", "Sign_Bar_", "Sign_Pub", "Sign_Chinese", "Sign_Pizza", "Sign_DeliPizza", "LargeSign_"]:
		if keyword in mesh_name: return true
	return false


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
				material.emission = tint
				material.emission_texture = original.albedo_texture
				material.emission_energy_multiplier = 0.0
				_emission_materials.append(material)
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
				material.roughness = 0.15
				material.metallic = 0.15
			_material_cache[key] = material
		mesh.set_surface_override_material(surface, material)


func _add_lamp_lens(lamp_transform: Transform3D) -> void:
	var lens := MeshInstance3D.new()
	var globe := BoxMesh.new()
	globe.size = Vector3(0.15, 0.012, 0.46)
	var material: StandardMaterial3D
	if _material_cache.has("lamp_lens"):
		material = _material_cache["lamp_lens"]
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = Color("fff2ce")
		material.emission_enabled = true
		material.emission = Color("ffdcac")
		_lamp_materials.append(material)
		_material_cache["lamp_lens"] = material
	globe.material = material
	lens.mesh = globe
	lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lens)
	lens.global_transform = lamp_transform


func _create_light_pools() -> void:
	for i in nearby_streetlight_budget:
		var light := SpotLight3D.new()
		light.rotation_degrees.x = -90.0
		light.light_color = Color("ffddad")
		light.spot_range = 16.0
		light.spot_angle = 68.0
		light.spot_attenuation = 1.0
		light.spot_angle_attenuation = 0.65
		light.shadow_enabled = i < 2
		light.distance_fade_enabled = true
		light.distance_fade_begin = 65.0
		light.distance_fade_length = 20.0
		light.visible = false
		add_child(light)
		_street_lights.append(light)
	for _i in nearby_neon_budget:
		var light := OmniLight3D.new()
		light.omni_range = 8.0
		light.omni_attenuation = 1.7
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 35.0
		light.distance_fade_length = 15.0
		light.visible = false
		add_child(light)
		_neon_lights.append(light)


func _update_nearby_lights() -> void:
	if not is_instance_valid(_subject): return
	var subject_position := _subject.global_position
	_lamp_positions.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_squared_to(subject_position) < b.distance_squared_to(subject_position))
	for i in _street_lights.size():
		var light := _street_lights[i]
		light.visible = _night_amount > 0.02 and i < _lamp_positions.size() and _lamp_positions[i].distance_squared_to(subject_position) < 85.0 * 85.0
		if light.visible:
			light.global_position = _lamp_positions[i]
			light.light_energy = 2.6 * _night_amount
	_neon_sources.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.position.distance_squared_to(subject_position) < b.position.distance_squared_to(subject_position))
	for i in _neon_lights.size():
		var light := _neon_lights[i]
		light.visible = _night_amount > 0.02 and i < _neon_sources.size() and _neon_sources[i].position.distance_squared_to(subject_position) < 50.0 * 50.0
		if light.visible:
			light.global_position = _neon_sources[i].position
			light.light_color = _neon_sources[i].color
			light.light_energy = 1.4 * _night_amount


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
	_refresh_probe(true)


func _refresh_probe(force := false) -> void:
	if not is_instance_valid(_subject) or not is_instance_valid(_probe): return
	var target := _subject.global_position + Vector3.UP * 4.0
	if force or _probe.global_position.distance_to(target) > 35.0:
		_probe.global_position = target
	else:
		# UPDATE_ONCE recaptures over six frames after a transform change.
		_probe.position.x += 0.001
