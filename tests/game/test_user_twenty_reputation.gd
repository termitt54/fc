extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		get_tree().quit(2)
		return
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	assert(loaded.get("success", false))
	assert(GameSession.apply_save_payload(loaded["data"].duplicate(true)).get("success", false))
	var plan := SeasonReputation.plan(GameSession.units, GameSession.season_number, func(pid: int) -> Dictionary: return GameSession.get_player(pid))
	var clubs := {}
	for unit in GameSession.units:
		for cid in unit["clubs_by_id"]:
			clubs[cid] = unit["clubs_by_id"][cid]
	var club_results: Array = []
	for cid in clubs:
		club_results.append({"id": cid, "name": clubs[cid]["name"], "reputation": clubs[cid]["reputation"], "next_delta": plan["clubs"].get(cid, {}).get("delta", 0)})
	var elite: Array = []
	for cid in GameSession.players_by_club:
		for player in GameSession.get_club_players(cid):
			if int(player["current_ability"]) < 80:
				continue
			var acceptable: Array = []
			for destination in clubs:
				if destination == cid:
					continue
				var context := TransferMarket._offer_context(GameSession.get_club_players(destination), int(clubs[cid]["reputation"]))
				if TransferMarket._destination_score(player, clubs[destination], GameSession.get_club_coach(destination), context) >= 0.0:
					acceptable.append({"id": destination, "name": clubs[destination]["name"], "reputation": clubs[destination]["reputation"]})
			elite.append({"id": player["id"], "name": player["name"], "club": clubs[cid]["name"], "ca": player["current_ability"], "reputation": player["reputation"], "next_delta": plan["players"].get(int(player["id"]), 0), "acceptable_destinations": acceptable})
	var output := {"saved_at": loaded["data"]["saved_at"], "season": GameSession.season_number, "clubs": club_results, "elite": elite,
		"scope": "Current closed-season plan and hypothetical sporting/salary acceptance. Not historical transfer validation, not actual bids: squad slots, transfer fee affordability and foreign limits are not applied."}
	var file := FileAccess.open("res://tests/performance/results/user-20-reputation-plan.json", FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(output, "  "))
	file.close()
	print("TWENTY REPUTATION DONE clubs=", clubs.size(), " elite=", elite.size())
	get_tree().quit()
