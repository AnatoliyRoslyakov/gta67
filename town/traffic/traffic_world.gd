extends Node3D

const Catalog = preload("res://vehicles/vehicle_catalog.gd")
const Driver = preload("res://town/traffic/traffic_driver.gd")
const Citizen = preload("res://town/traffic/citizen.gd")
const TrafficSignal = preload("res://town/traffic/traffic_signal.gd")
const CELL := 5.0
const WALK_CELL := 2.5
const DRIVER_BUCKET_SIZE := 20.0
const DRIVER_INDEX_INTERVAL := 0.1
const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const VEHICLES := ["Sedan", "Small", "Medium", "Taxi", "Van", "Muscle", "VAZ2101", "VAZ2105", "VAZ2106", "UAZ469", "UAZ452"]
const PEOPLE := ["Male_Hoodie", "Female_Jacket", "BusinessMan_Shirt", "BusinessWoman", "Male_Jacket", "Female_Coat"]

@export var vehicle_count := 40
@export var citizen_count := 64
var city_map: Node3D
var subject: Node3D
var road_cells: Dictionary = {}
var lanes: Dictionary = {}
var junction_cells: Dictionary = {}
var junctions: Array[Dictionary] = []
var sidewalk_cells: Dictionary = {}
var walk_neighbors: Dictionary = {}
var crossing_edges: Dictionary = {}
var signals: Array[Node3D] = []
var drivers: Array[CharacterBody3D] = []
var citizens: Array[CharacterBody3D] = []
var parked_count := 0
var elapsed := 0.0
var initialized := false
var rng := RandomNumberGenerator.new()
var _starting := false
var _driver_buckets: Dictionary = {}
var _driver_index_tick := 0.0
var _indexed_driver_count := -1
var _crossing_occupancy := PackedInt32Array()


func configure(city: Node3D, player: Node3D) -> void:
	city_map = city
	subject = player
	if is_inside_tree(): _initialize.call_deferred()


func set_target(player: Node3D) -> void:
	subject = player


func set_subject(player: Node3D) -> void:
	set_target(player)


func alert_nearby(origin: Vector3) -> void:
	for person in citizens:
		if person.global_position.distance_to(origin) < 45: person.flee(origin)


func _ready() -> void:
	if city_map != null: _initialize.call_deferred()


func _initialize() -> void:
	if _starting: return
	_starting = true
	rng.randomize()
	await get_tree().physics_frame
	_extract_surfaces()
	_build_lanes()
	_build_junctions()
	_build_walkways()
	_organize_parked_cars()
	await get_tree().physics_frame
	await _spawn_population()
	_rebuild_driver_index()
	await get_tree().physics_frame
	initialized = true


func _physics_process(delta: float) -> void:
	elapsed += delta
	_driver_index_tick -= delta
	if _driver_index_tick <= 0.0:
		_driver_index_tick += DRIVER_INDEX_INTERVAL
		_rebuild_driver_index()
	_crossing_occupancy.resize(junctions.size())
	_crossing_occupancy.fill(0)
	for person in citizens:
		var crossing: int = person.crossing_junction
		if crossing >= 0 and crossing < _crossing_occupancy.size(): _crossing_occupancy[crossing] += 1
	for index in junctions.size(): _refresh_junction(index)


func _rebuild_driver_index() -> void:
	_driver_buckets.clear()
	for driver in drivers:
		if not is_instance_valid(driver): continue
		var p := driver.global_position
		var bucket := Vector2i(floori(p.x / DRIVER_BUCKET_SIZE), floori(p.z / DRIVER_BUCKET_SIZE))
		if not _driver_buckets.has(bucket): _driver_buckets[bucket] = []
		_driver_buckets[bucket].append(driver)
	_indexed_driver_count = drivers.size()


func nearby_drivers(origin: Vector3, radius: float) -> Array[CharacterBody3D]:
	if _indexed_driver_count != drivers.size(): _rebuild_driver_index()
	var found: Array[CharacterBody3D] = []
	# Covers 0.1 s of movement at the fastest police speed. Positions are filtered live.
	var reach := radius + 2.5
	var minimum := Vector2i(floori((origin.x - reach) / DRIVER_BUCKET_SIZE), floori((origin.z - reach) / DRIVER_BUCKET_SIZE))
	var maximum := Vector2i(floori((origin.x + reach) / DRIVER_BUCKET_SIZE), floori((origin.z + reach) / DRIVER_BUCKET_SIZE))
	var radius_squared := radius * radius
	for x in range(minimum.x, maximum.x + 1):
		for z in range(minimum.y, maximum.y + 1):
			for driver in _driver_buckets.get(Vector2i(x, z), []):
				if is_instance_valid(driver) and driver.global_position.distance_squared_to(origin) <= radius_squared:
					found.append(driver)
	return found


func _release_junction(index: int) -> void:
	junctions[index].owner = null
	junctions[index].entered = false


func _actor_in_junction(actor: Node3D, index: int) -> bool:
	return junction_cells.get(world_cell(actor.global_position), -1) == index


func _refresh_junction(index: int) -> void:
	var owner: Node3D = junctions[index].get("owner")
	if not is_instance_valid(owner):
		_release_junction(index)
		return
	# A disabled car still blocks its physical lane, but must not lock every approach.
	if float(owner.get("damage")) > 70.0 or owner.global_position.distance_to(junctions[index].center) > 14.0:
		_release_junction(index)
		return
	if _actor_in_junction(owner, index): junctions[index].entered = true
	# Approaching cars lose their reservation when green ends; cars already inside clear the box.
	if not bool(junctions[index].get("entered", false)) and light_state(index, int(junctions[index].get("direction", 0))) != 2:
		_release_junction(index)


func _extract_surfaces() -> void:
	for node in city_map.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var n := str(mesh.name)
		var road := n.begins_with("SM_Env_Road_")
		for decoration in ["Lines", "Arrow", "Patch", "Median", "Parking"]:
			if decoration in n: road = false
		var walk := n.begins_with("SM_Env_Sidewalk_")
		if not road and not walk: continue
		var bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if bounds.position.y < -1 or bounds.position.y > 2: continue
		var step := CELL if road else WALK_CELL
		var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z)).grow(0.03)
		for x in range(floori(rect.position.x / step), ceili(rect.end.x / step)):
			for z in range(floori(rect.position.y / step), ceili(rect.end.y / step)):
				var p := Vector2((x + 0.5) * step, (z + 0.5) * step)
				if not rect.has_point(p): continue
				if road: road_cells[Vector2i(x, z)] = bounds.end.y
				else: sidewalk_cells[Vector2i(x, z)] = bounds.end.y
	# Road geometry wins over overlapping curb bounding boxes.
	for cell in sidewalk_cells.keys():
		var p := walk_position(cell)
		if road_cells.has(world_cell(p)): sidewalk_cells.erase(cell)


func _lane_allowed(cell: Vector2i, direction: int) -> bool:
	if not road_cells.has(cell): return false
	var forward: Vector2i = DIRECTIONS[direction]
	var right := Vector2i(-forward.y, forward.x)
	# A lane must continue along the street, not across its two-tile width.
	if not road_cells.has(cell + forward * 2) and not road_cells.has(cell - forward * 2): return false
	# Keep to the right side of each carriageway. Interior intersection cells permit turns.
	return not road_cells.has(cell + right) or road_cells.has(cell - right)


func _build_lanes() -> void:
	for cell in road_cells:
		for direction in 4:
			if not _lane_allowed(cell, direction): continue
			var state := Vector3i(cell.x, cell.y, direction)
			var options: Array[Vector3i] = []
			var forward: Vector2i = DIRECTIONS[direction]
			var lateral := Vector2i(-forward.y, forward.x)
			var intersection: bool = road_cells.has(cell + lateral) and road_cells.has(cell - lateral)
			for turn in [0, 1, -1]:
				if turn != 0 and not intersection and road_cells.has(cell + forward): continue
				var outgoing := posmod(direction + turn, 4)
				var next: Vector2i = cell + DIRECTIONS[outgoing]
				if _lane_allowed(next, outgoing): options.append(Vector3i(next.x, next.y, outgoing))
			if not options.is_empty(): lanes[state] = options
	# Remove branches ending on missing lane states; actors never route to a nonexistent node.
	while true:
		var removed := false
		for state in lanes.keys():
			var options: Array[Vector3i] = []
			for next in lanes[state]:
				if lanes.has(next): options.append(next)
			if options.is_empty():
				lanes.erase(state)
				removed = true
			else: lanes[state] = options
		if not removed: break


func _build_junctions() -> void:
	var candidates: Dictionary = {}
	for cell in road_cells:
		var count := 0
		for direction in DIRECTIONS:
			if road_cells.has(cell + direction): count += 1
		if count == 4: candidates[cell] = true
	while not candidates.is_empty():
		var open: Array[Vector2i] = [candidates.keys()[0]]
		var component: Array[Vector2i] = []
		while not open.is_empty():
			var cell: Vector2i = open.pop_back()
			if not candidates.has(cell): continue
			candidates.erase(cell)
			component.append(cell)
			for direction in DIRECTIONS:
				if candidates.has(cell + direction): open.append(cell + direction)
		if component.size() < 2 or component.size() > 25: continue
		var center := Vector3.ZERO
		for cell in component: center += road_position(cell)
		center /= component.size()
		var index := junctions.size()
		junctions.append({"center": center, "owner": null, "entered": false, "direction": 0})
		for cell in component: junction_cells[cell] = index
		var controller := TrafficSignal.new()
		controller.world = self
		controller.junction_index = index
		controller.position = center
		add_child(controller)
		signals.append(controller)


func _build_walkways() -> void:
	for cell in sidewalk_cells:
		var neighbors: Array[Vector2i] = []
		for direction in DIRECTIONS:
			var next: Vector2i = cell + direction
			if sidewalk_cells.has(next) and absf(sidewalk_cells[cell] - sidewalk_cells[next]) < 0.45:
				neighbors.append(next)
		if not neighbors.is_empty(): walk_neighbors[cell] = neighbors
	# Crossings are placed along each junction's curb line; cars receive an exclusive all-red walk phase.
	for index in junctions.size():
		var center: Vector3 = junctions[index].center
		for axis in [Vector3.RIGHT, Vector3.BACK]:
			var tangent: Vector3 = axis.cross(Vector3.UP)
			for side in [-1, 1]:
				var a := _closest_walk(center + tangent * side * 7.5 - axis * 7.5, 5)
				var b := _closest_walk(center + tangent * side * 7.5 + axis * 7.5, 5)
				if a == Vector2i(9999, 9999) or b == a or b == Vector2i(9999, 9999): continue
				var distance := walk_position(a).distance_to(walk_position(b))
				if distance < 7 or distance > 20: continue
				walk_neighbors[a].append(b)
				walk_neighbors[b].append(a)
				crossing_edges[_edge_key(a, b)] = index
				crossing_edges[_edge_key(b, a)] = index


func _closest_walk(p: Vector3, radius: float) -> Vector2i:
	var result := Vector2i(9999, 9999)
	var distance := radius
	var center := Vector2i(floori(p.x / WALK_CELL), floori(p.z / WALK_CELL))
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			var cell := center + Vector2i(dx, dz)
			if not walk_neighbors.has(cell): continue
			var candidate := walk_position(cell).distance_to(p)
			if candidate < distance:
				distance = candidate
				result = cell
	return result


func _organize_parked_cars() -> void:
	var cars := city_map.get_node_or_null("Road_Cars")
	if cars == null: return
	for car in cars.get_children():
		if not car is Node3D: continue
		if road_cells.has(world_cell(car.global_position)):
			# The asset showcase parks display cars in active lanes; replace those with moving traffic.
			car.free()
		else:
			car.add_to_group("parked_vehicles")
			parked_count += 1


func _spawn_population() -> void:
	# Keep the loading overlay responsive while models, colliders and rigs enter the tree.
	var car_batch := 0
	var pedestrian_batch := 0
	var model_bag: Array = []
	var candidates: Array = lanes.keys()
	candidates.shuffle()
	for state in candidates:
		if drivers.size() >= vehicle_count: break
		var p := lane_position(state)
		if junction_cells.has(Vector2i(state.x, state.y)): continue
		if is_instance_valid(subject) and p.distance_to(subject.global_position) < 16: continue
		var occupied := false
		for driver in drivers:
			if driver.position.distance_to(p) < 14: occupied = true; break
		if occupied or not _spawn_clear(p, Vector3(1.9, 1.5, 4.5), state.z * PI / 2): continue
		var actor := Driver.new()
		actor.world = self
		actor.state = state
		if model_bag.is_empty():
			model_bag.assign(VEHICLES)
			model_bag.shuffle()
		var vehicle_kind: String = model_bag.pop_back()
		actor.model_scene = load(Catalog.model_path(vehicle_kind))
		if vehicle_kind != "Taxi" and vehicle_kind not in Catalog.RUSSIAN_KINDS:
			actor.paint_tint = Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.3), rng.randf_range(0.65, 1.0))
		actor.acceleration = rng.randf_range(1.3, 2.5)
		actor.following_time = rng.randf_range(1.5, 2.1)
		actor.cruise_speed = rng.randf_range(6.5, 10.5) * (0.85 if vehicle_kind in ["Van", "UAZ469", "UAZ452"] else 1.0)
		actor.position = p + Vector3.UP * 0.03
		add_child(actor)
		drivers.append(actor)
		car_batch += 1
		if car_batch == 2:
			car_batch = 0
			await get_tree().process_frame
	var walk_candidates: Array = walk_neighbors.keys()
	walk_candidates.shuffle()
	for cell in walk_candidates:
		if citizens.size() >= citizen_count: break
		var p := walk_position(cell)
		if not _spawn_clear(p, Vector3(0.6, 1.7, 0.6)): continue
		var occupied := false
		for person in citizens:
			if person.position.distance_to(p) < 6: occupied = true; break
		if occupied: continue
		var person := Citizen.new()
		person.world = self
		person.cell = cell
		person.walk_speed = rng.randf_range(1.0, 1.65)
		person.model_scene = load("res://Assets/Synty/PolygonCity/Prefabs/Characters/Character_%s.tscn" % PEOPLE[citizens.size() % PEOPLE.size()])
		person.position = p + Vector3.UP * 0.03
		add_child(person)
		citizens.append(person)
		pedestrian_batch += 1
		if pedestrian_batch == 4:
			pedestrian_batch = 0
			await get_tree().process_frame


func _spawn_clear(p: Vector3, dims: Vector3, yaw: float = 0.0) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = dims
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * (dims.y / 2 + 0.15))
	query.collision_mask = 1 | 2 | 4 | 8
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func road_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL, float(road_cells.get(cell, 0)), (cell.y + 0.5) * CELL)


func walk_position(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * WALK_CELL, float(sidewalk_cells.get(cell, 0.2)), (cell.y + 0.5) * WALK_CELL)


func lane_position(state: Vector3i) -> Vector3:
	return road_position(Vector2i(state.x, state.y))


func world_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func choose_lane(state: Vector3i) -> Vector3i:
	var options: Array = lanes.get(state, [])
	if options.is_empty(): return state
	# Most drivers continue straight; occasional turns distribute traffic through the actual road network.
	if rng.randf() < 0.76:
		for next in options:
			if next.z == state.z: return next
	return options[rng.randi_range(0, options.size() - 1)]


func may_enter(actor: CharacterBody3D, from: Vector3i, to: Vector3i) -> bool:
	var index: int = junction_cells.get(Vector2i(to.x, to.y), -1)
	if index < 0: return true
	_refresh_junction(index)
	if float(actor.get("damage")) > 70.0: return false
	if _actor_in_junction(actor, index) or junction_cells.get(Vector2i(from.x, from.y), -1) == index: return true
	var owner: Node3D = junctions[index].owner
	if owner == actor and bool(junctions[index].get("entered", false)): return true
	if light_state(index, to.z) != 2: return false
	if is_instance_valid(owner) and owner != actor: return false
	if index < _crossing_occupancy.size() and _crossing_occupancy[index] > 0: return false
	# Do not block the box: require space beyond the crossing before entry.
	var direction: Vector2i = DIRECTIONS[to.z]
	var exit := lane_position(to) + Vector3(direction.x, 0, direction.y) * 9
	for other in nearby_drivers(exit, 9.0):
		if other == actor: continue
		var relative: Vector3 = other.global_position - exit
		var along := relative.x * direction.x + relative.z * direction.y
		var across := absf(relative.x * direction.y - relative.z * direction.x)
		if across < 2.2 and along > -3 and along < 8: return false
	junctions[index].owner = actor
	junctions[index].entered = false
	junctions[index].direction = to.z
	return true


func approach_speed(actor: CharacterBody3D, from: Vector3i, to: Vector3i) -> float:
	var forward: Vector2i = DIRECTIONS[to.z]
	for ahead in 3:
		var cell := Vector2i(to.x, to.y) + forward * ahead
		var index: int = junction_cells.get(cell, -1)
		if index < 0: continue
		if junction_cells.get(Vector2i(from.x, from.y), -1) == index: return INF
		var entry := Vector3i(cell.x, cell.y, to.z)
		if may_enter(actor, from, entry): return INF
		var distance := actor.global_position.distance_to(road_position(cell))
		# Brake before the crosswalk, accounting for the vehicle's front overhang.
		return sqrt(maxf(0, 2 * 4.0 * (distance - 8.5)))
	return INF


func light_state(_junction: int, direction: int) -> int:
	var phase := fmod(elapsed, 58.0)
	var ns := direction % 2 == 0
	if ns and phase < 11: return 2
	if ns and phase < 13: return 1
	if not ns and phase >= 15 and phase < 26: return 2
	if not ns and phase >= 26 and phase < 28: return 1
	return 0


func may_cross(a: Vector2i, b: Vector2i) -> bool:
	var index: int = crossing_edges.get(_edge_key(a, b), -1)
	if index < 0: return true
	var phase := fmod(elapsed, 58.0)
	if phase < 30 or phase >= 36: return false
	var start := walk_position(a)
	var end := walk_position(b)
	for driver in nearby_drivers((start + end) * 0.5, start.distance_to(end) * 0.5 + 3.2):
		if _distance_to_crossing(driver.global_position, start, end) < 3.2: return false
	if is_instance_valid(subject) and _distance_to_crossing(subject.global_position, start, end) < 3.2: return false
	return true


func _distance_to_crossing(p: Vector3, a: Vector3, b: Vector3) -> float:
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
	return Vector2(p.x, p.z).distance_to(nearest)


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	return "%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]


func debug_summary() -> Dictionary:
	return {"road_cells": road_cells.size(), "directed_lane_states": lanes.size(), "intersections": junctions.size(), "sidewalk_nodes": walk_neighbors.size(), "crossings": crossing_edges.size() / 2, "moving_cars": drivers.size(), "walkers": citizens.size(), "parked_cars": parked_count}
