extends Node

var failures: Array = []
var summaries: Array = []
var started := 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	if args.size()<4:
		push_error("Expected snapshot directory, settings JSON, season count and output JSON")
		get_tree().quit(1)
		return
	var snapshot := args[0].replace("\\", "/")
	assert(snapshot.contains("/.benchmark-runtime/user-") and snapshot.ends_with("-snapshot"))
	if not FileAccess.file_exists(snapshot.path_join("world.db")) or not FileAccess.file_exists(args[1]):
		push_error("Prepare the isolated world.db snapshot and match settings before running")
		get_tree().quit(1)
		return
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	SaveStore.database_path_override = snapshot.path_join("football-acceptance-games.db")
	assert(WorldDatabase.initialize())
	YouthGenerationConfig.reset_birth_to_defaults(false)
	MatchSimulationConfig.apply_values(JSON.parse_string(FileAccess.get_file_as_string(args[1])).values,false)
	var seasons := int(args[2]) if args.size()>2 else 10
	var built := GameSession.start_new_game(int(args[4]) if args.size()>4 else 886600)
	if not built.success:
		push_error("New world failed: %s" % str(built))
		get_tree().quit(1)
		return
	started = Time.get_ticks_msec()
	while GameSession.season_number <= seasons:
		if GameSession.season_day == GameSession.FIRST_MATCH_DAY:
			validate_squads()
			if not failures.is_empty():
				break
		if GameSession.season_finished:
			collect()
			if GameSession.season_number == seasons:
				break
			var next := GameSession.start_new_season()
			if not next.success:
				failures.append(next)
				break
		else:
			var result := GameSession.advance_day()
			if not result.success:
				failures.append(result)
				break
		if GameSession.season_day % 20 == 0:
			print("FOOTBALL WORLD season=",GameSession.season_number," day=",GameSession.season_day," elapsed_s=",(Time.get_ticks_msec()-started)/1000.0)
		await get_tree().process_frame
	var file := FileAccess.open(args[3] if args.size()>3 else snapshot.path_join("football-world-acceptance.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"seasons":summaries,"elapsed_s":(Time.get_ticks_msec()-started)/1000.0},"\t"))
	print("FOOTBALL WORLD END seasons=",summaries.size()," failures=",failures)
	get_tree().quit(1 if not failures.is_empty() else 0)

func validate_squads() -> void:
	var clubs := GameSession._collect_session_clubs()
	for cid in clubs:
		var squad := GameSession.get_club_players(int(cid))
		var cap := TransferMarket.foreign_limit_for_club(GameSession,int(cid))
		if not PlayerTypes.is_squad_shape_legal(squad) or (cap>=0 and TransferMarket.foreign_count(squad,clubs[cid])>cap):
			var detail := {"season":GameSession.season_number,"club":clubs[cid].name,"size":squad.size(),"positions":PlayerTypes.count_squad_positions(squad),"foreigners":TransferMarket.foreign_count(squad,clubs[cid]),"cap":cap,"nation":clubs[cid].country_id,"reserves":[],"academy":[],"domestic_free":[]}
			for pool_name in ["reserves","academy","domestic_free"]:
				var pool: Array = GameSession.get_club_reserve_players(int(cid)) if pool_name=="reserves" else GameSession.get_club_youth_players(int(cid)) if pool_name=="academy" else GameSession.free_agents
				for player in pool:
					if pool_name=="domestic_free" and int(player.get("nationality_country_id",0))!=int(clubs[cid].country_id):
						continue
					detail[pool_name].append({"id":player.id,"pos":player.position,"age":player.age,"ca":player.current_ability,"nation":player.nationality_country_id})
			failures.append(detail)

func collect() -> void:
	var summary := {"season":GameSession.season_number,"units":[],"countries":{},"player_count":0,"free_agents":GameSession.free_agents.size()}
	for unit in GameSession.units:
		var row := {"unit":unit.id,"national":NationalTeams.is_unit(unit),"matches":0,"goals":0,"margin6":0,"eight_plus":0,"close_matches":0,"close_margin6":0,"big_favourite_matches":0,"big_favourite_losses":0,"big_favourite_margin6_losses":0,"standings":unit.standings}
		for match_row in unit.matches:
			if not bool(match_row.get("played",false)) or match_row.get("stage","")!="REGULAR":
				continue
			var h := int(match_row.home_goals)
			var a := int(match_row.away_goals)
			row.matches += 1
			row.goals += h+a
			row.margin6 += int(absi(h-a)>=6)
			row.eight_plus += int(maxi(h,a)>=8)
			var report: Dictionary = match_row.get("report",{})
			var gap := float(report.get("home",{}).get("starting_ability",0.0))-float(report.get("away",{}).get("starting_ability",0.0))
			if absf(gap)<4.0:
				row.close_matches += 1
				row.close_margin6 += int(absi(h-a)>=6)
			if absf(gap)>=10.0:
				var margin := h-a if gap>0 else a-h
				row.big_favourite_matches += 1
				row.big_favourite_losses += int(margin<0)
				row.big_favourite_margin6_losses += int(margin<=-6)
		summary.units.append(row)
	for pool in GameSession.players_by_club.values()+GameSession.youth_players_by_club.values()+GameSession.reserve_players_by_club.values()+[GameSession.free_agents]:
		for player in pool:
			var nation := str(int(player.get("nationality_country_id",0)))
			if not summary.countries.has(nation):
				summary.countries[nation] = {"count":0,"ca":0,"pa":0,"prime_count":0,"prime_ca":0,"ca80":0,"ca90":0,"pa100":0}
			var country: Dictionary = summary.countries[nation]
			country.count += 1
			country.ca += int(player.current_ability)
			country.pa += int(player.potential_ability)
			country.ca80 += int(player.current_ability>=80)
			country.ca90 += int(player.current_ability>=90)
			country.pa100 += int(player.potential_ability==100)
			if int(player.age)>=22 and int(player.age)<=29:
				country.prime_count += 1
				country.prime_ca += int(player.current_ability)
			summary.player_count += 1
	summaries.append(summary)
	print("FOOTBALL WORLD COMPLETE ",GameSession.season_number," players=",summary.player_count," elapsed_s=",(Time.get_ticks_msec()-started)/1000.0)
