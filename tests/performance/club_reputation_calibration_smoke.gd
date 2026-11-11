extends Node
## Mutates only a dedicated disposable database copy, never the audit source.

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	var snapshot := root.path_join("user-club-reputation-calibration-snapshot")
	assert(FileAccess.file_exists(snapshot.path_join("games.db")))
	SaveStore.database_path_override = snapshot.path_join("games.db")
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	assert(WorldDatabase.initialize())
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded["success"])
	assert(GameSession.apply_save_payload(loaded["data"].duplicate(true))["success"])
	var expected := {}
	var before := {}
	var champions: Array = []
	for unit in GameSession.units:
		if bool(unit.get("national", false)):
			continue
		for piece in SeasonReputation._club_parts(unit, GameSession.season_number):
			var id := int(piece["club_id"])
			var current := int(unit["clubs_by_id"][id]["reputation"])
			before[id] = current
			expected[id] = clampi(current + SeasonReputation.combine_club(current, [piece]), 0, 1000)
		champions.append(int(unit.get("playoff", {}).get("champion_id", 0)))
	var started := Time.get_ticks_msec()
	assert(GameSession.start_new_season()["success"])
	assert(GameSession.season_number == 30)
	var actual := _club_reputations()
	assert(actual == expected)
	for id in actual:
		assert(absi(int(actual[id]) - int(before[id])) <= SeasonReputation.CLUB_CAP)
	for id in champions:
		assert(int(actual[id]) >= int(before[id]))
	assert(GameSession.save_game("reputation_calibration")["success"])
	assert(GameSession.load_game("reputation_calibration")["success"])
	assert(_club_reputations() == expected)
	var file := FileAccess.open(snapshot.path_join("smoke.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"season": GameSession.season_number, "clubs": actual.size(), "all_values_match_plan": true, "champions_nonnegative": true, "save_load_equal": true, "elapsed_seconds": float(Time.get_ticks_msec() - started) / 1000.0}))
	file.close()
	print("CLUB REPUTATION SMOKE passed: clubs=", actual.size(), " season=", GameSession.season_number)
	get_tree().quit()


func _club_reputations() -> Dictionary:
	var result := {}
	for unit in GameSession.units:
		if bool(unit.get("national", false)):
			continue
		for id in unit["clubs_by_id"]:
			result[id] = int(unit["clubs_by_id"][id]["reputation"])
	return result
