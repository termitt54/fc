class_name WeModal
extends Control
## Fullscreen dim + custom card. No OS window chrome.


signal closed
signal confirmed
signal cancelled

@export var card_width: float = 520.0
@export var card_height: float = 0.0
@export var close_on_dim: bool = true

@onready var _dim: ColorRect = %Dim
@onready var _card: PanelContainer = %Card
@onready var _title: Label = %Title
@onready var _close_button: Button = %CloseButton
@onready var _body: VBoxContainer = %Body
@onready var _error: Label = %ErrorLabel
@onready var _cancel_button: WeButton = %CancelButton
@onready var _confirm_button: WeButton = %ConfirmButton


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	_dim.color = Color(0.04, 0.07, 0.1, 0.7)
	_apply_card_size()
	_card.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE_RAISED, WeTokens.BORDER_STRONG, WeTokens.RADIUS_LG, 0, 22.0)
	)

	_title.add_theme_color_override("font_color", WeTokens.TEXT)
	_title.add_theme_font_size_override("font_size", 20)
	_error.add_theme_color_override("font_color", WeTokens.DANGER)
	_error.visible = false

	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.flat = true
	_close_button.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_close_button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	_close_button.pressed.connect(_on_cancel)

	_cancel_button.kind = WeButton.Kind.GHOST
	_confirm_button.kind = WeButton.Kind.PRIMARY
	_cancel_button.focus_mode = Control.FOCUS_ALL
	_confirm_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.pressed.connect(_on_cancel)
	_confirm_button.pressed.connect(_on_confirm)
	_dim.gui_input.connect(_on_dim_input)


func get_body() -> VBoxContainer:
	return _body


func set_card_size(width: float, height: float = 0.0) -> void:
	card_width = width
	card_height = height
	_apply_card_size()


func set_body_separation(value: int) -> void:
	if _body != null:
		_body.add_theme_constant_override("separation", value)


func _apply_card_size() -> void:
	if _card == null:
		return
	_card.custom_minimum_size = Vector2(card_width, card_height)
	if _body == null:
		return
	if card_height > 0.0:
		_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var host := _body.get_parent()
		if host is Container:
			(host as Container).size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


func set_title(text: String) -> void:
	_title.text = text


func set_confirm_text(text: String) -> void:
	_confirm_button.text = text


func set_cancel_text(text: String) -> void:
	_cancel_button.text = text


func set_busy(busy: bool) -> void:
	_cancel_button.disabled = busy
	_confirm_button.disabled = busy
	_close_button.disabled = busy


func show_error(message: String) -> void:
	_error.text = message
	_error.visible = not message.is_empty()


func clear_error() -> void:
	show_error("")


func open() -> void:
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	offset_left = 0
	offset_top = 0
	offset_right = 0
	offset_bottom = 0
	visible = true
	move_to_front()


func popup_centered() -> void:
	open()


func close() -> void:
	visible = false
	top_level = false
	closed.emit()


func hide_modal() -> void:
	close()


func _on_dim_input(event: InputEvent) -> void:
	if not close_on_dim:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_cancel()


func _on_cancel() -> void:
	cancelled.emit()


func _on_confirm() -> void:
	confirmed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
