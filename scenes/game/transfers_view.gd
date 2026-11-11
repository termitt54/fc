class_name TransfersView
extends VBoxContainer
## Completed signings for the hub. One row per arrival, dearest first.
## Seller-side log lines and bids are the same deal written twice, so they stay out.


signal player_requested(player_id: int)
signal club_requested(club_id: int)
signal closed

const PlayerTypesScript := preload("res://game/player_types.gd")
const WeSelectScene := preload("res://ui/components/we_select_field.tscn")

const ALL_SEASONS := 0
const ListPageScript := preload("res://game/list_page.gd")
const ClubHistory = preload("res://game/club_transfer_history.gd")
var _club_id := 0
var _filters := {"direction": "all", "payment": "all", "position": "all", "query": "", "min_fee": 0, "max_fee": 0}
var _stats_host: VBoxContainer
var _club_log: Array = []
var _club_log_size := -1

const COLUMNS := [
	{"key": "season", "label": "Сезон", "width": 88.0, "numeric": true},
	{"key": "player_name", "label": "Игрок", "width": 0.0, "numeric": false},
	{"key": "position", "label": "Поз", "width": 48.0, "numeric": false},
	{"key": "from", "label": "Откуда", "width": 160.0, "numeric": false},
	{"key": "to", "label": "Куда", "width": 160.0, "numeric": false},
	{"key": "fee", "label": "Сумма", "width": 110.0, "numeric": true},
]

var _rows: Array = []
var _page := 0
var _sort_key := "fee"
var _sort_asc := false
var _season_filter := ALL_SEASONS
var _option_ids: Array = []
var _suppress_select := false
var _title_label: Label
var _count_label: Label
var _season_select: WeSelectField
var _header_host: HBoxContainer
var _header_buttons: Dictionary = {}
var _list_host: VBoxContainer
var _scroll: ScrollContainer
var _pager: HBoxContainer
var _page_label: Label
var _page_prev: Button
var _page_next: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_chrome()


func set_club(club_id: int) -> void:
	_club_id = club_id
	_club_log_size = -1
	_sort_key = "season"
	_sort_asc = false
	_title_label.text = "Переходы клуба"
	_build_club_filters()
	refresh()


func _build_club_filters() -> void:
	if _stats_host != null:
		return
	var host := VBoxContainer.new()
	host.add_theme_constant_override("separation", 10)
	add_child(host)
	move_child(host, 1)
	_stats_host = VBoxContainer.new()
	_stats_host.add_theme_constant_override("separation", 8)
	host.add_child(_stats_host)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 10)
	host.add_child(filter_row)
	var search := _filter_input("Игрок или другой клуб", "Поиск по имени игрока и контрагенту")
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(search)
	search.text_changed.connect(func(text: String):
		_filters.query = text
		refresh())
	_add_filter_select(filter_row, "Направление", "direction", [
		{"id": "all", "label": "Все переходы"}, {"id": "in", "label": "Пришли"},
		{"id": "out", "label": "Ушли"}, {"id": "bid", "label": "Отклонённые предложения"}])
	_add_filter_select(filter_row, "Оплата", "payment", [
		{"id": "all", "label": "Любая сумма"}, {"id": "paid", "label": "За деньги"}, {"id": "free", "label": "Без оплаты"}])
	var positions: Array = [{"id": "all", "label": "Все позиции"}]
	for position in PlayerTypesScript.POSITIONS:
		positions.append({"id": position, "label": PlayerTypesScript.position_label(position)})
	_add_filter_select(filter_row, "Позиция", "position", positions)
	var amounts := HBoxContainer.new()
	amounts.add_theme_constant_override("separation", 10)
	host.add_child(amounts)
	for key in ["min_fee", "max_fee"]:
		var field := _filter_input("Сумма от, €" if key == "min_fee" else "Сумма до, €", "Полная сумма в евро; пустое поле снимает границу")
		field.custom_minimum_size.x = 180
		amounts.add_child(field)
		field.text_changed.connect(func(text: String):
			var numeric := text.replace(" ", "").replace("€", "").strip_edges()
			_filters[key] = maxi(0, int(numeric)) if numeric.is_valid_int() else 0
			refresh())
	var hint := Label.new()
	hint.text = "Сводка учитывает выбранные фильтры. Предложения не входят в доходы и расходы."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	amounts.add_child(hint)
	var reset := _page_button("Сбросить")
	reset.pressed.connect(func():
		_season_filter = ALL_SEASONS
		_option_ids = []
		_filters = {"direction": "all", "payment": "all", "position": "all", "query": "", "min_fee": 0, "max_fee": 0}
		_stats_host = null
		remove_child(host)
		host.queue_free()
		_build_club_filters()
		refresh())
	amounts.add_child(reset)


func _filter_input(placeholder: String, hint: String) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.tooltip_text = hint
	field.custom_minimum_size = Vector2(180, 36)
	field.add_theme_stylebox_override("normal", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 8))
	field.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.INSET, WeTokens.ACCENT, WeTokens.RADIUS_SM, 8))
	field.add_theme_color_override("font_color", WeTokens.TEXT)
	field.add_theme_font_size_override("font_size", 13)
	return field


func _add_filter_select(host: HBoxContainer, title: String, key: String, items: Array) -> void:
	var select := WeSelectScene.instantiate() as WeSelectField
	select.label = title
	select.compact = true
	select.custom_minimum_size.x = 190 if key == "direction" else 160
	host.add_child(select)
	select.set_items(items, "all")
	select.item_selected.connect(func(_index: int):
		_filters[key] = str(select.selected_id)
		refresh())


func _refresh_stats() -> void:
	if _stats_host == null:
		return
	for child in _stats_host.get_children():
		child.free()
	var stats := ClubHistory.summary(_rows)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 10)
	_stats_host.add_child(grid)
	for item in [["Пришли", str(stats.incoming)], ["Ушли", str(stats.outgoing)],
		["Потрачено", _format_fee(stats.spent)], ["Получено", _format_fee(stats.earned)],
		["Баланс", ("−" if stats.balance < 0 else "+") + _format_fee(absi(stats.balance))],
		["Платные покупки", "%.1f%%" % stats.paid_percent]]:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 12))
		grid.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 5)
		card.add_child(box)
		var caption := Label.new()
		caption.text = item[0]
		caption.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		caption.add_theme_font_size_override("font_size", 12)
		box.add_child(caption)
		var value := Label.new()
		value.text = item[1]
		value.add_theme_color_override("font_color", WeTokens.ACCENT)
		value.add_theme_font_size_override("font_size", 21)
		box.add_child(value)
	var records := Label.new()
	records.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	records.text = "Рекорд покупки: %s     ·     Рекорд продажи: %s     ·     Средняя платная покупка: %s     ·     Предложений: %d" % [_format_fee(stats.record_purchase), _format_fee(stats.record_sale), _format_fee(int(stats.average_purchase)), stats.bids]
	records.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	records.add_theme_font_size_override("font_size", 12)
	_stats_host.add_child(records)


func is_open() -> bool:
	return visible


func refresh() -> void:
	var log: Array = GameSession.transfer_log
	if _club_id > 0:
		# Scope once when the journal changes: filtering must not rescan the world.
		if _club_log_size != log.size():
			_club_log = []
			for entry in log:
				if typeof(entry) == TYPE_DICTIONARY and int(entry.get("club_id", 0)) == _club_id:
					_club_log.append(entry)
			_club_log_size = log.size()
		log = _club_log
	_sync_season_filter(_season_options(log, int(GameSession.season_number), _club_id))
	if _club_id > 0:
		_filters["season"] = _season_filter
		_rows = ClubHistory.rows(log, _club_id, _filters)
		_refresh_stats()
	else:
		_rows = deal_rows(log, _season_filter)
	_page = 0
	sort_deals(_rows, _sort_key, _sort_asc)
	_rebuild_header()
	_rebuild_list()


static func deal_rows(log: Array, season: int) -> Array:
	var rows: Array = []
	for entry in log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("direction", "")) != "in":
			continue
		var entry_season := int(entry.get("season", 0))
		if season > ALL_SEASONS and entry_season != season:
			continue
		var origin := str(entry.get("other_club", "")).strip_edges()
		if origin.is_empty():
			origin = "—"
		var destination := str(entry.get("club_name", "")).strip_edges()
		if destination.is_empty():
			destination = "—"
		rows.append({
			"season": entry_season,
			"day": int(entry.get("day", 0)),
			"player_id": int(entry.get("player_id", 0)),
			"player_name": str(entry.get("player_name", "Игрок")),
			"position": str(entry.get("position", "")),
			"from": origin,
			"to": destination,
			"club_id": int(entry.get("club_id", 0)),
			"fee": maxi(0, int(entry.get("fee", 0))),
		})
	return rows


static func sort_deals(rows: Array, key: String, ascending: bool) -> void:
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cmp := _compare(a, b, key)
		if cmp == 0:
			cmp = int(b.get("fee", 0)) - int(a.get("fee", 0))
		if cmp == 0:
			cmp = str(a.get("player_name", "")).nocasecmp_to(str(b.get("player_name", "")))
		if cmp == 0:
			return int(a.get("player_id", 0)) < int(b.get("player_id", 0))
		return cmp < 0 if ascending else cmp > 0
	)


static func _compare(a: Dictionary, b: Dictionary, key: String) -> int:
	var left: Variant = a.get(key, "")
	var right: Variant = b.get(key, "")
	if typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT \
		or typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT:
		var ln := float(left)
		var rn := float(right)
		if ln < rn:
			return -1
		if ln > rn:
			return 1
		return 0
	return str(left).nocasecmp_to(str(right))


static func _season_options(log: Array, current_season: int, club_id: int = 0) -> Array:
	var seen := {}
	if current_season > 0:
		seen[current_season] = true
	for entry in log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if club_id > 0 and int(entry.get("club_id", 0)) != club_id:
			continue
		if club_id == 0 and str(entry.get("direction", "")) != "in":
			continue
		var season := int(entry.get("season", 0))
		if season > 0:
			seen[season] = true
	var seasons: Array = seen.keys()
	seasons.sort()
	seasons.reverse()
	var options: Array = [{"id": ALL_SEASONS, "label": "Все сезоны"}]
	for season in seasons:
		options.append({"id": int(season), "label": "Сезон %d" % int(season)})
	return options


func _build_chrome() -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	add_child(title_row)

	var back := Button.new()
	back.text = "← Назад"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 34)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.05), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.1), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.08), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_color_override("font_color", WeTokens.TEXT)
	back.add_theme_font_size_override("font_size", 13)
	back.pressed.connect(func(): closed.emit())
	title_row.add_child(back)

	_title_label = Label.new()
	_title_label.text = "Трансферы"
	_title_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_title_label.add_theme_font_size_override("font_size", 18)
	var title_font := WeTokens.font_semibold()
	if title_font != null:
		_title_label.add_theme_font_override("font", title_font)
	title_row.add_child(_title_label)

	_season_select = WeSelectScene.instantiate() as WeSelectField
	_season_select.label = "Сезон"
	_season_select.compact = true
	_season_select.custom_minimum_size = Vector2(220, 0)
	_season_select.item_selected.connect(_on_season_selected)
	title_row.add_child(_season_select)

	_count_label = Label.new()
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_count_label.add_theme_font_size_override("font_size", 12)
	title_row.add_child(_count_label)

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)

	var header_wrap := PanelContainer.new()
	header_wrap.add_theme_stylebox_override("panel", WeTokens.fill(Color(0, 0, 0, 0.22), 0, 8, 6))
	box.add_child(header_wrap)
	_header_host = HBoxContainer.new()
	_header_host.add_theme_constant_override("separation", 10)
	header_wrap.add_child(_header_host)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)

	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.add_theme_constant_override("separation", 0)
	_scroll.add_child(_list_host)
	_build_pager(box)


func _sync_season_filter(options: Array) -> void:
	var ids: Array = []
	for item in options:
		ids.append(int(item.get("id", 0)))
	var keep := _season_filter if ids.has(_season_filter) else ALL_SEASONS
	if ids == _option_ids and keep == _season_filter:
		return
	_season_filter = keep
	_option_ids = ids
	_suppress_select = true
	_season_select.set_items(options, _season_filter)
	_suppress_select = false


func _on_season_selected(_index: int) -> void:
	if _suppress_select or _season_select == null:
		return
	var selected: Variant = _season_select.selected_id
	var season := ALL_SEASONS if selected == null else int(selected)
	if season == _season_filter:
		return
	_season_filter = season
	refresh()


func _rebuild_header() -> void:
	if _header_buttons.is_empty():
		for column in COLUMNS:
			var key := str(column["key"])
			var button := Button.new()
			button.flat = true
			button.focus_mode = Control.FOCUS_NONE
			button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			button.add_theme_font_size_override("font_size", 12)
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			_apply_col_size(button, float(column["width"]))
			button.pressed.connect(_on_sort_pressed.bind(key))
			_header_host.add_child(button)
			_header_buttons[key] = button
	for column in COLUMNS:
		var key := str(column["key"])
		var button: Button = _header_buttons[key]
		var label := str(column["label"])
		if key == _sort_key:
			label = "%s %s" % [label, "▲" if _sort_asc else "▼"]
		button.text = label
		button.add_theme_color_override(
			"font_color",
			WeTokens.ACCENT if key == _sort_key else WeTokens.TEXT_DIM
		)
		button.add_theme_color_override("font_hover_color", WeTokens.TEXT)


func _on_sort_pressed(key: String) -> void:
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = key != "fee" and key != "season"
	_page = 0
	sort_deals(_rows, _sort_key, _sort_asc)
	_rebuild_header()
	_rebuild_list()


func _rebuild_list() -> void:
	for child in _list_host.get_children():
		child.free()
	_count_label.text = _count_text(_rows.size())
	_page = ListPageScript.clamp_index(_page, _rows.size())
	_update_pager()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "В этом сезоне трансферов не было." if _season_filter > ALL_SEASONS else "Трансферов ещё не было."
		if _club_id > 0:
			empty.text = "По выбранным фильтрам записей не найдено."
		empty.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 13)
		_list_host.add_child(empty)
		return
	var window := ListPageScript.slice_of(_rows, _page)
	for i in window.size():
		_list_host.add_child(_make_row(window[i], i % 2 == 1))
	if _scroll != null:
		_scroll.scroll_vertical = 0


func _build_pager(parent: VBoxContainer) -> void:
	_pager = HBoxContainer.new()
	_pager.add_theme_constant_override("separation", 8)
	_pager.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(_pager)

	_page_prev = _page_button("←")
	_page_prev.pressed.connect(_on_page_pressed.bind(-1))
	_pager.add_child(_page_prev)

	_page_label = Label.new()
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.custom_minimum_size = Vector2(140, 0)
	_page_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_page_label.add_theme_font_size_override("font_size", 12)
	_pager.add_child(_page_label)

	_page_next = _page_button("→")
	_page_next.pressed.connect(_on_page_pressed.bind(1))
	_pager.add_child(_page_next)
	_pager.visible = false


func _page_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(36, 28)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.05), WeTokens.RADIUS_SM, 8, 4))
	button.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.1), WeTokens.RADIUS_SM, 8, 4))
	button.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.08), WeTokens.RADIUS_SM, 8, 4))
	button.add_theme_stylebox_override("disabled", WeTokens.fill(Color(1, 1, 1, 0.02), WeTokens.RADIUS_SM, 8, 4))
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
	button.add_theme_font_size_override("font_size", 14)
	return button


func _update_pager() -> void:
	if _pager == null:
		return
	var total := _rows.size()
	var pages := ListPageScript.count(total)
	_pager.visible = total > ListPageScript.SIZE
	_page_label.text = ListPageScript.label(_page, total)
	_page_prev.disabled = _page <= 0
	_page_next.disabled = _page >= pages - 1


func _on_page_pressed(step: int) -> void:
	var next := ListPageScript.clamp_index(_page + step, _rows.size())
	if next == _page:
		return
	_page = next
	_rebuild_list()


func _make_row(row: Dictionary, zebra: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.fill(Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0), 0, 8, 5)
	)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	panel.add_child(cols)

	cols.add_child(_text_cell("Сезон %d" % int(row.get("season", 0)), 88.0, WeTokens.TEXT_MUTED))
	var direction := str(row.get("direction", ""))
	var prefix := {"in": "↙  ", "out": "↗  ", "bid": "↔  "}.get(direction, "") as String
	var player_cell := _link_cell(
		prefix + str(row.get("player_name", "Игрок")),
		0.0,
		func(): player_requested.emit(int(row.get("player_id", 0)))
	)
	if not direction.is_empty():
		player_cell.add_theme_color_override("font_color", WeTokens.SUCCESS if direction == "in" else (WeTokens.DANGER if direction == "out" else WeTokens.TEXT_DIM))
		player_cell.tooltip_text = {"in": "Пришёл", "out": "Ушёл", "bid": "Предложение не состоялось"}.get(direction, "") + " · день %d" % int(row.get("day", 0))
	cols.add_child(player_cell)
	cols.add_child(_text_cell(_position_text(str(row.get("position", ""))), 48.0, WeTokens.TEXT_MUTED))
	cols.add_child(_text_cell(str(row.get("from", "—")), 160.0, WeTokens.TEXT))
	var club_id := int(row.get("to_club_id", row.get("club_id", 0)))
	if club_id > 0:
		cols.add_child(_link_cell(str(row.get("to", "—")), 160.0, func(): club_requested.emit(club_id)))
	else:
		cols.add_child(_text_cell(str(row.get("to", "—")), 160.0, WeTokens.TEXT))
	var fee := int(row.get("fee", 0))
	cols.add_child(_text_cell(
		"бесплатно" if fee <= 0 else _format_fee(fee),
		110.0,
		WeTokens.TEXT_DIM if fee <= 0 else WeTokens.ACCENT
	))
	return panel


func _link_cell(text: String, width: float, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_color_override("font_hover_color", WeTokens.ACCENT)
	_apply_col_size(button, width)
	button.pressed.connect(on_press)
	return button


func _text_cell(text: String, width: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	_apply_col_size(label, width)
	return label


func _apply_col_size(control: Control, width: float) -> void:
	if width <= 0.0:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		return
	control.custom_minimum_size = Vector2(width, 0)
	control.size_flags_horizontal = Control.SIZE_SHRINK_END


func _position_text(code: String) -> String:
	if code.is_empty():
		return "—"
	return PlayerTypesScript.position_label(code)


func _count_text(count: int) -> String:
	if _club_id > 0:
		return "Записей: %d" % count
	var mod10 := count % 10
	var mod100 := count % 100
	var word := "трансферов"
	if mod10 == 1 and mod100 != 11:
		word = "трансфер"
	elif mod10 >= 2 and mod10 <= 4 and (mod100 < 12 or mod100 > 14):
		word = "трансфера"
	if _season_filter > ALL_SEASONS:
		return "%d %s · сезон %d" % [count, word, _season_filter]
	return "%d %s" % [count, word]


func _format_fee(amount: int) -> String:
	var value := absi(amount)
	if value >= 1_000_000:
		var millions := float(value) / 1_000_000.0
		if is_equal_approx(millions, round(millions)):
			return "%dM €" % int(round(millions))
		return "%.1fM €" % millions
	if value >= 1000:
		var thousands := float(value) / 1000.0
		if is_equal_approx(thousands, round(thousands)):
			return "%dK €" % int(round(thousands))
		return "%.1fK €" % thousands
	return "%d €" % value
