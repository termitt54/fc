class_name TeamCard
extends VBoxContainer
## Club card view embedded in the game hub (keeps the main header).


signal closed
signal league_requested(unit_id: int)
signal country_requested(country_id: int)
signal player_requested(player_id: int)
signal coach_requested(coach_id: int)

const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerStatsScript := preload("res://game/player_stats.gd")

const LOGO_SIZE := 56
const FLAG_SIZE := Vector2(28, 18)
const SQUAD_FLAG_H := 14
const SQUAD_FLAG_COL := 28.0
const FACILITY_MAX := 20
const SQUAD_FIRST := 0
const SQUAD_RESERVE := 1
const SQUAD_YOUTH := 2

@onready var _header_card: PanelContainer = %HeaderCard
@onready var _logo_slot: Control = %LogoSlot
@onready var _name_label: Label = %NameLabel
@onready var _country_row: Control = %CountryRow
@onready var _flag_slot: Control = %FlagSlot
@onready var _meta_label: Label = %MetaLabel
@onready var _stars_host: Control = %StarsHost
@onready var _stars_chip: PanelContainer = %StarsChip
@onready var _league_chip: PanelContainer = %LeagueChip
@onready var _league_label: Label = %LeagueLabel
@onready var _close_button: WeButton = %CloseButton
@onready var _squad_panel: PanelContainer = %SquadPanel
@onready var _squad_host: VBoxContainer = %SquadHost
@onready var _side_host: VBoxContainer = %SideHost

const LEAGUE_MAX_WIDTH := 220.0

var _club_id: int = 0
var _unit: Dictionary = {}
var _club: Dictionary = {}
var _squad_mode: int = SQUAD_FIRST
var _squad_tabs: WeTabBar
var _squad_list_host: VBoxContainer
var _stars: ReputationStars
var _country_info_cache: Dictionary = {}
var _flag_tex_cache: Dictionary = {}


func _ready() -> void:
	_style_close_button()
	_close_button.pressed.connect(close)
	_league_chip.gui_input.connect(_on_league_chip_gui_input)
	_league_chip.mouse_entered.connect(_on_league_hover.bind(true))
	_league_chip.mouse_exited.connect(_on_league_hover.bind(false))
	_country_row.gui_input.connect(_on_country_row_gui_input)
	_country_row.mouse_entered.connect(_on_country_hover.bind(true))
	_country_row.mouse_exited.connect(_on_country_hover.bind(false))
	var title_font := WeTokens.font_semibold()
	if title_font != null:
		_name_label.add_theme_font_override("font", title_font)
	_stars = ReputationStars.new()
	_stars.star_size = 17.0
	_stars.star_gap = 2.0
	_stars_host.add_child(_stars)
	_header_card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE_RAISED, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	var chip := WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
	_stars_chip.add_theme_stylebox_override("panel", chip)
	_league_chip.add_theme_stylebox_override("panel", chip)
	_squad_panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	visible = false


func _style_close_button() -> void:
	_close_button.kind = WeButton.Kind.GHOST
	_close_button.text = "✕"
	_close_button.custom_minimum_size = Vector2(30, 30)
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 14)
	_close_button.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_close_button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	_close_button.add_theme_color_override("font_pressed_color", WeTokens.TEXT_MUTED)
	var normal := WeTokens.panel(Color(1, 1, 1, 0.04), WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
	normal.content_margin_left = 0
	normal.content_margin_right = 0
	normal.content_margin_top = 0
	normal.content_margin_bottom = 0
	var hover := WeTokens.panel(Color(1, 1, 1, 0.08), WeTokens.BORDER_STRONG, WeTokens.RADIUS_SM, 0)
	hover.content_margin_left = 0
	hover.content_margin_right = 0
	hover.content_margin_top = 0
	hover.content_margin_bottom = 0
	_close_button.add_theme_stylebox_override("normal", normal)
	_close_button.add_theme_stylebox_override("hover", hover)
	_close_button.add_theme_stylebox_override("pressed", hover)
	_close_button.add_theme_stylebox_override("focus", hover)


func open_for(unit: Dictionary, club_id: int) -> void:
	_unit = unit
	_club_id = club_id
	_club = _resolve_club(unit, club_id)
	_squad_mode = SQUAD_FIRST
	_build_identity()
	_build_squad()
	_build_side()
	visible = true


func refresh() -> void:
	if not visible or _club_id < 1:
		return
	_club = _resolve_club(_unit, _club_id)
	_build_identity()
	_build_squad_list()
	_build_side()


func close() -> void:
	if _club_id < 1:
		visible = false
		return
	visible = false
	_club_id = 0
	_unit = {}
	_club = {}
	closed.emit()


func is_open() -> bool:
	return visible and _club_id > 0


func get_club_id() -> int:
	return _club_id


func get_unit_id() -> int:
	return int(_unit.get("id", 0))


func suspend() -> void:
	visible = false


func resume() -> void:
	if _club_id > 0:
		visible = true


func _resolve_club(unit: Dictionary, club_id: int) -> Dictionary:
	if club_id < 1:
		return {}
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	if clubs.has(club_id):
		return clubs[club_id]
	for other in GameSession.units:
		clubs = other.get("clubs_by_id", {})
		if clubs.has(club_id):
			_unit = other
			return clubs[club_id]
	return {}


func _build_identity() -> void:
	for child in _logo_slot.get_children():
		child.queue_free()
	_logo_slot.add_child(_make_logo(LOGO_SIZE))

	var club_name := str(_club.get("name", ""))
	if club_name.is_empty():
		club_name = "Клуб #%d" % _club_id if _club_id > 0 else "Клуб"
	_name_label.text = club_name

	var country_info := _lookup_country(int(_club.get("country_id", 0)))
	var country := str(_club.get("country_name", "")).strip_edges()
	if country.is_empty():
		country = str(country_info.get("name", "")).strip_edges()

	var flag_path := str(_club.get("country_flag_path", "")).strip_edges()
	if flag_path.is_empty():
		flag_path = str(country_info.get("flag_path", "")).strip_edges()
	_set_flag(flag_path)

	_meta_label.text = country if not country.is_empty() else "—"
	if _stars != null:
		_stars.reputation = int(_club.get("reputation", 0))
	_league_label.text = _ellipsize_text(_current_league_text(), LEAGUE_MAX_WIDTH)
	_league_chip.tooltip_text = _current_league_text()
	_league_chip.visible = true


func _on_league_pressed() -> void:
	var unit_id := int(_unit.get("id", 0))
	league_requested.emit(unit_id)
	close()


func _on_league_chip_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			_on_league_pressed()
			accept_event()


func _on_league_hover(hovered: bool) -> void:
	_league_label.add_theme_color_override(
		"font_color",
		WeTokens.ACCENT if hovered else WeTokens.TEXT_MUTED
	)


func _on_country_row_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			var country_id := int(_club.get("country_id", 0))
			if country_id > 0:
				country_requested.emit(country_id)
			accept_event()


func _on_country_hover(hovered: bool) -> void:
	_meta_label.add_theme_color_override(
		"font_color",
		WeTokens.ACCENT if hovered else WeTokens.TEXT_MUTED
	)


func _ellipsize_text(text: String, max_width: float) -> String:
	var font := _league_label.get_theme_font("font")
	var font_size := _league_label.get_theme_font_size("font_size")
	if font == null or text.is_empty():
		return text
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var ellipsis := "…"
	var trimmed := text
	while trimmed.length() > 1:
		trimmed = trimmed.substr(0, trimmed.length() - 1)
		var candidate := trimmed + ellipsis
		if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
			return candidate
	return ellipsis


func _country_info(country_id: int) -> Dictionary:
	if country_id < 1:
		return {}
	if _country_info_cache.has(country_id):
		return _country_info_cache[country_id]
	var info := _lookup_country(country_id)
	_country_info_cache[country_id] = info
	return info


func _lookup_country(country_id: int) -> Dictionary:
	if country_id < 1:
		return {}
	var rows: Array = DatabaseManager.query_rows(
		"SELECT name, flag_path FROM countries WHERE id = ? LIMIT 1;",
		[country_id]
	)
	if rows.is_empty():
		return {}
	return {
		"name": str(rows[0].get("name", "")),
		"flag_path": str(rows[0].get("flag_path", "")) if rows[0].get("flag_path", null) != null else "",
	}


func _set_flag(path: String) -> void:
	for child in _flag_slot.get_children():
		child.queue_free()
	_flag_slot.visible = true

	if path.is_empty():
		_flag_slot.visible = false
		return

	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		_flag_slot.visible = false
		return

	var tex := WeTokens.texture_from_image(image)
	if tex == null:
		_flag_slot.visible = false
		return
	var display := WeTokens.fit_size(
		Vector2i(tex.get_width(), tex.get_height()), int(FLAG_SIZE.y), 20, 40
	)
	_flag_slot.custom_minimum_size = display
	_flag_slot.add_child(WeTokens.make_tex_rect(tex, display))


func _build_squad() -> void:
	_clear_host(_squad_host)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_squad_host.add_child(head)

	_squad_tabs = WeTabBar.new()
	_squad_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(_squad_tabs)
	_squad_tabs.set_tabs(PackedStringArray(["Основной", "Резерв", "Молодёжный"]))
	_squad_tabs.select(_squad_mode, false)
	_squad_tabs.tab_selected.connect(_on_squad_tab_selected)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var count := Label.new()
	count.name = "SquadCount"
	count.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	count.add_theme_font_size_override("font_size", 12)
	head.add_child(count)

	_squad_list_host = VBoxContainer.new()
	_squad_list_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_squad_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_squad_list_host.add_theme_constant_override("separation", 2)
	_squad_host.add_child(_squad_list_host)
	_build_squad_list()


func _on_squad_tab_selected(index: int) -> void:
	_squad_mode = index
	_build_squad_list()


func _build_squad_list() -> void:
	if _squad_list_host == null:
		return
	_clear_host(_squad_list_host)

	var players: Array = _current_squad_players()
	var count_label := _squad_host.find_child("SquadCount", true, false) as Label
	if count_label != null:
		count_label.text = "%d игроков" % players.size()

	if _squad_mode == SQUAD_RESERVE and players.is_empty():
		_squad_list_host.add_child(_hint("В резерве никого нет"))
		return
	if _squad_mode == SQUAD_YOUTH and players.is_empty():
		_squad_list_host.add_child(_hint("Молодёжный состав появится позже"))
		return
	if players.is_empty():
		_squad_list_host.add_child(_hint("Состав не сгенерирован"))
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_squad_list_host.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 2)
	scroll.add_child(list)

	list.add_child(_player_row({
		"pos": "Поз",
		"name": "Игрок",
		"age": "Возр",
		"apps": "Игр",
		"apps_tip": "Старты (выходы на замену)",
		"ca": "CA",
		"pa": "PA",
		"value": "Цена",
		"wage": "ЗП",
	}, true))

	var remaining: Array = players.duplicate()
	for line in PlayerTypes.SQUAD_LINES:
		var line_id := str(line.get("id", ""))
		var group: Array = []
		var leftover: Array = []
		for player in remaining:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if PlayerTypes.position_line(str(player.get("position", ""))) == line_id:
				group.append(player)
			else:
				leftover.append(player)
		remaining = leftover
		if group.is_empty():
			continue
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _player_ability(a) > _player_ability(b)
		)
		list.add_child(_squad_line_title(str(line.get("title", ""))))
		for i in group.size():
			var player: Dictionary = group[i]
			var pos_code := PlayerTypes.normalize_position(str(player.get("position", "")))
			var country_id := int(player.get("nationality_country_id", 0))
			if country_id < 1:
				country_id = int(_club.get("country_id", 0))
			var country := _country_info(country_id)
			var ca := _player_ability(player)
			var pa := int(player.get("potential_ability", ca))
			var season := PlayerStatsScript.season_of(player)
			var starts := int(season.get("starts", 0))
			var subs := PlayerStatsScript.substitute_apps(season)
			list.add_child(_player_row({
				"pos": PlayerTypes.position_label(pos_code) if not pos_code.is_empty() else "—",
				"pos_tip": PlayerTypes.position_full_label(pos_code),
				"name": str(player.get("name", "")),
				"age": str(int(player.get("age", 0))) if int(player.get("age", 0)) > 0 else "—",
				"apps": "%d (%d)" % [starts, subs],
				"apps_tip": "В старте %d · на замене %d" % [starts, subs],
				"ca": str(ca),
				"pa": str(pa),
				"value": _format_money_short(int(player.get("value", 0))),
				"wage": _format_money_short(int(player.get("wage", 0))),
				"player_id": int(player.get("id", 0)),
				"flag_path": str(country.get("flag_path", "")),
				"country_id": country_id,
				"country_name": str(country.get("name", "")).strip_edges(),
			}, false, i % 2 == 1))


func _current_squad_players() -> Array:
	if _squad_mode == SQUAD_YOUTH:
		if GameSession.has_method("get_club_youth_players"):
			return GameSession.get_club_youth_players(_club_id)
		return []
	if _squad_mode == SQUAD_RESERVE:
		if GameSession.has_method("get_club_reserve_players"):
			return GameSession.get_club_reserve_players(_club_id)
		return []
	return GameSession.get_club_players(_club_id)


func _build_side() -> void:
	_clear_host(_side_host)
	_side_host.add_child(_build_stats_row())
	_side_host.add_child(_build_history_card())
	_side_host.add_child(_build_transfers_card())


func _build_stats_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var finance := _build_finance_card()
	var facilities := _build_facilities_card()
	var coach := _build_coach_card()
	for card in [finance, facilities, coach]:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override(
			"panel",
			WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 8)
		)
		row.add_child(card)
	return row


func _current_league_text() -> String:
	var base := str(_unit.get("label", "")).strip_edges()
	if base.is_empty():
		base = str(_unit.get("competition_name", "")).strip_edges()
	if base.is_empty():
		base = str(_unit.get("name", "")).strip_edges()
	if base.is_empty():
		return "—"

	var divisions: Array = _unit.get("divisions", [])
	if divisions.size() > 1:
		for row in _unit.get("standings", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			if int(row.get("club_id", 0)) != _club_id:
				continue
			return "%s · Дивизион %d" % [base, int(row.get("division", 0)) + 1]
	return base


func _format_money_short(amount: int) -> String:
	var sign := "-" if amount < 0 else ""
	var value := absi(amount)
	if value >= 1_000_000:
		var millions := float(value) / 1_000_000.0
		if is_equal_approx(millions, round(millions)):
			return "%s%dM €" % [sign, int(round(millions))]
		return "%s%.1fM €" % [sign, millions]
	if value >= 1000:
		var thousands := float(value) / 1000.0
		if is_equal_approx(thousands, round(thousands)):
			return "%s%dK €" % [sign, int(round(thousands))]
		return "%s%.1fK €" % [sign, thousands]
	return "%s%d €" % [sign, value]


func _format_money(amount: int) -> String:
	var value := absi(amount)
	var chunks: Array[String] = []
	if value == 0:
		chunks.append("0")
	else:
		while value > 0:
			var part := value % 1000
			value /= 1000
			if value > 0:
				chunks.push_front("%03d" % part)
			else:
				chunks.push_front(str(part))
	var text := " ".join(chunks)
	if amount < 0:
		return "-%s €" % text
	return "%s €" % text


func _build_finance_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(_section_title("Финансы"))

	if _club_id < 1:
		box.add_child(_hint("Нет данных клуба"))
		return card

	var budget := 0
	var wages := 0
	if GameSession.has_method("get_club_budget"):
		budget = int(GameSession.get_club_budget(_club_id))
	if GameSession.has_method("get_club_wage_bill"):
		wages = int(GameSession.get_club_wage_bill(_club_id))

	var budget_row := HBoxContainer.new()
	budget_row.add_theme_constant_override("separation", 8)
	box.add_child(budget_row)
	var budget_label := Label.new()
	budget_label.text = "Бюджет"
	budget_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	budget_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	budget_label.add_theme_font_size_override("font_size", 12)
	budget_row.add_child(budget_label)
	var budget_value := Label.new()
	budget_value.text = _format_money_short(budget)
	budget_value.add_theme_color_override("font_color", WeTokens.DANGER if budget < 0 else WeTokens.SUCCESS)
	budget_value.add_theme_font_size_override("font_size", 13)
	budget_value.tooltip_text = _format_money(budget)
	budget_row.add_child(budget_value)

	var wage_row := HBoxContainer.new()
	wage_row.add_theme_constant_override("separation", 8)
	box.add_child(wage_row)
	var wage_label := Label.new()
	wage_label.text = "Зарплаты"
	wage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wage_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	wage_label.add_theme_font_size_override("font_size", 12)
	wage_row.add_child(wage_label)
	var wage_value := Label.new()
	wage_value.text = "%s/сез" % _format_money_short(wages)
	wage_value.add_theme_color_override("font_color", WeTokens.TEXT)
	wage_value.add_theme_font_size_override("font_size", 12)
	wage_value.tooltip_text = "Состав, резерв, молодёжка и тренер. Списывается один раз, когда окно закрывается."
	wage_row.add_child(wage_value)

	if not _club.is_empty():
		box.add_child(_facility_row(
			"Фонд",
			int(_club.get("finance_level", 0)),
			"Уровень финансов клуба: вместе с репутацией задаёт сезонный доход (100 тыс. — 50 млн) и потолок одного трансфера."
		))
	return card


func _build_facilities_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(_section_title("Инфраструктура"))

	if _club.is_empty():
		box.add_child(_hint("Нет данных клуба"))
		return card

	var rows := [
		["Тренировочная база", int(_club.get("training_level", 0)), "Влияет на дальнейшее развитие футболистов клуба."],
		["Молодёжная академия", int(_club.get("youth_academy", 0)), "Влияет на уровень подготовки воспитанников к моменту их появления в составе."],
		["Система скаутинга", int(_club.get("scouting_level", 0)), "Влияет на поиск и оценку существующих футболистов."],
		["Поиск молодых", int(_club.get("youth_search", 0)), "Влияет на способность клуба находить и привлекать лучших молодых футболистов."],
	]
	for row in rows:
		box.add_child(_facility_row(str(row[0]), int(row[1]), str(row[2])))
	return card


func _build_coach_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(_section_title("Главный тренер"))

	var coach := GameSession.get_club_coach(_club_id)
	if coach.is_empty():
		box.add_child(_hint("Не назначен"))
		return card

	var coach_id := int(coach.get("id", 0))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if coach_id > 0 else Control.CURSOR_ARROW
	if coach_id > 0:
		card.gui_input.connect(_on_coach_card_gui_input.bind(coach_id))
		card.mouse_entered.connect(_on_coach_card_hover.bind(card, true))
		card.mouse_exited.connect(_on_coach_card_hover.bind(card, false))

	var name_label := Label.new()
	name_label.text = str(coach.get("name", "Тренер")).strip_edges()
	if name_label.text.is_empty():
		name_label.text = "Тренер #%d" % coach_id
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_color_override("font_color", WeTokens.ACCENT)
	name_label.add_theme_font_size_override("font_size", 13)
	box.add_child(name_label)

	var age := int(coach.get("age", 0))
	var ca := int(coach.get("current_ability", coach.get("overall", 0)))
	var meta := Label.new()
	meta.text = "%d лет · CA %d" % [age, ca] if age > 0 else "CA %d" % ca
	meta.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	meta.add_theme_font_size_override("font_size", 11)
	box.add_child(meta)

	var style_line := Label.new()
	style_line.text = "%s · %s" % [
		TacticTypesScript.style_label(CoachTypesScript.primary_style_of(coach)),
		TacticTypesScript.formation_label(CoachTypesScript.primary_formation_of(coach)),
	]
	style_line.clip_text = true
	style_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	style_line.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	style_line.add_theme_font_size_override("font_size", 11)
	style_line.tooltip_text = "Запасной: %s · %s" % [
		TacticTypesScript.style_label(CoachTypesScript.backup_style_of(coach)),
		TacticTypesScript.formation_label(CoachTypesScript.backup_formation_of(coach)),
	]
	box.add_child(style_line)

	var years := int(coach.get("contract_years", 0))
	var contract_text := "—" if years < 1 else "%d %s" % [years, _years_word(years)]
	box.add_child(_info_row("Контракт", contract_text))
	var wage := int(coach.get("wage", 0))
	box.add_child(_info_row("Зарплата", "—" if wage < 1 else "%s/сез" % _format_money_short(wage)))
	box.add_child(_info_row("Нация", _coach_nation_value(coach)))
	return card


func _coach_nation_value(coach: Dictionary) -> Control:
	var nation_id := int(coach.get("nationality_country_id", 0))
	var nation := _country_info(nation_id)
	var nation_name := str(nation.get("name", "")).strip_edges()
	if nation_name.is_empty() and nation_id > 0:
		nation_name = "Страна #%d" % nation_id
	return _squad_flag_cell(str(nation.get("flag_path", "")), nation_id, nation_name, false)


func _info_row(caption: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var left := Label.new()
	left.text = caption
	left.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	left.add_theme_font_size_override("font_size", 11)
	row.add_child(left)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	if value is Control:
		var node := value as Control
		node.size_flags_horizontal = Control.SIZE_SHRINK_END
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(node)
	else:
		var right := Label.new()
		right.text = str(value)
		right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		right.size_flags_horizontal = Control.SIZE_SHRINK_END
		right.add_theme_color_override("font_color", WeTokens.TEXT)
		right.add_theme_font_size_override("font_size", 11)
		row.add_child(right)
	return row


func _years_word(years: int) -> String:
	var n := absi(years) % 100
	var n1 := n % 10
	if n > 10 and n < 20:
		return "лет"
	if n1 == 1:
		return "год"
	if n1 >= 2 and n1 <= 4:
		return "года"
	return "лет"


func _on_coach_card_gui_input(event: InputEvent, coach_id: int) -> void:
	if coach_id < 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			coach_requested.emit(coach_id)


func _on_coach_card_hover(card: PanelContainer, hovered: bool) -> void:
	var bg := WeTokens.SURFACE_RAISED if hovered else WeTokens.INSET
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(bg, WeTokens.BORDER, WeTokens.RADIUS_MD, 8)
	)


func _build_history_card() -> PanelContainer:
	var card := _side_card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(_section_title("История турниров"))

	var entries := _collect_history()
	if entries.is_empty():
		box.add_child(_hint("Пока нет призовых мест"))
		return card

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 3)
	scroll.add_child(list)

	for i in entries.size():
		list.add_child(_history_row(entries[i], i % 2 == 1))
	return card


func _build_transfers_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_section_title("История трансферов"))

	var transfers := _collect_transfers()
	if transfers.is_empty():
		box.add_child(_hint("Трансферов пока нет"))
		return card

	for i in mini(transfers.size(), 6):
		box.add_child(_transfer_row(transfers[i], i % 2 == 1))
	if transfers.size() > 6:
		box.add_child(_hint("и ещё %d…" % (transfers.size() - 6)))
	return card


func _collect_transfers() -> Array:
	if _club_id < 1:
		return []
	return GameSession.get_club_transfers(_club_id)


func _transfer_row(entry: Dictionary, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 6, 8, 5))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	row.add_child(cols)

	var direction := str(entry.get("direction", "")).strip_edges()
	var dir_label := Label.new()
	dir_label.text = "↑" if direction == "in" else ("↓" if direction == "out" else ("↔" if direction == "bid" else "•"))
	dir_label.custom_minimum_size = Vector2(16, 0)
	dir_label.add_theme_color_override(
		"font_color",
		WeTokens.SUCCESS if direction == "in" else (
			WeTokens.DANGER if direction == "out" else WeTokens.TEXT_MUTED
		)
	)
	dir_label.add_theme_font_size_override("font_size", 12)
	cols.add_child(dir_label)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	cols.add_child(info)

	var player := Label.new()
	player.text = str(entry.get("player_name", "Игрок"))
	player.clip_text = true
	player.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	player.add_theme_color_override("font_color", WeTokens.TEXT)
	player.add_theme_font_size_override("font_size", 12)
	info.add_child(player)

	var meta := Label.new()
	var fee := int(entry.get("fee", 0))
	var club_name := str(entry.get("other_club", "")).strip_edges()
	var season := int(entry.get("season", 0))
	var bits: PackedStringArray = PackedStringArray()
	if season > 0:
		bits.append("С%s" % season)
	if not club_name.is_empty():
		bits.append(club_name)
	if fee > 0:
		bits.append(_format_money(fee))
	meta.text = " · ".join(bits) if not bits.is_empty() else "—"
	meta.clip_text = true
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	meta.add_theme_font_size_override("font_size", 11)
	info.add_child(meta)
	return row


func _collect_history() -> Array:
	var items: Array = []
	if _club_id < 1:
		return items

	for unit in GameSession.units:
		var tournament := str(unit.get("label", unit.get("name", "Турнир")))
		for entry in unit.get("winners", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var season := int(entry.get("season", 0))
			var playoff_rows: Array = entry.get("playoff", []) if typeof(entry.get("playoff")) == TYPE_ARRAY else []
			var regular_rows: Array = entry.get("regular", []) if typeof(entry.get("regular")) == TYPE_ARRAY else []
			var matched := false
			for row in playoff_rows:
				if typeof(row) == TYPE_DICTIONARY and int(row.get("club_id", 0)) == _club_id:
					matched = true
					items.append({
						"season": season,
						"place": int(row.get("place", 0)),
						"tournament": "%s · плей-офф" % tournament,
					})
			for row in regular_rows:
				if typeof(row) == TYPE_DICTIONARY and int(row.get("club_id", 0)) == _club_id:
					matched = true
					items.append({
						"season": season,
						"place": int(row.get("place", 0)),
						"tournament": "%s · регулярный сезон" % tournament,
					})
			if not matched and int(entry.get("club_id", 0)) == _club_id:
				items.append({
					"season": season,
					"place": int(entry.get("place", 1)),
					"tournament": tournament,
				})
		for entry in unit.get("podium", []):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			if int(entry.get("club_id", 0)) != _club_id:
				continue
			items.append({
				"season": int(entry.get("season", 0)),
				"place": int(entry.get("place", 0)),
				"tournament": str(entry.get("tournament", tournament)),
			})

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get("season", 0))
		var sb := int(b.get("season", 0))
		if sa != sb:
			return sa > sb
		return int(a.get("place", 99)) < int(b.get("place", 99))
	)
	return items


func _history_row(entry: Dictionary, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 6, 8, 5))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	row.add_child(cols)

	var place := int(entry.get("place", 1))
	var place_label := Label.new()
	place_label.text = _place_text(place)
	place_label.custom_minimum_size = Vector2(56, 0)
	place_label.add_theme_color_override("font_color", _place_color(place))
	place_label.add_theme_font_size_override("font_size", 11)
	cols.add_child(place_label)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	cols.add_child(info)

	var tournament := Label.new()
	tournament.text = str(entry.get("tournament", ""))
	tournament.clip_text = true
	tournament.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tournament.add_theme_color_override("font_color", WeTokens.TEXT)
	tournament.add_theme_font_size_override("font_size", 12)
	info.add_child(tournament)

	var season := Label.new()
	season.text = "Сезон %d" % int(entry.get("season", 0))
	season.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	season.add_theme_font_size_override("font_size", 11)
	info.add_child(season)
	return row


func _facility_row(label_text: String, level: int, tip: String = "") -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	if not tip.is_empty():
		wrap.tooltip_text = tip

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	wrap.add_child(top)

	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	top.add_child(label)

	var value := Label.new()
	value.text = "%d/%d" % [level, FACILITY_MAX]
	value.add_theme_color_override("font_color", WeTokens.TEXT)
	value.add_theme_font_size_override("font_size", 12)
	top.add_child(value)

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = FACILITY_MAX
	bar.value = level
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_stylebox_override("background", WeTokens.fill(Color(0, 0, 0, 0.25), 3))
	bar.add_theme_stylebox_override("fill", WeTokens.fill(WeTokens.ACCENT, 3))
	wrap.add_child(bar)
	return wrap


func _side_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 12)
	)
	return card


func _player_ability(player: Dictionary) -> int:
	if player.has("current_ability"):
		return int(player.get("current_ability", 0))
	return int(player.get("overall", 0))


func _player_row(data: Dictionary, is_header: bool, zebra: bool = false) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(0, 0, 0, 0)
	if is_header:
		bg = Color(0, 0, 0, 0.2)
	elif zebra:
		bg = Color(1, 1, 1, 0.03)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 6, 8, 6))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cols)
	var color := WeTokens.TEXT_DIM if is_header else WeTokens.TEXT
	var pos := _col_label(str(data.get("pos", "")), 36, color)
	var pos_tip := str(data.get("pos_tip", ""))
	if not is_header and not pos_tip.is_empty():
		pos.tooltip_text = pos_tip
		pos.mouse_filter = Control.MOUSE_FILTER_STOP
	cols.add_child(pos)
	cols.add_child(_squad_flag_cell(
		str(data.get("flag_path", "")),
		int(data.get("country_id", 0)),
		str(data.get("country_name", "")),
		is_header
	))
	cols.add_child(_col_label(str(data.get("name", "")), 0, color, true))
	cols.add_child(_col_label(str(data.get("age", "")), 36, color))
	var apps := _col_label(str(data.get("apps", "")), 56, color)
	var apps_tip := str(data.get("apps_tip", ""))
	if not apps_tip.is_empty():
		apps.tooltip_text = apps_tip
		apps.mouse_filter = Control.MOUSE_FILTER_STOP
	cols.add_child(apps)
	cols.add_child(_col_label(
		str(data.get("ca", "")),
		36,
		WeTokens.ACCENT if not is_header else color
	))
	cols.add_child(_col_label(str(data.get("pa", "")), 36, color))
	var money_color := WeTokens.TEXT_MUTED if not is_header else color
	cols.add_child(_col_label(
		str(data.get("value", "")),
		56,
		money_color,
		false,
		HORIZONTAL_ALIGNMENT_RIGHT
	))
	cols.add_child(_col_label(
		str(data.get("wage", "")),
		52,
		money_color,
		false,
		HORIZONTAL_ALIGNMENT_RIGHT
	))

	var player_id := int(data.get("player_id", 0))
	if not is_header and player_id > 0:
		row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		row.gui_input.connect(_on_player_row_gui_input.bind(player_id))
		row.mouse_entered.connect(_on_player_row_hover.bind(row, true, zebra))
		row.mouse_exited.connect(_on_player_row_hover.bind(row, false, zebra))
	return row


func _squad_line_title(text: String) -> Control:
	var wrap := MarginContainer.new()
	wrap.add_theme_constant_override("margin_top", 8)
	wrap.add_theme_constant_override("margin_bottom", 1)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 11)
	wrap.add_child(label)
	return wrap


func _squad_flag_cell(
	flag_path: String,
	country_id: int,
	country_name: String,
	is_header: bool
) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(SQUAD_FLAG_COL, SQUAD_FLAG_H)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_header:
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return wrap

	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.add_child(_make_squad_flag(flag_path))
	if not country_name.is_empty():
		wrap.tooltip_text = country_name
	if country_id > 0:
		wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		wrap.gui_input.connect(_on_squad_flag_gui_input.bind(country_id))
	return wrap


func _make_squad_flag(path: String) -> Control:
	var tex := _squad_flag_texture(path)
	if tex == null:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(20, SQUAD_FLAG_H)
		placeholder.color = Color(1, 1, 1, 0.08)
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return placeholder
	var display := WeTokens.fit_size(
		Vector2i(tex.get_width(), tex.get_height()), SQUAD_FLAG_H, 16, 28
	)
	return WeTokens.make_tex_rect(tex, display)


func _squad_flag_texture(path: String) -> Texture2D:
	path = path.strip_edges()
	if path.is_empty():
		return null
	if _flag_tex_cache.has(path):
		return _flag_tex_cache[path]
	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		_flag_tex_cache[path] = null
		return null
	var texture := WeTokens.texture_from_image(image)
	_flag_tex_cache[path] = texture
	return texture


func _on_squad_flag_gui_input(event: InputEvent, country_id: int) -> void:
	if country_id < 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			country_requested.emit(country_id)
			get_viewport().set_input_as_handled()


func _on_player_row_gui_input(event: InputEvent, player_id: int) -> void:
	if player_id < 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			player_requested.emit(player_id)


func _on_player_row_hover(row: PanelContainer, hovered: bool, zebra: bool) -> void:
	var bg := Color(1, 1, 1, 0.08) if hovered else (Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0))
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 6, 8, 6))


func _col_label(
	text: String,
	width: int,
	color: Color,
	expand: bool = false,
	align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT
) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = align
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 12)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	elif width > 0:
		label.custom_minimum_size = Vector2(width, 0)
	return label


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _make_logo(size: int) -> Control:
	var path := str(_club.get("logo_path", "")).strip_edges()
	if path.is_empty():
		return _logo_placeholder(size)

	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		return _logo_placeholder(size)
	var tex := WeTokens.texture_from_image(image)
	if tex == null:
		return _logo_placeholder(size)
	return WeTokens.make_tex_rect(tex, Vector2(size, size))


func _logo_placeholder(size: int) -> Control:
	var placeholder := ColorRect.new()
	placeholder.custom_minimum_size = Vector2(size, size)
	placeholder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	placeholder.color = Color(1, 1, 1, 0.06)
	return placeholder


func _place_text(place: int) -> String:
	match place:
		1:
			return "1 место"
		2:
			return "2 место"
		3:
			return "3 место"
		_:
			return "%d м." % place


func _place_color(place: int) -> Color:
	match place:
		1:
			return WeTokens.ACCENT
		2:
			return Color(0.78, 0.84, 0.9, 1.0)
		3:
			return Color(0.82, 0.62, 0.42, 1.0)
		_:
			return WeTokens.TEXT_DIM


func _clear_host(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
