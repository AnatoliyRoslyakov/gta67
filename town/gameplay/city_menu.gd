extends CanvasLayer

signal resume_requested
signal contract_requested(kind: String)
signal cancel_contract_requested
signal service_requested
signal vehicle_select_requested

const INK := Color("101c24")
const PANEL := Color("1f3039")
const TEXT := Color("e2e8e3")
const MUTED := Color("aebfc5")
const ROUTE := Color("f0c574")
const SERVICE := Color("74cfc7")

var snapshot: Dictionary = {}
var stats_label: Label
var active_label: Label
var record_label: Label
var garage_label: Label
var resume_button: Button
var delivery_button: Button
var circuit_button: Button
var cancel_button: Button
var service_button: Button
var content: VBoxContainer
var quality_choice: OptionButton


func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Avenir Next", "Noto Sans", "DejaVu Sans"])
	theme.default_font = font
	theme.default_font_size = 16
	root.theme = theme
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.045, 0.06, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var frame := PanelContainer.new()
	root.add_child(frame)
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.anchor_left = 0.14
	frame.anchor_right = 0.86
	frame.offset_left = 0
	frame.offset_right = 0
	frame.offset_top = 30
	frame.offset_bottom = -30
	var panel_style := _style(INK)
	panel_style.border_width_left = 4
	panel_style.border_color = ROUTE
	panel_style.content_margin_left = 28
	panel_style.content_margin_right = 28
	panel_style.content_margin_top = 22
	panel_style.content_margin_bottom = 22
	frame.add_theme_stylebox_override("panel", panel_style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	frame.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	scroll.add_child(content)
	var heading := HBoxContainer.new()
	content.add_child(heading)
	var title := _label("Городские заказы", 28, TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	resume_button = _button("Продолжить", ROUTE)
	resume_button.pressed.connect(func(): resume_requested.emit())
	heading.add_child(resume_button)
	stats_label = _label("", 16, MUTED)
	content.add_child(stats_label)
	active_label = _label("", 16, ROUTE)
	content.add_child(active_label)
	cancel_button = _button("Отменить текущий заказ", MUTED)
	cancel_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cancel_button.pressed.connect(func(): cancel_contract_requested.emit())
	content.add_child(cancel_button)
	_separator()
	delivery_button = _job("Доставка по городу", "Заберите посылку и доставьте её клиенту. От $180 за маршрут и бонус $100 за аккуратную езду.", "Взять доставку", "delivery")
	circuit_button = _job("Маршрут на время", "Остановитесь на старте и нажмите F. Четыре точки, один фиксированный маршрут и личный рекорд. От $320 и бонус $100 за аккуратную езду.", "Выбрать заезд", "circuit")
	record_label = _label("", 14, MUTED)
	content.add_child(record_label)
	_separator()
	var garage_heading := _label("Сервис и припасы", 21, SERVICE)
	content.add_child(garage_heading)
	garage_label = _label("", 15, MUTED)
	content.add_child(garage_label)
	service_button = _button("Обслужить автомобиль", SERVICE)
	service_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	service_button.pressed.connect(func(): service_requested.emit())
	content.add_child(service_button)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 18)
	content.add_child(footer)
	var select_button := _button("Выбор автомобиля", MUTED)
	select_button.pressed.connect(func(): vehicle_select_requested.emit())
	footer.add_child(select_button)
	var pause_hint := _label("Игра на паузе. Esc — продолжить.", 13, MUTED)
	pause_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(pause_hint)
	var graphics := HBoxContainer.new()
	graphics.add_theme_constant_override("separation", 18)
	content.add_child(graphics)
	var graphics_label := _label("Графика и расход энергии", 14, MUTED)
	graphics_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	graphics_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	graphics.add_child(graphics_label)
	quality_choice = OptionButton.new()
	for label in CityPerformance.LABELS: quality_choice.add_item(label)
	quality_choice.select(CityPerformance.quality)
	quality_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality_choice.custom_minimum_size.y = 36
	quality_choice.item_selected.connect(func(index: int): CityPerformance.set_quality(index))
	graphics.add_child(quality_choice)
	hide()


func open(state: Dictionary) -> void:
	update_state(state)
	show()
	resume_button.grab_focus.call_deferred()


func close() -> void:
	hide()


func update_state(state: Dictionary) -> void:
	snapshot = state
	if not is_instance_valid(stats_label): return
	var money := int(state.get("cash", 0))
	var completed := int(state.get("completed_jobs", 0))
	stats_label.text = "$%d     Выполнено заказов: %d" % [money, completed]
	var contract: Dictionary = state.get("contract", {})
	var active := bool(contract.get("active", false))
	var ready := bool(contract.get("ready", true))
	var police: Dictionary = state.get("police", {})
	var wanted := int(police.get("level", 0)) > 0
	if not ready:
		active_label.text = "Подготавливаем городские маршруты…"
	elif active:
		active_label.text = "%s: %s" % [str(contract.get("title", "Текущий заказ")), str(contract.get("description", "Следуйте по маршруту"))]
	elif wanted:
		active_label.text = "Сначала скройтесь от полиции, затем возьмите заказ."
	else:
		active_label.text = "Выберите работу. Маршрут появится на радаре."
	cancel_button.visible = active
	delivery_button.disabled = active or wanted or not ready
	circuit_button.disabled = active or wanted or not ready
	var best := float(state.get("best_circuit", 0.0))
	record_label.text = "Рекорд заезда: %02d:%05.2f" % [int(best) / 60, fmod(best, 60.0)] if best > 0 else "Завершите первый заезд, чтобы установить личный рекорд."
	var vehicle_health := clampf(float(state.get("vehicle_health", 100.0)), 0.0, 100.0)
	var player_health := clampf(float(state.get("player_health", 100.0)), 0.0, 100.0)
	var stock: String = str(state.get("ammo", "12 / 84"))
	garage_label.text = "Кузов %d%%   Здоровье %d%%   Патроны %s\nРемонт и пополнение доступны у голубой метки S на радаре." % [roundi(vehicle_health), roundi(player_health), stock]
	var available := bool(state.get("service_available", false))
	var price := maxi(0, int(state.get("service_cost", 150)))
	service_button.disabled = not available or money < price or wanted or price <= 0
	if wanted: service_button.text = "Сервис недоступен во время розыска"
	elif not available:
		var distance := maxf(0, float(state.get("service_distance", 0)))
		service_button.text = "Подъедьте к сервису и остановитесь" + (" · %d м" % roundi(distance) if distance > 5 else "")
	elif money < price: service_button.text = "Нужно $%d для обслуживания" % price
	elif price <= 0: service_button.text = "Автомобиль исправен · припасы полные"
	else: service_button.text = "Ремонт и пополнение — $%d" % price


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("back"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()


func _job(title_text: String, description: String, action: String, kind: String) -> Button:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	content.add_child(row)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 4)
	row.add_child(copy)
	copy.add_child(_label(title_text, 21, TEXT))
	copy.add_child(_label(description, 14, MUTED))
	var button := _button(action, ROUTE)
	button.custom_minimum_size.x = 190
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect(func(): contract_requested.emit(kind))
	row.add_child(button)
	return button


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 42
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_focus_color", TEXT)
	button.add_theme_color_override("font_disabled_color", Color("71848d"))
	var normal := _style(PANEL)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 9
	normal.content_margin_bottom = 9
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("314753")
	button.add_theme_stylebox_override("hover", hover)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("40545e")
	button.add_theme_stylebox_override("pressed", pressed)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color("16252d")
	button.add_theme_stylebox_override("disabled", disabled)
	var focus := _style(Color.TRANSPARENT)
	focus.set_border_width_all(2)
	focus.border_color = accent
	button.add_theme_stylebox_override("focus", focus)
	return button


func _separator() -> void:
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 5)
	var style := StyleBoxLine.new()
	style.color = Color("344953")
	style.thickness = 1
	line.add_theme_stylebox_override("separator", style)
	content.add_child(line)


func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	return style
