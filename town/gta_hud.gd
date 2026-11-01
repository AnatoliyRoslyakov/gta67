extends CanvasLayer

const CityRadar = preload("res://town/city_radar.gd")
var city_map: Node3D
var player_body: VehicleBody3D
var cash := 500
var wanted_level := 0
var radar: Control
var cash_label: Label
var wanted_label: Label


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
	status_panel.offset_bottom = 120
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_panel.add_theme_stylebox_override("panel", _panel_style())
	root.add_child(status_panel)
	cash_label = _label(status_panel, Vector2(18, 7), 30, Color("a4d3b2"))
	wanted_label = _label(status_panel, Vector2(18, 47), 30, Color("e9c5a1"))
	_refresh_status()


func _process(_delta: float) -> void:
	_refresh_status()
	if is_instance_valid(player_body): radar.queue_redraw()


func _refresh_status() -> void:
	cash_label.text = "$%d" % maxi(cash, 0)
	var stars := clampi(wanted_level, 0, 3)
	wanted_label.text = "★".repeat(stars) + "☆".repeat(3 - stars)


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
