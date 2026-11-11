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
var _group_panels: Dictionary = {}
var _group_buttons: Dictionary = {}
var _selected_group := MatchSimConfigScript.GROUP_SCORING
var _summary: Label


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
	_group_panels.clear()
	_group_buttons.clear()
	var nav := HFlowContainer.new()
	nav.add_theme_constant_override("h_separation", 8)
	nav.add_theme_constant_override("v_separation", 8)
	_sections.add_child(nav)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.add_theme_color_override("font_color", WeTokens.ACCENT)
	_summary.add_theme_font_size_override("font_size", 13)
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var section_actions := HBoxContainer.new()
	section_actions.add_theme_constant_override("separation", 16)
	section_actions.add_child(_summary)
	var reset_section := WeButton.new()
	reset_section.text = "Сбросить этот раздел"
	reset_section.focus_mode = Control.FOCUS_NONE
	reset_section.pressed.connect(_on_reset_group_pressed)
	section_actions.add_child(reset_section)
	_sections.add_child(section_actions)
	for group in MatchSimConfigScript.GROUPS:
		var id := str(group.id)
		var button := WeButton.new()
		button.text = str(group.short)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_select_group.bind(id))
		nav.add_child(button)
		_group_buttons[id] = button
		var wrap := VBoxContainer.new()
		wrap.add_theme_constant_override("separation", 16)
		wrap.add_child(_make_group_header(group))
		_sections.add_child(wrap)
		_group_panels[id] = wrap
		var basic := _make_grid()
		wrap.add_child(basic)
		var advanced_button := WeButton.new()
		advanced_button.text = "Дополнительные настройки"
		advanced_button.toggle_mode = true
		advanced_button.focus_mode = Control.FOCUS_NONE
		wrap.add_child(advanced_button)
		var advanced := _make_grid()
		advanced.visible = false
		wrap.add_child(advanced)
		advanced_button.toggled.connect(func(expanded: bool): advanced.visible = expanded)
		var advanced_count := 0
		for knob in MatchSimConfigScript.schema():
			if str(knob.group) != id:
				continue
			var field: SliderField = SLIDER_SCENE.instantiate()
			field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			field.configure(_field_spec(knob), float(knob.default))
			if bool(knob.get("advanced", false)):
				advanced.add_child(field)
				advanced_count += 1
			else:
				basic.add_child(field)
			(field.get_node("%Label") as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			field.value_changed.connect(_on_field_changed)
			_fields[str(knob.key)] = field
		advanced_button.visible = advanced_count > 0
		advanced_button.text += " (%d)" % advanced_count
	_select_group(_selected_group)


func _make_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return grid


func _field_spec(spec: Dictionary) -> Dictionary:
	var out := spec.duplicate()
	out["hint"] = str(spec.hint) + "\nРекомендуется: " + MatchSimConfigScript.format_value(spec, float(spec.default))
	return out


func _select_group(id: String) -> void:
	_selected_group = id
	for key in _group_panels:
		_group_panels[key].visible = key == id
		_group_buttons[key].kind = WeButton.Kind.PRIMARY if key == id else WeButton.Kind.GHOST
	_update_summary()


func _update_summary() -> void:
	if _summary == null or _fields.is_empty():
		return
	var v := _collect_values()
	match _selected_group:
		MatchSimConfigScript.GROUP_LINEUP:
			_summary.text = "Замены запрещены, включая замены при травмах." if int(v.subs_max) == 0 else "До %d замен · плановые с %d-й минуты · последнюю бережём до %d-й. Травмы не ждут планового времени." % [int(v.subs_max), int(v.subs_first_minute), int(v.subs_reserve_until)]
		MatchSimConfigScript.GROUP_FITNESS:
			_summary.text = "Обычная выносливость: после полной игры готовность ≈ %d/100, работоспособность ≈ %d%%. Характер игры и возраст меняют нагрузку." % [int(v.condition_after_stamina_10), roundi(float(v.fresh_after_stamina_10)*100)]
		MatchSimConfigScript.GROUP_BALANCE:
			_summary.text = "100% означает базовую чувствительность движка, а не вероятность победы. Учитываются игроки, которые действительно находятся на поле."
		MatchSimConfigScript.GROUP_COACHING:
			_summary.text = "Сначала выбираются игроки и план, затем разыгрываются эпизоды. Эти настройки меняют силу тактических поправок и тренерских бонусов."
		_:
			_summary.text = "Футбол 8 на 8 · два тайма по 25 минут. Для более результативной игры начните с темпа атак; остальные параметры меняйте по одному."


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
		field.configure(_field_spec(spec), float(values.get(key, spec.get("default", 0.0))))
	_update_summary()


func _collect_values() -> Dictionary:
	var out := {}
	for key in _fields.keys():
		out[str(key)] = float((_fields[key] as SliderField).value)
	return out


func _on_field_changed(_value: float) -> void:
	if _suppress_dirty:
		return
	_dirty = true
	_update_summary()
	_set_status("Есть несохранённые изменения.", WeTokens.ACCENT)
	_refresh_actions()


func _refresh_actions() -> void:
	_save_button.disabled = not _dirty


func _on_save_pressed() -> void:
	var error := MatchSimConfigScript.validation_error(_collect_values())
	if not error.is_empty():
		_set_status(error, WeTokens.DANGER)
		return
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
	_update_summary()
	_set_status("Восстановлены значения по умолчанию — нажмите «Сохранить».", WeTokens.ACCENT)
	_refresh_actions()


func _on_reset_group_pressed() -> void:
	_suppress_dirty = true
	for spec in MatchSimConfigScript.schema():
		if str(spec.group) == _selected_group:
			(_fields[str(spec.key)] as SliderField).configure(_field_spec(spec), float(spec.default))
	_suppress_dirty = false
	_dirty = true
	_update_summary()
	_set_status("Рекомендуемые значения для этого раздела восстановлены. Нажмите «Сохранить».", WeTokens.ACCENT)
	_refresh_actions()


func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)
