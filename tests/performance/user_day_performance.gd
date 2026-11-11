extends Node
## Read-only source snapshot; all advancement and writes stay in its isolated copy.
const Config := preload("res://game/match_simulation_config.gd")
var report := {"samples": [], "digests": {}}
var output := ""

func _ready() -> void:
	call_deferred("run")

func record(label: String, started: int, extra: Dictionary = {}) -> void:
	var row := {"label": label, "ms": (Time.get_ticks_usec() - started) / 1000.0,
		"season": GameSession.season_number, "day": GameSession.season_day}
	row.merge(extra)
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		row["native"] = native.metrics(true)
	report.samples.append(row)
	print("DAY PERF ", JSON.stringify(row))
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [1, 2])
	var paced := args.size() == 2 and args[1] == "frames60"
	assert(args.size() == 1 or paced)
	if paced:
		Engine.max_fps = 60
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	var snapshot := args[0].replace("\\", "/").simplify_path()
	assert(snapshot.begins_with(root + "/user-") and snapshot.ends_with("-snapshot"))
	output = snapshot.path_join("day-performance-frames60.json" if paced else "day-performance.json")
	SaveStore.database_path_override = snapshot.path_join("games.db")
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	assert(WorldDatabase.initialize())
	Config.config_path = snapshot.path_join("config/match_simulation.json")
	Config.unload()
	YouthGenerationConfig.config_path = snapshot.path_join("config/youth_generation.json")
	YouthGenerationConfig.birth_config_path = snapshot.path_join("config/youth_talent_birth.json")
	YouthGenerationConfig.unload()
	var store := SaveStore.new()
	var started := Time.get_ticks_usec()
	var loaded := store.load_slot("perf_seed" if paced else "autosave")
	assert(loaded.success)
	assert(GameSession.apply_save_payload(loaded.data).success)
	report["backend"] = NativeSimulation.backend()
	report["cpu"] = OS.get_processor_name()
	report["engine"] = Engine.get_version_info()
	report["players"] = GameSession._count_saved_players()
	report["frame_limit"] = Engine.max_fps
	report["pools"] = {"main": 0, "reserve": 0, "youth": 0, "free": GameSession.free_agents.size()}
	for pair in [["main", GameSession.players_by_club], ["reserve", GameSession.reserve_players_by_club], ["youth", GameSession.youth_players_by_club]]:
		for players in pair[1].values():
			report.pools[pair[0]] += players.size()
	report["units"] = []
	for unit in GameSession.units:
		report.units.append({"id": unit.id, "name": unit.name, "clubs": unit.get("clubs_by_id", {}).size(),
			"divisions": unit.get("divisions", []).size(), "matches": unit.get("matches", []).size()})
	record("load_source", started)
	if GameSession.season_finished:
		started = Time.get_ticks_usec()
		assert(GameSession.start_new_season().success)
		record("new_season", started, {"profile": GameSession.last_new_season_profile.duplicate(), "market": GameSession.last_market_profile.duplicate()})
	while GameSession.is_market_day(GameSession.season_day):
		started = Time.get_ticks_usec()
		assert(GameSession.advance_day().success)
		record("opening_day", started, {"profile": GameSession.last_day_profile.duplicate(), "market": GameSession.last_market_profile.duplicate()})
	if not paced:
		started = Time.get_ticks_usec()
		assert(GameSession.save_game("perf_seed").success)
		record("save_seed", started)
	for mode in (["sliced", "sliced_ui"] if paced else ["sync", "sliced", "sliced_ui"]):
		loaded = store.load_slot("perf_seed")
		assert(loaded.success and GameSession.apply_save_payload(loaded.data).success)
		var screen: Control = null
		if mode == "sliced_ui":
			GameSession.select_unit(int(GameSession.units[0].id))
			screen = load("res://scenes/game/game_screen.tscn").instantiate()
			add_child(screen)
			await get_tree().process_frame
		for i in (8 if paced else 16):
			if GameSession.season_finished:
				break
			var day := GameSession.season_day
			var matches := 0
			for unit in GameSession.units:
				for match_row in unit.get("matches", []):
					if int(match_row.get("season_day", 0)) == day and not bool(match_row.get("played", false)):
						matches += 1
			started = Time.get_ticks_usec()
			var result: Dictionary
			if mode == "sync":
				result = GameSession.advance_day()
			else:
				result = await GameSession.advance_day_async()
			assert(result.success)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			var frame_start := Time.get_ticks_usec()
			await get_tree().process_frame
			record(mode, started, {"simulation_ms": elapsed, "following_frame_ms": (Time.get_ticks_usec() - frame_start) / 1000.0,
				"simulated_day": day, "matches": matches, "profile": GameSession.last_day_profile.duplicate(), "work": GameSession.last_work_profile.duplicate()})
		if screen != null:
			screen.queue_free()
			await get_tree().process_frame
		GameSession._strip_rating_caches()
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(var_to_bytes([GameSession.units, GameSession.players_by_club, GameSession.youth_players_by_club,
			GameSession.reserve_players_by_club, GameSession.free_agents, GameSession.coaches_by_club,
			GameSession.coach_market, GameSession.national_teams, GameSession.club_budgets, GameSession.transfer_log,
			GameSession._rng.state, GameSession.season_day]))
		report.digests[mode] = hashing.finish().hex_encode()
	started = Time.get_ticks_usec()
	assert(GameSession.save_game("perf_result").success)
	record("save_result", started)
	report["same_state"] = true
	for digest in report.digests.values():
		if digest != report.digests.values()[0]:
			report.same_state = false
	record("complete", Time.get_ticks_usec())
	get_tree().quit(0 if report.same_state else 1)
