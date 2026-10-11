extends WeModal

const TEXT_FIELD := preload("res://ui/components/we_text_field.tscn")
const RANGE_FIELD := preload("res://ui/components/we_range_field.tscn")
const FILE_FIELD := preload("res://ui/components/we_file_field.tscn")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

signal submitted(data: Dictionary)

enum FormMode { CREATE, EDIT }

var _mode: FormMode = FormMode.CREATE
var _edit_id: int = -1
var _continent_id: int = -1
var _busy: bool = false
var _updating_abbr: bool = false

var _name_field: WeTextField
var _abbr_field: WeTextField
var _flag_field: WeFileField
var _reputation_field: WeRangeField
var _youth_talent_field: WeRangeField


func _ready() -> void:
	super._ready()
	close_on_dim = false
	card_width = 640.0
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
	_abbr_field.max_length = 8
	_abbr_field.placeholder = "RUS"
	_abbr_field.custom_minimum_size = Vector2(130, 0)
	_abbr_field.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_abbr_field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_abbr_field.text_changed.connect(_on_abbr_changed)
	top_row.add_child(_abbr_field)

	_flag_field = FILE_FIELD.instantiate()
	_flag_field.label = "Флаг"
	_flag_field.compact = true
	_flag_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flag_field.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_flag_field.size_flags_stretch_ratio = 1.0
	top_row.add_child(_flag_field)

	_reputation_field = RANGE_FIELD.instantiate()
	_reputation_field.label = "Репутация (0–1000)"
	_reputation_field.min_value = 0
	_reputation_field.max_value = 1000
	_reputation_field.step = 1
	_reputation_field.value = 500
	_reputation_field.tooltip_text = "Престиж и сила страны. Не влияет на талант молодёжи."
	get_body().add_child(_reputation_field)

	_youth_talent_field = RANGE_FIELD.instantiate()
	_youth_talent_field.label = "Талант молодёжи (0–100)"
	_youth_talent_field.min_value = YouthGenerationConfigScript.YOUTH_TALENT_MIN
	_youth_talent_field.max_value = YouthGenerationConfigScript.YOUTH_TALENT_MAX
	_youth_talent_field.step = 1
	_youth_talent_field.value = YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT
	_youth_talent_field.tooltip_text = "Шкала 0–100. У каждого числа свои проценты на группы потенциала 40–49, 50–59, 60–69, 70–79, 80–89 и 90–100. Игрок рождается сразу в клубе."
	_youth_talent_field.grades = YouthGenerationConfigScript.YOUTH_TALENT_GRADES
	get_body().add_child(_youth_talent_field)


func is_edit_mode() -> bool:
	return _mode == FormMode.EDIT


func get_edit_id() -> int:
	return _edit_id


func open_create(continent_id: int) -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_continent_id = continent_id
	set_title("Новая страна")
	set_confirm_text("Создать")
	_fill_defaults()
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func open_edit(country: Dictionary) -> void:
	_mode = FormMode.EDIT
	_edit_id = int(country.get("id", -1))
	_continent_id = int(country.get("continent_id", -1))
	set_title("Редактирование страны")
	set_confirm_text("Сохранить")
	_name_field.text = str(country.get("name", ""))
	_updating_abbr = true
	_abbr_field.text = str(country.get("abbreviation", ""))
	_updating_abbr = false
	_flag_field.set_existing_path(str(country.get("flag_path", "")))
	_reputation_field.value = int(country.get("reputation", 500))
	_youth_talent_field.value = YouthGenerationConfigScript.clamp_youth_talent(
		int(country.get("youth_talent", YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT))
	)
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
	_youth_talent_field.editable = not busy
	_flag_field.set_disabled(busy)


func reset() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_continent_id = -1
	_fill_defaults()
	clear_error()
	set_busy(false)
	close()


func _fill_defaults() -> void:
	_name_field.text = ""
	_updating_abbr = true
	_abbr_field.text = ""
	_updating_abbr = false
	_flag_field.clear_selection()
	_reputation_field.value = 500
	_youth_talent_field.value = YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT


func _on_abbr_changed(new_text: String) -> void:
	if _updating_abbr or _busy:
		return
	var caret: int = _abbr_field.caret_column
	var normalized: String = CountryRepository.normalize_abbreviation(new_text)
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
		show_error("Введите название страны.")
		_name_field.focus_field()
		return

	var abbreviation: String = CountryRepository.normalize_abbreviation(_abbr_field.text)
	if abbreviation.is_empty():
		show_error("Введите аббревиатуру.")
		_abbr_field.focus_field()
		return
	if abbreviation.length() < 2:
		show_error("Аббревиатура слишком короткая.")
		_abbr_field.focus_field()
		return
	if _continent_id < 1:
		show_error("Не выбран континент.")
		return

	clear_error()
	submitted.emit({
		"continent_id": _continent_id,
		"name": name_text,
		"abbreviation": abbreviation,
		"reputation": _reputation_field.value,
		"youth_talent": _youth_talent_field.value,
		"flag_source_path": _flag_field.selected_path,
		"clear_flag": _flag_field.was_cleared(),
	})


func _on_cancel_pressed() -> void:
	if _busy:
		return
	reset()
