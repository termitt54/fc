extends Node
const Attraction = preload("res://game/club_attraction_config.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var folder := OS.get_cmdline_user_args()[0]
	SaveStore.database_path_override=folder.path_join("games.db")
	Attraction.config_path=folder.path_join("config/club_attraction.json")
	Attraction.unload()
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success and GameSession.apply_save_payload(loaded.data).success)
	var clubs: Dictionary=GameSession._collect_session_clubs()
	var top := PlayerOffer.world_top_reputation(clubs)
	var rows := []
	for raw_id in clubs:
		var id := int(raw_id)
		var squad := GameSession.get_club_players(id).duplicate(true)
		var coach := GameSession.get_club_coach(id)
		var core: Dictionary=TransferMarket._squad_market_info(GameSession,id,squad).starters
		var players := []
		for player in squad:
			var key_player := core.has(int(player.id))
			players.append({"id":player.id,"key":key_player,"can_sell":TransferMarket._seller_can_spare(GameSession,id,squad,player),"renew_chance":ContractRenewal.stay_chance(player,clubs[id],coach,{"key_player":key_player,"world_top_reputation":top}),"renew_wage":ContractRenewal.renewal_wage(player,{"key_player":key_player}),"wage":int(player.get("wage",0)),"ca":int(player.current_ability),"age":int(player.age)})
		var rng := RandomNumberGenerator.new();rng.seed=111126+id
		for player in squad:
			player.condition=100;player.injury_rounds=0;player.suspension_matches=0
		var lineup := LineupSelector.build(squad,[],coach,{"style":CoachTypes.primary_style_of(coach),"formation":"3-2-2"},rng)
		var selected := []
		for entry in lineup.starters:selected.append(int(entry.player.id))
		var row := {"id":id,"name":clubs[id].name,"players":players,"fresh_selected":selected}
		if int(clubs[id].get("country_id",0))==18 or id==41:
			var real_squad := GameSession.get_club_players(id)
			var outgoing := TransferMarket._pick_outgoing(GameSession,id,real_squad,coach)
			row["ordinary_upgrade_quote"]=quote(clubs,id,coach,outgoing)
			var weak := {}
			for candidate in real_squad:
				if core.has(int(candidate.id)) and (weak.is_empty() or int(candidate.current_ability)<int(weak.current_ability)):weak=candidate
			row["diagnostic_core_upgrade_quote"]=quote(clubs,id,coach,weak)
		rows.append(row)
	FileAccess.open(folder.path_join("club-cycle-probe.json"),FileAccess.WRITE).store_string(JSON.stringify({"attraction":Attraction.snapshot(),"clubs":rows}))
	print("CLUB PROBE COMPLETE ",rows.size())
	GameSession.clear()
	get_tree().quit()

func quote(clubs: Dictionary,id: int,coach: Dictionary,outgoing: Dictionary) -> Dictionary:
	if outgoing.is_empty():return {"outgoing_missing":true}
	var rng := RandomNumberGenerator.new();rng.seed=110011+id
	var target := TransferMarket._find_upgrade_target(GameSession,clubs,id,clubs[id],coach,outgoing,{},rng)
	var player: Dictionary=target.get("player",{})
	return {"outgoing":outgoing.name,"out_ca":outgoing.current_ability,"position":outgoing.position,"target":player.get("name"),"target_ca":player.get("current_ability"),"fee":target.get("fee"),"accepted":target.get("accepted",false),"reason":target.get("reason","acceptable" if bool(target.get("accepted",false)) else "no_candidate"),"seller":clubs.get(int(target.get("seller_id",0)),{}).get("name"),"fee_cap":ClubFinance.max_single_fee(GameSession.get_club_budget(id))}
