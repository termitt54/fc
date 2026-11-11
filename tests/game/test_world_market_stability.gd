extends Node

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		get_tree().quit(2)
		return
	call_deferred("run")

func run() -> void:
	var source := SaveStore.new().load_slot("autosave")
	if not source.get("success", false) or not GameSession.apply_save_payload(source["data"].duplicate(true))["success"]:
		get_tree().quit(1)
		return
	var started := Time.get_ticks_msec()
	var clubs := GameSession._collect_session_clubs()
	var elite_options: Array = []
	for player in GameSession.free_agents:
		if PlayerMarket.ability_of(player) < 80:
			continue
		var accepted: Array = []
		for cid in clubs:
			var context := TransferMarket._offer_context(GameSession.get_club_players(cid), 0, PlayerOffer.world_top_reputation(clubs))
			context["offer_wage"] = PlayerMarket.wage_for_move(player, clubs[cid], true)
			if PlayerOffer.evaluate(player, clubs[cid], GameSession.get_club_coach(cid), context)["accepted"]:
				accepted.append(clubs[cid]["name"])
		elite_options.append({"id": player["id"], "name": player["name"], "ca": player["current_ability"], "accepted": accepted})
	var initial_event_count: int = GameSession.coach_market["events"].size()
	var initial_transfers := GameSession.transfer_log.size()
	var cycles: Array = []
	for cycle in 3:
		var days := 0
		while not GameSession.season_finished and days < 300:
			if not (await GameSession.advance_day_async(8))["success"]:
				get_tree().quit(1)
				return
			days += 1
		if not GameSession.season_finished or not GameSession.start_new_season()["success"]:
			get_tree().quit(1)
			return
		while GameSession.season_day < 1:
			if not (await GameSession.advance_day_async(8))["success"]:
				get_tree().quit(1)
				return
		var bad_shapes: Array = []
		var foreign_violations: Array = []
		clubs = GameSession._collect_session_clubs()
		for cid in clubs:
			var squad := GameSession.get_club_players(cid)
			if not PlayerTypes.is_squad_shape_legal(squad):
				bad_shapes.append({"club": clubs[cid]["name"], "size": squad.size(), "positions": PlayerTypes.count_squad_positions(squad)})
			var limit := TransferMarket.foreign_limit_for_club(GameSession, cid)
			if limit >= 0 and TransferMarket.foreign_count(squad, clubs[cid]) > limit:
				foreign_violations.append(clubs[cid]["name"])
		cycles.append({"season": GameSession.season_number, "bad_shapes": bad_shapes, "foreign_violations": foreign_violations})
		print("WORLD STABILITY CYCLE ", JSON.stringify(cycles[-1]))
	var counts := {}
	var dismissals := {}
	for event in GameSession.coach_market["events"].slice(initial_event_count):
		counts[event["reason"]] = int(counts.get(event["reason"], 0)) + 1
		if event["reason"] == "dismissed":
			var key := "%d:%d" % [event["club_id"], event["season"]]
			dismissals[key] = int(dismissals.get(key, 0)) + 1
	var max_dismissals := 0
	for count in dismissals.values():
		max_dismissals = maxi(max_dismissals, int(count))
	var free_signings := 0
	for entry in GameSession.transfer_log.slice(initial_transfers):
		if entry["direction"] == "in" and entry["other_club"] == "свободный агент":
			free_signings += 1
	var result := {"source_saved_at": source["data"]["saved_at"], "source_season": source["data"]["season_number"],
		"elite_options": elite_options, "cycles": cycles, "events": counts, "max_club_season_dismissals": max_dismissals,
		"free_signings": free_signings, "elapsed_seconds": (Time.get_ticks_msec() - started) / 1000.0}
	var elite_outcomes: Array = []
	for elite in elite_options:
		var player := GameSession.get_player(int(elite["id"]))
		var club_id := int(player.get("club_id", 0))
		elite_outcomes.append({"name": elite["name"], "club": clubs.get(club_id, {}).get("name", "без клуба"),
			"moves": GameSession.transfer_log.slice(initial_transfers).filter(func(entry: Dictionary) -> bool: return int(entry["player_id"]) == int(elite["id"]))})
	result["elite_outcomes"] = elite_outcomes
	var swaps := 0
	var logs: Array = GameSession.transfer_log.slice(initial_transfers)
	for i in range(logs.size() - 1):
		if logs[i]["direction"] == "in" and logs[i]["other_club"] == "свободный агент" and logs[i + 1]["direction"] == "out" and logs[i + 1]["other_club"] == "вытеснен" and logs[i]["club_id"] == logs[i + 1]["club_id"]:
			swaps += 1
	result["free_swaps_including_repairs"] = swaps
	var before := var_to_bytes(GameSession.coach_market)
	var rng_state := GameSession._rng.state
	if not GameSession.save_game("zz_world_stability")["success"]:
		get_tree().quit(1)
		return
	GameSession.clear()
	result["roundtrip"] = GameSession.load_game("zz_world_stability")["success"] and before == var_to_bytes(GameSession.coach_market) and rng_state == GameSession._rng.state
	GameSession.delete_save("zz_world_stability")
	var ids := {}
	var duplicates := 0
	for squad in GameSession.players_by_club.values() + GameSession.reserve_players_by_club.values() + GameSession.youth_players_by_club.values() + [GameSession.free_agents]:
		for player in squad:
			if ids.has(player["id"]):
				duplicates += 1
			ids[player["id"]] = true
	result["duplicate_player_ids"] = duplicates
	var file := FileAccess.open("res://tests/performance/results/world-market-stability.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "  "))
	file.close()
	print("WORLD STABILITY END ", JSON.stringify(result))
	get_tree().quit(0 if max_dismissals <= 1 and duplicates == 0 and result["roundtrip"] and cycles.all(func(row: Dictionary) -> bool: return row["bad_shapes"].is_empty() and row["foreign_violations"].is_empty()) else 1)

