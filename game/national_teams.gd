class_name NationalTeams
extends RefCounted

const NationalCompetitionRulesScript = preload("res://game/national_competition_rules.gd")
## Countries own call-up IDs, never another copy of a club's player roster.

const TEAM_ID_BASE := 1000000000
const SQUAD_SIZE := 20
const QUOTAS := {"GK": 3, "CB": 7, "CM": 6, "ST": 4}

static func is_team(id: int) -> bool:
	return NationalCompetitionRulesScript.is_team(id)

static func team_id(country_id: int) -> int:
	return NationalCompetitionRulesScript.team_id(country_id)

static func is_unit(unit: Dictionary) -> bool:
	return NationalCompetitionRulesScript.is_unit(unit)

static func due(unit: Dictionary, season: int) -> bool:
	return NationalCompetitionRulesScript.due(unit, season)

static func identity(country: Dictionary) -> Dictionary:
	return NationalCompetitionRulesScript.identity(country)

static func ensure(session: Node) -> void:
	# Migration uses its own RNG and never changes an old save's match stream.
	var rng := RandomNumberGenerator.new()
	rng.seed = 842193 + int(session.season_number)
	for coach in session.coaches_by_club.values():
		CoachTypes.ensure_professionalism(coach)
		TacticTypes.ensure_coach_tactics(coach)
	for pool in ["free", "retired"]:
		for coach in session.coach_market.get(pool, []):
			CoachTypes.ensure_professionalism(coach)
			TacticTypes.ensure_coach_tactics(coach)
	var countries: Dictionary = session._countries_by_id()
	for cid in countries:
		if not session.national_teams.has(cid):
			session.national_teams[cid] = {"country": countries[cid], "coach": {}, "squad_ids": [], "withdrawn_ids": [], "registered_season": 0, "discipline": {}}
		var team: Dictionary = session.national_teams[cid]
		if (team.get("coach", {}) as Dictionary).is_empty():
			appoint(session, team, rng)
		else:
			CoachTypes.ensure_professionalism(team["coach"])
			TacticTypes.ensure_coach_tactics(team["coach"])
	# Lazy loading avoids a dependency cycle: rating uses national identities.
	var rating_script: Script = load("res://game/national_rating.gd")
	rating_script.ensure(session)
	session._national_player_index.clear()
	compact_registrations(session)

static func appoint(session: Node, team: Dictionary, rng: RandomNumberGenerator) -> void:
	CoachMarket.ensure(session)
	var country: Dictionary = team["country"]
	var employer := identity(country)
	employer["name"] = "Сборная " + str(country.get("name", ""))
	var best: Dictionary = {}
	var score := -INF
	for coach in session.coach_market["free"]:
		if int(coach.get("last_national_team_id", 0)) == int(country["id"]) and int(coach.get("national_departure_season", 0)) >= int(session.season_number):
			continue
		if not CoachMarket.accepts(coach, employer) or int(coach.get("age", 45)) >= int(coach.get("retirement_age", 75)):
			continue
		var value := float(coach.get("current_ability", 50)) + 2.0 * CoachTypes.professionalism_of(coach)
		if value > score:
			best = coach
			score = value
	if best.is_empty():
		best = CoachMarket._generate(session, employer, rng)
	else:
		session.coach_market["free"].erase(best)
	best["club_id"] = 0
	best["national_team_id"] = int(country["id"])
	best["employment_status"] = "national"
	best["contract_years"] = rng.randi_range(2, 4)
	best["free_seasons"] = 0
	best["career"].append({"season_from": session.season_number, "day_from": session.season_day, "season_to": 0,
		"club_id": 0, "national_team_id": country["id"], "club_name": "Сборная " + str(country.get("name", "")), "role": CoachTypes.ROLE_HEAD_COACH})
	team["coach"] = best
	CoachMarket._event(session, best, employer, "appointed", session.season_number, session.season_day)

static func close_season(session: Node, rng: RandomNumberGenerator) -> void:
	for team in session.national_teams.values():
		var coach: Dictionary = team.get("coach", {})
		if coach.is_empty():
			continue
		coach["age"] = int(coach.get("age", 45)) + 1
		coach["contract_years"] = maxi(0, int(coach.get("contract_years", 1)) - 1)
		var country: Dictionary = team["country"]
		var employer := identity(country)
		employer["name"] = "Сборная " + str(country.get("name", ""))
		var retired := int(coach["age"]) >= int(coach.get("retirement_age", 75))
		var poor := false
		for unit in session.units:
			if not is_unit(unit) or not bool(unit.get("international_started", false)) or not (unit.get("clubs_by_id", {}) as Dictionary).has(int(employer["id"])):
				continue
			var standings: Array = session.sorted_standings(unit)
			var playoff: Dictionary = unit.get("playoff", {})
			if bool(playoff.get("enabled", false)) and int(employer["id"]) != int(playoff.get("champion_id", 0)):
				var last_round := 0
				for series in playoff.get("series", []):
					if int(employer["id"]) in [int(series.get("home_id", 0)), int(series.get("away_id", 0))]:
						last_round = maxi(last_round, int(series.get("round", 0)))
				var total_rounds := PlayoffManager._rounds_for_teams(int(playoff.get("teams", 0)))
				if _expected_rank(unit, employer["id"]) <= 2 and total_rounds - last_round >= 2:
					poor = true
			var expected := _expected_rank(unit, employer["id"])
			for i in standings.size():
				if int(standings[i].get("club_id", 0)) == int(employer["id"]) and int(standings[i].get("played", 0)) > 0 and int(playoff.get("champion_id", 0)) != int(employer["id"]):
					poor = poor or i + 1 >= expected + maxi(3, int(standings.size() / 3))
		var reason := "retired" if retired else "dismissed" if poor else "contract_expired"
		if not retired and not poor and int(coach["contract_years"]) > 0:
			continue
		if not retired and not poor and CoachMarket.accepts(coach, employer, true) and rng.randf() < 0.8:
			coach["contract_years"] = rng.randi_range(2, 4)
			CoachMarket._event(session, coach, employer, "renewed", session.season_number, session.season_day)
			continue
		for stint in coach.get("career", []):
			if int(stint.get("season_to", 0)) == 0:
				stint["season_to"] = session.season_number
				stint["day_to"] = session.season_day
				stint["departure_reason"] = reason
		CoachMarket._event(session, coach, employer, reason, session.season_number, session.season_day)
		coach["last_national_team_id"] = int(country["id"])
		coach["national_departure_season"] = session.season_number
		coach["national_team_id"] = 0
		coach["contract_years"] = 0
		coach["employment_status"] = "retired" if retired else "free"
		session.coach_market["retired" if retired else "free"].append(coach)
		team["coach"] = {}
		appoint(session, team, rng)

static func _expected_rank(unit: Dictionary, id: int) -> int:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	var rep := int((clubs.get(id, {}) as Dictionary).get("reputation", 0))
	var rank := 1
	for club in clubs.values():
		if int(club.get("reputation", 0)) > rep:
			rank += 1
	return rank

static func index_players(session: Node) -> Dictionary:
	if session._national_player_index.is_empty():
		for map in [session.players_by_club, session.reserve_players_by_club, session.youth_players_by_club]:
			for pool in map.values():
				for player in pool:
					session._national_player_index[int(player["id"])] = player
		for player in session.free_agents:
			session._national_player_index[int(player["id"])] = player
	return session._national_player_index

static func selection_value(player: Dictionary, coach: Dictionary) -> float:
	var position := str(player.get("position", "CM"))
	var value := LineupSelector.role_value(MatchRatings.of(player), position, CoachTypes.primary_style_of(coach))
	value += form_bonus(player)
	value *= 0.65 + 0.35 * PlayerCondition.condition_of(player) / 100.0
	return value

static func form_bonus(player: Dictionary) -> float:
	var recent: Array = player.get("recent_ratings", [])
	if not recent.is_empty():
		var total := 0.0
		for rating in recent:
			total += float(rating)
		return clampf((total / recent.size() - 6.5) * 3.0, -4.0, 4.0) * minf(recent.size() / 5.0, 1.0)
	var stats: Dictionary = player.get("season_stats", {})
	var games := int(stats.get("matches", 0))
	return clampf((PlayerStats.average_rating(stats) - 6.5) * 3.0, -4.0, 4.0) * minf(games / 5.0, 1.0) if games > 0 else 0.0

static func select_squad(candidates: Array, coach: Dictionary, rng: RandomNumberGenerator) -> Array:
	var native: Variant = NativeSimulation.core(false)
	if native != null and TacticTypes._tactics_are_valid(coach):
		return native.national_roster(candidates,CoachTypes.primary_style_of(coach),CoachTypes.selection_uncertainty(coach)*18.0,rng)
	var grouped: Dictionary = {}
	var scores: Dictionary = {}
	var error := CoachTypes.selection_uncertainty(coach) * 18.0
	for player in candidates:
		if PlayerCondition.is_injured(player):
			continue
		var pos := str(player.get("position", "CM"))
		if not grouped.has(pos):
			grouped[pos] = []
		grouped[pos].append(player)
		scores[int(player["id"])] = selection_value(player, coach) + (rng.randf_range(-error, error) if error > 0 else 0.0)
	var picked: Array = []
	var rest: Array = []
	for pos in grouped:
		var pool: Array = grouped[pos]
		pool.sort_custom(func(a, b): return float(scores[int(a["id"])]) > float(scores[int(b["id"])]))
		for i in pool.size():
			if i < int(QUOTAS.get(pos, 0)):
				picked.append(int(pool[i]["id"]))
			else:
				rest.append(pool[i])
	rest.sort_custom(func(a, b): return float(scores[int(a["id"])]) > float(scores[int(b["id"])]))
	for player in rest:
		if picked.size() >= SQUAD_SIZE:
			break
		var pos := PlayerTypes.normalize_position(str(player.position))
		var count := 0
		for id in picked:
			for candidate in grouped.get(pos, []):
				if int(candidate.id)==int(id): count+=1
		if count < PlayerTypes.squad_slot_max(pos):
			picked.append(int(player["id"]))
	return picked

static func start_window(session: Node) -> void:
	for unit in session.units:
		if not is_unit(unit) and not PlayoffManager.is_unit_season_complete(unit):
			return
	for unit in session.units:
		if is_unit(unit) and bool(unit.get("international_started", false)) and not PlayoffManager.is_unit_season_complete(unit):
			return
	var waiting: Array = []
	for unit in session.units:
		if is_unit(unit) and due(unit, session.season_number) and not bool(unit.get("international_started", false)):
			waiting.append(unit)
	if waiting.is_empty():
		return
	waiting = waiting.slice(0, 1)
	# Serialize tournaments so a player can never play two international games on one day.
	var countries: Dictionary = {}
	for unit in waiting:
		for id in unit.get("clubs_by_id", {}):
			countries[int(id) - TEAM_ID_BASE] = true
	var candidates: Dictionary = {}
	session._national_player_index.clear()
	for player in index_players(session).values():
		var cid := int(player.get("nationality_country_id", 0))
		if not countries.has(cid):
			continue
		if not candidates.has(cid):
			candidates[cid] = []
		candidates[cid].append(player)
	for cid in countries:
		var team: Dictionary = session.national_teams.get(cid, {})
		if team.is_empty():
			continue
		team["squad_ids"] = select_squad(candidates.get(cid, []), team["coach"], session._rng)
		team["registered_season"] = session.season_number
		team["registered_unit_id"] = int(waiting[0].get("id", 0))
		team["withdrawn_ids"] = []
		team["discipline"] = {}
	for unit in waiting:
		if str(unit.get("competition_type", "")) in [CompetitionTypes.TYPE_DIVISIONS, CompetitionTypes.TYPE_LEAGUE, CompetitionTypes.TYPE_GROUP_AND_PLAYOFF]:
			# Country identities are the live save state, not the editor database.
			for id in unit.get("clubs_by_id", {}):
				var team: Dictionary = session.national_teams.get(int(id) - TEAM_ID_BASE, {})
				if not team.is_empty():
					unit["clubs_by_id"][id] = identity(team["country"])
					if team.get("rating", {}).has("elo"):
						unit["clubs_by_id"][id]["elo"] = float(team.rating.elo)
			session._next_match_id = InternationalDraw.prepare(unit, session.season_number, session._rng, session._next_match_id)
		unit["playoff"]["third_place"] = true
		var squads: Dictionary = {}
		var coaches: Dictionary = {}
		for id in unit.get("clubs_by_id", {}):
			squads[id] = match_squad(session, int(id))
			coaches[id] = session.get_club_coach(int(id))
		unit["season_preview"] = SeasonPreview.build(unit, session.season_number, squads, coaches)
		var rating_script: Script = load("res://game/national_rating.gd")
		rating_script.begin_edition(session, unit)
		unit["international_started"] = true
		unit["international_start_day"] = maxi(1, session.season_day + 1)
		for match_row in unit.get("matches", []):
			match_row["season_day"] = int(match_row.get("season_day", 1)) + session.season_day
			match_row["neutral"] = true
		# Knockout units have no regular calendar, start their bracket here.
		var started := PlayoffManager.maybe_start(unit, session.season_day, session._next_match_id)
		session._next_match_id = int(started.get("next_match_id", session._next_match_id))

static func roster(session: Node, id: int) -> Array:
	var team: Dictionary = session.national_teams.get(id - TEAM_ID_BASE, {})
	var players := index_players(session)
	var result: Array = []
	for pid in team.get("squad_ids", []):
		if players.has(int(pid)):
			result.append(players[int(pid)])
	return result

static func match_squad(session: Node, id: int) -> Array:
	var team: Dictionary = session.national_teams.get(id - TEAM_ID_BASE, {})
	var result: Array = []
	for player in roster(session, id):
		if int(player["id"]) in team.get("withdrawn_ids", []):
			continue
		var copy: Dictionary = player.duplicate(false)
		var state: Dictionary = (team.get("discipline", {}) as Dictionary).get(int(player["id"]), {})
		copy["yellow_running"] = int(state.get("yellow_running", 0))
		copy["suspension_matches"] = int(state.get("suspension_matches", 0))
		copy["_national_selection"] = true
		copy["_national_form_bonus"] = form_bonus(player)
		result.append(copy)
	return result

static func apply_report(session: Node, id: int, report: Dictionary, result: Dictionary, outcome: int, rules: Dictionary) -> void:
	var team: Dictionary = session.national_teams[id - TEAM_ID_BASE]
	var players := index_players(session)
	var discipline: Dictionary = team["discipline"]
	for state in discipline.values():
		state["suspension_matches"] = maxi(0, int(state.get("suspension_matches", 0)) - 1)
	for entry in report.get("players", []):
		var pid := int(entry.get("player_id", 0))
		if not players.has(pid) or int(entry.get("minutes", 0)) <= 0:
			continue
		var player: Dictionary = players[pid]
		if not player.has("national_stats"):
			player["national_stats"] = []
		var stats: Array = player["national_stats"]
		if stats.is_empty() or int(stats[-1].get("season", 0)) != int(session.season_number):
			stats.append(PlayerStats.blank(session.season_number, id))
		var holder := {"season_stats": stats[-1]}
		PlayerStats.apply_entry(holder, entry, session.season_number, id)
		PlayerStats.record_form(player, float(entry.get("rating", 0.0)))
		var minutes := int(entry["minutes"])
		var intensity := float(entry.get("intensity_minutes", minutes * float(report.get("intensity", 1.0)))) / minutes
		PlayerCondition.apply_match_load(player, minutes, intensity)
		var state: Dictionary = discipline.get(pid, {"yellow_running": 0, "suspension_matches": 0})
		MatchDay._apply_cards(state, entry, rules)
		discipline[pid] = state
		MatchDay._apply_injury(player, entry)
		if int(entry.get("injury_rounds", 0)) > 0 and pid not in team["withdrawn_ids"]:
			team["withdrawn_ids"].append(pid)
		PlayerCondition.adjust_morale(player, MatchDay._morale_delta(entry, outcome, int(entry["minutes"]), int(result.get("minutes_played", 90))))


## Shrink legacy registrations using only previously called-up players. No replacement
## call-ups, player copies or random draws, including during an ongoing tournament.
static func compact_registrations(session: Node) -> void:
	var index: Dictionary = index_players(session)
	for team in session.national_teams.values():
		if team.get("squad_ids", []).size() <= SQUAD_SIZE:
			continue
		var pool: Array = []
		for id in team.squad_ids:
			if index.has(int(id)): pool.append(index[int(id)])
		pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var va := selection_value(a, team.coach)
			var vb := selection_value(b, team.coach)
			return int(a.id)<int(b.id) if is_equal_approx(va,vb) else va>vb)
		var selected: Array = []
		var ids: Array = []
		for pos in PlayerTypes.POSITIONS:
			var need := PlayerTypes.squad_slot_min(pos)
			for player in pool:
				if need<=0: break
				if str(player.position)==pos and not ids.has(int(player.id)):
					selected.append(player)
					ids.append(int(player.id))
					need-=1
		for player in pool:
			if not ids.has(int(player.id)) and PlayerTypes.can_add_squad_position(selected,str(player.position)):
				selected.append(player)
				ids.append(int(player.id))
		team.squad_ids=ids
		team.withdrawn_ids=(team.get("withdrawn_ids",[]) as Array).filter(func(id): return ids.has(int(id)))
