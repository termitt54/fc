extends RefCounted
## Clubs retain their season reputation. Elo is a separate, unbounded SUM score.
const Elo = preload("res://game/national_rating.gd")
const Rules = preload("res://game/national_competition_rules.gd")
const Attraction = preload("res://game/club_attraction.gd")

static func strength_of(unit: Dictionary) -> float:
	var configured: Variant = unit.get("division_strength", null)
	if configured == null: configured = unit.get("rules", {}).get("division_strength", 500)
	if configured == null: configured = 500
	return clampf(float(configured), 0.0, 1000.0)

static func starting_strengths(units: Array) -> Dictionary:
	var selected := {}
	for unit in units:
		if Rules.is_unit(unit): continue
		var kind := str(unit.get("unit_kind", ""))
		var format := str(unit.get("competition_type", "LEAGUE"))
		var league := kind not in ["CUP", "SUPER_CUP"] and (kind == "DIVISION" or format in ["LEAGUE", "DIVISIONS"])
		var candidate := {"priority": 0 if league else 1,
			"level": int(unit.get("rules", {}).get("level", 1)),
			"unit_id": int(unit.get("id", 0)), "strength": strength_of(unit)}
		for raw_id in unit.get("clubs_by_id", {}):
			var id := int(raw_id)
			var previous: Dictionary = selected.get(id, {})
			if previous.is_empty() or candidate.priority < previous.priority or (candidate.priority == previous.priority and (candidate.level < previous.level or (candidate.level == previous.level and candidate.unit_id < previous.unit_id))):
				selected[id] = candidate
	var result := {}
	for id in selected: result[id] = float(selected[id].strength)
	return result

static func ensure(session: Node) -> void:
	var clubs: Dictionary = session._collect_session_clubs()
	var strengths := starting_strengths(session.units)
	# A cup copy lacking Elo must not erase a tracked league copy on load.
	var existing := {}
	for unit in session.units:
		if Rules.is_unit(unit): continue
		for raw_id in unit.get("clubs_by_id", {}):
			var rating: Dictionary = unit.clubs_by_id[raw_id].get("club_elo", {})
			var id := int(raw_id)
			if not rating.is_empty() and (not existing.has(id) or int(rating.get("games", 0)) > int(existing[id].get("games", 0))): existing[id] = rating
	for id in clubs:
		var club: Dictionary = clubs[id]
		var rating: Dictionary = existing.get(id, {})
		if rating.is_empty() or (int(rating.get("games", 0)) == 0 and int(rating.get("seed_version", 0)) < 2):
			var prestige := int(club.get("reputation", 500))
			var initial := float(strengths.get(int(id), 500.0))
			rating = {"elo": initial, "initial_elo": initial, "seed_version": 2,
				"initial_reputation": prestige, "sporting_reputation": float(prestige),
				"games": 0, "last_delta": 0.0, "season_delta": 0.0,
				"season": session.season_number, "since_season": session.season_number}
		else:
			rating.elo = maxf(0.0, float(rating.get("elo", 0.0)))
			if int(rating.get("season", 0)) != int(session.season_number):
				rating.season = session.season_number
				rating.season_delta = 0.0
		club["club_elo"] = rating
	for unit in session.units:
		if Rules.is_unit(unit): continue
		for id in unit.get("clubs_by_id", {}):
			if clubs.has(int(id)): unit.clubs_by_id[id]["club_elo"] = clubs[int(id)].club_elo
		if not unit.has("club_elo_version"):
			unit["club_elo_version"] = 1
			for row in unit.get("matches", []):
				if bool(row.get("played", false)): row["club_elo_counted"] = true

static func importance(unit: Dictionary, row: Dictionary) -> float:
	var strength := strength_of(unit)
	# FIFA final-tournament weights, scaled by the configured competition strength.
	return Elo.importance(unit, row) * (0.1 + 0.9 * strength / 1000.0)

static func record(session: Node, unit: Dictionary, row: Dictionary) -> void:
	if Rules.is_unit(unit) or not bool(row.get("played", false)) or bool(row.get("club_elo_counted", false)): return
	var clubs: Dictionary = session._collect_session_clubs()
	var home := int(row.get("home_id", 0))
	var away := int(row.get("away_id", 0))
	if not clubs.has(home) or not clubs.has(away): return
	if not clubs[home].has("club_elo") or not clubs[away].has("club_elo"):
		ensure(session)
	var a: Dictionary = clubs[home].club_elo
	var b: Dictionary = clubs[away].club_elo
	var pa := float(a.elo)
	var pb := float(b.elo)
	var hg := int(row.get("home_goals", 0))
	var ag := int(row.get("away_goals", 0))
	var wa := 1.0 if hg > ag else 0.0 if hg < ag else 0.5
	var wb := 1.0 - wa
	if hg == ag and not (row.get("shootout", {}) as Dictionary).is_empty():
		if Rules.match_winner_club_id(row) == home: wa = 0.75
		else: wb = 0.75
	var knockout := str(row.get("stage", "REGULAR")) == "PLAYOFF"
	var weight := importance(unit, row)
	var da := Elo.adjustment(pa, pb, wa, weight, knockout)
	var db := Elo.adjustment(pb, pa, wb, weight, knockout)
	for pair in [[a, pa, da], [b, pb, db]]:
		var rating: Dictionary = pair[0]
		rating.elo = maxf(0.0, float(pair[1]) + float(pair[2]))
		var applied := float(rating.elo) - float(pair[1])
		rating.last_delta = applied
		rating.season_delta = float(rating.season_delta) + applied
		rating.games = int(rating.games) + 1
	# Remove shared FIFA point inflation only from the recruitment projection.
	# Actual Elo uses SUM with a zero floor and no upper ceiling.
	var common_drift := 0.0
	for club in clubs.values():
		if club.has("club_elo"): common_drift += float(club.club_elo.elo) - float(club.club_elo.initial_elo)
	common_drift /= maxi(1, clubs.size())
	for club in clubs.values():
		if not club.has("club_elo"): continue
		var rating: Dictionary = club.club_elo
		rating.sporting_reputation = clampf(float(rating.initial_reputation) + (float(rating.elo) - float(rating.initial_elo) - common_drift) / 1.2, 0.0, 1000.0)
	row["club_elo_counted"] = true

static func rows(session: Node) -> Array:
	var result: Array = []
	var countries: Dictionary = session._countries_by_id()
	var clubs: Dictionary = session._collect_session_clubs()
	var strengths := starting_strengths(session.units)
	for id in clubs:
		var club: Dictionary = clubs[id]
		var rating: Dictionary = club.get("club_elo", {})
		var cid := int(club.get("country_id", 0))
		var country: Dictionary = countries.get(cid, {})
		result.append({"id": int(id), "name": club.get("name", ""),
			"country_id": cid, "country_name": country.get("name", ""), "flag_path": country.get("flag_path", ""),
			"logo_path": club.get("logo_path", ""), "elo": maxf(0.0, float(rating.get("elo", strengths.get(int(id), 500.0)))),
			"change": float(rating.get("season_delta", 0.0)), "reputation": int(club.get("reputation", 500)),
			"attraction": Attraction.value(club), "attraction_hint": Attraction.description(), "games": int(rating.get("games", 0))})
	result.sort_custom(func(a, b): return str(a.name).nocasecmp_to(str(b.name)) < 0 if is_equal_approx(a.elo, b.elo) else a.elo > b.elo)
	for i in result.size(): result[i]["rank"] = i + 1
	return result
