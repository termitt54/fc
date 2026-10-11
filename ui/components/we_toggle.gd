class_name WeToggle
extends PanelContainer
## Custom on/off toggle with label.


signal toggled(is_on: bool)

@export var label: String = "Включено":
	set(value):
		label = value
		if _label != null:
			_label.text = label

@export var is_on: bool = true:
	set(value):
		is_on = value
		_refresh()

var disabled: bool = false:
	set(value):
		disabled = value
		mouse_default_cursor_shape = (
			Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
		)
		_refresh()

@onready var _label: Label = %Label
@onready var _track: PanelContainer = %Track
@onready var _knob: PanelContainer = %Knob


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_label.add_theme_font_size_override("font_size", 14)
	add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 12)
	)
	_refresh()


func _on_gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			is_on = not is_on
			toggled.emit(is_on)
			accept_event()


func _refresh() -> void:
	if _track == null:
		return
	var track_bg := WeTokens.ACCENT_SOFT if is_on else Color(1, 1, 1, 0.06)
	var track_border := Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35) if is_on else WeTokens.BORDER
	_track.add_theme_stylebox_override("panel", WeTokens.panel(track_bg, track_border, 999, 2))
	_knob.add_theme_stylebox_override(
		"panel",
		WeTokens.fill(WeTokens.ACCENT if is_on else WeTokens.TEXT_MUTED, 999)
	)
	# Move knob via alignment in HBox: left spacer trick
	var box: HBoxContainer = _track.get_node("HBox")
	var left: Control = box.get_node("Left")
	var right: Control = box.get_node("Right")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL if is_on else Control.SIZE_SHRINK_BEGIN
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL if not is_on else Control.SIZE_SHRINK_BEGIN
	left.visible = is_on
	right.visible = not is_on
	modulate.a = 0.55 if disabled else 1.0
