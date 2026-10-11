extends WeModal

const TEXT_FIELD := preload("res://ui/components/we_text_field.tscn")
const NUMBER_FIELD := preload("res://ui/components/we_number_field.tscn")
const TOGGLE := preload("res://ui/components/we_toggle.tscn")

signal submitted(data: Dictionary)

enum FormMode { CREATE, EDIT }

const NAME_MAX_LENGTH := 100
const SHORT_NAME_MAX_LENGTH := 30

var _mode: FormMode = FormMode.CREATE
var _edit_id: int = -1
var _busy: bool = false
var _updating_code: bool = false

var _name_field: WeTextField
var _short_name_field: WeTextField
var _code_field: WeTextField
var _sort_field: WeNumberField
var _active_toggle: WeToggle


func _ready() -> void:
	super._ready()
	close_on_dim = false
	_build_fields()
	confirmed.connect(_on_save_pressed)
	cancelled.connect(_on_cancel_pressed)


func _build_fields() -> void:
	_name_field = TEXT_FIELD.instantiate()
	_name_field.label = "Название"
	_name_field.max_length = NAME_MAX_LENGTH
	get_body().add_child(_name_field)

	_short_name_field = TEXT_FIELD.instantiate()
	_short_name_field.label = "Краткое название"
	_short_name_field.max_length = SHORT_NAME_MAX_LENGTH
	get_body().add_child(_short_name_field)

	_code_field = TEXT_FIELD.instantiate()
	_code_field.label = "Системный код"
	_code_field.max_length = 40
	_code_field.text_changed.connect(_on_code_text_changed)
	get_body().add_child(_code_field)

	_sort_field = NUMBER_FIELD.instantiate()
	_sort_field.label = "Порядок"
	_sort_field.min_value = 0
	_sort_field.max_value = 9999
	_sort_field.value = 0
	get_body().add_child(_sort_field)

	_active_toggle = TOGGLE.instantiate()
	_active_toggle.label = "Активен"
	_active_toggle.is_on = true
	get_body().add_child(_active_toggle)


func is_edit_mode() -> bool:
	return _mode == FormMode.EDIT


func get_edit_id() -> int:
	return _edit_id


func open_create() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	set_title("Новый континент")
	set_confirm_text("Создать")
	_fill_defaults()
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func open_edit(continent: Dictionary) -> void:
	_mode = FormMode.EDIT
	_edit_id = int(continent.get("id", -1))
	set_title("Редактирование континента")
	set_confirm_text("Сохранить")
	_name_field.text = str(continent.get("name", ""))
	_short_name_field.text = str(continent.get("short_name", ""))
	_updating_code = true
	_code_field.text = str(continent.get("code", ""))
	_updating_code = false
	_sort_field.value = int(continent.get("sort_order", 0))
	_active_toggle.is_on = bool(continent.get("is_active", true))
	clear_error()
	set_busy(false)
	open()
	_name_field.focus_field()


func set_busy(busy: bool) -> void:
	_busy = busy
	super.set_busy(busy)
	_name_field.editable = not busy
	_short_name_field.editable = not busy
	_code_field.editable = not busy
	_sort_field.editable = not busy
	_active_toggle.disabled = busy


func reset() -> void:
	_mode = FormMode.CREATE
	_edit_id = -1
	_fill_defaults()
	clear_error()
	set_busy(false)
	close()


func _fill_defaults() -> void:
	_name_field.text = ""
	_short_name_field.text = ""
	_updating_code = true
	_code_field.text = ""
	_updating_code = false
	_sort_field.value = 0
	_active_toggle.is_on = true


func _on_code_text_changed(new_text: String) -> void:
	if _updating_code or _busy:
		return
	var caret: int = _code_field.caret_column
	var normalized: String = ContinentCode.normalize(new_text)
	if normalized == new_text:
		return
	_updating_code = true
	_code_field.text = normalized
	_code_field.caret_column = mini(caret, normalized.length())
	_updating_code = false


func _on_save_pressed() -> void:
	if _busy:
		return

	var name_text: String = _name_field.text.strip_edges()
	if name_text.is_empty():
		show_error("Введите название континента.")
		_name_field.focus_field()
		return
	if name_text.length() > NAME_MAX_LENGTH:
		show_error("Название не должно превышать %d символов." % NAME_MAX_LENGTH)
		_name_field.focus_field()
		return

	var short_name: String = _short_name_field.text.strip_edges()
	if short_name.length() > SHORT_NAME_MAX_LENGTH:
		show_error("Краткое название не должно превышать %d символов." % SHORT_NAME_MAX_LENGTH)
		_short_name_field.focus_field()
		return

	var code: String = ContinentCode.normalize(_code_field.text)
	if code.is_empty():
		show_error("Введите системный код.")
		_code_field.focus_field()
		return
	if not ContinentCode.is_valid(code):
		show_error("Системный код не может начинаться с цифры.")
		_code_field.focus_field()
		return

	clear_error()
	submitted.emit({
		"name": name_text,
		"short_name": short_name,
		"code": code,
		"sort_order": _sort_field.value,
		"is_active": _active_toggle.is_on,
	})


func _on_cancel_pressed() -> void:
	if _busy:
		return
	reset()
