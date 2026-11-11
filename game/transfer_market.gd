class_name TransferMarket
extends RefCounted
## Market window: surplus listings, one upgrade bid per club, hole-fill buys,
## then free-agent fill to the day cap. Unexpired unsold contracts are retained.


const CoachTypesScript := preload("res://game/coach_types.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")
const ClubFinanceScript := preload("res://game/club_finance.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")
const YouthGraduationScript := preload("res://game/youth_graduation.gd")
const Offer := preload("res://game/player_offer.gd")

const SQUAD_SIZE := PlayerTypesScript.SQUAD_SIZE
const POS_FLEX := "FLEX"
const LOCK_SEASONS := 2
const LIST_PER_CLUB := 2
const LIST_DEBT_PER_CLUB := 4
const MIN_JOIN_YEARS := 2
const UPGRADE_CA_GAP := 4
const WEAK_LINK_GAP := 6
const UPGRADE_FEE_FACTOR := 1.25
const TARGET_PAID_SHARE := 0.325
const STARTER_COVER_CA_GAP := 7


## Target genuine completed arrivals, not bids or the duplicate seller log.
## Vacancies anticipate the free signings still due in this market window.
static func paid_allowance(session: Node, clubs: Dictionary) -> int:
	var arrivals := 0
	var paid := 0
	for i in range(session.transfer_log.size() - 1, -1, -1):
		var entry: Dictionary = session.transfer_log[i]
		if int(entry.get("season", 0)) < int(session.season_number):
			break
		if int(entry.get("season", 0)) == int(session.season_number) and str(entry.get("direction", "")) == "in":
			arrivals += 1
			if int(entry.get("fee", 0)) > 0:
				paid += 1
	var vacancies := 0
	for id in clubs:
		vacancies += maxi(0, SQUAD_SIZE - session.get_club_players(int(id)).size())
	if arrivals + vacancies == 0:
		return 1 # An otherwise settled window may still start with a real upgrade.
	return maxi(0, int(ceil(float(arrivals + vacancies) * TARGET_PAID_SHARE)) - paid)


static func run_day(session: Node, rng: RandomNumberGenerator) -> Dictionary:
	if session == null or rng == null:
		return {"signed":0,"bought":0,"listed":0,"unsold":0,"upgrades":0,"bids":0}
	var job: RefCounted=load("res://game/transfer_market_job.gd").new(load("res://game/transfer_market.gd"),session,rng)
	while not job.step(): pass
	return job.result


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
	# Ramp to the 20-player squad cap across a 5-day window ending at -1.
	if day >= -1:
		return SQUAD_SIZE
	var open := -5
	var last := -1
	var total := last - open + 1
	var index := day - open + 1
	if index >= total:
		return SQUAD_SIZE
	return int(ceili(float(SQUAD_SIZE) * float(index) / float(total)))


static func _club_pick_order(_session: Node,clubs: Dictionary,rng: RandomNumberGenerator) -> Array:
	# Traversal order grants no reputation privilege. Actual destinations are
	# settled from simultaneous competing offers in the market job.
	var ids: Array=clubs.keys()
	ids.sort()
	for i in range(ids.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap: Variant=ids[i];ids[i]=ids[j];ids[j]=swap
	return ids


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
	var agent_index := _build_agent_index(session.free_agents, Offer.world_top_reputation(clubs))
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


static func _build_agent_index(agents: Array, world_top_reputation: int = 0) -> Dictionary:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.agent_index(agents,world_top_reputation)
	var positions := PackedStringArray()
	var raw_positions := PackedStringArray()
	var nations := PackedInt64Array()
	var reputations := PackedFloat64Array()
	var bases := PackedFloat64Array()
	var minimum_reputations := PackedFloat64Array()
	var minimum_qualities := PackedFloat64Array()
	positions.resize(agents.size())
	raw_positions.resize(agents.size())
	nations.resize(agents.size())
	reputations.resize(agents.size())
	bases.resize(agents.size())
	minimum_reputations.resize(agents.size())
	minimum_qualities.resize(agents.size())
	var groups := {}
	var indices: Array = []
	for i in agents.size():
		var player: Variant = agents[i]
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		var reservations := Offer.profile(player, world_top_reputation)
		minimum_reputations[i] = float(reservations["minimum_club_reputation"])
		minimum_qualities[i] = float(reservations["minimum_squad_ability"])
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
	return {"world_top_reputation": world_top_reputation, "all": indices, "positions": groups, "consumed": {}, "position": positions,
		"raw_position": raw_positions, "nation": nations, "rep": reputations, "base": bases,
		"minimum_reputation": minimum_reputations, "minimum_quality": minimum_qualities}


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
	# Recruit the best available player for any mandatory hole. Filling keepers
	# first used every foreign slot before a club even considered its attack.
	return _try_sign(session, rng, club_id, club, squad, POS_FLEX, relaxed, false, agent_index)


## The academy and reserve are existing registered club players. If recruitment
## leaves a hole, promote real cover instead of entering a season undermanned.
static func _promote_internal_cover(session: Node, club_id: int) -> int:
	var squad: Array = session.get_club_players(club_id)
	var promoted := 0
	var club: Dictionary = session.get_club_identity(club_id)
	var cap := foreign_limit_for_club(session,club_id)
	var pools: Array = [session.get_club_reserve_players(club_id), session.get_club_youth_players(club_id)]
	for pool in pools:
		while squad.size() < SQUAD_SIZE:
			var missing := PlayerTypesScript.missing_required_position(squad)
			var counts := PlayerTypesScript.count_squad_positions(squad)
			var best: Dictionary = {}
			for player in pool:
				var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
				if not PlayerTypesScript.can_add_squad_position(squad,position) or (not missing.is_empty() and int(counts.get(position,0))>=PlayerTypesScript.squad_slot_min(position)):
					continue
				if cap>=0 and is_foreigner(player,club) and foreign_count(squad,club)>=cap:
					continue
				if best.is_empty() or PlayerMarketScript.ability_of(player)>PlayerMarketScript.ability_of(best):
					best = player
			if best.is_empty():
				break
			pool.erase(best)
			YouthGraduationScript.prepare_first_team(best)
			best["contract_years"] = maxi(2,int(best.get("contract_years",0)))
			PlayerMarketScript.sign_wage(best,club,false)
			squad.append(best)
			promoted += 1
	return promoted


static func _try_sign(
	session: Node,
	rng: RandomNumberGenerator,
	club_id: int,
	club: Dictionary,
	squad: Array,
	needed: String,
	relaxed: bool,
	ignore_foreign: bool,
	agent_index: Dictionary = {},
	proposal: Dictionary = {}
) -> bool:
	if needed.is_empty():
		return false
	var limit := -1 if ignore_foreign else foreign_limit_for_club(session, club_id)
	var coach: Dictionary = session.get_club_coach(club_id)
	var best_index := -1
	var best_score := -99999.0
	var agents: Array = session.free_agents
	var native_reserves: Dictionary = agent_index.get("native_reserves", {})
	if not agent_index.has("native_reserves"):
		native_reserves = _build_native_reserves(session)
		if not agent_index.is_empty():
			agent_index["native_reserves"] = native_reserves
	# The squad does not change during this candidate scan.
	var legal_positions := {}
	for position in PlayerTypesScript.POSITIONS:
		legal_positions[position] = _position_ok(position, needed, relaxed, squad)
	var foreign_cap_reached := not ignore_foreign and limit >= 0 and foreign_count(squad, club) >= limit
	var skill := float(CoachTypesScript.transfers_of(coach))
	var club_rep := Offer.Attraction.value(club)
	var reach := club_rep + (skill - 10.0) * 28.0
	var noise_span := lerpf(6.0, 1.5, skill / 20.0)
	var club_nation := int(club.get("country_id", 0))
	var indexed := not agent_index.is_empty()
	var offer_context := _offer_context(squad)
	# The first few keepers/defenders do not describe the quality of a club
	# assembling its very first team. Prestige and wage demands still apply.
	if int(session.season_number) == 1 and int(session.season_day) < 1 and squad.size() < SQUAD_SIZE:
		offer_context["squad_ability"] = -1.0
	offer_context["world_top_reputation"] = int(agent_index.get("world_top_reputation", 0))
	offer_context["free_agent"] = true
	var talks := float(CoachTypesScript.negotiations_of(coach) - 10) * 2.0
	var squad_quality := float(offer_context["squad_ability"])
	var minimum_reputations: PackedFloat64Array = agent_index.get("minimum_reputation", PackedFloat64Array())
	var minimum_qualities: PackedFloat64Array = agent_index.get("minimum_quality", PackedFloat64Array())
	var positions: PackedStringArray = agent_index.get("position", PackedStringArray())
	var raw_positions: PackedStringArray = agent_index.get("raw_position", PackedStringArray())
	var nations: PackedInt64Array = agent_index.get("nation", PackedInt64Array())
	var reputations: PackedFloat64Array = agent_index.get("rep", PackedFloat64Array())
	var bases: PackedFloat64Array = agent_index.get("base", PackedFloat64Array())
	var indices: Array = range(agents.size()) if agent_index.is_empty() else \
		(agent_index["all"] if needed == POS_FLEX or relaxed else agent_index["positions"].get(needed, []))
	var reservation_cache := {}
	var native: Variant = NativeSimulation.core(false)
	if indexed and native != null:
		best_index = int(native.choose_agent(agents, agent_index, {
			"club": club, "club_id": club_id, "context": offer_context,
			"legal": legal_positions, "reserves": native_reserves, "indices": indices,
			"skill": int(skill), "negotiations": CoachTypesScript.negotiations_of(coach),
			"foreign_cap": foreign_cap_reached, "needed": needed,
		}, rng))
	else:
		for i in indices:
			if not agent_index.is_empty() and agent_index["consumed"].has(i):
				continue
			if typeof(agents[i]) != TYPE_DICTIONARY:
				continue
			var candidate: Dictionary = agents[i]
			var candidate_position := str(positions[i]) if indexed else PlayerTypesScript.normalize_position(str(candidate.get("position", "")))
			if not bool(legal_positions.get(candidate_position, false)):
				continue
			var candidate_nation := int(nations[i]) if indexed else int(candidate.get("nationality_country_id", 0))
			if foreign_cap_reached and candidate_nation > 0 and club_nation > 0 and candidate_nation != club_nation:
				continue
			var reservation_key := "%s:%s" % [candidate.get("nationality_country_id", 0), candidate.get("position", "")]
			if not reservation_cache.has(reservation_key):
				reservation_cache[reservation_key] = _native_reserved(candidate, club_nation, native_reserves, club_id)
			if bool(reservation_cache[reservation_key]):
				continue
			var score: float
			if indexed:
				# Same reservations as PlayerOffer, computed once for the pool.
				if club_rep + talks < minimum_reputations[i] or (squad_quality >= 0.0 and squad_quality < minimum_qualities[i]):
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
				if not Offer.evaluate(player, club, coach, offer_context)["accepted"]:
					continue
				score = _score_player(club, coach, player, needed, rng)
			if score > best_score:
				var wage_candidate: Dictionary = agents[i]
				offer_context["offer_wage"] = PlayerMarketScript.wage_for_move(wage_candidate, club, true)
				var wage_accepted: bool = Offer.evaluate(wage_candidate, club, coach, offer_context)["accepted"]
				offer_context.erase("offer_wage")
				if not wage_accepted:
					continue
				best_score = score
				best_index = i
	if best_index < 0:
		return false
	if bool(proposal.get("probe",false)):
		proposal["index"]=best_index
		return true
	return _accept_agent(session,rng,club_id,club,best_index,agent_index)

static func _accept_agent(session: Node,rng: RandomNumberGenerator,club_id: int,club: Dictionary,best_index: int,agent_index: Dictionary) -> bool:
	var agents: Array=session.free_agents
	if best_index<0 or best_index>=agents.size() or agent_index.get("consumed",{}).has(best_index):return false
	var signed: Dictionary=agents[best_index]
	var squad: Array=session.get_club_players(club_id)
	if int(signed.get("club_id",0))!=0 or not _eligible(signed,club,squad,foreign_limit_for_club(session,club_id),POS_FLEX,true):return false
	var native_reserves: Dictionary=agent_index.get("native_reserves",{})
	var club_nation := int(club.get("country_id",0))
	if _native_reserved(signed,club_nation,native_reserves,club_id):return false
	if agent_index.is_empty():
		agents.remove_at(best_index)
	else:
		agent_index["consumed"][best_index] = true
	_attach_to_club(session, signed, club_id, club, rng, 0, "свободный агент")
	var nation := int(signed.get("nationality_country_id", 0))
	if nation > 0 and native_reserves.has(nation):
		var supply: Dictionary = native_reserves[nation]["supply"]
		var position := PlayerTypesScript.normalize_position(str(signed.get("position", "")))
		supply[position] = maxi(0, int(supply.get(position, 0)) - 1)
	if native_reserves.has(club_nation):
		_update_native_reserve(session, club_id, native_reserves[club_nation])
	if native_reserves.has(0):
		var supply: Dictionary = native_reserves[0]["supply"]
		var position := PlayerTypesScript.normalize_position(str(signed.get("position", "")))
		supply[position] = maxi(0, int(supply.get(position, 0)) - 1)
		_update_native_reserve(session, club_id, native_reserves[0])
	return true


## Protect the domestic players that capped clubs still need before exporting
## them. No cap is waived and no extra players are generated.
static func _build_native_reserves(session: Node) -> Dictionary:
	# Scarcity also exists after retirement and expired contracts. Reserving only
	# the supply needed to satisfy mandatory roster/cap constraints prevents an
	# optional signing elsewhere from leaving a club unable to recruit legally.
	var reserves := {0: {"clubs": [], "supply": {}, "demand": {}, "total_need": 0}}
	for club in session._collect_session_clubs().values():
		var cid := int(club.get("id", 0))
		var nation := int(club.get("country_id", 0))
		var cap := foreign_limit_for_club(session, cid)
		reserves[0]["clubs"].append({"id": cid, "club": {"country_id": 0}, "cap": 0})
		if cid <= 0 or nation <= 0 or cap < 0 or cap >= SQUAD_SIZE:
			continue
		if not reserves.has(nation):
			reserves[nation] = {"clubs": [], "supply": {}, "demand": {}, "total_need": 0}
		reserves[nation]["clubs"].append({"id": cid, "club": club, "cap": cap})
	for player in session.free_agents:
		var global_position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		reserves[0]["supply"][global_position] = int(reserves[0]["supply"].get(global_position, 0)) + 1
		var nation := int(player.get("nationality_country_id", 0))
		if nation > 0 and reserves.has(nation):
			var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
			var supply: Dictionary = reserves[nation]["supply"]
			supply[position] = int(supply.get(position, 0)) + 1
	for nation in reserves:
		_refresh_native_reserve(session, int(nation), reserves[nation])
	return reserves


static func _refresh_native_reserve(session: Node, _nation: int, reserve: Dictionary) -> void:
	reserve["demand"] = {}
	reserve["capacity"] = {}
	reserve["club_state"] = {}
	reserve["club_entries"] = {}
	reserve["total_need"] = 0
	for entry in reserve["clubs"]:
		reserve["club_entries"][int(entry["id"])] = entry
		_update_native_reserve(session, int(entry["id"]), reserve)


static func _update_native_reserve(session: Node, club_id: int, reserve: Dictionary) -> void:
	if not reserve["club_entries"].has(club_id):
		return
	var entry: Dictionary = reserve["club_entries"][club_id]
	var previous: Dictionary = reserve["club_state"].get(club_id, {})
	var old_need := int(previous.get("need", 0))
	var old_counts: Dictionary = previous.get("counts", {})
	var squad: Array = session.get_club_players(club_id)
	var native_count := squad.size() - foreign_count(squad, entry["club"])
	var needed := maxi(0, SQUAD_SIZE - int(entry["cap"]) - native_count)
	var counts := PlayerTypesScript.count_squad_positions(squad)
	reserve["total_need"] += needed - old_need
	reserve["club_state"][club_id] = {"need": needed, "counts": counts}
	for position in PlayerTypesScript.POSITIONS:
		var missing := mini(maxi(0, PlayerTypesScript.squad_slot_min(position) - int(counts.get(position, 0))), needed)
		var old_missing := mini(maxi(0, PlayerTypesScript.squad_slot_min(position) - int(old_counts.get(position, 0))), old_need)
		reserve["demand"][position] = int(reserve["demand"].get(position, 0)) + missing - old_missing
		var capacity := mini(maxi(0, PlayerTypesScript.squad_slot_max(position) - int(counts.get(position, 0))), needed)
		var old_capacity := mini(maxi(0, PlayerTypesScript.squad_slot_max(position) - int(old_counts.get(position, 0))), old_need)
		reserve["capacity"][position] = int(reserve["capacity"].get(position, 0)) + capacity - old_capacity


static func _native_reserved(player: Dictionary, destination_nation: int, reserves: Dictionary, destination_club: int = 0) -> bool:
	if reserves.has(0) and _reserve_blocks(player, destination_club, reserves[0]):
		return true
	var nation := int(player.get("nationality_country_id", 0))
	if nation != destination_nation and reserves.has(destination_nation):
		if _reserve_blocks(player, destination_club, reserves[destination_nation], false, false):
			return true
	if nation <= 0 or not reserves.has(nation):
		return false
	var reserve: Dictionary = reserves[nation]
	return _reserve_blocks(player, destination_club if nation == destination_nation else 0, reserve)


static func _reserve_blocks(player: Dictionary, destination_club: int, reserve: Dictionary, consume_supply: bool = true, native_incoming: bool = true) -> bool:
	var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	var supply: Dictionary = reserve["supply"]
	var own: Dictionary = reserve["club_state"].get(destination_club, {})
	var need := int(own.get("need", 0))
	var counts: Dictionary = own.get("counts", {})
	var demand := int(reserve["demand"].get(position, 0))
	var own_missing := maxi(0, PlayerTypesScript.squad_slot_min(position) - int(counts.get(position, 0))) if need > 0 else 0
	var demand_after := demand - int(own_missing > 0)
	var available := int(supply.get(position, 0))
	if maxi(0, demand_after - available + int(consume_supply)) > maxi(0, demand - available):
		return true
	var usable_before := 0
	var usable_after := 0
	for code in PlayerTypesScript.POSITIONS:
		var capacity := int(reserve["capacity"].get(code, 0))
		var capacity_after := capacity
		if need > 0:
			var room := maxi(0, PlayerTypesScript.squad_slot_max(code) - int(counts.get(code, 0)))
			capacity_after += mini(maxi(0, room - int(code == position)), need - int(native_incoming)) - mini(room, need)
		usable_before += mini(int(supply.get(code, 0)), capacity)
		usable_after += mini(maxi(0, int(supply.get(code, 0)) - int(consume_supply and code == position)), capacity_after)
	var total_need := int(reserve["total_need"])
	return maxi(0, total_need - int(need > 0 and native_incoming) - usable_after) > maxi(0, total_need - usable_before)


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
	var missing := PlayerTypesScript.missing_required_position(squad)
	if not missing.is_empty():
		var counts := PlayerTypesScript.count_squad_positions(squad)
		return int(counts.get(position, 0)) < PlayerTypesScript.squad_slot_min(position)
	return needed == POS_FLEX or position == needed


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
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.score_transfer(club,player,CoachTypesScript.transfers_of(coach),needed,rng)
	var skill := float(CoachTypesScript.transfers_of(coach))
	var club_rep := Offer.Attraction.value(club)
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
	player.erase("free_agent_seasons")
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


static func _run_upgrade_wave(session: Node,clubs: Dictionary,rng: RandomNumberGenerator) -> Dictionary:
	var planner: RefCounted=load("res://game/transfer_planner.gd").new(load("res://game/transfer_market.gd"),session,clubs,rng)
	while not planner.step():pass
	var result: Dictionary=planner.result.duplicate()
	result["protected"]=planner.protected
	return result


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
	var world_top := Offer.world_top_reputation(clubs)
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
			if not _seller_can_spare(session, seller_id, seller_squad, player):
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
			var context := _offer_context(buyer_squad, int(round(Offer.Attraction.value(clubs[seller_id]))))
			context["world_top_reputation"] = world_top
			var player_accepts := _destination_score(player, buyer, coach, context) >= 0.0
			candidates.append({
				"player_accepts": player_accepts,
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
	for candidate in candidates:
		if bool(candidate["player_accepts"]):
			top = candidate
			break
	if not bool(top["player_accepts"]):
		top["accepted"] = false
		top["reason"] = "игрок отказал"
		return top
	var player: Dictionary = top.get("player", {})
	var seller: Dictionary = clubs.get(int(top.get("seller_id", 0)), {})
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
	var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	var have := 0
	var peers: Array = []
	for row in squad:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(row.get("position", ""))) == pos:
			have += 1
			if int(row.get("id", 0)) != int(player.get("id", 0)):
				peers.append(int(row.get("current_ability", 0)))
	if have <= PlayerTypesScript.squad_slot_min(pos):
		return false
	if _is_scheme_starter(session, seller_id, player, squad):
		peers.sort()
		peers.reverse()
		var starters := YouthGraduationScript.starter_count("3-2-2", pos)
		if peers.size() < starters or int(peers[starters - 1]) < int(player.get("current_ability", 0)) - STARTER_COVER_CA_GAP:
			return false
	return true

static func _seller_can_spare_info(info: Dictionary,player: Dictionary) -> bool:
	var pos := PlayerTypesScript.normalize_position(str(player.get("position","")))
	if int(info.counts.get(pos,0))<=PlayerTypesScript.squad_slot_min(pos):return false
	if not info.starters.has(int(player.id)):return true
	var peers := []
	for row in info.positions.get(pos,[]):
		if int(row.id)!=int(player.id):peers.append(int(row.get("current_ability",0)))
	peers.sort();peers.reverse()
	var n := YouthGraduationScript.starter_count("3-2-2",pos)
	return peers.size()>=n and int(peers[n-1])>=int(player.get("current_ability",0))-STARTER_COVER_CA_GAP


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
		formation = "3-2-2"
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
		formation = "3-2-2"
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
	if not _seller_can_spare(session, seller_id, session.get_club_players(seller_id), incoming):
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
	_protected_sellers: Variant = {}
) -> int:
	var allowance := paid_allowance(session, clubs)
	if allowance <= 0:
		return 0
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
	# Buyers may make several needed purchases. Invalidate both sides' cached
	# budgets, foreign counts and positions after every completed deal.
	var buyer_cache := {}
	for player in targets:
		if bought >= allowance:
			break
		var pid := int(player.get("id", 0))
		if moved.has(pid):
			continue
		var seller_id := int(player.get("club_id", 0))
		if seller_id < 1:
			continue
		if not is_buyable(player, int(session.season_number)):
			continue
		var deal: Dictionary = _pick_buyer_for_player(session, clubs, player, seller_id, buyers, rng, buyer_cache)
		if deal.is_empty():
			continue
		if _execute_club_sale(session, clubs, player, seller_id, deal, rng):
			bought += 1
			moved[pid] = true
			var buyer_id := int(deal.get("club_id", 0))
			buyer_cache.erase(buyer_id)
			buyer_cache.erase(seller_id)
			if session.get_club_players(buyer_id).size() >= SQUAD_SIZE:
				buyers.erase(buyer_id)
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
	if not _seller_can_spare(session, seller_id, session.get_club_players(seller_id), player):
		return {}
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
			buyer_cache[id] = _buyer_info(session, id, club, squad, Offer.world_top_reputation(clubs))
		var info: Dictionary = buyer_cache[id]
		var needed: String = info["needed"]
		var position := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		if not bool(info["positions"].get(position, false)) or (bool(info["foreign_cap"]) and is_foreigner(player, club)):
			continue
		var cap: int = info["cap"]
		if ask > cap:
			continue
		var coach: Dictionary = info["coach"]
		var offer_context: Dictionary = info["offer_context"]
		offer_context["source_reputation"] = int(round(Offer.Attraction.value(seller)))
		var destination := _destination_score(player, club, coach, offer_context)
		if destination < 0.0:
			continue
		if not listed and not _seller_accepts(player, seller, ask):
			continue
		if not _club_wants_player(session, id, club, coach, player, needed, rng):
			continue
		candidates.append({
			"club_id": id,
			"score": destination,
		})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["score"]) > float(b["score"])
	)
	return candidates[0]


static func _buyer_info(session: Node, id: int, club: Dictionary, squad: Array, world_top_reputation: int = 0) -> Dictionary:
	var needed := next_needed_position(squad)
	var legal := {}
	for position in PlayerTypesScript.POSITIONS:
		legal[position] = not needed.is_empty() and _position_ok(position, needed, false, squad)
	var limit := foreign_limit_for_club(session, id)
	return {"needed": needed, "positions": legal,
		"offer_context": _offer_context(squad, 0, world_top_reputation),
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


static func _destination_score(player: Dictionary, club: Dictionary, coach: Dictionary, context: Dictionary = {}) -> float:
	context["offer_wage"] = PlayerMarketScript.wage_for_move(player, club)
	return float(Offer.evaluate(player, club, coach, context)["score"])

static func _offer_context(squad: Array, source_reputation: int = 0, world_top_reputation: int = 0) -> Dictionary:
	var abilities: Array = []
	for player in squad:
		if typeof(player) == TYPE_DICTIONARY:
			abilities.append(PlayerMarketScript.ability_of(player))
	abilities.sort()
	abilities.reverse()
	var count := mini(8, abilities.size())
	var total := 0.0
	for i in count:
		total += float(abilities[i])
	return {"squad_ability": total / float(count) if count > 0 else -1.0, "source_reputation": source_reputation, "world_top_reputation": world_top_reputation}


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
	if fee > ClubFinanceScript.max_single_fee(int(session.get_club_budget(buyer_id))):
		return false
	if not _seller_can_spare(session, seller_id, session.get_club_players(seller_id), player):
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
		var remaining: Array = session.get_club_players(id).duplicate()
		for player in session.get_club_players(id):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if bool(player.get("for_sale", false)):
				if not _seller_can_spare(session, id, remaining, player):
					player["for_sale"] = false
					player.erase("asking_price")
					kept.append(player)
					continue
				# An unsold listing is not an expired contract. Preserve the
				# asset for the next window instead of gifting it to free agents.
				if int(player.get("contract_years", 0)) > 0:
					kept.append(player)
					continue
				remaining.erase(player)
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


## Reuse position groups across buyers; consumed dictionaries change club_id.
static func _free_position_groups(agents: Array) -> Dictionary:
	var groups := {}
	for player in agents:
		if typeof(player) != TYPE_DICTIONARY or int(player.get("age", 18)) < 18 or bool(player.get("is_youth", false)):
			continue
		var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
		if not groups.has(pos):
			groups[pos] = []
		groups[pos].append(player)
	for pos in groups:
		groups[pos].sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return PlayerMarketScript.ability_of(a) > PlayerMarketScript.ability_of(b))
	return groups

static func _termination_cost(session: Node, player: Dictionary) -> int:
	var paid := 1 if int(session.wages_paid_for_season) == int(session.season_number) else 0
	return maxi(0, int(player.get("contract_years", 0)) - paid) * int(player.get("wage", 0))

static func _find_free_swap(session: Node, clubs: Dictionary, cid: int, groups: Dictionary, required: String = "", outgoing_position: String = "") -> Dictionary:
	var club: Dictionary = clubs[cid]
	var squad: Array = session.get_club_players(cid)
	var info := _squad_market_info(session, cid, squad)
	var context := _offer_context(squad, 0, Offer.world_top_reputation(clubs))
	context["role"] = "first_team"
	var coach: Dictionary = session.get_club_coach(cid)
	var limit := foreign_limit_for_club(session, cid)
	var best := {}
	var best_gain := -INF
	for outgoing in squad:
		var out_id := int(outgoing.get("id", 0))
		if info["starters"].has(out_id) or is_transfer_locked(outgoing, int(session.season_number)):
			continue
		var pos := PlayerTypesScript.normalize_position(str(outgoing.get("position", "")))
		if not outgoing_position.is_empty() and pos != outgoing_position:
			continue
		if not required.is_empty() and int(info["counts"].get(pos, 0)) <= PlayerTypesScript.squad_slot_min(pos):
			continue
		var cost := _termination_cost(session, outgoing)
		var incoming_pos := required if not required.is_empty() else pos
		for incoming in groups.get(incoming_pos, []):
			if int(incoming.get("club_id", 0)) != 0:
				continue
			var gain := PlayerMarketScript.ability_of(incoming) - PlayerMarketScript.ability_of(outgoing)
			if required.is_empty() and gain < UPGRADE_CA_GAP:
				break
			if gain <= best_gain:
				continue
			if not _foreign_ok_after_swap(squad, club, outgoing, incoming, limit):
				continue
			context["offer_wage"] = PlayerMarketScript.wage_for_move(incoming, club, true)
			if int(session.get_club_budget(cid)) < cost + int(context["offer_wage"]):
				continue
			if not Offer.evaluate(incoming, club, coach, context)["accepted"]:
				continue
			best = {"incoming": incoming, "outgoing": outgoing, "termination_cost": cost}
			best_gain = gain
	return best

static func _execute_free_swap(session: Node, clubs: Dictionary, cid: int, swap: Dictionary, rng: RandomNumberGenerator) -> bool:
	var incoming: Dictionary = swap["incoming"]
	var outgoing: Dictionary = swap["outgoing"]
	var free_index: int = session.free_agents.find(incoming)
	if free_index < 0 or _is_scheme_starter(session, cid, outgoing, session.get_club_players(cid)):
		return false
	if not _remove_from_squad(session, cid, int(outgoing["id"])):
		return false
	session.free_agents.remove_at(free_index)
	session.adjust_club_budget(cid, -int(swap["termination_cost"]))
	_attach_to_club(session, incoming, cid, clubs[cid], rng, 0, "свободный агент")
	_release_to_agents(session, cid, _club_label(clubs[cid], cid), outgoing)
	return true

static func _repair_full_squads(session: Node, clubs: Dictionary, rng: RandomNumberGenerator, only_club_id: int = 0, groups: Dictionary = {}) -> int:
	var repaired := 0
	if groups.is_empty():
		groups = _free_position_groups(session.free_agents)
	for cid in ([only_club_id] if only_club_id > 0 else clubs.keys()):
		var squad: Array = session.get_club_players(int(cid))
		while squad.size() == SQUAD_SIZE:
			var needed := PlayerTypesScript.missing_required_position(squad)
			var counts := PlayerTypesScript.count_squad_positions(squad)
			var overflowing := ""
			for pos in PlayerTypesScript.POSITIONS:
				if int(counts.get(pos, 0)) > PlayerTypesScript.squad_slot_max(pos):
					overflowing = pos
					break
			if needed.is_empty() and overflowing.is_empty():
				break
			var swap := {}
			if not needed.is_empty():
				swap = _find_free_swap(session, clubs, int(cid), groups, needed, overflowing)
			else:
				for pos in PlayerTypesScript.POSITIONS:
					if int(counts.get(pos, 0)) >= PlayerTypesScript.squad_slot_max(pos):
						continue
					swap = _find_free_swap(session, clubs, int(cid), groups, pos, overflowing)
					if not swap.is_empty():
						break
			if swap.is_empty() or not _execute_free_swap(session, clubs, int(cid), swap, rng):
				break
			repaired += 1
			squad = session.get_club_players(int(cid))
	return repaired
