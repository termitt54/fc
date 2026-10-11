class_name CoachCard
extends VBoxContainer
## Head-coach profile card embedded in the game hub.


signal closed
signal club_requested(club_id: int)
signal country_requested(country_id: int)

const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")

const FLAG_SIZE := Vector2(22, 14)
const CLUB_LOGO_SIZE := 18
const CHIP_HEIGHT := 42
const ATTR_MAX := 20
const STAT_LABEL_WIDTH := 108.0
const STAT_BAR_WIDTH := 48.0

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

var _coach_id: int = 0
var _coach: Dictionary = {}
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


func open_for(coach_id: int) -> void:
	_coach_id = coach_id
	_coach = GameSession.get_coach(coach_id)
	_rebuild()
	visible = true


func refresh() -> void:
	if not visible or _coach_id < 1:
		return
	_coach = GameSession.get_coach(_coach_id)
	_rebuild()


func close() -> void:
	if _coach_id < 1:
		visible = false
		return
	visible = false
	_coach_id = 0
	_coach = {}
	closed.emit()


func is_open() -> bool:
	return visible and _coach_id > 0


func get_coach_id() -> int:
	return _coach_id


func suspend() -> void:
	visible = false


func resume() -> void:
	if _coach_id > 0:
		visible = true


func _rebuild() -> void:
	_build_identity()
	_build_header_facts()
	_clear_host(_body_host)
	if _coach.is_empty():
		_body_host.add_child(_hint("Тренер не найден"))
		return
	var grid := _build_body_grid()
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_body_host.add_child(grid)


func _build_identity() -> void:
	_pos_label.text = "ГТ"
	var coach_name := str(_coach.get("name", "")).strip_edges()
	if coach_name.is_empty():
		coach_name = "Тренер #%d" % _coach_id if _coach_id > 0 else "Тренер"
	_name_label.text = coach_name
	_build_meta_row()
	if _stars != null:
		_stars.reputation = int(_coach.get("reputation", 0))
	var ca := PlayerTypes.clamp_ability(int(_coach.get("current_ability", _coach.get("overall", 0))))
	var pa := PlayerTypes.clamp_ability(int(_coach.get("potential_ability", ca)))
	_ability_label.text = "CA %d · PA %d" % [ca, pa]


func _build_meta_row() -> void:
	_clear_host(_meta_host)
	if _coach.is_empty():
		return

	var age := int(_coach.get("age", 0))
	if age > 0:
		_meta_host.add_child(_meta_text("%d %s" % [age, _years_word(age)]))
		_meta_host.add_child(_meta_dot())

	var country_id := int(_coach.get("nationality_country_id", 0))
	var country := _load_country(country_id)
	var country_name := str(country.get("name", "")).strip_edges()
	if country_name.is_empty() and country_id > 0:
		country_name = "Сборная #%d" % country_id
	if not country_name.is_empty() or country_id > 0:
		_meta_host.add_child(_country_link(country_id, country_name, str(country.get("flag_path", ""))))
		_meta_host.add_child(_meta_dot())

	var club_id := int(_coach.get("club_id", 0))
	if club_id < 1:
		_meta_host.add_child(_meta_text("Без клуба"))
		return
	var club := _resolve_club(club_id)
	var club_name := str(club.get("name", "")).strip_edges()
	if club_name.is_empty():
		club_name = "Клуб #%d" % club_id
	_meta_host.add_child(_club_link(club_id, club_name, str(club.get("logo_path", ""))))


func _build_header_facts() -> void:
	_clear_host(_facts_host)
	_facts_host.visible = not _coach.is_empty()
	if _coach.is_empty():
		return
	var years := int(_coach.get("contract_years", 0))
	var transfers := CoachTypesScript.transfers_of(_coach)
	var talks := CoachTypesScript.negotiations_of(_coach)
	var facts := [
		["Зарплата", "%s/сез" % _format_money(int(_coach.get("wage", 0)))],
		["Контракт", "%d %s" % [years, _years_word(years)]],
		["Трансферы", "%d/%d" % [transfers, ATTR_MAX]],
		["Переговоры", "%d/%d" % [talks, ATTR_MAX]],
		["Стиль", TacticTypesScript.style_label(CoachTypesScript.primary_style_of(_coach))],
	]
	for fact in facts:
		_facts_host.add_child(_fact_chip(str(fact[0]), str(fact[1])))


func _fact_chip(caption: String, value: String) -> PanelContainer:
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
	val.add_theme_color_override("font_color", WeTokens.TEXT)
	val.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		val.add_theme_font_override("font", _title_font)
	box.add_child(val)
	return chip


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

	top.add_child(_quadrant_panel("Тренерские качества", _build_attributes_content()))
	top.add_child(_quadrant_panel("Карьера", _build_career_content()))
	bottom.add_child(_quadrant_panel("Стиль и схема", _build_tactics_content()))
	bottom.add_child(_quadrant_panel(
		"Трофеи",
		_placeholder_body("Трофеи появятся позже")
	))
	return root


func _build_attributes_content() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var attributes: Dictionary = _coach.get("attributes", {})
	if attributes.is_empty():
		box.add_child(_hint("Качества отсутствуют — начните новую игру"))
		return box
	for key in CoachTypesScript.ATTR_KEYS:
		var row := _stat_row(
			CoachTypesScript.attr_label(key),
			int(attributes.get(key, 1)),
			key == CoachTypesScript.ATTR_TRANSFERS
		)
		row.tooltip_text = CoachTypesScript.attr_tip(key)
		box.add_child(row)
	var note := Label.new()
	note.text = CoachTypesScript.attr_tip(CoachTypesScript.ATTR_TRANSFERS)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	note.add_theme_font_size_override("font_size", 11)
	box.add_child(note)
	return box


func _build_tactics_content() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	var primary_style := CoachTypesScript.primary_style_of(_coach)
	var backup_style := CoachTypesScript.backup_style_of(_coach)
	var primary_form := CoachTypesScript.primary_formation_of(_coach)
	var backup_form := CoachTypesScript.backup_formation_of(_coach)
	var rows := [
		["Основной стиль", TacticTypesScript.style_label(primary_style), TacticTypesScript.style_tip(primary_style)],
		["Запасной стиль", TacticTypesScript.style_label(backup_style), TacticTypesScript.style_tip(backup_style)],
		["Основная схема", TacticTypesScript.formation_label(primary_form), ""],
		["Запасная схема", TacticTypesScript.formation_label(backup_form), ""],
		["Характер", CoachTypesScript.style_label(str(_coach.get("style", ""))), "Высота линии и агрессия, не путать со стилем."],
	]
	for row in rows:
		box.add_child(_tactic_row(str(row[0]), str(row[1]), str(row[2])))
	var note := Label.new()
	note.text = "На матч чаще берёт своё, но не всегда. Стиль и схема всегда из одного ключа: без автобуса в атаке и без контроля в низком блоке."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	note.add_theme_font_size_override("font_size", 11)
	box.add_child(note)
	return box


func _tactic_row(caption: String, value: String, tip: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	if not tip.is_empty():
		row.tooltip_text = tip
	var cap := Label.new()
	cap.text = caption
	cap.custom_minimum_size.x = STAT_LABEL_WIDTH
	cap.clip_text = true
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	cap.add_theme_font_size_override("font_size", 12)
	row.add_child(cap)
	var val := Label.new()
	val.text = value
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	val.clip_text = true
	val.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	val.add_theme_color_override("font_color", WeTokens.TEXT)
	val.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		val.add_theme_font_override("font", _title_font)
	row.add_child(val)
	return row


func _build_career_content() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var career: Array = _coach.get("career", [])
	if career.is_empty():
		box.add_child(_hint("История карьеры появится позже"))
		return box
	for i in career.size():
		var entry: Variant = career[i]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		box.add_child(_career_row(entry, i % 2 == 1))
	return box


func _career_row(entry: Dictionary, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override(
		"panel",
		WeTokens.fill(Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0), 6, 8, 6)
	)
	var cols := VBoxContainer.new()
	cols.add_theme_constant_override("separation", 0)
	row.add_child(cols)
	var club_name := str(entry.get("club_name", "")).strip_edges()
	if club_name.is_empty():
		club_name = "Клуб #%d" % int(entry.get("club_id", 0))
	var title := Label.new()
	title.text = club_name
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 12)
	cols.add_child(title)
	var from_season := int(entry.get("season_from", 0))
	var to_season := int(entry.get("season_to", 0))
	var span := "Сезон %d — н.в." % from_season if to_season < 1 else "Сезоны %d–%d" % [from_season, to_season]
	var meta := Label.new()
	meta.text = "Главный тренер · %s" % span
	meta.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	meta.add_theme_font_size_override("font_size", 11)
	cols.add_child(meta)
	return row


func _quadrant_panel(title: String, content: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.0
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 10)
	)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	heading.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		heading.add_theme_font_override("font", _title_font)
	box.add_child(heading)
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
	wrap.add_child(label)
	return wrap


func _stat_row(label_text: String, value: int, emphasize: bool) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = STAT_LABEL_WIDTH
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.add_theme_color_override("font_color", WeTokens.ACCENT if emphasize else WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 12)
	if emphasize and _title_font != null:
		label.add_theme_font_override("font", _title_font)
	row.add_child(label)
	var level := clampi(value, 0, ATTR_MAX)
	var fill_color := _attr_color(level)
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
	value_label.add_theme_color_override("font_color", fill_color)
	value_label.add_theme_font_size_override("font_size", 12)
	if _title_font != null:
		value_label.add_theme_font_override("font", _title_font)
	row.add_child(value_label)
	return row


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
