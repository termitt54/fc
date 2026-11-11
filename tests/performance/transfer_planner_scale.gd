extends Node
const Config = preload("res://game/club_attraction_config.gd")
func _ready() -> void:call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var args := OS.get_cmdline_user_args();var folder := args[0]
	SaveStore.database_path_override=folder.path_join("games.db")
	var loaded := SaveStore.new().load_slot("autosave");assert(loaded.success)
	var original: Dictionary=loaded.data
	var payload := {"version":15,"season_number":138,"season_day":-5,"history_head":0,"units":[],"players_by_club":{},"youth_players_by_club":{},"reserve_players_by_club":{},"coaches_by_club":{},"club_budgets":{},"free_agents":[],"transfer_log":[],"wages_paid_for_season":137}
	for copy in 4:
		var offset := copy*10000;var poffset := copy*1000000
		for unit in original.units:
			if bool(unit.get("national",false)):continue
			var clubs := {}
			for raw_id in unit.clubs_by_id:
				var cid := int(raw_id);var id := cid+offset
				var club: Dictionary=unit.clubs_by_id[raw_id].duplicate(true);club.id=id;club.erase("transfer_plan");clubs[id]=club
				payload.club_budgets[id]=original.club_budgets[cid]
				var coach: Dictionary=original.coaches_by_club[cid].duplicate(true);coach.id=int(coach.id)+offset;coach.club_id=id;payload.coaches_by_club[id]=coach
				for pool in ["players_by_club","youth_players_by_club","reserve_players_by_club"]:
					payload[pool][id]=[]
					for source in original[pool].get(cid,[]):payload[pool][id].append(player_copy(source,id,poffset))
			payload.units.append({"id":int(unit.id)+offset,"competition_type":unit.competition_type,"rules":unit.rules.duplicate(true),"clubs_by_id":clubs,"matches":[],"standings":[],"divisions":[],"playoff":{"enabled":false}})
		for source in original.free_agents:payload.free_agents.append(player_copy(source,0,poffset))
	Config.config_path=folder.path_join("config/club_attraction.json");Config.unload()
	assert(GameSession.apply_save_payload(payload).success)
	GameSession._rng.seed=121126;GameSession._process_contract_renewals()
	var result := {"clubs":GameSession.players_by_club.size(),"players":GameSession._count_saved_players(),"days":[],"illegal":0}
	for day in range(-5,0):
		GameSession.season_day=day
		var start := Time.get_ticks_usec();var outcome := TransferMarket.run_day(GameSession,GameSession._rng)
		var row := {"day":day,"ms":(Time.get_ticks_usec()-start)/1000.0,"profile":outcome.profile}
		result.days.append(row);print("SCALE DAY ",day," ",row.ms)
	for squad in GameSession.players_by_club.values():result.illegal+=int(not PlayerTypes.is_squad_shape_legal(squad))
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("SCALE COMPLETE illegal=",result.illegal)
	get_tree().quit(0 if result.illegal==0 else 1)
func player_copy(source: Dictionary,club_id: int,offset: int) -> Dictionary:
	var result := {}
	for key in ["id","name","position","age","nationality_country_id","attributes","current_ability","potential_ability","reputation","characters","contract_years","contract_status","wage","value","value_pricing_version","player_model_version","joined_season","is_youth","is_reserve","retirement_age","development_factor"]:
		if source.has(key):result[key]=source[key].duplicate(true) if source[key] is Dictionary or source[key] is Array else source[key]
	result.id=int(result.id)+offset;result.club_id=club_id
	return result
