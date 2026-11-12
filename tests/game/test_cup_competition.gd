extends Node

var _passed := 0
var _failed := 0

func _ready() -> void:
	call_deferred("_run")

func _assert(ok: bool, message: String) -> void:
	if ok: _passed += 1
	else:
		_failed += 1
		push_error(message)

func _division(id: int, first: int, count: int) -> Dictionary:
	var ids: Array = []
	var clubs := {}
	for i in count:
		ids.append(first + i)
		clubs[first + i] = {"id": first + i, "name": "Клуб %d" % (first + i), "reputation": 500 + i}
	return {"id": id, "competition_id": 1, "unit_kind": "DIVISION", "competition_type": "DIVISIONS", "divisions": [{"index": 0, "club_ids": ids}], "clubs_by_id": clubs, "matches": [], "playoff": {"enabled": false}}

func _stage(name: String, kind: String, sources: Array, advance: int = 1) -> Dictionary:
	return {"name": name, "kind": kind, "source_units": sources, "draw": "RANDOM", "legs": 1, "groups": 2, "qualify": 2, "advance": advance, "gap": 2, "start_day": 1}

func _cup(stages: Array) -> Dictionary:
	return {"id": 100, "name": "Кубок", "competition_id": 1, "unit_kind": "CUP", "matches": [], "cup_config": {"stages": stages}}

func _finish(units: Array, restore: bool = false) -> Dictionary:
	var cup: Dictionary = units.back()
	var next_id := 1
	for day in range(1, 4000):
		for m in cup["matches"]:
			if int(m["season_day"]) == day:
				m["played"] = true
				m["home_goals"] = 1
				m["away_goals"] = 0
				m["winner_id"] = m["home_id"]
		for m in cup["matches"]:
			next_id = maxi(next_id, int(m["id"]) + 1)
		next_id = CupCompetition.after_day(cup, units, day, next_id)
		if restore and day % 3 == 0:
			units = bytes_to_var(var_to_bytes(units))
			cup = units.back()
		if bool(cup["cup_state"]["finished"]): return cup
	_assert(false, "Кубок должен завершиться")
	return cup

func _run() -> void:
	var lower := _division(4, 1, 16)
	var upper := _division(1, 17, 8)
	var stages := [_stage("Отбор", "KNOCKOUT", [4], 8), _stage("Группы", "GROUPS", [1]), _stage("Финалы", "KNOCKOUT", [])]
	stages[1]["groups"] = 4
	var cup := _cup(stages)
	var units: Array = [lower, upper, cup]
	var before := var_to_bytes([lower, upper])
	_assert(CupCompetition.initialize_all(units, 1).is_empty(), "Корректная цепочка принимается")
	_assert(var_to_bytes([lower, upper]) == before, "Инициализация не меняет дивизионы")
	var completed := _finish(units)
	_assert(int(completed["cup_state"]["champion_id"]) > 0, "Определён чемпион")
	_assert(completed["cup_state"]["stages"][0]["entrants"].size() == 16, "Низший дивизион входит первым")
	_assert(completed["cup_state"]["stages"][1]["entrants"].size() == 16, "Восемь победителей и восемь новых клубов")
	_assert(completed["winners"].size() == 1, "История чемпиона записана")
	_assert(var_to_bytes([lower, upper]) == before, "Розыгрыш не меняет дивизионы")
	var ids := {}
	var occupancy := {}
	for m in completed["matches"]:
		_assert(not ids.has(int(m["id"])), "Уникальные ID матчей")
		ids[int(m["id"])] = true
		for side in ["home_id", "away_id"]:
			var key := "%s:%s" % [m[side], m["season_day"]]
			_assert(not occupancy.has(key), "Клуб не играет дважды за день")
			occupancy[key] = true
	var restore_units: Array = [_division(4, 1, 16), _division(1, 17, 8), _cup(stages)]
	CupCompetition.initialize_all(restore_units, 1)
	var restored := _finish(restore_units, true)
	_assert(JSON.stringify(restored["matches"]) == JSON.stringify(completed["matches"]), "Загрузка посреди этапа сохраняет ход розыгрыша")
	for size in [3, 5, 100, 164, 200]:
		var knockout := _cup([_stage("Кубок", "KNOCKOUT", [1])])
		var world: Array = [_division(1, 1, size), knockout]
		_assert(CupCompetition.initialize_all(world, 2).is_empty(), "Произвольный размер %d" % size)
		var result := _finish(world)
		_assert(result["matches"].size() == size - 1, "N−1 матчей с проходами для %d" % size)
	var selected := _stage("Выбор", "KNOCKOUT", [1])
	selected["selected_only"] = true
	selected["club_ids"] = [2, 5, 8]
	var selection := _cup([selected])
	_assert(CupCompetition.participants(selected, selection, [_division(1, 1, 10)])["ids"] == [2, 5, 8], "Ручной выбор ограничивает участников")
	var invalid := _cup([_stage("Неверно", "GROUPS", [1])])
	_assert(not CupCompetition.validate_world(invalid, [_division(1, 1, 3)]).is_empty(), "Несовместимая структура отклоняется")
	var foreign := _division(1, 1, 10)
	foreign["competition_id"] = 2
	_assert(CupCompetition.participants(selected, selection, [foreign])["ids"].is_empty(), "Клубы другого турнира недоступны")
	var promoted := _division(1, 10, 4)
	_assert(CupCompetition.participants(_stage("Новый сезон", "KNOCKOUT", [1]), selection, [promoted])["ids"] == [10, 11, 12, 13], "Новый сезон читает актуальный состав дивизиона")
	var archive := TournamentHistory.snapshot(completed, 1)
	_assert(archive.has("cup_state") and archive["cup_state"]["stages"].size() == completed["cup_state"]["stages"].size(), "Архив сохраняет этапы кубка")
	var history_dialog := preload("res://scenes/game/season_history_dialog.tscn").instantiate()
	add_child(history_dialog)
	history_dialog.show_season(archive, 1, Callable(), Callable())
	history_dialog._show_tab(2)
	_assert(history_dialog._tabs.get_child(0).get_child_count() > 0 and history_dialog._tabs.get_child(2).get_child_count() > 0, "Архив показывает группы и кубковые матчи")
	history_dialog.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var fixture := preload("res://tests/game/squad_fixtures.gd")
	var match_config := {"home": {"players": fixture.squad(1, 50, rng)}, "away": {"players": fixture.squad(2, 50, rng)}, "allow_draw": false, "aggregate_offset": 100}
	var report := MatchEngine.simulate(match_config, rng)
	_assert(not bool(report["extra_time"]), "Дополнительное время зависит от суммы двух матчей")
	var skipped := _cup([_stage("Раз в четыре года", "KNOCKOUT", [1])])
	skipped["periodicity"] = "QUADRENNIAL"
	skipped["start_season"] = 1
	CupCompetition.initialize_all([_division(1, 1, 4), skipped], 2)
	_assert(bool(skipped["cup_state"]["finished"]) and bool(skipped["cup_state"]["skipped"]), "Периодичность кубка учитывается")
	await _integration()
	_test_rank_rules()
	_test_slots()
	print("CUP: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)

func _test_slots() -> void:
	var first := _stage("Отбор 8 → 4", "KNOCKOUT", [], 4)
	first["team_count"] = 8
	first["slots"] = []
	for place in range(1, 9): first["slots"].append({"unit_id": 4, "place": place})
	var second := _stage("16 команд", "KNOCKOUT", [])
	second["team_count"] = 16
	second["slots"] = []
	for place in range(9, 21): second["slots"].append({"unit_id": 4, "place": place})
	var cup := _cup([first, second])
	var source := _division(4, 1, 24)
	var world: Array = [source, cup]
	_assert(CupCompetition.validate_world(cup, world).is_empty(), "8 команд → 4 прошедших + 12 новых слотов = 16")
	CupCompetition.initialize_all(world, 1)
	var finished := _finish(world, true)
	_assert(finished["cup_state"]["stages"][0]["entrants"].size() == 8, "Первый этап разрешает восемь мест дивизиона")
	_assert(finished["cup_state"]["stages"][1]["entrants"].size() == 16, "Четыре победителя автоматически дополняют 12 новых клубов")
	var bad: Dictionary = second.duplicate(true)
	bad["slots"][0] = first["slots"][0].duplicate()
	_assert(not CupCompetition.validate_world(_cup([first, bad]), world).is_empty(), "Повторное место между этапами отклоняется")
	bad = second.duplicate(true)
	bad["team_count"] = 3
	_assert(not CupCompetition.validate_world(_cup([first, bad]), world).is_empty(), "Этап не может вместить меньше команд, чем передал предыдущий")
	bad = second.duplicate(true)
	bad["slots"][0] = {"unit_id": 0, "place": 0}
	_assert(not CupCompetition.validate_world(_cup([first, bad]), world).is_empty(), "Незаполненный слот отклоняется")

func _test_rank_rules() -> void:
	var source := _division(4, 1, 8)
	source["standings"] = []
	for id in range(1, 9):
		source["standings"].append({"club_id": id, "points": id * 3, "goal_diff": 0, "goals_for": 0})
	var first := _stage("Последние четыре", "KNOCKOUT", [4], 2)
	first["selection_mode"] = "BOTTOM"
	first["place_count"] = 4
	var second := _stage("Оставшиеся и победители", "KNOCKOUT", [4])
	second["selection_mode"] = "REMAINING"
	var cup := _cup([first, second])
	_assert(CupCompetition.participants(first, cup, [source])["ids"] == [4, 3, 2, 1], "Последние места берутся из таблицы, а не из порядка клубов")
	var range_rule := first.merged({"selection_mode": "RANGE", "place_from": 2, "place_to": 4}, true)
	_assert(CupCompetition.participants(range_rule, cup, [source])["ids"] == [7, 6, 5], "Диапазон мест включителен")
	_assert(CupCompetition.participants(first.merged({"selection_mode": "TOP", "place_count": 2}, true), cup, [source])["ids"] == [8, 7], "Первые N мест")
	var world: Array = [source, cup]
	var before := var_to_bytes(source)
	_assert(CupCompetition.initialize_all(world, 1).is_empty(), "Один дивизион может входить на нескольких этапах")
	var finished := _finish(world, true)
	_assert(finished["cup_state"]["stages"][0]["entrants"] == [4, 3, 2, 1], "Первый этап получает последние четыре команды")
	var next_entrants: Array = finished["cup_state"]["stages"][1]["entrants"]
	_assert(next_entrants.size() == 6, "Следующий этап: четыре оставшихся и два прошедших")
	for id in [5, 6, 7, 8]:
		_assert(id in next_entrants, "Оставшийся клуб входит во второй этап")
	_assert(var_to_bytes(source) == before, "Отбор по местам не меняет исходный дивизион")

func _integration() -> void:
	_assert(OS.get_user_data_dir().contains("fc-cup-tests"), "Интеграция использует отдельную тестовую базу")
	if not OS.get_user_data_dir().contains("fc-cup-tests"): return
	# Remove only fixtures left by an interrupted run in this dedicated database.
	for old in CompetitionRepository.new().get_all().get("data", []):
		if str(old.get("name", "")) == "Cup integration":
			CompetitionRepository.new().delete(int(old["id"]))
	var competition := CompetitionRepository.new().create({"name": "Cup integration", "scope_type": "INTERCONTINENTAL_CLUB"})
	_assert(competition["success"], "Создан тестовый турнир")
	if not competition["success"]: return
	var competition_id := int(competition["data"]["id"])
	var repo := CompetitionUnitRepository.new()
	var division := repo.create({"competition_id": competition_id, "name": "Источник", "unit_kind": "DIVISION", "competition_type": "DIVISIONS", "divisions_count": 1, "teams_per_division": 4, "matches_vs_own": 1})
	var cup := repo.create({"competition_id": competition_id, "name": "Настраиваемый кубок", "unit_kind": "CUP", "competition_type": "CUP"})
	_assert(division["success"] and cup["success"], "Созданы дивизион и кубок")
	var country := CountryRepository.new().create({"continent_id": 1, "name": "Cup test country", "abbreviation": "CUPT"})
	_assert(country["success"], "Создана страна")
	if not country["success"]: return
	var club_ids: Array = []
	for i in 4:
		var club := ClubRepository.new().create({"name": "Cup test club %d" % i, "short_name": "CT%d" % i, "country_id": country["data"]["id"]})
		_assert(club["success"], "Создан клуб")
		if club["success"]: club_ids.append(int(club["data"]["id"]))
	repo.set_club_ids(int(division["data"]["id"]), club_ids)
	var division_before := repo.get_by_id(int(division["data"]["id"]))
	var config := {"stages": [_stage("Полуфиналы и финал", "KNOCKOUT", [int(division["data"]["id"])])]}
	config["stages"][0]["legs"] = 2
	var format_repo := CupFormatRepository.new()
	_assert(format_repo.save_config(int(cup["data"]["id"]), config)["success"], "Настройки кубка сохранены")
	_assert(format_repo.get_config(int(cup["data"]["id"])) == config, "Настройки переживают чтение из SQLite")
	_assert(repo.get_by_id(int(division["data"]["id"])) == division_before, "Запись кубка не меняет строку дивизиона")
	_assert(not format_repo.save_config(int(division["data"]["id"]), config)["success"], "Конструктор не записывает настройки в дивизион")
	var dialog := preload("res://scenes/world_editor/dialogs/cup_format_dialog.tscn").instantiate()
	add_child(dialog)
	dialog.open_editor(cup["data"], repo.get_by_competition(competition_id)["data"])
	_assert(dialog._stages.size() == 1, "Редактор загрузил этап")
	dialog._pick(0)
	_assert(dialog._picker.visible and dialog._picker._clubs.size() == 4, "Выбор команд открывает клубы исходного дивизиона")
	_assert(dialog._picker.top_level and dialog._picker.z_index > dialog.z_index, "Окно выбора команд выше родительского окна и доступно для нажатий")
	var picker_args := OS.get_cmdline_user_args()
	if picker_args.size() >= 2 and picker_args[0] == "--picker-preview" and DisplayServer.get_name() != "headless":
		dialog.theme = load("res://ui/theme/app_theme.tres")
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(picker_args[1])
	dialog._picker._selected[int(club_ids[0])] = true
	dialog._picker._on_confirm()
	_assert(bool(dialog._stages[0]["selected_only"]) and dialog._stages[0]["club_ids"] == [club_ids[0]], "Выбранные команды возвращаются в черновик этапа")
	dialog._picker.close()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--preview" and DisplayServer.get_name() != "headless":
		dialog.theme = load("res://ui/theme/app_theme.tres")
		dialog._stages = [_stage("Отбор · 8 команд, проходят 4", "KNOCKOUT", [], 4), _stage("Основной этап · 16 команд", "KNOCKOUT", [])]
		dialog._stages[0]["team_count"] = 8
		dialog._stages[1]["team_count"] = 16
		dialog._render()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[1])
		dialog._stages = config["stages"].duplicate(true)
	dialog._stages[0]["name"] = "Несохранённое изменение"
	dialog.close()
	_assert(format_repo.get_config(int(cup["data"]["id"])) == config, "Отмена редактора не меняет базу")
	dialog.queue_free()
	var parent_form := preload("res://scenes/world_editor/dialogs/competition_form_dialog.tscn").instantiate()
	add_child(parent_form)
	parent_form.open_edit(competition["data"])
	_assert(parent_form._cup_dialog != null, "Конструктор подключён к форме турнира")
	parent_form.queue_free()
	var slot_config: Dictionary = config.duplicate(true)
	slot_config["stages"][0]["team_count"] = 4
	slot_config["stages"][0]["slots"] = []
	for place in range(1, 5): slot_config["stages"][0]["slots"].append({"unit_id": int(division["data"]["id"]), "place": place})
	_assert(format_repo.save_config(int(cup["data"]["id"]), slot_config)["success"], "Слоты сохраняются в SQLite")
	_assert(format_repo.get_config(int(cup["data"]["id"])) == slot_config, "Идентификаторы и места слотов восстанавливаются из SQLite")
	GameSession.clear()
	var started := GameSession.start_new_game(1729)
	_assert(started["success"], "Создана игровая сессия с кубком: " + str(started.get("error", "")))
	if started["success"]:
		var days := 0
		while not GameSession.season_finished and days < 200:
			var result: Dictionary
			if days % 2 == 0: result = await GameSession.advance_day_async()
			else: result = GameSession.advance_day()
			_assert(result["success"], "Продвижение синхронного / асинхронного дня")
			days += 1
		_assert(GameSession.season_finished, "Завершён полный сезон с кубком")
		var cup_unit: Dictionary = {}
		for u in GameSession.units:
			if int(u["id"]) == int(cup["data"]["id"]): cup_unit = u
		_assert(cup_unit.get("cup_state", {}).get("champion_id", 0) > 0, "Матчевый движок определил победителя кубка")
		_assert(cup_unit.get("matches", []).size() == 6, "Четыре клуба сыграли три двухматчевые пары")
		var saved := GameSession.save_game("cup-integration")
		_assert(saved["success"], "Сохранение кубка в игровую базу")
		var loaded := GameSession.load_game("cup-integration")
		_assert(loaded["success"], "Загрузка кубка из игровой базы")
		var next := GameSession.start_new_season()
		_assert(next["success"], "Следующий сезон запускается с прежними правилами дивизионов")
		GameSession.delete_save("cup-integration")
	GameSession.clear()
	repo.set_club_ids(int(division["data"]["id"]), [])
	CompetitionRepository.new().delete(competition_id)
	_assert(format_repo.get_config(int(cup["data"]["id"])).is_empty(), "Удаление турнира удаляет только принадлежащие ему настройки кубка")
	for id in club_ids: ClubRepository.new().delete(int(id))
	CountryRepository.new().delete(int(country["data"]["id"]))
