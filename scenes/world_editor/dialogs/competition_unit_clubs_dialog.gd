extends WeModal
## Checkbox picker for clubs assigned to a competition unit.


signal clubs_submitted(unit_id: int, club_ids: Array)

const SEARCH_FIELD := preload("res://ui/components/we_search_field.tscn")

var _unit_id: int = -1
var _clubs: Array = []
var _selected: Dictionary = {} # club_id -> true
var _busy: bool = false

var _search: WeSearchField
var _list: VBoxContainer
var _count_label: Label


func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 110
	set_card_size(560, 560)
	set_body_separation(10)
	_build_body()
	confirmed.connect(_on_confirm)
	cancelled.connect(_on_cancel)


func _build_body() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	get_body().add_child(header)

	_search = SEARCH_FIELD.instantiate()
	_search.placeholder = "Поиск клуба…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_search)
	_search.text_changed.connect(func(_t): _request_render())

	_count_label = Label.new()
	_count_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_count_label.add_theme_font_size_override("font_size", 12)
	_count_label.custom_minimum_size = Vector2(90, 0)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(_count_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func open_picker(unit_id: int, unit_title: String, clubs: Array, selected_ids: Array) -> void:
	_unit_id = unit_id
	_clubs = clubs
	_selected.clear()
	for club_id in selected_ids:
		_selected[int(club_id)] = true
	set_title("Клубы: %s" % unit_title)
	set_confirm_text("Сохранить")
	if _search != null:
		_search.text = ""
	_render_list()
	clear_error()
	set_busy(false)
	open()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)


func _request_render() -> void:
	call_deferred("_render_list")


func _render_list() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var query := ""
	if _search != null:
		query = _search.text.strip_edges().to_lower()

	var visible_count := 0
	for club in _clubs:
		if not _matches(club, query):
			continue
		visible_count += 1
		_list.add_child(_make_row(club))

	if visible_count == 0:
		var empty := Label.new()
		if query.is_empty():
			empty.text = "Нет клубов для выбора."
		else:
			empty.text = "Ничего не найдено."
		empty.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 12)
		_list.add_child(empty)

	_count_label.text = "выбрано: %d" % _selected.size()


func _matches(club: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var name_text: String = str(club.get("name", "")).to_lower()
	var short_name: String = str(club.get("short_name", "")).to_lower()
	var country_name: String = str(club.get("country_name", "")).to_lower()
	return (
		name_text.find(query) >= 0
		or short_name.find(query) >= 0
		or country_name.find(query) >= 0
	)


func _make_row(club: Dictionary) -> PanelContainer:
	var club_id: int = int(club.get("id", 0))
	var checked: bool = _selected.has(club_id)

	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _row_style(checked, false))

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	row.add_child(inner)

	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(18, 18)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box_bg: Color = WeTokens.ACCENT if checked else WeTokens.INSET
	var box_border: Color = WeTokens.ACCENT if checked else WeTokens.BORDER_STRONG
	box.add_theme_stylebox_override("panel", WeTokens.panel(box_bg, box_border, 4, 0))
	inner.add_child(box)

	var mark := Label.new()
	mark.text = "✓" if checked else ""
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", Color(0.05, 0.12, 0.12, 1.0))
	mark.add_theme_font_size_override("font_size", 12)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(mark)

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 0)
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(texts)

	var title := Label.new()
	title.text = str(club.get("name", ""))
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 13)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	texts.add_child(title)

	var country_name: String = str(club.get("country_name", ""))
	if not country_name.is_empty():
		var meta := Label.new()
		meta.text = country_name
		meta.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		meta.add_theme_font_size_override("font_size", 11)
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		texts.add_child(meta)

	row.mouse_entered.connect(func():
		row.add_theme_stylebox_override("panel", _row_style(checked, true))
	)
	row.mouse_exited.connect(func():
		row.add_theme_stylebox_override("panel", _row_style(checked, false))
	)
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_toggle_club(club_id)
				row.accept_event()
	)
	return row


func _row_style(checked: bool, hovered: bool) -> StyleBoxFlat:
	var bg: Color = WeTokens.ACCENT_SOFT if checked else Color(1, 1, 1, 0.02)
	if hovered and not checked:
		bg = Color(1, 1, 1, 0.06)
	var border: Color = WeTokens.BORDER
	if checked:
		border = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35)
	return WeTokens.panel(bg, border, 8, 8)


func _toggle_club(club_id: int) -> void:
	if _selected.has(club_id):
		_selected.erase(club_id)
	else:
		_selected[club_id] = true
	_request_render()


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
