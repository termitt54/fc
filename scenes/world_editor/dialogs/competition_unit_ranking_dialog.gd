extends WeModal
## Choose which standing criteria apply and their priority order.


signal ranking_submitted(unit_id: int, order: Array)

const BUTTON_SCRIPT := preload("res://ui/components/we_button.gd")

var _unit_id: int = -1
var _order: Array = []
var _busy: bool = false

var _active_list: VBoxContainer
var _unused_list: VBoxContainer


func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 110
	set_card_size(560, 620)
	set_body_separation(10)
	_build_body()
	confirmed.connect(_on_confirm)
	cancelled.connect(_on_cancel)


func _build_body() -> void:
	var hint := Label.new()
	hint.text = "Включите критерии и расставьте приоритет сверху вниз (1 — главный)."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	get_body().add_child(hint)

	var active_title := Label.new()
	active_title.text = "Приоритет"
	active_title.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	active_title.add_theme_font_size_override("font_size", 11)
	get_body().add_child(active_title)

	var active_scroll := ScrollContainer.new()
	active_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	active_scroll.custom_minimum_size = Vector2(0, 260)
	active_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(active_scroll)

	_active_list = VBoxContainer.new()
	_active_list.add_theme_constant_override("separation", 4)
	_active_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_scroll.add_child(_active_list)

	var unused_title := Label.new()
	unused_title.text = "Не используются"
	unused_title.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	unused_title.add_theme_font_size_override("font_size", 11)
	get_body().add_child(unused_title)

	var unused_scroll := ScrollContainer.new()
	unused_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unused_scroll.custom_minimum_size = Vector2(0, 140)
	unused_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(unused_scroll)

	_unused_list = VBoxContainer.new()
	_unused_list.add_theme_constant_override("separation", 4)
	_unused_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unused_scroll.add_child(_unused_list)


func open_editor(unit_id: int, unit_title: String, order: Array) -> void:
	_unit_id = unit_id
	_order = RankingCriteria.normalize_order(order)
	set_title("Места в группе: %s" % unit_title)
	set_confirm_text("Сохранить")
	_render()
	clear_error()
	set_busy(false)
	open()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)


func _render() -> void:
	_clear_list(_active_list)
	_clear_list(_unused_list)

	if _order.is_empty():
		var empty := Label.new()
		empty.text = "Добавьте хотя бы один критерий."
		empty.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 12)
		_active_list.add_child(empty)
	else:
		for i in _order.size():
			_active_list.add_child(_make_active_row(i, str(_order[i])))

	var unused: Array = RankingCriteria.unused_codes(_order)
	if unused.is_empty():
		var none := Label.new()
		none.text = "Все критерии уже в приоритете."
		none.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		none.add_theme_font_size_override("font_size", 12)
		_unused_list.add_child(none)
	else:
		for code in unused:
			_unused_list.add_child(_make_unused_row(str(code)))


func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()


func _make_active_row(index: int, code: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 8, 8)
	)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	row.add_child(inner)

	var rank := Label.new()
	rank.text = str(index + 1)
	rank.custom_minimum_size = Vector2(22, 0)
	rank.add_theme_color_override("font_color", WeTokens.ACCENT)
	rank.add_theme_font_size_override("font_size", 13)
	inner.add_child(rank)

	var title := Label.new()
	title.text = RankingCriteria.label(code)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 13)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(title)

	inner.add_child(_make_icon_button("↑", index > 0, func(): _move(index, -1)))
	inner.add_child(_make_icon_button("↓", index < _order.size() - 1, func(): _move(index, 1)))
	inner.add_child(_make_icon_button("×", _order.size() > 1, func(): _remove(index)))
	return row


func _make_unused_row(code: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(Color(1, 1, 1, 0.02), WeTokens.BORDER, 8, 8)
	)

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 8)
	row.add_child(inner)

	var title := Label.new()
	title.text = RankingCriteria.label(code)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	title.add_theme_font_size_override("font_size", 13)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	inner.add_child(title)

	var add_btn := Button.new()
	add_btn.set_script(BUTTON_SCRIPT)
	add_btn.text = "Добавить"
	add_btn.focus_mode = Control.FOCUS_NONE
	add_btn.custom_minimum_size = Vector2(0, 28)
	add_btn.add_theme_font_size_override("font_size", 11)
	add_btn.kind = WeButton.Kind.GHOST
	add_btn.pressed.connect(func(): _add(code))
	inner.add_child(add_btn)
	return row


func _make_icon_button(text: String, enabled: bool, on_press: Callable) -> Button:
	var button := Button.new()
	button.set_script(BUTTON_SCRIPT)
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(32, 28)
	button.add_theme_font_size_override("font_size", 12)
	button.kind = WeButton.Kind.GHOST
	if enabled:
		button.pressed.connect(on_press)
	return button


func _move(index: int, delta: int) -> void:
	var target := index + delta
	if target < 0 or target >= _order.size():
		return
	var tmp = _order[index]
	_order[index] = _order[target]
	_order[target] = tmp
	_render()


func _remove(index: int) -> void:
	if _order.size() <= 1 or index < 0 or index >= _order.size():
		return
	_order.remove_at(index)
	_render()


func _add(code: String) -> void:
	if not RankingCriteria.is_valid(code) or code in _order:
		return
	_order.append(code)
	_render()


func _on_confirm() -> void:
	if _busy or _unit_id < 1:
		return
	var order := RankingCriteria.normalize_order(_order)
	if order.is_empty():
		show_error("Нужен хотя бы один критерий.")
		return
	ranking_submitted.emit(_unit_id, order)
	close()


func _on_cancel() -> void:
	if _busy:
		return
	close()
