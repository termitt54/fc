extends MarginContainer

const CONTINENT_FORM := preload("res://scenes/world_editor/dialogs/continent_form_dialog.tscn")
const COUNTRY_FORM := preload("res://scenes/world_editor/dialogs/country_form_dialog.tscn")
const CLUB_FORM := preload("res://scenes/world_editor/dialogs/club_form_dialog.tscn")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

var _continent_repo := ContinentRepository.new()
var _country_repo := CountryRepository.new()
var _club_repo := ClubRepository.new()

var _continents: Array = []
var _countries: Array = []
var _clubs: Array = []

var _selected_continent_id: int = -1
var _selected_country_id: int = -1
var _selected_club_id: int = -1

var _continent_form
var _country_form
var _club_form
var _pending_delete: Dictionary = {}

@onready var _continent_col: WeEditorColumn = %ContinentCol
@onready var _country_col: WeEditorColumn = %CountryCol
@onready var _club_col: WeEditorColumn = %ClubCol
@onready var _confirm_dialog: WeMessageDialog = %ConfirmDialog
@onready var _info_dialog: WeMessageDialog = %InfoDialog


func _ready() -> void:
	_setup_forms()
	_connect_signals()
	_refresh_action_states()
	reload_continents()


func _setup_forms() -> void:
	_continent_form = CONTINENT_FORM.instantiate()
	_country_form = COUNTRY_FORM.instantiate()
	_club_form = CLUB_FORM.instantiate()
	add_child(_continent_form)
	add_child(_country_form)
	add_child(_club_form)


func _connect_signals() -> void:
	_continent_col.item_selected.connect(_on_continent_selected)
	_country_col.item_selected.connect(_on_country_selected)
	_club_col.item_selected.connect(_on_club_selected)

	_continent_col.search_changed.connect(func(_t): _render_continents())
	_country_col.search_changed.connect(func(_t): _render_countries())
	_club_col.search_changed.connect(func(_t): _render_clubs())

	_continent_col.create_pressed.connect(_on_continent_create)
	_country_col.create_pressed.connect(_on_country_create)
	_club_col.create_pressed.connect(_on_club_create)
	_continent_col.edit_pressed.connect(_on_continent_edit)
	_country_col.edit_pressed.connect(_on_country_edit)
	_club_col.edit_pressed.connect(_on_club_edit)
	_continent_col.delete_pressed.connect(_on_continent_delete)
	_country_col.delete_pressed.connect(_on_country_delete)
	_club_col.delete_pressed.connect(_on_club_delete)

	_continent_form.submitted.connect(_on_continent_submitted)
	_country_form.submitted.connect(_on_country_submitted)
	_club_form.submitted.connect(_on_club_submitted)
	_confirm_dialog.confirmed.connect(_on_delete_confirmed)


func _show_info(message: String) -> void:
	_info_dialog.open_info("Сообщение", message)


func reload_continents() -> void:
	if not WorldDatabase.is_ready():
		_show_info("Не удалось открыть базу редактора мира.")
		return

	var result: Dictionary = _continent_repo.get_all()
	if not result["success"]:
		_show_info(str(result.get("error", "Ошибка загрузки континентов.")))
		return

	_continents = result["data"]
	_render_continents()
	_restore_continent_selection()
	if _selected_continent_id > 0:
		reload_countries()
	else:
		_countries = []
		_clubs = []
		_selected_country_id = -1
		_selected_club_id = -1
		_render_countries()
		_render_clubs()
	_refresh_action_states()


func reload_countries() -> void:
	if _selected_continent_id < 1:
		_countries = []
		_render_countries()
		_refresh_action_states()
		return

	var result: Dictionary = _country_repo.get_by_continent(_selected_continent_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Ошибка загрузки стран.")))
		return

	_countries = result["data"]
	_render_countries()
	_restore_country_selection()
	if _selected_country_id > 0:
		reload_clubs()
	else:
		_clubs = []
		_selected_club_id = -1
		_render_clubs()
	_refresh_action_states()


func reload_clubs() -> void:
	if _selected_country_id < 1:
		_clubs = []
		_render_clubs()
		_refresh_action_states()
		return

	var result: Dictionary = _club_repo.get_by_country(_selected_country_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Ошибка загрузки клубов.")))
		return

	_clubs = result["data"]
	_render_clubs()
	_restore_club_selection()
	_refresh_action_states()


func _render_continents() -> void:
	var query: String = _continent_col.get_search_text().strip_edges().to_lower()
	var items: Array = []
	for item in _continents:
		if not _matches_query(item, query):
			continue
		items.append(_to_continent_item(item))
	_continent_col.set_empty_hint("Создайте первый континент")
	_continent_col.set_items(items)
	if _selected_continent_id > 0:
		_continent_col.select_id(_selected_continent_id)


func _render_countries() -> void:
	var query: String = _country_col.get_search_text().strip_edges().to_lower()
	var items: Array = []
	for item in _countries:
		if not _matches_query(item, query):
			continue
		items.append(_to_country_item(item))

	if _selected_continent_id < 1:
		_country_col.set_empty_hint("Выберите континент")
	else:
		_country_col.set_empty_hint("Нет стран — создайте первую")
	_country_col.set_items(items)
	if _selected_country_id > 0:
		_country_col.select_id(_selected_country_id)


func _render_clubs() -> void:
	var query: String = _club_col.get_search_text().strip_edges().to_lower()
	var items: Array = []
	for item in _clubs:
		if not _matches_query(item, query):
			continue
		items.append(_to_club_item(item))

	if _selected_country_id < 1:
		_club_col.set_empty_hint("Выберите страну")
	else:
		_club_col.set_empty_hint("Нет клубов — создайте первый")
	_club_col.set_items(items)
	if _selected_club_id > 0:
		_club_col.select_id(_selected_club_id)


func _to_continent_item(item: Dictionary) -> Dictionary:
	var active: bool = bool(item.get("is_active", true))
	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": str(item.get("code", "")),
		"meta": "стран: %d · клубов: %d%s" % [
			int(item.get("countries_count", 0)),
			int(item.get("clubs_count", 0)),
			"" if active else " · выкл",
		],
		"active": active,
	}


func _to_country_item(item: Dictionary) -> Dictionary:
	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": "",
		"meta": "реп. %d · талант %d · клубов: %d" % [
			int(item.get("reputation", 0)),
			int(item.get("youth_talent", YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT)),
			int(item.get("clubs_count", 0)),
		],
		"icon_path": str(item.get("flag_path", "")),
		"show_icon": true,
		"active": true,
	}


func _to_club_item(item: Dictionary) -> Dictionary:
	var active: bool = bool(item.get("is_active", true))
	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": "",
		"meta": "реп. %d%s" % [
			int(item.get("reputation", 0)),
			"" if active else " · выкл",
		],
		"icon_path": str(item.get("logo_path", "")),
		"show_icon": true,
		"large_icon": true,
		"stat_chips": [
			{
				"value": int(item.get("training_level", 0)),
				"short": "база",
				"tip": "Тренировочная база",
			},
			{
				"value": int(item.get("youth_academy", 0)),
				"short": "акад",
				"tip": "Молодёжная академия",
			},
			{
				"value": int(item.get("scouting_level", 0)),
				"short": "скаут",
				"tip": "Система скаутинга",
			},
			{
				"value": int(item.get("youth_search", 0)),
				"short": "поиск",
				"tip": "Поиск молодых игроков",
			},
		],
		"active": active,
	}


func _matches_query(item: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var name_text: String = str(item.get("name", "")).to_lower()
	var short_name: String = str(item.get("short_name", "")).to_lower()
	var abbreviation: String = str(item.get("abbreviation", "")).to_lower()
	var code: String = str(item.get("code", "")).to_lower()
	return (
		name_text.find(query) >= 0
		or short_name.find(query) >= 0
		or abbreviation.find(query) >= 0
		or code.find(query) >= 0
	)


func _on_continent_selected(entity_id: int) -> void:
	_selected_continent_id = entity_id
	_selected_country_id = -1
	_selected_club_id = -1
	reload_countries()


func _on_country_selected(entity_id: int) -> void:
	_selected_country_id = entity_id
	_selected_club_id = -1
	reload_clubs()


func _on_club_selected(entity_id: int) -> void:
	_selected_club_id = entity_id
	_refresh_action_states()


func _restore_continent_selection() -> void:
	if _selected_continent_id < 1:
		return
	if _continent_col.has_id(_selected_continent_id):
		_continent_col.select_id(_selected_continent_id)
	else:
		_selected_continent_id = -1


func _restore_country_selection() -> void:
	if _selected_country_id < 1:
		return
	if _country_col.has_id(_selected_country_id):
		_country_col.select_id(_selected_country_id)
	else:
		_selected_country_id = -1


func _restore_club_selection() -> void:
	if _selected_club_id < 1:
		return
	if _club_col.has_id(_selected_club_id):
		_club_col.select_id(_selected_club_id)
	else:
		_selected_club_id = -1


func _refresh_action_states() -> void:
	var db_ready: bool = WorldDatabase.is_ready()
	_continent_col.set_create_enabled(db_ready)
	_country_col.set_create_enabled(db_ready and _selected_continent_id > 0)
	_club_col.set_create_enabled(db_ready and _selected_country_id > 0)

	_continent_col.set_edit_enabled(_selected_continent_id > 0)
	_continent_col.set_delete_enabled(_selected_continent_id > 0)
	_country_col.set_edit_enabled(_selected_country_id > 0)
	_country_col.set_delete_enabled(_selected_country_id > 0)
	_club_col.set_edit_enabled(_selected_club_id > 0)
	_club_col.set_delete_enabled(_selected_club_id > 0)

	_country_col.set_search_enabled(_selected_continent_id > 0)
	_club_col.set_search_enabled(_selected_country_id > 0)


func _on_continent_create() -> void:
	_continent_form.open_create()


func _on_country_create() -> void:
	if _selected_continent_id < 1:
		return
	_country_form.open_create(_selected_continent_id)


func _on_club_create() -> void:
	if _selected_country_id < 1:
		return
	_club_form.open_create(_selected_country_id)


func _on_continent_edit() -> void:
	var result: Dictionary = _continent_repo.get_by_id(_selected_continent_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Континент не найден.")))
		return
	_continent_form.open_edit(result["data"])


func _on_country_edit() -> void:
	var result: Dictionary = _country_repo.get_by_id(_selected_country_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Страна не найдена.")))
		return
	_country_form.open_edit(result["data"])


func _on_club_edit() -> void:
	var result: Dictionary = _club_repo.get_by_id(_selected_club_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Клуб не найден.")))
		return
	_club_form.open_edit(result["data"])


func _on_continent_delete() -> void:
	_request_delete("continent", _selected_continent_id)


func _on_country_delete() -> void:
	_request_delete("country", _selected_country_id)


func _on_club_delete() -> void:
	_request_delete("club", _selected_club_id)


func _request_delete(kind: String, entity_id: int) -> void:
	if entity_id < 1:
		return

	var result: Dictionary
	match kind:
		"continent":
			result = _continent_repo.get_by_id(entity_id)
		"country":
			result = _country_repo.get_by_id(entity_id)
		_:
			result = _club_repo.get_by_id(entity_id)

	if not result["success"]:
		_show_info(str(result.get("error", "Запись не найдена.")))
		return

	var data: Dictionary = result["data"]
	if kind == "continent" and int(data.get("countries_count", 0)) > 0:
		_show_info(
			"Невозможно удалить континент «%s».\n\nК нему привязано стран: %d."
			% [str(data.get("name", "")), int(data.get("countries_count", 0))]
		)
		return
	if kind == "country" and int(data.get("clubs_count", 0)) > 0:
		_show_info(
			"Невозможно удалить страну «%s».\n\nК ней привязано клубов: %d."
			% [str(data.get("name", "")), int(data.get("clubs_count", 0))]
		)
		return

	_pending_delete = {"kind": kind, "id": entity_id}
	_confirm_dialog.open_confirm(
		"Подтверждение",
		"Удалить «%s»?\n\nЭто действие нельзя отменить." % str(data.get("name", "")),
		"Удалить"
	)


func _on_delete_confirmed() -> void:
	if _pending_delete.is_empty():
		return
	var kind: String = str(_pending_delete.get("kind", ""))
	var entity_id: int = int(_pending_delete.get("id", -1))
	_pending_delete = {}
	_confirm_dialog.close()

	var result: Dictionary
	match kind:
		"continent":
			result = _continent_repo.delete(entity_id)
			if result["success"]:
				_selected_continent_id = -1
				_selected_country_id = -1
				_selected_club_id = -1
				reload_continents()
		"country":
			result = _country_repo.delete(entity_id)
			if result["success"]:
				_selected_country_id = -1
				_selected_club_id = -1
				reload_countries()
		_:
			result = _club_repo.delete(entity_id)
			if result["success"]:
				_selected_club_id = -1
				reload_clubs()

	if not result["success"]:
		_show_info(str(result.get("error", "Не удалось удалить.")))


func _on_continent_submitted(data: Dictionary) -> void:
	var was_edit: bool = _continent_form.is_edit_mode()
	_continent_form.set_busy(true)
	var result: Dictionary
	if was_edit:
		result = _continent_repo.update(_continent_form.get_edit_id(), data)
	else:
		result = _continent_repo.create(data)
	_continent_form.set_busy(false)
	if not result["success"]:
		_continent_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_continent_form.reset()
	if not was_edit:
		_selected_continent_id = int(result["data"].get("id", -1))
	reload_continents()


func _on_country_submitted(data: Dictionary) -> void:
	var was_edit: bool = _country_form.is_edit_mode()
	_country_form.set_busy(true)
	var result: Dictionary
	if was_edit:
		result = _country_repo.update(_country_form.get_edit_id(), data)
	else:
		result = _country_repo.create(data)
	_country_form.set_busy(false)
	if not result["success"]:
		_country_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_country_form.reset()
	_selected_country_id = int(result["data"].get("id", _selected_country_id))
	reload_continents()


func _on_club_submitted(data: Dictionary) -> void:
	var was_edit: bool = _club_form.is_edit_mode()
	_club_form.set_busy(true)
	var result: Dictionary
	if was_edit:
		result = _club_repo.update(_club_form.get_edit_id(), data)
	else:
		result = _club_repo.create(data)
	_club_form.set_busy(false)
	if not result["success"]:
		_club_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_club_form.reset()
	_selected_club_id = int(result["data"].get("id", _selected_club_id))
	reload_countries()
