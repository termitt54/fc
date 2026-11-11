class_name NationalTeamCard
extends VBoxContainer
## National team card embedded in the game hub.


signal closed
signal player_requested(player_id: int)
signal coach_requested(coach_id: int)

const FLAG_SIZE := Vector2(72, 48)
const SQUAD_FIRST := 0
const SQUAD_YOUTH := 1

@onready var _header_card: PanelContainer = %HeaderCard
@onready var _flag_slot: Control = %FlagSlot
@onready var _name_label: Label = %NameLabel
@onready var _meta_label: Label = %MetaLabel
@onready var _stars_host: Control = %StarsHost
@onready var _stars_chip: PanelContainer = %StarsChip
@onready var _close_button: WeButton = %CloseButton
@onready var _squad_panel: PanelContainer = %SquadPanel
@onready var _squad_host: VBoxContainer = %SquadHost
@onready var _side_host: VBoxContainer = %SideHost

var _country_id: int = 0
var _country: Dictionary = {}
var _squad_mode: int = SQUAD_FIRST
var _squad_tabs: WeTabBar
var _squad_list_host: VBoxContainer
var _stars: ReputationStars


func _ready() -> void:
	_style_close_button()
	_close_button.pressed.connect(close)
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
	_stars_chip.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
	)
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


func open_for(country_id: int) -> void:
	_country_id = country_id
	_country = _load_country(country_id)
	_squad_mode = SQUAD_FIRST
	_build_identity()
	_build_squad()
	_build_side()
	visible = true


func refresh() -> void:
	if not visible or _country_id < 1:
		return
	_country = _load_country(_country_id)
	_build_identity()
	_build_squad_list()
	_build_side()


func close() -> void:
	if not visible:
		return
	visible = false
	_country_id = 0
	_country = {}
	closed.emit()


func is_open() -> bool:
	return visible and _country_id > 0


func get_country_id() -> int:
	return _country_id


func _load_country(country_id: int) -> Dictionary:
	if country_id < 1:
		return {}
	var team: Dictionary = GameSession.national_teams.get(country_id, {})
	if not team.is_empty(): return team.country
	var result: Dictionary = CountryRepository.new().get_by_id(country_id)
	if result.get("success", false):
		return result.get("data", {})
	return {}


func _build_identity() -> void:
	for child in _flag_slot.get_children():
		child.queue_free()
	_flag_slot.add_child(_make_flag(str(_country.get("flag_path", "")), FLAG_SIZE))

	var country_name := str(_country.get("name", "")).strip_edges()
	if country_name.is_empty():
		country_name = "Сборная #%d" % _country_id if _country_id > 0 else "Сборная"
	_name_label.text = country_name

	var parts: PackedStringArray = PackedStringArray()
	var abbr := str(_country.get("abbreviation", "")).strip_edges()
	if not abbr.is_empty():
		parts.append(abbr)
	var continent := _continent_name(int(_country.get("continent_id", 0)))
	if not continent.is_empty():
		parts.append(continent)
	var clubs_count := int(_country.get("clubs_count", 0))
	if clubs_count > 0:
		parts.append("%d клубов" % clubs_count)
	var team: Dictionary = GameSession.national_teams.get(_country_id, {})
	if team.has("rating"):
		parts.append("Elo %.1f (%+.1f за турнир)" % [float(team.rating.elo), float(team.rating.edition_delta)])
	parts.append("Талант %d" % int(_country.get("youth_talent", 50)))
	_meta_label.text = " · ".join(parts) if not parts.is_empty() else "Национальная сборная"

	if _stars != null:
		_stars.reputation = int(_country.get("reputation", 0))


func _continent_name(continent_id: int) -> String:
	if continent_id < 1:
		return ""
	var result: Dictionary = ContinentRepository.new().get_by_id(continent_id)
	if not result.get("success", false):
		return ""
	return str(result.get("data", {}).get("name", "")).strip_edges()


func _build_squad() -> void:
	_clear_host(_squad_host)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_squad_host.add_child(head)

	_squad_tabs = WeTabBar.new()
	_squad_tabs.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	head.add_child(_squad_tabs)
	_squad_tabs.set_tabs(PackedStringArray(["Основной", "Молодёжный"]))
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

	var team: Dictionary = GameSession.national_teams.get(_country_id, {})
	var squad := NationalTeams.roster(GameSession, NationalTeams.team_id(_country_id))
	var count_label := _squad_host.find_child("SquadCount", true, false) as Label
	if count_label != null:
		count_label.text = "%d / %d игроков" % [squad.size(),NationalTeams.SQUAD_SIZE]
	if _squad_mode == SQUAD_YOUTH:
		_squad_list_host.add_child(_hint("Молодёжная сборная появится позже"))
		return
	if squad.is_empty():
		_squad_list_host.add_child(_hint("Тренер объявит заявку перед международным турниром, после завершения клубного сезона."))
		return
	_squad_list_host.add_child(_hint("Заявка зафиксирована · Сезон %d · Замены травмированных запрещены" % int(team.get("registered_season", 0))))
	if squad.size() < NationalTeams.SQUAD_SIZE:
		_squad_list_host.add_child(_hint("В мире недостаточно здоровых игроков этой национальности для полной заявки."))
	var tree := Tree.new()
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tree.hide_root = true
	tree.columns = 6
	tree.column_titles_visible = true
	var titles := ["Поз", "Игрок", "Клуб", "Возраст", "CA", "Статус"]
	for i in titles.size():
		tree.set_column_title(i, titles[i])
		tree.set_column_expand(i, i in [1, 2, 5])
		tree.set_column_custom_minimum_width(i, 55)
	_squad_list_host.add_child(tree)
	var root := tree.create_item()
	squad.sort_custom(func(a, b):
		var pa := PlayerTypes.POSITIONS.find(str(a.get("position", "")))
		var pb := PlayerTypes.POSITIONS.find(str(b.get("position", "")))
		return pa < pb if pa != pb else int(a.get("current_ability", 0)) > int(b.get("current_ability", 0))
	)
	var clubs := GameSession._collect_session_clubs()
	for player in squad:
		var item := tree.create_item(root)
		var pid := int(player["id"])
		item.set_metadata(0, pid)
		var withdrawn: bool = pid in team.get("withdrawn_ids", [])
		var state: Dictionary = (team.get("discipline", {}) as Dictionary).get(pid, {})
		var status := "Выбыл: травма" if withdrawn else "Травмирован" if PlayerCondition.is_injured(player) else "Дисквалификация" if int(state.get("suspension_matches", 0)) > 0 else "Готов"
		var values := [str(player.get("position", "")), str(player.get("name", "")), str((clubs.get(int(player.get("club_id", 0)), {}) as Dictionary).get("name", "Свободный агент")), str(player.get("age", 0)), str(player.get("current_ability", 0)), status]
		for i in values.size():
			item.set_text(i, values[i])
			item.set_custom_color(i, WeTokens.TEXT_DIM if withdrawn else WeTokens.TEXT)
	tree.item_activated.connect(func():
		var item := tree.get_selected()
		if item != null:
			player_requested.emit(int(item.get_metadata(0)))
	)


func _build_side() -> void:
	_clear_host(_side_host)
	_side_host.add_child(_build_rating_card())
	_side_host.add_child(_build_clubs_card())
	_side_host.add_child(_build_coach_card())
	_side_host.add_child(_build_history_card())


func _build_clubs_card() -> PanelContainer:
	var card := _side_card()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	box.add_child(_section_title("Клубы страны"))

	var clubs := _collect_country_clubs()
	if clubs.is_empty():
		box.add_child(_hint("Нет клубов этой страны в текущей игре"))
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

	for i in clubs.size():
		var club: Dictionary = clubs[i]
		list.add_child(_club_row(str(club.get("name", "Клуб")), i % 2 == 1))
	return card


func _collect_country_clubs() -> Array:
	var items: Array = []
	var seen: Dictionary = {}
	if _country_id < 1:
		return items

	for unit in GameSession.units:
		if NationalTeams.is_unit(unit):
			continue
		var clubs: Dictionary = unit.get("clubs_by_id", {})
		for club_id in clubs.keys():
			var id: int = int(club_id)
			if seen.has(id):
				continue
			var club: Dictionary = clubs[id]
			if int(club.get("country_id", 0)) != _country_id:
				continue
			seen[id] = true
			items.append(club)

	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return items


func _club_row(club_name: String, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 6, 8, 5))
	var label := Label.new()
	label.text = club_name
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", WeTokens.TEXT)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)
	return row


func _build_coach_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_section_title("Главный тренер"))
	var coach: Dictionary = (GameSession.national_teams.get(_country_id, {}) as Dictionary).get("coach", {})
	if coach.is_empty():
		box.add_child(_hint("Не назначен"))
		return card
	var button := Button.new()
	button.text = str(coach.get("name", ""))
	button.pressed.connect(func(): coach_requested.emit(int(coach["id"])))
	box.add_child(button)
	box.add_child(_hint("Профессионализм %d/20 · Контракт %d г." % [CoachTypes.professionalism_of(coach), int(coach.get("contract_years", 0))]))
	box.add_child(_hint("%s · %s" % [TacticTypes.style_label(CoachTypes.primary_style_of(coach)), CoachTypes.primary_formation_of(coach)]))
	return card


func _build_history_card() -> PanelContainer:
	var card := _side_card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	box.add_child(_section_title("История"))
	var found := false
	for unit in GameSession.units:
		if not NationalTeams.is_unit(unit):
			continue
		for result in unit.get("winners", []):
			if int(result.get("club_id", 0)) == NationalTeams.team_id(_country_id):
				found = true
				box.add_child(_hint("Сезон %d · %s · Победитель" % [int(result.get("season", 0)), str(unit.get("label", ""))]))
	if not found:
		box.add_child(_hint("Пока нет побед в международных турнирах"))
	return card


func _side_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 12)
	)
	return card


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


func _make_flag(path: String, size: Vector2) -> Control:
	path = path.strip_edges()
	if path.is_empty():
		return _flag_placeholder(size)

	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		return _flag_placeholder(size)

	var tex := WeTokens.texture_from_image(image)
	if tex == null:
		return _flag_placeholder(size)
	var display := WeTokens.fit_size(
		Vector2i(tex.get_width(), tex.get_height()),
		int(size.y),
		int(size.x * 0.7),
		int(size.x)
	)
	return WeTokens.make_tex_rect(tex, display)


func _flag_placeholder(size: Vector2) -> Control:
	var placeholder := ColorRect.new()
	placeholder.custom_minimum_size = size
	placeholder.color = Color(1, 1, 1, 0.06)
	return placeholder


func _clear_host(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()


func _build_rating_card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 12))
	var box := VBoxContainer.new()
	panel.add_child(box)
	var team: Dictionary = GameSession.national_teams.get(_country_id, {})
	var rating: Dictionary = team.get("rating", {})
	box.add_child(_hint("Рейтинг Elo · с сезона %d · матчей %d" % [int(rating.get("since_season", 1)), int(rating.get("games", 0))]))
	box.add_child(_hint("Талант: %d · стартовый: %d · тенденция: %+.2f" % [int(_country.get("youth_talent", 50)), int(_country.get("initial_youth_talent", _country.get("youth_talent", 50))), float(rating.get("trend", 0.0))]))
	var current_talent := int(_country.get("youth_talent", 50))
	box.add_child(_hint("Следующий рост: +%.2f · спад: −%.2f очков тенденции" % [5.0 + 0.04 * current_talent, 5.0 + 0.04 * (100 - current_talent)]))
	var changes: Array = rating.get("talent_history", [])
	for change in changes.slice(maxi(0, changes.size() - 5)):
		box.add_child(_hint("Сезон %d: %d → %d · %s" % [int(change.season), int(change.before), int(change.after), str(change.reason)]))
	var history: Array = rating.get("history", [])
	for entry in history.slice(maxi(0, history.size() - 5)):
		var opponent: Dictionary = GameSession.get_club_identity(int(entry.opponent_id))
		box.add_child(_hint("С%d · %s · %+.1f → %.1f" % [int(entry.season), str(opponent.get("name", "Соперник")), float(entry.delta), float(entry.elo)]))
	return panel
