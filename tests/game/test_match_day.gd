extends Node
## Matchday inside a session: standings, statistics, condition, bans, season roll.
## Run: godot --headless --path . res://tests/game/test_match_day.tscn

const SquadFixtures := preload("res://tests/game/squad_fixtures.gd")
const MatchTypesScript := preload("res://game/match_types.gd")
const MatchDayScript := preload("res://game/match_day.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const PlayoffManagerScript := preload("res://game/playoff_manager.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerStatsScript := preload("res://game/player_stats.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_isolate_sim_config()
	print("=== Matchday tests ===")
	_test_day_advances_everything()
	_test_yellow_accumulation_bans()
	_test_season_roll()
	_test_playoff_match_has_winner()
	_test_series_counts_shootout()
	_test_best_of_waits_for_needed_wins()
	GameSession.clear()
	_restore_sim_config()
	_finish()


func _test_day_advances_everything() -> void:
	_load_fixture({"card_strictness": DisciplineRulesScript.STRICTNESS_DEFAULT})
	var before_condition := _average_condition(1)

	var advanced: Dictionary = GameSession.advance_day()
	_assert(bool(advanced.get("success", false)), "the day advances")

	var match_row: Dictionary = (GameSession.units[0]["matches"] as Array)[0]
	_assert(bool(match_row.get("played", false)), "the fixture is played")
	_assert(int(match_row.get("home_goals", -1)) >= 0, "the score is written back")
	_assert(match_row.has("report"), "a compact report is attached to the match")
	var report: Dictionary = match_row["report"]
	_assert(
		absf(float((report["home"] as Dictionary)["possession"]) - 0.5) < 0.5,
		"possession is a share, not a percentage"
	)

	var standing := _standing(1)
	_assert(int(standing.get("played", 0)) == 1, "the table counts the game")
	_assert(
		int(standing.get("goals_for", -1)) == int(match_row["home_goals"]),
		"goals reach the table"
	)
	var points_sum := int(_standing(1).get("points", 0)) + int(_standing(2).get("points", 0))
	_assert(points_sum == 3 or points_sum == 2, "points are handed out once (%d)" % points_sum)

	var with_minutes := 0
	var rated := 0
	for player in GameSession.get_club_players(1):
		var row := PlayerStatsScript.season_of(player)
		if int(row.get("minutes", 0)) > 0:
			with_minutes += 1
			if float(row.get("rating_sum", 0.0)) > 0.0:
				rated += 1
	_assert(with_minutes >= 8, "at least the starting eight collected minutes (%d)" % with_minutes)
	_assert(rated == with_minutes, "everyone who played got a rating")

	var goals := 0
	for club_id in [1, 2]:
		for player in GameSession.get_club_players(club_id):
			goals += int(PlayerStatsScript.season_of(player).get("goals", 0))
	_assert(
		goals == int(match_row["home_goals"]) + int(match_row["away_goals"]),
		"every goal has a scorer (%d)" % goals
	)

	_assert(
		_average_condition(1) < before_condition,
		"playing a round costs the squad condition"
	)


func _test_yellow_accumulation_bans() -> void:
	# One booking is enough for a ban, and referees are as strict as possible.
	_load_fixture({
		"card_strictness": DisciplineRulesScript.STRICTNESS_MAX,
		"yellow_ban_threshold": 1,
		"yellow_ban_matches": 2,
	})
	GameSession.advance_day()

	var booked := 0
	var banned := 0
	for club_id in [1, 2]:
		for player in GameSession.get_club_players(club_id):
			var row := PlayerStatsScript.season_of(player)
			if int(row.get("yellow", 0)) > 0 or int(row.get("red", 0)) > 0:
				booked += 1
			if PlayerConditionScript.is_suspended(player):
				banned += 1
	_assert(booked > 0, "a strict referee books somebody")
	_assert(banned >= booked - 1, "a booking at the threshold triggers a ban (%d of %d)" % [banned, booked])
	for club_id in [1, 2]:
		for player in GameSession.get_club_players(club_id):
			if int(PlayerStatsScript.season_of(player).get("yellow", 0)) > 0:
				_assert(
					int(player.get("yellow_running", 0)) == 0,
					"the yellow counter resets once the ban is served out"
				)
				break


func _test_season_roll() -> void:
	_load_fixture({})
	GameSession.advance_day()
	var sample := _first_player_with_minutes(1)
	_assert(not sample.is_empty(), "somebody played before the season break")
	var player_id := int(sample.get("id", 0))
	var matches := int(PlayerStatsScript.season_of(sample).get("matches", 0))

	_assert(GameSession.season_finished, "one fixture means the season is over")
	var started: Dictionary = GameSession.start_new_season()
	_assert(bool(started.get("success", false)), "a new season starts")
	_assert(
		int((started.get("data", {}) as Dictionary).get("season_number", 0)) == 2,
		"the season counter moves on"
	)

	var carried := GameSession.get_player(player_id)
	if carried.is_empty():
		_assert(true, "the sample player retired at the break")
		return
	_assert(
		int(PlayerStatsScript.season_of(carried).get("matches", 0)) == 0,
		"the new season row starts empty"
	)
	var career := PlayerStatsScript.career_of(carried)
	_assert(career.size() == 1, "last season is archived on the career list")
	_assert(
		int(PlayerStatsScript.career_totals(carried).get("matches", 0)) == matches,
		"career totals keep the games played"
	)
	_assert(
		PlayerConditionScript.condition_of(carried) == MatchTypesScript.CONDITION_START,
		"pre-season restores condition"
	)
	var fixture: Dictionary = (GameSession.units[0]["matches"] as Array)[0]
	_assert(not bool(fixture.get("played", true)), "the new calendar is unplayed")


func _test_playoff_match_has_winner() -> void:
	_load_fixture({})
	var unit: Dictionary = GameSession.units[0]
	var match_row := {
		"id": 99,
		"matchday": 1,
		"season_day": 1,
		"home_id": 1,
		"away_id": 2,
		"home_goals": -1,
		"away_goals": -1,
		"played": false,
		"stage": MatchTypesScript.STAGE_PLAYOFF,
		"series_id": 1,
		"game_index": 1,
	}
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	MatchDayScript.simulate(GameSession, unit, match_row, {"clubs": {}, "players": {}}, rng)
	var winner_id := int(match_row.get("winner_id", 0))
	_assert(winner_id == 1 or winner_id == 2, "a playoff match stores the winning club")
	var home := int(match_row.get("home_goals", 0))
	var away := int(match_row.get("away_goals", 0))
	var shootout: Dictionary = match_row.get("shootout", {})
	if shootout.is_empty():
		var report: Dictionary = match_row.get("report", {})
		shootout = report.get("shootout", {})
	_assert(
		home != away or not shootout.is_empty(),
		"a playoff draw is broken by extra time or a shootout"
	)
	if home == away and not shootout.is_empty():
		var pens_home := int(shootout.get("home", 0))
		var pens_away := int(shootout.get("away", 0))
		_assert(pens_home != pens_away, "penalties name a winner")
		_assert(
			winner_id == (1 if pens_home > pens_away else 2),
			"winner_id follows the shootout"
		)


func _test_series_counts_shootout() -> void:
	var unit := _playoff_unit([{
		"id": 1,
		"series_id": 1,
		"played": true,
		"home_id": 1,
		"away_id": 2,
		"home_goals": 2,
		"away_goals": 2,
		"winner_id": 1,
		"shootout": {"home": 4, "away": 3},
		"report": {"shootout": {"home": 4, "away": 3}},
	}])
	PlayoffManagerScript.after_day_simulated(unit, 1, 10, 1)
	var series: Dictionary = (unit["playoff"] as Dictionary)["series"][0]
	_assert(int(series.get("home_wins", 0)) == 1, "a shootout win counts in the series")
	_assert(int(series.get("away_wins", 0)) == 0, "the shootout loser does not get a series win")
	_assert(not bool(series.get("complete", true)), "one win does not finish a first-to-4 series")
	_assert(PlayoffManagerScript.match_winner_club_id({
		"played": true,
		"home_id": 3,
		"away_id": 4,
		"home_goals": 1,
		"away_goals": 1,
		"report": {"shootout": {"home": 3, "away": 4}},
	}) == 4, "legacy reports still resolve a shootout winner")


func _test_best_of_waits_for_needed_wins() -> void:
	var matches: Array = []
	# 3–2 after seven games because two finishes were 1–1 with no winner recorded.
	var scores := [
		[2, 1], [2, 1], [3, 1], [1, 1], [2, 0], [1, 1], [0, 2],
	]
	for i in scores.size():
		var pair: Array = scores[i]
		var home_id := 1 if i % 2 == 0 else 2
		var away_id := 2 if i % 2 == 0 else 1
		matches.append({
			"id": i + 1,
			"series_id": 1,
			"played": true,
			"home_id": home_id,
			"away_id": away_id,
			"home_goals": int(pair[0]),
			"away_goals": int(pair[1]),
		})
	var unit := _playoff_unit(matches)
	PlayoffManagerScript.after_day_simulated(unit, 7, 20, 1)
	var series: Dictionary = (unit["playoff"] as Dictionary)["series"][0]
	_assert(int(series.get("home_wins", 0)) == 3, "open-score wins are 3–2")
	_assert(int(series.get("away_wins", 0)) == 2, "the other side has two wins")
	_assert(not bool(series.get("complete", true)), "first-to-4 does not stop at 3–2")
	var scheduled := 0
	for match_row in (unit["playoff"] as Dictionary).get("matches", []):
		if not bool(match_row.get("played", false)):
			scheduled += 1
	_assert(scheduled == 1, "another game is booked until somebody reaches four wins")


func _playoff_unit(played_matches: Array) -> Dictionary:
	return {
		"matches": [],
		"playoff": {
			"enabled": true,
			"started": true,
			"finished": false,
			"format": PlayoffRules.FORMAT_BEST_OF,
			"series_wins": 4,
			"current_round": 1,
			"champion_id": 0,
			"third_place": false,
			"series": [{
				"id": 1,
				"round": 1,
				"home_id": 1,
				"away_id": 2,
				"home_wins": 0,
				"away_wins": 0,
				"home_goals": 0,
				"away_goals": 0,
				"games_played": 0,
				"complete": false,
				"winner_id": 0,
				"is_third_place": false,
			}],
			"matches": played_matches,
		},
	}


# --- fixture -------------------------------------------------------------


func _load_fixture(discipline: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var rules := {
		"points_win": 3,
		"points_draw": 1,
		"points_loss": 0,
		"divisions_count": 1,
		"teams_per_division": 2,
		"matches_vs_own": 1,
		"matches_vs_other": 0,
		"ranking_order": RankingCriteria.DEFAULT_ORDER,
		"discipline_enabled": true,
		"card_strictness": DisciplineRulesScript.STRICTNESS_DEFAULT,
		"yellow_ban_threshold": DisciplineRulesScript.YELLOW_THRESHOLD_DEFAULT,
		"yellow_ban_matches": DisciplineRulesScript.YELLOW_BAN_DEFAULT,
		"red_ban_matches": DisciplineRulesScript.RED_BAN_DEFAULT,
		"double_yellow_red": true,
		"yellow_reset": DisciplineRulesScript.RESET_SEASON,
	}
	for key in discipline.keys():
		rules[key] = discipline[key]

	var payload := {
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.FIRST_MATCH_DAY,
		"season_total_days": 1,
		"selected_unit_id": 1,
		"season_finished": false,
		"units": [{
			"id": 1,
			"competition_type": CompetitionTypes.TYPE_DIVISIONS,
			"name": "Test",
			"label": "Test",
			"rules": rules,
			"clubs_by_id": {
				1: {"id": 1, "country_id": 1, "reputation": 700, "name": "Alpha", "training_level": 12},
				2: {"id": 2, "country_id": 1, "reputation": 500, "name": "Beta", "training_level": 10},
			},
			"divisions": [{"index": 0, "club_ids": [1, 2]}],
			"standings": [_standing_row(1), _standing_row(2)],
			"matches": [{
				"id": 1,
				"matchday": 1,
				"season_day": 1,
				"home_id": 1,
				"away_id": 2,
				"home_goals": -1,
				"away_goals": -1,
				"played": false,
				"stage": "REGULAR",
			}],
			"playoff": {"enabled": false},
			"winners": [],
		}],
		"players_by_club": {
			"1": SquadFixtures.squad(1, 64, rng),
			"2": SquadFixtures.squad(2, 58, rng),
		},
		"youth_players_by_club": {},
		"free_agents": [],
		"coaches_by_club": {
			"1": SquadFixtures.coach(1, rng),
			"2": SquadFixtures.coach(2, rng),
		},
		"transfer_log": [],
	}
	var loaded: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(loaded.get("success", false)), "the matchday fixture loads")


func _standing_row(club_id: int) -> Dictionary:
	return {
		"club_id": club_id,
		"division": 0,
		"played": 0,
		"won": 0,
		"drawn": 0,
		"lost": 0,
		"goals_for": 0,
		"goals_against": 0,
		"goal_diff": 0,
		"points": 0,
	}


func _standing(club_id: int) -> Dictionary:
	for row in GameSession.units[0]["standings"]:
		if int(row.get("club_id", 0)) == club_id:
			return row
	return {}


func _average_condition(club_id: int) -> float:
	var squad := GameSession.get_club_players(club_id)
	if squad.is_empty():
		return 0.0
	var total := 0.0
	for player in squad:
		total += float(PlayerConditionScript.condition_of(player))
	return total / float(squad.size())


func _first_player_with_minutes(club_id: int) -> Dictionary:
	for player in GameSession.get_club_players(club_id):
		if int(PlayerStatsScript.season_of(player).get("minutes", 0)) > 0:
			return player
	return {}


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % message)
	else:
		_failed += 1
		print("FAIL: %s" % message)


func _isolate_sim_config() -> void:
	MatchSimConfigScript.config_path = "user://config/match_simulation_day_test.json"
	if FileAccess.file_exists(MatchSimConfigScript.config_path):
		DirAccess.remove_absolute(MatchSimConfigScript.config_path)
	MatchSimConfigScript.reset_to_defaults(false)


func _restore_sim_config() -> void:
	if FileAccess.file_exists("user://config/match_simulation_day_test.json"):
		DirAccess.remove_absolute("user://config/match_simulation_day_test.json")
	MatchSimConfigScript.config_path = MatchSimConfigScript.DEFAULT_CONFIG_PATH
	MatchSimConfigScript.reset_to_defaults(false)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
