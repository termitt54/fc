extends WeModal

const TEXT_FIELD := preload("res://ui/components/we_text_field.tscn")
const RANGE_FIELD := preload("res://ui/components/we_range_field.tscn")
const FILE_FIELD := preload("res://ui/components/we_file_field.tscn")

const ABBREVIATION_MAX_LENGTH := 8
const FACILITY_DEFAULT := 10
const REPUTATION_DEFAULT := 500

signal submitted(data: Dictionary)

enum FormMode { CREATE, EDIT }

var _mode: FormMode = FormMode.CREATE
var _edit_id: int = -1
var _country_id: int = -1
var _busy: bool = false
var _updating_abbr: bool = false

var _name_field: WeTextField
var _abbr_field: WeTextField
var _logo_field: WeFileField
var _reputation_field: WeRangeField
var _training_field: WeRangeField
var _youth_academy_field: WeRangeField
var _scouting_field: WeRangeField
var _youth_search_field: WeRangeField


func _ready() -> void:
	super._ready()
	close_on_dim = false
	card_width = 720.0
	_card.custom_minimum_size = Vector2(card_width, 0)
	_build_fields()
	confirmed.connect(_on_save_pressed)
	cancelled.connect(_on_cancel_pressed)


func _build_fields() -> void:
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	get_body().add_child(top_row)

	_name_field = TEXT_FIELD.instantiate()
	_name_field.label = "Название"
	_name_field.max_length = 100
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_name_field.size_flags_stretch_ratio = 1.4
	top_row.add_child(_name_field)

	_abbr_field = TEXT_FIELD.instantiate()
	_abbr_field.label = "Аббревиатура"
	_abbr_field.max_length = ABBREVIATION_MAX_LENGTH
	_abbr_field.placeholder = "SPB"
	_abbr_field.custom_minimum_size = Vector2(130, 0)
	_abbr_field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_abbr_field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_abbr_field.text_changed.connect(_on_abbr_changed)
	top_row.add_child(_abbr_field)

	_logo_field = FILE_FIELD.instantiate()
	_logo_field.label = "Логотип"
	_logo_field.compact = true
	_logo_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_logo_field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_logo_field.size_flags_stretch_ratio = 1.0
	top_row.add_child(_logo_field)

	_reputation_field = RANGE_FIELD.instantiate()
	_reputation_field.label = "Репутация (0-1000)"
	_reputation_field.min_value = 0
	_reputation_field.max_value = 1000
	_reputation_field.step = 1
	_reputation_field.value = REPUTATION_DEFAULT
	_reputation_field.tooltip_text = "Влияет на привлекательность клуба для талантливой молодёжи."
	get_body().add_child(_reputation_field)

	var facilities := GridContainer.new()
	facilities.columns = 2
	facilities.add_theme_constant_override("h_separation", 16)
	facilities.add_theme_constant_override("v_separation", 12)
	facilities.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	get_body().add_child(facilities)

	_training_field = _make_facility_field("Тренировочная база (0-20)", facilities)
	_training_field.tooltip_text = "Влияет на дальнейшее развитие футболистов клуба."
	_youth_academy_field = _make_facility_field("Молодёжная академия (0-20)", facilities)
	_youth_academy_field.tooltip_text = "Влияет на уровень подготовки воспитанников к моменту их появления в составе."
	_scouting_field = _make_facility_field("Система скаутинга (0-20)", facilities)
	_scouting_field.tooltip_text = "Влияет на поиск и оценку существующих футболистов."
	_youth_search_field = _make_facility_field("Поиск молодых игроков (0-20)", facilities)
	_youth_search_field.tooltip_text = "Влияет на способность клуба находить и привлекать лучших молодых футболистов."


func _make_facility_field(label_text: String, parent: Control) -> WeRangeField:
	var field: WeRangeField = RANGE_FIELD.instantiate()
	field.label = label_text
	field.min_value = 0
	field.max_value = 20
	field.step = 1
	field.value = FACILITY_DEFAULT
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(field)
	return field


func is_edit_mode() -> bool:
	return _mode == FormMode.EDIT


func get_edit_id() -> int:
	return _edit_id


func open_create(country_id: int) -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_country_id = country_id
	set_title("Новый клуб")
	set_confirm_text("Создать")
	_fill_defaults()
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func open_edit(club: Dictionary) -> void:
	_mode = FormMode.EDIT
	_edit_id = int(club.get("id", -1))
	_country_id = int(club.get("country_id", -1))
	set_title("Редактирование клуба")
	set_confirm_text("Сохранить")
	_name_field.text = str(club.get("name", ""))
	_updating_abbr = true
	_abbr_field.text = str(club.get("short_name", ""))
	_updating_abbr = false
	_logo_field.set_existing_path(str(club.get("logo_path", "")))
	_reputation_field.value = int(club.get("reputation", REPUTATION_DEFAULT))
	_training_field.value = int(club.get("training_level", FACILITY_DEFAULT))
	_youth_academy_field.value = int(club.get("youth_academy", FACILITY_DEFAULT))
	_scouting_field.value = int(club.get("scouting_level", FACILITY_DEFAULT))
	_youth_search_field.value = int(club.get("youth_search", FACILITY_DEFAULT))
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)
	_name_field.editable = not busy
	_abbr_field.editable = not busy
	_reputation_field.editable = not busy
	_training_field.editable = not busy
	_youth_academy_field.editable = not busy
	_scouting_field.editable = not busy
	_youth_search_field.editable = not busy
	_logo_field.set_disabled(busy)


func reset() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_country_id = -1
	_fill_defaults()
	clear_error()
	set_busy(false)
	close()


func _fill_defaults() -> void:
	_name_field.text = ""
	_updating_abbr = true
	_abbr_field.text = ""
	_updating_abbr = false
	_logo_field.clear_selection()
	_reputation_field.value = REPUTATION_DEFAULT
	_training_field.value = FACILITY_DEFAULT
	_youth_academy_field.value = FACILITY_DEFAULT
	_scouting_field.value = FACILITY_DEFAULT
	_youth_search_field.value = FACILITY_DEFAULT


func _on_abbr_changed(new_text: String) -> void:
	if _updating_abbr or _busy:
		return
	var caret: int = _abbr_field.caret_column
	var normalized: String = ClubRepository.normalize_abbreviation(new_text)
	if normalized == new_text:
		return
	_updating_abbr = true
	_abbr_field.text = normalized
	_abbr_field.caret_column = mini(caret, normalized.length())
	_updating_abbr = false


func _on_save_pressed() -> void:
	if _busy:
		return
	var name_text: String = _name_field.text.strip_edges()
	if name_text.is_empty():
		show_error("Введите название клуба.")
		_name_field.focus_field()
		return

	var abbreviation: String = ClubRepository.normalize_abbreviation(_abbr_field.text)
	if abbreviation.is_empty():
		show_error("Введите аббревиатуру.")
		_abbr_field.focus_field()
		return
	if abbreviation.length() < 2:
		show_error("Аббревиатура слишком короткая.")
		_abbr_field.focus_field()
		return
	if _country_id < 1:
		show_error("Не выбрана страна.")
		return

	clear_error()
	submitted.emit({
		"country_id": _country_id,
		"name": name_text,
		"short_name": abbreviation,
		"reputation": _reputation_field.value,
		"training_level": _training_field.value,
		"youth_academy": _youth_academy_field.value,
		"scouting_level": _scouting_field.value,
		"youth_search": _youth_search_field.value,
		"logo_source_path": _logo_field.selected_path,
		"clear_logo": _logo_field.was_cleared(),
	})


func _on_cancel_pressed() -> void:
	if _busy:
		return
	reset()
