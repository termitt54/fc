class_name WeNumberField
extends VBoxContainer
## Custom numeric stepper — no default SpinBox chrome.


signal value_changed(value: int)

@export var label: String = "Число":
	set(value):
		label = value
		if _label != null:
			_label.text = label

@export var min_value: int = 0
@export var max_value: int = 100
@export var step: int = 1
@export var value: int = 0:
	set(v):
		value = clampi(v, min_value, max_value)
		if _input != null and str(value) != _input.text:
			_input.text = str(value)

@export var compact: bool = false:
	set(v):
		compact = v
		if is_node_ready():
			_apply_density()

var editable: bool = true:
	set(v):
		editable = v
		if _input != null:
			_input.editable = editable
			_minus.disabled = not editable
			_plus.disabled = not editable
			_refresh_chrome()

@onready var _label: Label = %Label
@onready var _chrome: PanelContainer = %Chrome
@onready var _minus: Button = %Minus
@onready var _plus: Button = %Plus
@onready var _input: LineEdit = %Input


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_input.text = str(value)
	_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_input.focus_mode = Control.FOCUS_CLICK
	_input.text_submitted.connect(_on_text_submitted)
	_input.focus_exited.connect(_commit_text)
	_input.focus_entered.connect(_refresh_chrome)
	_input.focus_exited.connect(_refresh_chrome)
	_minus.pressed.connect(func(): _set_value(value - step, true))
	_plus.pressed.connect(func(): _set_value(value + step, true))
	_apply_density()
	_style_step_button(_minus)
	_style_step_button(_plus)
	_apply_input_theme()
	_refresh_chrome()


func _apply_density() -> void:
	add_theme_constant_override("separation", 3 if compact else 6)
	_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	_chrome.custom_minimum_size.y = 32 if compact else 40
	if _minus != null:
		_style_step_button(_minus)
	if _plus != null:
		_style_step_button(_plus)


func _style_step_button(button: Button) -> void:
	var side := 28 if compact else 36
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(side, side)
	button.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.04), WeTokens.RADIUS_SM))
	button.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.08), WeTokens.RADIUS_SM))
	button.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.12), WeTokens.RADIUS_SM))
	button.add_theme_stylebox_override("disabled", WeTokens.fill(Color(1, 1, 1, 0.02), WeTokens.RADIUS_SM))
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
	button.add_theme_font_size_override("font_size", 14 if compact else 16)


func _apply_input_theme() -> void:
	var empty := StyleBoxEmpty.new()
	_input.add_theme_stylebox_override("normal", empty)
	_input.add_theme_stylebox_override("focus", empty)
	_input.add_theme_stylebox_override("read_only", empty)
	_input.add_theme_color_override("font_color", WeTokens.TEXT)
	_input.add_theme_color_override("caret_color", WeTokens.ACCENT)
	_input.add_theme_font_size_override("font_size", 12 if compact else 14)


func _refresh_chrome() -> void:
	var focused := _input.has_focus()
	var border := WeTokens.BORDER_FOCUS if focused else WeTokens.BORDER
	_chrome.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, border, WeTokens.RADIUS_SM, 4)
	)


func _set_value(v: int, emit_change: bool) -> void:
	var next: int = clampi(v, min_value, max_value)
	var changed := next != value
	value = next
	_input.text = str(value)
	if changed and emit_change:
		value_changed.emit(value)


func _on_text_submitted(_t: String) -> void:
	_commit_text()


func _commit_text() -> void:
	if _input.text.is_valid_int():
		_set_value(int(_input.text), true)
	else:
		_input.text = str(value)
