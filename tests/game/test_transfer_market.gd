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
	_test_core_protection()
	_test_needed_positions()
	_test_day_targets()
	_test_two_day_intake_and_rules()
	_test_capped_countries_complete_opening_squads()
	_test_initial_partial_squad_is_not_a_quality_ceiling()
	_test_last_day_fills_when_needed_position_is_gone()
	_test_last_day_keeps_the_foreign_limit()
	_test_internal_cover_preserves_players_and_positions()
	_test_zero_blocks_and_minus_one_is_open()
	_test_transfer_lock()
	_test_club_to_club_sale()
	_test_free_upgrade_and_repair()
	_test_full_club_buys_an_upgrade()
	_test_upgrade_bid_can_be_rejected()
	_test_market_info_matches_starter_protection()
	_finish()


func _test_internal_cover_preserves_players_and_positions() -> void:
	_load_two_club_market([], 0, 15, 15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 125711
	var squad: Array = []
	for position in PlayerTypesScript.build_squad_positions(rng):
		squad.append(_player(position, 1, 500, 60))
	var removed: Dictionary = {}
	for player in squad:
		if player.position == "ST":
			removed = player
			break
	squad.erase(removed)
	GameSession.players_by_club[1] = squad
	var excess := ""
	var counts := PlayerTypesScript.count_squad_positions(squad)
	for position in PlayerTypesScript.POSITIONS:
		if position != "ST" and int(counts[position]) < PlayerTypesScript.squad_slot_max(position) and int(counts[position]) >= PlayerTypesScript.squad_slot_min(position):
			excess = position
			break
	if not excess.is_empty() and PlayerTypesScript.missing_required_position(squad) == "ST":
		_assert(not PlayerTypesScript.can_add_squad_position(squad, excess), "Last squad slot is reserved for the missing mandatory role")
	removed["is_reserve"] = true
	removed["club_id"] = 1
	GameSession.reserve_players_by_club[1] = [removed]
	var foreign := _player("ST", 2, 500, 90)
	foreign["club_id"] = 1
	GameSession.youth_players_by_club[1] = [foreign]
	_assert(TransferMarketScript._promote_internal_cover(GameSession, 1) == 1, "Existing reserve fills a first-team vacancy")
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(1)), "Internal cover restores the legal 20-player shape")
	_assert(GameSession.reserve_players_by_club[1].is_empty() and GameSession.get_club_players(1).has(removed), "Promotion moves the same player instead of duplicating him")
	_assert(not bool(removed.get("is_reserve", false)) and not bool(removed.get("is_youth", false)), "Promoted player's first-team state is consistent")
	_assert(GameSession.youth_players_by_club[1] == [foreign], "Promotion preserves unused academy players and the foreign cap")
	GameSession.clear()


func _test_capped_countries_complete_opening_squads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220016
	var agents: Array = []
	for nation in [1, 2]:
		for position in PlayerTypesScript.build_squad_positions(rng):
			agents.append(_player(position, nation, 600 if nation == 1 else 750, 60 if nation == 1 else 70))
	_load_two_club_market(agents, 3, 15, 15)
	GameSession.units[0]["clubs_by_id"][1]["reputation"] = 900
	GameSession.units[0]["clubs_by_id"][2]["reputation"] = 750
	GameSession.units[0]["clubs_by_id"][2]["country_id"] = 2
	_run_full_window(rng)
	for cid in [1, 2]:
		var squad := GameSession.get_club_players(cid)
		var club: Dictionary = GameSession.units[0]["clubs_by_id"][cid]
		_assert(PlayerTypesScript.is_squad_shape_legal(squad), "Capped countries finish the complete opening market with 20 players and all positions")
		_assert(TransferMarketScript.foreign_count(squad, club) <= 3, "Opening allocation preserves the configured foreign cap")
	_assert(GameSession.free_agents.is_empty(), "Enough existing players fill both teams without creating replacements")
	GameSession.clear()
	# The same scarcity can recur after contracts expire in later seasons.
	agents = []
	for nation in [1,2]:
		for position in PlayerTypesScript.build_squad_positions(rng):
			agents.append(_player(position,nation,250,40))
	_load_two_club_market(agents,3,15,15)
	GameSession.season_number = 2
	GameSession.units[0]["clubs_by_id"][2]["country_id"] = 2
	_run_full_window(rng)
	for cid in [1,2]:
		_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(cid)), "Later market windows retain enough scarce players for legal squads")
	GameSession.clear()


func _test_initial_partial_squad_is_not_a_quality_ceiling() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220022
	for season in [1, 2]:
		var target := _player("CB", 1, 750, 80)
		_load_two_club_market([target], 3, 15, 15)
		GameSession.season_number = season
		GameSession.units[0]["clubs_by_id"][1]["reputation"] = 950
		GameSession.players_by_club[1] = [_player("GK",1,350,35), _player("GK",1,350,35)]
		var clubs := GameSession._collect_session_clubs()
		var signed := TransferMarketScript._try_sign(GameSession,rng,1,clubs[1],GameSession.get_club_players(1),"CB",false,false)
		_assert(signed if season == 1 else not signed, "Only the first draft ignores a partial squad's misleading quality estimate")
		GameSession.clear()


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
	_assert(TransferMarketScript._day_target(-5, 0) == 4, "Day -5 targets 4")
	_assert(TransferMarketScript._day_target(-4, 0) == 8, "Day -4 targets 8")
	_assert(TransferMarketScript._day_target(-3, 0) == 12, "Day -3 targets 12")
	_assert(TransferMarketScript._day_target(-2, 0) == 16, "Day -2 targets 16")
	_assert(TransferMarketScript._day_target(-1, 0) == 20, "Day -1 fills to 20")


func _test_two_day_intake_and_rules() -> void:
	var agents: Array = []
	# Plenty of domestic players plus a smaller foreign pool.
	for pos in [
		PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
	]:
		for _i in 3:
			agents.append(_player(pos, 1, 720, 72))
		for _j in 2:
			agents.append(_player(pos, 1, 280, 45))
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
	_assert(GameSession.get_club_players(1).size() == 4, "Strong club signs 4 on day -5 (got %d)" % GameSession.get_club_players(1).size())
	_assert(GameSession.get_club_players(2).size() == 4, "Weak club signs 4 on day -5 (got %d)" % GameSession.get_club_players(2).size())

	GameSession.season_day = GameSession.MARKET_LAST_DAY
	var second: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(second.get("signed", 0)) > 0, "Day -1 signs the rest")
	_assert(GameSession.get_club_players(1).size() == 20, "Strong club reaches 20 (got %d)" % GameSession.get_club_players(1).size())
	_assert(GameSession.get_club_players(2).size() == 20, "Weak club reaches 20 (got %d)" % GameSession.get_club_players(2).size())
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
	var agents: Array = []
	for pos in ["GK","GK","CM","CM","CM","CM","CM","ST","ST","ST","ST"]:
		for _i in 4:
			agents.append(_player(pos,1,500,55))
			agents.append(_player(pos,1,350,48))
	for _i in 3: agents.append(_player("CB",1,500,55))
	_load_two_club_market(agents, 0, 10, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	_run_full_window(rng)
	_assert(not PlayerTypesScript.missing_required_position(GameSession.get_club_players(1)).is_empty(), "A scarce position remains visible instead of being filled with an unrelated player")
	_assert(GameSession.get_club_players(2).size() < 20, "Shortage cannot produce a full illegal squad")
	GameSession.clear()


func _test_zero_blocks_and_minus_one_is_open() -> void:
	var club := {"country_id": 1}
	var foreigner := {"position": PlayerTypesScript.POS_GK, "nationality_country_id": 2}
	var local := {"position": PlayerTypesScript.POS_GK, "nationality_country_id": 1}
	_assert(
		not TransferMarketScript._eligible(foreigner, club, [], 0, PlayerTypesScript.POS_GK, false),
		"a limit of 0 blocks a foreigner"
	)
	_assert(
		TransferMarketScript._eligible(local, club, [], 0, PlayerTypesScript.POS_GK, false),
		"a limit of 0 still allows a local player"
	)
	_assert(
		TransferMarketScript._eligible(foreigner, club, [], -1, PlayerTypesScript.POS_GK, false),
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
	var buyer_squad: Array = _legal_squad_missing_st(1, 19)
	var seller_squad: Array = _legal_full_squad(2)
	var backup := _player(PlayerTypesScript.POS_ST, 1, 400, 70)
	backup["club_id"] = 2
	_replace_extra(seller_squad, PlayerTypesScript.POS_CB, backup)
	for row in seller_squad:
		if row["position"] == PlayerTypesScript.POS_ST:
			row["current_ability"] = 70
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
	_set_strikers(seller_squad, 2, [80, 75, 52, 50])
	var extra := _player(PlayerTypesScript.POS_ST, 1, 520, 70)
	extra["club_id"] = 2
	extra["contract_status"] = GameSession.STATUS_CLUB
	extra["contract_years"] = 3
	extra["value"] = 80000
	_replace_extra(seller_squad, PlayerTypesScript.POS_CB, extra)
	_load_upgrade_market(buyer_squad, seller_squad, 700, 420, 2_000_000, 200000)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	GameSession.season_day = -4
	var result: Dictionary = TransferMarketScript.run_day(GameSession, rng)
	_assert(int(result.get("upgrades", 0)) >= 1, "a full club buys an upgrade (upgrades=%s)" % str(result.get("upgrades", 0)))
	_assert(GameSession.get_club_players(1).size() == 20, "buyer stays at 20 after the swap")
	_assert(GameSession.get_club_players(2).size() == 19, "seller is left with a hole")
	var moved := false
	for player in GameSession.get_club_players(1):
		if int(player.get("joined_season", 0)) == 2 and int(player.get("current_ability", 0)) >= 70:
			moved = true
			_assert(int(player.get("current_ability", 0)) >= 70, "a stronger striker arrived, including a starter with safe cover")
	_assert(moved, "a legal upgrade target joined the buying club")
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
	_set_strikers(seller_squad, 2, [85, 82, 49, 49])
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
	_assert(GameSession.get_club_players(1).size() == 20, "buyer squad is unchanged")
	_assert(GameSession.get_club_players(2).size() == 20, "seller squad is unchanged")
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
		player["attributes"] = _attributes(str(player.position),int(ratings[i]))
		MatchRatings.invalidate(player)
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
	var positions: Array = ["GK","GK","CB","CB","CB","CB","CB","CB","CB","CB","CM","CM","CM","CM","CM","CM","ST","ST","ST"]
	var squad: Array = []
	for pos in positions.slice(0,size):
		var row := _player(str(pos),1,400,50)
		row.club_id=club_id
		row.contract_status=GameSession.STATUS_CLUB
		row.contract_years=3
		squad.append(row)
	return squad

func _legal_full_squad(club_id: int) -> Array:
	var squad := _legal_squad_missing_st(club_id,19)
	var row := _player("ST",1,420,52)
	row.club_id=club_id
	row.contract_status=GameSession.STATUS_CLUB
	row.contract_years=3
	squad.append(row)
	return squad


func _test_market_info_matches_starter_protection() -> void:
	var squad: Array = []
	# Equal abilities, legacy aliases, and absent positions exercise the exact
	# old protection rule (at least one native player even for an unused role).
	for position in ["GK", "CB", "CM", "CM", "DM", "AM", "WM", "ST", "W", "ST", "unknown"]:
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
		"attributes": _attributes(position,ca),
		"contract_status": GameSession.STATUS_FREE_AGENT,
		"contract_years": 0,
		"value": 40000,
		"wage": 3000,
	}

func _attributes(position: String,ca: int) -> Dictionary:
	var result := {}
	for group in PlayerTypesScript.attribute_groups_for_position(position):
		result[group]={}
		for key in PlayerTypesScript.attribute_keys_for_group(group):result[group][key]=clampi(int(round(ca/5.0)),1,20)
	return result


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


func _test_core_protection() -> void:
	GameSession.clear()
	var squad := _legal_full_squad(1)
	var star := _player("GK", 1, 600, 88)
	star["club_id"] = 1
	star["for_sale"] = true
	var inserted := false
	for player in squad:
		if player["position"] == "GK":
			player["current_ability"] = 58
	for i in squad.size():
		if squad[i]["position"] == "GK" and not inserted:
			squad[i] = star
			inserted = true
	var backup := _player("GK", 1, 400, 55)
	backup["club_id"] = 1
	backup["contract_years"] = 3
	squad.append(backup)
	GameSession.players_by_club[1] = squad
	_assert(not TransferMarketScript._seller_can_spare(GameSession, 1, squad, star), "CA88 first goalkeeper cannot be sold with CA58 replacement")
	backup["current_ability"] = 85
	_assert(TransferMarketScript._seller_can_spare(GameSession, 1, squad, star), "starter can be sold with a genuinely strong replacement")
	_assert(not TransferMarketScript._seller_can_spare(GameSession, 1, [star, backup], star), "strong cover cannot bypass minimum squad position count")
	backup["current_ability"] = 55
	_assert(TransferMarketScript._seller_can_spare(GameSession, 1, squad, backup), "third reserve goalkeeper can leave")
	var before := squad.size()
	TransferMarketScript._release_unsold_listed(GameSession, {1: {"name": "Protected"}})
	_assert(GameSession.get_club_players(1).size() == before and GameSession.free_agents.is_empty(), "unsold listing cannot bypass first-team protection")
	_assert(not bool(star["for_sale"]), "unsafe listing is cancelled")
	backup["for_sale"] = true
	TransferMarketScript._release_unsold_listed(GameSession, {1: {"name": "Protected"}})
	_assert(GameSession.free_agents.is_empty() and GameSession.get_club_players(1).size() == before, "unsold contracted player remains an asset")
	backup["contract_years"] = 0
	TransferMarketScript._release_unsold_listed(GameSession, {1: {"name": "Protected"}})
	_assert(GameSession.free_agents.size() == 1 and GameSession.get_club_players(1).size() == before - 1, "safe release still works after contract expiry")
	GameSession.clear()


func _test_free_upgrade_and_repair() -> void:
	var squad := _legal_full_squad(1)
	for player in squad:
		player["current_ability"] = 75
		player["potential_ability"] = 85
		player["attributes"] = _attributes(str(player.position),75)
		MatchRatings.invalidate(player)
	_set_strikers(squad, 1, [72, 68, 48])
	_load_upgrade_market(squad, _legal_full_squad(2), 820, 300, 2000000, 0)
	var star := _player("ST", 1, 530, 92)
	GameSession.free_agents = [star]
	var clubs := GameSession._collect_session_clubs()
	var rng := RandomNumberGenerator.new()
	rng.seed = 14
	var swap := TransferMarketScript._find_free_swap(GameSession, clubs, 1, TransferMarketScript._free_position_groups(GameSession.free_agents))
	_assert(not swap.is_empty(), "full squad considers a strong free agent")
	if swap.is_empty():
		GameSession.clear()
		return
	var old_budget := GameSession.get_club_budget(1)
	GameSession.club_budgets[1] = 0
	_assert(TransferMarketScript._find_free_swap(GameSession, clubs, 1, TransferMarketScript._free_position_groups(GameSession.free_agents)).is_empty(), "free transfer still requires money for salary and termination")
	GameSession.club_budgets[1] = old_budget
	star["nationality_country_id"] = 2
	_assert(TransferMarketScript._find_free_swap(GameSession, clubs, 1, TransferMarketScript._free_position_groups(GameSession.free_agents)).is_empty(), "free upgrade cannot bypass the foreign limit")
	star["nationality_country_id"] = 1
	var outgoing: Dictionary = swap["outgoing"]
	_assert(int(outgoing["current_ability"]) == 48, "free signing replaces a weak reserve, not a starter")
	_assert(TransferMarketScript._execute_free_swap(GameSession, clubs, 1, swap, rng), "free-agent swap executes")
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(1)), "swap preserves 20 players and positional minima")
	_assert(star["club_id"] == 1 and GameSession.free_agents.has(outgoing), "incoming and outgoing each have one location")
	_assert(GameSession.get_club_budget(1) == old_budget - int(swap["termination_cost"]), "contract termination compensation is charged")
	# An illegal full squad with a surplus CB can be repaired without selling its core.
	squad = _legal_full_squad(1)
	var changed := false
	for player in squad:
		if player["position"] == "ST" and not changed:
			player["position"] = "CB"
			changed = true
	_load_upgrade_market(squad, _legal_full_squad(2), 820, 300, 2000000, 0)
	GameSession.free_agents = [_player("ST", 1, 500, 65)]
	clubs = GameSession._collect_session_clubs()
	_assert(TransferMarketScript._repair_full_squads(GameSession, clubs, rng) == 1, "filled illegal squad gets its missing position")
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(1)), "repair restores all positional requirements")
	squad = _legal_full_squad(1)
	changed = false
	for player in squad:
		if player["position"] == "CM" and not changed:
			player["position"] = "CB"
			changed = true
	_load_upgrade_market(squad, _legal_full_squad(2), 820, 300, 2000000, 0)
	GameSession.free_agents = [_player("GK", 1, 500, 60)]
	clubs = GameSession._collect_session_clubs()
	_assert(TransferMarketScript._repair_full_squads(GameSession, clubs, rng) == 1, "repair also handles a position above maximum without any missing minimum")
	_assert(PlayerTypesScript.is_squad_shape_legal(GameSession.get_club_players(1)), "repair respects both positional minima and maxima")
	GameSession.clear()
