extends Node
## Diagnostic, not an assertion that a particular title distribution is correct.
## Runs only in the isolated benchmark project. Never changes gameplay rules.
const Builder := preload("res://tests/performance/load_benchmark.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var report := {"frozen": [], "dynamic": [], "errors": []}
var started := 0

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		push_error("Use the isolated benchmark launcher")
		get_tree().quit(2)
		return
	if OS.get_cmdline_user_args().has("--title-check-only"):
		print("TITLE SCRIPT LOAD OK")
		get_tree().quit()
		return
	call_deferred("_run")

func _run() -> void:
	started = Time.get_ticks_msec()
	for profile in ["equal", "two_leaders"]:
		var fixture := _fixture(profile, 4242)
		for format in ["one_round", "four_rounds", "series_four_wins"]:
			var base := _format(fixture, format)
			var champions: Array = []
			var regular: Array = []
			for run in 30:
				if not _ok(GameSession.apply_save_payload(base.duplicate(true))):
					return
				GameSession._rng.seed = 9000 + run
				if not _complete_season():
					return
				var outcome := _outcome()
				champions.append(outcome["champion"])
				regular.append(outcome["regular_champion"])
				await get_tree().process_frame
			var summary := _summary(champions)
			summary.merge({"profile": profile, "format": format, "champions": champions,
				"regular_champions": regular, "regular_summary": _summary(regular),
				"regular_title_equals_final": _agreement(champions, regular)})
			report["frozen"].append(summary)
			print("TITLE FROZEN ", JSON.stringify(summary))
	for seed in [4242, 7711]:
		var base := _format(_fixture("two_leaders", seed), "four_rounds")
		base["season_day"] = -5
		if not _ok(GameSession.apply_save_payload(base)):
			return
		GameSession._rng.seed = seed
		GameSession._begin_calendar_day()
		var rows: Array = []
		var champions: Array = []
		var previous := {}
		for season in 20:
			while GameSession.season_day < 1:
				if not _ok(GameSession.advance_day()):
					return
			var clubs := _club_snapshot(previous)
			previous = {}
			for id in GameSession.players_by_club:
				previous[id] = {}
				for player in GameSession.players_by_club[id]:
					previous[id][int(player["id"])] = true
			if not _complete_season():
				return
			var outcome := _outcome()
			outcome.merge({"season": GameSession.season_number, "clubs_before_matches": clubs})
			rows.append(outcome)
			champions.append(outcome["champion"])
			print("TITLE DYNAMIC seed=", seed, " season=", season + 1, " winner=", outcome["champion"])
			if season < 19 and not _ok(GameSession.start_new_season()):
				return
			await get_tree().process_frame
		var summary := _summary(champions)
		summary.merge({"seed": seed, "champions": champions, "seasons": rows})
		report["dynamic"].append(summary)
	_finish()

func _fixture(profile: String, seed: int) -> Dictionary:
	var builder := Builder.new()
	builder._options["clubs"] = 8
	builder._options["league-size"] = 8
	builder._options["players-per-club"] = 50
	builder._rng.seed = seed
	var payload: Dictionary = builder._build_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed + 100
	var coach := Fixtures.coach(1, rng)
	for id in range(1, 9):
		var club: Dictionary = payload["units"][0]["clubs_by_id"][id]
		club["reputation"] = 750 if profile == "two_leaders" and id <= 2 else 450
		var ca := 80 if profile == "two_leaders" and id <= 2 else 60
		var squad: Array = []
		var used := {}
		for position in PlayerGenerator.build_position_list(rng):
			squad.append(PlayerGenerator.create_player(id, club, rng, {}, used, builder._id_state,
				{"position": position, "current_ability": ca, "potential_ability": mini(ca + 10, 99), "age": 25}))
		payload["players_by_club"][id] = squad
		payload["coaches_by_club"][id] = coach.duplicate(true)
		payload["coaches_by_club"][id]["id"] = id
		payload["coaches_by_club"][id]["club_id"] = id
	payload["next_player_id"] = builder._id_state["next_id"]
	payload["next_coach_id"] = 9
	payload["season_day"] = 1
	builder.free()
	return payload

func _format(fixture: Dictionary, format: String) -> Dictionary:
	var result := fixture.duplicate(true)
	var unit: Dictionary = result["units"][0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	var repetitions := 4 if format == "four_rounds" else 1
	var generated := FixtureGenerator.build_regular_season(range(1, 9), 1, 8, repetitions, 0, rng)
	unit["rules"]["matches_vs_own"] = repetitions
	unit["matches"] = generated["matches"]
	unit["divisions"] = generated["divisions"]
	unit["playoff"] = {"enabled": format == "series_four_wins", "teams": 8,
		"format": PlayoffRules.FORMAT_BEST_OF, "series_wins": 4, "seeding": PlayoffRules.SEEDING_OVERALL,
		"third_place": false}
	return result

func _complete_season() -> bool:
	var days := 0
	while not GameSession.season_finished:
		if not _ok(GameSession.advance_day()):
			return false
		days += 1
		if days > 200:
			report["errors"].append("Season exceeded 200 days")
			_finish()
			return false
	return true

func _outcome() -> Dictionary:
	var unit: Dictionary = GameSession.units[0]
	var table: Array = PlayoffManager._sorted_division_rows(unit, -1, RankingCriteria.DEFAULT_ORDER)
	var regular_id := int(table[0]["club_id"])
	var champion := int(unit.get("playoff", {}).get("champion_id", 0))
	if champion == 0:
		champion = regular_id
	return {"champion": champion, "regular_champion": regular_id, "table": table.duplicate(true)}

func _club_snapshot(previous: Dictionary) -> Array:
	var rows: Array = []
	for id in range(1, 9):
		var squad: Array = GameSession.get_club_players(id)
		var ca := 0.0
		var retained := 0
		var counts := {}
		for player in squad:
			ca += int(player.get("current_ability", 0))
			retained += int(previous.get(id, {}).has(int(player["id"])))
			var pos := str(player["position"])
			counts[pos] = int(counts.get(pos, 0)) + 1
		var violations: Array = []
		for pos in PlayerTypes.SQUAD_SLOT_MIN:
			if int(counts.get(pos, 0)) < PlayerTypes.SQUAD_SLOT_MIN[pos] or int(counts.get(pos, 0)) > PlayerTypes.SQUAD_SLOT_MAX[pos]:
				violations.append(pos)
		rows.append({"id": id, "mean_squad_ca": ca / maxf(1.0, squad.size()),
			"reputation": GameSession._collect_session_clubs()[id].get("reputation", 0),
			"budget": GameSession.get_club_budget(id), "coach_id": GameSession.get_club_coach(id).get("id", 0),
			"size": squad.size(), "retained": retained, "positions_outside_limits": violations})
	return rows

func _summary(champions: Array) -> Dictionary:
	var titles := {}
	var repeats := 0
	var leaders := 0
	var longest := 0
	var streak := 0
	var previous := -1
	for id in champions:
		titles[str(id)] = int(titles.get(str(id), 0)) + 1
		leaders += int(int(id) <= 2)
		if id == previous:
			repeats += 1
			streak += 1
		else:
			streak = 1
		longest = maxi(longest, streak)
		previous = id
	return {"runs": champions.size(), "titles": titles, "different_champions": titles.size(),
		"consecutive_repeats": repeats, "longest_streak": longest, "initial_leaders_titles": leaders}

func _agreement(a: Array, b: Array) -> int:
	var result := 0
	for i in a.size():
		result += int(a[i] == b[i])
	return result

func _ok(result: Dictionary) -> bool:
	if result.get("success", false):
		return true
	report["errors"].append(str(result.get("error", "Unknown error")))
	_finish()
	return false

func _finish() -> void:
	var position_records := 0
	for run in report["dynamic"]:
		for season in run["seasons"]:
			for club in season["clubs_before_matches"]:
				position_records += int(not club["positions_outside_limits"].is_empty())
	report["position_violation_records"] = position_records
	report["status"] = "completed_with_squad_violations" if position_records > 0 else "diagnostic_completed"
	if not report["errors"].is_empty():
		report["status"] = "failed"
	report["elapsed_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	report["scope"] = "Synthetic 8-club world; frozen independent runs are not career seasons; dynamic runs continue despite recorded position violations; equal facilities, flat prizes, equal initial budgets and coaches; initial first-team cohort age 25; averages describe all 25 players, not starting XI"
	var path := "res://tests/performance/results/title-stability.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write diagnostic report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TITLE END errors=", report["errors"], " seconds=", report["elapsed_seconds"], " report=", path)
	get_tree().quit(0 if report["errors"].is_empty() else 1)
