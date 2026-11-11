extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		get_tree().quit(2)
		return
	call_deferred("run")

func run() -> void:
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	assert(loaded.get("success", false))
	assert(GameSession.apply_save_payload(loaded["data"].duplicate(true))["success"])
	var initial := {}
	for cid in GameSession.coaches_by_club:
		initial[cid] = GameSession.coaches_by_club[cid]["id"]
	var started := Time.get_ticks_msec()
	var seasons: Array = []
	for cycle in 2:
		var days := 0
		while not GameSession.season_finished and days < 300:
			assert((await GameSession.advance_day_async(8))["success"])
			days += 1
		assert(GameSession.season_finished)
		assert(GameSession.start_new_season()["success"])
		var ids := {}
		for coach in GameSession.coaches_by_club.values() + GameSession.coach_market["free"] + GameSession.coach_market["retired"]:
			assert(not ids.has(coach["id"]))
			ids[coach["id"]] = true
		for cid in initial:
			assert(not GameSession.get_club_coach(cid).is_empty())
		seasons.append({"season": GameSession.season_number - 1, "days": days,
			"changed_from_initial": GameSession.coaches_by_club.keys().filter(func(cid: int) -> bool: return initial[cid] != GameSession.get_club_coach(cid)["id"]).size(),
			"events": GameSession.coach_market["events"].size(), "free": GameSession.coach_market["free"].size(), "retired": GameSession.coach_market["retired"].size()})
		print("COACH SAVE CYCLE ", JSON.stringify(seasons[-1]))
	var before := var_to_bytes(GameSession.coach_market)
	var before_rng := GameSession._rng.state
	assert(GameSession.save_game("zz_coach_smoke")["success"])
	GameSession.clear()
	assert(GameSession.load_game("zz_coach_smoke")["success"])
	assert(before == var_to_bytes(GameSession.coach_market))
	assert(before_rng == GameSession._rng.state)
	assert(GameSession.delete_save("zz_coach_smoke")["success"])
	var counts := {}
	for event in GameSession.coach_market["events"]:
		counts[event["reason"]] = int(counts.get(event["reason"], 0)) + 1
	var output := {"source_saved_at": loaded["data"]["saved_at"], "source_season": loaded["data"]["season_number"], "cycles": seasons,
		"event_counts": counts, "elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"save_roundtrip": true, "unique_coach_ids": true, "all_clubs_staffed": true,
		"scope": "Two seasons and interseasons on a copied save; no original slots modified; does not validate long-term competitive balance."}
	var file := FileAccess.open("res://tests/performance/results/coach-market-user-smoke.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "  "))
	file.close()
	print("COACH SAVE SMOKE PASS ", JSON.stringify(output))
	get_tree().quit()
