class_name WeSearchField
extends PanelContainer
## Custom search field with chrome, not a bare LineEdit.


signal text_changed(new_text: String)
signal text_submitted(new_text: String)

@export var placeholder: String = "Поиск…":
	set(value):
		placeholder = value
		if _input != null:
			_input.placeholder_text = placeholder

var editable: bool = true:
	set(value):
		editable = value
		if _input != null:
			_input.editable = value
			_refresh_chrome()

var text: String:
	get:
		return _input.text if _input != null else ""
	set(value):
		if _input != null:
			_input.text = value

@onready var _input: LineEdit = %Input


func _ready() -> void:
	custom_minimum_size.y = 34
	_input.placeholder_text = placeholder
	_input.editable = editable
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(func(t: String): text_submitted.emit(t))
	_input.clear_button_enabled = true
	_input.focus_entered.connect(_refresh_chrome)
	_input.focus_exited.connect(_refresh_chrome)
	_input.mouse_entered.connect(_refresh_chrome)
	_input.mouse_exited.connect(_refresh_chrome)
	_apply_input_theme()
	_refresh_chrome()


func clear() -> void:
	_input.clear()


func grab_search_focus() -> void:
	_input.grab_focus()


func _on_text_changed(new_text: String) -> void:
	text_changed.emit(new_text)


func _apply_input_theme() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	_input.add_theme_stylebox_override("normal", empty)
	_input.add_theme_stylebox_override("focus", empty)
	_input.add_theme_stylebox_override("read_only", empty)
	_input.add_theme_color_override("font_color", WeTokens.TEXT)
	_input.add_theme_color_override("font_placeholder_color", WeTokens.TEXT_DIM)
	_input.add_theme_color_override("caret_color", WeTokens.ACCENT)
	_input.add_theme_font_size_override("font_size", 13)


func _refresh_chrome() -> void:
	var focused := _input.has_focus()
	var hovered := get_global_rect().has_point(get_global_mouse_position())
	var bg := WeTokens.INSET
	var border := WeTokens.BORDER
	if not editable:
		bg = Color(0, 0, 0, 0.18)
		border = Color(1, 1, 1, 0.04)
	elif focused:
		border = WeTokens.BORDER_FOCUS
		bg = Color(0.04, 0.05, 0.07, 1.0)
	elif hovered:
		border = WeTokens.BORDER_STRONG
	add_theme_stylebox_override("panel", WeTokens.panel(bg, border, WeTokens.RADIUS_SM, 8))
