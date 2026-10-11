class_name WeTextField
extends VBoxContainer
## Labeled text field with custom chrome.


signal text_changed(new_text: String)
signal text_submitted(new_text: String)

@export var label: String = "Поле":
	set(value):
		label = value
		if _label != null:
			_label.text = label

@export var placeholder: String = "":
	set(value):
		placeholder = value
		if _input != null:
			_input.placeholder_text = placeholder

@export var max_length: int = 0:
	set(value):
		max_length = value
		if _input != null:
			_input.max_length = max_length

@export var compact: bool = false:
	set(value):
		compact = value
		if is_node_ready():
			_apply_density()

var editable: bool = true:
	set(value):
		editable = value
		if _input != null:
			_input.editable = value
			_refresh_chrome()

var _text: String = ""

var text: String:
	get:
		return _input.text if _input != null else _text
	set(value):
		_text = value
		if _input != null:
			_input.text = value

var caret_column: int:
	get:
		return _input.caret_column if _input != null else 0
	set(value):
		if _input != null:
			_input.caret_column = value

@onready var _label: Label = %Label
@onready var _chrome: PanelContainer = %Chrome
@onready var _input: LineEdit = %Input


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_input.placeholder_text = placeholder
	_input.max_length = max_length
	_input.editable = editable
	_input.text = _text
	_input.text_changed.connect(_on_input_text_changed)
	_input.text_submitted.connect(func(t: String): text_submitted.emit(t))
	_input.focus_entered.connect(_refresh_chrome)
	_input.focus_exited.connect(_refresh_chrome)
	_input.mouse_entered.connect(_refresh_chrome)
	_input.mouse_exited.connect(_refresh_chrome)
	_apply_density()
	_apply_input_theme()
	_refresh_chrome()


func _on_input_text_changed(new_text: String) -> void:
	_text = new_text
	text_changed.emit(new_text)


func _apply_density() -> void:
	add_theme_constant_override("separation", 3 if compact else 6)
	_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	_chrome.custom_minimum_size.y = 32 if compact else 40


func focus_field() -> void:
	_input.grab_focus()


func clear() -> void:
	_text = ""
	if _input != null:
		_input.clear()


func _apply_input_theme() -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 2
	empty.content_margin_right = 2
	_input.add_theme_stylebox_override("normal", empty)
	_input.add_theme_stylebox_override("focus", empty)
	_input.add_theme_stylebox_override("read_only", empty)
	_input.add_theme_color_override("font_color", WeTokens.TEXT)
	_input.add_theme_color_override("font_placeholder_color", WeTokens.TEXT_DIM)
	_input.add_theme_color_override("caret_color", WeTokens.ACCENT)
	_input.add_theme_font_size_override("font_size", 12 if compact else 14)


func _refresh_chrome() -> void:
	var focused := _input.has_focus()
	var hovered := _chrome.get_global_rect().has_point(get_global_mouse_position())
	var bg := WeTokens.INSET
	var border := WeTokens.BORDER
	if not editable:
		bg = Color(0, 0, 0, 0.18)
		border = Color(1, 1, 1, 0.04)
	elif focused:
		border = WeTokens.BORDER_FOCUS
	elif hovered:
		border = WeTokens.BORDER_STRONG
	var pad := 8 if compact else 10
	_chrome.add_theme_stylebox_override("panel", WeTokens.panel(bg, border, WeTokens.RADIUS_SM, pad))
