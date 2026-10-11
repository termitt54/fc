extends Control


const MAIN_MENU_PATH := "res://scenes/main_menu/main_menu.tscn"
const GAME_PATH := "res://scenes/game/game_screen.tscn"
const WeMessageScene := preload("res://ui/components/we_message_dialog.tscn")
const SaveStoreScript := preload("res://game/save_store.gd")

@onready var _back: WeButton = %Back
@onready var _status: Label = %Status
@onready var _empty: Label = %Empty
@onready var _scroll: ScrollContainer = %Scroll
@onready var _list: VBoxContainer = %List

var _dialog: WeMessageDialog
var _pending_delete: String = ""
var _busy: bool = false


func _ready() -> void:
	_back.kind = WeButton.Kind.GHOST
	_back.pressed.connect(_on_back_pressed)
	_dialog = WeMessageScene.instantiate() as WeMessageDialog
	add_child(_dialog)
	_dialog.confirmed.connect(_on_delete_confirmed)
	_refresh()
	_back.grab_focus()


func _refresh() -> void:
	for child in _list.get_children():
		child.queue_free()

	var listed: Dictionary = GameSession.list_saves()
	if not listed["success"]:
		_empty.visible = true
		_empty.text = str(listed.get("error", "Не удалось прочитать сохранения."))
		_scroll.visible = false
		return

	var items: Array = listed.get("data", [])
	_empty.visible = items.is_empty()
	_empty.text = "Пока нет сохранений. Начните игру и сохраните её из меню хаба."
	_scroll.visible = not items.is_empty()
	for row in items:
		if typeof(row) == TYPE_DICTIONARY:
			_list.add_child(_make_card(row))


func _make_card(row: Dictionary) -> PanelContainer:
	var slot := str(row.get("slot", ""))
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 16, 8.0)
	)

	var row_box := HBoxContainer.new()
	row_box.add_theme_constant_override("separation", 16)
	card.add_child(row_box)

	var text_col := VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_col.add_theme_constant_override("separation", 4)
	row_box.add_child(text_col)

	var title := Label.new()
	title.text = SaveStoreScript.display_name(slot)
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 16)
	text_col.add_child(title)

	var season := Label.new()
	season.text = _season_line(row)
	season.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	season.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	season.add_theme_font_size_override("font_size", 13)
	text_col.add_child(season)

	var meta := _meta_line(row)
	if not meta.is_empty():
		var meta_label := Label.new()
		meta_label.text = meta
		meta_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		meta_label.add_theme_font_size_override("font_size", 12)
		text_col.add_child(meta_label)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row_box.add_child(actions)

	var load_button := WeButton.new()
	load_button.text = "Загрузить"
	load_button.kind = WeButton.Kind.PRIMARY
	load_button.custom_minimum_size = Vector2(132, 36)
	load_button.pressed.connect(_on_load_pressed.bind(slot))
	actions.add_child(load_button)

	var delete_button := WeButton.new()
	delete_button.text = "Удалить"
	delete_button.kind = WeButton.Kind.DANGER
	delete_button.custom_minimum_size = Vector2(132, 36)
	delete_button.pressed.connect(_on_delete_pressed.bind(slot))
	actions.add_child(delete_button)
	return card


func _season_line(row: Dictionary) -> String:
	if bool(row.get("legacy", false)):
		return "Старый файл. При загрузке переносится в базу."
	var day := int(row.get("season_day", 0))
	var text := "Сезон %d · день %d" % [int(row.get("season_number", 1)), day]
	if day < 1:
		text += " · рынок"
	if bool(row.get("season_finished", false)):
		text += " · сезон завершён"
	return text


func _meta_line(row: Dictionary) -> String:
	var when := _format_saved_at(str(row.get("saved_at", "")))
	if bool(row.get("legacy", false)):
		return when
	var players := _ru_count(int(row.get("player_count", 0)), "игрок", "игрока", "игроков")
	var units := _ru_count(int(row.get("unit_count", 0)), "турнир", "турнира", "турниров")
	if when.is_empty():
		return "%s · %s" % [players, units]
	return "%s · %s · %s" % [when, players, units]


func _format_saved_at(raw: String) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	var date := text
	var clock := ""
	var split_at := "T" if text.contains("T") else " "
	if text.contains("T") or text.contains(" "):
		var parts := text.split(split_at)
		date = parts[0]
		clock = parts[1] if parts.size() > 1 else ""
	var bits := date.split("-")
	if bits.size() == 3:
		date = "%s.%s.%s" % [bits[2], bits[1], bits[0]]
	if clock.length() >= 5:
		clock = clock.substr(0, 5)
	if clock.is_empty():
		return date
	return "%s %s" % [date, clock]


func _ru_count(count: int, one: String, few: String, many: String) -> String:
	var n10 := count % 10
	var n100 := count % 100
	if n10 == 1 and n100 != 11:
		return "%d %s" % [count, one]
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return "%d %s" % [count, few]
	return "%d %s" % [count, many]


func _on_load_pressed(slot: String) -> void:
	if _busy:
		return
	_busy = true
	_status.visible = true
	_status.text = "Загрузка сохранения..."
	await get_tree().process_frame
	var result: Dictionary = GameSession.load_game(slot)
	if not result["success"]:
		_busy = false
		_status.visible = false
		_dialog.open_info("Загрузка", str(result.get("error", "Не удалось загрузить.")))
		return
	get_tree().change_scene_to_file(GAME_PATH)


func _on_delete_pressed(slot: String) -> void:
	if _busy:
		return
	_pending_delete = slot
	_dialog.open_confirm(
		"Удалить сохранение",
		"Удалить «%s»? Сезон из этого слота пропадёт." % SaveStoreScript.display_name(slot),
		"Удалить"
	)


func _on_delete_confirmed() -> void:
	var slot := _pending_delete
	_pending_delete = ""
	_dialog.close()
	if slot.is_empty():
		return
	var result: Dictionary = GameSession.delete_save(slot)
	if not result["success"]:
		_dialog.open_info("Удаление", str(result.get("error", "Не удалось удалить.")))
		return
	_refresh()


func _on_back_pressed() -> void:
	if _busy:
		return
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if _busy:
		return
	if _dialog != null and _dialog.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
