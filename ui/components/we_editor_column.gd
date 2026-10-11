class_name WeEditorColumn
extends PanelContainer
## Self-contained geography editor column: title, actions, search, entity list.


signal create_pressed
signal edit_pressed
signal delete_pressed
signal item_selected(entity_id: int)
signal search_changed(query: String)

@export var title: String = "Колонка":
	set(value):
		title = value
		if _title_label != null:
			_title_label.text = title

@onready var _title_label: Label = %Title
@onready var _badge: WeBadge = %Badge
@onready var _create_button: WeButton = %CreateButton
@onready var _search: WeSearchField = %SearchField
@onready var _list: WeEntityList = %EntityList
@onready var _edit_button: WeButton = %EditButton
@onready var _delete_button: WeButton = %DeleteButton


func _ready() -> void:
	add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_LG, 16, 14.0)
	)
	_title_label.text = title
	_title_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_title_label.add_theme_font_size_override("font_size", 16)

	_create_button.kind = WeButton.Kind.PRIMARY
	_edit_button.kind = WeButton.Kind.GHOST
	_delete_button.kind = WeButton.Kind.DANGER
	for button in [_create_button, _edit_button, _delete_button]:
		button.focus_mode = Control.FOCUS_NONE
	_edit_button.custom_minimum_size = Vector2(0, 32)
	_delete_button.custom_minimum_size = Vector2(0, 32)

	_create_button.pressed.connect(func(): create_pressed.emit())
	_edit_button.pressed.connect(func(): edit_pressed.emit())
	_delete_button.pressed.connect(func(): delete_pressed.emit())
	_search.text_changed.connect(func(t: String): search_changed.emit(t))
	_list.item_selected.connect(func(id: int): item_selected.emit(id))


func set_count(value: int) -> void:
	_badge.set_count(value)


func set_items(items: Array) -> void:
	_list.set_items(items)
	set_count(items.size())


func set_empty_hint(text: String) -> void:
	_list.set_empty_hint(text)


func select_id(entity_id: int) -> void:
	_list.select_id(entity_id)


func get_selected_id() -> int:
	return _list.get_selected_id()


func has_id(entity_id: int) -> bool:
	return _list.has_id(entity_id)


func get_search_text() -> String:
	return _search.text


func set_create_enabled(enabled: bool) -> void:
	_create_button.disabled = not enabled


func set_create_visible(show: bool) -> void:
	_create_button.visible = show


func set_edit_enabled(enabled: bool) -> void:
	_edit_button.disabled = not enabled


func set_delete_enabled(enabled: bool) -> void:
	_delete_button.disabled = not enabled


func set_search_enabled(enabled: bool) -> void:
	_search.editable = enabled


func set_crud_visible(visible: bool) -> void:
	_create_button.visible = visible
	_edit_button.visible = visible
	_delete_button.visible = visible
	var actions := _edit_button.get_parent()
	if actions is CanvasItem:
		actions.visible = visible
