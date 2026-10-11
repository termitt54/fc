class_name WeEntityList
extends PanelContainer
## Scrollable custom entity list with single selection.


signal item_selected(entity_id: int)

const ROW_SCENE := preload("res://ui/components/we_entity_row.tscn")

var _selected_id: int = -1
var _rows: Dictionary = {} # id -> WeEntityRow

@onready var _rows_box: VBoxContainer = %Rows
@onready var _hint: Label = %Hint


func _ready() -> void:
	var inset := WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_MD, 8)
	# Inner highlight edge for depth.
	inset.border_color = Color(0.4, 0.65, 0.7, 0.12)
	add_theme_stylebox_override("panel", inset)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.visible = true


func clear() -> void:
	_clear_rows()
	_selected_id = -1
	_hint.visible = true


func set_empty_hint(text: String) -> void:
	_hint.text = text


func set_items(items: Array) -> void:
	var keep_selected: int = _selected_id
	_clear_rows()
	_hint.visible = items.is_empty()

	for item in items:
		var row: WeEntityRow = ROW_SCENE.instantiate()
		_rows_box.add_child(row)
		var id: int = int(item.get("id", -1))
		row.setup(
			id,
			str(item.get("title", "")),
			str(item.get("subtitle", "")),
			str(item.get("meta", "")),
			bool(item.get("active", true)),
			str(item.get("icon_path", "")),
			bool(item.get("show_icon", false)),
			item.get("distribution", []) as Array,
			item.get("stat_chips", []) as Array,
			bool(item.get("large_icon", false))
		)
		row.pressed.connect(_on_row_pressed)
		_rows[id] = row

	if keep_selected > 0 and _rows.has(keep_selected):
		select_id(keep_selected)
	else:
		_selected_id = -1


func select_id(entity_id: int) -> void:
	_selected_id = entity_id
	for id in _rows:
		(_rows[id] as WeEntityRow).set_selected(int(id) == entity_id)


func get_selected_id() -> int:
	return _selected_id


func has_id(entity_id: int) -> bool:
	return _rows.has(entity_id)


func _clear_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.free()
	_rows.clear()


func _on_row_pressed(entity_id: int) -> void:
	select_id(entity_id)
	item_selected.emit(entity_id)
