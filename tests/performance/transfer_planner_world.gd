extends Node
const Config = preload("res://game/match_simulation_config.gd")
const Attraction = preload("res://game/club_attraction_config.gd")
func _ready() -> void:call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var args := OS.get_cmdline_user_args();var folder := args[0]
	SaveStore.database_path_override="user://tests/transfer-planner-benchmark.db"
	WorldDatabase.db_dir=folder;WorldDatabase.db_path=folder.path_join("world.db");assert(WorldDatabase.initialize())
	Config.config_path=folder.path_join("config/match_simulation.json");Config.unload()
	Attraction.config_path=folder.path_join("config/club_attraction.json");Attraction.unload()
	YouthGenerationConfig.config_path=folder.path_join("config/youth_generation.json")
	YouthGenerationConfig.birth_config_path=folder.path_join("config/youth_talent_birth.json");YouthGenerationConfig.unload()
	var seed := SaveStore.new().load_slot("closed_seed");assert(seed.success and GameSession.apply_save_payload(seed.data).success)
	var result := {"seasons":[],"illegal_squads":0,"foreign_violations":0,"original_source_modified":false}
	for cycle in 3:
		var start := Time.get_ticks_usec();var from_index := GameSession.transfer_log.size()
		assert(GameSession.start_new_season().success)
		var season := {"season":GameSession.season_number,"upgrades":0,"core_upgrades":0,"paid":0,"free":0}
		while not GameSession.season_finished:
			assert(GameSession.advance_day().success)
			if GameSession.season_day==1:
				for club in GameSession._collect_session_clubs().values():
					var plan: Dictionary=club.get("transfer_plan",{})
					if int(plan.get("season",0))==GameSession.season_number:
						season.upgrades+=int(plan.get("purchases",0));season.core_upgrades+=int(plan.get("core_upgrades",0))
		for row in GameSession.transfer_log.slice(from_index):
			if row.direction=="in":season["paid" if int(row.fee)>0 else "free"]+=1
		for id in GameSession.players_by_club:
			var sq: Array=GameSession.get_club_players(int(id))
			result.illegal_squads+=int(not PlayerTypes.is_squad_shape_legal(sq))
			var limit := TransferMarket.foreign_limit_for_club(GameSession,int(id))
			result.foreign_violations+=int(limit>=0 and TransferMarket.foreign_count(sq,GameSession.get_club_identity(int(id)))>limit)
		season.elapsed_ms=(Time.get_ticks_usec()-start)/1000.0
		season.paid_percent=100.0*season.paid/maxf(1,season.paid+season.free)
		result.seasons.append(season)
		FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
		print("WORLD SEASON ",JSON.stringify(season)," illegal=",result.illegal_squads," foreign=",result.foreign_violations)
	get_tree().quit(0 if result.illegal_squads==0 and result.foreign_violations==0 else 1)
