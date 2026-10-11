class_name WeDistributionTable
extends VBoxContainer
## Compact percent distribution editor with hundredths precision.


signal weights_changed(total: float, remaining: float)
signal validity_changed(is_valid: bool)

const STEP := 0.1
const EPS := 0.001

const TIER_COLORS := [
	Color(0.98, 0.82, 0.38, 1.0),
	Color(0.72, 0.9, 0.55, 1.0),
	Color(0.38, 0.86, 0.74, 1.0),
	Color(0.4, 0.74, 0.88, 1.0),
	Color(0.55, 0.68, 0.9, 1.0),
	Color(0.62, 0.66, 0.78, 1.0),
	Color(0.52, 0.56, 0.64, 1.0),
]

var _buckets: Array = []
var _rows: Array = []
var _bar_segments: Array = []
var _suppress: bool = false

@onready var _stack_panel: PanelContainer = $StackPanel
@onready var _stack_bar: HBoxContainer = %StackBar
@onready var _sum_value: Label = %SumValue
@onready var _sum_hint: Label = %SumHint
@onready var _rows_box: VBoxContainer = %Rows


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_stack_panel.custom_minimum_size = Vector2(0, 14)
	_stack_panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 8, 2)
	)
	_rows_box.add_theme_constant_override("separation", 2)
	_sum_value.add_theme_font_size_override("font_size", 16)


func set_buckets(buckets: Array) -> void:
	_buckets = []
	for bucket in buckets:
		var copy: Dictionary = bucket.duplicate(true)
		copy["weight_pct"] = _round2(float(copy.get("weight_pct", 0.0)))
		_buckets.append(copy)
	_rebuild()
	_emit_state()


func get_weights() -> Dictionary:
	var out := {}
	for bucket in _buckets:
		out[str(bucket["bucket_key"])] = _round2(float(bucket["weight_pct"]))
	return out


func get_buckets() -> Array:
	var out: Array = []
	for bucket in _buckets:
		out.append((bucket as Dictionary).duplicate(true))
	return out


func get_total() -> float:
	var total := 0.0
	for bucket in _buckets:
		total += float(bucket["weight_pct"])
	return _round2(total)


func is_valid() -> bool:
	return absf(get_total() - 100.0) < EPS


func _rebuild() -> void:
	for child in _stack_bar.get_children():
		child.queue_free()
	for child in _rows_box.get_children():
		child.queue_free()
	_bar_segments.clear()
	_rows.clear()

	_rows_box.add_child(_make_header())

	for i in _buckets.size():
		var bucket: Dictionary = _buckets[i]
		var color: Color = TIER_COLORS[i % TIER_COLORS.size()]
		_bar_segments.append(_make_bar_segment(color))
		_rows.append(_make_row(i, bucket, color))

	_refresh_visuals()


func _make_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 22)

	var range_h := Label.new()
	range_h.text = "Диапазон"
	range_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	range_h.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	range_h.add_theme_font_size_override("font_size", 11)
	row.add_child(range_h)

	var pct_h := Label.new()
	pct_h.text = "%"
	pct_h.custom_minimum_size = Vector2(118, 0)
	pct_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct_h.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	pct_h.add_theme_font_size_override("font_size", 11)
	row.add_child(pct_h)

	var rem_spacer := Control.new()
	rem_spacer.custom_minimum_size = Vector2(52, 0)
	row.add_child(rem_spacer)
	return row


func _make_bar_segment(color: Color) -> ColorRect:
	var seg := ColorRect.new()
	seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seg.color = color
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = 0.001
	_stack_bar.add_child(seg)
	return seg


func _make_row(index: int, bucket: Dictionary, color: Color) -> Dictionary:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	root.custom_minimum_size = Vector2(0, 30)
	_rows_box.add_child(root)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(3, 16)
	swatch.color = color
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(swatch)

	var label := Label.new()
	label.text = "%s  %s" % [str(bucket.get("range_label", "")), str(bucket.get("hint", ""))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_color_override("font_color", WeTokens.TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(label)

	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 2)
	stepper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.add_child(stepper)

	var minus := _make_step_button("−")
	var input := LineEdit.new()
	input.custom_minimum_size = Vector2(58, 28)
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.flat = true
	input.context_menu_enabled = false
	input.text = _format(float(bucket.get("weight_pct", 0.0)))
	input.add_theme_font_size_override("font_size", 13)
	input.add_theme_color_override("font_color", WeTokens.TEXT)
	input.add_theme_color_override("caret_color", WeTokens.ACCENT)
	var empty := StyleBoxEmpty.new()
	input.add_theme_stylebox_override("normal", empty)
	input.add_theme_stylebox_override("focus", empty)
	input.add_theme_stylebox_override("read_only", empty)

	var input_chrome := PanelContainer.new()
	input_chrome.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 8, 0)
	)
	input_chrome.add_child(input)

	var plus := _make_step_button("+")
	stepper.add_child(minus)
	stepper.add_child(input_chrome)
	stepper.add_child(plus)

	var remainder_btn := Button.new()
	remainder_btn.text = "+"
	remainder_btn.visible = false
	remainder_btn.focus_mode = Control.FOCUS_NONE
	remainder_btn.custom_minimum_size = Vector2(28, 28)
	remainder_btn.tooltip_text = "Добавить остаток сюда"
	remainder_btn.add_theme_stylebox_override(
		"normal",
		WeTokens.fill(WeTokens.ACCENT_SOFT, 8)
	)
	remainder_btn.add_theme_stylebox_override(
		"hover",
		WeTokens.fill(WeTokens.ACCENT_SOFT_STRONG, 8)
	)
	remainder_btn.add_theme_color_override("font_color", WeTokens.ACCENT)
	remainder_btn.add_theme_font_size_override("font_size", 14)
	root.add_child(remainder_btn)

	var row := {
		"index": index,
		"root": root,
		"input": input,
		"remainder_btn": remainder_btn,
	}

	minus.pressed.connect(func(): _nudge(index, -STEP))
	plus.pressed.connect(func(): _nudge(index, STEP))
	input.text_submitted.connect(func(_t): _commit_input(index))
	input.focus_exited.connect(func(): _commit_input(index))
	remainder_btn.pressed.connect(func(): _apply_remainder(index))

	return row


func _make_step_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(28, 28)
	button.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.05), 8))
	button.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.1), 8))
	button.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.14), 8))
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _nudge(index: int, delta: float) -> void:
	_set_weight(index, float(_buckets[index]["weight_pct"]) + delta)


func _commit_input(index: int) -> void:
	if _suppress:
		return
	var input: LineEdit = _rows[index]["input"]
	var text := input.text.strip_edges().replace(",", ".")
	if not text.is_valid_float():
		input.text = _format(float(_buckets[index]["weight_pct"]))
		return
	_set_weight(index, float(text))


func _apply_remainder(index: int) -> void:
	var remaining := _round2(100.0 - get_total())
	if remaining <= EPS:
		return
	_set_weight(index, float(_buckets[index]["weight_pct"]) + remaining)


func _set_weight(index: int, value: float) -> void:
	value = _round2(clampf(value, 0.0, 100.0))
	var others := 0.0
	for i in _buckets.size():
		if i == index:
			continue
		others += float(_buckets[i]["weight_pct"])
	var max_allowed := _round2(100.0 - others)
	if value > max_allowed:
		value = max_allowed
	_buckets[index]["weight_pct"] = value

	_suppress = true
	(_rows[index]["input"] as LineEdit).text = _format(value)
	_suppress = false

	_refresh_visuals()
	_emit_state()


func _refresh_visuals() -> void:
	var total := get_total()
	var remaining := _round2(100.0 - total)

	for i in _buckets.size():
		var weight := float(_buckets[i]["weight_pct"])
		var seg: ColorRect = _bar_segments[i]
		seg.visible = weight > EPS
		seg.size_flags_stretch_ratio = weight if weight > EPS else 0.0

		var rem_btn: Button = _rows[i]["remainder_btn"]
		rem_btn.visible = remaining > EPS

		var root: HBoxContainer = _rows[i]["root"]
		root.modulate = Color(1, 1, 1, 1.0 if weight > EPS else 0.55)

	_sum_value.text = "%.2f%%" % total
	if absf(remaining) < EPS:
		_sum_value.add_theme_color_override("font_color", WeTokens.SUCCESS)
		_sum_hint.text = "Готово"
		_sum_hint.add_theme_color_override("font_color", WeTokens.SUCCESS)
	elif remaining > 0.0:
		_sum_value.add_theme_color_override("font_color", WeTokens.ACCENT)
		_sum_hint.text = "осталось %.2f%% · «+» у строки" % remaining
		_sum_hint.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	else:
		_sum_value.add_theme_color_override("font_color", WeTokens.DANGER)
		_sum_hint.text = "превышение %.2f%%" % (-remaining)
		_sum_hint.add_theme_color_override("font_color", WeTokens.DANGER)


func _emit_state() -> void:
	var total := get_total()
	var remaining := _round2(100.0 - total)
	weights_changed.emit(total, remaining)
	validity_changed.emit(absf(remaining) < EPS)


func _round2(value: float) -> float:
	return snappedf(value, 0.01)


func _format(value: float) -> String:
	return "%.2f" % _round2(value)
