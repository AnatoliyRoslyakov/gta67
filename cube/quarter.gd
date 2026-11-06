extends "res://cube/geometry.gd"

const District = preload("res://Assets/WebQuarter/district.scn")
const Traffic = preload("res://cube/traffic.gd")
const Glass = preload("res://cube/glass.gdshader")
var camera := Camera3D.new()
var yaw := -0.48
var pitch := 0.57
var zoom_factor := 1.0
var zoom_target := 1.0
var rotating := true
var dragging := false
var inspect_offset := Vector2.ZERO
var touches := {}
var pane := MeshInstance3D.new()
var glass := ShaderMaterial.new()
var seams := MultiMeshInstance3D.new()
var cut_edge := StandardMaterial3D.new()
var frame_window := 0.0
var frame_count := 0
var fast_windows := 0
var observer := AudioListener3D.new()
var traffic := Traffic.new()
var atmosphere: Node
var env := Environment.new()
var sun := DirectionalLight3D.new()
var room_lights: Array[StandardMaterial3D] = []
var street_lights: Array[OmniLight3D] = []
var selected_time := "day"
var transition: Tween
# Sun angle, sunlight, skylight, energy, window light and gallery backdrop.
const TIMES := {
	"morning": [Vector3(-23,-100,0),Color("ffd0a1"),Color("ecdae1"),.92,.78,.15,Color("e9e4db")],
	"day": [Vector3(-54,-32,0),Color("fff1d4"),Color("e9f1f2"),.82,.85,0.0,Color("eae9df")],
	"evening": [Vector3(-16,75,0),Color("ffa16a"),Color("dcc5da"),.87,.59,.78,Color("d4c4bb")],
	"night": [Vector3(-48,120,0),Color("a9c5f7"),Color("aebfdf"),.32,.33,1.3,Color("232d34")]
}
var bridge: JavaScriptObject
var callback: JavaScriptObject

func _ready() -> void:
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eae9df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9f1f2")
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun.rotation_degrees = Vector3(-54,-32,0)
	sun.light_color = Color("fff1d4")
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 335
	add_child(sun)
	var district: Node3D = District.instantiate()
	add_child(district)
	add_child(observer)
	observer.make_current()
	atmosphere = self
	for mesh: MeshInstance3D in district.find_children("*","MeshInstance3D",true,false):
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as StandardMaterial3D
			if material and material.has_meta("rooms"): room_lights.append(material)
	for pos: Vector3 in district.get_meta("lamps",PackedVector3Array()):
		if street_lights.size() >= 6: break
		var lamp := OmniLight3D.new()
		lamp.position = pos-Vector3.UP*.3
		lamp.light_color = Color("ffd093")
		lamp.omni_range = 12
		lamp.shadow_enabled = false
		lamp.visible = false
		add_child(lamp)
		street_lights.append(lamp)
	traffic.positional_audio = false
	traffic.vehicle_count = 9
	traffic.citizen_count = 24
	add_child(traffic)
	traffic.configure(district,observer)
	case_glass()
	bake()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.make_current()
	camera_pose()
	while not traffic.initialized: await get_tree().process_frame
	if OS.has_feature("web"):
		bridge = JavaScriptBridge.get_interface("quarterUI")
		callback = JavaScriptBridge.create_callback(web_command)
		if bridge: bridge.connectGame(callback)

func case_glass() -> void:
	part(Vector3(0,-5.2,0),Vector3(100,7.4,100),"9f806b")
	part(Vector3(0,-1.45,0),Vector3(100,.9,100),"c9ae87")
	part(Vector3(0,-.52,0),Vector3(100,.99,100),"949080")
	glass.shader = Glass
	glass.set_shader_parameter("exposure",1.0)
	glass.set_shader_parameter("studio",preload("res://cube/studio_small_09.hdr"))
	glass.render_priority = 100
	pane.mesh = BoxMesh.new()
	pane.scale = Vector3.ONE * 101
	pane.position.y = 41.4
	pane.material_override = glass
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pane)
	# The polished cut edges on the far side remain visible through the front panes.
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = BoxMesh.new()
	batch.instance_count = 12
	var i := 0
	for axis in 3:
		for a in [-50.5,50.5]:
			for b in [-50.5,50.5]:
				var size := Vector3.ONE*.16
				size[axis] = 101
				var p := Vector3.ZERO
				p[(axis+1)%3]=a
				p[(axis+2)%3]=b
				p.y += 41.4
				batch.set_instance_transform(i,Transform3D(Basis.from_scale(size),p))
				i+=1
	seams.multimesh = batch
	cut_edge.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cut_edge.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	seams.material_override = cut_edge
	seams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(seams)

func orbit(delta: Vector2) -> void:
	set_spin(false)
	yaw -= delta.x*.006
	pitch = clampf(pitch+delta.y*.005,-.85,1.47)

func set_spin(on: bool) -> void:
	rotating = on
	if bridge: bridge.spinChanged(on)

func set_zoom(multiplier: float) -> void:
	zoom_target = clampf(zoom_target*multiplier,.12,1.32)

func is_night() -> bool:
	return selected_time=="night" or selected_time=="evening"

func change_time(key: String) -> void:
	if not TIMES.has(key): return
	selected_time = key
	if transition: transition.kill()
	transition = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var t: Array = TIMES[key]
	transition.tween_property(sun,"rotation_degrees",t[0],.8)
	transition.tween_property(sun,"light_color",t[1],.8)
	transition.tween_property(env,"ambient_light_color",t[2],.8)
	transition.tween_property(sun,"light_energy",t[3],.8)
	transition.tween_property(env,"ambient_light_energy",t[4],.8)
	transition.tween_property(env,"background_color",t[6],.8)
	transition.tween_property(glass,"shader_parameter/exposure",.50 if key=="night" else 1.0,.8)
	for room in room_lights: transition.tween_property(room,"emission_energy_multiplier",t[5],.8)
	for lamp in street_lights:
		if not lamp.visible: lamp.light_energy = 0
		lamp.visible = true
		transition.tween_property(lamp,"light_energy",float(t[5])*1.5,.8)
	transition.finished.connect(func():
		for lamp in street_lights: lamp.visible=is_night()
	)

func web_command(args: Array) -> void:
	if TIMES.has(str(args[0])):
		change_time(str(args[0]))
		return
	match str(args[0]):
		"in": set_zoom(.84)
		"out": set_zoom(1.19)
		"spin": set_spin(not rotating)
		"reset":
			yaw=-.48
			pitch=.57
			zoom_target=1
			inspect_offset=Vector2.ZERO
			set_spin(true)

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index==MOUSE_BUTTON_LEFT:
			dragging=e.pressed
			if e.pressed and e.double_click:
				var ground = Plane(Vector3.UP,0).intersects_ray(camera.project_ray_origin(e.position),camera.project_ray_normal(e.position))
				if ground != null:
					inspect_offset=Vector2(clampf(ground.x,-47,47),clampf(ground.z,-47,47))
					zoom_target=.20
					set_spin(false)
		if e.pressed and e.button_index==MOUSE_BUTTON_WHEEL_UP: set_zoom(.9)
		if e.pressed and e.button_index==MOUSE_BUTTON_WHEEL_DOWN: set_zoom(1.1)
	elif e is InputEventMouseMotion and dragging: orbit(e.relative)
	elif e is InputEventMagnifyGesture: set_zoom(1.0/e.factor)
	elif e is InputEventScreenTouch:
		if e.pressed: touches[e.index]=e.position
		else: touches.erase(e.index)
	elif e is InputEventScreenDrag and touches.has(e.index):
		var before: Array = touches.values()
		touches[e.index]=e.position
		var after: Array = touches.values()
		if before.size()==2:
			var motion: Vector2 = e.relative * camera.size / maxf(1, get_viewport().get_visible_rect().size.y) * .5
			inspect_offset += Vector2(-cos(yaw),sin(yaw))*motion.x + Vector2(sin(yaw),cos(yaw))*motion.y
			inspect_offset = inspect_offset.clamp(Vector2(-47,-47),Vector2(47,47))
			set_zoom(before[0].distance_to(before[1])/maxf(after[0].distance_to(after[1]),1))
		elif before.size()==1: orbit(e.relative)
	elif e is InputEventKey and e.pressed:
		match e.keycode:
			KEY_LEFT: orbit(Vector2(9,0))
			KEY_RIGHT: orbit(Vector2(-9,0))
			KEY_UP: orbit(Vector2(0,8))
			KEY_DOWN: orbit(Vector2(0,-8))
			KEY_EQUAL,KEY_PLUS: set_zoom(.9)
			KEY_MINUS: set_zoom(1.1)
			KEY_HOME: web_command(["reset"])

func camera_pose() -> void:
	var aspect := get_viewport().get_visible_rect().size.aspect()
	camera.size = 168 * zoom_factor / minf(aspect,1.0)
	var focus := Vector3(0,lerpf(2.2,40.1,minf(zoom_factor,1.0)),0)
	focus += Vector3(inspect_offset.x,0,inspect_offset.y)*(1.0-smoothstep(.45,1,zoom_factor))
	camera.position = focus + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*222
	camera.look_at(focus)
	observer.position = Vector3(focus.x,2,focus.z)
	observer.rotation.y = yaw
	var presence := smoothstep(.45,1.08,zoom_factor)
	pane.visible = presence > .001
	seams.visible = pane.visible
	cut_edge.albedo_color = Color(.45,.59,.56,presence*.44)
	glass.set_shader_parameter("presence",presence)

func _process(delta: float) -> void:
	if OS.has_feature("web"): update_resolution(delta)
	var dt := minf(delta,.06)
	if rotating: yaw += dt*.047
	zoom_factor = lerpf(zoom_factor,zoom_target,1-exp(-dt*10))
	camera_pose()

# Keep text at native CSS resolution. Only change the 3D buffer after a
# sustained frame-time change, never during an individual slow frame.
func update_resolution(delta: float) -> void:
	if delta > .25: return
	frame_window += delta
	frame_count += 1
	if frame_window < 2.5: return
	var rate := frame_count / frame_window
	var viewport := get_viewport()
	if rate < 42:
		viewport.scaling_3d_scale = maxf(.68,viewport.scaling_3d_scale-.10)
		fast_windows = 0
	elif rate > 57:
		fast_windows += 1
		if fast_windows >= 3:
			viewport.scaling_3d_scale = minf(1.0,viewport.scaling_3d_scale+.06)
			fast_windows = 0
	else: fast_windows = 0
	frame_window = 0
	frame_count = 0
