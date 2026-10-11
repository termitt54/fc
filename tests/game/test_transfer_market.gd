extends Node
## Transfer-window recruitment: positions, reputation fit, foreign limits.
## Run: godot --headless --path . res://tests/game/test_transfer_market.tscn

const TransferMarketScript := preload("res://game/transfer_market.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")


var _failed := 0
var _passed := 0
var _next_id := 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Transfer market tests ===")
	_test_needed_positions()
	_test_day_targets()
	_test_two_day_intake_and_rules()
	_test_last_day_fills_when_needed_position_is_gone()
	_test_last_day_keeps_the_foreign_limit()
	_test_zero_blocks_and_minus_one_is_open()
	_test_transfer_lock()
	_test_club_to_club_sale()
	_test_full_club_buys_an_upgrade()
	_test_upgrade_bid_can_be_rejected()
	_test_market_info_matches_starter_protection()
	_finish()


func _test_needed_positions() -> void:
	_assert(
		TransferMarketScript.next_needed_position([]) == PlayerTypesScript.POS_GK,
		"Empty squad needs a goalkeeper first"
	)
	var one_gk := [_player(PlayerTypesScript.POS_GK, 1, 400, 50)]
	_assert(
		TransferMarketScript.next_needed_position(one_gk) == PlayerTypesScript.POS_GK,
		"Second slot is still a goalkeeper"
	)
	var two_gk := [
		_player(PlayerTypesScript.POS_GK, 1, 400, 50),
		_player(PlayerTypesScript.POS_GK, 1, 400, 50),
	]
	_assert(
		TransferMarketScript.next_needed_position(two_gk) == PlayerTypesScript.POS_CB,
		"After two GKs the squad needs a centre-back"
	)


func _test_day_targets() -> void:
	_assert(TransferMarketScript._day_target(-5, 0) == 5, "Day -5 targets 5")
	_assert(TransferMarketScript._day_target(-4, 0) == 10, "Day -4 targets 10")
	_assert(TransferMarketScript._day_target(-3, 0) == 15, "Day -3 targets 15")
	_assert(TransferMarketScript._day_target(-2, 0) == 20, "Day -2 targets 20")
	_assert(TransferMarketScript._day_target(-1, 0) == 25, "Day -1 fills to 25")


func _test_two_day_intake_and_rules() -> void:
	var agents: Array = []
	# Plenty of domestic players plus a smaller foreign pool.
	for pos in [
		PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
		PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF,
	]:
		for _i in 3:
			agents.append(_player(pos, 1, 720, 72))
		for _j in 2:
			agents.append(_player(pos, 1, 280, 48))
		agents.append(_player(pos, 2, 500, 60))

	var payload := {
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"season_total_days": 32,
		"selected_unit_id": 1,
		"season_finished": false,
		"units": [{
			"id": 1,
			"foreign_players_limit": 4,
			"rules": {"foreign_players_limit": 4},
			"clubs_by_id": {
				1: {"id": 1, "country_id": 1, "reputation": 820, "name": "Alpha"},
				2: {"id": 2, "country_id": 1, "reputation": 280, "name": "Beta"},
			},
			"divisions": [{"club_ids": [1, 2]}],
		}],
		"players_by_club": {"1": [], "2": []},
		"youth_players_by_club": {},
		"free_agents": agents,
		"coaches_by_club": {
			"1": _coach(1, 18),
			"2": _coach(2, 5),
		},
		"transfer_log": [],
	}
	var loaded: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(loaded.get("success", false)), "Market fixture loads")

	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	GameSession.season_day = GameSession.MARKET_OPEN_DAY
	var first: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(first.get("signed", 0)) > 0, "Opening day signs players")
	_assert(GameSession.get_club_players(1).size() == 5, "Strong club signs 5 on day -5 (got %d)" % GameSession.get_club_players(1).size())
	_assert(GameSession.get_club_players(2).size() == 5, "Weak club signs 5 on day -5 (got %d)" % GameSession.get_club_players(2).size())

	GameSession.season_day = GameSession.MARKET_LAST_DAY
	var second: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(second.get("signed", 0)) > 0, "Day -1 signs the rest")
	_assert(GameSession.get_club_players(1).size() == 25, "Strong club reaches 25 (got %d)" % GameSession.get_club_players(1).size())
	_assert(GameSession.get_club_players(2).size() == 25, "Weak club reaches 25 (got %d)" % GameSession.get_club_players(2).size())
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(1)), "Strong club respects the squad law")
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(2)), "Weak club respects the squad law")

	_assert(_gk_count(GameSession.get_club_players(1)) >= 2, "Strong club has two goalkeepers")
	_assert(_gk_count(GameSession.get_club_players(2)) >= 2, "Weak club has two goalkeepers")
	_assert(_has_group(GameSession.get_club_players(1), PlayerTypesScript.DEF_POSITIONS), "Strong club signed defenders")
	_assert(_has_group(GameSession.get_club_players(1), PlayerTypesScript.MID_POSITIONS), "Strong club signed midfielders")
	_assert(_has_group(GameSession.get_club_players(1), PlayerTypesScript.ATT_POSITIONS), "Strong club signed attackers")

	var club := {"country_id": 1}
	_assert(
		TransferMarketScript.foreign_count(GameSession.get_club_players(1), club) <= 4,
		"Strong club respects foreign limit"
	)
	_assert(
		TransferMarketScript.foreign_count(GameSession.get_club_players(2), club) <= 4,
		"Weak club respects foreign limit"
	)

	var strong_rep := _avg_rep(GameSession.get_club_players(1))
	var weak_rep := _avg_rep(GameSession.get_club_players(2))
	_assert(strong_rep > weak_rep, "Higher club/coach reputation signs higher-reputation players (%.0f vs %.0f)" % [strong_rep, weak_rep])

	_assert(not GameSession.get_club_transfers(1).is_empty(), "Transfer history recorded for club 1")
	GameSession.clear()


func _test_last_day_fills_when_needed_position_is_gone() -> void:
	# Only a handful of full-backs exist; clubs still must reach 25 on day -1.
	var agents: Array = []
	for pos in [
		PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
		PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF,
	]:
		for _i in 4:
			agents.append(_player(pos, 1, 500, 55))
	for _fb in 3:
		agents.append(_player(PlayerTypesScript.POS_FB, 1, 500, 55))
	_load_two_club_market(agents, 0, 10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_run_full_window(rng)
	_assert(GameSession.get_club_players(1).size() == 25, "Club 1 reaches 25 without enough FBs (got %d)" % GameSession.get_club_players(1).size())
	_assert(GameSession.get_club_players(2).size() == 25, "Club 2 reaches 25 without enough FBs (got %d)" % GameSession.get_club_players(2).size())
	GameSession.clear()


func _test_zero_blocks_and_minus_one_is_open() -> void:
	var club := {"country_id": 1}
	var foreigner := {"position": PlayerTypesScript.POS_ST, "nationality_country_id": 2}
	var local := {"position": PlayerTypesScript.POS_ST, "nationality_country_id": 1}
	_assert(
		not TransferMarketScript._eligible(foreigner, club, [], 0, PlayerTypesScript.POS_ST, false),
		"a limit of 0 blocks a foreigner"
	)
	_assert(
		TransferMarketScript._eligible(local, club, [], 0, PlayerTypesScript.POS_ST, false),
		"a limit of 0 still allows a local player"
	)
	_assert(
		TransferMarketScript._eligible(foreigner, club, [], -1, PlayerTypesScript.POS_ST, false),
		"-1 leaves the foreign place open"
	)


func _test_last_day_keeps_the_foreign_limit() -> void:
	var agents: Array = []
	for pos in PlayerTypesScript.POSITIONS:
		for _i in 8:
			agents.append(_player(pos, 2, 480, 52))
		agents.append(_player(pos, 1, 400, 48))
	_load_two_club_market(agents, 2, 10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 19
	_run_full_window(rng)
	var club := {"id": 1, "country_id": 1}
	_assert(
		TransferMarketScript.foreign_count(GameSession.get_club_players(1), club) <= 2,
		"last market day keeps the foreign cap"
	)
	club["id"] = 2
	_assert(
		TransferMarketScript.foreign_count(GameSession.get_club_players(2), club) <= 2,
		"the second club keeps the same cap"
	)
	GameSession.clear()


func _load_two_club_market(agents: Array, foreign_limit: int, skill_a: int, skill_b: int) -> void:
	var loaded: Dictionary = GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"season_total_days": 32,
		"selected_unit_id": 1,
		"season_finished": false,
		"units": [{
			"id": 1,
			"foreign_players_limit": foreign_limit,
			"rules": {"foreign_players_limit": foreign_limit},
			"clubs_by_id": {
				1: {"id": 1, "country_id": 1, "reputation": 700, "name": "Alpha"},
				2: {"id": 2, "country_id": 1, "reputation": 300, "name": "Beta"},
			},
			"divisions": [{"club_ids": [1, 2]}],
		}],
		"players_by_club": {"1": [], "2": []},
		"youth_players_by_club": {},
		"free_agents": agents,
		"coaches_by_club": {
			"1": _coach(1, skill_a),
			"2": _coach(2, skill_b),
		},
		"transfer_log": [],
	})
	_assert(bool(loaded.get("success", false)), "Market scarcity fixture loads")


func _run_full_window(rng: RandomNumberGenerator) -> void:
	for day in [-5, -4, -3, -2, -1]:
		GameSession.season_day = day
		TransferMarketScript.run_day(GameSession, rng)


func _test_transfer_lock() -> void:
	_assert(
		not TransferMarketScript.is_transfer_locked({"id": 1}, 2),
		"founders without joined_season are not locked"
	)
	_assert(
		TransferMarketScript.is_transfer_locked({"joined_season": 3}, 3),
		"locked in the joining season"
	)
	_assert(
		TransferMarketScript.is_transfer_locked({"joined_season": 3}, 4),
		"locked in the following season"
	)
	_assert(
		not TransferMarketScript.is_transfer_locked({"joined_season": 3}, 5),
		"unlocked from the third season"
	)
	_assert(
		not TransferMarketScript.is_buyable({"club_id": 1, "age": 16, "is_youth": true}, 5),
		"youth is not buyable"
	)


func _test_club_to_club_sale() -> void:
	var listed := _player(PlayerTypesScript.POS_ST, 1, 500, 62)
	listed["club_id"] = 2
	listed["contract_status"] = GameSession.STATUS_CLUB
	listed["contract_years"] = 3
	listed["for_sale"] = true
	listed["asking_price"] = 40000
	listed["value"] = 40000
	var buyer_squad: Array = _legal_squad_missing_st(1, 24)
	var seller_squad: Array = _legal_full_squad(2)
	for i in seller_squad.size():
		if str(seller_squad[i].get("position", "")) == PlayerTypesScript.POS_ST:
			seller_squad[i] = listed
			break
	GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 2,
		"season_day": -4,
		"units": [{
			"id": 1,
			"clubs_by_id": {
				1: {"id": 1, "country_id": 1, "reputation": 700, "name": "Buyers", "finance_level": 16},
				2: {"id": 2, "country_id": 1, "reputation": 400, "name": "Sellers", "finance_level": 10},
			},
			"matches": [],
		}],
		"players_by_club": {1: buyer_squad, 2: seller_squad},
		"free_agents": [],
		"coaches_by_club": {
			1: _coach(1, 18),
			2: _coach(2, 8),
		},
		"club_budgets": {1: 500000, 2: 100000},
		"wages_paid_for_season": 2,
	})
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var result: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(result.get("bought", 0)) >= 1, "a listed player is bought (bought=%s)" % str(result.get("bought", 0)))
	var moved := false
	for player in GameSession.get_club_players(1):
		if int(player.get("id", 0)) == int(listed.get("id", 0)):
			moved = true
			_assert(int(player.get("joined_season", 0)) == 2, "join lock starts this season")
			_assert(int(player.get("contract_years", 0)) >= 2, "paid transfer gets at least 2 years")
	_assert(moved, "listed striker joined the buying club")
	_assert(GameSession.get_club_budget(1) < 500000, "buyer paid a fee")
	_assert(GameSession.get_club_budget(2) > 100000, "seller received a fee")
	GameSession.clear()


func _test_full_club_buys_an_upgrade() -> void:
	var buyer_squad := _legal_full_squad(1)
	var seller_squad := _legal_full_squad(2)
	_set_strikers(buyer_squad, 1, [72, 68, 48])
	_set_strikers(seller_squad, 2, [80, 64, 52])
	var extra := _player(PlayerTypesScript.POS_ST, 1, 520, 70)
	extra["club_id"] = 2
	extra["contract_status"] = GameSession.STATUS_CLUB
	extra["contract_years"] = 3
	extra["value"] = 80000
	_replace_extra(seller_squad, PlayerTypesScript.POS_CB, extra)
	var target_id := int(extra.get("id", 0))
	_load_upgrade_market(buyer_squad, seller_squad, 700, 420, 2_000_000, 200000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	GameSession.season_day = -4
	var result: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(result.get("upgrades", 0)) >= 1, "a full club buys an upgrade (upgrades=%s)" % str(result.get("upgrades", 0)))
	_assert(GameSession.get_club_players(1).size() == 25, "buyer stays at 25 after the swap")
	_assert(GameSession.get_club_players(2).size() == 24, "seller is left with a hole")
	var moved := false
	for player in GameSession.get_club_players(1):
		if int(player.get("id", 0)) == target_id:
			moved = true
			_assert(int(player.get("current_ability", 0)) == 70, "the stronger striker arrived")
	_assert(moved, "upgrade target joined the buying club")
	var dumped := false
	for player in GameSession.free_agents:
		if typeof(player) == TYPE_DICTIONARY and int(player.get("current_ability", 0)) == 48:
			dumped = true
	_assert(dumped, "the displaced weak striker went to free agents")
	_assert(GameSession.get_club_budget(1) < 2_000_000, "buyer paid a fee")
	_assert(GameSession.get_club_budget(2) > 200000, "seller received a fee")
	GameSession.clear()


func _test_upgrade_bid_can_be_rejected() -> void:
	var buyer_squad := _legal_full_squad(1)
	var seller_squad := _legal_full_squad(2)
	_set_strikers(buyer_squad, 1, [72, 68, 48])
	# One stronger starter so the extra star is spare; the rest stay below
	# outgoing CA 48 + 4 and cannot be an upgrade themselves.
	_set_strikers(seller_squad, 2, [85, 49, 49])
	var star := _player(PlayerTypesScript.POS_ST, 1, 960, 78)
	star["club_id"] = 2
	star["contract_status"] = GameSession.STATUS_CLUB
	star["contract_years"] = 3
	star["value"] = 120000
	_replace_extra(seller_squad, PlayerTypesScript.POS_CB, star)
	_load_upgrade_market(buyer_squad, seller_squad, 220, 500, 3_000_000, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	GameSession.season_day = -3
	var result: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(result.get("upgrades", 0)) == 0, "the star does not join a small club")
	_assert(int(result.get("bids", 0)) >= 1, "the failed bid is recorded (bids=%s)" % str(result.get("bids", 0)))
	var saw_bid := false
	for entry in GameSession.transfer_log:
		if typeof(entry) == TYPE_DICTIONARY and str(entry.get("direction", "")) == "bid":
			saw_bid = true
	_assert(saw_bid, "transfer log keeps the rejected offer")
	_assert(GameSession.get_club_players(1).size() == 25, "buyer squad is unchanged")
	_assert(GameSession.get_club_players(2).size() == 25, "seller squad is unchanged")
	GameSession.clear()


func _load_upgrade_market(
	buyer_squad: Array,
	seller_squad: Array,
	buyer_rep: int,
	seller_rep: int,
	buyer_budget: int,
	seller_budget: int
) -> void:
	GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 2,
		"season_day": -4,
		"units": [{
			"id": 1,
			"clubs_by_id": {
				1: {"id": 1, "country_id": 1, "reputation": buyer_rep, "name": "Buyers"},
				2: {"id": 2, "country_id": 1, "reputation": seller_rep, "name": "Sellers"},
			},
			"matches": [],
		}],
		"players_by_club": {1: buyer_squad, 2: seller_squad},
		"free_agents": [],
		"coaches_by_club": {
			1: _coach(1, 18),
			2: _coach(2, 8),
		},
		"club_budgets": {1: buyer_budget, 2: seller_budget},
		"wages_paid_for_season": 2,
		"transfer_log": [],
	})


func _set_strikers(squad: Array, club_id: int, ratings: Array) -> void:
	var i := 0
	for player in squad:
		if str(player.get("position", "")) != PlayerTypesScript.POS_ST:
			continue
		if i >= ratings.size():
			break
		player["current_ability"] = int(ratings[i])
		player["potential_ability"] = int(ratings[i]) + 4
		player["overall"] = int(ratings[i])
		player["club_id"] = club_id
		player["contract_years"] = 3
		i += 1


func _replace_extra(squad: Array, drop_position: String, incoming: Dictionary) -> void:
	var counts := PlayerTypesScript.count_squad_positions(squad)
	var minimum := int(PlayerTypesScript.SQUAD_SLOT_MIN.get(drop_position, 0))
	if int(counts.get(drop_position, 0)) <= minimum:
		squad.append(incoming)
		return
	for i in squad.size():
		var row: Dictionary = squad[i]
		if str(row.get("position", "")) != drop_position:
			continue
		if int(counts.get(drop_position, 0)) <= minimum:
			continue
		squad[i] = incoming
		return
	squad.append(incoming)


func _legal_squad_missing_st(club_id: int, size: int) -> Array:
	var positions: Array = [
		PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
		PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF,
	]
	while positions.size() < size:
		positions.append(PlayerTypesScript.POS_CB)
	var squad: Array = []
	for pos in positions:
		var row := _player(str(pos), 1, 400, 50)
		row["club_id"] = club_id
		row["contract_status"] = GameSession.STATUS_CLUB
		row["contract_years"] = 3
		squad.append(row)
	return squad


func _legal_full_squad(club_id: int) -> Array:
	var squad := _legal_squad_missing_st(club_id, 22)
	for pos in [PlayerTypesScript.POS_ST, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_FB]:
		var row := _player(pos, 1, 420, 52)
		row["club_id"] = club_id
		row["contract_status"] = GameSession.STATUS_CLUB
		row["contract_years"] = 3
		squad.append(row)
	return squad


func _test_market_info_matches_starter_protection() -> void:
	var squad: Array = []
	# Equal abilities, legacy aliases, and absent positions exercise the exact
	# old protection rule (at least one native player even for an unused role).
	for position in ["GK", "CB", "FB", "CM", "DM", "AM", "WM", "WF", "W", "ST", "unknown"]:
		for ca in [60, 60, 50]:
			squad.append(_player(position, 1, 500, ca))
	squad.append(null)
	var coach := _coach(1, 10)
	GameSession.coaches_by_club = {1: coach}
	for formation in ["2-3-2", "2-4-1", "3-1-3", "3-3-1", "3-2-2", "2-2-3"]:
		coach["primary_formation"] = formation
		var info := TransferMarketScript._squad_market_info(GameSession, 1, squad)
		for player in squad:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			_assert(info["starters"].has(int(player["id"])) == TransferMarketScript._is_scheme_starter(GameSession, 1, player, squad),
				"Cached protection matches original: %s player %d" % [formation, player["id"]])
		_assert(info["counts"] == PlayerTypesScript.count_squad_positions(squad), "Cached position counts match original")
	# A rebuilt wave must use changed ability and membership, not stale starters.
	var changed: Dictionary = squad[2]
	changed["current_ability"] = 99
	squad.remove_at(0)
	var refreshed := TransferMarketScript._squad_market_info(GameSession, 1, squad)
	_assert(refreshed["starters"].has(int(changed["id"])), "Rebuild sees an improved player after squad changes")
	var empty := TransferMarketScript._squad_market_info(GameSession, 1, [])
	_assert(empty["starters"].is_empty() and empty["counts"] == PlayerTypesScript.count_squad_positions([]), "Empty squads have no protected starters")
	GameSession.clear()


func _player(position: String, country_id: int, reputation: int, ca: int) -> Dictionary:
	var id := _next_id
	_next_id += 1
	return {
		"id": id,
		"club_id": 0,
		"name": "P%d" % id,
		"age": 24,
		"nationality_country_id": country_id,
		"position": position,
		"reputation": reputation,
		"current_ability": ca,
		"potential_ability": ca + 6,
		"overall": ca,
		"contract_status": GameSession.STATUS_FREE_AGENT,
		"contract_years": 0,
		"value": 40000,
		"wage": 3000,
	}


func _coach(club_id: int, transfers: int) -> Dictionary:
	return {
		"id": club_id,
		"club_id": club_id,
		"name": "Coach %d" % club_id,
		"primary_formation": "2-3-2",
		"attributes": {CoachTypesScript.ATTR_TRANSFERS: transfers},
		"current_ability": 50,
	}


func _gk_count(squad: Array) -> int:
	var n := 0
	for player in squad:
		if str(player.get("position", "")) == PlayerTypesScript.POS_GK:
			n += 1
	return n


func _has_group(squad: Array, group: Array) -> bool:
	for player in squad:
		if str(player.get("position", "")) in group:
			return true
	return false


func _avg_rep(squad: Array) -> float:
	if squad.is_empty():
		return 0.0
	var total := 0
	for player in squad:
		total += int(player.get("reputation", 0))
	return float(total) / float(squad.size())


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % message)
	else:
		_failed += 1
		print("FAIL: %s" % message)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
