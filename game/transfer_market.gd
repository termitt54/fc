class_name TransferMarket
extends RefCounted
## Market window: surplus listings, one upgrade bid per club, hole-fill buys,
## then free-agent fill to the day cap. Last day dumps unsold listings.


const CoachTypesScript := preload("res://game/coach_types.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")
const ClubFinanceScript := preload("res://game/club_finance.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")
const YouthGraduationScript := preload("res://game/youth_graduation.gd")

const SQUAD_SIZE := PlayerTypesScript.SQUAD_SIZE
const POS_FLEX := "FLEX"
const LOCK_SEASONS := 2
const LIST_PER_CLUB := 2
const LIST_DEBT_PER_CLUB := 4
const MIN_JOIN_YEARS := 2
const UPGRADE_CA_GAP := 4
const WEAK_LINK_GAP := 6
const UPGRADE_FEE_FACTOR := 1.25


static func run_day(session: Node, rng: RandomNumberGenerator) -> Dictionary:
	if session == null or rng == null:
		return {"signed": 0, "bought": 0, "listed": 0, "unsold": 0, "upgrades": 0, "bids": 0}
	if not session.is_market_day(session.season_day):
		return {"signed": 0, "bought": 0, "listed": 0, "unsold": 0, "upgrades": 0, "bids": 0}

	var clubs: Dictionary = session._collect_session_clubs()
	if clubs.is_empty():
		return {"signed": 0, "bought": 0, "listed": 0, "unsold": 0, "upgrades": 0, "bids": 0}

	var listed := 0
	var profile := {}
	var phase_start := Time.get_ticks_usec()
	if session.season_day == session.MARKET_OPEN_DAY:
		listed = _list_surplus(session, clubs)
	profile["list_surplus_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0

	phase_start = Time.get_ticks_usec()
	var upgrades: Dictionary = _run_upgrade_wave(session, clubs, rng)
	profile["upgrade_wave_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	var bought := int(upgrades.get("bought", 0)) + _run_club_to_club_wave(
		session, clubs, rng, upgrades.get("protected", {})
	)
	profile["club_sales_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0

	phase_start = Time.get_ticks_usec()
	var unsold := 0
	if session.season_day == session.MARKET_LAST_DAY:
		unsold = _release_unsold_listed(session, clubs)
	profile["release_unsold_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0

	phase_start = Time.get_ticks_usec()
	var order: Array = _club_pick_order(session, clubs, rng)
	var signed: int = _fill_from_free_agents(session, clubs, order, rng, false)
	if session.season_day == session.MARKET_LAST_DAY:
		signed += _fill_from_free_agents(session, clubs, order, rng, true)
	profile["free_agent_fill_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0

	return {
		"signed": signed,
		"bought": bought,
		"listed": listed,
		"unsold": unsold,
		"upgrades": int(upgrades.get("bought", 0)),
		"bids": int(upgrades.get("bids", 0)),
		"profile": profile,
	}


static func is_transfer_locked(player: Dictionary, season_number: int) -> bool:
	if not player.has("joined_season"):
		return false
	var joined := int(player.get("joined_season", 0))
	if joined < 1:
		return false
	return season_number - joined < LOCK_SEASONS


static func is_buyable(player: Dictionary, season_number: int) -> bool:
	if typeof(player) != TYPE_DICTIONARY:
		return false
	if bool(player.get("is_youth", false)):
		return false
	if int(player.get("age", 18)) < 18:
		return false
	if is_transfer_locked(player, season_number):
		return false
	return int(player.get("club_id", 0)) > 0


static func _day_target(day: int, _current_size: int = 0) -> int:
	# Ramp 5 → 10 → 15 → 20 → 25 across a 5-day window ending at -1.
	if day >= -1:
		return SQUAD_SIZE
	var open := -5
	var last := -1
	var total := last - open + 1
	var index := day - open + 1
	if index >= total:
		return SQUAD_SIZE
	return int(ceili(float(SQUAD_SIZE) * float(index) / float(total)))


static func _club_pick_order(session: Node, clubs: Dictionary, rng: RandomNumberGenerator) -> Array:
	var rows: Array = []
	for club_id in clubs.keys():
		var id := int(club_id)
		var club: Dictionary = clubs.get(id, {})
		var coach: Dictionary = session.get_club_coach(id)
		rows.append({
			"id": id,
			"skill": CoachTypesScript.transfers_of(coach),
			"rep": int(club.get("reputation", 500)),
			"noise": rng.randf(),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["skill"]) != int(b["skill"]):
			return int(a["skill"]) > int(b["skill"])
		if int(a["rep"]) != int(b["rep"]):
			return int(a["rep"]) > int(b["rep"])
		return float(a["noise"]) < float(b["noise"])
	)
	var order: Array = []
	for row in rows:
		order.append(int(row["id"]))
	return order


static func _fill_from_free_agents(
	session: Node,
	clubs: Dictionary,
	order: Array,
	rng: RandomNumberGenerator,
	relaxed: bool
) -> int:
	var signed := 0
	# Stable original indices preserve candidate order and RNG draws. Signings
	# mark entries consumed; compact once after the wave instead of shifting
	# the entire free-agent array for every contract.
	var agent_index := _build_agent_index(session.free_agents)
	var progressed := true
	while progressed:
		progressed = false
		for club_id in order:
			var id := int(club_id)
			var squad: Array = session.get_club_players(id)
			var target := SQUAD_SIZE if relaxed else _day_target(session.season_day, squad.size())
			if squad.size() >= target:
				continue
			var club: Dictionary = clubs.get(id, {})
			if club.is_empty():
				continue
			if _sign_one(session, rng, id, club, squad, relaxed, agent_index):
				signed += 1
				progressed = true
	_compact_agents(session, agent_index)
	return signed


static func _build_agent_index(agents: Array) -> Dictionary:
	var positions := PackedStringArray()
	var raw_positions := PackedStringArray()
	var nations := PackedInt64Array()
	var reputations := PackedFloat64Array()
	var bases := PackedFloat64Array()
	positions.resize(agents.size())
	raw_positions.resize(agents.size())
	nations.resize(agents.size())
	reputations.resize(agents.size())
	bases.resize(agents.size())
	var groups := {}
	var indices: Array = []
	for i in agents.size():
		var player: Variant = agents[i]
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		positions[i] = position
		raw_positions[i] = str(player.get("position", ""))
		nations[i] = int(player.get("nationality_country_id", 0))
		reputations[i] = float(int(player.get("reputation", 0)))
		var ca := float(int(player.get("current_ability", player.get("overall", 0))))
		var pa := float(int(player.get("potential_ability", ca)))
		bases[i] = ca * 1.15 + pa * 0.22
		if not groups.has(position):
			groups[position] = []
		groups[position].append(i)
		indices.append(i)
	return {"all": indices, "positions": groups, "consumed": {}, "position": positions,
		"raw_position": raw_positions, "nation": nations, "rep": reputations, "base": bases}


static func _compact_agents(session: Node, agent_index: Dictionary) -> void:
	if agent_index["consumed"].is_empty():
		return
	var remaining: Array = []
	for i in session.free_agents.size():
		if not agent_index["consumed"].has(i):
			remaining.append(session.free_agents[i])
	session.free_agents = remaining


static func _sign_one(
	session: Node,
	rng: RandomNumberGenerator,
	club_id: int,
	club: Dictionary,
	squad: Array,
	relaxed: bool,
	agent_index: Dictionary = {}
) -> bool:
	var needed := next_needed_position(squad)
	if needed.is_empty():
		return false
	# Prefer the missing position, then any legal slot. A set foreign cap
	# stays in force on the last day too.
	if _try_sign(session, rng, club_id, club, squad, needed, false, false, agent_index):
		return true
	if needed != POS_FLEX and _try_sign(session, rng, club_id, club, squad, POS_FLEX, relaxed, false, agent_index):
		return true
	return false


static func _try_sign(
	session: Node,
	rng: RandomNumberGenerator,
	club_id: int,
	club: Dictionary,
	squad: Array,
	needed: String,
	relaxed: bool,
	ignore_foreign: bool,
	agent_index: Dictionary = {}
) -> bool:
	if needed.is_empty():
		return false
	var limit := -1 if ignore_foreign else foreign_limit_for_club(session, club_id)
	var coach: Dictionary = session.get_club_coach(club_id)
	var best_index := -1
	var best_score := -99999.0
	var agents: Array = session.free_agents
	# The squad does not change during this candidate scan.
	var legal_positions := {}
	for position in PlayerTypesScript.POSITIONS:
		legal_positions[position] = _position_ok(position, needed, relaxed, squad)
	var foreign_cap_reached := not ignore_foreign and limit >= 0 and foreign_count(squad, club) >= limit
	var skill := float(CoachTypesScript.transfers_of(coach))
	var club_rep := float(int(club.get("reputation", 500)))
	var reach := club_rep + (skill - 10.0) * 28.0
	var noise_span := lerpf(6.0, 1.5, skill / 20.0)
	var club_nation := int(club.get("country_id", 0))
	var indexed := not agent_index.is_empty()
	var positions: PackedStringArray = agent_index.get("position", PackedStringArray())
	var raw_positions: PackedStringArray = agent_index.get("raw_position", PackedStringArray())
	var nations: PackedInt64Array = agent_index.get("nation", PackedInt64Array())
	var reputations: PackedFloat64Array = agent_index.get("rep", PackedFloat64Array())
	var bases: PackedFloat64Array = agent_index.get("base", PackedFloat64Array())
	var indices: Array = range(agents.size()) if agent_index.is_empty() else \
		(agent_index["all"] if needed == POS_FLEX or relaxed else agent_index["positions"].get(needed, []))
	for i in indices:
		if not agent_index.is_empty() and agent_index["consumed"].has(i):
			continue
		var score: float
		if indexed:
			if not bool(legal_positions.get(positions[i], false)):
				continue
			if foreign_cap_reached and nations[i] > 0 and club_nation > 0 and nations[i] != club_nation:
				continue
			var player_rep := reputations[i]
			var overreach := maxf(0.0, player_rep - reach)
			var fit := 1.0 - clampf(absf(player_rep - club_rep) / 1000.0, 0.0, 1.0)
			var pos_bonus := 2.0 if needed == POS_FLEX else (10.0 if raw_positions[i] == needed else 0.0)
			# Same double-precision operations and RNG draws as _score_player.
			score = bases[i] + fit * 30.0 + skill * 0.8 - overreach * (0.12 - skill * 0.003) \
				+ pos_bonus + rng.randf_range(-noise_span, noise_span)
		else:
			var player: Variant = agents[i]
			if typeof(player) != TYPE_DICTIONARY:
				continue
			var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
			if not bool(legal_positions.get(position, false)) or (foreign_cap_reached and is_foreigner(player, club)):
				continue
			score = _score_player(club, coach, player, needed, rng)
		if score > best_score:
			best_score = score
			best_index = i
	if best_index < 0:
		return false
	var signed: Dictionary = agents[best_index]
	if agent_index.is_empty():
		agents.remove_at(best_index)
	else:
		agent_index["consumed"][best_index] = true
	_attach_to_club(session, signed, club_id, club, rng, 0, "свободный агент")
	return true


static func next_needed_position(squad: Array) -> String:
	if squad.size() >= SQUAD_SIZE:
		return ""
	var missing := PlayerTypesScript.missing_required_position(squad)
	if not missing.is_empty():
		return missing
	if PlayerTypesScript.has_open_squad_slot(squad):
		return POS_FLEX
	return ""


static func _eligible(
	player: Dictionary,
	club: Dictionary,
	squad: Array,
	limit: int,
	needed: String,
	relaxed: bool,
	ignore_foreign: bool = false
) -> bool:
	if needed.is_empty():
		return false
	var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	if not _position_ok(position, needed, relaxed, squad):
		return false
	if not ignore_foreign and is_foreigner(player, club) and limit >= 0:
		if foreign_count(squad, club) >= limit:
			return false
	return true


static func _position_ok(position: String, needed: String, relaxed: bool, squad: Array) -> bool:
	if not PlayerTypesScript.can_add_squad_position(squad, position):
		return false
	if needed == POS_FLEX:
		return true
	if position == needed:
		return true
	# Last-day relax: any legal slot, even if a min (FB etc.) is still missing.
	if relaxed:
		return true
	return false


static func is_foreigner(player: Dictionary, club: Dictionary) -> bool:
	var player_nation := int(player.get("nationality_country_id", 0))
	var club_nation := int(club.get("country_id", 0))
	if player_nation < 1 or club_nation < 1:
		return false
	return player_nation != club_nation


static func foreign_count(squad: Array, club: Dictionary) -> int:
	var count := 0
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if is_foreigner(player, club):
			count += 1
	return count


static func foreign_limit_for_club(session: Node, club_id: int) -> int:
	# -1 means the competition sets no cap. 0 means no foreigners.
	# A club in several competitions keeps the strictest real cap.
	var limit := -1
	var found := false
	for unit in session.units:
		if not _unit_has_club(unit, club_id):
			continue
		var rules: Dictionary = unit.get("rules", {})
		var unit_limit := int(rules.get("foreign_players_limit", unit.get("foreign_players_limit", 0)))
		if unit_limit < 0:
			continue
		if not found or unit_limit < limit:
			limit = unit_limit
			found = true
	return limit if found else -1


static func _unit_has_club(unit: Dictionary, club_id: int) -> bool:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	if clubs.has(club_id) or clubs.has(str(club_id)):
		return true
	for division in unit.get("divisions", []):
		if typeof(division) != TYPE_DICTIONARY:
			continue
		for id in division.get("club_ids", []):
			if int(id) == club_id:
				return true
	return false


static func _score_player(
	club: Dictionary,
	coach: Dictionary,
	player: Dictionary,
	needed: String,
	rng: RandomNumberGenerator
) -> float:
	var skill := float(CoachTypesScript.transfers_of(coach))
	var club_rep := float(int(club.get("reputation", 500)))
	var player_rep := float(int(player.get("reputation", 0)))
	var ca := float(int(player.get("current_ability", player.get("overall", 0))))
	var pa := float(int(player.get("potential_ability", ca)))
	var reach := club_rep + (skill - 10.0) * 28.0
	var overreach := maxf(0.0, player_rep - reach)
	var fit := 1.0 - clampf(absf(player_rep - club_rep) / 1000.0, 0.0, 1.0)
	var noise_span := lerpf(6.0, 1.5, skill / 20.0)
	var pos_bonus := 10.0 if str(player.get("position", "")) == needed else 0.0
	if needed == POS_FLEX:
		pos_bonus = 2.0
	return (
		ca * 1.15
		+ pa * 0.22
		+ fit * 30.0
		+ skill * 0.8
		- overreach * (0.12 - skill * 0.003)
		+ pos_bonus
		+ rng.randf_range(-noise_span, noise_span)
	)


static func _attach_to_club(
	session: Node,
	player: Dictionary,
	club_id: int,
	club: Dictionary,
	rng: RandomNumberGenerator,
	fee: int = 0,
	other_club: String = "свободный агент"
) -> void:
	var was_free := int(player.get("club_id", 0)) < 1 \
		or str(player.get("contract_status", "")) == "free_agent"
	PlayerMarketScript.sign_wage(player, club, was_free)
	PlayerStats.begin_club_stint(player, int(session.season_number), club_id, maxi(0, fee))
	player["club_id"] = club_id
	player["contract_status"] = "club"
	player["for_sale"] = false
	player.erase("asking_price")
	var years := _roll_contract_years(rng, int(player.get("age", 24)))
	if int(session.season_number) > 1:
		player["joined_season"] = int(session.season_number)
		years = maxi(years, MIN_JOIN_YEARS)
	player["contract_years"] = years
	var squad: Array = session.players_by_club.get(club_id, [])
	if not session.players_by_club.has(club_id):
		session.players_by_club[club_id] = squad
	var already := false
	for existing in squad:
		if typeof(existing) == TYPE_DICTIONARY and int(existing.get("id", 0)) == int(player.get("id", 0)):
			already = true
			break
	if not already:
		squad.append(player)
		session.players_by_club[club_id] = squad
	var club_name := str(club.get("name", "")).strip_edges()
	if club_name.is_empty():
		club_name = "Клуб #%d" % club_id
	session.transfer_log.append({
		"season": int(session.season_number),
		"day": int(session.season_day),
		"club_id": club_id,
		"club_name": club_name,
		"player_id": int(player.get("id", 0)),
		"player_name": str(player.get("name", "Игрок")),
		"position": str(player.get("position", "")),
		"direction": "in",
		"fee": maxi(0, fee),
		"other_club": other_club,
	})


static func _roll_contract_years(rng: RandomNumberGenerator, age: int) -> int:
	if age >= 34:
		return rng.randi_range(1, 2)
	if age <= 21:
		return rng.randi_range(3, 5)
	return rng.randi_range(1, 4)


static func _list_surplus(session: Node, clubs: Dictionary) -> int:
	var listed := 0
	for club_id in clubs.keys():
		var id := int(club_id)
		var squad: Array = session.get_club_players(id)
		if squad.size() < SQUAD_SIZE:
			continue
		var counts := PlayerTypesScript.count_squad_positions(squad)
		var starters: Dictionary = _squad_market_info(session, id, squad)["starters"]
		var ranked: Array = []
		for player in squad:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if bool(player.get("for_sale", false)):
				continue
			if is_transfer_locked(player, int(session.season_number)):
				continue
			if starters.has(int(player.get("id", 0))):
				continue
			var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
			var have := int(counts.get(pos, 0))
			var minimum := int(PlayerTypesScript.SQUAD_SLOT_MIN.get(pos, 0))
			if have <= minimum:
				continue
			ranked.append(player)
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("current_ability", 0)) < int(b.get("current_ability", 0))
		)
		var cap := LIST_DEBT_PER_CLUB if int(session.get_club_budget(id)) < 0 else LIST_PER_CLUB
		var n := 0
		for player in ranked:
			if n >= cap:
				break
			player["for_sale"] = true
			player["asking_price"] = _player_value(player)
			n += 1
			listed += 1
	return listed


static func _run_upgrade_wave(
	session: Node,
	clubs: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var bought := 0
	var bids := 0
	var protected_ids: Dictionary = {}
	var order: Array = _club_pick_order(session, clubs, rng)
	var quota := maxi(1, int(ceili(float(clubs.size()) / 5.0)))
	var tried_today := 0
	var moved: Dictionary = {}
	# Local to this wave. Deals invalidate both sides before the next buyer.
	var squad_cache := {}
	for club_id in order:
		if tried_today >= quota:
			break
		var id := int(club_id)
		var club: Dictionary = clubs.get(id, {})
		if club.is_empty():
			continue
		if int(club.get("upgrade_bid_season", 0)) == int(session.season_number):
			continue
		if session.get_club_players(id).size() != SQUAD_SIZE:
			continue
		if int(session.get_club_budget(id)) <= 0:
			continue
		var squad: Array = session.get_club_players(id)
		var coach: Dictionary = session.get_club_coach(id)
		var outgoing := _pick_outgoing(session, id, squad, coach)
		if outgoing.is_empty():
			continue
		var target: Dictionary = _find_upgrade_target(
			session, clubs, id, club, coach, outgoing, moved, rng, squad_cache
		)
		club["upgrade_bid_season"] = int(session.season_number)
		if target.is_empty():
			continue
		tried_today += 1
		bids += 1
		var player: Dictionary = target.get("player", {})
		var seller_id: int = int(target.get("seller_id", 0))
		if not bool(target.get("accepted", false)):
			_log_bid(session, id, club, clubs.get(seller_id, {}), player, str(target.get("reason", "отказ")))
			continue
		if _execute_upgrade(session, clubs, id, seller_id, outgoing, player, rng):
			squad_cache.erase(id)
			squad_cache.erase(seller_id)
			bought += 1
			protected_ids[id] = true
			moved[int(player.get("id", 0))] = true
			moved[int(outgoing.get("id", 0))] = true
	return {"bought": bought, "bids": bids, "protected": protected_ids}


static func _pick_outgoing(
	session: Node,
	club_id: int,
	squad: Array,
	coach: Dictionary
) -> Dictionary:
	var best_ca: Dictionary = {}
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		var ca := int(player.get("current_ability", 0))
		if ca > int(best_ca.get(pos, 0)):
			best_ca[pos] = ca
	var ranked: Array = []
	var starters: Dictionary = _squad_market_info(session, club_id, squad)["starters"]
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if is_transfer_locked(player, int(session.season_number)):
			continue
		if starters.has(int(player.get("id", 0))):
			continue
		var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		var ca := int(player.get("current_ability", 0))
		var wants_out := bool(player.get("for_sale", false)) or int(player.get("contract_years", 3)) <= 1
		var gap := int(best_ca.get(pos, ca)) - ca
		if not wants_out and gap < WEAK_LINK_GAP:
			continue
		ranked.append({
			"player": player,
			"wants_out": wants_out,
			"ca": ca,
			"gap": gap,
		})
	if ranked.is_empty():
		return {}
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["wants_out"]) != bool(b["wants_out"]):
			return bool(a["wants_out"])
		if int(a["gap"]) != int(b["gap"]):
			return int(a["gap"]) > int(b["gap"])
		return int(a["ca"]) < int(b["ca"])
	)
	return ranked[0].get("player", {})


static func _find_upgrade_target(
	session: Node,
	clubs: Dictionary,
	buyer_id: int,
	buyer: Dictionary,
	coach: Dictionary,
	outgoing: Dictionary,
	moved: Dictionary,
	rng: RandomNumberGenerator,
	squad_cache: Dictionary = {}
) -> Dictionary:
	var needed := PlayerTypesScript.normalize_position(str(outgoing.get("position", "")))
	var out_ca := int(outgoing.get("current_ability", 0))
	var cap := ClubFinanceScript.max_single_fee(int(session.get_club_budget(buyer_id)))
	if cap <= 0 or needed.is_empty():
		return {}
	var candidates: Array = []
	var buyer_squad: Array = session.get_club_players(buyer_id)
	var buyer_limit := foreign_limit_for_club(session, buyer_id)
	for club_id in clubs.keys():
		var seller_id := int(club_id)
		if seller_id == buyer_id:
			continue
		var seller_squad: Array = session.get_club_players(seller_id)
		if not squad_cache.has(seller_id):
			squad_cache[seller_id] = _squad_market_info(session, seller_id, seller_squad)
		var info: Dictionary = squad_cache[seller_id]
		if int(info["counts"].get(needed, 0)) <= PlayerTypesScript.squad_slot_min(needed):
			continue
		for player in info["positions"].get(needed, []):
			var pid := int(player.get("id", 0))
			if moved.has(pid) or not is_buyable(player, int(session.season_number)):
				continue
			if int(player.get("current_ability", 0)) < out_ca + UPGRADE_CA_GAP:
				continue
			if info["starters"].has(pid):
				continue
			var fee := _upgrade_fee(player)
			if fee > cap:
				continue
			if not _foreign_ok_after_swap(
				buyer_squad,
				buyer,
				outgoing,
				player,
				buyer_limit
			):
				continue
			candidates.append({
				"player": player,
				"seller_id": seller_id,
				"fee": fee,
				"score": _score_player(buyer, coach, player, needed, rng),
			})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	var top: Dictionary = candidates[0]
	var player: Dictionary = top.get("player", {})
	var seller: Dictionary = clubs.get(int(top.get("seller_id", 0)), {})
	if _destination_score(player, buyer, coach) < 0.0:
		top["accepted"] = false
		top["reason"] = "игрок отказал"
		return top
	if not _seller_accepts_upgrade(player, seller, int(top.get("fee", 0))):
		top["accepted"] = false
		top["reason"] = "клуб отказал"
		return top
	top["accepted"] = true
	return top


static func _seller_can_spare(
	session: Node,
	seller_id: int,
	squad: Array,
	player: Dictionary
) -> bool:
	if _is_scheme_starter(session, seller_id, player, squad):
		return false
	var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	var have := 0
	for row in squad:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(row.get("position", ""))) == pos:
			have += 1
	return have > PlayerTypesScript.squad_slot_min(pos)


static func _seller_accepts_upgrade(player: Dictionary, _seller: Dictionary, fee: int) -> bool:
	var value := _player_value(player)
	if bool(player.get("for_sale", false)):
		return fee >= int(round(float(value) * 0.9))
	return fee >= value


static func _upgrade_fee(player: Dictionary) -> int:
	if bool(player.get("for_sale", false)) and int(player.get("asking_price", 0)) > 0:
		return int(player.get("asking_price", 0))
	return maxi(_player_value(player), int(round(float(_player_value(player)) * UPGRADE_FEE_FACTOR)))


static func _foreign_ok_after_swap(
	squad: Array,
	club: Dictionary,
	outgoing: Dictionary,
	incoming: Dictionary,
	limit: int
) -> bool:
	if limit < 0:
		return true
	var count := 0
	var out_id := int(outgoing.get("id", 0))
	for row in squad:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("id", 0)) == out_id:
			continue
		if is_foreigner(row, club):
			count += 1
	if is_foreigner(incoming, club):
		count += 1
	return count <= limit


## Same native-position protection as YouthGraduation.is_starter, computed once.
## Do not persist this data: squad membership and ability may change next wave.
static func _squad_market_info(session: Node, club_id: int, squad: Array) -> Dictionary:
	var coach: Dictionary = session.get_club_coach(club_id)
	var formation := CoachTypesScript.primary_formation_of(coach)
	if formation.is_empty():
		formation = "2-3-2"
	var positions := {}
	var counts := {}
	var starters := {}
	for pos in PlayerTypesScript.POSITIONS:
		counts[pos] = 0
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		if not positions.has(pos):
			positions[pos] = []
		positions[pos].append(player)
	for pos in positions:
		var players: Array = positions[pos]
		counts[pos] = players.size()
		# Keep scan order for random candidate scoring; sort a separate array.
		var ranked := players.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("current_ability", 0)) > int(b.get("current_ability", 0))
		)
		for i in mini(YouthGraduationScript.starter_count(formation, pos), ranked.size()):
			starters[int(ranked[i].get("id", 0))] = true
	return {"positions": positions, "counts": counts, "starters": starters}


static func _is_scheme_starter(
	session: Node,
	club_id: int,
	player: Dictionary,
	squad: Array
) -> bool:
	var coach: Dictionary = session.get_club_coach(club_id)
	var formation := CoachTypesScript.primary_formation_of(coach)
	if formation.is_empty():
		formation = "2-3-2"
	return YouthGraduationScript.is_starter(player, squad, formation)


static func _execute_upgrade(
	session: Node,
	clubs: Dictionary,
	buyer_id: int,
	seller_id: int,
	outgoing: Dictionary,
	incoming: Dictionary,
	rng: RandomNumberGenerator
) -> bool:
	var buyer: Dictionary = clubs.get(buyer_id, {})
	var seller: Dictionary = clubs.get(seller_id, {})
	if buyer.is_empty() or seller.is_empty():
		return false
	var fee := _upgrade_fee(incoming)
	var incoming_id := int(incoming.get("id", 0))
	var outgoing_id := int(outgoing.get("id", 0))
	if not _remove_from_squad(session, seller_id, incoming_id):
		return false
	if not _remove_from_squad(session, buyer_id, outgoing_id):
		# Roll back the seller removal if the outgoing vanished.
		var seller_squad: Array = session.players_by_club.get(seller_id, [])
		seller_squad.append(incoming)
		session.players_by_club[seller_id] = seller_squad
		return false
	session.adjust_club_budget(buyer_id, -fee)
	session.adjust_club_budget(seller_id, fee)
	var seller_name := _club_label(seller, seller_id)
	var buyer_name := _club_label(buyer, buyer_id)
	_log_move(session, seller_id, seller_name, incoming, "out", fee, buyer_name)
	_attach_to_club(session, incoming, buyer_id, buyer, rng, fee, seller_name)
	_release_to_agents(session, buyer_id, buyer_name, outgoing)
	return true


static func _release_to_agents(
	session: Node,
	club_id: int,
	club_name: String,
	player: Dictionary
) -> void:
	player["club_id"] = 0
	player["contract_status"] = "free_agent"
	player["contract_years"] = 0
	player["for_sale"] = false
	player.erase("asking_price")
	session.free_agents.append(player)
	_log_move(session, club_id, club_name, player, "out", 0, "вытеснен")


static func _log_bid(
	session: Node,
	buyer_id: int,
	buyer: Dictionary,
	seller: Dictionary,
	player: Dictionary,
	reason: String
) -> void:
	var seller_name := _club_label(seller, int(seller.get("id", 0)))
	session.transfer_log.append({
		"season": int(session.season_number),
		"day": int(session.season_day),
		"club_id": buyer_id,
		"club_name": _club_label(buyer, buyer_id),
		"player_id": int(player.get("id", 0)),
		"player_name": str(player.get("name", "Игрок")),
		"position": str(player.get("position", "")),
		"direction": "bid",
		"fee": _upgrade_fee(player),
		"other_club": "%s · %s" % [reason, seller_name],
	})


static func _log_move(
	session: Node,
	club_id: int,
	club_name: String,
	player: Dictionary,
	direction: String,
	fee: int,
	other_club: String
) -> void:
	session.transfer_log.append({
		"season": int(session.season_number),
		"day": int(session.season_day),
		"club_id": club_id,
		"club_name": club_name,
		"player_id": int(player.get("id", 0)),
		"player_name": str(player.get("name", "Игрок")),
		"position": str(player.get("position", "")),
		"direction": direction,
		"fee": maxi(0, fee),
		"other_club": other_club,
	})


static func _club_label(club: Dictionary, club_id: int) -> String:
	var name := str(club.get("name", "")).strip_edges()
	if name.is_empty():
		return "Клуб #%d" % club_id
	return name


static func _run_club_to_club_wave(
	session: Node,
	clubs: Dictionary,
	rng: RandomNumberGenerator,
	protected_sellers: Variant = {}
) -> int:
	var protected: Dictionary = protected_sellers if typeof(protected_sellers) == TYPE_DICTIONARY else {}
	var buyers: Dictionary = {}
	for club_id in clubs.keys():
		var id := int(club_id)
		if session.get_club_players(id).size() < SQUAD_SIZE:
			buyers[id] = true
	if buyers.is_empty():
		return 0

	var targets: Array = _collect_buyable_players(session, clubs)
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ra := int(a.get("reputation", 0))
		var rb := int(b.get("reputation", 0))
		if ra != rb:
			return ra > rb
		return int(a.get("current_ability", 0)) > int(b.get("current_ability", 0))
	)

	var bought := 0
	var moved: Dictionary = {}
	# Buyers leave the wave after their first purchase. Their squads, budgets
	# and foreign limits stay unchanged until then (buyers cannot be sellers).
	var buyer_cache := {}
	for player in targets:
		var pid := int(player.get("id", 0))
		if moved.has(pid):
			continue
		var seller_id := int(player.get("club_id", 0))
		if seller_id < 1 or buyers.has(seller_id) or protected.has(seller_id):
			continue
		if not is_buyable(player, int(session.season_number)):
			continue
		var deal: Dictionary = _pick_buyer_for_player(session, clubs, player, seller_id, buyers, rng, buyer_cache)
		if deal.is_empty():
			continue
		if _execute_club_sale(session, clubs, player, seller_id, deal, rng):
			bought += 1
			moved[pid] = true
			buyers.erase(int(deal.get("club_id", 0)))
	return bought


static func _collect_buyable_players(session: Node, clubs: Dictionary) -> Array:
	var out: Array = []
	for club_id in clubs.keys():
		for player in session.get_club_players(int(club_id)):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if is_buyable(player, int(session.season_number)):
				out.append(player)
	return out


static func _pick_buyer_for_player(
	session: Node,
	clubs: Dictionary,
	player: Dictionary,
	seller_id: int,
	buyers: Dictionary,
	rng: RandomNumberGenerator,
	buyer_cache: Dictionary = {}
) -> Dictionary:
	var ask := _asking_price(player)
	var seller: Dictionary = clubs.get(seller_id, {})
	var listed := bool(player.get("for_sale", false))
	var candidates: Array = []
	for buyer_id in buyers.keys():
		var id := int(buyer_id)
		if id == seller_id:
			continue
		var club: Dictionary = clubs.get(id, {})
		if club.is_empty():
			continue
		var squad: Array = session.get_club_players(id)
		if squad.size() >= SQUAD_SIZE:
			continue
		if not buyer_cache.has(id):
			buyer_cache[id] = _buyer_info(session, id, club, squad)
		var info: Dictionary = buyer_cache[id]
		var needed: String = info["needed"]
		var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		if not bool(info["positions"].get(position, false)) or (bool(info["foreign_cap"]) and is_foreigner(player, club)):
			continue
		var cap: int = info["cap"]
		if ask > cap:
			continue
		var coach: Dictionary = info["coach"]
		if _destination_score(player, club, coach) < 0.0:
			continue
		if not listed and not _seller_accepts(player, seller, ask):
			continue
		if not _club_wants_player(session, id, club, coach, player, needed, rng):
			continue
		candidates.append({
			"club_id": id,
			"score": _destination_score(player, club, coach),
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates[0]


static func _buyer_info(session: Node, id: int, club: Dictionary, squad: Array) -> Dictionary:
	var needed := next_needed_position(squad)
	var legal := {}
	for position in PlayerTypesScript.POSITIONS:
		legal[position] = not needed.is_empty() and _position_ok(position, needed, false, squad)
	var limit := foreign_limit_for_club(session, id)
	return {"needed": needed, "positions": legal,
		"foreign_cap": limit >= 0 and foreign_count(squad, club) >= limit,
		"cap": ClubFinanceScript.max_single_fee(int(session.get_club_budget(id))),
		"coach": session.get_club_coach(id)}


static func _club_wants_player(
	session: Node,
	club_id: int,
	club: Dictionary,
	coach: Dictionary,
	player: Dictionary,
	needed: String,
	rng: RandomNumberGenerator
) -> bool:
	var skill := CoachTypesScript.transfers_of(coach)
	var wishlist := 2 + int(skill / 5) + maxi(1, SQUAD_SIZE - session.get_club_players(club_id).size())
	var score := _score_player(club, coach, player, needed, rng)
	# Weak coaches miss targets more often; a low score is "not on the list".
	var bar := 40.0 - float(skill) * 1.2
	return score >= bar and wishlist > 0


static func _seller_accepts(player: Dictionary, _seller: Dictionary, ask: int) -> bool:
	var value := _player_value(player)
	if bool(player.get("for_sale", false)):
		return ask >= int(round(float(value) * 0.9))
	var ca := int(player.get("current_ability", 0))
	var stubborn := 1.35
	if ca >= 70:
		stubborn = 1.8
	return ask >= int(round(float(value) * stubborn))


static func _asking_price(player: Dictionary) -> int:
	if int(player.get("asking_price", 0)) > 0:
		return int(player.get("asking_price", 0))
	var value := _player_value(player)
	if bool(player.get("for_sale", false)):
		return value
	var ca := int(player.get("current_ability", 0))
	var mult := 1.4
	if ca >= 70:
		mult = 2.0
	return maxi(value, int(round(float(value) * mult)))


static func _player_value(player: Dictionary) -> int:
	return maxi(5000, int(player.get("value", 0)))


static func _destination_score(player: Dictionary, club: Dictionary, coach: Dictionary) -> float:
	var skill := float(CoachTypesScript.transfers_of(coach))
	var club_rep := float(int(club.get("reputation", 500)))
	var player_rep := float(int(player.get("reputation", 0)))
	var reach := club_rep + (skill - 10.0) * 28.0
	if player_rep > reach + 90.0:
		return -1.0
	var fit := 1.0 - clampf(absf(player_rep - club_rep) / 1000.0, 0.0, 1.0)
	return club_rep * 0.5 + fit * 40.0 + skill


static func _execute_club_sale(
	session: Node,
	clubs: Dictionary,
	player: Dictionary,
	seller_id: int,
	deal: Dictionary,
	rng: RandomNumberGenerator
) -> bool:
	var buyer_id := int(deal.get("club_id", 0))
	var fee := _asking_price(player)
	var buyer: Dictionary = clubs.get(buyer_id, {})
	var seller: Dictionary = clubs.get(seller_id, {})
	if buyer.is_empty() or seller.is_empty():
		return false
	if not _remove_from_squad(session, seller_id, int(player.get("id", 0))):
		return false
	session.adjust_club_budget(buyer_id, -fee)
	session.adjust_club_budget(seller_id, fee)
	var seller_name := str(seller.get("name", "")).strip_edges()
	if seller_name.is_empty():
		seller_name = "Клуб #%d" % seller_id
	var buyer_name := str(buyer.get("name", "")).strip_edges()
	if buyer_name.is_empty():
		buyer_name = "Клуб #%d" % buyer_id
	session.transfer_log.append({
		"season": int(session.season_number),
		"day": int(session.season_day),
		"club_id": seller_id,
		"club_name": seller_name,
		"player_id": int(player.get("id", 0)),
		"player_name": str(player.get("name", "Игрок")),
		"position": str(player.get("position", "")),
		"direction": "out",
		"fee": fee,
		"other_club": buyer_name,
	})
	_attach_to_club(session, player, buyer_id, buyer, rng, fee, seller_name)
	return true


static func _remove_from_squad(session: Node, club_id: int, player_id: int) -> bool:
	var squad: Array = session.players_by_club.get(club_id, [])
	var kept: Array = []
	var found := false
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if int(player.get("id", 0)) == player_id:
			found = true
			continue
		kept.append(player)
	if not found:
		return false
	session.players_by_club[club_id] = kept
	return true


static func _release_unsold_listed(session: Node, clubs: Dictionary) -> int:
	var unsold := 0
	for club_id in clubs.keys():
		var id := int(club_id)
		var club: Dictionary = clubs.get(id, {})
		var kept: Array = []
		for player in session.get_club_players(id):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if bool(player.get("for_sale", false)):
				player["for_sale"] = false
				player.erase("asking_price")
				player["club_id"] = 0
				player["contract_status"] = "free_agent"
				player["contract_years"] = 0
				session.free_agents.append(player)
				unsold += 1
				var club_name := str(club.get("name", "")).strip_edges()
				if club_name.is_empty():
					club_name = "Клуб #%d" % id
				session.transfer_log.append({
					"season": int(session.season_number),
					"day": int(session.season_day),
					"club_id": id,
					"club_name": club_name,
					"player_id": int(player.get("id", 0)),
					"player_name": str(player.get("name", "Игрок")),
					"position": str(player.get("position", "")),
					"direction": "out",
					"fee": 0,
					"other_club": "не продан",
				})
			else:
				kept.append(player)
		session.players_by_club[id] = kept
	return unsold
