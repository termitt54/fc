extends MarginContainer

const COMPETITION_FORM := preload("res://scenes/world_editor/dialogs/competition_form_dialog.tscn")

var _competition_repo := CompetitionRepository.new()
var _country_repo := CountryRepository.new()
var _continent_repo := ContinentRepository.new()

var _competitions: Array = []
var _countries: Array = []
var _continents: Array = []
var _selected_id: int = -1
var _form
var _pending_delete: Dictionary = {}

@onready var _list_col: WeEditorColumn = %CompetitionCol
@onready var _confirm_dialog: WeMessageDialog = %ConfirmDialog
@onready var _info_dialog: WeMessageDialog = %InfoDialog


func _ready() -> void:
	_form = COMPETITION_FORM.instantiate()
	add_child(_form)
	_connect_signals()
	_refresh_action_states()
	reload()


func _connect_signals() -> void:
	_list_col.item_selected.connect(_on_item_selected)
	_list_col.search_changed.connect(func(_t): _render())
	_list_col.create_pressed.connect(_on_create)
	_list_col.edit_pressed.connect(_on_edit)
	_list_col.delete_pressed.connect(_on_delete)
	_form.submitted.connect(_on_submitted)
	_confirm_dialog.confirmed.connect(_on_delete_confirmed)


func _show_info(message: String) -> void:
	_info_dialog.open_info("Сообщение", message)


func reload() -> void:
	if not WorldDatabase.is_ready():
		_show_info("Не удалось открыть базу редактора мира.")
		return

	var countries_result: Dictionary = _country_repo.get_all()
	_countries = countries_result["data"] if countries_result["success"] else []
	_form.set_countries(_countries)

	var continents_result: Dictionary = _continent_repo.get_all()
	_continents = continents_result["data"] if continents_result["success"] else []
	_form.set_continents(_continents)

	var result: Dictionary = _competition_repo.get_all()
	if not result["success"]:
		_show_info(str(result.get("error", "Ошибка загрузки турниров.")))
		return

	_competitions = result["data"]
	_render()
	_restore_selection()
	_refresh_action_states()


func _render() -> void:
	var query: String = _list_col.get_search_text().strip_edges().to_lower()
	var items: Array = []
	for item in _competitions:
		if not _matches_query(item, query):
			continue
		items.append(_to_item(item))

	_list_col.set_empty_hint("Нет турниров — создайте первый")
	_list_col.set_items(items)
	if _selected_id > 0:
		_list_col.select_id(_selected_id)


func _to_item(item: Dictionary) -> Dictionary:
	var active: bool = bool(item.get("is_active", true))
	var scope: String = str(item.get("scope_type", ""))
	var format_label: String = CompetitionTypes.scope_label(scope)

	var context: String = ""
	match scope:
		CompetitionTypes.SCOPE_DOMESTIC:
			context = str(item.get("country_name", ""))
		CompetitionTypes.SCOPE_CONTINENTAL:
			context = str(item.get("continent_name", ""))
		CompetitionTypes.SCOPE_INTERNATIONAL:
			context = CompetitionTypes.age_group_label(str(item.get("age_group", CompetitionTypes.AGE_SENIOR)))
		_:
			context = ""

	var subtitle_parts: PackedStringArray = PackedStringArray()
	subtitle_parts.append(format_label)
	if not context.is_empty():
		subtitle_parts.append(context)

	return {
		"id": int(item.get("id", -1)),
		"title": str(item.get("name", "")),
		"subtitle": " · ".join(subtitle_parts),
		"meta": "с %d · %s%s" % [
			int(item.get("start_season", 0)),
			CompetitionTypes.period_label(str(item.get("periodicity", ""))),
			"" if active else " · выкл",
		],
		"active": active,
	}


func _matches_query(item: Dictionary, query: String) -> bool:
	if query.is_empty():
		return true
	var name_text: String = str(item.get("name", "")).to_lower()
	var code: String = str(item.get("code", "")).to_lower()
	var country_name: String = str(item.get("country_name", "")).to_lower()
	var continent_name: String = str(item.get("continent_name", "")).to_lower()
	var format_label: String = CompetitionTypes.scope_label(str(item.get("scope_type", ""))).to_lower()
	return (
		name_text.find(query) >= 0
		or code.find(query) >= 0
		or country_name.find(query) >= 0
		or continent_name.find(query) >= 0
		or format_label.find(query) >= 0
	)


func _on_item_selected(entity_id: int) -> void:
	_selected_id = entity_id
	_refresh_action_states()


func _restore_selection() -> void:
	if _selected_id < 1:
		return
	if _list_col.has_id(_selected_id):
		_list_col.select_id(_selected_id)
	else:
		_selected_id = -1


func _refresh_action_states() -> void:
	var db_ready: bool = WorldDatabase.is_ready()
	_list_col.set_create_enabled(db_ready)
	_list_col.set_edit_enabled(_selected_id > 0)
	_list_col.set_delete_enabled(_selected_id > 0)
	_list_col.set_search_enabled(db_ready)


func _on_create() -> void:
	_form.set_countries(_countries)
	_form.set_continents(_continents)
	_form.open_create()


func _on_edit() -> void:
	var result: Dictionary = _competition_repo.get_by_id(_selected_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Турнир не найден.")))
		return
	_form.set_countries(_countries)
	_form.set_continents(_continents)
	_form.open_edit(result["data"])


func _on_delete() -> void:
	var result: Dictionary = _competition_repo.get_by_id(_selected_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Турнир не найден.")))
		return
	var data: Dictionary = result["data"]
	_pending_delete = {"id": int(data.get("id", -1))}
	_confirm_dialog.open_confirm(
		"Удалить турнир",
		"Удалить турнир «%s»?\n\nЭто действие нельзя отменить." % str(data.get("name", "")),
		"Удалить"
	)


func _on_delete_confirmed() -> void:
	var competition_id: int = int(_pending_delete.get("id", -1))
	_pending_delete.clear()
	if competition_id < 1:
		return
	var result: Dictionary = _competition_repo.delete(competition_id)
	if not result["success"]:
		_show_info(str(result.get("error", "Не удалось удалить турнир.")))
		return
	if _selected_id == competition_id:
		_selected_id = -1
	reload()


func _on_submitted(data: Dictionary) -> void:
	var was_edit: bool = _form.is_edit_mode()
	_form.set_busy(true)
	var result: Dictionary
	if was_edit:
		result = _competition_repo.update(_form.get_edit_id(), data)
	else:
		result = _competition_repo.create(data)
	_form.set_busy(false)
	if not result["success"]:
		_form.show_error(str(result.get("error", "Не удалось сохранить.")))
		return
	_form.reset()
	_selected_id = int(result["data"].get("id", _selected_id))
	reload()
