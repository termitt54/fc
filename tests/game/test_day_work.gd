extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0
var frames := 0
var busy_checks := false
var changed := 0
var screen: Control = null
var stop_on_progress := false

func _ready() -> void:
	GameSession.simulation_progress.connect(_progress)
	GameSession.session_changed.connect(func(): changed += 1)
	call_deferred("_run")

func _process(_delta: float) -> void:
	if GameSession.is_processing:
		frames += 1

func _run() -> void:
	var sort_players: Array = []
	for i in 512:
		sort_players.append({"id": i, "reputation": i % 9, "current_ability": i % 13})
	var expected_sort := sort_players.duplicate()
	expected_sort.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(a.get("reputation", 0))
		var rb := int(b.get("reputation", 0))
		return ra > rb if ra != rb else int(a.get("current_ability", 0)) > int(b.get("current_ability", 0)))
	var sorting: RefCounted = load("res://game/target_sort_work.gd").new(sort_players)
	while not sorting.is_ready():
		await get_tree().process_frame
	var sorted: Array = []
	for i in sorting.take():
		sorted.append(sort_players[i])
	_check(sorted == expected_sort, "Worker sort preserves original equal-key order")
	var fixture := _fixture(20)
	for market_case in [false, true]:
		fixture["season_day"] = -6 if market_case else 1
		_check(GameSession.apply_save_payload(fixture.duplicate(true))["success"], "Sync fixture loads")
		GameSession._rng.seed = 4411
		for day in (6 if market_case else 1):
			_check(GameSession.advance_day()["success"], "Sync day completes")
		var expected := _state()
		_check(GameSession.apply_save_payload(fixture.duplicate(true))["success"], "Sliced fixture loads")
		GameSession._rng.seed = 4411
		frames = 0
		busy_checks = false
		changed = 0
		for day in (6 if market_case else 1):
			var result: Dictionary = await GameSession.advance_day_async(1)
			_check(result["success"] and not GameSession.is_processing, "Sliced day completes and unlocks")
			_check(int(GameSession.last_work_profile["yields"]) > 0, "Day yields to frames")
		_check(_state() == expected, "Full state and RNG match sync path: market=" + str(market_case))
		_check(frames > 0 and busy_checks, "Heartbeat runs during processing")
		_check(changed == (6 if market_case else 1), "Only finished days publish session changes")
	fixture["season_day"] = 1
	_check(GameSession.apply_save_payload(fixture.duplicate(true))["success"], "UI fixture loads")
	screen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	busy_checks = false
	stop_on_progress = true
	screen._start_simulation(screen.SIM_SEASON)
	while GameSession.is_processing or screen._sim_loop_active:
		await get_tree().process_frame
	_check(screen._sim_mode == screen.SIM_OFF and GameSession.season_day == 2, "Auto stop finishes one day and starts no next day")
	_check(not screen.get_node("%AdvanceDayButton").disabled, "Day control unlocks after completion")
	screen.queue_free()
	await get_tree().process_frame
	screen = null
	GameSession.clear()
	var empty: Dictionary = await GameSession.advance_day_async()
	_check(not empty["success"] and not GameSession.is_processing, "Inactive day fails without locking")
	print("=== Day work: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _progress(_stage: String, _done: int, _total: int) -> void:
	if screen != null and stop_on_progress:
		stop_on_progress = false
		_check(screen.get_node("%AdvanceDayButton").disabled, "UI blocks a second day while busy")
		_check(not screen.get_node("%SimButton").disabled, "Auto stop stays available during work")
		screen._stop_simulation()
	if busy_checks:
		return
	busy_checks = true
	_check(GameSession.is_processing, "Progress is emitted while locked")
	_check(not GameSession.advance_day()["success"], "Duplicate day is rejected")
	_check(not GameSession.save_game("work_guard")["success"], "Partial save is rejected")
	_check(not GameSession.load_game("work_guard")["success"], "Load is rejected during work")
	_check(not GameSession.apply_save_payload({})["success"], "State replacement is rejected")
	_check(not GameSession.start_new_season()["success"], "New season is rejected during work")
	_check(not GameSession.start_new_game()["success"], "New game is rejected during work")
	_check(not GameSession.delete_save("work_guard")["success"], "Save deletion is rejected during work")
	GameSession.clear()
	_check(GameSession.is_active and not GameSession.units.is_empty(), "Clear cannot erase the active job")

func _state() -> PackedByteArray:
	GameSession._strip_rating_caches()
	return var_to_bytes([GameSession.season_number, GameSession.season_day, GameSession.season_total_days,
		GameSession._rng.state, GameSession._next_match_id, GameSession.units, GameSession.players_by_club,
		GameSession.youth_players_by_club, GameSession.reserve_players_by_club, GameSession.free_agents,
		GameSession.coaches_by_club, GameSession.club_budgets, GameSession.transfer_log, GameSession.wages_paid_for_season])

func _fixture(count: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8001
	var clubs := {}
	var squads := {}
	var coaches := {}
	var agents: Array = []
	var ids: Array = []
	for id in range(1, count + 1):
		ids.append(id)
		clubs[id] = {"id": id, "country_id": 1, "reputation": 500, "name": "Club %d" % id}
		squads[id] = Fixtures.squad(id, 60, rng)
		for i in 7:
			var player: Dictionary = squads[id][i + 2].duplicate(true)
			player["id"] = id * 1000 + 100 + i
			squads[id].append(player)
		coaches[id] = Fixtures.coach(id, rng)
		for player in Fixtures.squad(1000 + id, 63, rng):
			player["club_id"] = 0
			player["contract_status"] = "free_agent"
			agents.append(player)
	var generated := FixtureGenerator.build_regular_season(ids, 1, ids.size(), 1, 0, rng)
	var standings: Array = []
	for id in ids:
		standings.append({"club_id": id, "division": 0, "played": 0, "won": 0, "drawn": 0,
			"lost": 0, "goals_for": 0, "goals_against": 0, "goal_diff": 0, "points": 0})
	return {"version": GameSession.SAVE_VERSION, "season_number": 1, "season_day": 1,
		"selected_unit_id": 1, "players_by_club": squads, "coaches_by_club": coaches,
		"free_agents": agents, "units": [{"id": 1, "competition_type": CompetitionTypes.TYPE_DIVISIONS,
		"name": "Test", "rules": {"regular_season_enabled": true, "divisions_count": 1,
		"teams_per_division": count, "matches_vs_own": 1, "points_win": 3, "points_draw": 1,
		"points_loss": 0, "foreign_players_limit": -1, "ranking_order": RankingCriteria.DEFAULT_ORDER},
		"clubs_by_id": clubs, "divisions": generated["divisions"], "matches": generated["matches"],
		"standings": standings, "playoff": {"enabled": false}, "winners": []}]}

func _check(value: bool, message: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)
