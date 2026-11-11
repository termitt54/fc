extends RefCounted

const Rules = preload("res://game/national_competition_rules.gd")
## FIFA SUM; only outputs prestige/draw data, never match strength.
## State lives inside national_teams and therefore follows each save independently.

const VERSION := 1
const HISTORY_LIMIT := 128

static func initial_elo(country: Dictionary) -> float:
	return 800.0 + float(country.get("reputation", 500)) * 1.2

static func ensure_team(team: Dictionary, season: int) -> void:
	var country: Dictionary = team.get("country", {})
	if team.has("rating"):
		if not team.rating.has("edition_reputation_before"):
			team.rating["edition_reputation_before"] = int(country.get("reputation", 500))
		_ensure_talent_reference(team.rating)
		return
	var elo := initial_elo(country)
	team["rating"] = {"version": VERSION, "elo": elo, "initial_elo": elo,
		"initial_reputation": int(country.get("reputation", 500)), "edition_reputation_before": int(country.get("reputation", 500)), "games": 0,
		"last_delta": 0.0, "edition_delta": 0.0, "trend": 0.0,
		"since_season": season, "last_talent_evaluation": season - 1, "history": [], "talent_history": [], "evaluated_season": -1}
	country["initial_youth_talent"] = int(country.get("youth_talent", 50))
	_ensure_talent_reference(team.rating)

static func _ensure_talent_reference(rating: Dictionary) -> void:
	if int(rating.get("talent_reference_version", 0)) >= 2: return
	# Separate symmetric sporting expectations from FIFA knockout protection.
	# Migration preserves the current hierarchy and all already born players.
	rating["talent_elo"] = float(rating.get("elo", 1400.0))
	rating["talent_reference_version"] = 2
	rating["trend"] = 0.0

static func ensure(session: Node) -> void:
	for team in session.national_teams.values():
		ensure_team(team, session.season_number)
	for unit in session.units:
		if not Rules.is_unit(unit): continue
		if unit.has("national_rating"):
			var participants := {}
			for id in unit.national_rating.get("participants", {}):
				participants[int(id)] = unit.national_rating.participants[id]
			unit.national_rating["participants"] = participants
			continue
		# Never retrospectively count old games on migration, including mid-tournament.
		unit["national_rating"] = {"season": session.season_number, "participants": {}, "closed": false}
		for row in unit.get("matches", []):
			if bool(row.get("played", false)): row["elo_counted"] = true

static func expected(a: float, b: float) -> float:
	return 1.0 / (1.0 + pow(10.0, clampf((b - a) / 600.0, -20.0, 20.0)))

static func adjustment(a: float, b: float, result: float, importance: float, knockout: bool) -> float:
	var delta := importance * (result - expected(a, b))
	return maxf(0.0, delta) if knockout else delta

static func importance(unit: Dictionary, row: Dictionary) -> float:
	if str(row.get("stage", "REGULAR")) != "PLAYOFF": return 50.0
	var round_number := 0
	for series in unit.get("playoff", {}).get("series", []):
		if int(series.get("id", -1)) == int(row.get("series_id", -2)):
			round_number = int(series.get("round", 0))
	var rounds := Rules._rounds_for_teams(int(unit.get("playoff", {}).get("teams", 16)))
	return 60.0 if round_number >= maxi(1, rounds - 2) else 50.0

static func begin_edition(session: Node, unit: Dictionary) -> void:
	var state: Dictionary = unit.get("national_rating", {})
	if int(state.get("season", -1)) == int(session.season_number) and not (state.get("participants", {}) as Dictionary).is_empty(): return
	var participants := {}
	for raw_id in unit.get("clubs_by_id", {}):
		var id := int(raw_id)
		var team: Dictionary = session.national_teams.get(id - Rules.TEAM_ID_BASE, {})
		if team.is_empty(): continue
		ensure_team(team, session.season_number)
		team.rating.edition_delta = 0.0
		team.rating.edition_reputation_before = int(team.country.get("reputation", 500))
		var scheduled := 0
		for fixture in unit.get("matches", []):
			if str(fixture.get("stage", "REGULAR")) == "REGULAR" and id in [int(fixture.get("home_id", 0)),int(fixture.get("away_id", 0))]: scheduled+=1
		participants[id] = {"elo": float(team.rating.talent_elo), "residual": 0.0, "games": 0,"reference_games":maxi(3,scheduled)}
	unit["national_rating"] = {"season": session.season_number, "participants": participants, "closed": false}

static func record(session: Node, unit: Dictionary, row: Dictionary) -> void:
	if not Rules.is_unit(unit) or not bool(row.get("played", false)) or bool(row.get("elo_counted", false)): return
	begin_edition(session, unit)
	var home := int(row.get("home_id", 0))
	var away := int(row.get("away_id", 0))
	var a: Dictionary = session.national_teams.get(home - Rules.TEAM_ID_BASE, {})
	var b: Dictionary = session.national_teams.get(away - Rules.TEAM_ID_BASE, {})
	if a.is_empty() or b.is_empty(): return
	var pa := float(a.rating.elo)
	var pb := float(b.rating.elo)
	var talent_a := float(a.rating.talent_elo)
	var talent_b := float(b.rating.talent_elo)
	var hg := int(row.get("home_goals", 0))
	var ag := int(row.get("away_goals", 0))
	var wa := 1.0 if hg > ag else 0.0 if hg < ag else 0.5
	var wb := 1.0 - wa
	if hg == ag and not (row.get("shootout", {}) as Dictionary).is_empty():
		if Rules.match_winner_club_id(row) == home: wa = 0.75
		else: wb = 0.75
	var knockout := str(row.get("stage", "REGULAR")) == "PLAYOFF"
	var weight := importance(unit, row)
	var da := adjustment(pa, pb, wa, weight, knockout)
	var db := adjustment(pb, pa, wb, weight, knockout)
	# A shootout remains a draw for development; losses always count here.
	var actual_a := 1.0 if hg > ag else 0.0 if hg < ag else 0.5
	var talent_delta := 32.0 * (actual_a - expected(talent_a, talent_b))
	a.rating.talent_elo = talent_a + talent_delta
	b.rating.talent_elo = talent_b - talent_delta
	var participants: Dictionary = unit.national_rating.participants
	for item in [[home, a, pa, da, wa, away], [away, b, pb, db, wb, home]]:
		var id: int = item[0]
		var team: Dictionary = item[1]
		var rating: Dictionary = team.rating
		rating.elo = float(item[2]) + float(item[3])
		rating.last_delta = float(item[3])
		rating.edition_delta = float(rating.edition_delta) + float(item[3])
		rating.games = int(rating.games) + 1
		var history: Array = rating.history
		history.append({"season": session.season_number, "day": session.season_day,
			"opponent_id": item[5], "elo": rating.elo, "delta": item[3]})
		if history.size() > HISTORY_LIMIT: history.pop_front()
		var entry: Dictionary = participants.get(id, {})
		var opponent: Dictionary = participants.get(int(item[5]), {})
		if not entry.is_empty() and not opponent.is_empty():
			# Symmetric pre-match expectations exclude FIFA knockout protection.
			var actual := 1.0 if (id == home and hg > ag) or (id == away and ag > hg) else 0.5 if hg == ag else 0.0
			var reference := expected(talent_a,talent_b) if id == home else expected(talent_b,talent_a)
			entry.residual = float(entry.residual) + actual - reference
			entry.games = int(entry.games) + 1
	for cid in session.national_teams:
		sync_identity(session, Rules.team_id(int(cid)))
	row["elo_counted"] = true
	row["elo_change"] = {"home_before": pa, "away_before": pb, "home_delta": da, "away_delta": db, "importance": weight}

static func sync_identity(session: Node, id: int) -> void:
	var team: Dictionary = session.national_teams.get(id - Rules.TEAM_ID_BASE, {})
	if team.is_empty(): return
	var rating: Dictionary = team.rating
	var country: Dictionary = team.country
	# FIFA's knockout protection introduces points into the system. Remove that
	# common drift when deriving prestige so it cannot push every nation to 1000.
	var common_drift := 0.0
	for other in session.national_teams.values():
		if other.has("rating"): common_drift += float(other.rating.elo) - float(other.rating.initial_elo)
	common_drift /= maxi(1, session.national_teams.size())
	country["elo"] = float(rating.elo)
	country["reputation"] = clampi(int(round(float(rating.initial_reputation) + (float(rating.elo) - float(rating.initial_elo) - common_drift) * 0.5)), 0, 1000)
	for unit in session.units:
		if Rules.is_unit(unit) and (unit.get("clubs_by_id", {}) as Dictionary).has(id):
			unit.clubs_by_id[id] = Rules.identity(country)

static func advance_talent(country: Dictionary, rating: Dictionary, evidence: float, season: int) -> int:
	var talent := clampi(int(country.get("youth_talent", 50)), 0, 100)
	var elapsed := maxi(1, season - int(rating.get("last_talent_evaluation", season - 2)))
	rating["last_talent_evaluation"] = season
	# Annual cups must not double the country's development speed. Long gaps
	# fade stale evidence; they do not generate success or failure by themselves.
	var cadence := minf(1.0, float(elapsed) / 2.0)
	var trend := float(rating.get("trend", 0.0)) * pow(0.98, float(elapsed) / 2.0) + clampf(evidence, -2.5, 2.5) * cadence
	# Roughly 4 exceptional biennial editions per point at high talent; no
	# restriction relative to initial talent. Typical balanced results cancel out.
	# Equal evidence must have equal thresholds in either direction at any talent.
	var up := 8.0
	var down := 8.0
	var delta := 0
	if trend >= up and talent < 100:
		delta = 1
		trend -= up
	elif trend <= -down and talent > 0:
		delta = -1
		trend += down
	if (talent == 100 and trend > 0.0) or (talent == 0 and trend < 0.0): trend = 0.0
	rating["trend"] = trend
	if delta != 0:
		country["youth_talent"] = talent + delta
		var history: Array = rating.get("talent_history", [])
		history.append({"season": season, "before": talent, "after": talent + delta,
			"reason": "Устойчивые результаты выше ожиданий" if delta > 0 else "Устойчивые результаты ниже ожиданий"})
		if history.size() > HISTORY_LIMIT: history.pop_front()
		rating["talent_history"] = history
	return delta

static func close_completed(session: Node) -> void:
	var pending: Array = []
	var combined := {}
	# Evaluate all editions together. Adding another cup must not let the first
	# finished tournament monopolise the country's annual talent observation.
	for unit in session.units:
		if not Rules.is_unit(unit) or not Rules.due(unit, session.season_number): continue
		if not bool(unit.get("international_started", false)) or not Rules.is_unit_season_complete(unit): return
		var state: Dictionary = unit.get("national_rating", {})
		if state.is_empty() or bool(state.get("closed", false)): continue
		pending.append(state)
		for raw_id in state.get("participants", {}):
			var id := int(raw_id)
			var entry: Dictionary = state.participants[raw_id]
			var total: Dictionary = combined.get(id, {"games": 0, "residual": 0.0,"reference_games":0})
			total.games = int(total.games) + int(entry.games)
			total.residual = float(total.residual) + float(entry.residual)
			total.reference_games = int(total.reference_games)+int(entry.get("reference_games",3))
			combined[id] = total
	for id in combined:
		var entry: Dictionary = combined[id]
		var team: Dictionary = session.national_teams.get(int(id) - Rules.TEAM_ID_BASE, {})
		if team.is_empty() or int(entry.games) < 3 or int(team.rating.evaluated_season) == int(session.season_number): continue
		team.rating.evaluated_season = session.season_number
		# A finalist must not have its positive evidence diluted merely because it
		# played more games than an early loser. This denominator is fixed ex ante.
		var evidence := clampf(float(entry.residual) / sqrt(float(maxi(3,int(entry.reference_games)))) * 2.0, -2.5, 2.5)
		advance_talent(team.country, team.rating, evidence, session.season_number)
		sync_identity(session, int(id))
	for state in pending: state["closed"] = true

static func rows(session: Node) -> Array:
	var result: Array = []
	var counts := {}
	var pools: Array = [session.free_agents]
	for squads in [session.players_by_club, session.reserve_players_by_club, session.youth_players_by_club]:
		pools.append_array(squads.values())
	for pool in pools:
		for player in pool:
			var cid := int(player.get("nationality_country_id", 0))
			counts[cid] = int(counts.get(cid, 0)) + 1
	for cid in session.national_teams:
		var team: Dictionary = session.national_teams[cid]
		ensure_team(team, session.season_number)
		var country: Dictionary = team.country
		result.append({"id": Rules.team_id(int(cid)), "country_id": int(cid),
			"name": country.get("name", ""), "country_name": country.get("name", ""),
			"logo_path": country.get("flag_path", ""), "flag_path": country.get("flag_path", ""),
			"elo": float(team.rating.elo), "change": float(team.rating.edition_delta),
			"reputation": int(country.get("reputation", 500)),
			"reputation_change": int(country.get("reputation", 500)) - int(team.rating.edition_reputation_before),
			"talent": int(country.get("youth_talent", 50)), "player_count": int(counts.get(int(cid), 0)),
			"coach_name": str(team.get("coach", {}).get("name", "—")),
			"games": int(team.rating.games), "since_season": int(team.rating.since_season)})
	result.sort_custom(func(a, b): return str(a.name).nocasecmp_to(str(b.name)) < 0 if is_equal_approx(a.elo, b.elo) else a.elo > b.elo)
	for i in result.size(): result[i]["rank"] = i + 1
	return result
