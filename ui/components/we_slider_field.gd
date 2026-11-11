class_name WeSliderField
extends VBoxContainer
## Labeled float slider with optional percent formatting.


signal value_changed(value: float)

@export var label: String = "Значение":
	set(v):
		label = v
		if _label != null:
			_label.text = label

@export var hint: String = "":
	set(v):
		hint = v
		_refresh_hint()

@export var min_value: float = 0.0:
	set(v):
		min_value = v
		if _slider != null:
			_slider.min_value = min_value
			value = value
			_refresh_ends()

@export var max_value: float = 1.0:
	set(v):
		max_value = v
		if _slider != null:
			_slider.max_value = max_value
			value = value
			_refresh_ends()

@export var step: float = 0.01:
	set(v):
		step = maxf(v, 0.0001)
		if _slider != null:
			_slider.step = step

@export var decimals: int = 2
@export var percent: bool = false
@export var suffix: String = ""
var display_scale := 1.0

@export var value: float = 0.0:
	set(v):
		value = clampf(v, min_value, max_value)
		if _slider != null and not is_equal_approx(_slider.value, value):
			_slider.set_value_no_signal(value)
		_refresh_value_label()

var default_value: float = 0.0
var _number_edit: LineEdit
var _editing := false

@onready var _label: Label = %Label
@onready var _value_label: Label = %ValueLabel
@onready var _hint_label: Label = %HintLabel
@onready var _slider: HSlider = %Slider
@onready var _min_label: Label = %MinLabel
@onready var _max_label: Label = %MaxLabel


func configure(spec: Dictionary, current: float) -> void:
	label = str(spec.get("label", label))
	hint = str(spec.get("hint", ""))
	min_value = float(spec.get("min", 0.0))
	max_value = float(spec.get("max", 1.0))
	step = float(spec.get("step", 0.01))
	decimals = int(spec.get("decimals", 2))
	percent = bool(spec.get("percent", false))
	suffix = str(spec.get("suffix", ""))
	display_scale = float(spec.get("display_scale", 1.0))
	default_value = float(spec.get("default", current))
	value = current


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_label.add_theme_font_size_override("font_size", 12)
	_value_label.add_theme_font_size_override("font_size", 15)
	_value_label.custom_minimum_size.y = 30
	_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_value_label.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_value_label.tooltip_text = "Нажмите, чтобы ввести число вручную"
	_value_label.gui_input.connect(_on_value_input)
	_number_edit = LineEdit.new()
	_number_edit.name = "NumberEdit"
	_number_edit.custom_minimum_size = Vector2(104, 30)
	_number_edit.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_number_edit.select_all_on_focus = true
	_number_edit.visible = false
	_number_edit.add_theme_font_size_override("font_size", 14)
	_number_edit.add_theme_color_override("font_color", WeTokens.TEXT)
	_number_edit.add_theme_stylebox_override("normal", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 6))
	_number_edit.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER_FOCUS, WeTokens.RADIUS_SM, 6))
	_value_label.get_parent().add_child(_number_edit)
	_number_edit.text_submitted.connect(func(_text: String): _finish_edit())
	_number_edit.focus_exited.connect(_finish_edit)
	_number_edit.gui_input.connect(_on_edit_input)
	_hint_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_hint_label.add_theme_font_size_override("font_size", 11)
	_min_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_max_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_min_label.add_theme_font_size_override("font_size", 11)
	_max_label.add_theme_font_size_override("font_size", 11)

	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = step
	_slider.set_value_no_signal(value)
	_slider.scrollable = false
	_slider.value_changed.connect(_on_slider_changed)
	_style_slider()
	_refresh_hint()
	_refresh_ends()
	_refresh_value_label()


func _on_slider_changed(v: float) -> void:
	value = v
	value_changed.emit(value)


## Input uses the displayed units: 50 means 50%, including display_scale.
func apply_text(text: String) -> bool:
	var cleaned := text.strip_edges().replace(",", ".").replace("%", "")
	if not suffix.is_empty(): cleaned = cleaned.trim_suffix(suffix).strip_edges()
	if not cleaned.is_valid_float(): return false
	var entered := float(cleaned)
	if not is_finite(entered) or display_scale <= 0.0: return false
	var raw := entered / display_scale / (100.0 if percent else 1.0)
	value = clampf(snappedf(raw, step), min_value, max_value)
	value_changed.emit(value)
	return true


func _on_value_input(event: InputEvent) -> void:
	if not _slider.editable: return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_editing = true
		_number_edit.text = formatted(value).replace("%", "").trim_suffix(suffix).strip_edges() if not suffix.is_empty() else formatted(value).replace("%", "")
		_value_label.visible = false
		_number_edit.visible = true
		_number_edit.grab_focus()
		_number_edit.select_all()
		get_viewport().set_input_as_handled()


func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_editing = false
		_number_edit.visible = false
		_value_label.visible = true
		get_viewport().set_input_as_handled()


func _finish_edit() -> void:
	if not _editing: return
	_editing = false
	apply_text(_number_edit.text)
	_number_edit.visible = false
	_value_label.visible = true


func set_enabled(enabled: bool) -> void:
	if _editing: _finish_edit()
	_slider.editable = enabled
	_value_label.mouse_default_cursor_shape = Control.CURSOR_IBEAM if enabled else Control.CURSOR_ARROW
	modulate.a = 1.0 if enabled else 0.4


func formatted(v: float) -> String:
	v *= display_scale
	if percent:
		var shown := maxi(decimals - 2, 0)
		return ("%." + str(shown) + "f%%") % (v * 100.0)
	var text := ("%." + str(decimals) + "f") % v
	if suffix.is_empty():
		return text
	return text + suffix


func _refresh_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.text = hint
	_hint_label.visible = not hint.is_empty()
	tooltip_text = hint


func _refresh_ends() -> void:
	if _min_label == null:
		return
	_min_label.text = formatted(min_value)
	_max_label.text = formatted(max_value)


func _refresh_value_label() -> void:
	if _value_label == null:
		return
	_value_label.text = formatted(value)
	var drifted := absf(value - default_value) >= step * 0.49
	_value_label.add_theme_color_override("font_color", WeTokens.ACCENT if drifted else WeTokens.TEXT)


func _style_slider() -> void:
	var track := WeTokens.polish_style(StyleBoxFlat.new())
	track.bg_color = Color(1, 1, 1, 0.08)
	track.set_corner_radius_all(999)
	track.content_margin_top = 4
	track.content_margin_bottom = 4

	var fill := WeTokens.polish_style(StyleBoxFlat.new())
	fill.bg_color = WeTokens.ACCENT
	fill.set_corner_radius_all(999)

	var grabber := WeTokens.polish_style(StyleBoxFlat.new())
	grabber.bg_color = WeTokens.TEXT
	grabber.set_corner_radius_all(999)
	grabber.set_content_margin_all(0)
	grabber.content_margin_left = 7
	grabber.content_margin_right = 7
	grabber.content_margin_top = 7
	grabber.content_margin_bottom = 7
	grabber.shadow_color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35)
	grabber.shadow_size = 4

	var grabber_hl := grabber.duplicate()
	grabber_hl.bg_color = WeTokens.ACCENT

	_slider.add_theme_stylebox_override("slider", track)
	_slider.add_theme_stylebox_override("grabber_area", fill)
	_slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	_slider.add_theme_stylebox_override("grabber", grabber)
	_slider.add_theme_stylebox_override("grabber_highlight", grabber_hl)
	_slider.add_theme_constant_override("center_grabber", 1)
