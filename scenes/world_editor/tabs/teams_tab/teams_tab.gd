extends MarginContainer
## Flat directory of every country and every club. The columns do not filter each other.


const COUNTRY_FORM := preload("res://scenes/world_editor/dialogs/country_form_dialog.tscn")
const CLUB_FORM := preload("res://scenes/world_editor/dialogs/club_form_dialog.tscn")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

const SORT_REPUTATION := "reputation"

const COUNTRY_SORTS: Array = [
	{"id": SORT_REPUTATION, "label": "Репутация"},
	{"id": "name", "label": "Название"},
	{"id": "abbreviation", "label": "Аббревиатура"},
	{"id": "youth_talent", "label": "Талант молодёжи"},
	{"id": "clubs_count", "label": "Число клубов"},
]

const CLUB_SORTS: Array = [
	{"id": SORT_REPUTATION, "label": "Репутация"},
	{"id": "name", "label": "Название"},
	{"id": "short_name", "label": "Аббревиатура"},
	{"id": "training_level", "label": "Тренировочная база"},
	{"id": "youth_academy", "label": "Академия"},
	{"id": "scouting_level", "label": "Скаутинг"},
	{"id": "youth_search", "label": "Поиск молодёжи"},
]

var _country_repo := CountryRepository.new()
var _club_repo := ClubRepository.new()

var _countries: Array = []
var _clubs: Array = []
var _selected_country_id: int = -1
var _selected_club_id: int = -1
var _pending_delete: Dictionary = {}

var _country_form
var _club_form

@onready var _country_sort: WeSelectField = %CountrySort
@onready var _club_sort: WeSelectField = %ClubSort
@onready var _country_col: WeEditorColumn = %CountryCol
@onready var _club_col: WeEditorColumn = %ClubCol
@onready var _confirm_dialog: WeMessageDialog = %ConfirmDialog
@onready var _info_dialog: WeMessageDialog = %InfoDialog


func _ready() -> void:
	_country_form = COUNTRY_FORM.instantiate()
	_club_form = CLUB_FORM.instantiate()
	add_child(_country_form)
	add_child(_club_form)

	_country_sort.label = "Сортировка"
	_country_sort.compact = true
	_country_sort.set_items(COUNTRY_SORTS, SORT_REPUTATION)
	_club_sort.label = "Сортировка"
	_club_sort.compact = true
	_club_sort.set_items(CLUB_SORTS, SORT_REPUTATION)

	_country_col.set_create_visible(false)
	_club_col.set_create_visible(false)

	_country_sort.item_selected.connect(func(_index: int): _render_countries())
	_club_sort.item_selected.connect(func(_index: int): _render_clubs())
	_country_col.search_changed.connect(func(_text: String): _render_countries())
	_club_col.search_changed.connect(func(_text: String): _render_clubs())
	_country_col.item_selected.connect(_on_country_selected)
	_club_col.item_selected.connect(_on_club_selected)
	_country_col.edit_pressed.connect(_on_country_edit)
	_club_col.edit_pressed.connect(_on_club_edit)
	_country_col.delete_pressed.connect(_on_country_delete)
	_club_col.delete_pressed.connect(_on_club_delete)
	_country_form.submitted.connect(_on_country_submitted)
	_club_form.submitted.connect(_on_club_submitted)
	_confirm_dialog.confirmed.connect(_on_delete_confirmed)
	reload()


func reload() -> void:
	if not WorldDatabase.is_ready():
		_show_info("Не удалось открыть базу редактора мира.")
		return
	var countries: Dictionary = _country_repo.get_all()
	if not countries["success"]:
		_show_info(str(countries.get("error", "Ошибка загрузки стран.")))
		return
	var clubs: Dictionary = _club_repo.get_all()
	if not clubs["success"]:
		_show_info(str(clubs.get("error", "Ошибка загрузки команд.")))
		return
	_countries = countries["data"]
	_clubs = clubs["data"]
	_render_countries()
	_render_clubs()
	_refresh_actions()


func _render_countries() -> void:
	var query := _country_col.get_search_text().strip_edges().to_lower()
	var rows: Array = []
	for item in _countries:
		if _matches(item, query):
			rows.append(item)
	_sort_rows(rows, str(_country_sort.selected_id))
	var items: Array = []
	for item in rows:
		items.append(_to_country_item(item))
	_country_col.set_empty_hint("Нет стран")
	_country_col.set_items(items)
	if _selected_country_id > 0 and _country_col.has_id(_selected_country_id):
		_country_col.select_id(_selected_country_id)
	elif _selected_country_id > 0:
		_selected_country_id = -1
	_refresh_actions()


func _render_clubs() -> void:
	var query := _club_col.get_search_text().strip_edges().to_lower()
	var rows: Array = []
	for item in _clubs:
		if _matches(item, query):
			rows.append(item)
	_sort_rows(rows, str(_club_sort.selected_id))
	var items: Array = []
	for item in rows:
		items.append(_to_club_item(item))
	_club_col.set_empty_hint("Нет команд")
	_club_col.set_items(items)
	if _selected_club_id > 0 and _club_col.has_id(_selected_club_id):
		_club_col.select_id(_selected_club_id)
	elif _selected_club_id > 0:
		_selected_club_id = -1
	_refresh_actions()


func _to_country_item(item: Dictionary) -> Dictionary:
	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": str(item.get("abbreviation", "")),
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
	var active := bool(item.get("is_active", true))
	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": str(item.get("country_name", "")),
		"meta": "реп. %d%s" % [
			int(item.get("reputation", 0)),
			"" if active else " · выкл",
		],
		"icon_path": str(item.get("logo_path", "")),
		"show_icon": true,
		"large_icon": true,
		"stat_chips": [
			{"value": int(item.get("training_level", 0)), "short": "база", "tip": "Тренировочная база"},
			{"value": int(item.get("youth_academy", 0)), "short": "акад", "tip": "Молодёжная академия"},
			{"value": int(item.get("scouting_level", 0)), "short": "скаут", "tip": "Система скаутинга"},
			{"value": int(item.get("youth_search", 0)), "short": "поиск", "tip": "Поиск молодых игроков"},
		],
		"active": active,
	}


func _matches(item: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var fields := [
		str(item.get("name", "")),
		str(item.get("short_name", "")),
		str(item.get("abbreviation", "")),
		str(item.get("country_name", "")),
	]
	var folded := query
	for field in fields:
		if field.to_lower().find(folded) >= 0:
			return true
	return false


func _sort_rows(rows: Array, field: String) -> void:
	var text_field := field == "name" or field == "abbreviation" or field == "short_name" or field == "country_name"
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if text_field:
			var text_cmp := str(a.get(field, "")).nocasecmp_to(str(b.get(field, "")))
			if text_cmp != 0:
				return text_cmp < 0
		else:
			var left := int(a.get(field, 0))
			var right := int(b.get(field, 0))
			if left != right:
				return left > right
		var name_cmp := str(a.get("name", "")).nocasecmp_to(str(b.get("name", "")))
		if name_cmp != 0:
			return name_cmp < 0
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)


func _on_country_selected(entity_id: int) -> void:
	_selected_country_id = entity_id
	_refresh_actions()


func _on_club_selected(entity_id: int) -> void:
	_selected_club_id = entity_id
	_refresh_actions()


func _refresh_actions() -> void:
	_country_col.set_edit_enabled(_selected_country_id > 0)
	_country_col.set_delete_enabled(_selected_country_id > 0)
	_club_col.set_edit_enabled(_selected_club_id > 0)
	_club_col.set_delete_enabled(_selected_club_id > 0)


func _on_country_edit() -> void:
	var result: Dictionary = _country_repo.get_by_id(_selected_country_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Страна не найдена.")))
		return
	_country_form.open_edit(result["data"])


func _on_club_edit() -> void:
	var result: Dictionary = _club_repo.get_by_id(_selected_club_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Команда не найдена.")))
		return
	_club_form.open_edit(result["data"])


func _on_country_delete() -> void:
	_request_delete("country", _selected_country_id)


func _on_club_delete() -> void:
	_request_delete("club", _selected_club_id)


func _request_delete(kind: String, entity_id: int) -> void:
	if entity_id < 1:
		return
	var result: Dictionary = (
		_country_repo.get_by_id(entity_id) if kind == "country" else _club_repo.get_by_id(entity_id)
	)
	if not result["success"]:
		_show_info(str(result.get("error", "Запись не найдена.")))
		return
	var data: Dictionary = result["data"]
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
	var kind := str(_pending_delete.get("kind", ""))
	var entity_id := int(_pending_delete.get("id", -1))
	_pending_delete = {}
	_confirm_dialog.close()
	var result: Dictionary
	if kind == "country":
		result = _country_repo.delete(entity_id)
		if result["success"]:
			_selected_country_id = -1
	else:
		result = _club_repo.delete(entity_id)
		if result["success"]:
			_selected_club_id = -1
	if not result["success"]:
		_show_info(str(result.get("error", "Не удалось удалить.")))
		return
	reload()


func _on_country_submitted(data: Dictionary) -> void:
	_country_form.set_busy(true)
	var result: Dictionary = _country_repo.update(_country_form.get_edit_id(), data)
	_country_form.set_busy(false)
	if not result["success"]:
		_country_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_country_form.reset()
	_selected_country_id = int(result["data"].get("id", _selected_country_id))
	reload()


func _on_club_submitted(data: Dictionary) -> void:
	_club_form.set_busy(true)
	var result: Dictionary = _club_repo.update(_club_form.get_edit_id(), data)
	_club_form.set_busy(false)
	if not result["success"]:
		_club_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_club_form.reset()
	_selected_club_id = int(result["data"].get("id", _selected_club_id))
	reload()


func _show_info(message: String) -> void:
	_info_dialog.open_info("Сообщение", message)
