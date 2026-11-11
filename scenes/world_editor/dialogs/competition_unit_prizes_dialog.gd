extends WeModal
## Division-place awards and one playoff finish, edited together.
signal prizes_submitted(unit_id: int, prize_rules: Dictionary)

var _unit_id := -1
var _unit: Dictionary = {}
var _amounts: Dictionary = {}
var _busy := false
var _hint: Label
var _columns: BoxContainer
var _place_grid: GridContainer
var _fields: Dictionary = {}
var _step_buttons: Array[Button] = []
var _fund_labels: Dictionary = {}
var _total: Label

func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 110
	set_body_separation(14)
	_hint = _text("", 12, WeTokens.TEXT_MUTED)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_body().add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(scroll)
	_columns = BoxContainer.new()
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_columns.add_theme_constant_override("separation", 16)
	scroll.add_child(_columns)
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 12, 14))
	get_body().add_child(summary)
	var line := HBoxContainer.new()
	summary.add_child(line)
	var caption := _text("Общий фонд по настройкам", 13, WeTokens.TEXT_MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(caption)
	_total = _text("", 19, WeTokens.ACCENT)
	line.add_child(_total)
	confirmed.connect(_on_confirm)
	cancelled.connect(_on_cancel)
	get_viewport().size_changed.connect(_layout)
	_layout()

func open_editor(unit: Dictionary) -> void:
	_unit_id = int(unit.get("id", 0))
	_unit = unit.duplicate(true)
	_amounts = PrizeRules.parse_stored(unit.get("prize_rules", {}), _unit)
	set_title("Призовые · %s" % str(unit.get("name", "турнир")))
	set_confirm_text("Сохранить")
	_render()
	_layout()
	clear_error()
	set_busy(false)
	open()

func _layout() -> void:
	var view := get_viewport_rect().size
	var width := minf(1120.0, view.x - 48.0)
	set_card_size(width, minf(680.0, view.y - 56.0))
	if _columns != null:
		_columns.vertical = width < 780.0
	if is_instance_valid(_place_grid):
		_place_grid.columns = 2 if width >= 1040.0 else 1

func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)
	for field in _fields.values():
		field.editable = not busy
	for button in _step_buttons:
		button.disabled = busy

func _render() -> void:
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	_fields.clear()
	_step_buttons.clear()
	_fund_labels.clear()
	_place_grid = null
	var overall := PrizeRules.uses_overall_regular(_unit)
	var divisions := maxi(1, int(_unit.get("divisions_count", 1)))
	_hint.text = "Выплата за место в каждом дивизионе + выплата за итог плей-офф. Все суммы в евро; 0 — без выплаты." if not overall else "Выплата за место в общей таблице + выплата за итог плей-офф. Все суммы в евро; 0 — без выплаты."
	var place_title := "Общая таблица" if overall else "Места в дивизионах"
	var place_note := "%d мест" % PrizeRules.regular_place_count(_unit) if overall else "Одинаковые суммы для каждого из %d дивизионов" % divisions
	var places := _section(place_title, place_note, "places", 1.45)
	_place_grid = GridContainer.new()
	_place_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_place_grid.add_theme_constant_override("h_separation", 10)
	_place_grid.add_theme_constant_override("v_separation", 6)
	places.add_child(_place_grid)
	var playoff: VBoxContainer
	if PrizeRules.playoff_enabled(_unit):
		playoff = _section("Плей-офф", "Одна выплата за конечный результат", "playoff", 1.0)
	for row in PrizeRules.describe_rows(_unit):
		var is_playoff := str(row.key).begins_with("playoff_")
		var target: Container = playoff if is_playoff else _place_grid
		target.add_child(_amount_row(row, is_playoff))
	_update_funds()

func _section(title: String, note: String, key: String, stretch: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.size_flags_stretch_ratio = stretch
	panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 14, 14))
	_columns.add_child(panel)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var stripe := ColorRect.new()
	stripe.color = WeTokens.ACCENT
	stripe.custom_minimum_size = Vector2(3, 20)
	heading.add_child(stripe)
	heading.add_child(_text(title, 15, WeTokens.TEXT))
	box.add_child(_text(note, 11, WeTokens.TEXT_DIM))
	var fund := _text("", 12, WeTokens.ACCENT)
	_fund_labels[key] = fund
	box.add_child(fund)
	var rule := HSeparator.new()
	rule.add_theme_color_override("separator", WeTokens.BORDER)
	box.add_child(rule)
	return box

func _amount_row(row: Dictionary, playoff: bool) -> PanelContainer:
	var key := str(row.key)
	var panel := PanelContainer.new()
	panel.set_meta("prize_key", key)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent := key == PrizeRules.KEY_CHAMPION
	panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.ACCENT_SOFT if accent else WeTokens.SURFACE, WeTokens.BORDER_FOCUS if accent else Color.TRANSPARENT, 9, 7))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	panel.add_child(line)
	var title := _text(str(row.label).replace("Вылет: ", ""), 12, WeTokens.ACCENT if accent else WeTokens.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.custom_minimum_size.x = 98 if playoff else 70
	title.tooltip_text = ("Вылет на стадии: " if key.begins_with("playoff_out_") else "") + str(row.label) + " · " + str(row.hint)
	line.add_child(title)
	for direction in [-1, 0, 1]:
		if direction == 0:
			var field := LineEdit.new()
			field.custom_minimum_size = Vector2(116, 30)
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.expand_to_text_length = false
			field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
			field.text = _money(int(_amounts.get(key, 0)))
			field.tooltip_text = str(row.label) + ": сумма в евро"
			field.add_theme_font_size_override("font_size", 12)
			field.add_theme_color_override("font_color", WeTokens.TEXT)
			field.add_theme_color_override("caret_color", WeTokens.ACCENT)
			field.add_theme_stylebox_override("normal", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 6, 5))
			field.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER_FOCUS, 6, 5))
			field.focus_entered.connect(func(): field.text = str(int(_amounts.get(key, 0))); field.select_all())
			field.focus_exited.connect(_commit_field.bind(key))
			field.text_submitted.connect(func(_v): _commit_field(key); field.release_focus())
			_fields[key] = field
			line.add_child(field)
		else:
			var button := Button.new()
			button.text = "−" if direction < 0 else "+"
			button.custom_minimum_size = Vector2(24, 30)
			button.focus_mode = Control.FOCUS_NONE
			button.add_theme_font_size_override("font_size", 14)
			button.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
			button.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.035), 6))
			button.add_theme_stylebox_override("hover", WeTokens.fill(WeTokens.ACCENT_SOFT, 6))
			button.add_theme_stylebox_override("pressed", WeTokens.fill(WeTokens.ACCENT_SOFT_STRONG, 6))
			button.pressed.connect(func(): _commit_field(key); _set_amount(key, int(_amounts.get(key, 0)) + direction * PrizeRules.AMOUNT_STEP))
			_step_buttons.append(button)
			line.add_child(button)
	return panel

func _commit_field(key: String) -> void:
	var field: LineEdit = _fields[key]
	var raw := field.text.replace(" ", "").replace("\u00a0", "").replace("\u202f", "").strip_edges()
	if raw.is_empty():
		_set_amount(key, 0)
	elif raw.is_valid_int():
		_set_amount(key, PrizeRules.clamp_amount(raw))
	else:
		field.text = _money(int(_amounts.get(key, 0)))

func _set_amount(key: String, value: int) -> void:
	_amounts[key] = PrizeRules.clamp_amount(value)
	_fields[key].text = _money(int(_amounts[key]))
	_update_funds()

func _update_funds() -> void:
	var places := 0
	for place in range(1, PrizeRules.regular_place_count(_unit) + 1):
		places += int(_amounts.get(PrizeRules.regular_key(place), 0))
	var divisions := 1 if PrizeRules.uses_overall_regular(_unit) else maxi(1, int(_unit.get("divisions_count", 1)))
	var playoffs := 0
	if PrizeRules.playoff_enabled(_unit):
		for key in [PrizeRules.KEY_CHAMPION, PrizeRules.KEY_RUNNER_UP]:
			playoffs += int(_amounts.get(key, 0))
		if PrizeRules.has_third_place(_unit):
			playoffs += int(_amounts.get(PrizeRules.KEY_THIRD, 0)) + int(_amounts.get(PrizeRules.KEY_FOURTH, 0))
		for round_no in PrizeRules.playoff_out_rounds(_unit):
			var losers := int(int(_unit.get("teams_playoff", 0)) / pow(2.0, int(round_no)))
			playoffs += losers * int(_amounts.get(PrizeRules.out_key(int(round_no)), 0))
	if _fund_labels.has("places"):
		_fund_labels.places.text = "Фонд: %s €%s" % [_money(places * divisions), " · %s € на дивизион" % _money(places) if divisions > 1 else ""]
	if _fund_labels.has("playoff"):
		_fund_labels.playoff.text = "Фонд: %s €" % _money(playoffs)
	_total.text = _money(places * divisions + playoffs) + " €"

func _money(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += " "
		out += digits[i]
	return out

func _text(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _on_confirm() -> void:
	if _busy or _unit_id < 1:
		return
	for key in _fields:
		_commit_field(str(key))
	prizes_submitted.emit(_unit_id, PrizeRules.normalize(_amounts, _unit))
	close()

func _on_cancel() -> void:
	if not _busy:
		close()
