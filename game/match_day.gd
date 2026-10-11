class_name MatchDay
extends RefCounted
## Bridge between the session calendar and the match engine.
## Builds the two team specs, runs one game and writes every consequence back:
## statistics, condition, morale, cards, bans and injuries.


const MatchTypesScript := preload("res://game/match_types.gd")
const MatchEngineScript := preload("res://game/match_engine.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerStatsScript := preload("res://game/player_stats.gd")
const UnitSeasonStatsScript := preload("res://game/unit_season_stats.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")

const PLAYOFF_IMPORTANCE := 1.12

const MORALE_WIN := 5.0
const MORALE_DRAW := 1.0
const MORALE_LOSS := -4.5
const MORALE_RATING_PIVOT := 6.5
const MORALE_RATING_WEIGHT := 1.4
const MORALE_MOTM := 2.0
const MORALE_RED := -2.5
const MORALE_UNUSED := -0.4
const MORALE_UNUSED_AMBITIOUS := -1.1


## Runs one scheduled match. `tick` collects who played, so the session can
## hand out the right amount of rest afterwards.
static func simulate(
	session: Node,
	unit: Dictionary,
	match_row: Dictionary,
	tick: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var home_id := int(match_row.get("home_id", 0))
	var away_id := int(match_row.get("away_id", 0))
	var playoff := str(match_row.get("stage", MatchTypesScript.STAGE_REGULAR)) == MatchTypesScript.STAGE_PLAYOFF
	var discipline: Dictionary = DisciplineRulesScript.from_rules(unit.get("rules", {}))

	var result: Dictionary = MatchEngineScript.simulate(
		{
			"home": _team_spec(session, unit, home_id),
			"away": _team_spec(session, unit, away_id),
			"allow_draw": not playoff,
			"neutral": bool(match_row.get("neutral", false)),
			"importance": PLAYOFF_IMPORTANCE if playoff else 1.0,
			"discipline": discipline,
		},
		rng
	)

	var home_goals := int(result.get("home_goals", 0))
	var away_goals := int(result.get("away_goals", 0))
	var outcome := _winner_side(result, home_goals, away_goals)

	# Bans are served by taking part in the matchday, so they tick down before
	# the cards from this very game are handed out.
	_serve_suspensions(session, home_id)
	_serve_suspensions(session, away_id)

	_apply_side(session, home_id, result.get("home_team", {}), result, outcome, discipline)
	_apply_side(session, away_id, result.get("away_team", {}), result, -outcome, discipline)

	_collect_tick(tick, home_id, result.get("home_team", {}))
	_collect_tick(tick, away_id, result.get("away_team", {}))
	# Before the row is marked played, so a backfill of older games does not
	# count this match twice.
	UnitSeasonStatsScript.record_report(unit, home_id, result.get("home_team", {}))
	UnitSeasonStatsScript.record_report(unit, away_id, result.get("away_team", {}))

	match_row["home_goals"] = home_goals
	match_row["away_goals"] = away_goals
	match_row["played"] = true
	match_row["winner_id"] = _winner_club_id(home_id, away_id, outcome)
	match_row["extra_time"] = bool(result.get("extra_time", false))
	var shootout: Dictionary = result.get("shootout", {})
	if shootout.is_empty():
		match_row.erase("shootout")
	else:
		match_row["shootout"] = shootout
	match_row["report"] = _compact_report(result)
	return result


## One calendar round of rest for every player in the save.
static func advance_rounds(session: Node, tick: Dictionary) -> void:
	var players: Dictionary = tick.get("players", {})
	for map in [session.players_by_club, session.youth_players_by_club, session.reserve_players_by_club]:
		for club_id in map.keys():
			for player in map[club_id]:
				if typeof(player) == TYPE_DICTIONARY:
					PlayerConditionScript.advance_round(
						player, players.has(int(player.get("id", 0)))
					)
	for player in session.free_agents:
		if typeof(player) == TYPE_DICTIONARY:
			PlayerConditionScript.advance_round(player, false)


## Same recovery order, with checkpoints between small batches of players.
static func advance_rounds_async(session: Node, tick: Dictionary, work: RefCounted = null) -> void:
	var players: Dictionary = tick.get("players", {})
	var processed := 0
	for map in [session.players_by_club, session.youth_players_by_club, session.reserve_players_by_club]:
		for club_id in map.keys():
			for player in map[club_id]:
				processed += 1
				if work != null and processed % 64 == 0:
					await work.checkpoint("Восстановление игроков", processed)
				if typeof(player) == TYPE_DICTIONARY:
					PlayerConditionScript.advance_round(
						player, players.has(int(player.get("id", 0)))
					)
	for player in session.free_agents:
		processed += 1
		if work != null and processed % 64 == 0:
			await work.checkpoint("Восстановление игроков", processed)
		if typeof(player) == TYPE_DICTIONARY:
			PlayerConditionScript.advance_round(player, false)


## Yellow cards are wiped for the clubs of one unit.
static func reset_yellows_for_unit(session: Node, unit: Dictionary) -> void:
	for club_id in (unit.get("clubs_by_id", {}) as Dictionary).keys():
		for player in session.get_club_players(int(club_id)):
			if typeof(player) == TYPE_DICTIONARY:
				PlayerConditionScript.reset_yellows(player)
		for player in session.get_club_reserve_players(int(club_id)):
			if typeof(player) == TYPE_DICTIONARY:
				PlayerConditionScript.reset_yellows(player)


static func _team_spec(session: Node, unit: Dictionary, club_id: int) -> Dictionary:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	var club: Dictionary = clubs.get(club_id, {})
	return {
		"club_id": club_id,
		"squad": session.get_club_players(club_id),
		"youth": session.get_club_reserve_players(club_id) + session.get_club_youth_players(club_id),
		"coach": session.get_club_coach(club_id),
		"reputation": int(club.get("reputation", 500)),
	}


static func _apply_side(
	session: Node,
	club_id: int,
	report: Dictionary,
	result: Dictionary,
	outcome: int,
	discipline: Dictionary
) -> void:
	if report.is_empty():
		return
	var season := int(session.season_number)
	var minutes_total := maxi(int(result.get("minutes_played", MatchTypesScript.REGULAR_MINUTES)), 1)
	var intensity := float(report.get("intensity", 1.0))
	var roster := _roster_index(session, club_id)
	var played: Dictionary = {}

	for entry in report.get("players", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var player_id := int(entry.get("player_id", 0))
		if not roster.has(player_id):
			continue
		var player: Dictionary = roster[player_id]
		played[player_id] = true
		var minutes := int(entry.get("minutes", 0))
		if minutes < 1:
			continue

		PlayerStatsScript.apply_entry(player, entry, season, club_id)
		var player_intensity := float(entry.get("intensity_minutes", minutes * intensity)) / minutes
		PlayerConditionScript.apply_match_load(player, minutes, player_intensity)
		_apply_cards(player, entry, discipline)
		_apply_injury(player, entry)
		PlayerConditionScript.adjust_morale(
			player, _morale_delta(entry, outcome, minutes, minutes_total)
		)

	_nudge_unused(session, club_id, played)


static func _roster_index(session: Node, club_id: int) -> Dictionary:
	var index: Dictionary = {}
	for pool in [session.get_club_players(club_id), session.get_club_reserve_players(club_id), session.get_club_youth_players(club_id)]:
		for player in pool:
			if typeof(player) == TYPE_DICTIONARY:
				index[int(player.get("id", 0))] = player
	return index


static func _apply_cards(player: Dictionary, entry: Dictionary, discipline: Dictionary) -> void:
	var yellow := int(entry.get("yellow", 0))
	if yellow > 0:
		var running := PlayerConditionScript.add_yellow(player, yellow)
		var threshold := int(discipline.get("yellow_threshold", 0))
		if threshold > 0 and running >= threshold:
			PlayerConditionScript.add_suspension(player, int(discipline.get("yellow_ban", 1)))
			PlayerConditionScript.reset_yellows(player)
	if int(entry.get("red", 0)) > 0:
		PlayerConditionScript.add_suspension(
			player, maxi(int(entry.get("suspension", 0)), int(discipline.get("red_ban", 2)))
		)


static func _apply_injury(player: Dictionary, entry: Dictionary) -> void:
	var rounds := int(entry.get("injury_rounds", 0))
	if rounds < 1:
		return
	PlayerConditionScript.assign_injury(player, str(entry.get("injury_grade", "")), rounds)


static func _morale_delta(entry: Dictionary, outcome: int, minutes: int, minutes_total: int) -> float:
	var share := clampf(float(minutes) / float(minutes_total), 0.0, 1.0)
	var base := MORALE_DRAW
	if outcome > 0:
		base = MORALE_WIN
	elif outcome < 0:
		base = MORALE_LOSS
	var delta := base * share
	delta += (float(entry.get("rating", MatchTypesScript.RATING_BASE)) - MORALE_RATING_PIVOT) * MORALE_RATING_WEIGHT
	if bool(entry.get("motm", false)):
		delta += MORALE_MOTM
	if int(entry.get("red", 0)) > 0:
		delta += MORALE_RED
	return delta


## Watching from the stands stings, and it stings more for the ambitious.
static func _nudge_unused(session: Node, club_id: int, played: Dictionary) -> void:
	for player in session.get_club_players(club_id):
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if played.has(int(player.get("id", 0))):
			continue
		if not PlayerConditionScript.is_available(player):
			continue
		var ambitious: bool = PlayerTypes.characters_of(player).has(PlayerTypes.CHAR_AMBITIOUS)
		PlayerConditionScript.adjust_morale(
			player, MORALE_UNUSED_AMBITIOUS if ambitious else MORALE_UNUSED
		)


static func _serve_suspensions(session: Node, club_id: int) -> void:
	for player in session.get_club_players(club_id):
		if typeof(player) == TYPE_DICTIONARY:
			PlayerConditionScript.serve_suspension(player)


static func _collect_tick(tick: Dictionary, club_id: int, report: Dictionary) -> void:
	var clubs: Dictionary = tick.get("clubs", {})
	clubs[club_id] = true
	tick["clubs"] = clubs
	var players: Dictionary = tick.get("players", {})
	for entry in report.get("players", []):
		if typeof(entry) == TYPE_DICTIONARY and int(entry.get("minutes", 0)) > 0:
			players[int(entry.get("player_id", 0))] = true
	tick["players"] = players


static func _winner_side(result: Dictionary, home_goals: int, away_goals: int) -> int:
	var winner := int(result.get("winner", 0))
	if winner != 0:
		return winner
	if home_goals != away_goals:
		return 1 if home_goals > away_goals else -1
	var shootout: Dictionary = result.get("shootout", {})
	if shootout.is_empty():
		return 0
	var home_pens := int(shootout.get("home", 0))
	var away_pens := int(shootout.get("away", 0))
	if home_pens == away_pens:
		return 0
	return 1 if home_pens > away_pens else -1


static func _winner_club_id(home_id: int, away_id: int, outcome: int) -> int:
	if outcome > 0:
		return home_id
	if outcome < 0:
		return away_id
	return 0


## Only the numbers a match list needs: the per-player rows stay on the players.
static func _compact_report(result: Dictionary) -> Dictionary:
	var report := {
		"home": _compact_team(result.get("home_team", {})),
		"away": _compact_team(result.get("away_team", {})),
		"minutes": int(result.get("minutes_played", 0)),
	}
	if bool(result.get("extra_time", false)):
		report["extra_time"] = true
	var shootout: Dictionary = result.get("shootout", {})
	if not shootout.is_empty():
		report["shootout"] = shootout
	var highlights: Array = []
	for event in result.get("events", []):
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var type := str(event.get("type", ""))
		if type == MatchTypesScript.EVENT_GOAL \
			or type == MatchTypesScript.EVENT_PENALTY_GOAL \
			or type == MatchTypesScript.EVENT_RED:
			highlights.append(event)
	if not highlights.is_empty():
		report["highlights"] = highlights
	return report


static func _compact_team(report: Dictionary) -> Dictionary:
	if report.is_empty():
		return {}
	return {
		"club_id": int(report.get("club_id", 0)),
		"style": str(report.get("style", "")),
		"formation": str(report.get("formation", "")),
		"initial_style": str(report.get("initial_style", report.get("style", ""))),
		"plan_source": str(report.get("plan_source", "primary")),
		"plan_reason": str(report.get("plan_reason", "preferred_plan")),
		"decisions": report.get("decisions", []).duplicate(true),
		"shots": int(report.get("shots", 0)),
		"on_target": int(report.get("on_target", 0)),
		"possession": float(report.get("possession", 0.5)),
		"yellow": int(report.get("yellow", 0)),
		"red": int(report.get("red", 0)),
	}
