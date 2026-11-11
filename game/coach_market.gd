class_name CoachMarket
extends RefCounted
## Club boards, unemployed coaches and persistent careers. No player-market RNG.

const Generator := preload("res://game/coach_generator.gd")
const MIN_REVIEW_MATCHES := 12
const REVIEW_INTERVAL := 5
const BAD_REVIEWS_TO_DISMISS := 3

static func ensure(session: Node) -> void:
	var state: Dictionary = session.coach_market
	for key in ["free", "retired", "events"]:
		if not state.has(key):
			state[key] = []
	if not state.has("turnover_initialized"):
		var clubs := clubs_of(session)
		for event in state["events"]:
			var cid := int(event.get("club_id", 0))
			if event.get("reason", "") == "dismissed" and clubs.has(cid):
				clubs[cid]["coach_dismissal_season"] = maxi(int(clubs[cid].get("coach_dismissal_season", 0)), int(event["season"]))
		state["turnover_initialized"] = true
	if not state.has("expectations"):
		state["expectations"] = {}
	for cid in session.coaches_by_club:
		var coach: Dictionary = session.coaches_by_club[cid]
		if not coach.has("board_confidence"):
			coach["board_confidence"] = _past_confidence(session, coach, int(cid))
		coach["employment_status"] = "club"
		coach["club_id"] = int(cid)
	for coach in state["free"]:
		coach["club_id"] = 0
		coach["employment_status"] = "free"

static func clubs_of(session: Node) -> Dictionary:
	var clubs := {}
	for unit in session.units:
		if NationalTeams.is_unit(unit):
			continue
		for cid in unit.get("clubs_by_id", {}):
			clubs[int(cid)] = unit["clubs_by_id"][cid]
	return clubs

static func prepare(session: Node, rng: RandomNumberGenerator) -> void:
	ensure(session)
	var clubs := clubs_of(session)
	if clubs.is_empty():
		return
	_seed_pool(session, clubs, rng)
	for cid in clubs:
		if session.get_club_coach(cid).is_empty():
			appoint_best(session, cid, clubs[cid], rng)
	if int(session.coach_market.get("expectation_season", 0)) == int(session.season_number):
		return
	# Freeze squad expectations before the first result. Transfers are over.
	var expectations := {}
	for unit in session.units:
		if NationalTeams.is_unit(unit):
			continue
		var ranked: Array = []
		for cid in unit.get("clubs_by_id", {}):
			var abilities: Array = []
			for player in session.get_club_players(int(cid)):
				abilities.append(PlayerMarket.ability_of(player))
			abilities.sort()
			abilities.reverse()
			var count := mini(8, abilities.size())
			var total := 0.0
			for i in count:
				total += float(abilities[i])
			ranked.append({"id": int(cid), "quality": total / maxf(count, 1)})
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["quality"] > b["quality"] if a["quality"] != b["quality"] else a["id"] < b["id"])
		for i in ranked.size():
			var cid := int(ranked[i]["id"])
			# A club in multiple competitions is assessed in its first league only.
			if not expectations.has(cid):
				expectations[cid] = {"rank": i + 1, "size": ranked.size(), "unit_id": int(unit["id"])}
	session.coach_market["expectations"] = expectations
	session.coach_market["expectation_season"] = session.season_number
	session.coach_market["last_review_day"] = 0

static func assessments(session: Node) -> Dictionary:
	var out := {}
	var expectations: Dictionary = session.coach_market.get("expectations", {})
	for unit in session.units:
		if NationalTeams.is_unit(unit):
			continue
		var table: Array = session.sorted_standings(unit)
		for i in table.size():
			var row: Dictionary = table[i]
			var cid := int(row["club_id"])
			var expected: Dictionary = expectations.get(cid, {})
			if expected.is_empty() or int(expected["unit_id"]) != int(unit["id"]):
				continue
			var matches := int(row.get("played", 0))
			var deficit := (i + 1) - int(expected["rank"])
			var threshold := maxi(3, int(ceil(float(expected["size"]) * 0.20)))
			var reference: Dictionary = table[clampi(int(expected["rank"]) - 1, 0, table.size() - 1)]
			var point_gap := float(reference.get("points", 0)) / maxf(int(reference.get("played", 0)), 1) - float(row.get("points", 0)) / maxf(matches, 1)
			out[cid] = {"expected": expected["rank"], "actual": i + 1, "matches": matches,
				"points": int(row.get("points", 0)), "reference_ppg": float(reference.get("points", 0)) / maxf(int(reference.get("played", 0)), 1),
				"deficit": deficit, "poor": matches >= MIN_REVIEW_MATCHES and deficit >= threshold and point_gap >= 0.30,
				"success": i + 1 <= int(expected["rank"])}
	return out

static func review(session: Node, rng: RandomNumberGenerator) -> void:
	if session.season_day < 1:
		return
	prepare(session, rng)
	if session.season_day - int(session.coach_market.get("last_review_day", 0)) < REVIEW_INTERVAL:
		return
	session.coach_market["last_review_day"] = session.season_day
	var clubs := clubs_of(session)
	var results := assessments(session)
	for cid in results:
		var result: Dictionary = results[cid]
		var coach: Dictionary = session.get_club_coach(cid)
		if coach.is_empty():
			continue
		var since_hire := int(result["matches"]) - int(coach.get("appointment_matches", 0))
		if since_hire < MIN_REVIEW_MATCHES or int(clubs[cid].get("coach_dismissal_season", 0)) == int(session.season_number):
			continue
		coach["board_strikes"] = int(coach.get("board_strikes", 0)) + 1 if _stint_is_poor(coach, result) else 0
		if int(coach["board_strikes"]) >= BAD_REVIEWS_TO_DISMISS + int(coach.get("board_confidence", 0)):
			depart(session, cid, "dismissed", session.season_number, session.season_day, true)
			var appointed := appoint_best(session, cid, clubs[cid], rng, int(result["matches"]))
			appointed["appointment_points"] = result["points"]
			appointed["appointment_reference_ppg"] = result["reference_ppg"]

static func close_season(session: Node, rng: RandomNumberGenerator) -> void:
	if int(session.coach_market.get("last_close", 0)) >= int(session.season_number):
		return
	prepare(session, rng)
	session.coach_market["last_close"] = session.season_number
	var clubs := clubs_of(session)
	var results := assessments(session)
	for coach in session.coach_market["free"].duplicate():
		coach["age"] = int(coach.get("age", 45)) + 1
		coach["free_seasons"] = int(coach.get("free_seasons", 0)) + 1
		coach["reputation"] = maxi(0, int(coach.get("reputation", 500)) - 4)
		if int(coach["age"]) >= _retirement_age(coach, rng):
			session.coach_market["free"].erase(coach)
			coach["employment_status"] = "retired"
			session.coach_market["retired"].append(coach)
			_event(session, coach, {}, "retired", session.season_number + 1, -5)
	var vacancies: Array = []
	for cid in clubs:
		var coach: Dictionary = session.get_club_coach(cid)
		if coach.is_empty():
			vacancies.append(cid)
			continue
		var result: Dictionary = results.get(cid, {})
		var poor := _stint_is_poor(coach, result)
		var confidence := int(coach.get("board_confidence", 0))
		var already_changed := int(clubs[cid].get("coach_dismissal_season", 0)) == int(session.season_number)
		var title := _won_title(session, cid)
		var recognised := title or (not result.is_empty() and (int(result.get("actual", 999)) <= 3 or int(result.get("expected", 0)) - int(result.get("actual", 0)) >= 3))
		var board_failure := poor and confidence <= 0 and not already_changed and not title
		coach["board_confidence"] = mini(2, confidence + 1) if recognised else maxi(0, confidence - (1 if poor else 0))
		coach["age"] = int(coach.get("age", 45)) + 1
		coach["appointment_matches"] = 0
		coach["board_strikes"] = 0
		coach["contract_years"] = maxi(0, int(coach.get("contract_years", 1)) - 1)
		var delta := 8 if recognised else (-12 if poor else 0)
		coach["reputation"] = clampi(int(coach.get("reputation", 500)) + delta, 0, 1000)
		var reason := ""
		if int(coach["age"]) >= _retirement_age(coach, rng):
			reason = "retired"
		elif board_failure and int(result.get("matches", 0)) >= MIN_REVIEW_MATCHES:
			reason = "dismissed" if int(coach["contract_years"]) > 0 else "not_renewed"
		elif int(coach["contract_years"]) == 0:
			if accepts(coach, clubs[cid], true) and rng.randf() < (0.94 if bool(result.get("success", false)) else 0.82):
				coach["contract_years"] = rng.randi_range(2, 4)
				coach["wage"] = maxi(int(coach.get("wage", 0)), Generator._estimate_wage(int(coach.get("current_ability", 50)), int(coach["reputation"]), int(coach["age"])))
				_event(session, coach, clubs[cid], "renewed", session.season_number + 1, -5)
			else:
				reason = "contract_expired"
		if not reason.is_empty():
			depart(session, cid, reason, session.season_number, session.season_day)
			vacancies.append(cid)
	# All clubs release first; larger jobs get first choice of the same market.
	vacancies.sort_custom(func(a: int, b: int) -> bool: return int(clubs[a].get("reputation", 500)) > int(clubs[b].get("reputation", 500)))
	_seed_pool(session, clubs, rng)
	for cid in vacancies:
		appoint_best(session, cid, clubs[cid], rng, 0, session.season_number + 1, -5)

static func accepts(coach: Dictionary, club: Dictionary, renewal: bool = false) -> bool:
	var ambition := maxf(int(coach.get("reputation", 500)), int(coach.get("current_ability", 50)) * 9.0)
	var flexibility := 180.0 + minf(int(coach.get("free_seasons", 0)) * 30.0, 120.0) + (100.0 if renewal else 0.0)
	return ambition - float(club.get("reputation", 500)) <= flexibility

static func depart(session: Node, cid: int, reason: String, season: int, day: int, midseason: bool = false) -> void:
	var coach: Dictionary = session.get_club_coach(cid)
	if coach.is_empty():
		return
	var club: Dictionary = clubs_of(session).get(cid, {})
	if reason == "dismissed":
		club["coach_dismissal_season"] = season
		# Compensation uses the unexpired salary commitment.
		var paid_year := 1 if midseason and int(session.wages_paid_for_season) == season else 0
		var remaining := maxi(0, int(coach.get("contract_years", 0)) - paid_year)
		session.adjust_club_budget(cid, -int(coach.get("wage", 0)) * remaining)
	for entry in coach.get("career", []):
		if int(entry.get("season_to", 0)) == 0 and int(entry.get("club_id", 0)) == cid:
			entry["season_to"] = season
			entry["day_to"] = day
			entry["departure_reason"] = reason
	_event(session, coach, club, reason, season, day)
	session.coaches_by_club.erase(cid)
	coach["club_id"] = 0
	coach["contract_years"] = 0
	coach["employment_status"] = "retired" if reason == "retired" else "free"
	coach["free_seasons"] = 0
	coach["last_club_id"] = cid
	coach["departure_season"] = season
	session.coach_market["retired" if reason == "retired" else "free"].append(coach)

static func appoint_best(session: Node, cid: int, club: Dictionary, rng: RandomNumberGenerator, matches: int = 0, season: int = 0, day: int = -999) -> Dictionary:
	var best := {}
	var best_score := -INF
	var squad: Array = session.get_club_players(cid)
	var style_fits := _squad_style_fits(squad)
	var positions := PlayerTypes.count_squad_positions(squad)
	var debt := int(session.get_club_budget(cid)) < 0
	var wage_cap := maxf(10000.0, ClubFinance.seasonal_income(int(club.get("finance_level", 10)), int(club.get("reputation", 500))) * (0.01 if debt else 0.035))
	for coach in session.coach_market["free"]:
		if int(coach.get("last_club_id", 0)) == cid and int(coach.get("departure_season", 0)) >= int(session.season_number):
			continue
		if not accepts(coach, club) or int(coach.get("age", 45)) >= int(coach.get("retirement_age", 75)):
			continue
		if int(coach.get("wage", 0)) > wage_cap:
			continue
		var attributes: Dictionary = coach.get("attributes", {})
		var score := float(coach.get("current_ability", 50)) + float(attributes.get("tactics", 10)) * 1.5 + float(attributes.get("development", 10))
		score += 15.0 * float(style_fits.get(CoachTypes.primary_style_of(coach), 0.0))
		for pos in PlayerTypes.POSITIONS:
			var missing := maxi(0, YouthGraduation.starter_count(CoachTypes.primary_formation_of(coach), pos) - int(positions.get(pos, 0)))
			score -= 8.0 * missing
		score -= absf(float(club.get("reputation", 500)) - float(coach.get("reputation", 500))) * 0.015
		if score > best_score:
			best = coach
			best_score = score
	if best.is_empty():
		# Affordable new local coach, not a re-rolled replica of the outgoing coach.
		var local := club.duplicate()
		local["reputation"] = mini(int(club.get("reputation", 500)), 500 if debt else 650)
		best = _generate(session, local, rng)
		best["wage"] = mini(int(best["wage"]), int(wage_cap))
	else:
		session.coach_market["free"].erase(best)
	best["club_id"] = cid
	best["employment_status"] = "club"
	best["free_seasons"] = 0
	best["contract_years"] = rng.randi_range(2, 4)
	best["appointment_matches"] = matches
	best["appointment_points"] = 0
	best["appointment_reference_ppg"] = 0.0
	best["board_strikes"] = 0
	best["board_confidence"] = 0
	var hiring_season := season if season > 0 else int(session.season_number)
	var hiring_day := day if day != -999 else int(session.season_day)
	best["career"].append({"season_from": hiring_season, "day_from": hiring_day, "season_to": 0,
		"club_id": cid, "club_name": club.get("name", ""), "role": CoachTypes.ROLE_HEAD_COACH})
	session.coaches_by_club[cid] = best
	if hiring_season == int(session.season_number) and hiring_day >= 1 and int(session.wages_paid_for_season) == hiring_season:
		var remaining_share := clampf(float(session.season_total_days - hiring_day + 1) / maxf(session.season_total_days, 1), 0.0, 1.0)
		session.adjust_club_budget(cid, -int(round(float(best.get("wage", 0)) * remaining_share)))
	_event(session, best, club, "appointed", hiring_season, hiring_day)
	return best

static func _seed_pool(session: Node, clubs: Dictionary, rng: RandomNumberGenerator) -> void:
	if clubs.is_empty():
		return
	var target := maxi(8, int(ceil(clubs.size() * 0.35)))
	var ids: Array = clubs.keys()
	var names := {}
	var pools := {}
	while session.coach_market["free"].size() < target:
		var club: Dictionary = clubs[ids[rng.randi_range(0, ids.size() - 1)]].duplicate()
		club["reputation"] = clampi(int(club.get("reputation", 500)) + rng.randi_range(-200, 100), 100, 1000)
		session.coach_market["free"].append(_generate(session, club, rng, pools, names))

static func _generate(session: Node, club: Dictionary, rng: RandomNumberGenerator, pools: Dictionary = {}, names: Dictionary = {}) -> Dictionary:
	var ids := {"next_id": session._next_coach_id}
	var coach := Generator.generate_for_club(0, club, rng, pools, names, ids, session.season_number)
	session._next_coach_id = int(ids["next_id"])
	coach["club_id"] = 0
	coach["career"] = []
	coach["employment_status"] = "free"
	coach["contract_years"] = 0
	coach["free_seasons"] = 0
	_retirement_age(coach, rng)
	return coach

static func _retirement_age(coach: Dictionary, rng: RandomNumberGenerator) -> int:
	if not coach.has("retirement_age"):
		coach["retirement_age"] = rng.randi_range(70, 75)
	return int(coach["retirement_age"])

static func _event(session: Node, coach: Dictionary, club: Dictionary, reason: String, season: int, day: int) -> void:
	session.coach_market["events"].append({"season": season, "day": day, "coach_id": coach["id"],
		"coach_name": coach.get("name", ""), "club_id": club.get("id", coach.get("club_id", 0)),
		"club_name": club.get("name", ""), "reason": reason})


static func reason_label(reason: String) -> String:
	return str({"appointed": "Назначен", "dismissed": "Уволен", "renewed": "Договор продлён", "not_renewed": "Клуб не продлил договор", "contract_expired": "Договор завершён", "retired": "Завершил карьеру"}.get(reason, reason))


static func initialize_loaded_pool(session: Node) -> void:
	if session.coach_market.has("initialized"):
		return
	ensure(session)
	var clubs := clubs_of(session)
	if clubs.is_empty():
		return
	# Upgrade old saves deterministically without consuming their match RNG.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(session.season_number) ^ int(session._next_coach_id) ^ 731946
	_seed_pool(session, clubs, rng)
	session.coach_market["initialized"] = true

static func open_market(session: Node, rng: RandomNumberGenerator) -> void:
	ensure(session)
	var clubs := clubs_of(session)
	if clubs.is_empty():
		return
	_seed_pool(session, clubs, rng)
	session.coach_market["initialized"] = true
	for cid in clubs:
		if session.get_club_coach(cid).is_empty():
			appoint_best(session, cid, clubs[cid], rng)


static func _stint_is_poor(coach: Dictionary, result: Dictionary) -> bool:
	if not bool(result.get("poor", false)):
		return false
	var appointment_matches := int(coach.get("appointment_matches", 0))
	if appointment_matches <= 0:
		return true
	var matches := int(result.get("matches", 0)) - appointment_matches
	if matches < MIN_REVIEW_MATCHES:
		return false
	var points := int(result.get("points", 0)) - int(coach.get("appointment_points", 0))
	return float(points) / float(matches) < float(coach.get("appointment_reference_ppg", 0.0)) - 0.30


static func _won_title(session: Node, cid: int) -> bool:
	for unit in session.units:
		if NationalTeams.is_unit(unit):
			continue
		for result in unit.get("winners", []).slice(-1):
			if int(result.get("season", 0)) == int(session.season_number) and int(result.get("club_id", 0)) == cid:
				return true
	return false


static func _past_confidence(session: Node, coach: Dictionary, cid: int) -> int:
	var start := int(session.season_number)
	for stint in coach.get("career", []):
		if int(stint.get("club_id", 0)) == cid and int(stint.get("season_to", 0)) == 0:
			start = int(stint.get("season_from", start))
	var successes := {}
	for unit in session.units:
		if NationalTeams.is_unit(unit):
			continue
		for result in unit.get("winners", []).slice(-2):
			var year := int(result.get("season", 0))
			if year < start or year >= int(session.season_number):
				continue
			if int(result.get("club_id", 0)) == cid:
				successes[year] = true
			for row in result.get("regular", []):
				if int(row.get("club_id", 0)) == cid and int(row.get("place", 999)) <= 3:
					successes[year] = true
	return mini(2, successes.size())


## Recruitment compatibility ignores temporary injuries and morale. Build all
## seven style ratings once for this squad, not once per free coach.
static func _squad_style_fits(squad: Array) -> Dictionary:
	var fits := {}
	for style in TacticTypes.STYLES:
		var values: Array = []
		for player in squad:
			if str(player.get("position", "")) != "GK":
				var ratings := MatchRatings.of(player)
				values.append((float(ratings.get("create",0.0))+float(ratings.get("finish",0.0)))*0.5 if style=="attacking" else (float(ratings.get("defend",0.0))+float(ratings.get("aerial",0.0)))*0.5)
		values.sort()
		var total := 0.0
		for i in range(maxi(0, values.size() - 7), values.size()):
			total += float(values[i])
		fits[style] = total / 7.0
	return fits
