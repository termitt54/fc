class_name PlayerCard
extends VBoxContainer
## Player profile card embedded in the game hub.


signal closed
signal club_requested(club_id: int)
signal country_requested(country_id: int)

const FLAG_SIZE := Vector2(22, 14)
const CLUB_LOGO_SIZE := 18
const CHIP_HEIGHT := 42
const PERSONALITY_MAX := 20
const ATTR_MAX := 20
const STAT_LABEL_WIDTH := 108.0
const STAT_BAR_WIDTH := 48.0
const CAREER_LOGO_SIZE := 18
const CAREER_COL_SEASON := 36.0
const CAREER_COL_APPS := 64.0
const CAREER_COL_STAT := 42.0
const CAREER_PILL_HEIGHT := 26.0
const CAREER_COL_MIN := 56.0
const CAREER_COL_RATING := 48.0
const CaHistoryChartScript := preload("res://scenes/game/ca_history_chart.gd")

@onready var _header_card: PanelContainer = %HeaderCard
@onready var _pos_badge: PanelContainer = %PosBadge
@onready var _pos_label: Label = %PosLabel
@onready var _name_label: Label = %NameLabel
@onready var _meta_host: HBoxContainer = %MetaHost
@onready var _stars_host: Control = %StarsHost
@onready var _stars_chip: PanelContainer = %StarsChip
@onready var _ability_chip: PanelContainer = %AbilityChip
@onready var _ability_label: Label = %AbilityLabel
@onready var _close_button: WeButton = %CloseButton
@onready var _facts_host: HBoxContainer = %FactsHost
@onready var _body_host: Control = %BodyHost

var _player_id: int = 0
var _player: Dictionary = {}
var _stars: ReputationStars
var _title_font: Font
var _chip_style: StyleBoxFlat


func _ready() -> void:
	_style_close_button()
	_close_button.pressed.connect(close)
	_title_font = WeTokens.font_semibold()
	if _title_font != null:
		_name_label.add_theme_font_override("font", _title_font)
		_pos_label.add_theme_font_override("font", _title_font)
	_stars = ReputationStars.new()
	_stars.star_size = 15.0
	_stars.star_gap = 2.0
	_stars_host.add_child(_stars)
	_header_card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE_RAISED, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	_chip_style = WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
	_stars_chip.add_theme_stylebox_override("panel", _chip_style)
	_ability_chip.add_theme_stylebox_override("panel", _chip_style)
	_stars_chip.custom_minimum_size.y = CHIP_HEIGHT
	_ability_chip.custom_minimum_size.y = CHIP_HEIGHT
	_pos_badge.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.ACCENT_SOFT, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	visible = false


func _style_close_button() -> void:
	_close_button.kind = WeButton.Kind.GHOST
	_close_button.text = "✕"
	_close_button.custom_minimum_size = Vector2(CHIP_HEIGHT, CHIP_HEIGHT)
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_close_button.focus_mode = Control.FOCUS_NONE
	_close_button.add_theme_font_size_override("font_size", 16)
	_close_button.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_close_button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	_close_button.add_theme_color_override("font_pressed_color", WeTokens.TEXT_MUTED)
	var normal := WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
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


func open_for(player_id: int) -> void:
	_player_id = player_id
	_player = GameSession.get_player(player_id)
	_rebuild()
	visible = true


func refresh() -> void:
	if not visible or _player_id < 1:
		return
	_player = GameSession.get_player(_player_id)
	_rebuild()


func close() -> void:
	if _player_id < 1:
		visible = false
		return
	visible = false
	_player_id = 0
	_player = {}
	closed.emit()


func is_open() -> bool:
	return visible and _player_id > 0


func get_player_id() -> int:
	return _player_id


func suspend() -> void:
	visible = false


func resume() -> void:
	if _player_id > 0:
		visible = true


func _rebuild() -> void:
	_build_identity()
	_build_header_facts()
	_clear_host(_body_host)
	if _player.is_empty():
		_body_host.add_child(_hint("Игрок не найден"))
		return

	var grid := _build_body_grid()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body_host.add_child(grid)


func _build_identity() -> void:
	var pos_code := str(_player.get("position", ""))
	_pos_label.text = PlayerTypes.position_label(pos_code) if not pos_code.is_empty() else "—"
	_pos_badge.tooltip_text = PlayerTypes.position_full_label(pos_code) if not pos_code.is_empty() else ""

	var player_name := str(_player.get("name", "")).strip_edges()
	if player_name.is_empty():
		player_name = "Игрок #%d" % _player_id if _player_id > 0 else "Игрок"
	_name_label.text = player_name

	_build_meta_row()

	if _stars != null:
		_stars.reputation = int(_player.get("reputation", 0))

	var ca := PlayerTypes.ability_of(_player)
	var pa := int(_player.get("potential_ability", ca))
	_ability_label.text = "CA %d · PA %d" % [ca, pa]


func _build_meta_row() -> void:
	_clear_host(_meta_host)
	if _player.is_empty():
		return

	var age := int(_player.get("age", 0))
	if age > 0:
		_meta_host.add_child(_meta_text("%d %s" % [age, _years_word(age)]))
		_meta_host.add_child(_meta_dot())

	var country_id := int(_player.get("nationality_country_id", 0))
	var country := _load_country(country_id)
	var country_name := str(country.get("name", "")).strip_edges()
	if country_name.is_empty() and country_id > 0:
		country_name = "Сборная #%d" % country_id
	if not country_name.is_empty() or country_id > 0:
		_meta_host.add_child(_country_link(country_id, country_name, str(country.get("flag_path", ""))))
		_meta_host.add_child(_meta_dot())

	var club_id := int(_player.get("club_id", 0))
	if club_id < 1:
		_meta_host.add_child(_meta_text("Свободный агент"))
	else:
		var club := _resolve_club(club_id)
		var club_name := str(club.get("name", "")).strip_edges()
		if club_name.is_empty():
			club_name = "Клуб #%d" % club_id
		_meta_host.add_child(_club_link(club_id, club_name, str(club.get("logo_path", ""))))


func _build_header_facts() -> void:
	_clear_host(_facts_host)
	_facts_host.visible = not _player.is_empty()
	if _player.is_empty():
		return

	var years := int(_player.get("contract_years", 0))
	var contract := "Свободный агент"
	if int(_player.get("club_id", 0)) > 0:
		contract = "%d %s" % [years, _years_word(years)]
	var facts := [
		["Стоимость", _format_money(int(_player.get("value", 0)))],
		["Зарплата", "%s/сез" % _format_money(int(_player.get("wage", 0)))],
		["Контракт", contract],
		["Форма", "%s · %d%%" % [
			PlayerCondition.condition_label(_player),
			PlayerCondition.condition_of(_player),
		]],
		["Мораль", PlayerCondition.morale_label(_player)],
	]
	for fact in facts:
		_facts_host.add_child(_fact_chip(str(fact[0]), str(fact[1])))

	var available := PlayerCondition.is_available(_player)
	_facts_host.add_child(_fact_chip(
		"Готовность",
		PlayerCondition.status_label(_player),
		WeTokens.TEXT if available else WeTokens.DANGER
	))


func _fact_chip(caption: String, value: String, value_color: Color = WeTokens.TEXT) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override(
		"panel",
		_chip_style.duplicate() if _chip_style != null else WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
	)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 8)
	pad.add_theme_constant_override("margin_right", 8)
	pad.add_theme_constant_override("margin_top", 4)
	pad.add_theme_constant_override("margin_bottom", 4)
	chip.add_child(pad)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	pad.add_child(box)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	cap.add_theme_font_size_override("font_size", 10)
	box.add_child(cap)

	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", value_color)
	val.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		val.add_theme_font_override("font", _title_font)
	box.add_child(val)
	return chip


func _meta_text(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _meta_dot() -> Label:
	var label := Label.new()
	label.text = "·"
	label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 13)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label


func _country_link(country_id: int, country_name: String, flag_path: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if country_id > 0 else Control.CURSOR_ARROW

	var flag := _make_flag(flag_path)
	if flag != null:
		row.add_child(flag)

	var label := Label.new()
	label.text = country_name if not country_name.is_empty() else "—"
	label.add_theme_color_override("font_color", WeTokens.ACCENT)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	row.add_child(label)

	if country_id > 0:
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					country_requested.emit(country_id)
		)
		row.mouse_entered.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.TEXT)
		)
		row.mouse_exited.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.ACCENT)
		)
	return row


func _club_link(club_id: int, club_name: String, logo_path: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if club_id > 0 else Control.CURSOR_ARROW

	row.add_child(_make_logo(logo_path, CLUB_LOGO_SIZE))

	var label := Label.new()
	label.text = club_name
	label.add_theme_color_override("font_color", WeTokens.ACCENT)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	row.add_child(label)

	if club_id > 0:
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					club_requested.emit(club_id)
		)
		row.mouse_entered.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.TEXT)
		)
		row.mouse_exited.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.ACCENT)
		)
	return row


func _resolve_club(club_id: int) -> Dictionary:
	if club_id < 1:
		return {}
	for unit in GameSession.units:
		var clubs: Dictionary = unit.get("clubs_by_id", {})
		if clubs.has(club_id):
			return clubs[club_id]
	return {}


func _make_flag(path: String) -> Control:
	path = path.strip_edges()
	if path.is_empty():
		return null
	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		return null
	var tex := WeTokens.texture_from_image(image)
	if tex == null:
		return null
	var display := WeTokens.fit_size(
		Vector2i(tex.get_width(), tex.get_height()), int(FLAG_SIZE.y), 16, 28
	)
	return WeTokens.make_tex_rect(tex, display)


func _make_logo(path: String, size: int) -> Control:
	path = path.strip_edges()
	if not path.is_empty():
		var abs_path := path
		if path.begins_with("user://") or path.begins_with("res://"):
			abs_path = ProjectSettings.globalize_path(path)
		var image := Image.new()
		if image.load(abs_path) == OK:
			var tex := WeTokens.texture_from_image(image)
			if tex != null:
				return WeTokens.make_tex_rect(tex, Vector2(size, size))
	var placeholder := ColorRect.new()
	placeholder.custom_minimum_size = Vector2(size, size)
	placeholder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	placeholder.color = Color(1, 1, 1, 0.08)
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return placeholder


func _build_body_grid() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	var top := HBoxContainer.new()
	top.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.size_flags_stretch_ratio = 1.0
	top.add_theme_constant_override("separation", 8)
	root.add_child(top)

	var bottom := HBoxContainer.new()
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.size_flags_stretch_ratio = 1.0
	bottom.add_theme_constant_override("separation", 8)
	root.add_child(bottom)

	top.add_child(_quadrant_panel("Характеристики", _build_characteristics_content()))
	top.add_child(_quadrant_panel("Карьера · Статистика", _build_statistics_content()))
	bottom.add_child(_quadrant_panel("История развития", _build_development_content()))
	bottom.add_child(_awards_quadrant())
	return root


func _awards_quadrant() -> Control:
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.size_flags_stretch_ratio = 1.0
	stack.add_theme_constant_override("separation", 8)

	stack.add_child(_quadrant_panel(
		"Трофеи",
		_placeholder_body("Трофеи появятся позже")
	))
	stack.add_child(_quadrant_panel(
		"Личные награды",
		_placeholder_body("Личные награды появятся позже")
	))
	return stack


func _quadrant_panel(title: String, content: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.custom_minimum_size = Vector2(0, 0)
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 10)
	)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)

	box.add_child(_block_heading(title))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return card


func _placeholder_body(text: String) -> Control:
	var wrap := CenterContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label := _hint(text)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrap.add_child(label)
	return wrap


func _build_statistics_content() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)

	var totals: Dictionary = PlayerStats.career_totals(_player)
	var rows: Array = PlayerStats.with_transfer_fees(
		PlayerStats.timeline(_player),
		GameSession.get_player_transfers(_player_id),
		_player_id
	)
	if int(totals.get("matches", 0)) < 1 and rows.is_empty():
		root.add_child(_hint("Матчей ещё не было"))
		return root

	root.add_child(_career_summary(totals))
	root.add_child(_career_history(rows))
	return root


func _career_summary(totals: Dictionary) -> Control:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)

	var starts := int(totals.get("starts", 0))
	var rating := PlayerStats.average_rating(totals)
	var yellow := int(totals.get("yellow", 0))
	var red := int(totals.get("red", 0))
	flow.add_child(_career_stat_badge(
		"Матчи",
		_apps_text(starts, PlayerStats.substitute_apps(totals)),
		true,
		"Старты (выходы на замену)"
	))
	flow.add_child(_career_stat_badge("Мин", _format_count(int(totals.get("minutes", 0))), false))
	flow.add_child(_career_stat_badge("Оц.", "%.2f" % rating if rating > 0.0 else "—", true))
	if _is_keeper():
		flow.add_child(_career_stat_badge("Сухие", str(int(totals.get("clean_sheets", 0))), true))
		flow.add_child(_career_stat_badge("Сейвы", _format_count(int(totals.get("saves", 0))), false))
		flow.add_child(_career_stat_badge("Проп.", _format_count(int(totals.get("conceded", 0))), false))
		flow.add_child(_career_stat_badge("Пен.", str(int(totals.get("pen_saved", 0))), false))
	else:
		var pens := int(totals.get("pen_scored", 0)) + int(totals.get("pen_missed", 0))
		flow.add_child(_career_stat_badge("Голы", str(int(totals.get("goals", 0))), true))
		flow.add_child(_career_stat_badge("Пас", str(int(totals.get("assists", 0))), false))
		flow.add_child(_career_stat_badge("Пен.", "%d/%d" % [int(totals.get("pen_scored", 0)), pens], false))
	flow.add_child(_career_stat_badge("ЛИ", str(int(totals.get("motm", 0))), false, "Лучший игрок матча"))
	flow.add_child(_career_stat_badge(
		"ЖК/КК",
		"%d · %d" % [yellow, red],
		false,
		"Жёлтые и красные карточки",
		WeTokens.DANGER if red > 0 else WeTokens.TEXT
	))
	flow.add_child(_career_stat_badge("Травмы", str(int(totals.get("injuries", 0))), false))
	return flow


func _career_history(rows: Array) -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)

	if rows.is_empty():
		wrap.add_child(_hint("Нет матчей"))
		return wrap

	wrap.add_child(_career_header_row())
	var previous_season := -1
	for i in rows.size():
		var entry: Variant = rows[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		var season := int(row.get("season", 0))
		wrap.add_child(_career_data_row(row, season != previous_season, i == 0, i % 2 == 1))
		previous_season = season
	return wrap


func _career_header_row() -> Control:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	cols.add_child(_career_header_label("С", CAREER_COL_SEASON, "Сезон"))
	var club := _career_header_label("Клуб", 0, "")
	club.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(club)
	cols.add_child(_career_header_label("И", CAREER_COL_APPS, "Старты (выходы на замену)"))
	if _is_keeper():
		cols.add_child(_career_header_label("СМ", CAREER_COL_STAT, "Сухие матчи"))
		cols.add_child(_career_header_label("Св", CAREER_COL_STAT, "Сейвы"))
		cols.add_child(_career_header_label("Пр", CAREER_COL_STAT, "Пропущено"))
	else:
		cols.add_child(_career_header_label("Г", CAREER_COL_STAT, "Голы"))
		cols.add_child(_career_header_label("П", CAREER_COL_STAT, "Передачи"))
	cols.add_child(_career_header_label("Мин", CAREER_COL_MIN, "Минуты"))
	cols.add_child(_career_header_label("Оц", CAREER_COL_RATING, "Средняя оценка"))
	return cols


func _career_data_row(entry: Dictionary, show_season: bool, featured: bool, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _career_row_style(zebra, featured))
	var cols := HBoxContainer.new()
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.add_theme_constant_override("separation", 6)
	row.add_child(cols)

	var season := int(entry.get("season", 0))
	var season_text := str(season) if show_season and season > 0 else ""
	cols.add_child(_career_value_badge(season_text, CAREER_COL_SEASON, "Сезон", show_season))
	cols.add_child(_career_club_cell(entry))
	cols.add_child(_career_value_badge(
		_apps_text(int(entry.get("starts", 0)), PlayerStats.substitute_apps(entry)),
		CAREER_COL_APPS,
		"Старты (выходы на замену)",
		true
	))
	if _is_keeper():
		cols.add_child(_career_value_badge(str(int(entry.get("clean_sheets", 0))), CAREER_COL_STAT, "Сухие матчи", int(entry.get("clean_sheets", 0)) > 0))
		cols.add_child(_career_value_badge(str(int(entry.get("saves", 0))), CAREER_COL_STAT, "Сейвы", false))
		cols.add_child(_career_value_badge(str(int(entry.get("conceded", 0))), CAREER_COL_STAT, "Пропущено", false))
	else:
		cols.add_child(_career_value_badge(str(int(entry.get("goals", 0))), CAREER_COL_STAT, "Голы", int(entry.get("goals", 0)) > 0))
		cols.add_child(_career_value_badge(str(int(entry.get("assists", 0))), CAREER_COL_STAT, "Передачи", int(entry.get("assists", 0)) > 0))
	cols.add_child(_career_value_badge(
		_format_count(int(entry.get("minutes", 0))),
		CAREER_COL_MIN,
		"Минуты",
		false
	))
	var rating := PlayerStats.average_rating(entry)
	cols.add_child(_career_value_badge(
		"%.2f" % rating if rating > 0.0 else "—",
		CAREER_COL_RATING,
		"Средняя оценка",
		true,
		WeTokens.ACCENT
	))
	return row


func _career_club_cell(entry: Dictionary) -> Control:
	var club_id := int(entry.get("club_id", 0))
	var club := _resolve_club(club_id)
	var club_name := _club_full_name(club_id)
	if club_id < 1:
		var empty := Label.new()
		empty.text = "—"
		empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		empty.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
		empty.add_theme_font_size_override("font_size", 12)
		return empty
	return _career_club_link(
		club_id,
		club_name,
		str(club.get("logo_path", "")),
		int(entry.get(PlayerStats.TRANSFER_FEE_KEY, -1)) if entry.has(PlayerStats.TRANSFER_FEE_KEY) else -1
	)


func _career_club_link(club_id: int, club_name: String, logo_path: String, fee: int = -1) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if club_id > 0 else Control.CURSOR_ARROW
	row.add_child(_make_logo(logo_path, CAREER_LOGO_SIZE))

	var label := Label.new()
	label.text = club_name
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", WeTokens.TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	row.add_child(label)

	if fee >= 0:
		row.add_child(_transfer_fee_badge(fee))

	if club_id > 0:
		row.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton:
				var mb := event as InputEventMouseButton
				if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
					club_requested.emit(club_id)
		)
		row.mouse_entered.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.ACCENT)
		)
		row.mouse_exited.connect(func() -> void:
			label.add_theme_color_override("font_color", WeTokens.TEXT)
		)
	return row


func _transfer_fee_badge(fee: int) -> Control:
	var paid := fee > 0
	return _career_value_badge(
		_format_money_short(fee) if paid else "бесплатно",
		0.0,
		"Стоимость перехода",
		true,
		WeTokens.ACCENT if paid else WeTokens.SUCCESS
	)


func _career_stat_badge(
	caption: String,
	value: String,
	accent: bool,
	tip: String = "",
	value_color: Color = WeTokens.TEXT
) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = CAREER_PILL_HEIGHT
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", _career_chip_style(accent))
	if not tip.is_empty():
		chip.tooltip_text = tip

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	chip.add_child(row)

	var cap := Label.new()
	cap.text = caption
	cap.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	cap.add_theme_font_size_override("font_size", 11)
	row.add_child(cap)

	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", WeTokens.ACCENT if accent and value_color == WeTokens.TEXT else value_color)
	val.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		val.add_theme_font_override("font", _title_font)
	row.add_child(val)
	return chip


func _career_value_badge(
	text: String,
	width: float,
	tip: String,
	accent: bool,
	color: Color = WeTokens.TEXT
) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(width, CAREER_PILL_HEIGHT)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_END
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.add_theme_stylebox_override("panel", _career_chip_style(accent and not text.is_empty()))
	if not tip.is_empty():
		chip.tooltip_text = tip
		chip.mouse_filter = Control.MOUSE_FILTER_STOP

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color if not text.is_empty() else Color(0, 0, 0, 0))
	label.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	chip.add_child(label)
	if text.is_empty():
		chip.modulate = Color(1, 1, 1, 0.0)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


func _career_header_label(text: String, width: float, tip: String) -> Label:
	var label := Label.new()
	label.text = text
	if width > 0.0:
		label.custom_minimum_size.x = width
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 11)
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	if not tip.is_empty():
		label.tooltip_text = tip
		label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label


func _career_chip_style(accent: bool) -> StyleBoxFlat:
	var box := WeTokens.panel(
		WeTokens.ACCENT_SOFT_STRONG if accent else WeTokens.SURFACE_RAISED,
		WeTokens.BORDER_FOCUS if accent else WeTokens.BORDER_STRONG,
		8,
		0
	)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


func _career_row_style(zebra: bool, featured: bool) -> StyleBoxFlat:
	var bg := Color(1, 1, 1, 0.06) if zebra else Color(1, 1, 1, 0.025)
	var box := WeTokens.fill(bg, WeTokens.RADIUS_SM, 8, 6)
	box.set_border_width_all(0)
	box.border_width_left = 3
	box.border_color = WeTokens.ACCENT if featured else Color(0.55, 0.72, 0.78, 0.28)
	box.content_margin_left = 10
	box.content_margin_right = 8
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	return box


func _apps_text(starts: int, subs: int) -> String:
	return "%d (%d)" % [starts, subs]


func _club_full_name(club_id: int) -> String:
	if club_id < 1:
		return "—"
	var club := _resolve_club(club_id)
	var full_name := str(club.get("name", "")).strip_edges()
	if not full_name.is_empty():
		return full_name
	return _club_short_name(club_id)


func _club_short_name(club_id: int) -> String:
	if club_id < 1:
		return "—"
	var club := _resolve_club(club_id)
	var short_name := str(club.get("short_name", "")).strip_edges()
	if not short_name.is_empty():
		return short_name
	var full_name := str(club.get("name", "")).strip_edges()
	return full_name if not full_name.is_empty() else "#%d" % club_id


func _is_keeper() -> bool:
	return PlayerTypes.normalize_position(str(_player.get("position", ""))) == PlayerTypes.POS_GK


func _build_characteristics_content() -> Control:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)

	root.add_child(_build_attributes_block())
	root.add_child(_build_character_strip())
	root.add_child(_build_personality_scales_block())
	return root


func _build_character_strip() -> Control:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.text = "Характер"
	title.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	title.add_theme_font_size_override("font_size", 11)
	wrap.add_child(title)

	var characters: Array = PlayerTypes.characters_of(_player)
	if characters.is_empty():
		wrap.add_child(_hint("Нет данных"))
		return wrap

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	wrap.add_child(row)

	for code in characters:
		row.add_child(_character_chip(str(code)))
	return wrap


func _character_chip(code: String) -> Control:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.tooltip_text = PlayerTypes.character_effect(code)
	chip.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE_RAISED, WeTokens.BORDER, WeTokens.RADIUS_SM, 8)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	chip.add_child(box)

	var name_label := Label.new()
	name_label.text = PlayerTypes.character_label(code)
	name_label.add_theme_color_override("font_color", WeTokens.ACCENT)
	name_label.add_theme_font_size_override("font_size", 13)
	if _title_font != null:
		name_label.add_theme_font_override("font", _title_font)
	box.add_child(name_label)

	var effect := Label.new()
	effect.text = PlayerTypes.character_effect(code)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.max_lines_visible = 2
	effect.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effect.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	effect.add_theme_font_size_override("font_size", 11)
	box.add_child(effect)
	return chip


func _build_development_content() -> Control:
	var chart := CaHistoryChartScript.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.custom_minimum_size = Vector2(0, 200)
	chart.set_points(_development_points())
	return chart


func _development_points() -> Array:
	var raw: Variant = _player.get("development_history", null)
	var points: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for row in raw:
			if typeof(row) != TYPE_DICTIONARY:
				continue
			points.append({
				"season": int(row.get("season", 0)),
				"ca": int(row.get("ca", 0)),
			})
	if points.is_empty():
		points.append({
			"season": maxi(int(GameSession.season_number), 1),
			"ca": int(_player.get("current_ability", _player.get("overall", 0))),
		})
	return points


func _latest_development_season() -> int:
	var points := _development_points()
	if points.is_empty():
		return 0
	return int((points.back() as Dictionary).get("season", 0))


func _attribute_delta(group: String, key: String) -> int:
	var raw: Variant = _player.get("development_deltas", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return 0
	var group_data: Variant = (raw as Dictionary).get(group, null)
	if typeof(group_data) != TYPE_DICTIONARY:
		return 0
	return int((group_data as Dictionary).get(key, 0))


func _build_attributes_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(header)

	var title := Label.new()
	title.text = "Атрибуты"
	title.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	title.add_theme_font_size_override("font_size", 11)
	header.add_child(title)

	if _player.has("development_deltas") and _latest_development_season() > 0:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(spacer)
		var note := Label.new()
		note.text = "к сезону %d" % _latest_development_season()
		note.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		note.add_theme_font_size_override("font_size", 11)
		header.add_child(note)

	var attributes: Dictionary = _player.get("attributes", {})
	if attributes.is_empty():
		box.add_child(_hint("Атрибуты отсутствуют — начните новую игру"))
		return box

	var position := str(_player.get("position", ""))
	var groups: Array = PlayerTypes.attribute_groups_for_position(position)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	for group in groups:
		var group_data: Variant = attributes.get(group, {})
		if typeof(group_data) != TYPE_DICTIONARY:
			continue
		grid.add_child(_attribute_group_panel(str(group), group_data))
	return box


func _attribute_group_panel(group: String, group_data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(Color(1, 1, 1, 0.03), WeTokens.BORDER, WeTokens.RADIUS_SM, 8)
	)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	var title := Label.new()
	title.text = PlayerTypes.attr_group_label(group)
	title.add_theme_color_override("font_color", WeTokens.ACCENT)
	title.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		title.add_theme_font_override("font", _title_font)
	col.add_child(title)

	for key in PlayerTypes.attribute_keys_for_group(group):
		if not group_data.has(key):
			continue
		col.add_child(_stat_row(
			PlayerTypes.attribute_label(key),
			int(group_data.get(key, 0)),
			true,
			_attribute_delta(group, str(key))
		))
	return panel


func _build_personality_scales_block() -> Control:
	var personality: Dictionary = _player.get("personality", {})
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_theme_constant_override("separation", 4)
	if personality.is_empty():
		return wrap

	var title := Label.new()
	title.text = "Шкалы"
	title.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	title.add_theme_font_size_override("font_size", 11)
	wrap.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 2)
	wrap.add_child(grid)

	for key in PlayerTypes.PERSONALITY_KEYS:
		grid.add_child(_stat_row(
			PlayerTypes.personality_label(key),
			int(personality.get(key, 0)),
			false
		))
	return wrap


func _stat_row(label_text: String, value: int, colorize: bool, delta: int = 0) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = STAT_LABEL_WIDTH
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var level := clampi(value, 0, ATTR_MAX)
	var fill_color := _attr_color(level) if colorize else WeTokens.ACCENT_DIM

	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = ATTR_MAX
	bar.value = level
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(STAT_BAR_WIDTH, 5)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", WeTokens.fill(Color(1, 1, 1, 0.06), 2))
	bar.add_theme_stylebox_override("fill", WeTokens.fill(fill_color, 2))
	row.add_child(bar)

	var value_label := Label.new()
	value_label.text = str(level)
	value_label.custom_minimum_size = Vector2(22, 0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", fill_color if colorize else WeTokens.TEXT)
	value_label.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		value_label.add_theme_font_override("font", _title_font)
	row.add_child(value_label)

	if colorize:
		var delta_label := Label.new()
		delta_label.custom_minimum_size = Vector2(28, 0)
		delta_label.add_theme_font_size_override("font_size", 11)
		if _title_font != null:
			delta_label.add_theme_font_override("font", _title_font)
		if delta > 0:
			delta_label.text = "+%d" % delta
			delta_label.add_theme_color_override("font_color", WeTokens.SUCCESS)
			delta_label.tooltip_text = "Прирост к сезону %d" % _latest_development_season()
		elif delta < 0:
			delta_label.text = str(delta)
			delta_label.add_theme_color_override("font_color", WeTokens.DANGER)
			delta_label.tooltip_text = "Спад к сезону %d" % _latest_development_season()
		row.add_child(delta_label)
	return row


func _block_heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		label.add_theme_font_override("font", _title_font)
	return label


func _section_card(pad: int = 10, expand: bool = true) -> PanelContainer:
	var card := PanelContainer.new()
	if expand:
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, pad)
	)
	return card


func _attr_color(value: int) -> Color:
	if value >= 16:
		return WeTokens.ACCENT
	if value >= 13:
		return Color(0.55, 0.9, 0.72, 1.0)
	if value >= 10:
		return WeTokens.TEXT
	if value >= 7:
		return WeTokens.TEXT_MUTED
	return WeTokens.TEXT_DIM


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 12)
	return label


func _load_country(country_id: int) -> Dictionary:
	if country_id < 1 or not WorldDatabase.is_ready():
		return {}
	var result: Dictionary = CountryRepository.new().get_by_id(country_id)
	if result.get("success", false):
		return result.get("data", {})
	return {}


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


func _format_count(amount: int) -> String:
	var value := absi(amount)
	var chunks: Array[String] = []
	if value == 0:
		return "0"
	while value > 0:
		var part := value % 1000
		value /= 1000
		if value > 0:
			chunks.push_front("%03d" % part)
		else:
			chunks.push_front(str(part))
	var text := " ".join(chunks)
	return "-%s" % text if amount < 0 else text


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


func _clear_host(host: Node) -> void:
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
