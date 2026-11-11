extends Node
## Timings and individual archive reads on a scratch copy only.
const HISTORY := preload("res://game/history_store.gd")

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	var folder := root.path_join("user-longrun-snapshot")
	SaveStore.database_path_override = folder.path_join("games.db")
	WorldDatabase.db_dir = folder
	WorldDatabase.db_path = folder.path_join("world.db")
	assert(WorldDatabase.initialize())
	var store := SaveStore.new()
	var started := Time.get_ticks_usec()
	var loaded := store.load_slot("autosave")
	assert(loaded["success"])
	var result := {"load_ms": (Time.get_ticks_usec() - started) / 1000.0, "profiles": [], "days": []}
	started = Time.get_ticks_usec()
	assert(GameSession.apply_save_payload(loaded["data"])["success"])
	result["apply_ms"] = (Time.get_ticks_usec() - started) / 1000.0
	var head := GameSession.history_head
	assert(store._open())
	assert(store._db.query_with_bindings(HISTORY.ANCESTORS + "SELECT player_id,name,retired_season,matches,goals FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry) AND retired_season IN (1,20,50,100) ORDER BY retired_season,player_id;", [head,head]))
	var examples: Dictionary = {}
	for row in store._db.query_result:
		if not examples.has(row["retired_season"]):
			examples[row["retired_season"]] = row.duplicate(true)
	store._close()
	for example in examples.values():
		started = Time.get_ticks_usec()
		var profile := GameSession.get_player_profile(int(example["player_id"]))
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		var totals := PlayerStats.career_totals(profile)
		result["profiles"].append({"id": example["player_id"], "name": profile.get("name", ""), "retired_season": profile.get("retired_season",0),
			"lookup_ms": elapsed, "attributes_present": not profile.get("attributes",{}).is_empty(),
			"matches": totals.get("matches",0), "goals": totals.get("goals",0),
			"matches_consistent": int(totals.get("matches",0)) == int(example["matches"]),
			"goals_consistent": int(totals.get("goals",0)) == int(example["goals"]),
			"career_rows": PlayerStats.timeline(profile).size(), "development_rows": profile.get("development_history",[]).size()})
	for n in 5:
		var day := GameSession.season_day
		started = Time.get_ticks_usec()
		var advanced := GameSession.advance_day()
		result["days"].append({"day":day, "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0,
			"success": advanced.get("success",false), "profile": GameSession.last_day_profile.duplicate(true)})
	var file := FileAccess.open(folder.path_join("health.json"), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("LONG SAVE HEALTH ", JSON.stringify(result))
	get_tree().quit()
