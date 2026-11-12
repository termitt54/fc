extends WeModal
## Read-only, lazy tabs: no old editions are retained by the simulation.

var _unit: Dictionary = {}
var _tabs: TabContainer
var _make_card: Callable
var _apply_card: Callable
var _render_table: Callable
var _make_logo: Callable
var _series: Dictionary = {}
var _page := 0
var _calendar: VBoxContainer
var _calendar_rows: Array = []
const PAGE_SIZE := 100

func _ready() -> void:
	super._ready()
	cancelled.connect(close)
	confirmed.connect(close)
	closed.connect(queue_free)
	_confirm_button.hide()
	set_cancel_text("Закрыть")

func show_season(unit: Dictionary, season: int, make_card: Callable, apply_card: Callable, render_table: Callable = Callable(), make_logo: Callable = Callable()) -> void:
	_unit = unit
	_make_card = make_card
	_apply_card = apply_card
	_render_table = render_table
	_make_logo = make_logo
	var area := get_viewport_rect().size
	set_card_size(maxf(640, area.x * 0.94), maxf(440, area.y * 0.9))
	set_title("%s · Сезон %d" % [str(unit.get("label", unit.get("name", "Турнир"))), season])
	_tabs = TabContainer.new()
	_tabs.tabs_visible = false
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var navigation := WeTabBar.new()
	get_body().add_child(navigation)
	navigation.set_tabs(PackedStringArray(["Таблицы", "Статистика", "Плей-офф", "Матчи"]))
	navigation.tab_selected.connect(func(index): _tabs.current_tab = index)
	get_body().add_child(_tabs)
	for title in ["Таблицы", "Статистика", "Плей-офф", "Матчи"]:
		var page := VBoxContainer.new()
		page.name = title
		_tabs.add_child(page)
	_tabs.tab_changed.connect(_show_tab)
	open()
	_show_tab(0)

func show_series(unit: Dictionary, series: Dictionary, make_logo: Callable = Callable()) -> void:
	_unit = unit
	_series = series
	_make_logo = make_logo
	_calendar_rows = TournamentHistory.series_matches(unit, series)
	set_card_size(minf(1080, get_viewport_rect().size.x * 0.94), minf(300 + _calendar_rows.size() * 76, get_viewport_rect().size.y * 0.88))
	set_title("Плей-офф · Результаты матчей")
	_series_summary(series)
	_calendar = VBoxContainer.new()
	_calendar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	get_body().add_child(_calendar)
	_render_matches()
	open()

func _show_tab(index: int) -> void:
	var page: VBoxContainer = _tabs.get_child(index)
	if page.get_child_count() > 0:
		return
	if bool(_unit.get("archive_missing", false)):
		var hint := Label.new()
		hint.text = str(_unit.get("archive_error", "Подробные данные этого сезона не были сохранены старой версией игры. Доступны только итоговые места."))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		page.add_child(hint)
		_show_places(page)
		return
	if _unit.has("cup_state") and index in [0, 2]:
		if index == 2:
			_calendar = page
			_calendar_rows = _unit.get("matches", []).duplicate(false)
			_render_matches()
		else:
			var scroll := ScrollContainer.new()
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			page.add_child(scroll)
			var content := VBoxContainer.new()
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			scroll.add_child(content)
			for stage in _unit["cup_state"].get("stages", []):
				_message(content, str(stage["name"]))
				var group := 0
				for table in CupCompetition.group_tables(stage):
					group += 1
					_message(content, "Группа %d" % group)
					for row in table:
						var id := int(row["club_id"])
						var identity: Dictionary = _unit.get("clubs_by_id", {}).get(id, _unit.get("clubs_by_id", {}).get(str(id), {}))
						_message(content, "%s — %d · %d:%d" % [identity.get("name", str(id)), int(row["points"]), int(row["goals_for"]), int(row["goals_against"])])
				for id in stage.get("outputs", []):
					var identity: Dictionary = _unit.get("clubs_by_id", {}).get(int(id), _unit.get("clubs_by_id", {}).get(str(id), {}))
					_message(content, "Прошёл дальше: " + str(identity.get("name", id)))
		return
	match index:
		0: _tables(page)
		1: _statistics(page)
		2:
			var playoff: Dictionary = _unit.get("playoff", {})
			if not bool(playoff.get("enabled", false)):
				_message(page, "В этом сезоне плей-офф не проводился.")
				return
			var bracket := PlayoffBracketView.new()
			bracket.setup(_unit, playoff, _make_card, _apply_card)
			page.add_child(bracket)
		3:
			_calendar = page
			_calendar_rows = _unit.get("matches", []).duplicate(false)
			_calendar_rows.sort_custom(func(a, b): return int(a.get("season_day", 0)) < int(b.get("season_day", 0)))
			_render_matches()

func _message(host: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	host.add_child(label)

func _grid(host: Control) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2 if get_viewport_rect().size.x >= 1150 else 1
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	return grid

func _history_card(host: Node, title: String = "") -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("history_board", true)
	panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 12, 14))
	host.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	if not title.is_empty():
		box.add_child(_label(title, 14, WeTokens.TEXT))
	return box

func _label(text: String, font_size: int = 13, color: Color = WeTokens.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _logo(id: int, edge: int = 24) -> Control:
	if _make_logo.is_valid():
		var logo: Control = _make_logo.call(id, edge)
		if not logo is ColorRect:
			return logo
		logo.free()
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(edge, edge)
	badge.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT, 8, 2, 2))
	var mark := _label(GameSession.club_name(_unit, id, true).left(2).to_upper(), 12, WeTokens.ACCENT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(mark)
	return badge

func _team(host: Node, id: int, mirrored: bool = false, edge: int = 24) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	host.add_child(row)
	var name := _label(GameSession.club_name(_unit, id, false), 14)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if mirrored:
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(name)
		row.add_child(_logo(id, edge))
	else:
		row.add_child(_logo(id, edge))
		row.add_child(name)

func _series_summary(series: Dictionary) -> void:
	var box := _history_card(get_body())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	box.add_child(row)
	_team(row, int(series.get("home_id", 0)), true, 40)
	var middle := VBoxContainer.new()
	middle.custom_minimum_size.x = 180
	row.add_child(middle)
	var format := str(_unit.get("playoff", {}).get("format", ""))
	var goals := format != PlayoffRules.FORMAT_BEST_OF
	var home := int(series.get("home_goals" if goals else "home_wins", 0))
	var away := int(series.get("away_goals" if goals else "away_wins", 0))
	var score := _label("%d : %d" % [home, away] if int(series.get("games_played", 0)) > 0 else "— : —", 30, WeTokens.ACCENT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(score)
	var caption := "Победы в серии" if not goals else ("Сумма голов" if format == PlayoffRules.FORMAT_TWO_LEGGED else "Счёт матча")
	var subtitle := _label(caption, 11, WeTokens.TEXT_MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(subtitle)
	_team(row, int(series.get("away_id", 0)), false, 40)
	var description := PlayoffRules.format_label(format)
	if format == PlayoffRules.FORMAT_BEST_OF:
		description = "До %d побед" % int(_unit.get("playoff", {}).get("series_wins", 3))
	description += " · Завершено" if bool(series.get("complete", false)) else " · Не завершено"
	var status := _label(description, 12, WeTokens.TEXT_MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)

func _tables(host: Control) -> void:
	if _unit.get("standings", []).is_empty():
		_message(host, "В этом турнире нет группового или регулярного этапа.")
		return
	var grid := _grid(host)
	var groups: Array = _unit.get("divisions", []).duplicate(false)
	if groups.size() > 1 and bool(_unit.get("rules", {}).get("regular_season_enabled", false)):
		groups.append({"index": -1})
	for group in groups:
		var index := int(group.get("index", 0))
		var title := ("Группа %d" if NationalTeams.is_unit(_unit) else "Дивизион %d") % (index + 1)
		if index == -1:
			title = "Общая таблица"
		if _render_table.is_valid():
			var card: Control = _render_table.call("table", _unit, {"index": index, "title": title}, 0, 0)
			card.set_meta("history_board", true)
			grid.add_child(card)
	if groups.is_empty():
		_message(grid, "Турнирные таблицы не сохранились.")

func _statistics(host: Control) -> void:
	var grid := _grid(host)
	for board in UnitSeasonStats.BOARDS:
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(block)
		_stats_page(block, board, 0)

func _stats_page(host: VBoxContainer, board: Dictionary, offset: int) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	if not _render_table.is_valid():
		return
	var count := UnitSeasonStats.leaders(_unit, str(board["field"]), 1000000).size()
	var card: Control = _render_table.call("stats", _unit, board, offset, 12)
	card.set_meta("history_board", true)
	host.add_child(card)
	if count > 12:
		var controls := HBoxContainer.new()
		host.add_child(controls)
		_page_button(controls, "←", offset == 0, func(): _stats_page(host, board, offset - 12))
		controls.add_child(_label("%d–%d из %d" % [offset + 1, mini(offset + 12, count), count], 12, WeTokens.TEXT_MUTED))
		_page_button(controls, "→", offset + 12 >= count, func(): _stats_page(host, board, offset + 12))

func _show_places(host: Node) -> void:
	for entry in _unit.get("winners", []):
		for section in ["playoff", "regular"]:
			var rows: Array = entry.get(section, [])
			if section == "playoff" and not entry.has("playoff") and int(entry.get("club_id", 0)) > 0:
				rows = [{"place": 1, "club_name": entry.get("club_name", "Победитель")}]
			if rows.is_empty():
				continue
			var box := _history_card(host, "Плей-офф" if section == "playoff" else "Регулярный сезон")
			for row in rows:
				var line := HBoxContainer.new()
				box.add_child(line)
				line.add_child(_label(str(row.get("place", 0)), 14, WeTokens.ACCENT))
				line.add_child(_label(str(row.get("club_name", "—")), 14))

func _render_matches() -> void:
	for child in _calendar.get_children():
		_calendar.remove_child(child)
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_calendar.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	list.set_meta("history_board", true)
	if _calendar_rows.is_empty():
		_message(list, "Матчи пока не назначены")
	for match_row in _calendar_rows.slice(_page * PAGE_SIZE, (_page + 1) * PAGE_SIZE):
		_match_card(list, match_row)
	if _calendar_rows.size() <= PAGE_SIZE:
		return
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 12)
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	_calendar.add_child(controls)
	_page_button(controls, "←", _page == 0, func(): _page -= 1; _render_matches())
	controls.add_child(_label("%d–%d из %d" % [_page * PAGE_SIZE + 1, mini((_page + 1) * PAGE_SIZE, _calendar_rows.size()), _calendar_rows.size()], 12, WeTokens.TEXT_MUTED))
	_page_button(controls, "→", (_page + 1) * PAGE_SIZE >= _calendar_rows.size(), func(): _page += 1; _render_matches())

func _page_button(host: Node, text: String, disabled: bool, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.disabled = disabled
	button.custom_minimum_size = Vector2(34, 30)
	button.add_theme_stylebox_override("normal", WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 8, 6))
	button.add_theme_stylebox_override("hover", WeTokens.panel(WeTokens.SURFACE_RAISED, WeTokens.ACCENT, 8, 6))
	button.add_theme_stylebox_override("pressed", WeTokens.fill(WeTokens.ACCENT_SOFT, 8, 6, 6))
	button.add_theme_stylebox_override("disabled", WeTokens.fill(Color(1, 1, 1, 0.02), 8, 6, 6))
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.pressed.connect(action)
	host.add_child(button)

func _match_card(host: Node, match_row: Dictionary) -> void:
	var box := _history_card(host)
	box.add_theme_constant_override("separation", 6)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	box.add_child(line)
	var day := _label("ДЕНЬ %d" % int(match_row.get("season_day", 0)), 11, WeTokens.TEXT_MUTED)
	day.custom_minimum_size.x = 68
	line.add_child(day)
	_team(line, int(match_row.get("home_id", 0)), true)
	var center := VBoxContainer.new()
	center.custom_minimum_size.x = 130
	line.add_child(center)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT if bool(match_row.get("played", false)) else Color(1, 1, 1, 0.04), 8, 14, 5))
	center.add_child(chip)
	var score := _label("%d : %d" % [int(match_row.get("home_goals", 0)), int(match_row.get("away_goals", 0))] if bool(match_row.get("played", false)) else "— : —", 19, WeTokens.ACCENT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.tooltip_text = TournamentHistory.score(match_row)
	chip.add_child(score)
	var shootout: Dictionary = match_row.get("shootout", match_row.get("report", {}).get("shootout", {}))
	if not shootout.is_empty() or bool(match_row.get("extra_time", false)):
		var note := "Пенальти %d : %d" % [int(shootout.get("home", 0)), int(shootout.get("away", 0))] if not shootout.is_empty() else "Доп. время"
		var extra := _label(note, 11, WeTokens.TEXT_MUTED)
		extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(extra)
	_team(line, int(match_row.get("away_id", 0)))
	var stage := "Плей-офф" if str(match_row.get("stage", "")) == "PLAYOFF" else ("Групповой этап" if NationalTeams.is_unit(_unit) else "Регулярный сезон")
	if match_row.has("cup_stage"):
		stage = str(match_row["cup_stage"])
	if bool(match_row.get("is_third_place", false)):
		stage = "Матч за 3-е место"
	var caption := _label(stage, 11, WeTokens.TEXT_MUTED)
	caption.custom_minimum_size.x = 115
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(caption)
