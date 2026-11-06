extends "res://cube/geometry.gd"

const Life = preload("res://cube/life.gd")
var camera := Camera3D.new()
var yaw := 0.66
var pitch := 0.57
var zoom_factor := 1.0
var zoom_target := 1.0
var rotating := true
var dragging := false
var inspect_offset := Vector2.ZERO
var touches := {}
var clock := 3.0
var lamps := []
var life := Life.new()
var bridge: JavaScriptObject
var callback: JavaScriptObject
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 6704
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("eae9df")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("e9f1f2")
	env.ambient_light_energy = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-54,-32,0)
	sun.light_color = Color("fff1d4")
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 185
	add_child(sun)
	streets()
	buildings()
	park()
	case_glass()
	bake()
	add_child(life)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	add_child(camera)
	camera.make_current()
	camera_pose()
	if OS.has_feature("web"):
		bridge = JavaScriptBridge.get_interface("quarterUI")
		callback = JavaScriptBridge.create_callback(web_command)
		if bridge: bridge.connectGame(callback)

func streets() -> void:
	# Three exposed strata make the depth readable even from below.
	part(Vector3(0,-3,0),Vector3(49.8,3.4,49.8),"aa8063")
	part(Vector3(0,-1.35,0),Vector3(49.8,0.55,49.8),"c5ac86")
	part(Vector3(0,-0.64,0),Vector3(49.8,0.92,49.8),"907e67")
	part(Vector3(0,-0.1,0),Vector3(49.8,0.2,49.8),"d7cbb1")
	part(Vector3(0,0.04,0),Vector3(49.8,0.09,5),"505b60")
	for z in [-17,17]:
		part(Vector3(0,0.04,z),Vector3(26.8,0.09,4.8),"505b60")
	for x in [-11,11]:
		part(Vector3(x,0.05,0),Vector3(4.8,0.1,34),"505b60")
		for z in [-13,-10,-7,7,10,13]:
			part(Vector3(x,0.114,z),Vector3(0.11,0.015,1.35),"e4cf94")
		for dir in [-1,1]:
			for stripe in 8:
				part(Vector3(x-1.95+stripe*0.55,0.125,dir*3.0),Vector3(0.31,0.02,1),"efe3c8")
				part(Vector3(x+dir*3.3,0.125,-1.95+stripe*0.55),Vector3(1,0.02,0.31),"efe3c8")
			for axis in 2:
				var sx: float = x + dir*2.85
				var sz: float = dir*(3.7 if axis==0 else -3.7)
				part(Vector3(sx,1.2,sz),Vector3(.12,2.4,.12),"435150")
				part(Vector3(sx,2.4,sz),Vector3(.37,.85,.38),"253e41")
				var lens := MeshInstance3D.new()
				lens.mesh = primitives.leaf
				lens.position = Vector3(sx,2.45,sz)
				lens.scale = Vector3(.42,.38,.43)
				var mat := StandardMaterial3D.new()
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				lens.material_override = mat
				add_child(lens)
				lamps.append([mat,x,axis])
	for x in range(-24,25,3):
		if abs(abs(x)-11)>3:
			part(Vector3(x,.11,0),Vector3(1.45,.02,.11),"e4cf94")
		if abs(x)<9:
			for z in [-17,17]:
				part(Vector3(x,.11,z),Vector3(1.45,.02,.11),"e4cf94")

func building(x: float,z: float,w: float,d: float,floors: int,wall: String,roof: String,style: int) -> void:
	var h := 2.7 + floors * 2.15
	var face := 1 if z < 0 else -1
	part(Vector3(x,.18,z),Vector3(w+.6,.36,d+.6),"b7a68c")
	part(Vector3(x,h*.5+.32,z),Vector3(w,h,d),wall)
	part(Vector3(x,h+.36,z),Vector3(w+.38,.32,d+.38),"f2dcbc")
	part(Vector3(x,2.93,z),Vector3(w+.22,.22,d+.22),"f7dfb7")
	for sign_z in [-1,1]:
		var fz: float = z + sign_z*(d/2+.055)
		for col in maxi(2,roundi(w/1.85)):
			var wx := x - w/2 + (col+.5) * w / maxi(2,roundi(w/1.85))
			for f in floors:
				var wy := 4.05 + f * 2.13
				part(Vector3(wx,wy,fz),Vector3(1.16,1.44,.11),"e8d3ab")
				part(Vector3(wx,wy,fz+sign_z*.08),Vector3(.92,1.18,.11),["466771","65848a","c6aa81"][(col+f+style)%3])
				part(Vector3(wx,wy-.68,fz),Vector3(1.35,.12,.36),"f3dfbd")
			part(Vector3(wx,1.56,fz),Vector3(1.33,1.93,.13),"446369")
	for side in [-1,1]:
		for f in floors:
			for col in maxi(2,roundi(d/2.1)):
				var wz := z - d/2 + (col+.5)*d/maxi(2,roundi(d/2.1))
				part(Vector3(x+side*(w/2+.035),4.0+2.13*f,wz),Vector3(.11,1.22,1.01),"54727a")
	if style % 3 == 0:
		part(Vector3(x,h+1.52,z),Vector3(w+.64,2.35,d+.55),roof,"roof")
		part(Vector3(x+w*.27,h+1.98,z+d*.22),Vector3(.65,2.05,.72),"995e4d")
	else:
		part(Vector3(x,h+.59,z),Vector3(w-.35,.19,d-.35),roof)
		part(Vector3(x-w*.14,h+.91,z),Vector3(w*.37,.59,d*.36),"8c9386")
		for side in [-1,1]:
			part(Vector3(x,h+.77,z+side*d*.49),Vector3(w,.53,.17),wall)
	for strip in 10:
		var awning_z := z+face*(d/2+.48)
		part(Vector3(x-w*.46+(strip+.5)*w*.092,2.64,awning_z),Vector3(w*.093,.17,.97),roof if strip%2==0 else "f2dfb7")
		part(Vector3(x-w*.46+(strip+.5)*w*.092,2.5,awning_z+face*.43),Vector3(w*.093,.28,.12),roof if strip%2==0 else "f2dfb7")

func buildings() -> void:
	building(-19,-9,8.3,9.8,4,"cb8366","a15143",0)
	building(-19,-19.2,8.1,7.8,3,"e4bd89","645b59",3)
	building(18.9,-9.0,8.0,9.0,5,"d49d70","546e70",2)
	building(18.9,-19.5,7.8,8.4,3,"99aba1","a15f50",0)
	# Steel frame and a banded water tank above the factory.
	for dx in [-.95,.95]:
		for dz in [-.95,.95]:
			part(Vector3(18.9+dx,14.8,-9+dz),Vector3(.19,2.8,.19),"525e5c")
	part(Vector3(18.9,17.25,-9),Vector3(3.3,2.85,3.3),"ae7958","round")
	for y in [15.95,17.9,18.72]:
		part(Vector3(18.9,y,-9),Vector3(3.44,.16,3.44),"54615d","round")
	building(-4.1,-9.0,6.7,9.0,4,"e2b885","8f5046",3)
	building(3.6,-9.2,7.15,8.6,7,"a5b7a6","677d76",1)
	# Setback clock tower with dial, copper crown and a needle.
	var x := 3.6
	var z := -9.2
	part(Vector3(x,20.8,z),Vector3(5,5.7,5),"c3c4a7")
	for side in [-1,1]:
		part(Vector3(x,21.6,z+side*2.53),Vector3(2.18,2.18,.13),"486661")
		part(Vector3(x,21.6,z+side*2.62),Vector3(1.88,1.88,.12),"f6e6bf")
		part(Vector3(x,21.9,z+side*2.70),Vector3(.12,.64,.09),"435c56")
		part(Vector3(x+.27,21.64,z+side*2.70),Vector3(.57,.12,.09),"435c56")
	part(Vector3(x,24,z),Vector3(5.6,.65,5.6),"58796e")
	part(Vector3(x,25.25,z),Vector3(3.55,2.2,3.55),"a8bc9f")
	part(Vector3(x,26.9,z),Vector3(3.9,1.35,3.9),"688b78","roof")
	part(Vector3(x,28.3,z),Vector3(.14,2.55,.14),"62685c")
	building(-18.9,9.1,8.5,9.4,2,"e0ac79","648b83",1)
	building(-19,19.7,8.3,8.1,2,"ba8675","8d5650",3)
	building(18.8,9.3,8,9.2,3,"d3bfa0","89665c",0)
	building(18.8,19.7,8,7.7,2,"a9b7ad","648481",1)
	building(0,-22.2,11,3.6,1,"c79072","a76250",0)
	building(3.95,9,6.2,8.7,2,"d59b80","548982",1)
	part(Vector3(3.95,4.1,4.54),Vector3(5.8,.99,.32),"286b68")
	var sign_label := Label3D.new()
	sign_label.text = "K I N O"
	sign_label.font_size = 56
	sign_label.pixel_size = .014
	sign_label.modulate = Color("ffe3af")
	sign_label.outline_size = 0
	sign_label.rotation.y = PI
	sign_label.position = Vector3(3.95,4.1,4.33)
	add_child(sign_label)

func tree(x: float,z: float,s: float) -> void:
	part(Vector3(x,.15,z),Vector3(1.55,.2,1.55),"aa9979")
	part(Vector3(x,1.3*s,z),Vector3(.42*s,2.7*s,.42*s),"80684c","round")
	part(Vector3(x,3.25*s,z),Vector3(2.85*s,3.45*s,2.85*s),"79916a","leaf")
	part(Vector3(x+.52*s,3.62*s,z+.18*s),Vector3(2.1*s,2.6*s,2.1*s),"a3ae72","leaf")

func park() -> void:
	part(Vector3(-3.9,.16,9.05),Vector3(8,.28,10.4),"a2ac7d")
	part(Vector3(-3.9,.32,9.4),Vector3(8,.07,1.2),"dacdb0")
	for p in [Vector2(-6,6.8),Vector2(-2,12),Vector2(-6.1,12.6),Vector2(-7.1,22),Vector2(-2,21.9),Vector2(4.2,22.4),Vector2(-15,3.8),Vector2(15,-3.9),Vector2(23,-2.95),Vector2(22.6,3.65)]:
		tree(p.x,p.y,rng.randf_range(.83,1.22))
	for x in [-6,-2,5]:
		var z := 10.35 if x<0 else 20.25
		part(Vector3(x,.64,z),Vector3(1.9,.18,.6),"a27450")
		part(Vector3(x,1.02,z+.24),Vector3(1.9,.53,.13),"a27450")
		for dx in [-.67,.67]: part(Vector3(x+dx,.39,z),Vector3(.13,.6,.42),"52645e")
	for x in [-22,-6,6,22]:
		for z in [-3.75,3.75]:
			part(Vector3(x,1.64,z),Vector3(.11,3.24,.11),"455959")
			part(Vector3(x,3.26,z),Vector3(.5,.48,.5),"ffdfa2","round")
			part(Vector3(x,3.55,z),Vector3(.64,.14,.64),"455959","round")

func case_glass() -> void:
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_color = Color(.58,.82,.79,.045)
	var pane := MeshInstance3D.new()
	pane.mesh = BoxMesh.new()
	pane.scale = Vector3.ONE*50.4
	pane.position.y = 20.4
	pane.material_override = glass
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pane)
	for side in [-25.2,25.2]:
		for y in [-4.8,45.6]:
			part(Vector3(side,y,0),Vector3(.14,.14,50.4),"8fafa5")
			part(Vector3(0,y,side),Vector3(50.4,.14,.14),"8fafa5")
		for other in [-25.2,25.2]:
			part(Vector3(side,20.4,other),Vector3(.14,50.4,.14),"a9c5bb")
			for y in [-4.72,45.52]:
				part(Vector3(side,y,other),Vector3(.39,.39,.39),"849b89")

func orbit(delta: Vector2) -> void:
	set_spin(false)
	yaw -= delta.x*.006
	pitch = clampf(pitch+delta.y*.005,-.85,1.47)

func set_spin(on: bool) -> void:
	rotating = on
	if bridge: bridge.spinChanged(on)

func set_zoom(multiplier: float) -> void:
	zoom_target = clampf(zoom_target*multiplier,.32,1.32)

func web_command(args: Array) -> void:
	match str(args[0]):
		"in": set_zoom(.84)
		"out": set_zoom(1.19)
		"spin": set_spin(not rotating)
		"reset":
			yaw=.66
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
					inspect_offset=Vector2(clampf(ground.x,-23,23),clampf(ground.z,-23,23))
					zoom_target=.42
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
			inspect_offset = inspect_offset.clamp(Vector2(-23,-23),Vector2(23,23))
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
	camera.size = 84 * zoom_factor / minf(aspect,1.0)
	var focus := Vector3(0,lerpf(6.0,19.8,minf(zoom_factor,1.0)),0)
	focus += Vector3(inspect_offset.x,0,inspect_offset.y)*(1.0-smoothstep(.45,1,zoom_factor))
	camera.position = focus + Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*112
	camera.look_at(focus)

func _process(delta: float) -> void:
	var dt := minf(delta,.06)
	clock += dt
	if rotating: yaw += dt*.047
	zoom_factor = lerpf(zoom_factor,zoom_target,1-exp(-dt*10))
	camera_pose()
	life.advance(dt,clock)
	for lamp in lamps:
		var phase := Life.phase(clock,lamp[1])
		var green: bool = (phase<6.0 if lamp[2]==0 else phase>=8.0 and phase<14.0)
		var amber: bool = (phase>=6 and phase<7 if lamp[2]==0 else phase>=14 and phase<15)
		lamp[0].albedo_color = Color("91e6a0") if green else (Color("ffc267") if amber else Color("e86657"))
