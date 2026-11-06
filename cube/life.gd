extends Node3D

const Pieces = preload("res://cube/geometry.gd")
const PAINT := ["b95948","749a91","d2a65f","5d7888","eed7ad","a36c60"]
var cars := []
var walkers := []
var paths := []
var walk_paths := []

static func phase(clock: float, junction_x: float) -> float:
	return fposmod(clock+(4.0 if junction_x>0 else 0.0),20.0)

# Offset each curb loop to its own driving lane, then round every corner.
func loop(corners: PackedVector2Array, offset: float, radius: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.bake_interval = .12
	var vertices := PackedVector2Array()
	for i in corners.size():
		var prev := (corners[i]-corners[posmod(i-1,corners.size())]).normalized()
		var next := (corners[(i+1)%corners.size()]-corners[i]).normalized()
		var sides := Vector2(-prev.y,prev.x)+Vector2(-next.y,next.x)
		vertices.append(corners[i]+sides*offset)
	for i in vertices.size():
		var p := vertices[i]
		var prev := (p-vertices[posmod(i-1,vertices.size())]).normalized()
		var next := (vertices[(i+1)%vertices.size()]-p).normalized()
		var a := p-prev*radius
		var b := p+next*radius
		for step in 9:
			var t := step/8.0
			var sample := a.lerp(p,t).lerp(p.lerp(b,t),t)
			curve.add_point(Vector3(sample.x,0,sample.y))
	curve.add_point(curve.get_point_position(0))
	return curve

func rectangle(left: float, top: float, right: float, bottom: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(left,top),Vector2(right,top),Vector2(right,bottom),Vector2(left,bottom)])

func _ready() -> void:
	var north := rectangle(-11,-17,11,0)
	var south := rectangle(-11,0,11,17)
	var outer := rectangle(-11,-17,11,17)
	outer.reverse()
	for route in [north,south,outer]:
		paths.append(loop(route,1.07,2.35))
	for i in 9:
		var car := Pieces.new()
		var paint: String = PAINT[i%PAINT.size()]
		var van := i%4==1
		car.part(Vector3(0,.53,0),Vector3(1.42,.54,2.93),paint)
		car.part(Vector3(0,.95,-.13),Vector3(1.24,.61,1.95 if van else 1.54),"48616a")
		car.part(Vector3(0,1.29,-.14),Vector3(1.28,.17,2.01 if van else 1.58),paint)
		for side in [-1,1]:
			car.part(Vector3(side*.635,.98,-.12),Vector3(.06,.55,.13),paint)
			for axle in [-.91,.91]:
				car.part(Vector3(side*.70,.38,axle),Vector3(.22,.57,.60),"374447","leaf")
			car.part(Vector3(side*.46,.59,1.48),Vector3(.32,.17,.06),"ffde90")
			car.part(Vector3(side*.48,.59,-1.48),Vector3(.29,.15,.06),"a24b40")
		if i==2: car.part(Vector3(0,1.46,0),Vector3(.51,.22,.34),"ffe49b")
		car.bake()
		add_child(car)
		var curve: Curve3D = paths[i%3]
		var distance := curve.get_baked_length()*(floori(i/3.0)/3.0 + .053*(i%3))
		var actor := {"node":car,"curve":curve,"s":distance,"v":2.6,"cruise":2.8+.17*(i%4)}
		place(actor)
		cars.append(actor)
	for box in [Rect2(-7.9,-14,15.8,10.35),Rect2(-7.9,3.75,15.8,10.38),Rect2(14.45,3.45,9.25,11.83),Rect2(-23.85,-15.05,9.65,11.49),Rect2(-9.4,20.25,17.7,3.3)]:
		walk_paths.append(loop(rectangle(box.position.x,box.position.y,box.end.x,box.end.y),0,.68))
	# Cross at the marked stripes on the east and west sides of the two junctions.
	for x in [-11.0,11.0]:
		walk_paths.append(loop(rectangle(x-3.3,-3.85,x+3.3,3.85),0,.42))
	for i in 25:
		var body := Pieces.new()
		var skin: String = ["c38763","8c6050","dab195","ad7858"][i%4]
		var jacket: String = ["b95742","4a7c80","dbb15d","74845e","617089","bc846e"][i%6]
		body.part(Vector3(0,1.0,0),Vector3(.48,.63,.33),jacket)
		body.part(Vector3(0,1.54,0),Vector3(.36,.4,.35),skin,"leaf")
		body.part(Vector3(0,1.73,-.025),Vector3(.4,.19,.37),"58483e","leaf")
		for side in [-1,1]:
			body.part(Vector3(side*.29,1,0),Vector3(.13,.46,.18),jacket)
			body.part(Vector3(side*.29,.72,0),Vector3(.14,.16,.17),skin)
		body.bake()
		var legs := []
		for side in [-1,1]:
			var leg := Pieces.new()
			leg.position = Vector3(side*.135,.74,0)
			leg.part(Vector3(0,-.32,0),Vector3(.19,.61,.22),"47565d")
			leg.part(Vector3(0,-.61,.055),Vector3(.21,.13,.32),"544b40")
			leg.bake()
			body.add_child(leg)
			legs.append(leg)
		add_child(body)
		var curve: Curve3D = walk_paths[i%7]
		var person := {"node":body,"curve":curve,"s":curve.get_baked_length()*fposmod(i*.379,1),"pace":.82+.11*(i%4),"legs":legs,"cross":i%7>=5}
		place(person)
		walkers.append(person)

func place(actor: Dictionary) -> void:
	var shape: Curve3D = actor.curve
	var s := fposmod(float(actor.s),shape.get_baked_length())
	var p := shape.sample_baked(s)
	var ahead := shape.sample_baked(fposmod(s+.1,shape.get_baked_length()))-p
	actor.node.position = p + Vector3.UP*.13
	actor.node.rotation.y = atan2(ahead.x,ahead.z)

func traffic_stop(p: Vector3, dir: Vector3, clock: float) -> float:
	var room := INF
	for x in [-11.0,11.0]:
		var diff := Vector3(x,0,0)-p
		var along := diff.dot(dir)
		if along<3.4 or along>13 or absf(diff.cross(dir).y)>1.75: continue
		var t := phase(clock,x)
		var green := t<6 if absf(dir.z)>.85 else t>=8 and t<14
		if not green: room=minf(room,along-4.85)
	return room

func advance(dt: float,clock: float) -> void:
	for c in cars:
		var n: Node3D = c.node
		var dir := n.basis.z
		var room := traffic_stop(n.position,dir,clock)
		for other in cars:
			if c.node==other.node: continue
			var diff: Vector3 = other.node.position-n.position
			var along := diff.dot(dir)
			if along>.1 and along<9 and absf(diff.cross(dir).y)<1.35 and dir.dot(other.node.basis.z)>.25:
				room=minf(room,along-3.65)
		var target := minf(c.cruise,sqrt(4.6*maxf(0,room)))
		c.v = move_toward(c.v,target,dt*(3.6 if target<c.v else 1.65))
		c.s = fposmod(c.s+dt*c.v,c.curve.get_baked_length())
		place(c)
	for person in walkers:
		var n: Node3D = person.node
		var pace: float = person.pace
		if person.cross:
			var j := -11.0 if n.position.x<0 else 11.0
			var d := Vector2(n.position.x-j,n.position.z)
			var t := phase(clock,j)
			var vertical := absf(n.basis.z.z)>.95
			var edge := -d.y*n.basis.z.z if vertical else -d.x*n.basis.z.x
			if edge>=2.52 and edge<=2.87 and (t<15.1 or t>17.1): pace=0
			# Once the walker leaves the curb, finish before traffic resumes.
			else: pace=2.15
		person.s = fposmod(person.s + pace*dt, person.curve.get_baked_length())
		place(person)
		var stride := sin(float(person.s)*4.7)*.52 if pace>0 else 0.0
		person.legs[0].rotation.x=stride
		person.legs[1].rotation.x=-stride
