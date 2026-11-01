extends Control

var subject := Vector3.ZERO
var heading := 0.0
var destination := Vector3.ZERO
var police_positions: Array[Vector3] = []
const SCALE := 0.34
const CENTER := Vector2(100, 100)


func _draw() -> void:
	draw_style_box(_background(), Rect2(0, 0, 200, 200))
	var origin := Vector2(subject.x, subject.z)
	var coast := 325 * SCALE - origin.x * SCALE + 100
	draw_rect(Rect2(Vector2(coast, 0), Vector2(200, 200)), Color("336c77"))
	for x in [-300, -180, -60, 60, 180]:
		var screen_x: float = (x - origin.x) * SCALE + 100
		draw_line(Vector2(screen_x, 0), Vector2(screen_x, 200), Color("758088"), 5)
	for z in [-300, -180, -60, 60, 180, 300]:
		var screen_z: float = (z - origin.y) * SCALE + 100
		draw_line(Vector2(0, screen_z), Vector2(200, screen_z), Color("758088"), 5)
	var mark := (Vector2(destination.x, destination.z) - origin) * SCALE + CENTER
	mark = mark.clamp(Vector2(8, 8), Vector2(192, 192))
	draw_circle(mark, 5, Color("f5a1cc"))
	for point in police_positions:
		var dot := (Vector2(point.x, point.z) - origin) * SCALE + CENTER
		draw_circle(dot, 4, Color("83c5f4"))
	var arrow := PackedVector2Array([Vector2(0, -9), Vector2(-6, 7), Vector2(0, 4), Vector2(6, 7)])
	for i in arrow.size(): arrow[i] = arrow[i].rotated(heading) + CENTER
	draw_colored_polygon(arrow, Color("f7edd8"))
	draw_string(ThemeDB.fallback_font, Vector2(12, 20), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("dce2db"))


func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("273c43")
	style.border_color = Color("c2cec8")
	style.set_border_width_all(2)
	return style
