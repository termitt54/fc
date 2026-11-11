extends Node
## Diagnostic only: all mutations stay in an isolated copy, no saves are written.

func _ready() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"))
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	assert(loaded.get("success", false))
	var payload: Dictionary = loaded["data"]
	assert(GameSession.apply_save_payload(payload.duplicate(true)).get("success", false))
	var unit: Dictionary = GameSession.units[0]
	var plan := SeasonReputation.plan(GameSession.units, GameSession.season_number, func(pid: int) -> Dictionary: return GameSession.get_player(pid))
	var pieces := SeasonReputation._club_parts(unit, GameSession.season_number)
	var clubs: Array = []
	for piece in pieces:
		var cid := int(piece["club_id"])
		var club: Dictionary = unit["clubs_by_id"][cid]
		clubs.append({"id": cid, "name": club["name"], "reputation": club["reputation"],
			"last_saved_delta": club.get("reputation_delta", 0), "upcoming_delta": plan["clubs"][cid]["delta"],
			"surprise": piece["step"], "level_pull": piece["pull"]})
	var players: Array = []
	for cid in GameSession.players_by_club:
		var club_rep := int(unit["clubs_by_id"][cid]["reputation"])
		for player in GameSession.get_club_players(cid):
			var pid := int(player["id"])
			var before := int(player["reputation"])
			var target := PlayerMarket.target_reputation(int(player["current_ability"]), club_rep)
			var drifted := PlayerMarket.drift_reputation(player.duplicate(true), club_rep)
			var result := int(plan["players"].get(pid, 0))
			players.append({"id": pid, "club_id": cid, "ca": player["current_ability"], "reputation": before,
				"club_reputation": club_rep, "ability_club_target": target, "result_delta": result,
				"projected_net_at_unchanged_ca": SeasonReputation.settled_player_reputation(before, drifted, result) - before})
	var coach10 := {"attributes": {"transfers": 10, "negotiations": 10}}
	var coach20 := {"attributes": {"transfers": 20, "negotiations": 20}}
	var star := {"id": 999999, "name": "Audit star", "position": "GK", "age": 25, "current_ability": 90,
		"potential_ability": 95, "reputation": 900, "wage": 1000000, "club_id": 0,
		"contract_years": 0, "contract_status": "free_agent", "is_youth": false, "nationality_country_id": 14}
	var weak := {"id": 56, "name": "Audit weak club", "country_id": 14, "reputation": 200}
	GameSession.players_by_club[56] = []
	GameSession.free_agents = [star]
	GameSession.coaches_by_club[56] = coach10
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var automatically_signed := TransferMarket._try_sign(GameSession, rng, 56, weak, [], "GK", false, false)
	var probes := {
		"last_expected_700_in_1000_league": SeasonReputation.table_delta(1000, 700, 34, 34, 34),
		"last_expected_850_in_1000_league": SeasonReputation.table_delta(1000, 850, 34, 34, 34),
		"last_expected_890_in_1000_league": SeasonReputation.table_delta(1000, 890, 34, 34, 34),
		"rep850_to_club500_coach10": TransferMarket._destination_score({"reputation": 850}, {"reputation": 500}, coach10),
		"rep850_to_club500_coach20": TransferMarket._destination_score({"reputation": 850}, {"reputation": 500}, coach20),
		"free_rep900_ca90_signed_to_club200": automatically_signed,
		"ca90_club900_target": PlayerMarket.target_reputation(90, 900),
		"ca50_club900_target": PlayerMarket.target_reputation(50, 900),
		"ca90_club0_target": PlayerMarket.target_reputation(90, 0),
		"zero_matches_result": SeasonReputation.player_adjustment(1000, 20, 0, 8.0, 90),
	}
	var output := "res://tests/performance/results/reputation-audit-20261011.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			output = argument.trim_prefix("--report=")
	var file := FileAccess.open(output, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"saved_at": payload["saved_at"], "season": payload["season_number"],
		"clubs": clubs, "players": players, "probes": probes,
		"scope": "Current season result plan; no historical reputations reconstructed; player projection holds CA unchanged, actual development runs first"}, "  "))
	file.close()
	print("REPUTATION AUDIT COMPLETE probes=", JSON.stringify(probes))
	get_tree().quit()
