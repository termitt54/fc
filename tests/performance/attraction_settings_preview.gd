extends Node
const Config = preload("res://game/club_attraction_config.gd")

func _ready() -> void: call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	Config.config_path = "user://tests/attraction-preview.json"
	Config.apply_values(Config.defaults())
	var settings = load("res://scenes/settings/settings.tscn").instantiate()
	add_child(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings._tab_bar.select(2)
	var tab = settings.get_node("%ClubAttraction")
	var folder := OS.get_cmdline_user_args()[0]
	for weighted in [false, true]:
		tab._mode.is_on = weighted
		tab._mode.toggled.emit(weighted)
		for i in 6: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var name := "attraction-settings-weights.png" if weighted else "attraction-settings-bounded.png"
		assert(get_viewport().get_texture().get_image().save_png(folder.path_join(name)) == OK)
	print("Attraction settings screenshots saved")
	get_tree().quit()
