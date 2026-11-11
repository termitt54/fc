extends MarginContainer
## Editable birth chances for every country talent. Saved to user://config/youth_talent_birth.json.

const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

const TalentTools := preload("res://game/youth_talent_tools.gd")

const BAND_LABELS := ["20–39", "40–49", "50–59", "60–69", "70–74", "75–79", "80–84", "85–89", "90–94", "95–99", "100"]
const TALENT_W := 76
const CELL_W := 80
const SUM_W := 76
const GENIUS_W := 100
const SUMMARY_W := 140
const ROW_H := 40
const HEADER_H := 76
const MEAN_STEP := 0.1
const PA80_STEP := 0.5
const METRICS := ["mean", "pa70", "pa80", "pa90", "pa100"]

@onready var _card: PanelContainer = %Card
@onready var _header: VBoxContainer = %Header
@onready var _rows: VBoxContainer = %Rows
@onready var _save_button: WeButton = %SaveButton
@onready var _reset_button: WeButton = %ResetButton
@onready var _status: Label = %StatusLabel
@onready var _table_scroll: ScrollContainer = %TableScroll
@onready var _header_scroll: ScrollContainer = %TableWidth
@onready var _frozen_scroll: ScrollContainer = %FrozenScroll
@onready var _frozen_rows: VBoxContainer = %FrozenRows
var _frozen_buttons: Array = []
var _hovered_talent := -1
var _syncing_scroll := false
var _empty_spin_icon: Texture2D

var _cells: Array = []
var _sums: Array = []
var _genius: Array = []
var _stats: Array = []
var _dirty := false
var _suppress := false
var _talent: SpinBox
var _compare: SpinBox
var _population: SpinBox
var _forecast_label: Label
var _warning_label: Label
var _show_all: CheckButton
var _mean: SpinBox
var _spread: SpinBox
var _elite: SpinBox
var _one_in: SpinBox
var _undo_rows: Array = []
var _undo_button: WeButton
var _summary_controls: Dictionary = {}


func _ready() -> void:
	_card.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 20)
	)
	_save_button.kind = WeButton.Kind.PRIMARY
	_reset_button.kind = WeButton.Kind.GHOST
	_save_button.focus_mode = Control.FOCUS_NONE
	_reset_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_on_save_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_style_table()
	_build_inspector()
	_header.visible = true
	_build_rows(YouthGenerationConfigScript.editor_birth_weights())
	_dirty = false
	_select_talent()
	_refresh_actions()
	_set_status("Изменения попадут в генерацию только после сохранения. Существующие игроки не меняются.", WeTokens.TEXT_MUTED)
	_sync_table_geometry.call_deferred()


func _column_header() -> VBoxContainer:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 0)
	header.add_child(groups)
	for item in [["ВЕРОЯТНОСТИ РОЖДЕНИЯ · %", CELL_W * 11], ["ИТОГОВЫЕ ПОКАЗАТЕЛИ · − / + И ТОЧНЫЙ ВВОД", SUMMARY_W * 5 + 48], ["КОНТРОЛЬ", GENIUS_W + SUM_W]]:
		var group := PanelContainer.new()
		group.custom_minimum_size = Vector2(item[1], 28)
		group.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 0, 12, 0))
		var label := _header_label(item[0], 0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", WeTokens.ACCENT_DIM)
		group.add_child(label)
		groups.add_child(group)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	header.add_child(row)
	for label in BAND_LABELS:
		row.add_child(_header_cell(label, CELL_W))
	for metric in METRICS:
		var title := {"mean": "Средний потенциал\nPA · шаг ±0,1", "pa70": "Доля с PA ≥70\nшаг ±0,5 п.п.", "pa80": "Доля с PA ≥80\nшаг ±0,5 п.п.", "pa90": "Доля с PA ≥90\nшаг ±0,01 п.п.", "pa100": "Шанс PA 100, %\nшаг ±5% от шанса"}[metric] as String
		row.add_child(_header_cell(title, SUMMARY_W + 24 if metric in ["pa90", "pa100"] else SUMMARY_W))
	var genius_header := _header_cell("PA 100\n1 из N игроков", GENIUS_W)
	genius_header.tooltip_text = "В среднем одно рождение с PA 100 на указанное число игроков. Это пересчёт колонки 100, а не добавочный шанс."
	row.add_child(genius_header)
	row.add_child(_header_cell("Сумма\n100%", SUM_W))
	return header


func _header_cell(text: String, width: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(width, 48)
	var style := WeTokens.fill(WeTokens.SURFACE_RAISED, 0)
	style.border_width_bottom = 1
	style.border_color = WeTokens.BORDER_STRONG
	cell.add_theme_stylebox_override("panel", style)
	var label := _header_label(text, 0)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cell.tooltip_text = text.replace("\n", " · ")
	cell.add_child(label)
	return cell


func _header_label(text: String, width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	return label


func _style_table() -> void:
	(%TableFrame as PanelContainer).add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER_STRONG, 10, 1))
	(%FrozenHeader as PanelContainer).add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.SURFACE_RAISED, 0))
	var frozen_title: Label = %FrozenHeader.get_child(0)
	frozen_title.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	frozen_title.add_theme_font_size_override("font_size", 12)
	for bar in [_table_scroll.get_v_scroll_bar(), _table_scroll.get_h_scroll_bar()]:
		bar.custom_minimum_size = Vector2(12, 12)
		bar.add_theme_stylebox_override("scroll", WeTokens.fill(WeTokens.INSET, 5, 0, 0))
		bar.add_theme_stylebox_override("grabber", WeTokens.fill(WeTokens.BORDER_STRONG, 5, 0, 0))
		bar.add_theme_stylebox_override("grabber_highlight", WeTokens.fill(WeTokens.ACCENT_DIM, 5, 0, 0))
		bar.add_theme_stylebox_override("grabber_pressed", WeTokens.fill(WeTokens.ACCENT, 5, 0, 0))
		bar.visibility_changed.connect(_sync_table_geometry.call_deferred)
	_table_scroll.get_v_scroll_bar().value_changed.connect(_sync_vertical.bind(true))
	_frozen_scroll.get_v_scroll_bar().value_changed.connect(_sync_vertical.bind(false))
	_table_scroll.get_h_scroll_bar().value_changed.connect(_sync_horizontal.bind(true))
	_header_scroll.get_h_scroll_bar().value_changed.connect(_sync_horizontal.bind(false))
	_table_scroll.resized.connect(_sync_table_geometry.call_deferred)
	var actions := _save_button.get_parent() as HBoxContainer
	(actions.get_parent() as PanelContainer).add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 10, 12, 8))
	actions.custom_minimum_size.y = 34
	_status.add_theme_font_size_override("font_size", 12)


func _sync_vertical(value: float, from_main: bool) -> void:
	if _syncing_scroll:
		return
	_syncing_scroll = true
	if from_main:
		_frozen_scroll.scroll_vertical = roundi(value)
	else:
		_table_scroll.scroll_vertical = roundi(value)
	_syncing_scroll = false


func _sync_horizontal(value: float, from_main: bool) -> void:
	if _syncing_scroll:
		return
	_syncing_scroll = true
	if from_main:
		_header_scroll.scroll_horizontal = roundi(value)
	else:
		_table_scroll.scroll_horizontal = roundi(value)
	_syncing_scroll = false


func _sync_table_geometry() -> void:
	var vertical := _table_scroll.get_v_scroll_bar()
	var horizontal := _table_scroll.get_h_scroll_bar()
	(%HeaderGutter as Control).custom_minimum_size.x = vertical.get_combined_minimum_size().x if vertical.visible else 0.0
	(%FrozenFooter as Control).custom_minimum_size.y = horizontal.get_combined_minimum_size().y if horizontal.visible else 0.0
	_sync_vertical(_table_scroll.scroll_vertical, true)
	_sync_horizontal(_table_scroll.scroll_horizontal, true)


func _hover_row(talent: int, hovered: bool) -> void:
	var previous := _hovered_talent
	_hovered_talent = talent if hovered else (-1 if previous == talent else previous)
	if previous >= 0:
		_style_row(previous)
	_style_row(talent)


func _style_row(talent: int) -> void:
	if talent < 0 or talent >= _rows.get_child_count():
		return
	var selected := _talent != null and int(_talent.value) == talent
	var compared := _compare != null and int(_compare.value) == talent
	var bg := WeTokens.INSET.lightened(0.025) if talent % 2 else WeTokens.INSET
	if talent == _hovered_talent:
		bg = WeTokens.SURFACE_RAISED
	if selected:
		bg = Color(0.12, 0.24, 0.25, 1)
	var row_style := WeTokens.fill(bg, 0)
	row_style.border_width_bottom = 1
	row_style.border_color = Color(1, 1, 1, 0.025)
	(_rows.get_child(talent) as PanelContainer).add_theme_stylebox_override("panel", row_style)
	var frozen_style := row_style.duplicate() as StyleBoxFlat
	frozen_style.border_width_left = 3
	frozen_style.border_color = WeTokens.ACCENT if selected else (WeTokens.BORDER_STRONG if compared else Color(0, 0, 0, 0))
	var button: Button = _frozen_buttons[talent]
	for state in ["normal", "hover", "pressed"]:
		button.add_theme_stylebox_override(state, frozen_style)
	button.add_theme_color_override("font_color", WeTokens.ACCENT if selected else WeTokens.TEXT_MUTED)
	button.add_theme_color_override("font_hover_color", WeTokens.ACCENT)
	button.add_theme_color_override("font_pressed_color", WeTokens.ACCENT)


func _scroll_to_talent(talent: int) -> void:
	if _show_all.button_pressed and talent < _rows.get_child_count():
		_table_scroll.scroll_vertical = maxi(0, roundi(_rows.get_child(talent).position.y - ROW_H * 3))


func _on_cell_key(event: InputEvent, edit: LineEdit) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	var talent := int(edit.get_meta("talent"))
	var column := int(edit.get_meta("column"))
	if event.keycode == KEY_ESCAPE:
		_suppress = true
		edit.text = _format_tenths(int(edit.get_meta("tenths")))
		_suppress = false
		edit.release_focus()
		edit.accept_event()
	elif event.keycode in [KEY_UP, KEY_DOWN]:
		var direction := 1 if event.keycode == KEY_DOWN else -1
		var next := talent + direction
		while next >= 0 and next < _cells.size():
			if _rows.get_child(next).visible:
				_on_edit_committed(edit)
				(_cells[next][column] as LineEdit).grab_focus()
				break
			next += direction
		edit.accept_event()


func _build_rows(table: Array) -> void:
	var prior_suppress := _suppress
	_suppress = true
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()
	for child in _header.get_children():
		_header.remove_child(child)
		child.free()
	_header.add_child(_column_header())
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	_cells.clear()
	_sums.clear()
	_genius.clear()
	_stats.clear()
	_summary_controls.clear()
	for child in _frozen_rows.get_children():
		child.free()
	_frozen_buttons.clear()
	for talent in table.size():
		var source: Array = table[talent]
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = ROW_H
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		panel.add_child(row)
		panel.mouse_entered.connect(_hover_row.bind(talent, true))
		panel.mouse_exited.connect(_hover_row.bind(talent, false))
		var talent_button := Button.new()
		talent_button.text = str(talent)
		talent_button.custom_minimum_size = Vector2(TALENT_W, ROW_H)
		talent_button.focus_mode = Control.FOCUS_NONE
		talent_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		talent_button.add_theme_font_size_override("font_size", 14)
		talent_button.tooltip_text = "Выбрать строку таланта %d" % talent
		talent_button.pressed.connect(func(): _talent.value = talent)
		talent_button.mouse_entered.connect(_hover_row.bind(talent, true))
		talent_button.mouse_exited.connect(_hover_row.bind(talent, false))
		_frozen_rows.add_child(talent_button)
		_frozen_buttons.append(talent_button)
		var edits: Array = []
		for column in BAND_LABELS.size():
			var tenths := int(source[column]) if column < source.size() else 0
			var edit := _make_edit(talent, column, tenths)
			edits.append(edit)
			row.add_child(edit)
		var statistics: Array = []
		_summary_controls[talent] = {}
		for key in METRICS:
			row.add_child(_make_summary_control(talent, key))
			statistics.append(_summary_controls[talent][key]["edit"])
		_stats.append(statistics)
		var genius := _header_label("", GENIUS_W)
		genius.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
		row.add_child(genius)
		var sum_label := Label.new()
		sum_label.custom_minimum_size = Vector2(SUM_W, ROW_H)
		sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sum_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sum_label.add_theme_font_size_override("font_size", 13)
		row.add_child(sum_label)
		_rows.add_child(panel)
		_cells.append(edits)
		_sums.append(sum_label)
		_genius.append(genius)
		_refresh_sum(talent)
	_filter_rows()
	_suppress = prior_suppress
	_sync_table_geometry.call_deferred()


func _make_summary_control(talent: int, metric: String) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(SUMMARY_W + 24 if metric in ["pa90", "pa100"] else SUMMARY_W, ROW_H)
	box.add_theme_constant_override("separation", 3)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var buttons: Array = []
	for text in ["−", "+"]:
		var button := Button.new()
		button.text = text
		button.custom_minimum_size = Vector2(26, 28)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 15)
		button.add_theme_color_override("font_color", WeTokens.TEXT)
		button.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.035), 5))
		button.add_theme_stylebox_override("hover", WeTokens.fill(WeTokens.ACCENT_SOFT, 5))
		button.add_theme_stylebox_override("pressed", WeTokens.fill(WeTokens.ACCENT_SOFT_STRONG, 5))
		button.add_theme_stylebox_override("disabled", WeTokens.fill(Color(0, 0, 0, 0), 5))
		button.add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
		buttons.append(button)
	var edit := LineEdit.new()
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(94 if metric in ["pa90", "pa100"] else 70, 32)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.max_length = 16
	edit.set_meta("summary_talent", talent)
	edit.set_meta("summary_metric", metric)
	edit.add_theme_font_size_override("font_size", 12)
	edit.add_theme_color_override("font_color", WeTokens.TEXT)
	edit.add_theme_stylebox_override("normal", WeTokens.fill(Color(0, 0, 0, 0), 5))
	edit.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.ACCENT_SOFT, WeTokens.BORDER_FOCUS, 5, 0))
	box.add_child(buttons[0])
	box.add_child(edit)
	box.add_child(buttons[1])
	_summary_controls[talent][metric] = {"edit": edit, "minus": buttons[0], "plus": buttons[1]}
	var name := _metric_name(metric)
	var hint := "Талант %d: %s. %s Ручной ввод — Enter или выход из поля. Действует после сохранения." % [talent, name, _metric_explanation(metric)]
	edit.tooltip_text = hint
	buttons[0].tooltip_text = "Уменьшить %s. %s" % [name, hint]
	buttons[1].tooltip_text = "Увеличить %s. %s" % [name, hint]
	buttons[0].pressed.connect(_nudge_summary.bind(talent, metric, -1))
	buttons[1].pressed.connect(_nudge_summary.bind(talent, metric, 1))
	edit.focus_entered.connect(func():
		_talent.set_value_no_signal(talent)
		_select_talent()
		_set_status("Талант %d: %s. %s" % [talent, name, _metric_explanation(metric)], WeTokens.TEXT_MUTED)
		edit.text = "%.6f" % float(edit.get_meta("actual", 0.0))
		edit.set_meta("original_text", edit.text)
		edit.select_all()
		_table_scroll.ensure_control_visible(edit))
	edit.focus_exited.connect(_commit_summary.bind(talent, metric))
	edit.text_submitted.connect(func(_value: String): _commit_summary(talent, metric))
	edit.text_changed.connect(func(text: String):
		if not _suppress and text.replace(",", ".").replace("%", "").strip_edges().is_valid_float():
			_dirty = true
			_refresh_actions())
	return box


func _metric_name(metric: String) -> String:
	return {"mean": "средний потенциал PA", "pa70": "доля игроков с PA от 70", "pa80": "доля игроков с PA от 80", "pa90": "доля игроков с PA от 90", "pa100": "шанс рождения PA 100"}.get(metric, "")


func _metric_explanation(metric: String) -> String:
	if metric == "mean":
		return "Средний потенциал всех новых игроков. Шаг 0,1 PA; шансы PA 90–100 сохраняются."
	if metric == "pa100":
		return "Процент всех рождений. + делает гениев чаще, − реже. Шаг 5% текущего шанса, минимум 0,000001 п.п."
	return "50%% означает 50 из 100 новых игроков с потенциалом не ниже %s. %s" % [metric.trim_prefix("pa"), "Шанс PA 100 сохраняется." if metric == "pa90" else "Шансы PA 90–100 сохраняются."]


func _metric_value(row: Array, metric: String) -> float:
	return YouthGenerationConfigScript.row_mean_potential(row) if metric == "mean" else YouthGenerationConfigScript.row_probability(row, int(metric.trim_prefix("pa"))) * 100.0


func _metric_display(metric: String, value: float) -> String:
	if metric == "mean":
		return "%.1f" % value
	if metric in ["pa90", "pa100"]:
		return _format_tenths(roundi(value * YouthGenerationConfigScript.PERCENT_SCALE)) + "%"
	return "%.2f%%" % value


func _metric_step(metric: String, value: float) -> float:
	if metric == "mean": return MEAN_STEP
	if metric == "pa90": return 0.01
	if metric == "pa100": return maxf(1.0 / YouthGenerationConfigScript.PERCENT_SCALE, roundf(value * 0.05 * YouthGenerationConfigScript.PERCENT_SCALE) / YouthGenerationConfigScript.PERCENT_SCALE)
	return PA80_STEP


func _refresh_summary(talent: int, metric: String, value: float, valid: bool) -> void:
	var controls: Dictionary = _summary_controls[talent][metric]
	var edit: LineEdit = controls.edit
	edit.set_meta("actual", value)
	if not edit.has_focus():
		edit.text = _metric_display(metric, value)
		edit.set_meta("original_text", edit.text)
	edit.editable = valid
	var limits := TalentTools.summary_limits(_selected_row(talent), metric) if valid else {"min": value, "max": value}
	var tolerance := 0.00001 if metric == "mean" else 0.0000005
	controls.minus.disabled = not valid or value <= float(limits.min) + tolerance
	controls.plus.disabled = not valid or value >= float(limits.max) - tolerance
	if metric == "pa100":
		controls.minus.disabled = not valid or value <= 0.0
		controls.plus.disabled = not valid or value >= 100.0


func _nudge_summary(talent: int, metric: String, direction: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and is_ancestor_of(focused) and focused.has_meta("summary_talent"):
		if not _commit_summary(int(focused.get_meta("summary_talent")), str(focused.get_meta("summary_metric"))):
			return
		focused.release_focus()
	var row := _selected_row(talent)
	if row.is_empty():
		return
	var current := _metric_value(row, metric)
	_apply_summary(talent, metric, current + direction * _metric_step(metric, current))


func _commit_summary(talent: int, metric: String) -> bool:
	if _suppress:
		return true
	var edit: LineEdit = _summary_controls[talent][metric].edit
	if edit.text == str(edit.get_meta("original_text", "")):
		return true
	var cleaned := edit.text.strip_edges().replace("%", "").replace(" ", "").replace(",", ".")
	var success := false
	if cleaned.is_valid_float() and is_finite(float(cleaned)):
		success = _apply_summary(talent, metric, float(cleaned))
	else:
		_set_status("Введите число: например 77,5 или 49,5%.", WeTokens.DANGER)
	edit.text = _metric_display(metric, float(edit.get_meta("actual", 0.0)))
	edit.set_meta("original_text", edit.text)
	return success


func _apply_summary(talent: int, metric: String, value: float) -> bool:
	var result := TalentTools.adjust_summary(_selected_row(talent), metric, value)
	if not bool(result.ok):
		_set_status(str(result.error), WeTokens.DANGER)
		return false
	_remember_undo()
	_replace_row(talent, result.row)
	_talent.set_value_no_signal(talent)
	_select_talent()
	var preserved := "PA 90–100 сохранены." if metric in ["mean", "pa70", "pa80"] else ("Шанс PA 100 сохранён." if metric == "pa90" else "Остальные диапазоны пересчитаны пропорционально.")
	var message := "Талант %d: %s = %s. Сумма 100%%. %s" % [talent, _metric_name(metric), _metric_display(metric, result.actual), preserved]
	if bool(result.clamped):
		message += " Достигнута граница доступного диапазона."
	_tool_done(message)
	return true


func _make_edit(talent: int, column: int, tenths: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(CELL_W, 32)
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.text = _display_units(tenths)
	edit.set_meta("display_text", edit.text)
	edit.tooltip_text = "Точное значение: %s%%. При редактировании показана полная точность." % _format_tenths(tenths)
	edit.max_length = 10
	edit.add_theme_font_size_override("font_size", 12)
	edit.add_theme_color_override("font_color", WeTokens.TEXT)
	edit.add_theme_color_override("font_placeholder_color", WeTokens.TEXT_DIM)
	edit.add_theme_stylebox_override("normal", WeTokens.fill(Color(0, 0, 0, 0), 5))
	edit.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.ACCENT_SOFT, WeTokens.BORDER_FOCUS, 5, 0))
	edit.set_meta("talent", talent)
	edit.set_meta("column", column)
	edit.set_meta("tenths", tenths)
	edit.text_changed.connect(func(text: String):
		edit.set_meta("committed_display", false)
		_on_text_changed(text, talent))
	edit.focus_entered.connect(_on_edit_started.bind(edit))
	edit.focus_exited.connect(_on_edit_committed.bind(edit))
	edit.text_submitted.connect(func(_text: String) -> void: _on_edit_committed(edit))
	edit.gui_input.connect(_on_cell_key.bind(edit))
	return edit


func _on_text_changed(_text: String, talent: int) -> void:
	if _suppress:
		return
	_dirty = true
	_refresh_sum(talent)
	_refresh_actions()


func _on_edit_committed(edit: LineEdit) -> void:
	if _suppress:
		return
	var tenths := int(edit.get_meta("tenths")) if bool(edit.get_meta("committed_display", false)) and edit.text == str(edit.get_meta("display_text", "")) else _tenths_from_text(edit.text)
	if tenths < 0:
		tenths = int(edit.get_meta("tenths"))
	edit.set_meta("tenths", tenths)
	_suppress = true
	edit.text = _display_units(tenths)
	edit.set_meta("display_text", edit.text)
	edit.set_meta("committed_display", true)
	edit.tooltip_text = "Точное значение: %s%%. При редактировании показана полная точность." % _format_tenths(tenths)
	_suppress = false
	_refresh_sum(int(edit.get_meta("talent")))
	_refresh_actions()


func _on_edit_started(edit: LineEdit) -> void:
	edit.set_meta("committed_display", false)
	_talent.set_value_no_signal(int(edit.get_meta("talent")))
	_select_talent()
	_suppress = true
	edit.text = _format_tenths(int(edit.get_meta("tenths")))
	_suppress = false
	_table_scroll.ensure_control_visible(edit)


func _read_edit(edit: LineEdit) -> int:
	if not edit.has_focus() and edit.text == str(edit.get_meta("display_text", "")):
		return int(edit.get_meta("tenths"))
	return _tenths_from_text(edit.text)


func _refresh_sum(talent: int) -> void:
	var total := 0
	var edits: Array = _cells[talent]
	var valid := true
	for edit in edits:
		var tenths := _read_edit(edit as LineEdit)
		if tenths < 0:
			valid = false
			break
		total += tenths
	var label: Label = _sums[talent]
	var weights: Array = []
	for edit in edits:
		weights.append(maxi(_read_edit(edit as LineEdit), 0))
	var exact_percent := YouthGenerationConfigScript.row_probability(weights, 100) * 100.0
	(_genius[talent] as Label).text = _grouped_integer(int(round(100.0 / exact_percent))) if exact_percent > 0.0 else "—"
	(_genius[talent] as Label).tooltip_text = "Абсолютный шанс PA 100: %.6f%%" % exact_percent
	for metric in METRICS:
		_refresh_summary(talent, metric, _metric_value(weights, metric), valid and total == YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL)
	if not valid:
		label.text = "—"
		label.add_theme_color_override("font_color", WeTokens.DANGER)
		return
	label.text = "100%" if total == YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL else _format_tenths(total) + "%"
	var color := WeTokens.SUCCESS if total == YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL else WeTokens.DANGER
	label.add_theme_color_override("font_color", color)


func _collect_rows() -> Array:
	var rows: Array = []
	for edits in _cells:
		var row: Array = []
		for edit in edits:
			var tenths := _read_edit(edit as LineEdit)
			if tenths < 0:
				return []
			row.append(tenths)
		rows.append(row)
	return rows


func _table_is_valid() -> bool:
	var rows := _collect_rows()
	if rows.size() != _cells.size():
		return false
	for row in rows:
		var total := 0
		for weight in row:
			total += int(weight)
		if total != YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL:
			return false
	return true


func _refresh_actions() -> void:
	_save_button.disabled = (not _dirty) or (not _table_is_valid())
	_refresh_forecast()


func _on_save_pressed() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit and is_ancestor_of(focused):
		if focused.has_meta("summary_talent") and not _commit_summary(int(focused.get_meta("summary_talent")), str(focused.get_meta("summary_metric"))):
			return
		focused.release_focus()
	var result: Dictionary = YouthGenerationConfigScript.apply_birth_weights(_collect_rows())
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "Ошибка сохранения.")), WeTokens.DANGER)
		return
	_dirty = false
	_set_status("Сохранено. Действует на новую генерацию игроков.", WeTokens.SUCCESS)
	_refresh_actions()


func _on_reset_pressed() -> void:
	_remember_undo()
	_suppress = true
	_build_rows(YouthGenerationConfigScript.default_birth_weights())
	_suppress = false
	_dirty = true
	_set_status("Восстановлены значения по умолчанию — нажмите «Сохранить».", WeTokens.ACCENT)
	_refresh_actions()


func _tenths_from_text(text: String) -> int:
	var cleaned := text.strip_edges().replace(",", ".")
	if cleaned.is_empty() or not cleaned.is_valid_float():
		return -1
	return clampi(int(round(clampf(float(cleaned), 0.0, 100.0) * YouthGenerationConfigScript.PERCENT_SCALE)), 0, YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL)


func _format_tenths(tenths: int) -> String:
	var formatted := "%.6f" % (float(tenths) / YouthGenerationConfigScript.PERCENT_SCALE)
	while formatted.ends_with("0"):
		formatted = formatted.trim_suffix("0")
	return formatted + "0" if formatted.ends_with(".") else formatted


func _grouped_integer(value: int) -> String:
	var digits := str(value)
	var result := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			result += " "
		result += digits[i]
	return result


func _display_units(units: int) -> String:
	if units < YouthGenerationConfigScript.PERCENT_SCALE:
		return _format_tenths(units)
	return "%.2f" % (float(units) / YouthGenerationConfigScript.PERCENT_SCALE)



func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func _text(text: String, muted: bool = true) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size",12)
	label.add_theme_color_override("font_color",WeTokens.TEXT_MUTED if muted else WeTokens.TEXT)
	return label


func _number(parent: Container, title: String, lo: float, hi: float, step: float, value: float, hint: String) -> SpinBox:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_text(title))
	var chrome := PanelContainer.new()
	chrome.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 8, 3))
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 2)
	chrome.add_child(controls)
	var input := SpinBox.new()
	input.min_value = lo
	input.max_value = hi
	input.step = step
	input.value = value
	input.custom_minimum_size.x = 150
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.tooltip_text = hint
	if _empty_spin_icon == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_empty_spin_icon = ImageTexture.create_from_image(image)
	input.add_theme_icon_override("updown", _empty_spin_icon)
	input.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.get_line_edit().add_theme_color_override("font_color", WeTokens.TEXT)
	input.get_line_edit().add_theme_font_size_override("font_size", 13)
	input.get_line_edit().add_theme_stylebox_override("normal", WeTokens.fill(Color(0, 0, 0, 0), 5, 8, 6))
	input.get_line_edit().add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.ACCENT_SOFT, WeTokens.BORDER_FOCUS, 5, 6))
	for direction in [-1, 1]:
		var button := Button.new()
		button.text = "−" if direction < 0 else "+"
		button.custom_minimum_size = Vector2(32, 32)
		button.focus_mode = Control.FOCUS_NONE
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
		button.add_theme_stylebox_override("normal", WeTokens.fill(Color(0, 0, 0, 0), 5))
		button.add_theme_stylebox_override("hover", WeTokens.fill(WeTokens.ACCENT_SOFT, 5))
		button.add_theme_stylebox_override("pressed", WeTokens.fill(WeTokens.ACCENT_SOFT_STRONG, 5))
		button.pressed.connect(func():
			if input.get_line_edit().has_focus():
				input.apply()
				input.get_line_edit().release_focus()
			input.value += direction * input.step)
		controls.add_child(button)
	controls.add_child(input)
	controls.move_child(input, 1)
	box.add_child(chrome)
	parent.add_child(box)
	return input


func _action(parent: Container, title: String, callback: Callable) -> WeButton:
	var button := WeButton.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _build_inspector() -> void:
	var body: VBoxContainer = %Body
	var inspector := VBoxContainer.new()
	inspector.add_theme_constant_override("separation",8)
	body.add_child(inspector)
	body.move_child(inspector,2)
	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation",16)
	inspector.add_child(selectors)
	_talent = _number(selectors,"Редактируем талант",0,100,1,85,"Строка таблицы, которую изменяют инструменты ниже. Это уровень страны, а не CA игрока.")
	_compare = _number(selectors,"Сравнить с талантом",0,100,1,75,"Сравнение качества потенциала при одинаковом количестве рождений.")
	_population = _number(selectors,"Игроков в прогнозе",1,1000000,1,1000,"Только масштаб прогноза, не число игроков, рождаемых игрой. Например 100 игроков за сезон × 10 сезонов = 1000.")
	_show_all = CheckButton.new()
	_show_all.text = "Вся таблица 0–100"
	_show_all.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_show_all.add_theme_font_size_override("font_size", 13)
	_show_all.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	selectors.add_child(_show_all)
	_talent.value_changed.connect(func(_v):
		_select_talent()
		_scroll_to_talent.call_deferred(int(_talent.value)))
	_compare.value_changed.connect(func(_v): _filter_rows(); _refresh_forecast())
	_population.value_changed.connect(func(_v): _refresh_forecast())
	_show_all.toggled.connect(func(_v):
		_filter_rows()
		_scroll_to_talent.call_deferred(int(_talent.value)))
	_forecast_label = _text("",false)
	_forecast_label.add_theme_stylebox_override("normal", WeTokens.fill(WeTokens.INSET, 8, 12, 10))
	inspector.add_child(_forecast_label)
	_warning_label = _text("")
	_warning_label.add_theme_color_override("font_color",WeTokens.DANGER)
	inspector.add_child(_warning_label)
	var toggle := WeButton.new()
	toggle.text = "Профиль и плавная шкала"
	toggle.kind = WeButton.Kind.GHOST
	toggle.toggle_mode = true
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	inspector.add_child(toolbar)
	toolbar.add_child(toggle)
	var help_toggle := WeButton.new()
	help_toggle.text = "Как читать таблицу"
	help_toggle.kind = WeButton.Kind.GHOST
	help_toggle.toggle_mode = true
	toolbar.add_child(help_toggle)
	var navigation := _text("↑ ↓ — соседняя строка  ·  Esc — отменить ввод")
	navigation.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	toolbar.add_child(navigation)
	var help := VBoxContainer.new()
	help.visible = false
	inspector.add_child(help)
	help_toggle.toggled.connect(func(open: bool): help.visible = open)
	help.add_child(_text("PA — потенциал, а не текущая сила CA. «Доля с PA ≥80» = процент рождений с потенциалом от 80 до 100: например, 50% — это 50 из 100 игроков. Доли вложены: PA ≥90 входит в PA ≥80 и PA ≥70; изменение одного показателя может менять остальные."))
	help.add_child(_text("− / + и ввод числа меняют только строку указанного таланта. Средний PA: шаг 0,1; доли PA ≥70/≥80: 0,5 п.п.; PA ≥90: 0,01 п.п. Для PA 100 шаг — 5% текущего шанса, а «1 из N» справа — его пересчёт, не дополнительная вероятность."))
	var tools := VBoxContainer.new()
	tools.add_theme_constant_override("separation",8)
	tools.visible = false
	inspector.add_child(tools)
	toggle.toggled.connect(func(open: bool): tools.visible = open)
	tools.add_child(_text("Профиль: средний PA задаёт уровень поколения; разброс — различие обычных игроков и редких сильных. PA 90+ управляет хвостом звёзд; PA 100 настраивается отдельно. Все инструменты меняют только выбранную строку до сохранения."))
	var parameters := HBoxContainer.new()
	parameters.add_theme_constant_override("separation",16)
	tools.add_child(parameters)
	_mean = _number(parameters,"Средний PA поколения",29.5,96,0.1,70,"Желаемый средний потенциал всех рождений, не средний CA сборной. Инструмент подберёт доли диапазонов.")
	_spread = _number(parameters,"Разброс текущего профиля ×",0.5,2,0.05,1,"1 — ширина исходного профиля. Меньше — игроки ближе к среднему; больше — больше крайних значений. Средний PA затем подгоняется отдельно.")
	_elite = _number(parameters,"Вес редких PA 90–99 ×",0.05,5,0.05,1,"Относительный вес диапазонов 90–99 перед подгонкой среднего. Не готовый процент: конечную долю смотрите в прогнозе. PA 100 не затрагивается.")
	_one_in = _number(parameters,"PA 100: один на N игроков",0,100000000,1,1000000,"0 — PA 100 не рождается. 1000000 — в среднем один на миллион рождений, не гарантированная квота. Точность таблицы — до одного на сто миллионов.")
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",8)
	actions.add_theme_constant_override("v_separation",6)
	tools.add_child(actions)
	_action(actions,"Построить профиль",_reshape_selected)
	_action(actions,"Довести сумму до 100%",_normalise_selected)
	_action(actions,"Плавно заполнить между уровнями",_interpolate_selected)
	_action(actions,"Рекомендуемая строка",_reset_selected)
	_undo_button = _action(_save_button.get_parent(),"Отменить",_undo_tool)
	_save_button.get_parent().move_child(_undo_button, 1)
	_undo_button.kind = WeButton.Kind.GHOST
	_undo_button.disabled = true
	tools.add_child(_text("Плавное заполнение использует выбранный и сравниваемый уровни как границы: меняет только строки между ними. Границы сохраняются. Для ручной правки процентов используйте таблицу; внутри 80–99 верхние значения по-прежнему реже. Рождение PA и его реализация в CA — разные процессы."))


func _selected_row(talent: int) -> Array:
	var row := []
	if talent>=_cells.size():
		return row
	for edit in _cells[talent]:
		var value := _read_edit(edit)
		if value<0:
			return []
		row.append(value)
	return row


func _select_talent() -> void:
	if _cells.is_empty():
		return
	_filter_rows()
	_load_profile_parameters()
	_refresh_forecast()


func _load_profile_parameters() -> void:
	var row := _selected_row(int(_talent.value))
	if row.is_empty() or row.reduce(func(a,b): return a+b,0)!=YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL:
		return
	_mean.value = YouthGenerationConfigScript.row_mean_potential(row)
	_spread.value = 1
	_elite.value = 1
	var chance := YouthGenerationConfigScript.row_probability(row,100)
	_one_in.value = round(1.0/chance) if chance>0 else 0


func _filter_rows() -> void:
	if _talent==null:
		return
	for i in _rows.get_child_count():
		_rows.get_child(i).visible = _show_all.button_pressed or i==int(_talent.value) or i==int(_compare.value)
		_frozen_buttons[i].visible = _rows.get_child(i).visible
		_style_row(i)
	_sync_table_geometry.call_deferred()


func _forecast_text(talent: int) -> String:
	var row := _selected_row(talent)
	if row.is_empty() or row.reduce(func(a,b): return a+b,0)!=YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL:
		return "Талант %d: исправьте сумму строки — нужно 100%%." % talent
	var f := TalentTools.forecast(row,int(_population.value))
	return "Талант %d · средний PA %.1f · из %d игроков ожидается PA 70+: %.1f / 80+: %.1f / 90+: %.2f / 95+: %.3f / 100: %.5f" % [talent,f.mean,int(_population.value),f.thresholds[70].expected,f.thresholds[80].expected,f.thresholds[90].expected,f.thresholds[95].expected,f.thresholds[100].expected]


func _refresh_forecast() -> void:
	if _forecast_label==null or _cells.is_empty():
		return
	_forecast_label.text = _forecast_text(int(_talent.value))+"\n"+_forecast_text(int(_compare.value))
	_forecast_label.tooltip_text = "Ожидаемые количества — средние на дистанции, не обещание для отдельного поколения. Это PA, не стартовый или будущий гарантированный CA."
	var rows := _collect_rows()
	if rows.is_empty() or not _table_is_valid():
		_warning_label.text = "Есть некорректные строки. Сохранение недоступно, пока сумма каждой строки не станет 100%."
		_warning_label.visible = true
		return
	var warnings := TalentTools.progression_warnings(rows)
	_warning_label.text = "Внимание: у %d уровней рост таланта снижает средний PA. Проверьте шкалу; это предупреждение, сохранение разрешено." % warnings.size() if not warnings.is_empty() else ""
	_warning_label.visible = not _warning_label.text.is_empty()


func _remember_undo() -> void:
	_undo_rows = _collect_rows()
	_undo_button.disabled = _undo_rows.is_empty()


func _replace_row(talent: int, row: Array) -> void:
	_suppress = true
	for i in row.size():
		var edit: LineEdit = _cells[talent][i]
		edit.set_meta("tenths",int(row[i]))
		edit.text = _display_units(int(row[i]))
		edit.set_meta("display_text",edit.text)
		edit.tooltip_text = "Точное значение: %s%%" % _format_tenths(int(row[i]))
	_suppress = false
	_refresh_sum(talent)


func _tool_done(message: String) -> void:
	_dirty = true
	_refresh_actions()
	_set_status(message+" Нажмите «Сохранить» для применения.",WeTokens.ACCENT)


func _reshape_selected() -> void:
	var result := TalentTools.reshape(_selected_row(int(_talent.value)),_mean.value,_spread.value,_elite.value,_one_in.value)
	if not bool(result.ok):
		_set_status(str(result.error),WeTokens.DANGER)
		return
	_remember_undo()
	_replace_row(int(_talent.value),result.row)
	_load_profile_parameters()
	_tool_done("Профиль выбранного таланта построен.")


func _normalise_selected() -> void:
	var row := TalentTools.normalise(_selected_row(int(_talent.value)))
	if row.is_empty():
		_set_status("Введите хотя бы одно положительное значение.",WeTokens.DANGER)
		return
	_remember_undo()
	_replace_row(int(_talent.value),row)
	_load_profile_parameters()
	_tool_done("Доли пропорционально приведены к 100%.")


func _interpolate_selected() -> void:
	var lo := mini(int(_talent.value),int(_compare.value))
	var hi := maxi(int(_talent.value),int(_compare.value))
	if hi-lo<2 or not _table_is_valid():
		_set_status("Нужны два уровня с промежутком и корректная таблица с суммой 100%.",WeTokens.DANGER)
		return
	_remember_undo()
	var a := _selected_row(lo)
	var b := _selected_row(hi)
	for i in range(lo+1,hi):
		_replace_row(i,TalentTools.interpolate(a,b,float(i-lo)/float(hi-lo)))
	_tool_done("Заполнены уровни %d–%d; крайние строки сохранены." % [lo+1,hi-1])


func _reset_selected() -> void:
	_remember_undo()
	_replace_row(int(_talent.value),YouthGenerationConfigScript.default_birth_weights()[int(_talent.value)])
	_load_profile_parameters()
	_tool_done("Восстановлена выбранная строка.")


func _undo_tool() -> void:
	if _undo_rows.is_empty():
		return
	_build_rows(_undo_rows)
	_undo_rows = []
	_undo_button.disabled = true
	_load_profile_parameters()
	_tool_done("Последнее действие инструмента отменено.")
