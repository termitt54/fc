class_name WeButton
extends Button
## Custom editor button with intentional variants.


enum Kind { PRIMARY, GHOST, DANGER, LINK }

@export var kind: Kind = Kind.GHOST:
	set(value):
		kind = value
		if is_node_ready():
			_apply_kind()


func _ready() -> void:
	if focus_mode == Control.FOCUS_NONE:
		focus_mode = Control.FOCUS_ALL
	if kind != Kind.LINK:
		custom_minimum_size.y = maxf(custom_minimum_size.y, 34.0)
	_apply_kind()


func _apply_kind() -> void:
	match kind:
		Kind.PRIMARY:
			_apply_styles(
				Color(0.22, 0.72, 0.62, 1.0),
				Color(0.45, 0.92, 0.8, 0.35),
				Color(0.28, 0.8, 0.7, 1.0),
				Color(0.55, 0.95, 0.85, 0.5),
				Color(0.18, 0.58, 0.5, 1.0),
				Color(0.35, 0.8, 0.7, 0.4),
				Color(0.04, 0.12, 0.12, 1.0),
				WeTokens.TEXT_DIM,
				true
			)
		Kind.DANGER:
			_apply_styles(
				WeTokens.DANGER_SOFT,
				Color(0.95, 0.45, 0.48, 0.35),
				Color(0.95, 0.42, 0.45, 0.28),
				Color(0.95, 0.5, 0.52, 0.5),
				Color(0.95, 0.42, 0.45, 0.14),
				Color(0.95, 0.45, 0.48, 0.4),
				Color(1.0, 0.78, 0.78, 1.0),
				WeTokens.TEXT_DIM,
				false
			)
		Kind.LINK:
			_apply_link_styles()
		_:
			_apply_styles(
				Color(1, 1, 1, 0.05),
				WeTokens.BORDER_STRONG,
				Color(1, 1, 1, 0.1),
				Color(0.55, 0.78, 0.82, 0.35),
				Color(1, 1, 1, 0.04),
				WeTokens.BORDER_FOCUS,
				WeTokens.TEXT,
				WeTokens.TEXT_DIM,
				false
			)


func _apply_link_styles() -> void:
	flat = true
	var kept_min := custom_minimum_size
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 4
	empty.content_margin_top = 2
	empty.content_margin_bottom = 2
	add_theme_stylebox_override("normal", empty)
	add_theme_stylebox_override("hover", empty)
	add_theme_stylebox_override("pressed", empty)
	add_theme_stylebox_override("focus", empty)
	add_theme_stylebox_override("disabled", empty)
	add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	add_theme_color_override("font_hover_color", WeTokens.ACCENT)
	add_theme_color_override("font_pressed_color", WeTokens.ACCENT_DIM)
	add_theme_color_override("font_focus_color", WeTokens.ACCENT)
	add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
	add_theme_font_size_override("font_size", 13)
	# Keep ellipsis/clip working for long link labels (e.g. league name).
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if kept_min != Vector2.ZERO:
		custom_minimum_size = kept_min


func _apply_styles(
	normal_bg: Color,
	normal_border: Color,
	hover_bg: Color,
	hover_border: Color,
	pressed_bg: Color,
	pressed_border: Color,
	font_color: Color,
	disabled_font: Color,
	with_shadow: bool
) -> void:
	add_theme_stylebox_override("normal", _box(normal_bg, normal_border, with_shadow))
	add_theme_stylebox_override("hover", _box(hover_bg, hover_border, with_shadow))
	add_theme_stylebox_override("pressed", _box(pressed_bg, pressed_border, false))
	add_theme_stylebox_override("focus", _box(hover_bg, hover_border, with_shadow))
	add_theme_stylebox_override("disabled", _box(Color(1, 1, 1, 0.03), Color(1, 1, 1, 0.05), false))
	add_theme_color_override("font_color", font_color)
	add_theme_color_override(
		"font_hover_color",
		Color(0.02, 0.1, 0.1, 1.0) if kind == Kind.PRIMARY else Color(1, 1, 1, 1)
	)
	add_theme_color_override("font_pressed_color", font_color.darkened(0.06))
	add_theme_color_override("font_disabled_color", disabled_font)
	add_theme_font_size_override("font_size", 13)


func _box(bg: Color, border: Color, with_shadow: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(WeTokens.RADIUS_SM)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	if with_shadow:
		box.shadow_color = Color(0.08, 0.35, 0.32, 0.35)
		box.shadow_size = 6
		box.shadow_offset = Vector2(0, 2)
	return WeTokens.polish_style(box)
