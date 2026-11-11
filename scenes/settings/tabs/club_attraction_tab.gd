extends MarginContainer
const Config = preload("res://game/club_attraction_config.gd")
const Attraction = preload("res://game/club_attraction.gd")
const SliderScene = preload("res://ui/components/we_slider_field.tscn")
const ToggleScene = preload("res://ui/components/we_toggle.tscn")

var _fields := {}
var _mode: WeToggle
var _mode_label: Label
var _preview: Label
var _status: Label
var _save: WeButton
var _dirty := false

func _ready() -> void:
	for side in ["left", "right", "top", "bottom"]: add_theme_constant_override("margin_" + side, 12)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 24))
	scroll.add_child(card)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	card.add_child(box)
	box.add_child(_label("Привлекательность клуба", 22, WeTokens.TEXT))
	box.add_child(_label("Влияет на согласие игрока перейти в клуб или продлить контракт. Зарплата, роль и качество состава учитываются отдельно.", 13, WeTokens.TEXT_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_mode = ToggleScene.instantiate()
	_mode.label = "Соотношение репутации и Elo"
	_mode.custom_minimum_size.x = 420
	row.add_child(_mode)
	for child in _mode.find_children("*", "Control", true, false): child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mode.toggled.connect(func(_on: bool): _changed())
	_mode_label = _label("", 14, WeTokens.ACCENT)
	_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_mode_label)
	box.add_child(_label("Переключатель включён — используются доли. Выключен — действует ограниченная поправка Elo. Неактивный блок не участвует в расчёте.", 12, WeTokens.TEXT_DIM))
	box.add_child(_label("Соотношение", 17, WeTokens.TEXT))
	var weights := _grid()
	box.add_child(weights)
	_add_field(weights, "reputation_weight", "Доля репутации", "Престиж клуба. Доли всегда дают 100%: изменение одной автоматически меняет другую.", 100, "%")
	_add_field(weights, "elo_weight", "Доля Elo", "Текущий клубный Elo. При 50/50 репутация 600 и Elo 800 дают привлекательность 700. Предел поправки и число матчей здесь не используются. Elo и итоговая привлекательность могут быть выше 1000.", 100, "%")
	box.add_child(_label("Поправка Elo", 17, WeTokens.TEXT))
	var bounded := _grid()
	box.add_child(bounded)
	_add_field(bounded, "max_effect", "Предел поправки Elo", "Учитывается 25% разницы спортивной оценки по Elo и репутации, затем применяется предел. Максимальная прибавка или потеря привлекательности к репутации. 60 означает до +60 или −60; 0 отключает поправку. Значение сохраняется для этого режима.", 1000, "")
	_add_field(bounded, "confidence_matches", "Матчей до полного влияния", "20 — поправка постепенно включается за 20 отслеженных матчей клуба. 0 — полное влияние сразу. Это не срок сброса Elo.", 1000, "")
	_preview = _label("", 14, WeTokens.ACCENT)
	box.add_child(_preview)
	box.add_child(_label("Нажмите на любое числовое значение для ручного ввода. Enter применяет ввод, Escape отменяет. Изменения вступают в силу после сохранения.", 12, WeTokens.TEXT_DIM))
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	box.add_child(footer)
	var reset := WeButton.new()
	reset.text = "По умолчанию"
	reset.kind = WeButton.Kind.GHOST
	reset.pressed.connect(func(): _apply_fields(Config.defaults()); _dirty = true; _refresh())
	footer.add_child(reset)
	_status = _label("", 12, WeTokens.TEXT_MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(_status)
	_save = WeButton.new()
	_save.text = "Сохранить"
	_save.kind = WeButton.Kind.PRIMARY
	_save.pressed.connect(_save_settings)
	footer.add_child(_save)
	_apply_fields(Config.snapshot())
	_refresh()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 16)
	return grid

func _add_field(parent: Control, key: String, title: String, hint: String, maximum: float, suffix: String) -> void:
	var field = SliderScene.instantiate()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.configure({"label": title, "hint": hint, "min": 0, "max": maximum, "step": 1,
		"decimals": 0, "suffix": suffix, "default": Config.defaults()[key]}, Config.defaults()[key])
	parent.add_child(field)
	(field.get_node("%Label") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	field.value_changed.connect(func(v: float): _field_changed(key, v))
	_fields[key] = field

func _field_changed(key: String, value: float) -> void:
	if key == "reputation_weight": _fields.elo_weight.value = 100.0 - value
	if key == "elo_weight": _fields.reputation_weight.value = 100.0 - value
	_changed()

func _changed() -> void:
	_dirty = true
	_refresh()

func _values() -> Dictionary:
	var values := {"mode": Config.MODE_WEIGHTS if _mode.is_on else Config.MODE_BOUNDED}
	for key in _fields: values[key] = float(_fields[key].value)
	return values

func _apply_fields(values: Dictionary) -> void:
	_mode.is_on = str(values.mode) == Config.MODE_WEIGHTS
	for key in _fields: _fields[key].value = float(values[key])

func _refresh() -> void:
	var weighted := _mode.is_on
	for key in ["reputation_weight", "elo_weight"]: _fields[key].set_enabled(weighted)
	for key in ["max_effect", "confidence_matches"]: _fields[key].set_enabled(not weighted)
	_mode_label.text = "Сейчас: соотношение" if weighted else "Сейчас: поправка Elo"
	var example := {"reputation": 600, "club_elo": {"elo": 800, "sporting_reputation": 800, "games": 20}}
	_preview.text = ("Пример: репутация 600, Elo 800 → привлекательность %.1f" if weighted else "Пример: репутация 600, расчётная поправка +50, отслежено 20 матчей → привлекательность %.1f") % Attraction.value_with_settings(example, _values())
	_save.disabled = not _dirty
	_status.text = "Есть несохранённые изменения" if _dirty else "Настройки сохранены"

func _save_settings() -> void:
	# Commit any currently focused numeric editor before collecting the values.
	for field in _fields.values(): field._finish_edit()
	var result := Config.apply_values(_values(), true)
	if not bool(result.ok):
		_status.text = str(result.error)
		return
	_dirty = false
	_refresh()
