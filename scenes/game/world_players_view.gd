extends VBoxContainer
## Global player directory for the in-game hub.


signal player_requested(player_id: int)
signal club_requested(club_id: int)
signal country_requested(country_id: int)
signal closed

const PlayerTypesScript := preload("res://game/player_types.gd")

const FLAG_H := 14
const LOGO_SIZE := 22
const COL_FLAG := 36.0
const COL_CLUB := 28.0
const COL_POS := 40.0
const COL_AGE := 48.0
const COL_CA := 48.0
const COL_PA := 48.0

const COLUMNS := [
	{"key": "country_name", "label": "Флаг", "width": COL_FLAG, "numeric": false},
	{"key": "club_name", "label": "Клуб", "width": COL_CLUB, "numeric": false},
	{"key": "name", "label": "Игрок", "width": 0.0, "numeric": false},
	{"key": "position", "label": "Поз", "width": COL_POS, "numeric": false},
	{"key": "age", "label": "Возраст", "width": COL_AGE, "numeric": true},
	{"key": "ca", "label": "CA", "width": COL_CA, "numeric": true},
	{"key": "pa", "label": "PA", "width": COL_PA, "numeric": true},
]

const MODE_ALL := "all"
const MODE_MARKET := "market"

const ListPageScript := preload("res://game/list_page.gd")

var _rows: Array = []
var _page := 0
var _sort_key := "ca"
var _sort_asc := false
var _tex_cache: Dictionary = {}
var _header_buttons: Dictionary = {}
var _count_label: Label
var _title_label: Label
var _header_host: HBoxContainer
var _list_host: VBoxContainer
var _scroll: ScrollContainer
var _pager: HBoxContainer
var _page_label: Label
var _page_prev: Button
var _page_next: Button
var _mode := MODE_ALL


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_build_chrome()


func is_open() -> bool:
	return visible


func set_mode(mode: String) -> void:
	_mode = MODE_MARKET if mode == MODE_MARKET else MODE_ALL
	if _title_label != null:
		_title_label.text = "Рынок" if _mode == MODE_MARKET else "Игроки"


func refresh() -> void:
	if _mode == MODE_MARKET:
		_rows = GameSession.get_market_player_rows()
	else:
		_rows = GameSession.get_all_player_rows()
	_page = 0
	_sort_rows()
	_rebuild_header()
	_rebuild_list()


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
	_title_label.text = "Игроки"
	_title_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_title_label.add_theme_font_size_override("font_size", 18)
	var title_font := WeTokens.font_semibold()
	if title_font != null:
		_title_label.add_theme_font_override("font", title_font)
	title_row.add_child(_title_label)

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
			button.pressed.connect(_on_sort_pressed.bind(key, bool(column["numeric"])))
			_header_host.add_child(button)
			_header_buttons[key] = button
	_refresh_header_labels()


func _refresh_header_labels() -> void:
	for column in COLUMNS:
		var key := str(column["key"])
		if not _header_buttons.has(key):
			continue
		var button: Button = _header_buttons[key]
		button.text = _header_text(column)
		button.add_theme_color_override(
			"font_color",
			WeTokens.ACCENT if key == _sort_key else WeTokens.TEXT_DIM
		)
		button.add_theme_color_override("font_hover_color", WeTokens.TEXT)


func _header_text(column: Dictionary) -> String:
	var label := str(column["label"])
	if str(column["key"]) != _sort_key:
		return label
	return "%s %s" % [label, "▲" if _sort_asc else "▼"]


func _on_sort_pressed(key: String, numeric: bool) -> void:
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = not numeric
	_page = 0
	_sort_rows()
	_refresh_header_labels()
	_rebuild_list()


func _sort_rows() -> void:
	_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var cmp := _compare_rows(a, b)
		if cmp == 0:
			return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
		return cmp < 0 if _sort_asc else cmp > 0
	)


func _compare_rows(a: Dictionary, b: Dictionary) -> int:
	var left: Variant = a.get(_sort_key, "")
	var right: Variant = b.get(_sort_key, "")
	if typeof(left) == TYPE_INT or typeof(left) == TYPE_FLOAT \
		or typeof(right) == TYPE_INT or typeof(right) == TYPE_FLOAT:
		var ln := float(left)
		var rn := float(right)
		if ln < rn:
			return -1
		if ln > rn:
			return 1
		return 0
	var ls := str(left)
	var rs := str(right)
	if _sort_key == "position":
		ls = PlayerTypesScript.position_label(ls) if not ls.is_empty() else "—"
		rs = PlayerTypesScript.position_label(rs) if not rs.is_empty() else "—"
	return ls.nocasecmp_to(rs)


func _rebuild_list() -> void:
	for child in _list_host.get_children():
		child.free()
	if _mode == MODE_MARKET:
		_count_label.text = "%d свободных агентов" % _rows.size()
	else:
		_count_label.text = "%d игроков" % _rows.size()
	_page = ListPageScript.clamp_index(_page, _rows.size())
	_update_pager()
	if _rows.is_empty():
		var empty := Label.new()
		empty.text = "Свободных агентов нет." if _mode == MODE_MARKET else "Игроки ещё не сгенерированы."
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
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 10)
	cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(cols)

	cols.add_child(_flag_cell(row))
	cols.add_child(_club_cell(row))
	cols.add_child(_name_cell(row))
	cols.add_child(_text_cell(_position_text(row), COL_POS, WeTokens.TEXT_MUTED))
	cols.add_child(_text_cell(str(int(row.get("age", 0))), COL_AGE, WeTokens.TEXT))
	cols.add_child(_text_cell(str(int(row.get("ca", 0))), COL_CA, WeTokens.ACCENT))
	cols.add_child(_text_cell(str(int(row.get("pa", 0))), COL_PA, Color(0.78, 0.84, 0.9, 1.0)))

	var player_id := int(row.get("id", 0))
	panel.gui_input.connect(_on_row_gui_input.bind(player_id))
	panel.mouse_entered.connect(_on_row_hover.bind(panel, true, zebra))
	panel.mouse_exited.connect(_on_row_hover.bind(panel, false, zebra))
	return panel


func _flag_cell(row: Dictionary) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(COL_FLAG, LOGO_SIZE)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var flag := _make_flag(str(row.get("flag_path", "")))
	wrap.add_child(flag)
	var country_id := int(row.get("country_id", 0))
	if country_id > 0:
		wrap.gui_input.connect(_on_icon_gui_input.bind(func(): country_requested.emit(country_id)))
	wrap.tooltip_text = str(row.get("country_name", ""))
	return wrap


func _club_cell(row: Dictionary) -> Control:
	var wrap := CenterContainer.new()
	wrap.custom_minimum_size = Vector2(COL_CLUB, LOGO_SIZE)
	var club_id := int(row.get("club_id", 0))
	if club_id < 1:
		var mark := Label.new()
		mark.text = "—"
		mark.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		mark.add_theme_font_size_override("font_size", 13)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(mark)
		wrap.tooltip_text = "Свободный агент"
		return wrap
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	wrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	wrap.add_child(_make_logo(str(row.get("logo_path", "")), LOGO_SIZE))
	wrap.gui_input.connect(_on_icon_gui_input.bind(func(): club_requested.emit(club_id)))
	wrap.tooltip_text = str(row.get("club_name", ""))
	return wrap


func _name_cell(row: Dictionary) -> Control:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 6)
	var name := Label.new()
	name.text = str(row.get("name", ""))
	if name.text.is_empty():
		name.text = "Игрок #%d" % int(row.get("id", 0))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_color_override("font_color", WeTokens.TEXT)
	name.add_theme_font_size_override("font_size", 13)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name)
	if bool(row.get("is_youth", false)):
		box.add_child(_name_badge("мол."))
	elif bool(row.get("is_free_agent", false)) and _mode == MODE_ALL:
		box.add_child(_name_badge("св."))
	return box


func _name_badge(text: String) -> Label:
	var badge := Label.new()
	badge.text = text
	badge.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	badge.add_theme_font_size_override("font_size", 11)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


func _text_cell(text: String, width: float, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _position_text(row: Dictionary) -> String:
	var code := str(row.get("position", ""))
	if code.is_empty():
		return "—"
	return PlayerTypesScript.position_label(code)


func _on_row_gui_input(event: InputEvent, player_id: int) -> void:
	if player_id < 1:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			player_requested.emit(player_id)


func _on_icon_gui_input(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			callback.call()
			# Stop the row underneath from also opening the player.
			get_viewport().set_input_as_handled()


func _on_row_hover(panel: PanelContainer, hovered: bool, zebra: bool) -> void:
	var bg := Color(1, 1, 1, 0.08) if hovered else (Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0))
	panel.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 8, 5))


func _apply_col_size(control: Control, width: float) -> void:
	if width <= 0.0:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		control.custom_minimum_size = Vector2(width, 0)
		control.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


func _make_flag(path: String) -> Control:
	var tex := _load_texture(path)
	if tex == null:
		return _placeholder(Vector2(20, FLAG_H))
	var display := WeTokens.fit_size(
		Vector2i(tex.get_width(), tex.get_height()), FLAG_H, 16, 28
	)
	return WeTokens.make_tex_rect(tex, display)


func _make_logo(path: String, size: int) -> Control:
	var tex := _load_texture(path)
	if tex == null:
		return _placeholder(Vector2(size, size))
	return WeTokens.make_tex_rect(tex, Vector2(size, size))


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
	var image := Image.new()
	if image.load(abs_path) != OK:
		_tex_cache[path] = null
		return null
	var texture := WeTokens.texture_from_image(image)
	_tex_cache[path] = texture
	return texture
