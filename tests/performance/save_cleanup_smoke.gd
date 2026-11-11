extends Node
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	SaveStore.database_path_override=args[0]
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success)
	assert(int(loaded.data.season_number)==137 and int(loaded.data.season_day)==25)
	var size := 0
	for squad in loaded.data.players_by_club.values():
		assert(squad.size()==20)
		size+=squad.size()
	assert(size==3280)
	assert(GameSession.apply_save_payload(loaded.data).success)
	var archive := CareerArchive.new()
	assert(archive.open_head(GameSession.history_head))
	assert(archive.count()==35360)
	var leaders := archive.top_scorers(10)
	assert(leaders.size()==10)
	for player in leaders:
		assert(int(player.matches)>0)
		assert(not GameSession.get_player_profile(int(player.player_id)).is_empty())
	archive.close()
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify({"success":true,"season":137,"day":25,"club_players":size,"retired_records":35360,"archived_leaders_profiles":10}))
	print("CLEANED SAVE LOAD OK: 35360 careers; all 164 main squads intact; archived scorers open")
	GameSession.clear()
	get_tree().quit()
