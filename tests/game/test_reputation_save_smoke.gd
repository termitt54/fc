extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		get_tree().quit(2)
		return
	call_deferred("run")

func run() -> void:
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	assert(loaded.get("success", false))
	assert(GameSession.apply_save_payload(loaded["data"].duplicate(true)).get("success", false))
	var before_clubs := {}
	var before_players := {}
	for unit in GameSession.units:
		for id in unit["clubs_by_id"]:
			before_clubs[id] = int(unit["clubs_by_id"][id]["reputation"])
	for club_id in GameSession.players_by_club:
		for player in GameSession.get_club_players(club_id):
			before_players[int(player["id"])] = int(player["reputation"])
	var started := Time.get_ticks_msec()
	assert(GameSession.start_new_season().get("success", false))
	var changes: Array = []
	for unit in GameSession.units:
		for id in unit["clubs_by_id"]:
			var club: Dictionary = unit["clubs_by_id"][id]
			changes.append({"name": club["name"], "before": before_clubs[id], "after": club["reputation"]})
	var largest_player_jump := 0
	for club_id in GameSession.players_by_club:
		for player in GameSession.get_club_players(club_id):
			var id := int(player["id"])
			if before_players.has(id):
				largest_player_jump = maxi(largest_player_jump, absi(int(player["reputation"]) - int(before_players[id])))
	assert(largest_player_jump <= PlayerMarket.REPUTATION_DRIFT_MAX)
	var days := 0
	while not GameSession.season_finished and days < 300:
		assert(GameSession.advance_day().get("success", false))
		days += 1
		if days % 20 == 0:
			await get_tree().process_frame
	assert(GameSession.season_finished)
	var result := {"source_saved_at": loaded["data"]["saved_at"], "completed_season": GameSession.season_number,
		"days": days, "elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0,
		"largest_existing_first_team_reputation_change": largest_player_jump, "closed_season_club_changes": changes,
		"scope": "Copied save; real interseason, transfer window and one completed season; no save slots written, archive writes only in copied diagnostic database; does not establish long-run competitive balance"}
	var file := FileAccess.open("res://tests/performance/results/reputation-save-smoke-20261011.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("SAVE SMOKE PASS season=", GameSession.season_number, " days=", days, " max player jump=", largest_player_jump)
	get_tree().quit()
