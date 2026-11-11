extends Node
## Coach lifecycle only: no fixtures, player development or match simulation.
func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("run")

func run() -> void:
	GameSession.clear()
	var clubs := {}
	var standings: Array = []
	for cid in range(1, 1001):
		clubs[cid] = {"id": cid, "name": "Club %d" % cid, "country_id": 1, "reputation": 700, "finance_level": 10}
		standings.append({"club_id": cid, "played": 20, "points": 30, "goal_diff": 0, "goals_for": 0})
		GameSession.coaches_by_club[cid] = {"id": cid, "club_id": cid, "name": "Coach %d" % cid,
			"age": 45, "current_ability": 70, "reputation": 600, "contract_years": 3, "wage": 10000,
			"attributes": {"tactics": 14, "development": 14}, "career": [{"club_id": cid, "club_name": clubs[cid]["name"], "season_from": 1, "season_to": 0}]}
		GameSession.club_budgets[cid] = 10000000
	GameSession.units = [{"id": 1, "name": "Synthetic", "clubs_by_id": clubs, "standings": standings, "rules": {}}]
	GameSession._next_coach_id = 1001
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var samples: Array = []
	var started := Time.get_ticks_msec()
	for season in range(1, 101):
		GameSession.season_number = season
		GameSession.season_day = 50
		var before := Time.get_ticks_usec()
		CoachMarket.close_season(GameSession, rng)
		assert(GameSession.coaches_by_club.size() == 1000)
		var ids := {}
		for coach in GameSession.coaches_by_club.values() + GameSession.coach_market["free"] + GameSession.coach_market["retired"]:
			assert(not ids.has(coach["id"]))
			ids[coach["id"]] = true
		samples.append({"season": season, "ms": float(Time.get_ticks_usec() - before) / 1000.0,
			"free": GameSession.coach_market["free"].size(), "retired": GameSession.coach_market["retired"].size(), "events": GameSession.coach_market["events"].size()})
		if season % 20 == 0:
			print("COACH BENCH ", JSON.stringify(samples[-1]))
		await get_tree().process_frame
	var file := FileAccess.open("res://tests/performance/results/coach-market-1000-100-seasons.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"status": "passed", "clubs": 1000, "seasons": 100,
		"elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0, "samples": samples,
		"scope": "Synthetic coach lifecycle only. Excludes player development, matches, UI rendering and database saving."}, "  "))
	file.close()
	print("COACH BENCH PASS")
	GameSession.clear()
	get_tree().quit()
