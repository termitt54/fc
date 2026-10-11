class_name WeBadge
extends Label
## Compact count / status pill.


func _ready() -> void:
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 11)
	add_theme_color_override("font_color", WeTokens.ACCENT)
	_refresh()


func set_count(value: int) -> void:
	text = str(value)
	_refresh()


func _refresh() -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = WeTokens.ACCENT_SOFT
	box.border_color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35)
	box.set_border_width_all(1)
	box.set_corner_radius_all(999)
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	add_theme_stylebox_override("normal", WeTokens.polish_style(box))
