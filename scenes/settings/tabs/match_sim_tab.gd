extends MarginContainer
## Match-engine calibration. Saved to user://config/match_simulation.json.

const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const SLIDER_SCENE := preload("res://ui/components/we_slider_field.tscn")
const SliderField := preload("res://ui/components/we_slider_field.gd")

@onready var _card: PanelContainer = %Card
@onready var _sections: VBoxContainer = %Sections
@onready var _save_button: WeButton = %SaveButton
@onready var _reset_button: WeButton = %ResetButton
@onready var _status: Label = %StatusLabel

var _dirty := false
var _suppress_dirty := false
var _fields: Dictionary = {}


func _ready() -> void:
	_card.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 20)
	)
	_save_button.kind = WeButton.Kind.PRIMARY
	_reset_button.kind = WeButton.Kind.GHOST
	_save_button.focus_mode = Control.FOCUS_NONE
	_reset_button.focus_mode = Control.FOCUS_NONE
	_save_button.pressed.connect(_on_save_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_build_sections()
	_reload_from_config(false)
	_set_status("Изменения применяются к новым матчам.", WeTokens.TEXT_MUTED)


func _build_sections() -> void:
	for child in _sections.get_children():
		child.queue_free()
	_fields.clear()

	var knobs_by_group := {}
	for knob in MatchSimConfigScript.schema():
		var group_id := str(knob.get("group", ""))
		if not knobs_by_group.has(group_id):
			knobs_by_group[group_id] = []
		(knobs_by_group[group_id] as Array).append(knob)

	for group in MatchSimConfigScript.GROUPS:
		var group_id := str(group.get("id", ""))
		var knobs: Array = knobs_by_group.get(group_id, [])
		if knobs.is_empty():
			continue
		var wrap := VBoxContainer.new()
		wrap.add_theme_constant_override("separation", 10)
		wrap.add_child(_make_group_header(group))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 28)
		grid.add_theme_constant_override("v_separation", 16)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wrap.add_child(grid)
		_sections.add_child(wrap)
		for knob in knobs:
			var field: SliderField = SLIDER_SCENE.instantiate()
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.configure(knob, float(knob.get("default", 0.0)))
			grid.add_child(field)
			field.value_changed.connect(_on_field_changed)
			_fields[str(knob["key"])] = field


func _make_group_header(group: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var title := Label.new()
	title.text = str(group.get("title", ""))
	title.add_theme_color_override("font_color", WeTokens.TEXT)
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)
	var hint := Label.new()
	hint.text = str(group.get("hint", ""))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 12)
	box.add_child(hint)
	return box


func _reload_from_config(mark_dirty: bool) -> void:
	_suppress_dirty = true
	var values := MatchSimConfigScript.editor_values()
	_apply_values_to_fields(values)
	_suppress_dirty = false
	_dirty = mark_dirty
	_refresh_actions()


func _apply_values_to_fields(values: Dictionary) -> void:
	for key in _fields.keys():
		var field: SliderField = _fields[key]
		var spec := MatchSimConfigScript.knob_by_key(str(key))
		field.configure(spec, float(values.get(key, spec.get("default", 0.0))))


func _collect_values() -> Dictionary:
	var out := {}
	for key in _fields.keys():
		out[str(key)] = float((_fields[key] as SliderField).value)
	return out


func _on_field_changed(_value: float) -> void:
	if _suppress_dirty:
		return
	_dirty = true
	_set_status("Есть несохранённые изменения.", WeTokens.ACCENT)
	_refresh_actions()


func _refresh_actions() -> void:
	_save_button.disabled = not _dirty


func _on_save_pressed() -> void:
	var result: Dictionary = MatchSimConfigScript.apply_values(_collect_values(), true)
	if not bool(result.get("ok", false)):
		_set_status(str(result.get("error", "Ошибка сохранения.")), WeTokens.DANGER)
		return
	_dirty = false
	_set_status("Сохранено. Новые матчи используют эти коэффициенты.", WeTokens.SUCCESS)
	_refresh_actions()


func _on_reset_pressed() -> void:
	_suppress_dirty = true
	_apply_values_to_fields(MatchSimConfigScript.default_values())
	_suppress_dirty = false
	_dirty = true
	_set_status("Восстановлены значения по умолчанию — нажмите «Сохранить».", WeTokens.ACCENT)
	_refresh_actions()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
