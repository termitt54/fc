class_name WeRangeField
extends VBoxContainer
## Labeled integer range slider.


signal value_changed(value: int)

@export var label: String = "Значение":
	set(v):
		label = v
		if _label != null:
			_label.text = label

@export var min_value: int = 0:
	set(v):
		min_value = v
		if _slider != null:
			_slider.min_value = min_value
			value = value

@export var max_value: int = 100:
	set(v):
		max_value = v
		if _slider != null:
			_slider.max_value = max_value
			value = value

@export var step: int = 1:
	set(v):
		step = maxi(v, 1)
		if _slider != null:
			_slider.step = step

@export var value: int = 0:
	set(v):
		value = clampi(v, min_value, max_value)
		if _slider != null and int(_slider.value) != value:
			_slider.set_value_no_signal(value)
		_refresh_value_label()

var editable: bool = true:
	set(v):
		editable = v
		if _slider != null:
			_slider.editable = editable
			_slider.modulate.a = 1.0 if editable else 0.55

## Optional [{min, max, label}, ...] shown under the slider.
var grades: Array = []:
	set(v):
		grades = v
		_rebuild_grade_row()
		_refresh_value_label()

@onready var _label: Label = %Label
@onready var _value_label: Label = %ValueLabel
@onready var _slider: HSlider = %Slider
@onready var _min_label: Label = %MinLabel
@onready var _max_label: Label = %MaxLabel
@onready var _ends: HBoxContainer = $Ends

var _grade_row: HBoxContainer
var _grade_chips: Array = []


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_label.add_theme_font_size_override("font_size", 12)
	_value_label.add_theme_color_override("font_color", WeTokens.ACCENT)
	_value_label.add_theme_font_size_override("font_size", 16)
	_min_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_max_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_min_label.add_theme_font_size_override("font_size", 11)
	_max_label.add_theme_font_size_override("font_size", 11)

	_slider.min_value = min_value
	_slider.max_value = max_value
	_slider.step = step
	_slider.value = value
	_slider.editable = editable
	_slider.value_changed.connect(_on_slider_changed)
	_style_slider()
	_min_label.text = str(min_value)
	_max_label.text = str(max_value)
	_rebuild_grade_row()
	_refresh_value_label()


func _on_slider_changed(v: float) -> void:
	value = int(v)
	value_changed.emit(value)


func _refresh_value_label() -> void:
	if _value_label == null:
		return
	var grade := _grade_label_for(value)
	if grade.is_empty():
		_value_label.text = str(value)
	else:
		_value_label.text = "%d · %s" % [value, grade]
	_highlight_grade_chips()


func _grade_label_for(v: int) -> String:
	for band in grades:
		if typeof(band) != TYPE_DICTIONARY:
			continue
		if v >= int(band.get("min", 0)) and v <= int(band.get("max", 0)):
			return str(band.get("label", ""))
	return ""


func _rebuild_grade_row() -> void:
	if _slider == null:
		return
	if _grade_row != null and is_instance_valid(_grade_row):
		remove_child(_grade_row)
		_grade_row.free()
		_grade_row = null
	_grade_chips.clear()
	if grades.is_empty():
		if _ends != null:
			_ends.visible = true
		return
	if _ends != null:
		_ends.visible = false

	_grade_row = HBoxContainer.new()
	_grade_row.add_theme_constant_override("separation", 4)
	_grade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grade_row)

	var span := float(maxi(1, max_value - min_value))
	for band in grades:
		if typeof(band) != TYPE_DICTIONARY:
			continue
		var lo := clampi(int(band.get("min", min_value)), min_value, max_value)
		var hi := clampi(int(band.get("max", max_value)), min_value, max_value)
		var width := maxf(1.0, float(hi - lo + 1) / span)
		var chip := Label.new()
		chip.text = str(band.get("short", band.get("label", "")))
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chip.size_flags_stretch_ratio = width
		chip.add_theme_font_size_override("font_size", 10)
		chip.clip_text = true
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = "%s: %d–%d" % [str(band.get("label", "")), lo, hi]
		chip.set_meta("min", lo)
		chip.set_meta("max", hi)
		_grade_row.add_child(chip)
		_grade_chips.append(chip)
	_highlight_grade_chips()


func _highlight_grade_chips() -> void:
	for chip in _grade_chips:
		if not is_instance_valid(chip):
			continue
		var active := value >= int(chip.get_meta("min", 0)) and value <= int(chip.get_meta("max", 0))
		chip.add_theme_color_override("font_color", WeTokens.ACCENT if active else WeTokens.TEXT_DIM)


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
