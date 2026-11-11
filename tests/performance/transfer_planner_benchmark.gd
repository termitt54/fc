extends Node
const Config = preload("res://game/match_simulation_config.gd")
const Attraction = preload("res://game/club_attraction_config.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	var folder := args[0]
	SaveStore.database_path_override=folder.path_join("games.db")
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success)
	var seed: Dictionary=loaded.data
	SaveStore.database_path_override="user://tests/transfer-planner-benchmark.db"
	Config.config_path=folder.path_join("config/match_simulation.json");Config.unload()
	Attraction.config_path=folder.path_join("config/club_attraction.json");Attraction.unload()
	YouthGenerationConfig.config_path=folder.path_join("config/youth_generation.json")
	YouthGenerationConfig.birth_config_path=folder.path_join("config/youth_talent_birth.json");YouthGenerationConfig.unload()
	var result := {"backend":NativeSimulation.backend(),"ordinary":[],"market_windows":[]}
	for repeat in (1 if args.size()>2 and args[2]=="quick" else 3):
		var copy := seed.duplicate(true);copy.history_head=0
		assert(GameSession.apply_save_payload(copy).success)
		var start := Time.get_ticks_usec()
		assert(GameSession.advance_day().success)
		result.ordinary.append({"ms":(Time.get_ticks_usec()-start)/1000.0,"profile":GameSession.last_day_profile.duplicate(true)})
		assert(GameSession.apply_save_payload(copy).success)
		GameSession.season_number+=1;GameSession.season_day=-5
		GameSession._rng.seed=121126
		GameSession._process_contract_renewals()
		var from_index := GameSession.transfer_log.size()
		var window := {"days":[],"paid":0,"free":0,"illegal":0}
		start=Time.get_ticks_usec()
		for day in range(-5,0):
			GameSession.season_day=day
			var day_start := Time.get_ticks_usec()
			var outcome := TransferMarket.run_day(GameSession,GameSession._rng)
			window.days.append({"day":day,"ms":(Time.get_ticks_usec()-day_start)/1000.0,"result":outcome})
		window.ms=(Time.get_ticks_usec()-start)/1000.0
		for row in GameSession.transfer_log.slice(from_index):
			if row.direction=="in":window["paid" if int(row.fee)>0 else "free"]+=1
		for squad in GameSession.players_by_club.values():window.illegal+=int(not PlayerTypes.is_squad_shape_legal(squad))
		result.market_windows.append(window)
		print("BENCH WINDOW ",repeat," ",window.ms," ms, paid=",window.paid," free=",window.free," illegal=",window.illegal)
	if args.size()>2 and args[2]=="prepare_closed":
		var copy := seed.duplicate(true);copy.history_head=0
		assert(GameSession.apply_save_payload(copy).success)
		while not GameSession.season_finished:
			assert(GameSession.advance_day().success)
		assert(GameSession.save_game("closed_seed").success)
		var start := Time.get_ticks_usec()
		assert(GameSession.start_new_season().success)
		result.new_season={"ms":(Time.get_ticks_usec()-start)/1000.0,"profile":GameSession.last_new_season_profile.duplicate(true)}
	elif args.size()>2 and args[2]=="closed":
		var closed := SaveStore.new().load_slot("closed_seed")
		assert(closed.success and GameSession.apply_save_payload(closed.data).success)
		var start := Time.get_ticks_usec()
		assert(GameSession.start_new_season().success)
		result.new_season={"ms":(Time.get_ticks_usec()-start)/1000.0,"profile":GameSession.last_new_season_profile.duplicate(true)}
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("BENCH COMPLETE")
	get_tree().quit()
