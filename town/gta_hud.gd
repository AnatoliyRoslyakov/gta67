extends CanvasLayer

const CityRadar = preload("res://town/city_radar.gd")
var city_map: Node3D
var player_body: Node3D
var cash := 500
var wanted_level := 0
var radar: Control
var cash_label: Label
var wanted_label: Label
var clock_text := "17:30"
var driving := true
var riding_gary := false
var weapon_drawn := false
var ammo_text := "12 / 84"
var health := 100.0
var speed := 0.0
var boost_value := 1.0
var hint := ""
var clock_label: Label
var detail_label: Label
var hint_label: Label
var reticle: Label
var boost_bar: ProgressBar
var integrity_bar: ProgressBar
var integrity_label: Label
var wanted_status: Label
var wanted_progress: ProgressBar
var objective_title: Label
var objective_step: Label
var objective_metrics: Label
var notification_panel: Panel
var notification_label: Label
var notification_time := 0.0
var pending_notifications: Array[String] = []
var gameplay: Dictionary = {}
var _status_tick := 0.0


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Noto Sans", "DejaVu Sans"])
	root.add_theme_font_override("font", font)
	add_child(root)
	var radar_panel := Panel.new()
	radar_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	radar_panel.offset_left = 24
	radar_panel.offset_right = 232
	radar_panel.offset_top = -236
	radar_panel.offset_bottom = -28
	radar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(radar_panel)
	radar = CityRadar.new()
	radar.position = Vector2(4, 4)
	radar.size = Vector2(200, 200)
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.clip_contents = true
	radar_panel.add_child(radar)
	if is_instance_valid(city_map): radar.configure(city_map, player_body)
	var status_panel := Panel.new()
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status_panel.offset_left = -232
	status_panel.offset_right = -24
	status_panel.offset_top = 24
	status_panel.offset_bottom = 191
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(status_panel)
	cash_label = _label(status_panel, Vector2(18, 7), 30, Color("a4d3b2"))
	wanted_label = _label(status_panel, Vector2(18, 47), 30, Color("e9c5a1"))
	wanted_status = _label(status_panel, Vector2(18, 91), 14, Color("becbc8"))
	wanted_progress = _bar(status_panel, Vector2(18, 118), Vector2(172, 3), Color("ed817b"))
	clock_label = _label(status_panel, Vector2(18, 139), 14, Color("becbc8"))
	var detail_panel := Panel.new()
	root.add_child(detail_panel)
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	detail_panel.offset_left = -264
	detail_panel.offset_right = -24
	detail_panel.offset_top = -139
	detail_panel.offset_bottom = -28
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_theme_stylebox_override("panel", _panel_style())
	detail_label = _label(detail_panel, Vector2(18, 8), 26, Color("e9eee7"))
	boost_bar = ProgressBar.new()
	boost_bar.position = Vector2(18, 52)
	boost_bar.size = Vector2(204, 5)
	boost_bar.max_value = 1
	boost_bar.show_percentage = false
	boost_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.20, 0.27, 0.28, 0.75)
	boost_bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("6ecac3")
	boost_bar.add_theme_stylebox_override("fill", fill)
	detail_panel.add_child(boost_bar)
	boost_bar.size = Vector2(204, 5)
	integrity_label = _label(detail_panel, Vector2(18, 65), 13, Color("becbc8"))
	integrity_bar = _bar(detail_panel, Vector2(18, 91), Vector2(204, 4), Color("f0c574"))
	hint_label = _label(root, Vector2.ZERO, 16, Color("e1e6de"))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.offset_left = 256
	hint_label.anchor_right = 1.0
	hint_label.offset_right = -288
	hint_label.offset_top = -64
	hint_label.offset_bottom = -20
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 14)
	reticle = _label(root, Vector2.ZERO, 20, Color(1, 1, 1, 0.8))
	reticle.text = "+"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -7
	reticle.offset_top = -12
	_build_objective(root)
	_build_notification(root)
	_refresh_status()


func _process(delta: float) -> void:
	_status_tick -= delta
	if _status_tick <= 0.000001:
		_status_tick = maxf(_status_tick + 0.05, 0.0)
		_refresh_status()
		if is_instance_valid(player_body): radar.queue_redraw()
	if notification_time > 0:
		notification_time = maxf(0, notification_time - delta)
		notification_panel.modulate.a = minf(notification_time * 2.0, 1.0)
		if notification_time <= 0 and not pending_notifications.is_empty():
			_show_notification(pending_notifications.pop_front())
	notification_panel.visible = notification_time > 0


func _refresh_status() -> void:
	cash_label.text = "$%d" % maxi(cash, 0)
	var stars := clampi(wanted_level, 0, 3)
	wanted_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	clock_label.text = clock_text + "   Polygon City"
	detail_label.text = "%03d км/ч" % roundi(speed) if driving or riding_gary else (ammo_text + "   ПАТР." if weapon_drawn else "ПЕШКОМ")
	boost_bar.value = boost_value if driving else health / 100.0
	integrity_bar.visible = driving
	integrity_bar.value = clampf(float(gameplay.get("vehicle_health", 100.0)) / 100.0, 0, 1)
	integrity_label.text = "Кузов %d%%" % roundi(integrity_bar.value * 100) if driving else "Здоровье %d%%" % roundi(health)
	if riding_gary: integrity_label.text = "Гэри · здоровье %d%%" % roundi(health)
	hint_label.text = hint
	reticle.visible = not driving and weapon_drawn
	_refresh_gameplay()


func set_gameplay_state(state: Dictionary) -> void:
	gameplay = state
	var contract: Dictionary = state.get("contract", {})
	var police: Dictionary = state.get("police", {})
	if is_instance_valid(radar):
		radar.set_navigation({
			"route": contract.get("route", []),
			"target": contract.get("target", Vector3.INF),
			"active": contract.get("active", false),
			"police": police.get("blips", []),
			"service_position": state.get("service_position", Vector3.INF),
			"car_position": state.get("car_position", Vector3.INF),
			"on_foot": not driving,
		})


func notify_message(message: String) -> void:
	if message.is_empty(): return
	if notification_time <= 0 and is_instance_valid(notification_label):
		_show_notification(message)
	else:
		if pending_notifications.size() >= 3: pending_notifications.pop_front()
		pending_notifications.append(message)


func _show_notification(message: String) -> void:
	notification_label.text = message
	notification_time = 4.0
	notification_panel.modulate.a = 1.0


func _refresh_gameplay() -> void:
	var police: Dictionary = gameplay.get("police", {})
	var arrest := clampf(float(police.get("arrest_progress", 0.0)), 0, 1)
	var searching := not bool(police.get("seen", false))
	wanted_progress.visible = wanted_level > 0
	if wanted_level <= 0:
		wanted_status.text = "Вне розыска"
		wanted_status.modulate = Color("becbc8")
	elif arrest > 0:
		wanted_status.text = "Уезжайте — задержание"
		wanted_status.modulate = Color("ed817b")
		wanted_progress.value = arrest
	elif searching:
		wanted_status.text = "Полиция ищет вас"
		wanted_status.modulate = Color("f0c574")
		wanted_progress.value = clampf(float(police.get("search_progress", 0.0)), 0, 1)
	else:
		wanted_status.text = "Полиция видит вас"
		wanted_status.modulate = Color("ed817b")
		wanted_progress.value = 1.0
	var contract: Dictionary = gameplay.get("contract", {})
	if contract.get("active", false):
		objective_title.text = str(contract.get("title", "Городской заказ"))
		if contract.get("kind", "") == "circuit":
			objective_title.text = "Городской круг · %d/4" % int(contract.get("stage", 1)) if contract.get("race_started", false) else "Городской круг · к старту"
		objective_step.text = str(contract.get("description", contract.get("step", "Следуйте по маршруту")))
		var distance := maxf(0, float(contract.get("distance", 0)))
		var distance_text := "%.1f км" % (distance / 1000) if distance >= 1000 else "%d м" % roundi(distance)
		objective_metrics.text = distance_text + "    $%d" % int(contract.get("reward", 0))
		var remaining := float(contract.get("time_left", contract.get("remaining_time", -1.0)))
		if remaining >= 0 and contract.get("kind", "") == "circuit": objective_metrics.text += "    %02d:%02d" % [int(remaining) / 60, int(remaining) % 60]
	else:
		objective_title.text = "Городские заказы"
		objective_step.text = "Tab — заказы   Esc — пауза"
		objective_metrics.text = "S — сервис на карте   C — ваш автомобиль"


func _build_objective(root: Control) -> void:
	var panel := Panel.new()
	panel.position = Vector2(24, 104)
	panel.size = Vector2(328, 132)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := _panel_style()
	style.border_width_left = 3
	style.border_color = Color("f0c574")
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)
	objective_title = _label(panel, Vector2(17, 12), 20, Color("f0c574"))
	objective_title.size.x = 296
	objective_title.clip_text = true
	objective_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	objective_step = _label(panel, Vector2(17, 43), 15, Color("e2e8e3"))
	objective_step.size = Vector2(294, 48)
	objective_step.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_metrics = _label(panel, Vector2(17, 102), 12, Color("becbc8"))
	objective_metrics.size.x = 296
	objective_metrics.clip_text = true


func _build_notification(root: Control) -> void:
	notification_panel = Panel.new()
	root.add_child(notification_panel)
	notification_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	notification_panel.offset_left = -210
	notification_panel.offset_right = 210
	notification_panel.offset_top = 24
	notification_panel.offset_bottom = 86
	notification_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notification_panel.add_theme_stylebox_override("panel", _panel_style())
	notification_label = _label(notification_panel, Vector2(16, 11), 16, Color("e2e8e3"))
	notification_label.size = Vector2(388, 44)
	notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notification_panel.hide()
	if not pending_notifications.is_empty(): _show_notification(pending_notifications.pop_front())


func _bar(parent: Control, p: Vector2, dimensions: Vector2, color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.position = p
	bar.max_value = 1.0
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.2, 0.27, 0.28, 0.75)
	bar.add_theme_stylebox_override("background", background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("fill", fill)
	parent.add_child(bar)
	bar.size = dimensions
	return bar


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.07, 0.09, 0.72)
	return style


func _label(parent: Node, p: Vector2, font_size: int, tint: Color) -> Label:
	var label := Label.new()
	label.position = p
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tint)
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.06, 0.08, 0.8))
	label.add_theme_constant_override("outline_size", 1)
	parent.add_child(label)
	return label
