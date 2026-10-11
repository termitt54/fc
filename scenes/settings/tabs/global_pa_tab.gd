extends MarginContainer
## Editable birth chances for every country talent. Saved to user://config/youth_talent_birth.json.

const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

const BAND_LABELS := ["40–49", "50–59", "60–69", "70–79", "80–89", "90–100"]
const TALENT_W := 56
const CELL_W := 84
const SUM_W := 72

@onready var _card: PanelContainer = %Card
@onready var _header: HBoxContainer = %Header
@onready var _rows: VBoxContainer = %Rows
@onready var _save_button: WeButton = %SaveButton
@onready var _reset_button: WeButton = %ResetButton
@onready var _status: Label = %StatusLabel

var _cells: Array = []
var _sums: Array = []
var _dirty := false
var _suppress := false


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
	_header.visible = false
	_build_rows(YouthGenerationConfigScript.editor_birth_weights())
	_dirty = false
	_refresh_actions()
	_set_status("Все уровни таланта. Сохранение действует на новую генерацию.", WeTokens.TEXT_MUTED)


func _column_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_header_label("Талант", TALENT_W))
	for label in BAND_LABELS:
		row.add_child(_header_label(label, CELL_W))
	row.add_child(_header_label("Сумма", SUM_W))
	return row


func _header_label(text: String, width: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	return label


func _build_rows(table: Array) -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	_cells.clear()
	_sums.clear()
	_rows.add_child(_column_header())
	for talent in table.size():
		var source: Array = table[talent]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var talent_label := Label.new()
		talent_label.text = str(talent)
		talent_label.custom_minimum_size = Vector2(TALENT_W, 28)
		talent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		talent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		talent_label.add_theme_font_size_override("font_size", 13)
		talent_label.add_theme_color_override("font_color", WeTokens.TEXT)
		row.add_child(talent_label)
		var edits: Array = []
		for column in BAND_LABELS.size():
			var tenths := int(source[column]) if column < source.size() else 0
			var edit := _make_edit(talent, column, tenths)
			edits.append(edit)
			row.add_child(edit)
		var sum_label := Label.new()
		sum_label.custom_minimum_size = Vector2(SUM_W, 28)
		sum_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sum_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sum_label.add_theme_font_size_override("font_size", 13)
		row.add_child(sum_label)
		_rows.add_child(row)
		_cells.append(edits)
		_sums.append(sum_label)
		_refresh_sum(talent)


func _make_edit(talent: int, column: int, tenths: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(CELL_W, 28)
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.text = _format_tenths(tenths)
	edit.max_length = 6
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_color_override("font_color", WeTokens.TEXT)
	edit.add_theme_color_override("font_placeholder_color", WeTokens.TEXT_DIM)
	edit.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.04), WeTokens.RADIUS_SM))
	edit.add_theme_stylebox_override("focus", WeTokens.fill(WeTokens.ACCENT_SOFT, WeTokens.RADIUS_SM))
	edit.set_meta("talent", talent)
	edit.set_meta("column", column)
	edit.set_meta("tenths", tenths)
	edit.text_changed.connect(_on_text_changed.bind(talent))
	edit.focus_exited.connect(_on_edit_committed.bind(edit))
	edit.text_submitted.connect(func(_text: String) -> void: _on_edit_committed(edit))
	return edit


func _on_text_changed(_text: String, talent: int) -> void:
	if _suppress:
		return
	_dirty = true
	_refresh_sum(talent)
	_refresh_actions()


func _on_edit_committed(edit: LineEdit) -> void:
	var tenths := _tenths_from_text(edit.text)
	if tenths < 0:
		tenths = int(edit.get_meta("tenths"))
	edit.set_meta("tenths", tenths)
	_suppress = true
	edit.text = _format_tenths(tenths)
	_suppress = false
	_refresh_sum(int(edit.get_meta("talent")))
	_refresh_actions()


func _refresh_sum(talent: int) -> void:
	var total := 0
	var edits: Array = _cells[talent]
	var valid := true
	for edit in edits:
		var tenths := _tenths_from_text((edit as LineEdit).text)
		if tenths < 0:
			valid = false
			break
		total += tenths
	var label: Label = _sums[talent]
	if not valid:
		label.text = "—"
		label.add_theme_color_override("font_color", WeTokens.DANGER)
		return
	label.text = _format_tenths(total)
	var color := WeTokens.SUCCESS if total == YouthGenerationConfigScript.BIRTH_WEIGHT_TOTAL else WeTokens.DANGER
	label.add_theme_color_override("font_color", color)


func _collect_rows() -> Array:
	var rows: Array = []
	for edits in _cells:
		var row: Array = []
		for edit in edits:
			var tenths := _tenths_from_text((edit as LineEdit).text)
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


func _on_save_pressed() -> void:
	var result: Dictionary = YouthGenerationConfigScript.apply_birth_weights(_collect_rows())
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "Ошибка сохранения.")), WeTokens.DANGER)
		return
	_dirty = false
	_set_status("Сохранено. Действует на новую генерацию игроков.", WeTokens.SUCCESS)
	_refresh_actions()


func _on_reset_pressed() -> void:
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
	return clampi(int(round(clampf(float(cleaned), 0.0, 100.0) * 10.0)), 0, 1000)


func _format_tenths(tenths: int) -> String:
	var whole := int(tenths / 10)
	var frac := absi(tenths % 10)
	return "%d.%d" % [whole, frac]


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
