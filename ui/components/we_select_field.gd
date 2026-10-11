class_name WeSelectField
extends VBoxContainer
## Custom labeled select — shared chrome + themed popup for the whole editor.


signal item_selected(index: int)
signal item_reselected(index: int)

const CHROME_HEIGHT := 40
const CHROME_HEIGHT_COMPACT := 32
const ITEM_HEIGHT := 36
const ITEM_HEIGHT_COMPACT := 30
const POPUP_MAX_HEIGHT := 280
const PLACEHOLDER := "Не выбрано"

@export var label: String = "Поле":
	set(value):
		label = value
		if _label != null:
			_label.text = label

@export var compact: bool = false:
	set(value):
		compact = value
		if is_node_ready():
			_apply_density()

var editable: bool = true:
	set(value):
		editable = value
		if is_node_ready():
			_refresh_chrome()
			if not editable:
				_close_popup()

var selected_id: Variant:
	get:
		if _selected_index < 0 or _selected_index >= _ids.size():
			return null
		return _ids[_selected_index]
	set(value):
		_select_by_id(value)

@onready var _label: Label = %Label
@onready var _chrome: PanelContainer = %Chrome
@onready var _value_label: Label = %ValueLabel
@onready var _chevron: Label = %Chevron

var _ids: Array = []
var _labels: PackedStringArray = PackedStringArray()
var _selected_index: int = -1
var _popup: PopupPanel
var _popup_list: VBoxContainer
var _hovered: bool = false


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_value_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	_chrome.mouse_filter = Control.MOUSE_FILTER_STOP
	_chrome.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chrome.gui_input.connect(_on_chrome_gui_input)
	_chrome.mouse_entered.connect(func():
		_hovered = true
		_refresh_chrome()
	)
	_chrome.mouse_exited.connect(func():
		_hovered = false
		_refresh_chrome()
	)

	_build_popup()
	_apply_density()
	_refresh_value_label()
	_refresh_chrome()


func _apply_density() -> void:
	add_theme_constant_override("separation", 3 if compact else 6)
	_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	_value_label.add_theme_font_size_override("font_size", 12 if compact else 14)
	_chevron.add_theme_font_size_override("font_size", 11 if compact else 12)
	_chrome.custom_minimum_size.y = CHROME_HEIGHT_COMPACT if compact else CHROME_HEIGHT


func set_items(items: Array, selected: Variant = null) -> void:
	_ids.clear()
	_labels = PackedStringArray()
	for item in items:
		var item_id: Variant = item.get("id", null) if item is Dictionary else item
		var item_label: String = str(item.get("label", item_id)) if item is Dictionary else str(item)
		_ids.append(item_id)
		_labels.append(item_label)

	if selected != null:
		_select_by_id(selected)
	elif not _ids.is_empty():
		_selected_index = 0
	else:
		_selected_index = -1
	_refresh_value_label()
	_refresh_chrome()


func clear_items() -> void:
	_ids.clear()
	_labels = PackedStringArray()
	_selected_index = -1
	_refresh_value_label()
	_close_popup()


func _select_by_id(value: Variant) -> void:
	for i in _ids.size():
		if _ids[i] == value:
			_selected_index = i
			_refresh_value_label()
			_refresh_chrome()
			return
	_selected_index = 0 if not _ids.is_empty() else -1
	_refresh_value_label()
	_refresh_chrome()


func _build_popup() -> void:
	_popup = PopupPanel.new()
	_popup.transparent = true
	_popup.transparent_bg = true
	_popup.unresizable = true
	_popup.borderless = true
	_popup.hide()
	_popup.popup_hide.connect(_on_popup_hide)
	_popup.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE_RAISED, WeTokens.BORDER_STRONG, WeTokens.RADIUS_MD, 6, 16.0)
	)
	add_child(_popup)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_popup.add_child(scroll)

	_popup_list = VBoxContainer.new()
	_popup_list.add_theme_constant_override("separation", 2)
	_popup_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_popup_list)


func _on_chrome_gui_input(event: InputEvent) -> void:
	if not editable or _ids.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _popup.visible:
				_close_popup()
			else:
				_open_popup()
			accept_event()


func _open_popup() -> void:
	_rebuild_popup_items()
	var chrome_rect := _chrome.get_global_rect()
	var row_h := ITEM_HEIGHT_COMPACT if compact else ITEM_HEIGHT
	var content_h := mini(_ids.size() * (row_h + 2) + 12, POPUP_MAX_HEIGHT)
	_popup.size = Vector2i(int(maxi(chrome_rect.size.x, 160.0)), int(content_h))
	_popup.position = Vector2i(
		int(chrome_rect.position.x),
		int(chrome_rect.position.y + chrome_rect.size.y + 4.0)
	)
	_popup.popup()
	_chevron.text = "▴"
	_refresh_chrome()


func _close_popup() -> void:
	if _popup != null and _popup.visible:
		_popup.hide()


func _on_popup_hide() -> void:
	_chevron.text = "▾"
	_refresh_chrome()


func _rebuild_popup_items() -> void:
	for child in _popup_list.get_children():
		_popup_list.remove_child(child)
		child.queue_free()

	for i in _ids.size():
		_popup_list.add_child(_make_option_row(i))


func _make_option_row(index: int) -> PanelContainer:
	var selected := index == _selected_index
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ITEM_HEIGHT_COMPACT if compact else ITEM_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _option_style(selected, false))

	var inner := HBoxContainer.new()
	inner.add_theme_constant_override("separation", 10)
	row.add_child(inner)

	var accent := ColorRect.new()
	accent.custom_minimum_size = Vector2(3, 0)
	accent.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var accent_idle: Color = WeTokens.ACCENT if selected else Color(0, 0, 0, 0)
	accent.color = accent_idle
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(accent)

	var text := Label.new()
	text.text = _labels[index]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var text_idle: Color = WeTokens.TEXT if selected else WeTokens.TEXT_MUTED
	text.add_theme_color_override("font_color", text_idle)
	text.add_theme_font_size_override("font_size", 12 if compact else 14)
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(text)

	row.mouse_entered.connect(func():
		if not is_instance_valid(row):
			return
		row.add_theme_stylebox_override("panel", _option_style(selected, true))
		text.add_theme_color_override("font_color", WeTokens.TEXT)
		if not selected:
			accent.color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.45)
	)
	row.mouse_exited.connect(func():
		if not is_instance_valid(row):
			return
		row.add_theme_stylebox_override("panel", _option_style(selected, false))
		text.add_theme_color_override("font_color", text_idle)
		accent.color = accent_idle
	)
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				row.accept_event()
				_choose_index(index)
	)
	return row


func _option_style(selected: bool, hovered: bool) -> StyleBoxFlat:
	var bg := Color(0, 0, 0, 0)
	if selected:
		bg = WeTokens.ACCENT_SOFT
	elif hovered:
		bg = Color(1, 1, 1, 0.06)
	var box := WeTokens.fill(bg, 8, 10, 6)
	return box


func _choose_index(index: int) -> void:
	if index < 0 or index >= _ids.size():
		return
	var changed := index != _selected_index
	_selected_index = index
	_refresh_value_label()
	_close_popup()
	_refresh_chrome()
	if changed:
		# Defer so listeners can rebuild UI without freeing this row mid-signal.
		call_deferred("_emit_item_selected", index)
	else:
		call_deferred("_emit_item_reselected", index)


func _emit_item_selected(index: int) -> void:
	item_selected.emit(index)


func _emit_item_reselected(index: int) -> void:
	item_reselected.emit(index)


func _refresh_value_label() -> void:
	if _value_label == null:
		return
	if _selected_index >= 0 and _selected_index < _labels.size():
		_value_label.text = _labels[_selected_index]
		_value_label.add_theme_color_override("font_color", WeTokens.TEXT)
	else:
		_value_label.text = PLACEHOLDER
		_value_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)


func _refresh_chrome() -> void:
	if _chrome == null:
		return
	var open := _popup != null and _popup.visible
	var bg := WeTokens.INSET
	var border := WeTokens.BORDER
	if not editable:
		bg = Color(0, 0, 0, 0.18)
		border = Color(1, 1, 1, 0.04)
		_chrome.mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		_chrome.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		if open or _hovered:
			border = WeTokens.BORDER_FOCUS if open else WeTokens.BORDER_STRONG
	_chrome.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(bg, border, WeTokens.RADIUS_SM, 8 if compact else 10)
	)
	_chevron.add_theme_color_override(
		"font_color",
		WeTokens.ACCENT if open else (WeTokens.TEXT_MUTED if editable else WeTokens.TEXT_DIM)
	)
