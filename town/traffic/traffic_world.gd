extends Node3D

signal start_bay_ready(pose: Transform3D)

const Catalog = preload("res://vehicles/vehicle_catalog.gd")
const Driver = preload("res://town/traffic/traffic_driver.gd")
const Citizen = preload("res://town/traffic/citizen.gd")
const TrafficSignal = preload("res://town/traffic/traffic_signal.gd")
const CELL := 5.0
const WALK_CELL := 2.5
const DRIVER_BUCKET_SIZE := 20.0
const DRIVER_INDEX_INTERVAL := 0.1
const DIRECTIONS := [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]
const VEHICLES := ["Sedan", "Small", "Medium", "Taxi", "Van", "Muscle", "UAZ469"]
const PEOPLE := ["Male_Hoodie", "Female_Jacket", "BusinessMan_Shirt", "BusinessWoman", "Male_Jacket", "Female_Coat", "BusinessMan_Suit"]

var positional_audio := true
@export var vehicle_count := 40
@export var citizen_count := 88
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
var drivers: Array[RigidBody3D] = []
var citizens: Array[CharacterBody3D] = []
var parked_count := 0
var _predecessors := {}
var inbound_distance := {}
var _flow_center := Vector3.INF
var _entry_lanes: Array[Vector3i] = []
var _sidewalk_entries: Array = []
var _flow_tick := 1.25
var _signal_second := -1
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
	_crossing_occupancy.resize(junctions.size())
	_build_walkways()
	_sidewalk_entries = walk_neighbors.keys()
	for lane: Vector3i in lanes:
		for branch in lanes[lane]:
			if not _predecessors.has(branch): _predecessors[branch] = []
			_predecessors[branch].append(lane)
		var ahead: Vector2i = DIRECTIONS[lane.z]
		var straight := Vector3i(lane.x + ahead.x, lane.y + ahead.y, lane.z)
		if straight in lanes[lane] and not junction_cells.has(Vector2i(lane.x, lane.y)):
			_entry_lanes.append(lane)
	_organize_parked_cars()
	await get_tree().physics_frame
	await _spawn_population()
	_rebuild_driver_index()
	await get_tree().physics_frame
	initialized = true
	add_child(preload("res://town/street_life.gd").new())


func _physics_process(delta: float) -> void:
	elapsed += delta
	if initialized and is_instance_valid(subject):
		_flow_tick -= delta
		if _flow_tick <= 0.0:
			_flow_tick = 0.9
			_stream_street_population()
	var second := floori(elapsed)
	if second != _signal_second:
		_signal_second = second
		for signal_head in signals: signal_head.show_phase()
	_driver_index_tick -= delta
	if _driver_index_tick <= 0.0:
		_driver_index_tick += DRIVER_INDEX_INTERVAL
		_rebuild_driver_index()
	for index in junctions.size():
		if junctions[index].owner != null: _refresh_junction(index)


func crossing_changed(previous: int, current: int) -> void:
	if previous >= 0: _crossing_occupancy[previous] -= 1
	if current >= 0: _crossing_occupancy[current] += 1


func _rebuild_driver_index() -> void:
	_driver_buckets.clear()
	for driver in drivers:
		if not is_instance_valid(driver): continue
		var p := driver.global_position
		var bucket := Vector2i(floori(p.x / DRIVER_BUCKET_SIZE), floori(p.z / DRIVER_BUCKET_SIZE))
		if not _driver_buckets.has(bucket): _driver_buckets[bucket] = []
		_driver_buckets[bucket].append(driver)
	_indexed_driver_count = drivers.size()


func nearby_drivers(origin: Vector3, radius: float) -> Array[RigidBody3D]:
	if _indexed_driver_count != drivers.size(): _rebuild_driver_index()
	var found: Array[RigidBody3D] = []
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
	elif junctions[index].entered:
		_release_junction(index)
		return
	# Approaching cars lose their reservation when green ends; cars already inside clear the box.
	if not bool(junctions[index].get("entered", false)) and light_state(index, int(junctions[index].get("direction", 0))) != 2:
		_release_junction(index)


func _extract_surfaces() -> void:
	for node in city_map.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var n := str(mesh.name)
		var road := n.begins_with("SM_Env_Road_")
		# Marked road tiles replace bare asphalt on parts of the showcase map.
		for decoration in ["Patch", "Median", "Parking"]:
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
	var bay: MeshInstance3D
	var nearest := INF
	for candidate in cars.get_children():
		if not candidate is MeshInstance3D or road_cells.has(world_cell(candidate.global_position)): continue
		var distance := subject.global_position.distance_squared_to(candidate.global_position)
		if distance < nearest:
			bay = candidate
			nearest = distance
	if bay:
		var pose := bay.global_transform.orthonormalized()
		bay.free()
		pose.origin += Vector3.UP * 0.35
		start_bay_ready.emit(pose)
	for car in cars.get_children():
		if not car is Node3D: continue
		if road_cells.has(world_cell(car.global_position)):
			# The asset showcase parks display cars in active lanes; replace those with moving traffic.
			car.free()
		elif posmod(hash(car.global_position.round()), 3) != 0:
			car.free()
		else:
			if car is MeshInstance3D: _park_car(car)
			parked_count += 1


# One sleeping convex body replaces the showcase model's per-wheel static
# colliders and concave body. A collision can wake and displace the whole car.
func _park_car(car: MeshInstance3D) -> void:
	var pose := car.global_transform.orthonormalized()
	var body := RigidBody3D.new()
	body.mass = 1850 if "Van" in str(car.name) or "Ambo" in str(car.name) else 1350
	body.linear_damp = 1.1
	body.angular_damp = 2.0
	body.collision_layer = 4
	body.collision_mask = 1 | 2 | 4 | 8
	for old_body in car.find_children("*", "StaticBody3D", true, false): old_body.free()
	var bounds: AABB = pose.affine_inverse() * car.global_transform * car.get_aabb()
	for wheel: MeshInstance3D in car.find_children("*Wheel_*", "MeshInstance3D", true, false):
		var wheel_bounds: AABB = pose.affine_inverse() * wheel.global_transform * wheel.get_aabb()
		bounds = bounds.merge(wheel_bounds)
	var collider := CollisionShape3D.new()
	var hull := BoxShape3D.new()
	hull.size = bounds.size * Vector3(0.88, 1.0, 0.93)
	collider.shape = hull
	collider.position = bounds.get_center()
	body.add_child(collider)
	car.get_parent().add_child(body)
	body.global_transform = pose
	car.reparent(body)
	body.add_to_group("parked_vehicles")
	body.sleeping = true
	body.reset_physics_interpolation()


func _spawn_population() -> void:
	await _spawn_drivers()
	await _spawn_walkers()


func _spawn_drivers() -> void:
	# Keep the loading overlay responsive while models, colliders and rigs enter the tree.
	var car_batch := 0
	var palette := ["c04e41","43856c","e1dbca","b86d37","783b60","5399ac","50545c","888fbc","a0af68"]
	var colors := palette.duplicate()
	colors.shuffle()
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
			actor.paint_tint = Color(colors.pop_back())
			if colors.is_empty():
				colors = palette.duplicate()
				colors.shuffle()
		actor.acceleration = rng.randf_range(1.3, 2.5)
		actor.following_time = rng.randf_range(1.5, 2.1)
		actor.cruise_speed = rng.randf_range(6.5, 10.5) * (0.85 if vehicle_kind in ["Van", "UAZ469"] else 1.0)
		actor.position = p + Vector3.UP * 0.03
		add_child(actor)
		drivers.append(actor)
		car_batch += 1
		if car_batch == 2:
			car_batch = 0
			await get_tree().process_frame


func _spawn_walkers() -> void:
	var pedestrian_batch := 0
	var walk_candidates: Array = walk_neighbors.keys()
	walk_candidates.shuffle()
	var local_streets := []
	for cell in walk_candidates:
		var gap := walk_position(cell).distance_squared_to(subject.global_position)
		if gap > 6 ** 2 and gap < 45 ** 2: local_streets.append(cell)
	walk_candidates = local_streets.slice(0, 24) + walk_candidates
	for cell in walk_candidates:
		if citizens.size() >= citizen_count: break
		var p := walk_position(cell)
		if not _spawn_clear(p, Vector3(0.6, 1.7, 0.6)): continue
		var occupied := false
		for person in citizens:
			if person.position.distance_to(p) < 3.7: occupied = true; break
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


# New journeys enter from unseen streets. Keep vehicles involved in an impact,
# nearby queues, police, and pedestrians in a conversation in their current scene.
func _out_of_sight(point: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	if point.distance_squared_to(subject.global_position) < 34 ** 2: return false
	for height in [0.7, 2.2]:
		var sample_point: Vector3 = point + Vector3.UP * height
		if not camera.is_position_in_frustum(sample_point): continue
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, sample_point, 1)
		if subject is CollisionObject3D: ray.exclude = [subject.get_rid()]
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	return true


# Reverse breadth-first distances route arrivals along connected roads.
# Euclidean heading alone sends cars into parallel streets behind the block.
func _update_arrivals(origin: Vector3) -> void:
	if _flow_center.distance_squared_to(origin) < 18 ** 2: return
	_flow_center = origin
	inbound_distance.clear()
	var queue: Array[Vector3i] = []
	var nearest := INF
	for lane: Vector3i in lanes: nearest = minf(nearest, origin.distance_to(lane_position(lane)))
	for lane: Vector3i in lanes:
		if origin.distance_to(lane_position(lane)) < nearest + 10:
			inbound_distance[lane] = 0
			queue.append(lane)
	var cursor := 0
	while cursor < queue.size():
		var lane := queue[cursor]
		cursor += 1
		for previous in _predecessors.get(lane, []):
			if inbound_distance.has(previous): continue
			inbound_distance[previous] = int(inbound_distance[lane]) + 1
			queue.append(previous)


func _stream_street_population() -> void:
	var origin := subject.global_position
	_update_arrivals(origin)
	var nearby := nearby_drivers(origin, 58)
	var moving := 0
	for car in nearby:
		if car.speed > 1.5: moving += 1
	var donor: RigidBody3D
	var best_score := -INF
	for car in drivers:
		if car.is_in_group("police") or car.damage > 0 or car.grip_recovery > 0: continue
		var distance := origin.distance_to(car.global_position)
		var stalled: bool = car.stationary_time > 9 and car._plan_speed > 1.0
		if not stalled and (distance < 85 or moving >= 7): continue
		var score := distance + (150.0 if stalled else 0.0)
		if score > best_score and _out_of_sight(car.global_position):
			best_score = score
			donor = car
	if donor != null:
		var best_lane := Vector3i.ZERO
		var best := -INF
		for attempt in 80:
			var lane := _entry_lanes[rng.randi_range(0, _entry_lanes.size() - 1)]
			var p := lane_position(lane)
			var relative := origin - p
			var distance := relative.length()
			if distance < 35 or distance > (135 if moving >= 5 else 100): continue
			var axis: Vector2i = DIRECTIONS[lane.z]
			var forward := Vector3(axis.x, 0, axis.y)
			var alignment := relative.normalized().dot(forward)
			var straight := Vector3i(lane.x + axis.x, lane.y + axis.y, lane.z)
			var hops := int(inbound_distance.get(straight, 999))
			if moving < 5 and hops >= 24: continue
			var score := rng.randf() + alignment * 0.8 - absf(distance - 65) * 0.008
			if moving < 5: score += 0.9 - hops * 0.04
			# Check the block downstream too. A free gap at the tail of a queue
			# is not a useful entry lane for another vehicle.
			for neighbor in nearby_drivers(p + forward * 18, 24):
				if neighbor == donor: continue
				var separation := neighbor.global_position - p
				if absf(separation.cross(forward).y) > 3.3: continue
				score -= 0.7 if neighbor.speed > 2.0 else 3.5
			if score < -1.2: continue
			if score <= best or not nearby_drivers(p, 11).is_empty() or not _out_of_sight(p): continue
			if not _spawn_clear(p, Vector3(2.3, 1.8, 6.0), atan2(axis.x, axis.y)): continue
			best = score
			best_lane = lane
		if is_finite(best):
			for i in junctions.size():
				if junctions[i].owner == donor: _release_junction(i)
			donor.start_journey(best_lane, moving < 5)
			_rebuild_driver_index()
	var local_walkers := 0
	var distant: CharacterBody3D
	var farthest := 70.0 ** 2
	for person in citizens:
		var d := origin.distance_squared_to(person.global_position)
		if d < 38 ** 2: local_walkers += 1
		if d > farthest and person.health == 100 and person.can_chat() and _out_of_sight(person.global_position):
			farthest = d
			distant = person
	if local_walkers >= 15 or distant == null: return
	for attempt in 48:
		var cell: Vector2i = _sidewalk_entries[rng.randi_range(0, _sidewalk_entries.size() - 1)]
		var p := walk_position(cell)
		if p.distance_squared_to(origin) > 42 ** 2 or not _out_of_sight(p): continue
		if not _spawn_clear(p, Vector3(0.9, 1.7, 0.9)): continue
		distant.global_position = p + Vector3.UP * 0.03
		distant.velocity = Vector3.ZERO
		distant.cell = cell
		distant.previous_cell = cell
		distant._choose_next()
		distant.motion._clear_foot_locks()
		distant.reset_physics_interpolation()
		break


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
	if options.size() == 1: return options[0]
	# Favor a continuous carriageway. A single adjacent road tile can be a
	# median opening or a parking apron rather than a usable through street.
	var best := -INF
	var selected: Vector3i = options[0]
	for candidate: Vector3i in options:
		var axis: Vector2i = DIRECTIONS[candidate.z]
		var step := Vector3i(axis.x, axis.y, 0)
		var cursor := candidate
		var continuity := 0
		for i in 4:
			if not lanes.has(cursor) or cursor + step not in lanes[cursor]: break
			continuity += 1
			cursor += step
		var score := rng.randf_range(0.0, 2.0) + continuity * 0.85
		if candidate.z == state.z: score += 0.8
		for other in nearby_drivers(lane_position(candidate) + Vector3(axis.x, 0, axis.y) * 8, 7):
			if other.speed < 1.2: score -= 1.4
		if score > best:
			best = score
			selected = candidate
	return selected


func may_enter(actor: RigidBody3D, from: Vector3i, to: Vector3i) -> bool:
	var index: int = junction_cells.get(Vector2i(to.x, to.y), -1)
	if index < 0: return true
	_refresh_junction(index)
	if float(actor.get("damage")) > 70.0: return false
	if _actor_in_junction(actor, index) or junction_cells.get(Vector2i(from.x, from.y), -1) == index: return true
	var owner: Node3D = junctions[index].owner
	if owner == actor and bool(junctions[index].get("entered", false)): return true
	if light_state(index, to.z) != 2: return false
	if is_instance_valid(owner) and owner != actor:
		var parallel: bool = posmod(int(junctions[index].direction) - to.z, 2) == 0
		if not parallel or owner._plan_turn or actor._plan_turn: return false
	if index < _crossing_occupancy.size() and _crossing_occupancy[index] > 0:
		var lane_axis: Vector2i = DIRECTIONS[to.z]
		var approach := Vector3(lane_axis.x, 0, lane_axis.y)
		for person in citizens:
			if person.crossing_junction != index: continue
			var ahead := person.global_position - actor.global_position
			if ahead.dot(approach) > 0 and ahead.dot(approach) < 14 and absf(ahead.cross(approach).y) < 2.6: return false
	# Do not block the box: require space beyond the crossing before entry.
	var direction: Vector2i = DIRECTIONS[to.z]
	var exit := lane_position(to) + Vector3(direction.x, 0, direction.y) * 9
	for other in nearby_drivers(exit, 9.0):
		if other == actor: continue
		var relative: Vector3 = other.global_position - exit
		var along := relative.x * direction.x + relative.z * direction.y
		var across := absf(relative.x * direction.y - relative.z * direction.x)
		if other.speed < 1.2 and across < 1.8 and along > -2 and along < 5: return false
	if is_instance_valid(owner) or actor.global_position.distance_squared_to(lane_position(to)) > 7.5 ** 2: return true
	junctions[index].owner = actor
	junctions[index].entered = false
	junctions[index].direction = to.z
	return true


func approach_speed(actor: RigidBody3D, from: Vector3i, to: Vector3i) -> float:
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
		return sqrt(maxf(0, 2 * 4.0 * (distance - 5.6)))
	return INF


func junction_phase(index: int) -> int:
	return posmod(floori(elapsed) + index * 7, 42)


func walk_signal(index: int) -> bool:
	var phase := junction_phase(index)
	return phase >= 36 and phase < 41


func light_state(index: int, direction: int) -> int:
	var phase := junction_phase(index)
	if direction % 2 == 0:
		if phase < 15: return 2
		if phase < 17: return 1
	else:
		if phase >= 18 and phase < 33: return 2
		if phase >= 33 and phase < 35: return 1
	return 0


func may_cross(a: Vector2i, b: Vector2i) -> bool:
	var index: int = crossing_edges.get(_edge_key(a, b), -1)
	if index < 0: return true
	if not walk_signal(index): return false
	var start := walk_position(a)
	var end := walk_position(b)
	# A person checks approaching vehicles before stepping off the curb, including
	# a player approaching on red. Once committed they keep their reservation.
	for driver in nearby_drivers((start + end) * 0.5, start.distance_to(end) * 0.5 + 26.0):
		if _will_reach_crosswalk(driver, start, end): return false
	if subject is RigidBody3D and _will_reach_crosswalk(subject, start, end): return false
	return true


func _will_reach_crosswalk(car: RigidBody3D, start: Vector3, end: Vector3) -> bool:
	var position_xz := Vector2(car.global_position.x, car.global_position.z)
	var travel := Vector2(car.linear_velocity.x, car.linear_velocity.z) * 1.8
	if travel.length_squared() < 0.1: return _distance_to_crossing(car.global_position, start, end) < 2.3
	var closest := Geometry2D.get_closest_points_between_segments(position_xz, position_xz + travel, Vector2(start.x, start.z), Vector2(end.x, end.z))
	return closest[0].distance_squared_to(closest[1]) < 2.3 * 2.3


func _distance_to_crossing(p: Vector3, a: Vector3, b: Vector3) -> float:
	var nearest := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), Vector2(a.x, a.z), Vector2(b.x, b.z))
	return Vector2(p.x, p.z).distance_to(nearest)


func _edge_key(a: Vector2i, b: Vector2i) -> String:
	return "%d,%d>%d,%d" % [a.x, a.y, b.x, b.y]


func debug_summary() -> Dictionary:
	return {"road_cells": road_cells.size(), "directed_lane_states": lanes.size(), "intersections": junctions.size(), "sidewalk_nodes": walk_neighbors.size(), "crossings": crossing_edges.size() / 2, "moving_cars": drivers.size(), "walkers": citizens.size(), "parked_cars": parked_count}
