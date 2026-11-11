extends Node
## Visual QA uses only a frozen copy and never saves the loaded world.
func _ready() -> void: call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var folder := OS.get_cmdline_user_args()[0].replace("\\", "/")
	assert(folder.contains("/.benchmark-runtime/user-") and folder.ends_with("-snapshot"))
	SaveStore.database_path_override = folder.path_join("games.db")
	WorldDatabase.db_dir = folder
	WorldDatabase.db_path = folder.path_join("world.db")
	assert(WorldDatabase.initialize())
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success)
	assert(GameSession.apply_save_payload(loaded.data).success)
	# Resource paths are relative to userdata. Missing images in isolated userdata
	# should use placeholders, not try to access the user's live assets.
	for team in GameSession.national_teams.values(): team.country.flag_path = ""
	for unit in GameSession.units:
		for club in unit.get("clubs_by_id", {}).values():
			club["flag_path"] = ""
			club["logo_path"] = ""
	var screen = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.get_node("%NationalRatingLink").pressed.emit()
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_cmdline_user_args()[1]
	assert(get_viewport().get_texture().get_image().save_png(output) == OK)
	print("UI QA screenshot: ", output)
	screen._teams_view.set_national(true, true)
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(output.replace(".png", "-national.png")) == OK)
	screen._teams_view.set_national(true)
	screen._show_directory("teams")
	for i in 6: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(output.replace(".png", "-reputation.png")) == OK)
	get_tree().quit()
