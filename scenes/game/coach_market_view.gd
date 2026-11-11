extends VBoxContainer
## Paginated coach directory and appointment journal, using the hub's theme.
signal closed
signal coach_requested(coach_id: int)
signal club_requested(club_id: int)

const PAGE_SIZE := 50
var _filter: WeTabBar
var _search: WeTextField
var _list: VBoxContainer
var _columns: VBoxContainer
var _count: Label
var _previous: WeButton
var _next: WeButton
var logo_builder: Callable
var _page_label: Label
var _page := 0
var _rows: Array = []

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 12, 16))
	add_child(top)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	top.add_child(header)
	var back := WeButton.new()
	back.text = "← Назад"
	back.pressed.connect(func(): closed.emit())
	header.add_child(back)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("Тренеры", 21, WeTokens.TEXT))
	titles.add_child(_label("Главные тренеры клубов и сборных · Карьера и назначения", 12, WeTokens.TEXT_MUTED))
	_count = _label("", 13, WeTokens.ACCENT)
	_count.custom_minimum_size.x = 105
	header.add_child(_count)
	_search = preload("res://ui/components/we_text_field.tscn").instantiate()
	_search.label = "Поиск"
	_search.placeholder = "Имя тренера или команда"
	_search.compact = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.x = 240
	_search.text_changed.connect(func(_text: String): _page = 0; refresh())
	header.add_child(_search)
	_filter = WeTabBar.new()
	add_child(_filter)
	_filter.set_tabs(PackedStringArray(["Свободные", "Клубы и сборные", "Завершили карьеру", "Назначения и увольнения"]))
	_filter.tab_selected.connect(func(_index: int): _page = 0; refresh())
	var panel := PanelContainer.new()
	panel.clip_contents = true
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 12, 1))
	add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 0)
	panel.add_child(body)
	_columns = VBoxContainer.new()
	body.add_child(_columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 0)
	scroll.add_child(_list)
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(footer)
	_previous = WeButton.new()
	_previous.text = "←"
	_previous.pressed.connect(func(): _page = maxi(0, _page - 1); refresh())
	footer.add_child(_previous)
	_page_label = Label.new()
	footer.add_child(_page_label)
	_next = WeButton.new()
	_next.text = "→"
	_next.pressed.connect(func(): _page = mini(maxi(0, (_rows.size() - 1) / PAGE_SIZE), _page + 1); refresh())
	footer.add_child(_next)

func refresh() -> void:
	if _list == null:
		return
	CoachMarket.ensure(GameSession)
	_rows = []
	var mode := _filter.get_current()
	var coaches: Array = []
	match mode:
		0: coaches = GameSession.coach_market["free"].duplicate()
		1:
			coaches = GameSession.coaches_by_club.values()
			for team in GameSession.national_teams.values():
				coaches.append(team["coach"])
		2: coaches = GameSession.coach_market["retired"].duplicate()
		3: coaches = GameSession.coach_market["events"].duplicate()
	var clubs := CoachMarket.clubs_of(GameSession)
	var query := _search.text.strip_edges().to_lower()
	if mode == 3 and query.is_empty():
		_rows = coaches
		coaches = []
	for coach in coaches:
		var cid := int(coach.get("club_id", 0))
		var national_id := int(coach.get("national_team_id", 0))
		var club_name := str(coach.get("club_name", clubs.get(cid, {}).get("name", "Без клуба")))
		if national_id > 0:
			club_name = "Сборная " + str((GameSession.national_teams.get(national_id, {}) as Dictionary).get("country", {}).get("name", ""))
		var name := str(coach.get("coach_name", coach.get("name", "")))
		if query.is_empty() or (name + " " + club_name).to_lower().contains(query):
			_rows.append({"coach": coach, "name": name, "club": club_name})
	if mode == 3:
		_rows.reverse()
	else:
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["coach"].get("current_ability", 0)) > int(b["coach"].get("current_ability", 0)))
	_page = clampi(_page, 0, maxi(0, int((_rows.size() - 1) / PAGE_SIZE)))
	for host in [_columns, _list]:
		for child in host.get_children():
			host.remove_child(child)
			child.queue_free()
	_header(mode)
	var start := _page * PAGE_SIZE
	for i in range(start, mini(start + PAGE_SIZE, _rows.size())):
		var row: Dictionary = _rows[i]
		var coach: Dictionary = row.get("coach", row)
		if mode == 3 and not row.has("coach"):
			row = {"name": coach.get("coach_name", ""), "club": coach.get("club_name", "")}
		_coach_row(row, coach, mode)
	if _rows.is_empty():
		var empty := _line(_list)
		empty.add_child(_label("По выбранным условиям ничего не найдено", 14, WeTokens.TEXT_MUTED))
	_count.text = "%d %s" % [_rows.size(), "событий" if mode == 3 else "тренеров"]
	_page_label.text = "%d–%d из %d" % [start + 1 if not _rows.is_empty() else 0, mini(start + PAGE_SIZE, _rows.size()), _rows.size()]
	_previous.disabled = _page == 0
	_next.disabled = start + PAGE_SIZE >= _rows.size()

func _label(text: String, font_size: int = 13, color: Color = WeTokens.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	return label

func _line(host: Node, header: bool = false) -> HBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := WeTokens.fill(Color(0, 0, 0, 0.13) if header else Color(0, 0, 0, 0), 0, 14, 10 if not header else 8)
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.05)
	panel.add_theme_stylebox_override("panel", style)
	host.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	return row

func _cell(text: String, width: int, color: Color = WeTokens.TEXT_MUTED) -> Label:
	var label := _label(text, 13, color)
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _header(mode: int) -> void:
	var row := _line(_columns, true)
	for title in ["Тренер", "Команда"]:
		var label := _label(title, 12, WeTokens.TEXT_DIM)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = 1.3 if title == "Тренер" else 1.0
		label.custom_minimum_size.x = 44 if title == "Тренер" else 32
		row.add_child(label)
	var titles := ["Возраст", "CA", "Репутация", "Зарплата/сез", "Контракт", "Характер игры"] if mode != 3 else ["Сезон", "День", "Событие"]
	var widths := [60, 60, 90, 120, 90, 160] if mode != 3 else [80, 70, 240]
	for i in titles.size():
		row.add_child(_cell(str(titles[i]), int(widths[i]), WeTokens.TEXT_DIM))

func _link(text: String, action: Callable) -> WeButton:
	var button := WeButton.new()
	button.kind = WeButton.Kind.LINK
	button.text = text
	button.tooltip_text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(action)
	return button

func _coach_row(data: Dictionary, coach: Dictionary, mode: int) -> void:
	var row := _line(_list)
	var coach_id := int(coach.get("coach_id", coach.get("id", 0)))
	var name := HBoxContainer.new()
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.size_flags_stretch_ratio = 1.3
	name.add_theme_constant_override("separation", 10)
	row.add_child(name)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(34, 34)
	avatar.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT, 9, 4, 4))
	var initials := _cell(str(data.get("name", "")).left(1), 20, WeTokens.ACCENT)
	avatar.add_child(initials)
	name.add_child(avatar)
	name.add_child(_link(str(data.get("name", "Тренер")), func(): coach_requested.emit(coach_id)))
	var employer := HBoxContainer.new()
	employer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	employer.custom_minimum_size.x = 32
	employer.add_theme_constant_override("separation", 8)
	row.add_child(employer)
	var national_id := int(coach.get("national_team_id", 0))
	var club_id := NationalTeams.team_id(national_id) if national_id > 0 else int(coach.get("club_id", 0))
	if club_id > 0:
		if logo_builder.is_valid():
			var logo: Control = logo_builder.call(club_id, 24)
			if logo is ColorRect:
				logo.free()
				var badge := PanelContainer.new()
				badge.custom_minimum_size = Vector2(24, 24)
				badge.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT, 6, 2, 2))
				badge.add_child(_cell(str(data.get("club", "")).left(2), 20, WeTokens.ACCENT))
				logo = badge
			employer.add_child(logo)
		employer.add_child(_link(str(data.get("club", "—")), func(): club_requested.emit(club_id)))
	else:
		var status_text := str(data.get("club", "—")) if mode == 3 else ("Завершил карьеру" if mode == 2 else "Свободный агент")
		var status := _label(status_text, 13, WeTokens.TEXT_MUTED if mode == 2 or mode == 3 else WeTokens.SUCCESS)
		status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		employer.add_child(status)
	if mode == 3:
		row.add_child(_cell(str(coach.get("season", 0)), 80))
		row.add_child(_cell(str(coach.get("day", 0)), 70))
		row.add_child(_cell(CoachMarket.reason_label(str(coach.get("reason", ""))), 240, WeTokens.ACCENT))
		return
	row.add_child(_cell(str(coach.get("age", 0)), 60))
	var rating := PanelContainer.new()
	rating.custom_minimum_size.x = 60
	rating.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT, 7, 0, 3))
	rating.add_child(_cell(str(coach.get("current_ability", 0)), 60, WeTokens.ACCENT))
	row.add_child(rating)
	row.add_child(_cell(str(coach.get("reputation", 0)), 90, WeTokens.TEXT))
	var wage := int(coach.get("wage", 0))
	var money := ("%.1fM €" % (wage / 1000000.0)) if wage >= 1000000 else (("%.1fK €" % (wage / 1000.0)) if wage >= 1000 else "%d €" % wage)
	row.add_child(_cell(money, 120))
	row.add_child(_cell("%d г." % int(coach.get("contract_years", 0)) if mode == 1 else "—", 90))
	row.add_child(_cell(TacticTypes.style_label(CoachTypes.primary_style_of(coach)), 160, WeTokens.TEXT))
