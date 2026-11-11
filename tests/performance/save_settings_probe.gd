extends SceneTree
func _initialize() -> void:
	var folder := OS.get_cmdline_user_args()[0]
	var config: Script=load("res://game/match_simulation_config.gd")
	config.config_path=folder.path_join("config/match_simulation.json")
	config.unload()
	var result := {"version":config.CONFIG_VERSION,"fingerprint":config.fingerprint(),"values":config.snapshot(),"defaults":config.default_values()}
	FileAccess.open(folder.path_join("effective_settings.json"),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SETTINGS ",result.fingerprint)
	quit()
