extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var snapshot := OS.get_cmdline_user_args()[0]
	assert(snapshot.replace("\\", "/").contains("/.benchmark-runtime/user-"))
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	assert(WorldDatabase.initialize())
	YouthGenerationConfig.reset_birth_to_defaults(false)
	var args := OS.get_cmdline_user_args()
	assert(GameSession.start_new_game(int(args[1]) if args.size() > 1 else 220016).success)
	while GameSession.season_day < 1:
		var counts := {}
		for squad in GameSession.players_by_club.values():
			counts[squad.size()] = int(counts.get(squad.size(), 0)) + 1
		print("OPENING ", GameSession.season_day, " counts=", counts, " free=", GameSession.free_agents.size())
		if args.has("sliced"):
			assert((await GameSession.advance_day_async(8)).success)
		else:
			assert(GameSession.advance_day().success)
	var rows: Array = []
	for cid in GameSession.players_by_club:
		var club := GameSession.get_club_identity(int(cid))
		var squad := GameSession.get_club_players(int(cid))
		var positions := {}
		for player in squad:
			positions[player.position] = int(positions.get(player.position, 0)) + 1
		var cap := TransferMarket.foreign_limit_for_club(GameSession,int(cid))
		var foreigners := TransferMarket.foreign_count(squad,club)
		rows.append({"id":cid,"name":club.get("name"),"size":squad.size(),"positions":positions,"foreigners":foreigners,"cap":cap,"legal":PlayerTypes.is_squad_shape_legal(squad) and (cap<0 or foreigners<=cap)})
		if squad.size() < 25:
			var needed := TransferMarket.next_needed_position(squad)
			var context := TransferMarket._offer_context(squad,0,PlayerOffer.world_top_reputation(GameSession._collect_session_clubs()))
			var reasons := {}
			for player in GameSession.free_agents:
				if player.position != needed:
					continue
				context.offer_wage = PlayerMarket.wage_for_move(player,club,true)
				var reason := str(PlayerOffer.evaluate(player,club,GameSession.get_club_coach(int(cid)),context).reason)
				reasons[reason] = int(reasons.get(reason,0))+1
			print("STUCK ",club.get("name")," rep=",club.get("reputation")," needed=",needed," quality=",context.squad_ability," limit=",TransferMarket.foreign_limit_for_club(GameSession,int(cid))," foreign=",TransferMarket.foreign_count(squad,club)," reasons=",reasons)
	var file := FileAccess.open(snapshot.path_join("opening-market-audit.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	print("OPENING FINAL ", JSON.stringify(rows.filter(func(row): return int(row.size) < 25)))
	for player in GameSession.free_agents:
		print("LEFTOVER ",player.get("name")," pos=",player.position," nation=",player.nationality_country_id," ca=",player.current_ability," rep=",player.reputation)
	get_tree().quit(1 if rows.any(func(row): return not bool(row.legal)) else 0)
