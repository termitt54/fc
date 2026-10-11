extends WeModal
## Edit prize money for regular-season / division places and playoff finishes.


signal prizes_submitted(unit_id: int, prize_rules: Dictionary)

const NUMBER_FIELD := preload("res://ui/components/we_number_field.tscn")

var _unit_id: int = -1
var _unit: Dictionary = {}
var _amounts: Dictionary = {}
var _busy: bool = false
var _list: VBoxContainer


func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 110
	set_card_size(620, 720)
	set_body_separation(8)
	_build_body()
	confirmed.connect(_on_confirm)
	cancelled.connect(_on_cancel)


func _build_body() -> void:
	var hint := Label.new()
	hint.text = "Суммы за сезон. Регулярка и плей-офф складываются. 0 — без выплаты."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	get_body().add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func open_editor(unit: Dictionary) -> void:
	_unit_id = int(unit.get("id", 0))
	_unit = unit.duplicate(true)
	_amounts = PrizeRules.parse_stored(unit.get("prize_rules", {}), _unit)
	set_title("Призовые: %s" % str(unit.get("name", "дивизион")))
	set_confirm_text("Сохранить")
	_render()
	clear_error()
	set_busy(false)
	open()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)


func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var rows: Array = PrizeRules.describe_rows(_unit)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "Для этих правил пока нечего настраивать."
		empty.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 12)
		_list.add_child(empty)
		return

	var current_section := ""
	for row in rows:
		var section := str(row.get("section", ""))
		if section != current_section:
			current_section = section
			_list.add_child(_make_section_title(section))
		_list.add_child(_make_amount_row(row))


func _make_section_title(text: String) -> Label:
	var title := Label.new()
	title.text = text
	title.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	title.add_theme_font_size_override("font_size", 11)
	return title


func _make_amount_row(row: Dictionary) -> PanelContainer:
	var key := str(row.get("key", ""))
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 8, 8)
	)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	panel.add_child(inner)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	inner.add_child(titles)

	var label := Label.new()
	label.text = str(row.get("label", key))
	label.add_theme_color_override("font_color", WeTokens.TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	titles.add_child(label)

	var hint := Label.new()
	hint.text = str(row.get("hint", ""))
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	titles.add_child(hint)

	var field: WeNumberField = NUMBER_FIELD.instantiate()
	field.compact = true
	field.label = "Сумма"
	field.min_value = 0
	field.max_value = PrizeRules.AMOUNT_MAX
	field.step = PrizeRules.AMOUNT_STEP
	field.custom_minimum_size = Vector2(220, 0)
	field.value = int(_amounts.get(key, 0))
	field.value_changed.connect(func(v: int): _amounts[key] = PrizeRules.clamp_amount(v))
	inner.add_child(field)
	return panel


func _on_confirm() -> void:
	if _busy or _unit_id < 1:
		return
	prizes_submitted.emit(_unit_id, PrizeRules.normalize(_amounts, _unit))
	close()


func _on_cancel() -> void:
	if _busy:
		return
	close()
