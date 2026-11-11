extends Node
const Dialog = preload("res://scenes/game/club_transfers_dialog.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	GameSession.clear()
	GameSession.season_number = 12
	var names := ["Максим Баранов", "Diego Santos", "Антон Крылов", "Lucas Moreira", "Andreas Jensen", "Илья Волков", "Oliver Berg", "Денис Соколов"]
	for i in 128:
		GameSession.transfer_log.append({"club_id": 1, "club_name": "CSKA Moscow",
			"other_club": ["Barcelona", "Свободный агент", "Valencia", "Bayern Munich"][i % 4],
			"season": 12 - i / 16, "day": -5 + i % 5, "player_id": i + 1,
			"player_name": names[i % names.size()], "position": ["GK", "CB", "CM", "ST"][i % 4],
			"direction": ["in", "out", "in", "bid"][i % 4],
			"fee": [2750000, 12450000, 0, 6000000][i % 4] + (0 if i % 4 == 2 else i * 10000)})
	var dialog := preload("res://ui/components/we_modal.tscn").instantiate()
	dialog.set_script(Dialog)
	add_child(dialog)
	dialog.show_club(1, "CSKA Moscow")
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := OS.get_cmdline_user_args()[0]
	assert(get_viewport().get_texture().get_image().save_png(output) == OK)
	print("Club transfers preview saved: ", output)
	get_tree().quit()
