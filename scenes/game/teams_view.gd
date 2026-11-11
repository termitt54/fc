extends VBoxContainer

const NationalRatingScript = preload("res://game/national_rating.gd")
const ClubRatingScript = preload("res://game/club_rating.gd")
## Sortable, filterable directory of every club in the save.


signal club_requested(club_id: int)
signal country_requested(country_id: int)
signal closed
signal kind_changed

const ListPageScript := preload("res://game/list_page.gd")

const LOGO_SIZE := 26
const FLAG_H := 14
const FLAG_SLOT := 28.0
const COL_GAP := 10
const ROW_H := 42

const COLUMNS := [
	{"key": "name", "label": "Клуб", "width": 0.0, "numeric": false},
	{"key": "reputation", "label": "Репутация", "width": 108.0, "numeric": true,
		"hint": "Репутация клуба"},
	{"key": "strength_total", "label": "Общая сила", "width": 124.0, "numeric": true,
		"hint": "Сумма рейтингов всех игроков клуба: основной состав, резерв и молодёжка"},
	{"key": "strength_avg", "label": "Средняя сила", "width": 132.0, "numeric": true,
		"hint": "Средний рейтинг тех же игроков"},
	{"key": "budget", "label": "Финансы", "width": 124.0, "numeric": true,
		"hint": "Текущий бюджет клуба"},
]

const NATIONAL_COLUMNS := [
	{"key": "name", "label": "Сборная", "width": 0.0, "numeric": false},
	{"key": "rank", "label": "Место", "width": 58.0, "numeric": true},
	{"key": "elo", "label": "Elo", "width": 90.0, "numeric": true},
	{"key": "change", "label": "За турнир", "width": 100.0, "numeric": true, "hint": "Изменение Elo в последнем начатом турнире"},
	{"key": "talent", "label": "Талант", "width": 70.0, "numeric": true},
	{"key": "player_count", "label": "Игроков", "width": 80.0, "numeric": true, "hint": "Все действующие игроки этой национальности, включая молодёжь и свободных агентов"},
	{"key": "coach_name", "label": "Тренер", "width": 180.0, "numeric": false},
]

const NATIONAL_REPUTATION_COLUMNS := [
	{"key": "name", "label": "Сборная", "width": 0.0, "numeric": false},
	{"key": "reputation", "label": "Репутация", "width": 108.0, "numeric": true},
	{"key": "reputation_change", "label": "За турнир", "width": 100.0, "numeric": true, "hint": "Изменение репутации относительно начала последнего турнира сборной"},
	{"key": "talent", "label": "Талант", "width": 70.0, "numeric": true},
	{"key": "player_count", "label": "Игроков", "width": 80.0, "numeric": true},
	{"key": "coach_name", "label": "Тренер", "width": 180.0, "numeric": false},
]

const CLUB_RATING_COLUMNS := [
	{"key": "name", "label": "Клуб", "width": 0.0, "numeric": false},
	{"key": "rank", "label": "Место", "width": 58.0, "numeric": true},
	{"key": "elo", "label": "Elo", "width": 90.0, "numeric": true},
	{"key": "change", "label": "За сезон", "width": 100.0, "numeric": true},
	{"key": "reputation", "label": "Репутация", "width": 108.0, "numeric": true},
	{"key": "attraction", "label": "Привлекательность", "width": 150.0, "numeric": true, "hint": "Репутация с поправкой за Elo. Поправка до ±60, полный вес после 20 отслеженных матчей. Также игрок учитывает зарплату, роль и силу состава."},
]

var _elo_mode := false
var _title: Label
var _national := false
var _tabs: WeTabBar
var _subtitle: Label
var _bounds: HBoxContainer
var _all_rows: Array = []
var _rows: Array = []
var _page := 0
var _sort_key := "reputation"
var _sort_asc := false
var _query := ""
var _country_id := 0
var _suppress := false
var _identity_width := 240.0
var _tex_cache: Dictionary = {}
var _bound_inputs: Dictionary = {}

var _count_label: Label
var _header_host: HBoxContainer
var _list_host: VBoxContainer
var _scroll: ScrollContainer
var _table: VBoxContainer
var _pager: HBoxContainer
var _page_label: Label
var _page_prev: Button
var _page_next: Button
var _search: WeSearchField
var _country: WeSelectField


func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	_build_chrome()


func is_open() -> bool:
	return visible


func refresh() -> void:
	if _list_host == null:
		return
	_all_rows = NationalRatingScript.rows(GameSession) if _national else ClubRatingScript.rows(GameSession) if _elo_mode else GameSession.get_club_rows()
	_suppress = true
	_sync_countries()
	_suppress = false
	_apply_view()


func set_national(enabled: bool, elo_mode: bool = false) -> void:
	_national = enabled
	_elo_mode = elo_mode
	_sort_key = "elo" if _elo_mode else "reputation"
	_sort_asc = false
	if _tabs != null:
		_tabs.select(1 if enabled else 0, false)
		_tabs.visible = true
	if _title != null: _title.text = "Рейтинг" if _elo_mode else "Команды"
	if _bounds != null: _bounds.visible = not enabled and not _elo_mode
	if _search != null: _search.placeholder = "Название сборной" if enabled else "Название клуба или страна"
	if _subtitle != null:
		_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_subtitle.text = "Elo сборных · изменение за турнир" if _elo_mode and enabled else "Elo клубов · изменение за сезон · влияние на привлекательность игрокам" if _elo_mode else "Репутация сборных · изменение за турнир · талант и пул игроков" if enabled else "Репутация, сила состава и бюджет"
	_reset_filters(false)
	refresh()
	kind_changed.emit()


func _columns() -> Array:
	return (NATIONAL_COLUMNS if _national else CLUB_RATING_COLUMNS) if _elo_mode else NATIONAL_REPUTATION_COLUMNS if _national else COLUMNS


static func squad_totals(players: Array) -> Dictionary:
	var total := 0
	var count := 0
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		total += int(player.get("current_ability", player.get("overall", 0)))
		count += 1
	return {
		"total": total,
		"average": 0.0 if count == 0 else float(total) / float(count),
		"count": count,
	}


static func parse_bound(text: String) -> Variant:
	var cleaned := text.strip_edges().replace(" ", "").replace("€", "").replace(",", ".")
	if cleaned.is_empty() or cleaned == "-" or cleaned == "." or cleaned == "-.":
		return null
	if not cleaned.is_valid_float():
		return null
	return float(cleaned)


static func filtered(rows: Array, query: String, country_id: int, minimums: Dictionary) -> Array:
	var out: Array = []
	var needle := query.strip_edges().to_lower()
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if not _passes(row, needle, country_id, minimums):
			continue
		out.append(row)
	return out


static func sorted_rows(rows: Array, key: String, ascending: bool) -> Array:
	var copy := rows.duplicate()
	copy.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cmp := _compare(a, b, key)
		if cmp == 0:
			return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
		return cmp < 0 if ascending else cmp > 0
	)
	return copy


static func clubs_phrase(count: int) -> String:
	var n := absi(count) % 100
	var last := n % 10
	var word := "клубов"
	if n < 11 or n > 14:
		if last == 1:
			word = "клуб"
		elif last >= 2 and last <= 4:
			word = "клуба"
	return "%d %s" % [count, word]


static func grouped_int(value: int) -> String:
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var parts: PackedStringArray = PackedStringArray()
	while digits.length() > 3:
		parts.insert(0, digits.substr(digits.length() - 3, 3))
		digits = digits.substr(0, digits.length() - 3)
	parts.insert(0, digits)
	return sign + " ".join(parts)


static func money_short(amount: int) -> String:
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


static func money_full(amount: int) -> String:
	return "%s €" % grouped_int(amount)


static func _passes(row: Dictionary, needle: String, country_id: int, minimums: Dictionary) -> bool:
	if country_id > 0 and int(row.get("country_id", 0)) != country_id:
		return false
	if not needle.is_empty():
		var hay := ("%s %s" % [str(row.get("name", "")), str(row.get("country_name", ""))]).to_lower()
		if not hay.contains(needle):
			return false
	for key in minimums.keys():
		var bound: Variant = minimums[key]
		if bound == null:
			continue
		if float(row.get(key, 0)) < float(bound):
			return false
	return true


static func _compare(a: Dictionary, b: Dictionary, key: String) -> int:
	var left: Variant = a.get(key, "")
	var right: Variant = b.get(key, "")
	if key in ["name", "country_name", "coach_name"]:
		return str(left).nocasecmp_to(str(right))
	var ln := float(left)
	var rn := float(right)
	if ln < rn:
		return -1
	if ln > rn:
		return 1
	return 0


func _build_chrome() -> void:
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 12)
	add_child(title_row)

	var back := Button.new()
	back.text = "← Назад"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(0, 36)
	back.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	back.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.05), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.1), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.08), WeTokens.RADIUS_SM, 14, 8))
	back.add_theme_color_override("font_color", WeTokens.TEXT)
	back.add_theme_font_size_override("font_size", 13)
	var title_font := WeTokens.font_semibold()
	if title_font != null:
		back.add_theme_font_override("font", title_font)
	back.pressed.connect(func(): closed.emit())
	title_row.add_child(back)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(titles)
	var title := Label.new()
	title.text = "Команды"
	_title = title
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 18)
	if title_font != null:
		title.add_theme_font_override("font", title_font)
	titles.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Репутация, сила состава и бюджет"
	subtitle.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	subtitle.add_theme_font_size_override("font_size", 12)
	titles.add_child(subtitle)
	_subtitle = subtitle

	_count_label = Label.new()
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count_label.add_theme_color_override("font_color", WeTokens.ACCENT)
	_count_label.add_theme_font_size_override("font_size", 13)
	title_row.add_child(_count_label)

	_tabs = WeTabBar.new()
	_tabs.name = "TeamKindTabs"
	add_child(_tabs)
	_tabs.set_tabs(PackedStringArray(["Клубы", "Сборные"]))
	_tabs.tab_selected.connect(func(index: int): set_national(index == 1, _elo_mode))
	_build_filters()

	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 0)
	)
	add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(box)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(_scroll)

	_table = VBoxContainer.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.add_theme_constant_override("separation", 0)
	_scroll.add_child(_table)

	var header_wrap := PanelContainer.new()
	header_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_wrap.add_theme_stylebox_override("panel", WeTokens.fill(Color(0, 0, 0, 0.22), 0, 8, 6))
	_table.add_child(header_wrap)
	_header_host = HBoxContainer.new()
	_header_host.add_theme_constant_override("separation", COL_GAP)
	_header_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_wrap.add_child(_header_host)

	_list_host = VBoxContainer.new()
	_list_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_host.add_theme_constant_override("separation", 0)
	_table.add_child(_list_host)
	_build_pager(box)


func _build_filters() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 10)
	)
	add_child(card)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 8)
	card.add_child(stack)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	stack.add_child(top)
	_search = preload("res://ui/components/we_search_field.tscn").instantiate()
	_search.placeholder = "Название клуба или страна"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(220, 36)
	_search.text_changed.connect(_on_search_changed)
	top.add_child(_search)
	_search.custom_minimum_size.y = 36

	_country = preload("res://ui/components/we_select_field.tscn").instantiate()
	_country.label = ""
	_country.compact = true
	_country.custom_minimum_size.x = 220
	_country.item_selected.connect(_on_country_selected)
	top.add_child(_country)
	if _country.has_node("%Label"):
		(_country.get_node("%Label") as CanvasItem).visible = false
	var country_chrome := _country.get_node_or_null("%Chrome") as Control
	if country_chrome != null:
		country_chrome.custom_minimum_size.y = 36

	var bounds := HBoxContainer.new()
	_bounds = bounds
	bounds.add_theme_constant_override("separation", 8)
	stack.add_child(bounds)
	bounds.add_child(_bound_field("reputation", "Репутация от"))
	bounds.add_child(_bound_field("strength_total", "Общая сила от"))
	bounds.add_child(_bound_field("strength_avg", "Средняя сила от"))
	bounds.add_child(_bound_field("budget", "Бюджет от"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bounds.add_child(spacer)
	var reset := Button.new()
	reset.text = "Сбросить"
	reset.focus_mode = Control.FOCUS_NONE
	reset.custom_minimum_size = Vector2(108, 32)
	reset.size_flags_vertical = Control.SIZE_SHRINK_END
	reset.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	reset.add_theme_stylebox_override("normal", WeTokens.fill(Color(1, 1, 1, 0.05), WeTokens.RADIUS_SM, 12, 6))
	reset.add_theme_stylebox_override("hover", WeTokens.fill(Color(1, 1, 1, 0.1), WeTokens.RADIUS_SM, 12, 6))
	reset.add_theme_stylebox_override("pressed", WeTokens.fill(Color(1, 1, 1, 0.08), WeTokens.RADIUS_SM, 12, 6))
	reset.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	reset.add_theme_font_size_override("font_size", 13)
	reset.pressed.connect(_reset_filters)
	bounds.add_child(reset)


func _bound_field(key: String, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size.x = 148
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.add_theme_font_size_override("font_size", 11)
	caption_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	box.add_child(caption_label)
	var edit := LineEdit.new()
	edit.placeholder_text = "любое"
	edit.custom_minimum_size.y = 32
	edit.add_theme_font_size_override("font_size", 13)
	edit.add_theme_color_override("font_color", WeTokens.TEXT)
	edit.add_theme_color_override("font_placeholder_color", WeTokens.TEXT_DIM)
	edit.add_theme_color_override("caret_color", WeTokens.ACCENT)
	edit.add_theme_stylebox_override("normal", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 8))
	edit.add_theme_stylebox_override("focus", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER_FOCUS, WeTokens.RADIUS_SM, 8))
	edit.text_changed.connect(func(_text: String): _on_bounds_changed())
	box.add_child(edit)
	_bound_inputs[key] = edit
	return box


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


func _sync_countries() -> void:
	if _country == null:
		return
	var seen := {}
	var countries: Array = []
	for row in _all_rows:
		var id := int(row.get("country_id", 0))
		if id < 1 or seen.has(id):
			continue
		seen[id] = true
		var label := str(row.get("country_name", "")).strip_edges()
		if label.is_empty():
			label = "Страна #%d" % id
		countries.append({"id": id, "label": label})
	countries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["label"]).nocasecmp_to(str(b["label"])) < 0
	)
	var items: Array = [{"id": 0, "label": "Все страны"}]
	items.append_array(countries)
	if _country_id != 0 and not seen.has(_country_id):
		_country_id = 0
	_country.set_items(items, _country_id)


func _minimums() -> Dictionary:
	var out := {}
	if _national or _elo_mode: return out
	for key in _bound_inputs.keys():
		var bound: Variant = parse_bound(str(_bound_inputs[key].text))
		if bound != null:
			out[key] = bound
	return out


func _apply_view() -> void:
	_rows = sorted_rows(filtered(_all_rows, _query, _country_id, _minimums()), _sort_key, _sort_asc)
	_page = ListPageScript.clamp_index(_page, _rows.size())
	if _count_label != null:
		if _national:
			_count_label.text = "Сборных: %d" % _rows.size()
		elif _rows.size() == _all_rows.size():
			_count_label.text = clubs_phrase(_rows.size())
		else:
			_count_label.text = "%s из %d" % [clubs_phrase(_rows.size()), _all_rows.size()]
	_rebuild_list()


func _on_search_changed(value: String) -> void:
	if _suppress:
		return
	_query = value.strip_edges().to_lower()
	_page = 0
	_apply_view()


func _on_country_selected(_index: int) -> void:
	if _suppress or _country == null:
		return
	_country_id = int(_country.selected_id) if _country.selected_id != null else 0
	_page = 0
	_apply_view()


func _on_bounds_changed() -> void:
	if _suppress:
		return
	_page = 0
	_apply_view()


func _reset_filters(apply: bool = true) -> void:
	_suppress = true
	_query = ""
	_country_id = 0
	if _search != null:
		_search.text = ""
	if _country != null:
		_country.selected_id = 0
	for key in _bound_inputs.keys():
		(_bound_inputs[key] as LineEdit).text = ""
	_suppress = false
	_page = 0
	if apply: _apply_view()


func _on_sort_pressed(key: String, numeric: bool) -> void:
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = not numeric
	_page = 0
	_apply_view()


func _rebuild_list() -> void:
	_clear(_header_host)
	_clear(_list_host)
	_update_pager()
	var window := ListPageScript.slice_of(_rows, _page)
	_identity_width = _measure_identity(window)
	_build_header()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Нет сборных по этим условиям." if _national else "Нет клубов по этим условиям."
		empty.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 13)
		_list_host.add_child(empty)
		return
	for i in window.size():
		_list_host.add_child(_make_row(window[i], i % 2 == 1))
	if _scroll != null:
		_scroll.scroll_vertical = 0


func _measure_identity(window: Array) -> float:
	var font := WeTokens.font()
	var widest := 140.0
	for row in window:
		var text := str(row.get("name", ""))
		var width := float(text.length() * 8)
		if font != null:
			width = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 4.0
		widest = maxf(widest, width)
	return LOGO_SIZE + COL_GAP + widest + COL_GAP + FLAG_SLOT


func _build_header() -> void:
	var identity := HBoxContainer.new()
	identity.custom_minimum_size.x = _identity_width
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", COL_GAP)
	_header_host.add_child(identity)
	var logo_gap := Control.new()
	logo_gap.custom_minimum_size = Vector2(LOGO_SIZE, 0)
	identity.add_child(logo_gap)
	identity.add_child(_header_button(_columns()[0], true))
	var flag_gap := Control.new()
	flag_gap.custom_minimum_size = Vector2(FLAG_SLOT, 0)
	identity.add_child(flag_gap)
	for i in range(1, _columns().size()):
		_header_host.add_child(_header_button(_columns()[i], false))


func _header_button(column: Dictionary, expand: bool) -> Button:
	var key := str(column["key"])
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT if expand else HORIZONTAL_ALIGNMENT_RIGHT
	button.add_theme_font_size_override("font_size", 12)
	button.tooltip_text = str(column.get("hint", column["label"]))
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 8
	empty.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	if expand:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		button.custom_minimum_size.x = float(column["width"])
	var label := str(column["label"])
	if key == _sort_key:
		label = "%s %s" % [label, "▲" if _sort_asc else "▼"]
	button.text = label
	button.add_theme_color_override("font_color", WeTokens.ACCENT if key == _sort_key else WeTokens.TEXT_DIM)
	button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	button.pressed.connect(_on_sort_pressed.bind(key, bool(column["numeric"])))
	return button


func _make_row(row: Dictionary, zebra: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = ROW_H
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.fill(Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0), 0, 8, 6)
	)
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", COL_GAP)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(cols)

	cols.add_child(_identity_cell(row))
	if _national or _elo_mode:
		for column in _columns().slice(1):
			var key: String = column.key
			var value := str(row.get(key, "—"))
			if key in ["elo", "attraction"]: value = "%.1f" % float(row.get(key, 0.0))
			if key == "change": value = "%+.1f" % float(row.change)
			if key == "reputation_change": value = "%+d" % int(row.reputation_change)
			cols.add_child(_value_cell(value, float(column.width), WeTokens.ACCENT if key in ["elo", "reputation"] else WeTokens.SUCCESS if key in ["change", "reputation_change"] and float(row.get(key, 0)) > 0 else WeTokens.DANGER if key in ["change", "reputation_change"] and float(row.get(key, 0)) < 0 else WeTokens.TEXT, str(row.get("attraction_hint", value)) if key == "attraction" else str(column.get("hint", value))))
		panel.gui_input.connect(_on_row_gui_input.bind(int(row.id)))
		panel.mouse_entered.connect(_on_row_hover.bind(panel, true, zebra))
		panel.mouse_exited.connect(_on_row_hover.bind(panel, false, zebra))
		return panel
	cols.add_child(_value_cell(str(int(row.get("reputation", 0))), 108.0, WeTokens.ACCENT, str(row.get("reputation", 0))))
	var count := int(row.get("player_count", 0))
	var total_hint := "%s · %s" % [grouped_int(int(row.get("strength_total", 0))), clubs_players_hint(count)]
	cols.add_child(_value_cell(grouped_int(int(row.get("strength_total", 0))), 124.0, WeTokens.TEXT, total_hint))
	var avg := float(row.get("strength_avg", 0.0))
	cols.add_child(_value_cell("%.1f" % avg, 132.0, Color(0.78, 0.84, 0.9, 1.0), total_hint))
	var budget := int(row.get("budget", 0))
	var budget_color := WeTokens.DANGER if budget < 0 else WeTokens.SUCCESS
	cols.add_child(_value_cell(money_short(budget), 124.0, budget_color, money_full(budget)))

	var club_id := int(row.get("id", 0))
	panel.gui_input.connect(_on_row_gui_input.bind(club_id))
	panel.mouse_entered.connect(_on_row_hover.bind(panel, true, zebra))
	panel.mouse_exited.connect(_on_row_hover.bind(panel, false, zebra))
	return panel


static func clubs_players_hint(count: int) -> String:
	if count == 0:
		return "в клубе нет игроков"
	var n := absi(count) % 100
	var last := n % 10
	var word := "игроков"
	if n < 11 or n > 14:
		if last == 1:
			word = "игрок"
		elif last >= 2 and last <= 4:
			word = "игрока"
	return "%d %s клуба" % [count, word]


func _identity_cell(row: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.custom_minimum_size.x = _identity_width
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", COL_GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_make_logo(str(row.get("logo_path", ""))))

	var name := Label.new()
	name.text = str(row.get("name", ""))
	name.tooltip_text = name.text
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.clip_text = false
	name.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	name.add_theme_color_override("font_color", WeTokens.TEXT)
	name.add_theme_font_size_override("font_size", 14)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := WeTokens.font()
	if font != null:
		name.add_theme_font_override("font", font)
		name.custom_minimum_size.x = font.get_string_size(name.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	box.add_child(name)
	box.add_child(_flag_cell(row))
	return box


func _value_cell(text: String, width: float, color: Color, hint: String) -> Label:
	var label := Label.new()
	label.text = text
	label.tooltip_text = hint
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _flag_cell(row: Dictionary) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(FLAG_SLOT, LOGO_SIZE)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wrap.add_child(_make_flag(str(row.get("flag_path", ""))))
	var country_id := int(row.get("country_id", 0))
	var country_name := str(row.get("country_name", ""))
	wrap.tooltip_text = country_name if not country_name.is_empty() else "Страна"
	if country_id > 0:
		wrap.gui_input.connect(_on_flag_gui_input.bind(country_id))
	return wrap


func _make_flag(path: String) -> Control:
	var tex := _load_texture(path)
	if tex == null:
		return _placeholder(Vector2(20, FLAG_H))
	var display := WeTokens.fit_size(Vector2i(tex.get_width(), tex.get_height()), FLAG_H, 16, 28)
	return WeTokens.make_tex_rect(tex, display)


func _make_logo(path: String) -> Control:
	var tex := _load_texture(path)
	if tex == null:
		return _placeholder(Vector2(LOGO_SIZE, LOGO_SIZE))
	return WeTokens.make_tex_rect(tex, Vector2(LOGO_SIZE, LOGO_SIZE))


func _placeholder(size: Vector2) -> ColorRect:
	var box := ColorRect.new()
	box.custom_minimum_size = size
	box.color = Color(1, 1, 1, 0.08)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


func _load_texture(path: String) -> Texture2D:
	path = path.strip_edges()
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		_tex_cache[path] = null
		return null
	var image := Image.new()
	if image.load(abs_path) != OK:
		_tex_cache[path] = null
		return null
	var texture := WeTokens.texture_from_image(image)
	_tex_cache[path] = texture
	return texture


func _on_row_gui_input(event: InputEvent, club_id: int) -> void:
	if club_id < 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			club_requested.emit(club_id)


func _on_flag_gui_input(event: InputEvent, country_id: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			country_requested.emit(country_id)
			get_viewport().set_input_as_handled()


func _on_row_hover(panel: PanelContainer, hovered: bool, zebra: bool) -> void:
	var bg := Color(1, 1, 1, 0.08) if hovered else (Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0))
	panel.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 8, 6))


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
	_apply_view()


func _clear(host: Node) -> void:
	if host == null:
		return
	# Header buttons call this from their own pressed signal, so free() is illegal.
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
