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

@export var value: float = 0.0:
	set(v):
		value = clampf(v, min_value, max_value)
		if _slider != null and not is_equal_approx(_slider.value, value):
			_slider.set_value_no_signal(value)
		_refresh_value_label()

var default_value: float = 0.0

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
	default_value = float(spec.get("default", current))
	value = current


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_label.add_theme_font_size_override("font_size", 12)
	_value_label.add_theme_font_size_override("font_size", 15)
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


func formatted(v: float) -> String:
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
