extends Node
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	var folder := OS.get_cmdline_user_args()[0].replace("\\","/")
	assert(folder.contains("/.benchmark-runtime/user-") and folder.ends_with("-snapshot"))
	SaveStore.database_path_override=folder.path_join("games.db")
	WorldDatabase.db_dir=folder
	WorldDatabase.db_path=folder.path_join("world.db")
	assert(WorldDatabase.initialize())
	var config: Script=load("res://game/match_simulation_config.gd")
	config.config_path=folder.path_join("config/match_simulation.json")
	config.unload()
	YouthGenerationConfig.config_path=folder.path_join("config/youth_generation.json")
	YouthGenerationConfig.birth_config_path=folder.path_join("config/youth_talent_birth.json")
	YouthGenerationConfig.unload()
	var start := Time.get_ticks_usec()
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success)
	var result := {"load_ms":(Time.get_ticks_usec()-start)/1000.0,"days":[],"source_season":loaded.data.season_number,"source_day":loaded.data.season_day}
	start=Time.get_ticks_usec()
	assert(GameSession.apply_save_payload(loaded.data).success)
	result.apply_ms=(Time.get_ticks_usec()-start)/1000.0
	result.backend=NativeSimulation.backend()
	for i in 3:
		start=Time.get_ticks_usec()
		var outcome := GameSession.advance_day()
		assert(outcome.success)
		result.days.append({"day":GameSession.season_day,"elapsed_ms":(Time.get_ticks_usec()-start)/1000.0,"profile":GameSession.last_day_profile.duplicate(true)})
	FileAccess.open(folder.path_join("runtime_probe.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("RUNTIME PROBE ",JSON.stringify(result))
	get_tree().quit()
