extends Node
func _ready() -> void:
	call_deferred("run")
func flatten(payload: Dictionary) -> Array:
	var players: Array = []
	for key in ["players_by_club","youth_players_by_club","reserve_players_by_club"]:
		for pool in payload.get(key,{}).values(): players.append_array(pool)
	players.append_array(payload.get("free_agents",[]))
	return players
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size()==2 and args[0].replace("\\","/").contains("/.benchmark-runtime/user-") and args[0].ends_with("-snapshot"))
	SaveStore.database_path_override = args[0].path_join("games.db")
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success)
	var before := {}
	for player in flatten(loaded.data):
		before[int(player.id)] = {"ca":int(player.current_ability),"pa":int(player.potential_ability),"name":str(player.name),"career":player.get("career_stats",[]).duplicate(true)}
	var started := Time.get_ticks_usec()
	assert(GameSession.apply_save_payload(loaded.data).success)
	var failures := []
	var max_delta := 0
	var changed := 0
	var players := flatten({"players_by_club":GameSession.players_by_club,"reserve_players_by_club":GameSession.reserve_players_by_club,"youth_players_by_club":GameSession.youth_players_by_club,"free_agents":GameSession.free_agents})
	for player in players:
		var prior: Dictionary = before[int(player.id)]
		var delta := absi(int(player.current_ability)-int(prior.ca))
		max_delta = maxi(max_delta,delta)
		changed += int(delta>0)
		var n := 0
		for group in player.attributes.values(): n += group.size()
		if delta>1 or player.current_ability>player.potential_ability or n!=(16 if player.position=="GK" else 11) or player.characters.size()!=1 or player.has("personality") or player.potential_ability!=prior.pa or player.name!=prior.name or player.get("career_stats",[])!=prior.career:
			failures.append(player.id)
	var report := {"players":players.size(),"source_players":before.size(),"max_ca_delta":max_delta,"players_with_ca_rounding":changed,"failures":failures,"apply_ms":(Time.get_ticks_usec()-started)/1000.0}
	var file := FileAccess.open(args[1],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("MIGRATION ",JSON.stringify(report))
	get_tree().quit(int(not failures.is_empty() or players.size()!=before.size()))
