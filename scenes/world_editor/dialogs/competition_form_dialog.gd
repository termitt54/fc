extends WeModal
## Create = identity card. Edit = identity + tournament composition units.

const TEXT_FIELD := preload("res://ui/components/we_text_field.tscn")
const SELECT_FIELD := preload("res://ui/components/we_select_field.tscn")
const NUMBER_FIELD := preload("res://ui/components/we_number_field.tscn")
const FILE_FIELD := preload("res://ui/components/we_file_field.tscn")
const BUTTON_SCRIPT := preload("res://ui/components/we_button.gd")
const UNIT_CLUBS_DIALOG := preload("res://scenes/world_editor/dialogs/competition_unit_clubs_dialog.tscn")
const UNIT_RANKING_DIALOG := preload("res://scenes/world_editor/dialogs/competition_unit_ranking_dialog.tscn")
const UNIT_PRIZES_DIALOG := preload("res://scenes/world_editor/dialogs/competition_unit_prizes_dialog.tscn")

signal submitted(data: Dictionary)

enum FormMode { CREATE, EDIT }

const NAME_MAX_LENGTH := 100
const CREATE_SIZE := Vector2(820, 0)
const EDIT_SIZE := Vector2(1040, 900)

var _mode: FormMode = FormMode.CREATE
var _edit_id: int = -1
var _busy: bool = false
var _unit_repo := CompetitionUnitRepository.new()
var _club_repo := ClubRepository.new()
var _units: Array = []
var _collapsed_unit_ids: Dictionary = {} # unit_id -> true when collapsed
var _clubs_dialog: Control
var _ranking_dialog: Control
var _prizes_dialog: Control

var _identity_box: VBoxContainer
var _rules_section: PanelContainer
var _units_list: VBoxContainer
var _empty_units_label: Label
var _create_hint: Label

var _name_field: WeTextField
var _period_field: WeSelectField
var _start_season_field: WeNumberField
var _format_field: WeSelectField
var _country_field: WeSelectField
var _continent_field: WeSelectField
var _age_group_field: WeSelectField


func _ready() -> void:
	super._ready()
	close_on_dim = false
	_build_fields()
	_clubs_dialog = UNIT_CLUBS_DIALOG.instantiate()
	_clubs_dialog.z_index = 110
	add_child(_clubs_dialog)
	_clubs_dialog.clubs_submitted.connect(_on_unit_clubs_submitted)
	_ranking_dialog = UNIT_RANKING_DIALOG.instantiate()
	_ranking_dialog.z_index = 110
	add_child(_ranking_dialog)
	_ranking_dialog.ranking_submitted.connect(_on_unit_ranking_submitted)
	_prizes_dialog = UNIT_PRIZES_DIALOG.instantiate()
	_prizes_dialog.z_index = 110
	add_child(_prizes_dialog)
	_prizes_dialog.prizes_submitted.connect(_on_unit_prizes_submitted)
	_apply_mode_chrome()
	confirmed.connect(_on_save_pressed)
	cancelled.connect(_on_cancel_pressed)


func _build_fields() -> void:
	_identity_box = VBoxContainer.new()
	_identity_box.add_theme_constant_override("separation", 6)
	_identity_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	get_body().add_child(_identity_box)

	var top_row := _make_row()
	_identity_box.add_child(top_row)

	_name_field = _make_text("Наименование турнира", NAME_MAX_LENGTH)
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.size_flags_stretch_ratio = 1.6
	top_row.add_child(_name_field)

	_period_field = _make_select("Периодичность")
	_period_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_period_field)
	_period_field.set_items(CompetitionTypes.period_options(), CompetitionTypes.PERIOD_ANNUAL)

	_start_season_field = _make_number("Старт (сезон)", CompetitionRepository.START_SEASON_MIN, CompetitionRepository.START_SEASON_MAX)
	_start_season_field.value = _default_start_season()
	_start_season_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_season_field.size_flags_stretch_ratio = 0.7
	_start_season_field.custom_minimum_size = Vector2(120, 0)
	top_row.add_child(_start_season_field)

	var shape_row := _make_row()
	_identity_box.add_child(shape_row)

	_format_field = _make_select("Формат турнира")
	_format_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(_format_field)
	_format_field.set_items(CompetitionTypes.scope_options(), CompetitionTypes.SCOPE_DOMESTIC)
	_format_field.item_selected.connect(func(_i): _refresh_context_fields())

	_country_field = _make_select("Страна")
	_country_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(_country_field)

	_continent_field = _make_select("Континент")
	_continent_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(_continent_field)

	_age_group_field = _make_select("Возрастная группа")
	_age_group_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shape_row.add_child(_age_group_field)
	_age_group_field.set_items(CompetitionTypes.age_group_options(), CompetitionTypes.AGE_SENIOR)

	_create_hint = Label.new()
	_create_hint.text = "После создания откройте турнир, чтобы добавить дивизионы, кубки и суперкубки."
	_create_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_create_hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_create_hint.add_theme_font_size_override("font_size", 11)
	_identity_box.add_child(_create_hint)

	_build_composition_section()
	_refresh_context_fields()


func _build_composition_section() -> void:
	_rules_section = PanelContainer.new()
	_rules_section.visible = false
	_rules_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules_section.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 10)
	)
	get_body().add_child(_rules_section)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules_section.add_child(outer)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	outer.add_child(header)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 1)
	header.add_child(titles)

	var title := Label.new()
	title.text = "Состав турнира"
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 13)
	titles.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Дивизионы, кубки и суперкубки в одном списке. Тип — у каждого элемента."
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	subtitle.add_theme_font_size_override("font_size", 11)
	titles.add_child(subtitle)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	header.add_child(actions)

	actions.add_child(_make_add_button("+ Дивизион", CompetitionTypes.UNIT_DIVISION))
	actions.add_child(_make_add_button("+ Кубок", CompetitionTypes.UNIT_CUP))
	actions.add_child(_make_add_button("+ Суперкубок", CompetitionTypes.UNIT_SUPER_CUP))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)

	_units_list = VBoxContainer.new()
	_units_list.add_theme_constant_override("separation", 6)
	_units_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_units_list)

	_empty_units_label = Label.new()
	_empty_units_label.text = "Пока пусто — добавьте дивизион, кубок или суперкубок."
	_empty_units_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_units_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_empty_units_label.add_theme_font_size_override("font_size", 11)
	_units_list.add_child(_empty_units_label)


func _make_add_button(text: String, unit_kind: String) -> Button:
	var button := Button.new()
	button.set_script(BUTTON_SCRIPT)
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.kind = WeButton.Kind.GHOST
	button.pressed.connect(func(): _on_add_unit(unit_kind))
	return button


func _make_text(label_text: String, max_len: int = 0) -> WeTextField:
	var field: WeTextField = TEXT_FIELD.instantiate()
	field.compact = true
	field.label = label_text
	if max_len > 0:
		field.max_length = max_len
	return field


func _make_select(label_text: String) -> WeSelectField:
	var field: WeSelectField = SELECT_FIELD.instantiate()
	field.compact = true
	field.label = label_text
	return field


func _make_number(label_text: String, min_v: int, max_v: int) -> WeNumberField:
	var field: WeNumberField = NUMBER_FIELD.instantiate()
	field.compact = true
	field.label = label_text
	field.min_value = min_v
	field.max_value = max_v
	return field


func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


func is_edit_mode() -> bool:
	return _mode == FormMode.EDIT


func get_edit_id() -> int:
	return _edit_id


func set_countries(countries: Array) -> void:
	var items: Array = []
	for country in countries:
		items.append({
			"id": int(country.get("id", 0)),
			"label": str(country.get("name", "")),
		})
	var keep: Variant = _country_field.selected_id
	_country_field.set_items(items, keep)


func set_continents(continents: Array) -> void:
	var items: Array = []
	for continent in continents:
		items.append({
			"id": int(continent.get("id", 0)),
			"label": str(continent.get("name", "")),
		})
	var keep: Variant = _continent_field.selected_id
	_continent_field.set_items(items, keep)


func open_create() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_units.clear()
	_collapsed_unit_ids.clear()
	set_title("Новый турнир")
	set_confirm_text("Создать")
	_fill_defaults()
	_apply_mode_chrome()
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func open_edit(competition: Dictionary) -> void:
	_mode = FormMode.EDIT
	_edit_id = int(competition.get("id", -1))
	set_title("Редактирование турнира")
	set_confirm_text("Сохранить")
	_name_field.text = str(competition.get("name", ""))
	_period_field.selected_id = str(competition.get("periodicity", CompetitionTypes.PERIOD_ANNUAL))
	_start_season_field.value = int(competition.get("start_season", _default_start_season()))
	_format_field.selected_id = str(competition.get("scope_type", CompetitionTypes.SCOPE_DOMESTIC))
	_country_field.selected_id = int(competition.get("country_id", 0))
	_continent_field.selected_id = int(competition.get("continent_id", 0))
	var age_group: String = str(competition.get("age_group", CompetitionTypes.AGE_SENIOR))
	if age_group.is_empty():
		age_group = CompetitionTypes.AGE_SENIOR
	_age_group_field.selected_id = age_group
	_refresh_context_fields()
	_load_units()
	_apply_mode_chrome()
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)
	_name_field.editable = not busy
	_period_field.editable = not busy
	_start_season_field.editable = not busy
	_format_field.editable = not busy
	_country_field.editable = not busy
	_continent_field.editable = not busy
	_age_group_field.editable = not busy


func reset() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_units.clear()
	_collapsed_unit_ids.clear()
	_fill_defaults()
	_apply_mode_chrome()
	clear_error()
	set_busy(false)
	close()


func _apply_mode_chrome() -> void:
	var is_edit := _mode == FormMode.EDIT
	if is_edit:
		set_card_size(EDIT_SIZE.x, EDIT_SIZE.y)
		set_body_separation(6)
		_identity_box.add_theme_constant_override("separation", 6)
		_title.add_theme_font_size_override("font_size", 17)
	else:
		set_card_size(CREATE_SIZE.x, CREATE_SIZE.y)
		set_body_separation(8)
		_identity_box.add_theme_constant_override("separation", 6)
		_title.add_theme_font_size_override("font_size", 18)

	_create_hint.visible = not is_edit
	_rules_section.visible = is_edit
	_identity_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	get_body().size_flags_vertical = Control.SIZE_EXPAND_FILL if is_edit else Control.SIZE_SHRINK_BEGIN


func _fill_defaults() -> void:
	_name_field.text = ""
	_period_field.selected_id = CompetitionTypes.PERIOD_ANNUAL
	_start_season_field.value = _default_start_season()
	_format_field.selected_id = CompetitionTypes.SCOPE_DOMESTIC
	_age_group_field.selected_id = CompetitionTypes.AGE_SENIOR
	_refresh_context_fields()
	_render_units()


func _refresh_context_fields() -> void:
	var scope: String = str(_format_field.selected_id) if _format_field.selected_id != null else CompetitionTypes.SCOPE_DOMESTIC
	_country_field.visible = scope == CompetitionTypes.SCOPE_DOMESTIC
	_continent_field.visible = scope == CompetitionTypes.SCOPE_CONTINENTAL
	_age_group_field.visible = scope == CompetitionTypes.SCOPE_INTERNATIONAL


func _default_start_season() -> int:
	return 1


func _load_units() -> void:
	_units.clear()
	if _edit_id < 1:
		_render_units()
		return
	var result: Dictionary = _unit_repo.get_by_competition(_edit_id)
	if result["success"]:
		_units = result["data"]
	else:
		show_error(str(result.get("error", "Не удалось загрузить состав.")))
	_render_units()


func _render_units() -> void:
	for child in _units_list.get_children():
		_units_list.remove_child(child)
		child.queue_free()

	if _units.is_empty():
		_empty_units_label = Label.new()
		_empty_units_label.text = "Пока пусто — добавьте дивизион, кубок или суперкубок."
		_empty_units_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_empty_units_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		_empty_units_label.add_theme_font_size_override("font_size", 11)
		_units_list.add_child(_empty_units_label)
		return

	var index_by_kind := {}
	for unit in _units:
		var kind: String = str(unit.get("unit_kind", ""))
		index_by_kind[kind] = int(index_by_kind.get(kind, 0)) + 1
		_units_list.add_child(_make_unit_card(unit, int(index_by_kind[kind])))


func _make_unit_card(unit: Dictionary, kind_index: int) -> PanelContainer:
	var unit_id: int = int(unit.get("id", 0))
	var kind: String = str(unit.get("unit_kind", ""))
	var unit_name: String = str(unit.get("name", ""))
	var collapsed: bool = bool(_collapsed_unit_ids.get(unit_id, false))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_SM, 10)
	)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	box.add_child(header)

	var chevron := Label.new()
	chevron.text = "▸" if collapsed else "▾"
	chevron.custom_minimum_size = Vector2(16, 0)
	chevron.add_theme_color_override("font_color", WeTokens.ACCENT)
	chevron.add_theme_font_size_override("font_size", 14)
	chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(chevron)

	var badge := Label.new()
	badge.text = CompetitionTypes.unit_kind_label(kind)
	badge.add_theme_color_override("font_color", WeTokens.ACCENT)
	badge.add_theme_font_size_override("font_size", 11)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(badge)

	var index_label := Label.new()
	index_label.text = "#%d" % kind_index
	index_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	index_label.add_theme_font_size_override("font_size", 11)
	index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(index_label)

	var summary := Label.new()
	summary.text = unit_name
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_color_override("font_color", WeTokens.TEXT_MUTED if collapsed else WeTokens.TEXT_DIM)
	summary.add_theme_font_size_override("font_size", 12)
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(summary)

	var delete_btn := Button.new()
	delete_btn.set_script(BUTTON_SCRIPT)
	delete_btn.text = "Удалить"
	delete_btn.focus_mode = Control.FOCUS_NONE
	delete_btn.custom_minimum_size = Vector2(0, 26)
	delete_btn.add_theme_font_size_override("font_size", 11)
	delete_btn.kind = WeButton.Kind.DANGER
	delete_btn.pressed.connect(func(): _on_delete_unit(unit_id))
	header.add_child(delete_btn)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.visible = not collapsed
	box.add_child(body)

	header.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_toggle_unit_collapsed(unit_id)
				header.accept_event()
	)

	body.add_child(_make_unit_divider())

	var fields := _make_row()
	var name_field := _make_text("Название", NAME_MAX_LENGTH)
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.size_flags_stretch_ratio = 1.2
	name_field.text = unit_name
	fields.add_child(name_field)
	name_field.text_changed.connect(func(t: String): _on_unit_name_changed(unit_id, t))

	var logo_field: WeFileField = FILE_FIELD.instantiate()
	logo_field.label = "Лого"
	logo_field.compact = true
	logo_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	logo_field.size_flags_stretch_ratio = 0.9
	logo_field.custom_minimum_size = Vector2(128, 0)
	logo_field.set_existing_path(str(unit.get("logo_path", "")))
	fields.add_child(logo_field)
	logo_field.file_changed.connect(func(path: String): _on_unit_logo_changed(unit_id, path, logo_field))

	var level_field := _make_number("Ур.", 1, 99)
	level_field.value = int(unit.get("level", 1))
	level_field.custom_minimum_size = Vector2(84, 0)
	fields.add_child(level_field)
	level_field.value_changed.connect(func(v: int): _on_unit_level_changed(unit_id, v))

	if kind == CompetitionTypes.UNIT_DIVISION:
		var strength_field := _make_number(
			"Сила",
			CompetitionUnitRepository.DIVISION_STRENGTH_MIN,
			CompetitionUnitRepository.DIVISION_STRENGTH_MAX
		)
		strength_field.value = CompetitionUnitRepository.normalize_division_strength(
			unit.get("division_strength", CompetitionUnitRepository.DIVISION_STRENGTH_DEFAULT)
		)
		strength_field.tooltip_text = "Коэффициент силы дивизиона, шкала репутации 0–1000"
		strength_field.custom_minimum_size = Vector2(96, 0)
		fields.add_child(strength_field)
		strength_field.value_changed.connect(func(v: int):
			_on_unit_rule_changed(unit_id, "division_strength", v)
		)

	var current_type: String = str(unit.get("competition_type", CompetitionTypes.default_type_for_unit(kind)))

	var type_field := _make_select("Тип")
	type_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_field.size_flags_stretch_ratio = 0.9
	fields.add_child(type_field)
	type_field.set_items(CompetitionTypes.type_options(), current_type)
	type_field.item_selected.connect(func(_i: int): _on_unit_type_changed(unit_id, str(type_field.selected_id)))

	var foreign_field := _make_number(
		"Легионеры",
		CompetitionUnitRepository.FOREIGN_LIMIT_MIN,
		CompetitionUnitRepository.FOREIGN_LIMIT_MAX
	)
	foreign_field.value = int(unit.get("foreign_players_limit", 0))
	foreign_field.tooltip_text = "0 — ни одного легионера. −1 — без лимита."
	foreign_field.custom_minimum_size = Vector2(108, 0)
	fields.add_child(foreign_field)
	foreign_field.value_changed.connect(func(v: int): _on_unit_foreign_changed(unit_id, unit, v))

	var clubs_wrap := VBoxContainer.new()
	clubs_wrap.add_theme_constant_override("separation", 3)
	clubs_wrap.custom_minimum_size = Vector2(100, 0)
	fields.add_child(clubs_wrap)

	var clubs_label := Label.new()
	clubs_label.text = "Клубы"
	clubs_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	clubs_label.add_theme_font_size_override("font_size", 11)
	clubs_wrap.add_child(clubs_label)

	var clubs_btn := Button.new()
	clubs_btn.set_script(BUTTON_SCRIPT)
	clubs_btn.text = "Выбрать (%d)" % int(unit.get("clubs_count", 0))
	clubs_btn.focus_mode = Control.FOCUS_NONE
	clubs_btn.custom_minimum_size = Vector2(100, 32)
	clubs_btn.add_theme_font_size_override("font_size", 11)
	clubs_btn.kind = WeButton.Kind.GHOST
	clubs_btn.pressed.connect(func(): _on_open_unit_clubs(unit))
	clubs_wrap.add_child(clubs_btn)

	body.add_child(_make_unit_section("Основное", fields))
	body.add_child(_make_unit_section("Дисциплина", _make_discipline_row(unit_id, unit)))

	if current_type == CompetitionTypes.TYPE_DIVISIONS:
		body.add_child(_make_unit_section("Структура", _make_divisions_rules_row(unit_id, unit)))
		body.add_child(_make_unit_section("Переходы и итоги", _make_divisions_movement_row(unit_id, unit)))
		body.add_child(_make_unit_section("Плей-офф", _make_divisions_playoff_row(unit_id, unit)))
		body.add_child(_make_unit_section("Призовые", _make_divisions_prize_row(unit)))

	return card


func _toggle_unit_collapsed(unit_id: int) -> void:
	if unit_id < 1:
		return
	if _collapsed_unit_ids.get(unit_id, false):
		_collapsed_unit_ids.erase(unit_id)
	else:
		_collapsed_unit_ids[unit_id] = true
	_render_units()


func _make_unit_section(title: String, content: Control) -> PanelContainer:
	var section := PanelContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(Color(1, 1, 1, 0.028), WeTokens.BORDER, 8, 8)
	)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(col)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	col.add_child(title_row)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(3, 12)
	accent.color = WeTokens.ACCENT
	accent.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(accent)

	var title_label := Label.new()
	title_label.text = title.to_upper()
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	title_label.add_theme_font_size_override("font_size", 10)
	title_row.add_child(title_label)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(content)
	return section


func _make_unit_divider() -> ColorRect:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.color = WeTokens.BORDER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## Cards, bans and how yellows accumulate. Applies to any unit kind.
func _make_discipline_row(unit_id: int, unit: Dictionary) -> HBoxContainer:
	var row := _make_row()

	row.add_child(_make_rule_checkbox(
		unit_id,
		"Карточки",
		"discipline_enabled",
		bool(unit.get("discipline_enabled", DisciplineRules.ENABLED_DEFAULT)),
		"судьи в игре"
	))

	var strictness := _make_number(
		"Строгость",
		DisciplineRules.STRICTNESS_MIN,
		DisciplineRules.STRICTNESS_MAX
	)
	strictness.value = DisciplineRules.normalize_strictness(
		unit.get("card_strictness", DisciplineRules.STRICTNESS_DEFAULT)
	)
	strictness.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strictness.custom_minimum_size = Vector2(104, 0)
	row.add_child(strictness)
	strictness.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "card_strictness", v))

	var threshold := _make_number("ЖК до диск.", 0, DisciplineRules.YELLOW_THRESHOLD_MAX)
	threshold.value = DisciplineRules.normalize_yellow_threshold(
		unit.get("yellow_ban_threshold", DisciplineRules.YELLOW_THRESHOLD_DEFAULT)
	)
	threshold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	threshold.custom_minimum_size = Vector2(104, 0)
	row.add_child(threshold)
	threshold.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "yellow_ban_threshold", v))

	var yellow_ban := _make_number("Матчей за ЖК", 1, DisciplineRules.YELLOW_BAN_MAX)
	yellow_ban.value = DisciplineRules.normalize_yellow_ban(
		unit.get("yellow_ban_matches", DisciplineRules.YELLOW_BAN_DEFAULT)
	)
	yellow_ban.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yellow_ban.custom_minimum_size = Vector2(112, 0)
	row.add_child(yellow_ban)
	yellow_ban.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "yellow_ban_matches", v))

	var red_ban := _make_number("Матчей за КК", 1, DisciplineRules.RED_BAN_MAX)
	red_ban.value = DisciplineRules.normalize_red_ban(
		unit.get("red_ban_matches", DisciplineRules.RED_BAN_DEFAULT)
	)
	red_ban.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	red_ban.custom_minimum_size = Vector2(112, 0)
	row.add_child(red_ban)
	red_ban.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "red_ban_matches", v))

	row.add_child(_make_rule_checkbox(
		unit_id,
		"2 ЖК = КК",
		"double_yellow_red",
		bool(unit.get("double_yellow_red", DisciplineRules.DOUBLE_YELLOW_RED_DEFAULT)),
		"удаление"
	))

	var reset_field := _make_select("Сброс ЖК")
	reset_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_field.size_flags_stretch_ratio = 1.2
	reset_field.custom_minimum_size = Vector2(140, 0)
	row.add_child(reset_field)
	reset_field.set_items(
		DisciplineRules.reset_options(),
		DisciplineRules.normalize_reset(unit.get("yellow_reset", DisciplineRules.RESET_DEFAULT))
	)
	reset_field.item_selected.connect(func(_i: int):
		_on_unit_rule_changed(unit_id, "yellow_reset", str(reset_field.selected_id))
	)

	return row


func _make_divisions_rules_row(unit_id: int, unit: Dictionary) -> HBoxContainer:
	var row := _make_row()

	var divisions := _make_number("Див.", 1, CompetitionUnitRepository.RULE_COUNT_MAX)
	divisions.value = int(unit.get("divisions_count", CompetitionUnitRepository.DIVISIONS_COUNT_DEFAULT))
	divisions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(divisions)
	divisions.value_changed.connect(func(v: int):
		_on_unit_rule_changed(unit_id, "divisions_count", v)
		call_deferred("_load_units")
	)

	var teams := _make_number("Кл./див.", 1, CompetitionUnitRepository.RULE_COUNT_MAX)
	teams.value = int(unit.get("teams_per_division", CompetitionUnitRepository.TEAMS_PER_DIVISION_DEFAULT))
	teams.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(teams)
	teams.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "teams_per_division", v))

	var own_games := _make_number("Игры своя", 0, CompetitionUnitRepository.RULE_COUNT_MAX)
	own_games.value = int(unit.get("matches_vs_own", CompetitionUnitRepository.MATCHES_VS_OWN_DEFAULT))
	own_games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(own_games)
	own_games.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "matches_vs_own", v))

	var other_games := _make_number("Игры чуж.", 0, CompetitionUnitRepository.RULE_COUNT_MAX)
	other_games.value = int(unit.get("matches_vs_other", CompetitionUnitRepository.MATCHES_VS_OTHER_DEFAULT))
	other_games.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(other_games)
	other_games.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "matches_vs_other", v))

	var pts_win := _make_number("Очки П", 0, CompetitionUnitRepository.POINTS_MAX)
	pts_win.value = int(unit.get("points_win", CompetitionUnitRepository.POINTS_WIN_DEFAULT))
	pts_win.custom_minimum_size = Vector2(84, 0)
	row.add_child(pts_win)
	pts_win.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "points_win", v))

	var pts_draw := _make_number("Очки Н", 0, CompetitionUnitRepository.POINTS_MAX)
	pts_draw.value = int(unit.get("points_draw", CompetitionUnitRepository.POINTS_DRAW_DEFAULT))
	pts_draw.custom_minimum_size = Vector2(84, 0)
	row.add_child(pts_draw)
	pts_draw.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "points_draw", v))

	var pts_loss := _make_number("Очки Пор.", 0, CompetitionUnitRepository.POINTS_MAX)
	pts_loss.value = int(unit.get("points_loss", CompetitionUnitRepository.POINTS_LOSS_DEFAULT))
	pts_loss.custom_minimum_size = Vector2(90, 0)
	row.add_child(pts_loss)
	pts_loss.value_changed.connect(func(v: int): _on_unit_rule_changed(unit_id, "points_loss", v))

	return row


func _make_divisions_movement_row(unit_id: int, unit: Dictionary) -> HBoxContainer:
	var row := _make_row()
	var divisions_count: int = int(unit.get("divisions_count", CompetitionUnitRepository.DIVISIONS_COUNT_DEFAULT))
	var ranking_order: Array = RankingCriteria.parse_stored(unit.get("ranking_order", null))
	var movement_scope: String = CompetitionUnitRepository.normalize_scope(
		unit.get("movement_scope", CompetitionUnitRepository.MOVEMENT_SCOPE_DEFAULT),
		CompetitionUnitRepository.MOVEMENT_SCOPE_DEFAULT
	)

	var movement_scope_field := _make_select("П/П по")
	movement_scope_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	movement_scope_field.size_flags_stretch_ratio = 0.95
	movement_scope_field.custom_minimum_size = Vector2(128, 0)
	row.add_child(movement_scope_field)
	movement_scope_field.set_items(CompetitionUnitRepository.scope_options(), movement_scope)
	movement_scope_field.item_selected.connect(func(_i: int):
		_on_unit_rule_changed(unit_id, "movement_scope", str(movement_scope_field.selected_id))
		call_deferred("_load_units")
	)

	row.add_child(_make_quota_field(
		unit_id,
		"Повыш.",
		"teams_promote",
		int(unit.get("teams_promote", CompetitionUnitRepository.TEAMS_PROMOTE_DEFAULT)),
		divisions_count,
		movement_scope
	))
	row.add_child(_make_quota_field(
		unit_id,
		"Пониж.",
		"teams_relegate",
		int(unit.get("teams_relegate", CompetitionUnitRepository.TEAMS_RELEGATE_DEFAULT)),
		divisions_count,
		movement_scope
	))

	var ranking_wrap := VBoxContainer.new()
	ranking_wrap.add_theme_constant_override("separation", 3)
	ranking_wrap.custom_minimum_size = Vector2(120, 0)
	row.add_child(ranking_wrap)

	var ranking_label := Label.new()
	ranking_label.text = "Места"
	ranking_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	ranking_label.add_theme_font_size_override("font_size", 11)
	ranking_wrap.add_child(ranking_label)

	var ranking_btn := Button.new()
	ranking_btn.set_script(BUTTON_SCRIPT)
	ranking_btn.text = "Правила (%d)" % ranking_order.size()
	ranking_btn.focus_mode = Control.FOCUS_NONE
	ranking_btn.custom_minimum_size = Vector2(120, 32)
	ranking_btn.add_theme_font_size_override("font_size", 11)
	ranking_btn.kind = WeButton.Kind.GHOST
	ranking_btn.pressed.connect(func(): _on_open_unit_ranking(unit))
	ranking_wrap.add_child(ranking_btn)

	var ranking_hint := Label.new()
	ranking_hint.text = "приоритет"
	ranking_hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	ranking_hint.add_theme_font_size_override("font_size", 10)
	ranking_wrap.add_child(ranking_hint)

	row.add_child(_make_regular_season_checkbox(
		unit_id,
		bool(unit.get("regular_season_enabled", CompetitionUnitRepository.REGULAR_SEASON_DEFAULT))
	))

	return row


func _make_divisions_playoff_row(unit_id: int, unit: Dictionary) -> HBoxContainer:
	var row := _make_row()
	var divisions_count: int = int(unit.get("divisions_count", CompetitionUnitRepository.DIVISIONS_COUNT_DEFAULT))
	var playoff_scope: String = CompetitionUnitRepository.normalize_scope(
		unit.get("playoff_scope", CompetitionUnitRepository.PLAYOFF_SCOPE_DEFAULT),
		CompetitionUnitRepository.PLAYOFF_SCOPE_DEFAULT
	)
	var playoff_format: String = PlayoffRules.normalize_format(
		unit.get("playoff_format", PlayoffRules.FORMAT_DEFAULT)
	)
	var series_wins: int = PlayoffRules.normalize_series_wins(
		unit.get("playoff_series_wins", PlayoffRules.SERIES_WINS_DEFAULT)
	)
	var seeding: String = PlayoffRules.normalize_seeding(
		unit.get("playoff_seeding", PlayoffRules.SEEDING_DEFAULT)
	)

	var playoff_scope_field := _make_select("ПО по")
	playoff_scope_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	playoff_scope_field.custom_minimum_size = Vector2(110, 0)
	row.add_child(playoff_scope_field)
	playoff_scope_field.set_items(CompetitionUnitRepository.scope_options(), playoff_scope)
	playoff_scope_field.item_selected.connect(func(_i: int):
		_on_unit_rule_changed(unit_id, "playoff_scope", str(playoff_scope_field.selected_id))
		call_deferred("_load_units")
	)

	row.add_child(_make_quota_field(
		unit_id,
		"Мест в ПО",
		"teams_playoff",
		int(unit.get("teams_playoff", CompetitionUnitRepository.TEAMS_PLAYOFF_DEFAULT)),
		divisions_count,
		playoff_scope
	))

	var format_field := _make_select("Формат ПО")
	format_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	format_field.custom_minimum_size = Vector2(120, 0)
	row.add_child(format_field)
	format_field.set_items(PlayoffRules.format_options(), playoff_format)
	format_field.item_selected.connect(func(_i: int):
		_on_unit_rule_changed(unit_id, "playoff_format", str(format_field.selected_id))
		call_deferred("_load_units")
	)

	if playoff_format == PlayoffRules.FORMAT_BEST_OF:
		var series_field := _make_select("Серия")
		series_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		series_field.custom_minimum_size = Vector2(88, 0)
		row.add_child(series_field)
		series_field.set_items(PlayoffRules.series_wins_options(), series_wins)
		series_field.item_selected.connect(func(_i: int):
			_on_unit_rule_changed(unit_id, "playoff_series_wins", int(series_field.selected_id))
		)

	var seeding_field := _make_select("Посев ПО")
	seeding_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seeding_field.size_flags_stretch_ratio = 1.3
	seeding_field.custom_minimum_size = Vector2(160, 0)
	row.add_child(seeding_field)
	seeding_field.set_items(PlayoffRules.seeding_options(), seeding)
	seeding_field.item_selected.connect(func(_i: int):
		_on_unit_rule_changed(unit_id, "playoff_seeding", str(seeding_field.selected_id))
	)

	row.add_child(_make_rule_checkbox(
		unit_id,
		"Матч 3-е",
		"playoff_third_place",
		bool(unit.get("playoff_third_place", PlayoffRules.THIRD_PLACE_DEFAULT)),
		"бронза"
	))

	return row


func _make_divisions_prize_row(unit: Dictionary) -> HBoxContainer:
	var row := _make_row()
	var filled: int = PrizeRules.filled_count(unit.get("prize_rules", {}), unit)

	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	wrap.custom_minimum_size = Vector2(140, 0)
	row.add_child(wrap)

	var label := Label.new()
	label.text = "Таблица"
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 11)
	wrap.add_child(label)

	var button := Button.new()
	button.set_script(BUTTON_SCRIPT)
	button.text = "Призовые (%d)" % filled
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(140, 32)
	button.add_theme_font_size_override("font_size", 11)
	button.kind = WeButton.Kind.GHOST
	button.pressed.connect(func(): _on_open_unit_prizes(unit))
	wrap.add_child(button)

	var hint := Label.new()
	if PrizeRules.playoff_enabled(unit):
		hint.text = "места + стадии ПО"
	elif PrizeRules.uses_overall_regular(unit):
		hint.text = "места общ. табл."
	else:
		hint.text = "места кажд. див."
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	wrap.add_child(hint)
	return row


func _make_regular_season_checkbox(unit_id: int, enabled: bool) -> VBoxContainer:
	return _make_rule_checkbox(unit_id, "Рег. чемп.", "regular_season_enabled", enabled, "единая табл.")


func _make_rule_checkbox(
	unit_id: int,
	label_text: String,
	field: String,
	enabled: bool,
	hint_text: String
) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 3)
	wrap.custom_minimum_size = Vector2(118, 0)

	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 11)
	wrap.add_child(label)

	var checked := {"value": enabled}

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 32)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _checkbox_row_style(checked["value"]))
	wrap.add_child(row)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	row.add_child(inner)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(18, 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(box)

	var mark := Label.new()
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", Color(0.05, 0.12, 0.12, 1.0))
	mark.add_theme_font_size_override("font_size", 12)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mark)

	var state := Label.new()
	state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state.add_theme_font_size_override("font_size", 12)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(state)

	var apply_visual := func():
		var on: bool = checked["value"]
		row.add_theme_stylebox_override("panel", _checkbox_row_style(on))
		box.add_theme_stylebox_override(
			"panel",
			WeTokens.panel(
				WeTokens.ACCENT if on else WeTokens.INSET,
				WeTokens.ACCENT if on else WeTokens.BORDER_STRONG,
				4,
				0
			)
		)
		mark.text = "✓" if on else ""
		state.text = "Вкл" if on else "Выкл"
		state.add_theme_color_override("font_color", WeTokens.TEXT if on else WeTokens.TEXT_DIM)

	apply_visual.call()

	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				checked["value"] = not checked["value"]
				apply_visual.call()
				_on_unit_rule_changed(unit_id, field, checked["value"])
				row.accept_event()
	)

	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	wrap.add_child(hint)

	return wrap


func _checkbox_row_style(checked: bool) -> StyleBoxFlat:
	var bg: Color = WeTokens.ACCENT_SOFT if checked else WeTokens.INSET
	var border: Color = WeTokens.BORDER
	if checked:
		border = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35)
	return WeTokens.panel(bg, border, WeTokens.RADIUS_SM, 8)


func _make_quota_field(
	unit_id: int,
	label_text: String,
	field: String,
	value: int,
	divisions_count: int,
	scope_code: String
) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var number_field := _make_number(label_text, 0, CompetitionUnitRepository.RULE_COUNT_MAX)
	number_field.value = value
	number_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.add_child(number_field)

	var hint := Label.new()
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	hint.text = CompetitionUnitRepository.quota_hint(value, divisions_count, scope_code)
	wrap.add_child(hint)

	number_field.value_changed.connect(func(v: int):
		_on_unit_rule_changed(unit_id, field, v)
		hint.text = CompetitionUnitRepository.quota_hint(v, divisions_count, scope_code)
	)
	return wrap


func _on_add_unit(unit_kind: String) -> void:
	if _busy or _edit_id < 1:
		return
	var next_index: int = _unit_repo.count_by_kind(_edit_id, unit_kind) + 1
	var result: Dictionary = _unit_repo.create({
		"competition_id": _edit_id,
		"unit_kind": unit_kind,
		"name": CompetitionTypes.default_name_for_unit(unit_kind, next_index),
		"level": 1,
		"competition_type": CompetitionTypes.default_type_for_unit(unit_kind),
		"sort_order": _unit_repo.next_sort_order(_edit_id),
	})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось добавить.")))
		return
	clear_error()
	_load_units()


func _on_delete_unit(unit_id: int) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.delete(unit_id)
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось удалить.")))
		return
	_collapsed_unit_ids.erase(unit_id)
	clear_error()
	_load_units()


func _on_unit_name_changed(unit_id: int, new_name: String) -> void:
	if _busy or unit_id < 1:
		return
	var name_text := new_name.strip_edges()
	if name_text.is_empty():
		return
	var result: Dictionary = _unit_repo.update(unit_id, {"name": name_text})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить название.")))
		return
	clear_error()


func _on_unit_logo_changed(unit_id: int, path: String, logo_field: WeFileField) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.set_logo(unit_id, path)
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить логотип.")))
		return
	clear_error()
	if logo_field != null and result.has("data"):
		logo_field.set_existing_path(str(result["data"].get("logo_path", "")))


func _on_unit_level_changed(unit_id: int, level: int) -> void:
	if _busy or unit_id < 1:
		return
	_unit_repo.update(unit_id, {"level": level})


func _on_unit_type_changed(unit_id: int, type_code: String) -> void:
	if _busy or unit_id < 1:
		return
	if not CompetitionTypes.is_valid_type(type_code):
		return
	var result: Dictionary = _unit_repo.update(unit_id, {"competition_type": type_code})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить тип.")))
		return
	clear_error()
	call_deferred("_load_units")


func _on_unit_foreign_changed(unit_id: int, unit: Dictionary, limit_value: int) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.update(unit_id, {"foreign_players_limit": limit_value})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить лимит легионеров.")))
		return
	unit["foreign_players_limit"] = limit_value
	clear_error()


func _on_unit_rule_changed(unit_id: int, field: String, value: Variant) -> void:
	if _busy or unit_id < 1 or field.is_empty():
		return
	var result: Dictionary = _unit_repo.update(unit_id, {field: value})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить правило.")))
		return
	clear_error()


func _on_open_unit_ranking(unit: Dictionary) -> void:
	if _busy or _ranking_dialog == null:
		return
	var unit_id: int = int(unit.get("id", 0))
	if unit_id < 1:
		return
	clear_error()
	_ranking_dialog.open_editor(
		unit_id,
		str(unit.get("name", CompetitionTypes.unit_kind_label(str(unit.get("unit_kind", ""))))),
		RankingCriteria.parse_stored(unit.get("ranking_order", null))
	)


func _on_unit_ranking_submitted(unit_id: int, order: Array) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.update(unit_id, {"ranking_order": order})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить правила мест.")))
		return
	clear_error()
	call_deferred("_load_units")


func _on_open_unit_prizes(unit: Dictionary) -> void:
	if _busy or _prizes_dialog == null:
		return
	var unit_id: int = int(unit.get("id", 0))
	if unit_id < 1:
		return
	clear_error()
	_prizes_dialog.open_editor(unit)


func _on_unit_prizes_submitted(unit_id: int, prize_rules: Dictionary) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.update(unit_id, {"prize_rules": prize_rules})
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить призовые.")))
		return
	clear_error()
	call_deferred("_load_units")


func _on_open_unit_clubs(unit: Dictionary) -> void:
	if _busy or _clubs_dialog == null:
		return
	var unit_id: int = int(unit.get("id", 0))
	if unit_id < 1:
		return

	var clubs_result := _load_clubs_for_picker()
	if not clubs_result["success"]:
		show_error(str(clubs_result.get("error", "Не удалось загрузить клубы.")))
		return

	var selected_result: Dictionary = _unit_repo.get_club_ids(unit_id)
	if not selected_result["success"]:
		show_error(str(selected_result.get("error", "Не удалось загрузить выбранные клубы.")))
		return

	clear_error()
	_clubs_dialog.open_picker(
		unit_id,
		str(unit.get("name", CompetitionTypes.unit_kind_label(str(unit.get("unit_kind", ""))))),
		clubs_result["data"],
		selected_result["data"]
	)


func _load_clubs_for_picker() -> Dictionary:
	var scope: String = str(_format_field.selected_id) if _format_field.selected_id != null else ""
	match scope:
		CompetitionTypes.SCOPE_DOMESTIC:
			var country_id: int = int(_country_field.selected_id) if _country_field.selected_id != null else 0
			if country_id < 1:
				return DbResult.fail("Сначала выберите страну турнира.")
			return _club_repo.get_by_country(country_id)
		CompetitionTypes.SCOPE_CONTINENTAL:
			var continent_id: int = int(_continent_field.selected_id) if _continent_field.selected_id != null else 0
			if continent_id < 1:
				return DbResult.fail("Сначала выберите континент турнира.")
			return _club_repo.get_by_continent(continent_id)
		_:
			return _club_repo.get_all()


func _on_unit_clubs_submitted(unit_id: int, club_ids: Array) -> void:
	if _busy or unit_id < 1:
		return
	var result: Dictionary = _unit_repo.set_club_ids(unit_id, club_ids)
	if not result["success"]:
		show_error(str(result.get("error", "Не удалось сохранить клубы.")))
		return
	clear_error()
	call_deferred("_load_units")


func _on_save_pressed() -> void:
	if _busy:
		return

	var name_text: String = _name_field.text.strip_edges()
	if name_text.is_empty():
		show_error("Введите наименование турнира.")
		_name_field.focus_field()
		return

	var period_code: Variant = _period_field.selected_id
	if period_code == null or not CompetitionTypes.is_valid_period(str(period_code)):
		show_error("Выберите периодичность.")
		return

	var format_code: Variant = _format_field.selected_id
	if format_code == null or not CompetitionTypes.is_valid_scope(str(format_code)):
		show_error("Выберите формат турнира.")
		return

	var scope: String = str(format_code)
	var payload := {
		"name": name_text,
		"periodicity": str(period_code),
		"start_season": _start_season_field.value,
		"scope_type": scope,
		"country_id": 0,
		"continent_id": 0,
		"age_group": "",
	}

	match scope:
		CompetitionTypes.SCOPE_DOMESTIC:
			var country_id: Variant = _country_field.selected_id
			if country_id == null or int(country_id) < 1:
				show_error("Выберите страну.")
				return
			payload["country_id"] = int(country_id)
		CompetitionTypes.SCOPE_CONTINENTAL:
			var continent_id: Variant = _continent_field.selected_id
			if continent_id == null or int(continent_id) < 1:
				show_error("Выберите континент.")
				return
			payload["continent_id"] = int(continent_id)
		CompetitionTypes.SCOPE_INTERNATIONAL:
			var age_code: Variant = _age_group_field.selected_id
			if age_code == null or not CompetitionTypes.is_valid_age_group(str(age_code)):
				show_error("Выберите возрастную группу.")
				return
			payload["age_group"] = str(age_code)

	clear_error()
	submitted.emit(payload)


func _on_cancel_pressed() -> void:
	if _busy:
		return
	reset()
