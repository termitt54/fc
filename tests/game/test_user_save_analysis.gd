extends Node
## Inspect a copied save only; never advances a day or writes a slot.
const HISTORY := preload("res://game/history_store.gd")

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	if args.size() != 1:
		get_tree().quit(2)
		return
	var snapshot := args[0].replace("\\", "/").simplify_path()
	if not snapshot.begins_with(root + "/user-") or not snapshot.ends_with("-snapshot"):
		get_tree().quit(2)
		return
	SaveStore.database_path_override = snapshot.path_join("games.db")
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	assert(WorldDatabase.initialize())
	var store := SaveStore.new()
	var started := Time.get_ticks_usec()
	var loaded := store.load_slot("autosave")
	assert(loaded["success"])
	var load_ms := (Time.get_ticks_usec() - started) / 1000.0
	var payload: Dictionary = loaded["data"]
	assert(GameSession.apply_save_payload(payload.duplicate(true))["success"])
	var archived: Array = []
	var head := int(payload.get("history_head", 0))
	assert(store._open())
	assert(store._db.query_with_bindings(HISTORY.ANCESTORS + "SELECT body FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry);", [head, head]))
	for row in store._db.query_result:
		archived.append(bytes_to_var(row["body"]))
	store._close()
	var result := {"load_ms": load_ms, "profile": GameSession.get_player_profile(10098), "logos": [], "national_rosters": []}
	for unit in GameSession.units:
		for history in unit.get("winners", []):
			for row in history.get("regular", []) + history.get("playoff", []):
				var cid := int(row.get("club_id", 0))
				var club := GameSession.get_club_identity(cid)
				result["logos"].append({"club_id": cid, "name": row.get("club_name", ""), "local": unit.get("clubs_by_id", {}).has(cid), "path": club.get("logo_path", "")})
	for country_id in GameSession.national_teams:
		var team: Dictionary = GameSession.national_teams[country_id]
		var players := NationalTeams.roster(GameSession, NationalTeams.TEAM_ID_BASE + int(country_id))
		var ratings: Array = []
		for player in players:
			ratings.append(int(player.get("current_ability", 0)))
		ratings.sort()
		ratings.reverse()
		result["national_rosters"].append({"country_id": country_id, "country": team.get("country", {}), "registered_season": team.get("registered_season", 0), "ca": ratings, "coach": team.get("coach", {})})
	var national_editions: Array = []
	for unit in payload.get("units", []):
		if not bool(unit.get("national", false)):
			continue
		for winner in unit.get("winners", []):
			var edition := store.tournament_season(head, int(unit["id"]), int(winner["season"]))
			assert(edition["success"])
			if not (edition["data"] as Dictionary).is_empty():
				national_editions.append(edition["data"])
	for item in [["payload.json", payload], ["archive.json", archived], ["inspection.json", result], ["national_editions.json", national_editions]]:
		var file := FileAccess.open(snapshot.path_join(item[0]), FileAccess.WRITE)
		assert(file != null)
		file.store_string(JSON.stringify(item[1]))
		file.close()
	print("SAVE INSPECTION season=", GameSession.season_number, " archive=", archived.size(), " profile10098=", result["profile"].get("name", "MISSING"), " load_ms=", load_ms)
	get_tree().quit()
