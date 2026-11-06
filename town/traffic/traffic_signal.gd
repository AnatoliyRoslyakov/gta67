extends Node3D

static var lens_mesh: SphereMesh
static var lens_finishes: Array[StandardMaterial3D] = []
var world: Node3D
var junction_index := 0
var lamps: Array[Array] = []
var pedestrian_labels: Array[Label3D] = []
var _last_light_states := PackedInt32Array([-1, -1, -1, -1])
var _last_walk_state := -1


func _ready() -> void:
	if lens_mesh == null:
		lens_mesh = SphereMesh.new()
		lens_mesh.radial_segments = 12
		lens_mesh.rings = 5
		lens_mesh.radius = 0.135
		lens_mesh.height = 0.27
		for color: Color in [Color("ff4438"), Color("ffc040"), Color("38e79b")]:
			for active in [false, true]:
				var finish := StandardMaterial3D.new()
				finish.albedo_color = color if active else color.darkened(0.88)
				finish.emission_enabled = active
				finish.emission = color
				finish.emission_energy_multiplier = 4.2
				lens_finishes.append(finish)
	for direction in 4:
		var axis: Vector2i = world.DIRECTIONS[direction]
		var forward := Vector3(axis.x, 0, axis.y)
		var right := forward.cross(Vector3.UP)
		var head := Node3D.new()
		head.position = -forward * 8 + right * 7
		head.rotation.y = atan2(-forward.x, -forward.z)
		add_child(head)
		_box(head, Vector3(0, 2.2, 0), Vector3(0.12, 4.4, 0.12), Color("515d61"))
		_box(head, Vector3(0, 4.25, 0), Vector3(0.46, 1.45, 0.4), Color("20292e"))
		var row: Array = []
		for i in 3:
			var lens := MeshInstance3D.new()
			lens.mesh = lens_mesh
			lens.position = Vector3(0, 4.7 - i * 0.43, 0.22)
			lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			lens.material_override = lens_finishes[i * 2]
			head.add_child(lens)
			row.append(lens)
		lamps.append(row)
		_box(head, Vector3(0, 2.6, 0.12), Vector3(0.64, 0.40, 0.22), Color("151c21"))
		var sign := Label3D.new()
		sign.position = Vector3(0, 2.6, 0.24)
		sign.pixel_size = 0.009
		sign.font_size = 20
		sign.outline_size = 0
		head.add_child(sign)
		pedestrian_labels.append(sign)

	show_phase(floori(fmod(world.elapsed, 58.0)))


func show_phase(second: int) -> void:
	for direction in 4:
		var active: int = world.light_state(junction_index, direction)
		if active == _last_light_states[direction]: continue
		_last_light_states[direction] = active
		for i in 3:
			lamps[direction][i].material_override = lens_finishes[i * 2 + int(active == i)]
	var walk := second >= 30 and second < 36
	if int(walk) == _last_walk_state: return
	_last_walk_state = int(walk)
	for sign in pedestrian_labels:
		sign.text = "WALK" if walk else "WAIT"
		sign.modulate = Color("91efc1") if walk else Color("e78b73")


func _box(parent: Node3D, p: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = p
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	instance.material_override = material
	parent.add_child(instance)
