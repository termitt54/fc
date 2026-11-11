extends Node
## Mature copied world: finish partial season 104, then fully simulate 105–107.
var counts: Dictionary = {}
var seen: Dictionary = {}
var errors: Array = []

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	var folder := root.path_join("user-stability-world-snapshot")
	SaveStore.database_path_override = folder.path_join("games.db")
	WorldDatabase.db_dir = folder
	WorldDatabase.db_path = folder.path_join("world.db")
	assert(WorldDatabase.initialize())
	MatchSimulationConfig.config_path = "user://tests/stability_world_match.json"
	MatchSimulationConfig.apply_values(JSON.parse_string(FileAccess.get_file_as_string("res://tests/performance/user_match_settings.json"))["values"],false)
	YouthGenerationConfig.config_path = "res://tests/performance/user_youth_generation.json"
	YouthGenerationConfig.birth_config_path = "res://tests/performance/user_youth_talent_birth.json"
	YouthGenerationConfig.unload()
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded["success"] and int(loaded["data"]["season_number"])==104)
	assert(GameSession.apply_save_payload(loaded["data"])["success"])
	var started := Time.get_ticks_msec()
	var guard := 0
	while GameSession.season_number<108 and Time.get_ticks_msec()-started<900000:
		var advanced: Dictionary
		if GameSession.season_finished:
			print("WORLD completed season ",GameSession.season_number," elapsed_s=",(Time.get_ticks_msec()-started)/1000.0)
			if GameSession.season_number==107:
				break
			advanced = GameSession.start_new_season()
			seen.clear()
		else:
			advanced = GameSession.advance_day()
			_collect()
			# Contract exits intentionally leave vacancies before the market.
			if GameSession.season_day==GameSession.FIRST_MATCH_DAY:
				_validate_squads()
		if not advanced.get("success",false):
			errors.append(advanced)
			break
		guard += 1
		if guard%30==0:
			print("WORLD season=",GameSession.season_number," day=",GameSession.season_day," elapsed_s=",(Time.get_ticks_msec()-started)/1000.0)
		await get_tree().process_frame
	if GameSession.season_number!=107 or not GameSession.season_finished:
		errors.append("Did not finish target seasons")
	var result := {"errors":errors,"counts":counts,"season":GameSession.season_number,"steps":guard,
		"elapsed_s":(Time.get_ticks_msec()-started)/1000.0,"scope":"Partial 104 excluded. Complete seasons 105–107 in a scratch copy with user settings; no original slot written."}
	var file := FileAccess.open("res://tests/performance/results/match-stability-world.json",FileAccess.WRITE)
	assert(file!=null)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("WORLD RESULT ",JSON.stringify(result))
	get_tree().quit(0 if errors.is_empty() else 1)

func _collect() -> void:
	if GameSession.season_number<105:
		return
	for unit in GameSession.units:
		for row in unit.get("matches",[]):
			var key := "%d:%d:%d" % [GameSession.season_number,int(unit["id"]),int(row.get("id",0))]
			if not row.get("played",false) or seen.has(key):
				continue
			seen[key] = true
			var bucket := "%d_%s" % [GameSession.season_number,"national" if NationalTeams.is_unit(unit) else "club"]
			if not counts.has(bucket):
				counts[bucket] = {"matches":0,"goals":0,"margin4":0,"eight_plus":0,"close_matches":0,"close_margin4":0}
			var summary: Dictionary = counts[bucket]
			var hg := int(row["home_goals"])
			var ag := int(row["away_goals"])
			summary["matches"] += 1
			summary["goals"] += hg+ag
			summary["margin4"] += int(absi(hg-ag)>=4)
			summary["eight_plus"] += int(maxi(hg,ag)>=8)
			var report: Dictionary = row.get("report",{})
			var home: Dictionary = report.get("home",{})
			var away: Dictionary = report.get("away",{})
			if absf(float(home.get("starting_ability",0))-float(away.get("starting_ability",0)))<=3.0:
				summary["close_matches"] += 1
				summary["close_margin4"] += int(absi(hg-ag)>=4)

func _validate_squads() -> void:
	var seen_players := {}
	for squads in [GameSession.players_by_club,GameSession.youth_players_by_club,GameSession.reserve_players_by_club]:
		for squad in squads.values():
			for player in squad:
				var id := int(player["id"])
				if seen_players.has(id):
					errors.append("Duplicate player %d" % id)
				seen_players[id] = true
	for club_id in GameSession.players_by_club:
		var squad: Array = GameSession.players_by_club[club_id]
		var positions := {}
		for player in squad:
			positions[player["position"]] = int(positions.get(player["position"],0))+1
		for position in PlayerTypes.SQUAD_SLOT_MIN:
			if int(positions.get(position,0))<int(PlayerTypes.SQUAD_SLOT_MIN[position]):
				errors.append({"kind":"position_quota","season":GameSession.season_number,"club_id":club_id,
					"position":position,"count":int(positions.get(position,0)),"minimum":int(PlayerTypes.SQUAD_SLOT_MIN[position]),"squad_size":squad.size()})
