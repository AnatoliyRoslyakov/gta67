extends Node

const Progress = preload("res://town/gameplay/city_progress.gd")
const Contracts = preload("res://town/gameplay/city_contracts.gd")
const Police = preload("res://town/gameplay/city_police.gd")
const CityMenu = preload("res://town/gameplay/city_menu.gd")
var town: Node3D
var progress = Progress.new()
var contracts: Node3D
var police: Node3D
var menu: CanvasLayer
var service_position := Vector3.ZERO
var vehicle_key := ""
var _ui_tick := 0.0
var _save_tick := 20.0
var _recovery_cooldown := 0.0
var _configured := false
var _save_error_reported := false
var _return_to_selector: Callable
var _pending_recovery: Dictionary = {}


func configure(scene: Node3D, back: Callable) -> void:
	town = scene
	_return_to_selector = back
	process_mode = Node.PROCESS_MODE_ALWAYS
	progress.load_progress()
	vehicle_key = town.player_body.vehicle_scene.resource_path.get_file().get_basename()
	town.cash = progress.cash
	town.vehicle_health = float(progress.vehicle_health.get(vehicle_key, 100.0))
	town.character.magazine = progress.magazine
	town.character.reserve = progress.reserve
	town.character.health = progress.player_health
	town.player_body.drive_condition = town.vehicle_health / 100.0
	contracts = Contracts.new()
	contracts.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(contracts)
	contracts.configure(town)
	contracts.completed.connect(_on_contract_completed)
	contracts.connect("notification", _notify)
	police = Police.new()
	police.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(police)
	police.configure(town)
	police.wanted_changed.connect(func(level: int): town.wanted_level = level)
	police.busted.connect(_on_busted)
	police.connect("notification", _notify)
	menu = CityMenu.new()
	add_child(menu)
	menu.resume_requested.connect(close_menu)
	menu.contract_requested.connect(start_contract)
	menu.cancel_contract_requested.connect(_cancel_contract)
	menu.service_requested.connect(service_vehicle)
	menu.vehicle_select_requested.connect(_return_to_cars)
	town.player_body.collision_impact.connect(_on_vehicle_impact)
	town.player_body.shot_damage.connect(_damage_vehicle)
	town.character.incapacitated.connect(_on_incapacitated)
	service_position = town.spawn_transform.origin + Vector3(-4.5, -0.4, -8.0)
	_create_service_marker()
	_configured = true
	_notify("Tab — заказы и маршрут. F — действие у цели или сервиса.")
	if not progress.load_warning.is_empty(): _notify(progress.load_warning)
	_refresh_ui()


func _process(delta: float) -> void:
	if not _configured: return
	# Menu transactions explicitly refresh their own state. A frozen city does
	# not need new dictionaries, label shaping and radar redraws every 150 ms.
	if get_tree().paused: return
	_ui_tick -= delta
	if _ui_tick <= 0:
		_ui_tick = 0.15
		_refresh_ui()
	_recovery_cooldown = maxf(0.0, _recovery_cooldown - delta)
	if _recovery_cooldown <= 0:
		if not _pending_recovery.is_empty():
			var pending := _pending_recovery.duplicate()
			_pending_recovery.clear()
			_recover_after_incident(pending.reason, pending.fee)
		elif town.character.health <= 0:
			_on_incapacitated()
	_save_tick -= delta
	if _save_tick <= 0:
		_save_tick = 20.0
		save_progress()


func _unhandled_input(event: InputEvent) -> void:
	if not _configured or CityPerformance.loading: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_TAB or event.is_action_pressed("back"):
			get_viewport().set_input_as_handled()
			if menu.visible: close_menu()
			else: open_menu()
		elif event.physical_keycode == KEY_F and not get_tree().paused:
			get_viewport().set_input_as_handled()
			if not contracts.interact(): service_vehicle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and _configured:
		open_menu.call_deferred()


func open_menu() -> void:
	if not _configured or menu.visible or CityPerformance.loading: return
	town.character.aiming = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.open(snapshot())
	save_progress()


func close_menu() -> void:
	if not _configured: return
	menu.close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if town.driving else Input.MOUSE_MODE_CAPTURED


func snapshot() -> Dictionary:
	var distance: float = town.player_body.global_position.distance_to(service_position)
	return {"cash": town.cash, "completed_jobs": progress.completed_jobs,
		"best_circuit": progress.best_circuit, "total_earned": progress.total_earned,
		"vehicle_health": town.vehicle_health, "player_health": town.character.health,
		"ammo": "%02d / %02d" % [town.character.magazine, town.character.reserve],
		"contract": contracts.get_state(), "police": police.get_state(),
		"service_position": service_position, "car_position": town.player_body.global_position,
		"service_available": _service_available(), "service_cost": service_cost(),
		"service_distance": distance, "on_foot": not town.driving}


func _refresh_ui() -> void:
	var state := snapshot()
	town.gta_hud.set_gameplay_state(state)
	if menu.visible: menu.update_state(state)


func context_hint() -> String:
	var job: Dictionary = contracts.get_state()
	if job.get("can_interact", false): return "F — " + str(job.get("interaction", "передать посылку"))
	if _service_available():
		var price := service_cost()
		if price > 0: return "F — ремонт и припасы · $%d" % price
	return ""


func start_contract(kind: String) -> void:
	if town.wanted_level > 0:
		_notify("Сначала скройтесь от полиции")
		return
	if town.vehicle_health <= 0:
		_notify("Автомобиль разбит. F5 — эвакуация, затем ремонт в сервисе")
		return
	if contracts.start_contract(kind): close_menu()
	_refresh_ui()


func _cancel_contract() -> void:
	contracts.cancel_contract()
	_refresh_ui()


func _on_contract_completed(reward: int, kind: String, _bonus: int) -> void:
	town.cash += reward
	progress.completed_jobs += 1
	progress.total_earned += reward
	if kind == "circuit":
		var time: float = contracts.get_state().get("last_time", 0.0)
		if time > 0 and (progress.best_circuit <= 0 or time < progress.best_circuit):
			progress.best_circuit = time
	save_progress()
	_refresh_ui()


func _service_available() -> bool:
	if town.wanted_level > 0 or town.transition: return false
	if town.player_body.global_position.distance_to(service_position) > 10.0: return false
	if town.player_body.linear_velocity.length() > 0.6: return false
	return town.driving or town.character.global_position.distance_to(service_position) < 10.0


func service_cost() -> int:
	var missing_ammo: int = 96 - town.character.magazine - town.character.reserve
	return ceili((100.0 - town.vehicle_health) * 1.5 + (100.0 - town.character.health) * 0.5 + maxi(0, missing_ammo) * 0.75)


func service_vehicle() -> void:
	if not _service_available():
		_notify("Остановите автомобиль у голубого значка сервиса. Розыск должен закончиться.")
		return
	var price := service_cost()
	if price <= 0:
		_notify("Автомобиль исправен, здоровье и припасы полные")
		return
	if town.cash < price:
		_notify("Нужно $%d. Выполните заказ, чтобы заработать." % price)
		return
	town.cash -= price
	town.vehicle_health = 100.0
	town.player_body.drive_condition = 1.0
	town.character.health = 100.0
	town.character.magazine = 12
	town.character.reserve = 84
	town.character.reload_time = 0.0
	save_progress()
	_notify("Автомобиль восстановлен, припасы пополнены · −$%d" % price)
	_refresh_ui()


func report_shot(origin: Vector3, collider: Object) -> void:
	if _recovery_cooldown > 0: return
	var severity := 1
	if is_instance_valid(collider) and collider is Node:
		if collider.is_in_group("police") or collider.is_in_group("pedestrians"): severity = 2
	police.report_crime(severity, origin)


func _on_vehicle_impact(strength: float, collider: Node, own_closing_speed: float) -> void:
	if _recovery_cooldown > 0: return
	_damage_vehicle(clampf((strength - 2.5) * 3.0, 0.0, 45.0))
	if not town.driving or not is_instance_valid(collider) or own_closing_speed < 3.0: return
	if collider.is_in_group("pedestrians") and strength > 3.0:
		if collider.has_method("receive_hit"): collider.receive_hit(strength * 5, town.player_body.global_basis.z)
		police.report_crime(2, town.player_body.global_position)
	elif collider.is_in_group("police") and strength > 3.5:
		police.report_crime(1, town.player_body.global_position)
	elif collider.is_in_group("traffic") and strength > 7.0:
		police.report_crime(1, town.player_body.global_position)


func _damage_vehicle(amount: float) -> void:
	if amount <= 0 or _recovery_cooldown > 0: return
	var previous: float = town.vehicle_health
	town.vehicle_health = maxf(0.0, previous - amount)
	town.player_body.drive_condition = town.vehicle_health / 100.0
	if town.driving and amount > 10: town.character.receive_hit(amount * 0.15, Vector3.ZERO)
	if previous > 0 and town.vehicle_health <= 0:
		contracts.fail_contract("Автомобиль разбит")
		_notify("Двигатель повреждён. E — выйти · F5 — эвакуация")
	elif previous > 30 and town.vehicle_health <= 30:
		_notify("Автомобиль повреждён. Заезжайте в сервис — голубой значок на радаре")


func recover_vehicle() -> void:
	if _recovery_cooldown > 0: return
	if town.wanted_level > 0:
		_notify("Эвакуация недоступна во время погони")
		return
	if not town.reset_vehicle(): return
	contracts.on_vehicle_reset()
	var fee: int = mini(town.cash, 75)
	town.cash -= fee
	town.vehicle_health = maxf(town.vehicle_health, 35.0)
	town.player_body.drive_condition = town.vehicle_health / 100.0
	_recovery_cooldown = 3.0
	save_progress()
	_notify("Эвакуация · −$%d. Полный ремонт доступен в сервисе." % fee)


func _on_busted() -> void:
	if _recovery_cooldown > 0: return
	_recover_after_incident("Задержание", 200)

func recover_world_fall() -> void:
	if _recovery_cooldown <= 0 and _pending_recovery.is_empty(): _recover_after_incident("Возвращение в город", 0)


func _on_incapacitated() -> void:
	if _recovery_cooldown > 0: return
	_recover_after_incident("Медицинская помощь", 100)


func _recover_after_incident(reason: String, maximum_fee: int) -> void:
	if not town.reset_vehicle():
		_pending_recovery = {"reason": reason, "fee": maximum_fee}
		_recovery_cooldown = 2.0
		_notify("Ищем свободное место для возвращения в город…")
		return
	_recovery_cooldown = 3.0
	_pending_recovery.clear()
	police.clear_wanted()
	contracts.fail_contract(reason)
	var fee: int = mini(town.cash, maximum_fee)
	town.cash -= fee
	town.character.health = 100.0
	town.character.grant_invulnerability(3.0)
	town.vehicle_health = maxf(town.vehicle_health, 35.0)
	town.player_body.drive_condition = town.vehicle_health / 100.0
	if not town.driving:
		if is_instance_valid(town.character.mount):
			town.character.mount.unboard(town.player_body.global_position + Vector3.UP * 2)
		var exit: Vector3 = town._safe_exit()
		if exit != Vector3.INF:
			town.character.global_position = exit
			town.character.velocity = Vector3.ZERO
			town.character.reset_physics_interpolation()
		else:
			town.character.set_active(false)
			town.player_body.set_controlled(true)
			town.driving = true
			town._set_subject(town.player_body)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	save_progress()
	_notify("%s · −$%d. Можно вернуться к заказам." % [reason, fee])


func save_progress() -> void:
	if not _configured or not _pending_recovery.is_empty(): return
	progress.cash = town.cash
	progress.vehicle_health[vehicle_key] = town.vehicle_health
	progress.player_health = town.character.health
	progress.magazine = town.character.magazine
	progress.reserve = town.character.reserve
	var error: Error = progress.save_progress()
	if error != OK and not _save_error_reported:
		_save_error_reported = true
		_notify("Прогресс не записан: проверьте доступ к папке сохранений")


func _return_to_cars() -> void:
	if town.wanted_level > 0:
		_notify("Сначала завершите погоню")
		return
	contracts.cancel_contract()
	save_progress()
	close_menu()
	_return_to_selector.call()


func _notify(message: String) -> void:
	if is_instance_valid(town) and is_instance_valid(town.gta_hud): town.gta_hud.notify_message(message)


func _create_service_marker() -> void:
	var marker := Node3D.new()
	marker.name = "CityService"
	add_child(marker)
	marker.global_position = service_position
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 1.45
	mesh.outer_radius = 1.55
	mesh.rings = 32
	mesh.ring_segments = 8
	ring.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("74cfc7")
	material.emission_enabled = true
	material.emission = Color("74cfc7")
	material.emission_energy_multiplier = 0.6
	ring.material_override = material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(ring)
	var label := Label3D.new()
	label.text = "Сервис\nРемонт · припасы"
	label.position.y = 2.6
	label.font_size = 32
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color("a9eee1")
	label.visibility_range_end = 45.0
	marker.add_child(label)
	_place_service_marker.call_deferred(marker)


func _place_service_marker(marker: Node3D) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(marker) or not is_instance_valid(town): return
	var ray := PhysicsRayQueryParameters3D.create(service_position + Vector3.UP * 3, service_position - Vector3.UP * 3, 1, [town.player_body.get_rid()])
	var ground := town.get_world_3d().direct_space_state.intersect_ray(ray)
	if not ground.is_empty():
		service_position.y = ground.position.y + 0.06
		marker.global_position = service_position


func _exit_tree() -> void:
	if _configured and is_instance_valid(town): save_progress()
	if get_tree(): get_tree().paused = false
