extends MarginContainer
## Per-country first/last name pools editor.


var _country_repo := CountryRepository.new()
var _name_repo := CountryNameRepository.new()

var _countries: Array = []
var _counts: Dictionary = {}
var _selected_country_id: int = -1
var _dirty: bool = false
var _busy: bool = false
var _loading_editor: bool = false

@onready var _country_col: WeEditorColumn = %CountryCol
@onready var _editor_panel: PanelContainer = %EditorPanel
@onready var _title_label: Label = %TitleLabel
@onready var _hint_label: Label = %HintLabel
@onready var _status_label: Label = %StatusLabel
@onready var _save_button: WeButton = %SaveButton
@onready var _first_chrome: PanelContainer = %FirstChrome
@onready var _last_chrome: PanelContainer = %LastChrome
@onready var _first_edit: TextEdit = %FirstNamesEdit
@onready var _last_edit: TextEdit = %LastNamesEdit


func _ready() -> void:
	_country_col.set_crud_visible(false)
	_country_col.set_empty_hint("Нет стран")
	_editor_panel.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_LG, 0, 14.0)
	)
	_title_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_hint_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_status_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	_style_names_editor(_first_chrome, _first_edit)
	_style_names_editor(_last_chrome, _last_edit)
	_style_field_labels()

	_save_button.kind = WeButton.Kind.PRIMARY
	_save_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_on_save_pressed)
	_country_col.item_selected.connect(_on_country_selected)
	_country_col.search_changed.connect(func(_t): _render_countries())
	_first_edit.text_changed.connect(_on_editor_changed)
	_last_edit.text_changed.connect(_on_editor_changed)

	_set_editor_enabled(false)
	_refresh_status("")
	if visible:
		reload()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		reload()


func reload() -> void:
	if not WorldDatabase.is_ready():
		_countries = []
		_counts = {}
		_render_countries()
		_clear_editor("База мира недоступна.")
		return

	var result: Dictionary = _country_repo.get_all()
	if not result["success"]:
		_countries = []
		_counts = {}
		_render_countries()
		_clear_editor(str(result.get("error", "Не удалось загрузить страны.")))
		return

	_countries = result["data"]
	_counts = _name_repo.get_counts_by_country()
	_render_countries()
	if _selected_country_id > 0 and _country_col.has_id(_selected_country_id):
		_country_col.select_id(_selected_country_id)
		_load_selected_country()
	elif not _countries.is_empty():
		var sorted_ids := _sorted_country_ids()
		var first_id := int(sorted_ids[0]) if not sorted_ids.is_empty() else 0
		_selected_country_id = first_id
		_country_col.select_id(first_id)
		_load_selected_country()
	else:
		_selected_country_id = -1
		_clear_editor("Создайте страну во вкладке «География».")


func _sorted_country_ids() -> Array:
	var sorted: Array = _countries.duplicate()
	sorted.sort_custom(_compare_countries_by_name_count)
	var ids: Array = []
	for item in sorted:
		ids.append(int(item.get("id", 0)))
	return ids


func _style_field_labels() -> void:
	for path in [
		"Columns/EditorPanel/EditorPad/EditorVBox/NamesRow/FirstCol/FirstLabel",
		"Columns/EditorPanel/EditorPad/EditorVBox/NamesRow/LastCol/LastLabel",
	]:
		var label := get_node_or_null(path) as Label
		if label != null:
			label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)


func _style_names_editor(chrome: PanelContainer, edit: TextEdit) -> void:
	chrome.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, 8)
	)
	edit.add_theme_color_override("font_color", WeTokens.TEXT)
	edit.add_theme_color_override("caret_color", WeTokens.ACCENT)
	edit.add_theme_font_size_override("font_size", 13)
	var empty := StyleBoxEmpty.new()
	edit.add_theme_stylebox_override("normal", empty)
	edit.add_theme_stylebox_override("focus", empty)
	edit.add_theme_stylebox_override("read_only", empty)


func _render_countries() -> void:
	var query: String = _country_col.get_search_text().strip_edges().to_lower()
	var filtered: Array = []
	for item in _countries:
		if _matches_query(item, query):
			filtered.append(item)
	filtered.sort_custom(_compare_countries_by_name_count)
	var items: Array = []
	for item in filtered:
		items.append(_to_country_item(item))
	_country_col.set_items(items)
	if _selected_country_id > 0:
		_country_col.select_id(_selected_country_id)


func _compare_countries_by_name_count(a: Dictionary, b: Dictionary) -> bool:
	var total_a := _name_total_for(int(a.get("id", 0)))
	var total_b := _name_total_for(int(b.get("id", 0)))
	if total_a != total_b:
		return total_a < total_b
	return str(a.get("name", "")).to_lower() < str(b.get("name", "")).to_lower()


func _name_total_for(country_id: int) -> int:
	var counts: Dictionary = _counts.get(country_id, {"first": 0, "last": 0})
	return int(counts.get("first", 0)) + int(counts.get("last", 0))


func _to_country_item(item: Dictionary) -> Dictionary:
	var country_id := int(item.get("id", -1))
	var counts: Dictionary = _counts.get(country_id, {"first": 0, "last": 0})
	var first_n := int(counts.get("first", 0))
	var last_n := int(counts.get("last", 0))
	return {
		"id": country_id,
		"title": str(item.get("name", "")),
		"subtitle": "",
		"meta": "имён: %d · фамилий: %d" % [first_n, last_n],
		"icon_path": str(item.get("flag_path", "")),
		"show_icon": true,
		"active": true,
	}


func _matches_query(item: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var hay := "%s %s" % [str(item.get("name", "")), str(item.get("abbreviation", ""))]
	return hay.to_lower().contains(query)


func _on_country_selected(country_id: int) -> void:
	if country_id == _selected_country_id:
		return
	if _dirty and not _busy:
		_save_current(false)
	_selected_country_id = country_id
	_load_selected_country()


func _load_selected_country() -> void:
	var country := _find_country(_selected_country_id)
	if country.is_empty():
		_clear_editor("Выберите страну")
		return

	_loading_editor = true
	_title_label.text = "%s (%s)" % [
		str(country.get("name", "")),
		str(country.get("abbreviation", "")),
	]
	var pools: Dictionary = _name_repo.get_pools(_selected_country_id)
	_first_edit.text = "\n".join(pools.get("first", PackedStringArray()))
	_last_edit.text = "\n".join(pools.get("last", PackedStringArray()))
	_loading_editor = false
	_dirty = false
	_set_editor_enabled(true)
	_refresh_status(_counts_text_for(_selected_country_id))


func _clear_editor(message: String) -> void:
	_loading_editor = true
	_title_label.text = message
	_first_edit.text = ""
	_last_edit.text = ""
	_loading_editor = false
	_dirty = false
	_set_editor_enabled(false)
	_refresh_status("")


func _set_editor_enabled(enabled: bool) -> void:
	_first_edit.editable = enabled and not _busy
	_last_edit.editable = enabled and not _busy
	_save_button.disabled = not enabled or _busy or not _dirty


func _on_editor_changed() -> void:
	if _loading_editor or _busy:
		return
	_dirty = true
	_save_button.disabled = false
	_refresh_status("Есть несохранённые изменения")


func _on_save_pressed() -> void:
	_save_current(true)


func _save_current(show_ok: bool) -> void:
	if _selected_country_id < 1 or _busy:
		return
	_busy = true
	_set_editor_enabled(false)
	var result: Dictionary = _name_repo.replace_for_country(
		_selected_country_id,
		_parse_name_lines(_first_edit.text),
		_parse_name_lines(_last_edit.text)
	)
	_busy = false
	if not result["success"]:
		_refresh_status(str(result.get("error", "Не удалось сохранить.")))
		_status_label.add_theme_color_override("font_color", WeTokens.DANGER)
		_set_editor_enabled(true)
		_save_button.disabled = false
		return

	_dirty = false
	_counts = _name_repo.get_counts_by_country()
	_render_countries()
	_country_col.select_id(_selected_country_id)
	_set_editor_enabled(true)
	_status_label.add_theme_color_override("font_color", WeTokens.SUCCESS if show_ok else WeTokens.TEXT_MUTED)
	_refresh_status(
		"Сохранено · %s" % _counts_text_for(_selected_country_id)
		if show_ok
		else _counts_text_for(_selected_country_id)
	)


func _counts_text_for(country_id: int) -> String:
	var counts: Dictionary = _counts.get(country_id, {"first": 0, "last": 0})
	return "имён: %d · фамилий: %d" % [
		int(counts.get("first", 0)),
		int(counts.get("last", 0)),
	]


func _refresh_status(text: String) -> void:
	_status_label.text = text
	if text.begins_with("Есть") or text.begins_with("Не ") or text.begins_with("База"):
		_status_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	elif text.begins_with("Сохранено"):
		_status_label.add_theme_color_override("font_color", WeTokens.SUCCESS)
	else:
		_status_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)


func _parse_name_lines(text: String) -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for line in text.split("\n"):
		var name := str(line).strip_edges()
		if name.is_empty():
			continue
		var key := name.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(name)
	return out


func _find_country(country_id: int) -> Dictionary:
	for item in _countries:
		if int(item.get("id", 0)) == country_id:
			return item
	return {}
