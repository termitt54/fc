class_name CaHistoryChart
extends Control
## CA by season for the player card. Points are {season, ca}.


var points: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	call_deferred("_fill_parent")


func _fill_parent() -> void:
	var parent := get_parent() as ScrollContainer
	if parent == null:
		return
	if not parent.resized.is_connected(_fill_parent):
		parent.resized.connect(_fill_parent)
	var height := maxf(180.0, parent.size.y)
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size.y = height


func set_points(rows: Array) -> void:
	points = rows
	queue_redraw()


func _draw() -> void:
	if points.is_empty() or size.x < 48.0 or size.y < 48.0:
		return

	var font := WeTokens.font()
	var value_font := WeTokens.font_semibold()
	if font == null:
		font = ThemeDB.fallback_font
	if value_font == null:
		value_font = font

	var plot := Rect2(34.0, 18.0, size.x - 46.0, size.y - 42.0)
	if plot.size.x < 8.0 or plot.size.y < 8.0:
		return

	var lo := int(_row(0).get("ca", 0))
	var hi := lo
	for i in points.size():
		var ca := int(_row(i).get("ca", 0))
		lo = mini(lo, ca)
		hi = maxi(hi, ca)
	if hi - lo < 8:
		var mid := int(round((float(lo) + float(hi)) * 0.5))
		lo = mid - 4
		hi = mid + 4
	lo = maxi(0, lo - 2)
	hi = mini(100, hi + 2)
	if hi <= lo:
		hi = mini(100, lo + 8)
	var span := float(hi - lo)

	var grid := Color(1, 1, 1, 0.07)
	for step in 3:
		var gy := plot.position.y + plot.size.y * float(step) / 2.0
		draw_line(Vector2(plot.position.x, gy), Vector2(plot.end.x, gy), grid, 1.0)
		var grid_ca := hi - int(round(span * float(step) / 2.0))
		_draw_label(
			font, str(grid_ca),
			Vector2(0.0, gy - 6.0), 28.0, 10, WeTokens.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_RIGHT
		)

	var coords: PackedVector2Array = PackedVector2Array()
	for i in points.size():
		var t := 0.5 if points.size() == 1 else float(i) / float(points.size() - 1)
		var ca := float(int(_row(i).get("ca", 0)))
		var x := plot.position.x + plot.size.x * t
		var y := plot.position.y + plot.size.y * (1.0 - (ca - float(lo)) / span)
		coords.append(Vector2(x, y))

	if coords.size() >= 2:
		var fill := PackedVector2Array()
		fill.append(Vector2(coords[0].x, plot.end.y))
		for point in coords:
			fill.append(point)
		fill.append(Vector2(coords[coords.size() - 1].x, plot.end.y))
		draw_colored_polygon(fill, Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.14))
		draw_polyline(coords, WeTokens.ACCENT, 2.0, true)

	var label_step := 1
	var gap := plot.size.x / float(maxi(points.size() - 1, 1))
	while label_step < points.size() and gap * float(label_step) < 26.0:
		label_step += 1

	for i in coords.size():
		var point := coords[i]
		var ca := int(_row(i).get("ca", 0))
		var rising := i == 0 or ca >= int(_row(i - 1).get("ca", ca))
		var dot := WeTokens.ACCENT if i == 0 else (WeTokens.SUCCESS if rising else WeTokens.DANGER)
		draw_circle(point, 4.5, WeTokens.BG_DEEP)
		draw_circle(point, 3.0, dot)
		var show := i == 0 or i == coords.size() - 1 or i % label_step == 0
		if not show:
			continue
		_draw_label(
			value_font, str(ca),
			Vector2(point.x - 16.0, point.y - 16.0), 32.0, 11, WeTokens.TEXT,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_label(
			font, str(int(_row(i).get("season", 0))),
			Vector2(point.x - 16.0, plot.end.y + 6.0), 32.0, 10, WeTokens.TEXT_DIM,
			HORIZONTAL_ALIGNMENT_CENTER
		)


func _row(index: int) -> Dictionary:
	var raw: Variant = points[index]
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


func _draw_label(
	font: Font,
	text: String,
	origin: Vector2,
	width: float,
	font_size: int,
	color: Color,
	alignment: HorizontalAlignment
) -> void:
	if font == null:
		return
	draw_string(font, origin + Vector2(0.0, font_size), text, alignment, width, font_size, color)
