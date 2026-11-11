extends WeModal
## Readable club picker with stable selection, logos and reputation sorting.

signal clubs_submitted(unit_id: int, club_ids: Array)

const SEARCH_FIELD := preload("res://ui/components/we_search_field.tscn")
const SELECT_FIELD := preload("res://ui/components/we_select_field.tscn")
const SORT_REPUTATION_DESC := 0
const SORT_REPUTATION_ASC := 1
const SORT_NAME := 2
const CHECK_SIZE := 20
const LOGO_SIZE := 36
const RATING_W := 112
const ROW_GAP := 10
const ROW_H := 60

var _hint_label: Label
var _national := false
var _unit_id: int = -1
var _clubs: Array = []
var _selected: Dictionary = {}
var _taken: Dictionary = {}
var _busy: bool = false
var _render_pending: bool = false
var _logo_cache: Dictionary = {}
var _rows: Dictionary = {}
var _search: WeSearchField
var _sort: WeSelectField
var _clear_button: WeButton
var _list: VBoxContainer
var _scroll: ScrollContainer
var _count_label: Label
var _hidden_label: Label
var _results_label: Label
var _header_gutter: Control


func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 110
	set_body_separation(12)
	_build_body()
	_fit_card()
	get_viewport().size_changed.connect(_fit_card)
	confirmed.connect(_on_confirm)
	cancelled.connect(_on_cancel)


func _fit_card() -> void:
	var available := get_viewport_rect().size
	set_card_size(minf(780, available.x - 40), minf(720, available.y - 40))
	_scroll.custom_minimum_size.y = maxf(100, minf(420, available.y - 350))
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_sync_header_gutter()


func _build_body() -> void:
	var hint := _label("Выберите клубы для участия в турнире", 13, WeTokens.TEXT_MUTED)
	get_body().add_child(hint)
	_hint_label = hint

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	get_body().add_child(filters)
	_search = SEARCH_FIELD.instantiate()
	_search.placeholder = "Поиск по названию или стране…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filters.add_child(_search)
	_search.custom_minimum_size.y = 36
	_search.text_changed.connect(func(_text): _request_render())

	_sort = SELECT_FIELD.instantiate()
	_sort.compact = true
	_sort.label = ""
	_sort.custom_minimum_size.x = 248
	_sort.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_sort.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	filters.add_child(_sort)
	if _sort.has_node("%Label"):
		(_sort.get_node("%Label") as CanvasItem).visible = false
	var sort_chrome := _sort.get_node_or_null("%Chrome") as Control
	if sort_chrome != null:
		sort_chrome.custom_minimum_size.y = 36
	_sort.set_items([
		{"id": SORT_REPUTATION_DESC, "label": "Репутация: по убыванию"},
		{"id": SORT_REPUTATION_ASC, "label": "Репутация: по возрастанию"},
		{"id": SORT_NAME, "label": "Название: А–Я"},
	], SORT_REPUTATION_DESC)
	_sort.item_selected.connect(func(_index): _request_render())

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 12)
	get_body().add_child(toolbar)
	_count_label = _label("", 13, WeTokens.ACCENT)
	_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	toolbar.add_child(_count_label)
	_hidden_label = _label("", 12, WeTokens.TEXT_DIM)
	_hidden_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hidden_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hidden_label.clip_text = true
	_hidden_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	toolbar.add_child(_hidden_label)
	_clear_button = WeButton.new()
	_clear_button.text = "Убрать всех"
	_clear_button.kind = WeButton.Kind.GHOST
	_clear_button.focus_mode = Control.FOCUS_NONE
	_clear_button.custom_minimum_size = Vector2(132, 36)
	_clear_button.pressed.connect(_clear_selection)
	toolbar.add_child(_clear_button)

	var columns := PanelContainer.new()
	columns.add_theme_stylebox_override("panel", WeTokens.fill(Color(0, 0, 0, 0.18), 8, ROW_GAP, 6))
	get_body().add_child(columns)
	var column_row := HBoxContainer.new()
	column_row.add_theme_constant_override("separation", ROW_GAP)
	columns.add_child(column_row)
	column_row.add_child(_spacer(CHECK_SIZE))
	column_row.add_child(_spacer(LOGO_SIZE))
	_results_label = _label("", 11, WeTokens.TEXT_DIM)
	_results_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_results_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column_row.add_child(_results_label)
	var reputation_header := _label("РЕПУТАЦИЯ", 11, WeTokens.TEXT_DIM)
	reputation_header.custom_minimum_size.x = RATING_W
	reputation_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reputation_header.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column_row.add_child(reputation_header)
	_header_gutter = Control.new()
	_header_gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column_row.add_child(_header_gutter)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	get_body().add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_scroll.get_v_scroll_bar().visibility_changed.connect(_sync_header_gutter)


static func is_listed(club_id: int, selected: Dictionary, taken: Dictionary) -> bool:
	return not taken.has(club_id) or selected.has(club_id)


func open_picker(unit_id: int, unit_title: String, clubs: Array, selected_ids: Array, national: bool = false, taken_ids: Array = []) -> void:
	_national = national
	_hint_label.text = "Выберите национальные сборные для участия в турнире" if national else "Выберите клубы для участия в турнире"
	_unit_id = unit_id
	_clubs = clubs.duplicate()
	_logo_cache.clear()
	_selected.clear()
	_taken.clear()
	for club_id in selected_ids:
		_selected[int(club_id)] = true
	for club_id in taken_ids:
		var taken_id := int(club_id)
		if taken_id > 0:
			_taken[taken_id] = true
	set_title(("Сборные: %s" if national else "Клубы: %s") % unit_title)
	set_confirm_text("Сохранить")
	if _clear_button != null:
		_clear_button.text = "Убрать всех"
	_search.text = ""
	_sort.set_items([
		{"id": SORT_REPUTATION_DESC, "label": "Репутация: по убыванию"},
		{"id": SORT_REPUTATION_ASC, "label": "Репутация: по возрастанию"},
		{"id": SORT_NAME, "label": "Название: А–Я"},
	], SORT_REPUTATION_DESC)
	_render_list()
	_scroll.scroll_vertical = 0
	clear_error()
	set_busy(false)
	_fit_card()
	open()
	_search.grab_search_focus()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)
	if _sort != null:
		_sort.editable = not busy
	if _clear_button != null:
		_clear_button.disabled = busy or _selected.is_empty()
	if _search != null:
		_search.editable = not busy
	for data in _rows.values():
		(data["row"] as Button).disabled = busy


func _request_render() -> void:
	if _render_pending:
		return
	_render_pending = true
	call_deferred("_render_list")


func _render_list() -> void:
	_render_pending = false
	if _list == null:
		return
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var query := _search.text.strip_edges().to_lower()
	var ordered: Array = []
	var available := 0
	var hidden := 0
	for club in _clubs:
		var club_id := int(club.get("id", 0))
		if not is_listed(club_id, _selected, _taken):
			hidden += 1
			continue
		available += 1
		ordered.append(club)
	ordered.sort_custom(_club_before)
	var visible_count := 0
	for club in ordered:
		if not _matches(club, query):
			continue
		visible_count += 1
		_list.add_child(_make_row(club))
	if visible_count == 0:
		var empty_text := "Клубы не найдены. Попробуйте другое название или страну."
		if query.is_empty():
			empty_text = "Свободных клубов нет: все уже в других дивизионах." if hidden > 0 else "Нет клубов для выбора."
		var empty := _label(empty_text, 14, WeTokens.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.y = 80
		_list.add_child(empty)
	_results_label.text = "КЛУБЫ · %d" % visible_count if query.is_empty() else "КЛУБЫ · %d из %d" % [visible_count, available]
	if _hidden_label != null:
		_hidden_label.text = "" if hidden == 0 else "Скрыто %d — уже в других дивизионах" % hidden
	_update_count()
	call_deferred("_sync_header_gutter")


func _club_before(a: Dictionary, b: Dictionary) -> bool:
	if _sort_mode() != SORT_NAME:
		var left := int(a.get("reputation", 0))
		var right := int(b.get("reputation", 0))
		if left != right:
			return left > right if _sort_mode() == SORT_REPUTATION_DESC else left < right
	var name_order := str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", "")))
	if name_order != 0:
		return name_order < 0
	return int(a.get("id", 0)) < int(b.get("id", 0))


func _matches(club: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	for key in ["name", "short_name", "country_name"]:
		if str(club.get(key, "")).to_lower().contains(query):
			return true
	return false


func _sort_mode() -> int:
	if _sort == null or _sort.selected_id == null:
		return SORT_REPUTATION_DESC
	return int(_sort.selected_id)


func _clear_selection() -> void:
	if _busy or _selected.is_empty():
		return
	_selected.clear()
	_request_render()


func _spacer(width: int) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(width, 0)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _make_row(club: Dictionary) -> Button:
	var club_id := int(club.get("id", 0))
	var row := Button.new()
	row.custom_minimum_size.y = ROW_H
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.toggle_mode = true
	row.button_pressed = _selected.has(club_id)
	row.disabled = _busy
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.tooltip_text = "%s · %s · Репутация: %d / 1000" % [club.get("name", ""), club.get("country_name", ""), int(club.get("reputation", 0))]
	row.add_theme_stylebox_override("normal", _row_style(false, false))
	row.add_theme_stylebox_override("hover", _row_style(false, true))
	row.add_theme_stylebox_override("pressed", _row_style(true, false))
	row.add_theme_stylebox_override("hover_pressed", _row_style(true, true))
	row.add_theme_stylebox_override("focus", WeTokens.panel(Color.TRANSPARENT, WeTokens.ACCENT, 10, 0))

	var padding := MarginContainer.new()
	padding.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	padding.add_theme_constant_override("margin_left", ROW_GAP)
	padding.add_theme_constant_override("margin_right", ROW_GAP)
	padding.add_theme_constant_override("margin_top", 8)
	padding.add_theme_constant_override("margin_bottom", 8)
	padding.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(padding)
	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", ROW_GAP)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	padding.add_child(inner)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(CHECK_SIZE, CHECK_SIZE)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(box)
	var mark := _label("", 14, WeTokens.BG_DEEP)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mark)

	var logo_slot := PanelContainer.new()
	logo_slot.custom_minimum_size = Vector2(LOGO_SIZE, LOGO_SIZE)
	logo_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_slot.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 8, 4))
	inner.add_child(logo_slot)
	var logo := _load_logo(str(club.get("logo_path", "")))
	if logo != null:
		logo_slot.add_child(WeTokens.make_tex_rect(logo, Vector2(LOGO_SIZE - 8, LOGO_SIZE - 8)))
	else:
		var initials := ""
		for word in str(club.get("name", "?")).split(" ", false):
			initials += word.left(1).to_upper()
			if initials.length() == 2:
				break
		var fallback := _label(initials, 14, WeTokens.TEXT_MUTED)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		logo_slot.add_child(fallback)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.add_theme_constant_override("separation", 4)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)
	var title := _label(str(club.get("name", "")), 15, WeTokens.TEXT)
	title.add_theme_font_override("font", WeTokens.font_semibold())
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	texts.add_child(title)
	var country_name := str(club.get("country_name", ""))
	var meta := _label(country_name, 12, WeTokens.TEXT_MUTED)
	meta.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	meta.visible = not country_name.is_empty()
	texts.add_child(meta)

	var rating := VBoxContainer.new()
	rating.custom_minimum_size.x = RATING_W
	rating.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rating.add_theme_constant_override("separation", 5)
	rating.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(rating)
	var reputation := int(club.get("reputation", 0))
	var score := _label("%d / 1000" % reputation, 13, WeTokens.TEXT)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rating.add_child(score)
	var stars := ReputationStars.new()
	stars.reputation = reputation
	stars.star_size = 14
	stars.star_gap = 3
	stars.size_flags_horizontal = Control.SIZE_SHRINK_END
	rating.add_child(stars)
	# Keep the entire row clickable, including its rating.
	stars.set_deferred("mouse_filter", Control.MOUSE_FILTER_IGNORE)

	_rows[club_id] = {"row": row, "box": box, "mark": mark}
	_update_row(club_id)
	row.toggled.connect(func(checked: bool):
		if _busy:
			row.set_pressed_no_signal(_selected.has(club_id))
			return
		if checked:
			_selected[club_id] = true
		else:
			_selected.erase(club_id)
		if not checked and _taken.has(club_id):
			_request_render()
			return
		_update_row(club_id)
		_update_count()
	)
	return row


func _load_logo(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _logo_cache.has(path):
		return _logo_cache[path] as Texture2D
	var texture: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(path) == OK:
			texture = WeTokens.texture_from_image(image, 96)
	_logo_cache[path] = texture
	return texture


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _update_row(club_id: int) -> void:
	var data: Dictionary = _rows[club_id]
	var checked := _selected.has(club_id)
	(data["box"] as PanelContainer).add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.ACCENT if checked else WeTokens.INSET, WeTokens.ACCENT if checked else WeTokens.BORDER_STRONG, 6, 0))
	(data["mark"] as Label).text = "✓" if checked else ""


func _sync_header_gutter() -> void:
	if _header_gutter == null or _scroll == null:
		return
	var bar := _scroll.get_v_scroll_bar()
	_header_gutter.custom_minimum_size.x = bar.size.x if bar.visible else 0.0


func _update_count() -> void:
	_count_label.text = "Выбрано: %d" % _selected.size()
	if _clear_button != null:
		_clear_button.disabled = _busy or _selected.is_empty()


func _row_style(checked: bool, hovered: bool) -> StyleBoxFlat:
	var bg := WeTokens.INSET.lightened(0.035) if checked else WeTokens.INSET
	if hovered:
		bg = bg.lightened(0.045)
	var border := WeTokens.BORDER_FOCUS if checked else WeTokens.BORDER
	var style := WeTokens.panel(bg, border, 10, 0)
	if checked:
		style.border_width_left = 3
	return style


func _on_confirm() -> void:
	if _busy or _unit_id < 1:
		return
	var ids: Array = _selected.keys()
	ids.sort()
	clubs_submitted.emit(_unit_id, ids)
	close()


func _on_cancel() -> void:
	if _busy:
		return
	close()
