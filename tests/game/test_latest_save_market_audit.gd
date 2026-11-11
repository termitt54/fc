extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		get_tree().quit(2)
		return
	var started := Time.get_ticks_usec()
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	assert(loaded.get("success", false))
	var load_ms := float(Time.get_ticks_usec() - started) / 1000.0
	assert(GameSession.apply_save_payload(loaded["data"].duplicate(true)).get("success", false))
	var clubs := {}
	for unit in GameSession.units:
		for cid in unit["clubs_by_id"]:
			clubs[cid] = unit["clubs_by_id"][cid]
	var elite: Array = []
	for player in GameSession.free_agents:
		if PlayerMarket.ability_of(player) < 80:
			continue
		var options: Array = []
		for cid in clubs:
			var squad: Array = GameSession.get_club_players(cid)
			var context := TransferMarket._offer_context(squad)
			context["offer_wage"] = PlayerMarket.wage_for_move(player, clubs[cid], true)
			var willingness := PlayerOffer.evaluate(player, clubs[cid], GameSession.get_club_coach(cid), context)
			var fb_abilities: Array = []
			for member in squad:
				if member["position"] == "FB":
					fb_abilities.append(PlayerMarket.ability_of(member))
			options.append({"club": clubs[cid]["name"], "accepted": willingness["accepted"], "reason": willingness["reason"],
				"squad_size": squad.size(), "budget": GameSession.get_club_budget(cid), "fb_abilities": fb_abilities,
				"foreign_count": TransferMarket.foreign_count(squad, clubs[cid]), "foreign_limit": TransferMarket.foreign_limit_for_club(GameSession, cid),
				"nationality": clubs[cid].get("country_id", 0)})
		elite.append({"id": player["id"], "name": player["name"], "ca": player["current_ability"], "age": player["age"],
			"nationality": player["nationality_country_id"], "free_years": player.get("free_agent_seasons", 0), "options": options})
	var file := FileAccess.open("res://tests/performance/results/user-40-market-audit.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"saved_at": loaded["data"]["saved_at"], "season": GameSession.season_number,
		"load_ms": load_ms, "free_elite": elite, "scope": "Current hypothetical player acceptance; actual slot, fee, wage affordability and foreign constraints are separate."}, "  "))
	file.close()
	print("LATEST MARKET AUDIT DONE load_ms=", load_ms, " elite_free=", elite.size())
	get_tree().quit()
