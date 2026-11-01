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


func _ready() -> void:
	layer = 2
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	radar.configure(city_map, player_body)
	var status_panel := Panel.new()
	status_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	status_panel.offset_left = -232
	status_panel.offset_right = -24
	status_panel.offset_top = 24
	status_panel.offset_bottom = 151
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(status_panel)
	cash_label = _label(status_panel, Vector2(18, 7), 30, Color("a4d3b2"))
	wanted_label = _label(status_panel, Vector2(18, 47), 30, Color("e9c5a1"))
	clock_label = _label(status_panel, Vector2(18, 94), 16, Color("becbc8"))
	var detail_panel := Panel.new()
	root.add_child(detail_panel)
	detail_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	detail_panel.offset_left = -264
	detail_panel.offset_right = -24
	detail_panel.offset_top = -106
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
	hint_label = _label(root, Vector2.ZERO, 16, Color("e1e6de"))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.offset_left = 256
	hint_label.offset_top = -53
	reticle = _label(root, Vector2.ZERO, 20, Color(1, 1, 1, 0.8))
	reticle.text = "+"
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -7
	reticle.offset_top = -12
	_refresh_status()


func _process(_delta: float) -> void:
	_refresh_status()
	if is_instance_valid(player_body): radar.queue_redraw()


func _refresh_status() -> void:
	cash_label.text = "$%d" % maxi(cash, 0)
	var stars := clampi(wanted_level, 0, 3)
	wanted_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)
	clock_label.text = clock_text + "  /  POLYGON CITY"
	detail_label.text = "%03d км/ч" % roundi(speed) if driving else (ammo_text + "   ПАТР." if weapon_drawn else "ПЕШКОМ")
	boost_bar.value = boost_value if driving else health / 100.0
	hint_label.text = hint
	reticle.visible = not driving and weapon_drawn


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
