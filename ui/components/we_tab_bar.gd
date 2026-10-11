class_name WeTabBar
extends HBoxContainer
## Custom tab strip without TabContainer chrome.


signal tab_selected(index: int)

var _tabs: PackedStringArray = PackedStringArray()
var _current: int = 0
var _buttons: Array[Button] = []


func _ready() -> void:
	add_theme_constant_override("separation", 8)


func set_tabs(titles: PackedStringArray) -> void:
	_tabs = titles
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	for i in _tabs.size():
		var button := Button.new()
		button.text = _tabs[i]
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(0, 36)
		button.pressed.connect(_on_pressed.bind(i))
		add_child(button)
		_buttons.append(button)
	select(_current, false)


func select(index: int, emit_signal: bool = true) -> void:
	if _buttons.is_empty():
		_current = index
		return
	_current = clampi(index, 0, _buttons.size() - 1)
	for i in _buttons.size():
		_style_button(_buttons[i], i == _current)
	if emit_signal:
		tab_selected.emit(_current)


func get_current() -> int:
	return _current


func _on_pressed(index: int) -> void:
	select(index, true)


func _style_button(button: Button, selected: bool) -> void:
	var normal := _tab_box(
		WeTokens.ACCENT_SOFT if selected else Color(1, 1, 1, 0.03),
		Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.4) if selected else Color(0, 0, 0, 0)
	)
	var hover := _tab_box(Color(1, 1, 1, 0.08), WeTokens.BORDER)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", WeTokens.ACCENT if selected else WeTokens.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	button.add_theme_font_size_override("font_size", 14)


func _tab_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	box.set_corner_radius_all(WeTokens.RADIUS_SM)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 9
	box.content_margin_bottom = 9
	return WeTokens.polish_style(box)
