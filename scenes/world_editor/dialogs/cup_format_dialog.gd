extends WeModal
## Cup-only draft editor: no division writes and no database writes until Save.

signal saved
var _cup: Dictionary
var _sources: Array = []
var _stages: Array = []
var _list: VBoxContainer
var _picker: Control
var _pick_index := -1
var _active: CheckBox
var _member_counts := {}

func _ready() -> void:
	super._ready()
	close_on_dim = false
	z_index = 120
	set_card_size(960, 850)
	var hint := Label.new()
	hint.text = "Задайте число команд и заполните слоты местами из дивизионов этого турнира. Прошедшие предыдущий этап занимают слоты автоматически. Места берутся из итоговых таблиц сезона; жеребьёвка пар настраивается отдельно."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	get_body().add_child(hint)
	_active = CheckBox.new()
	_active.text = "Проводить кубок"
	get_body().add_child(_active)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	get_body().add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 14)
	scroll.add_child(_list)
	var add := Button.new()
	add.text = "+ Добавить этап"
	add.pressed.connect(func():
		_stages.append({"name": "Этап %d" % (_stages.size() + 1), "kind": "KNOCKOUT", "draw": "RANDOM", "legs": 1, "groups": 2, "qualify": 2, "advance": 1, "gap": 2, "start_day": 1, "team_count": 8, "slots": [], "source_units": [], "club_ids": [], "selected_only": false})
		_render()
	)
	get_body().add_child(add)
	_picker = preload("res://scenes/world_editor/dialogs/competition_unit_clubs_dialog.tscn").instantiate()
	add_child(_picker)
	# The picker's _ready() sets its own layer. Set the nested modal layer afterwards.
	_picker.z_index = z_index + 10
	_picker.clubs_submitted.connect(func(_id, ids):
		if _pick_index >= 0 and _pick_index < _stages.size():
			_stages[_pick_index]["club_ids"] = ids
			_stages[_pick_index]["selected_only"] = true
			_stages[_pick_index]["selection_mode"] = "MANUAL"
			_render()
	)
	confirmed.connect(_save)
	cancelled.connect(func(): close())

func open_editor(cup: Dictionary, sources: Array) -> void:
	_cup = cup
	var loaded := CompetitionUnitRepository.new().get_by_competition(int(cup.get("competition_id", 0)))
	var available: Array = loaded.get("data", sources) if loaded.get("success", false) else sources
	_sources = available.filter(func(u): return str(u.get("unit_kind", "")) == "DIVISION")
	_member_counts.clear()
	for source in _sources:
		var members := CompetitionUnitRepository.new().get_club_ids(int(source["id"]))
		_member_counts[int(source["id"])] = members.get("data", []).size()
	var config := CupFormatRepository.new().get_config(int(cup["id"]))
	_stages = config.get("stages", []).duplicate(true)
	_upgrade_slots()
	_active.button_pressed = not _stages.is_empty()
	clear_error()
	set_title("Этапы кубка · " + str(cup.get("name", "")))
	set_confirm_text("Сохранить кубок")
	_render()
	open()

func _render() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for i in _stages.size():
		var s: Dictionary = _stages[i]
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, 10, 12))
		_list.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 8)
		panel.add_child(box)
		var header := HBoxContainer.new()
		box.add_child(header)
		var name := LineEdit.new()
		name.text = str(s.get("name", ""))
		name.placeholder_text = "Название этапа"
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name.text_changed.connect(func(t): s["name"] = t)
		header.add_child(name)
		for direction in [-1, 1]:
			var move := Button.new()
			move.text = "↑" if direction == -1 else "↓"
			move.disabled = i + direction < 0 or i + direction >= _stages.size()
			move.pressed.connect(func():
				var other: Variant = _stages[i + direction]
				_stages[i + direction] = _stages[i]
				_stages[i] = other
				_render()
			)
			header.add_child(move)
		var remove := Button.new()
		remove.text = "Удалить этап"
		remove.pressed.connect(func(): _stages.remove_at(i); _render())
		header.add_child(remove)
		var formats := HBoxContainer.new()
		box.add_child(formats)
		_select(formats, "Формат", s, "kind", [["KNOCKOUT", "Плей-офф"], ["GROUPS", "Группы"]], true)
		_select(formats, "Жеребьёвка", s, "draw", [["RANDOM", "Свободная"], ["ELO", "Корзины по Elo"], ["REPUTATION", "Корзины по репутации"], ["DIVISION", "Корзины по дивизионам"]])
		_number(formats, "Матчей / кругов", s, "legs", 1, 2)
		var rules := HBoxContainer.new()
		box.add_child(rules)
		if str(s.get("kind", "KNOCKOUT")) == "GROUPS":
			_number(rules, "Групп", s, "groups", 1, 512, true)
			_number(rules, "Выходят из группы", s, "qualify", 1, 512, true)
		else:
			_number(rules, "Выходят дальше", s, "advance", 1, 4096, true)
		_number(rules, "Не раньше дня", s, "start_day", 1, 10000)
		_number(rules, "Интервал матчей", s, "gap", 1, 30)
		var neutral := CheckBox.new()
		neutral.text = "Нейтральное поле"
		neutral.button_pressed = bool(s.get("neutral", false))
		neutral.toggled.connect(func(on): s["neutral"] = on)
		box.add_child(neutral)
		_build_slots(box, s, i)

	if _stages.is_empty():
		var empty := Label.new()
		empty.text = "Добавьте этапы. Последний этап должен определять одного победителя."
		_list.add_child(empty)

func _upgrade_slots() -> void:
	var snapshots := _source_snapshots()
	var entered := {}
	var carry := 0
	for s in _stages:
		if not s.has("slots"):
			var p := CupCompetition.participants(s, _cup, snapshots)
			var slots: Array = []
			for id in p["ids"]:
				if entered.has(id): continue
				entered[id] = true
				var origin := int(p["origins"].get(id, 0))
				for source in snapshots:
					if int(source["id"]) != origin: continue
					var ids: Array = source["divisions"][0]["club_ids"]
					slots.append({"unit_id": origin, "place": ids.find(id) + 1})
			s["slots"] = slots
			s["team_count"] = carry + slots.size()
		carry = CupCompetition.output_count(s)

func _build_slots(box: VBoxContainer, s: Dictionary, index: int) -> void:
	s["team_count"] = maxi(2, int(s.get("team_count", 8)))
	var carry := CupCompetition.output_count(_stages[index - 1]) if index > 0 else 0
	var row := HBoxContainer.new()
	box.add_child(row)
	_number(row, "Команд на этапе", s, "team_count", 2, 4096, true)
	var title := Label.new()
	title.text = "%d автоматически из предыдущего этапа" % carry
	row.add_child(title)
	if int(s.get("team_count", 8)) < carry:
		var error := Label.new()
		error.text = "Предыдущий этап передаёт больше команд, чем вмещает этот. Увеличьте число участников."
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(error)
	var slots: Array = s.get("slots", [])
	var free := maxi(0, int(s.get("team_count", 8)) - carry)
	while slots.size() < free: slots.append({"unit_id": 0, "place": 0})
	if slots.size() > free: slots.resize(free)
	s["slots"] = slots
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	for n in carry:
		var reserved := Label.new()
		reserved.text = "Слот %d · Прошедший №%d из «%s»" % [n + 1, n + 1, _stages[index - 1].get("name", "Предыдущий этап")]
		reserved.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reserved.custom_minimum_size.x = 400
		grid.add_child(reserved)
	for n in slots.size():
		var slot: Dictionary = slots[n]
		var line := HBoxContainer.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(line)
		var label := Label.new()
		label.text = "Слот %d" % (carry + n + 1)
		line.add_child(label)
		var source_select := OptionButton.new()
		source_select.custom_minimum_size.x = 180
		source_select.add_item("Выберите дивизион", 0)
		for source in _sources:
			var id := int(source["id"])
			source_select.add_item(str(source["name"]), id)
			if id == int(slot.get("unit_id", 0)): source_select.select(source_select.item_count - 1)
		line.add_child(source_select)
		source_select.item_selected.connect(func(selected):
			slot["unit_id"] = source_select.get_item_id(selected)
			slot["place"] = 0
			call_deferred("_render")
		)
		var place_select := OptionButton.new()
		place_select.add_item("Место", 0)
		for place in range(1, int(_member_counts.get(int(slot.get("unit_id", 0)), 0)) + 1):
			place_select.add_item("%d-е место" % place, place)
			if place == int(slot.get("place", 0)): place_select.select(place)
		place_select.disabled = int(slot.get("unit_id", 0)) == 0
		place_select.item_selected.connect(func(selected): slot["place"] = place_select.get_item_id(selected))
		line.add_child(place_select)
	if _sources.is_empty():
		var empty := Label.new()
		empty.text = "В этом турнире нет дивизионов. Добавьте их в состав турнира, чтобы выбирать места."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(empty)

func _select(row: HBoxContainer, title: String, s: Dictionary, key: String, items: Array, rebuild: bool = false) -> void:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wrap)
	var label := Label.new()
	label.text = title
	wrap.add_child(label)
	var field := OptionButton.new()
	for item in items:
		field.add_item(str(item[1]))
		if str(s.get(key, "")) == str(item[0]): field.select(field.item_count - 1)
	field.item_selected.connect(func(index):
		s[key] = items[index][0]
		if rebuild: call_deferred("_render")
	)
	wrap.add_child(field)

func _number(row: HBoxContainer, title: String, s: Dictionary, key: String, minimum: int, maximum: int, rebuild: bool = false) -> void:
	var wrap := VBoxContainer.new()
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(wrap)
	var label := Label.new()
	label.text = title
	wrap.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.value = int(s.get(key, minimum))
	field.value_changed.connect(func(v):
		s[key] = int(v)
		if rebuild: call_deferred("_render")
	)
	wrap.add_child(field)

func _source_snapshots() -> Array:
	var result: Array = []
	for source in _sources:
		var u: Dictionary = source.duplicate(true)
		var ids := CompetitionUnitRepository.new().get_club_ids(int(u["id"]))
		u["divisions"] = [{"club_ids": ids.get("data", [])}]
		u["clubs_by_id"] = {}
		result.append(u)
	return result

func _pick(index: int) -> void:
	if index < 0 or index >= _stages.size():
		return
	_pick_index = index
	var s: Dictionary = _stages[index]
	var p := CupCompetition.participants(s.merged({"selection_mode": "ALL", "selected_only": false}, true), _cup, _source_snapshots())
	var clubs: Array = []
	for id in p["ids"]:
		var loaded := ClubRepository.new().get_by_id(int(id))
		if loaded["success"]: clubs.append(loaded["data"])
	_picker.z_index = z_index + 10
	_picker.open_picker(int(_cup["id"]), str(s["name"]), clubs, s.get("club_ids", []))

func _save() -> void:
	var config := {"version": 1, "stages": _stages} if _active.button_pressed else {}
	if _active.button_pressed:
		var draft := _cup.duplicate(true)
		draft["cup_config"] = config
		var errors := CupCompetition.validate_world(draft, _source_snapshots())
		if not errors.is_empty():
			show_error("\n".join(errors))
			return
	var result := CupFormatRepository.new().save_config(int(_cup["id"]), config)
	if not result["success"]:
		show_error(str(result.get("error", "Ошибка сохранения")))
		return
	saved.emit()
	close()
