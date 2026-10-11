extends Node
## Match engine: lineups, calibration, discipline, statistics and speed.
## Run: godot --headless --path . res://tests/game/test_match_engine.tscn

const MatchTypesScript := preload("res://game/match_types.gd")
const MatchEngineScript := preload("res://game/match_engine.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const LineupSelectorScript := preload("res://game/lineup_selector.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerStatsScript := preload("res://game/player_stats.gd")
const SquadFixtures := preload("res://tests/game/squad_fixtures.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")

const SQUAD_SIZE := 18
const CALIBRATION_MATCHES := 400
const BENCHMARK_MATCHES := 500
## Measured at roughly 1.8 ms per match; the budget leaves room for slow machines.
const BENCHMARK_BUDGET_MS := 2500

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_isolate_sim_config()
	print("=== Match engine tests ===")
	_test_lineup()
	_test_availability()
	_test_effective_lineup()
	_test_calibration()
	_test_strength_matters()
	_test_playoff_decides()
	_test_discipline_switch()
	_test_condition_and_stats()
	_test_benchmark()
	_restore_sim_config()
	_finish()


# --- lineup --------------------------------------------------------------


func _test_lineup() -> void:
	var rng := _rng(101)
	var squad := _make_squad(1, 60, rng)
	var coach := _make_coach(1, rng)
	for formation in TacticTypesScript.FORMATIONS:
		var lineup: Dictionary = LineupSelectorScript.build(
			squad, [], coach, {"style": TacticTypesScript.STYLE_CONTROL, "formation": formation}, rng
		)
		var starters: Array = lineup.get("starters", [])
		_assert(starters.size() == 8, "%s fields 8 players (got %d)" % [formation, starters.size()])
		var keepers := 0
		var ids: Dictionary = {}
		for record in starters:
			var player: Dictionary = record["player"]
			ids[int(player.get("id", 0))] = true
			if PlayerTypes.normalize_position(str(player.get("position", ""))) == PlayerTypes.POS_GK:
				keepers += 1
		_assert(ids.size() == starters.size(), "%s never fields the same player twice" % formation)
		_assert(keepers >= 1, "%s starts a goalkeeper" % formation)
		var bench: Array = lineup.get("bench", [])
		_assert(
			bench.size() <= TacticTypesScript.MATCH_BENCH,
			"%s bench is at most %d (got %d)" % [formation, TacticTypesScript.MATCH_BENCH, bench.size()]
		)
		for player in bench:
			_assert(not ids.has(int(player.get("id", 0))), "%s bench excludes starters" % formation)


func _test_availability() -> void:
	var rng := _rng(202)
	var squad := _make_squad(1, 60, rng)
	var banned := int(squad[3].get("id", 0))
	var hurt := int(squad[4].get("id", 0))
	PlayerConditionScript.ensure_state(squad[3])
	PlayerConditionScript.ensure_state(squad[4])
	PlayerConditionScript.add_suspension(squad[3], 2)
	PlayerConditionScript.assign_injury(squad[4], MatchTypesScript.INJURY_GRADE_MEDIUM, 4)

	var available := LineupSelectorScript.available_count(squad)
	_assert(available == SQUAD_SIZE - 2, "banned and injured drop out of the pool (%d)" % available)

	var lineup: Dictionary = LineupSelectorScript.build(
		squad, [], _make_coach(1, rng), {"formation": TacticTypesScript.FORM_232}, rng
	)
	var picked: Dictionary = {}
	for record in lineup.get("starters", []):
		picked[int((record["player"] as Dictionary).get("id", 0))] = true
	for player in lineup.get("bench", []):
		picked[int(player.get("id", 0))] = true
	_assert(not picked.has(banned), "suspended player is not in the squad")
	_assert(not picked.has(hurt), "injured player is not in the squad")


# --- calibration ---------------------------------------------------------


func _test_effective_lineup() -> void:
	var rng := _rng(271)
	var squad := SquadFixtures.squad(1, 60, rng, 0)
	for player in squad:
		player["condition"] = 100
	var spec := _spec(1, squad, _make_coach(1, rng))
	var lineup := MatchEngineScript._select_lineup(spec, rng)
	var initial := MatchEngineScript._lineup_ability(lineup)
	_assert(is_equal_approx(initial, 60.0), "native fresh starters have their actual ability")
	var starters: Array = lineup["starters"]
	var bench: Array = lineup["bench"]
	var stronger_reserves := SquadFixtures.squad(2, 95, rng, 0)
	for i in bench.size():
		for reserve in stronger_reserves:
			if reserve["position"] == bench[i]["position"]:
				var replacement: Dictionary = reserve.duplicate(true)
				replacement["id"] = bench[i]["id"]
				replacement["condition"] = 100
				bench[i] = replacement
				break
	_assert(is_equal_approx(MatchEngineScript._lineup_ability(lineup), initial),
		"unselected bench stars cannot raise starting strength")
	starters[0]["fit"] = 0.3
	_assert(MatchEngineScript._lineup_ability(lineup) < initial,
		"playing out of position reduces effective strength")
	starters[0]["fit"] = 1.0
	for record in starters:
		record["player"]["condition"] = 50
	_assert(MatchEngineScript._lineup_ability(lineup) < initial,
		"starting condition affects the team coefficient")
	for record in starters:
		record["player"]["condition"] = 100
	var team := MatchEngineScript._build_team("home", spec, lineup, initial, initial, rng,
		MatchSimConfigScript.snapshot())
	MatchEngineScript._build_wheels(team)
	_assert(is_equal_approx(float(team["ability"]), initial),
		"initial and on-field strength use the same scale")
	var before := float(team["ability"])
	var ctx := {"rng": rng, "events": []}
	var outgoing: Dictionary = team["on_field"][1]
	MatchEngineScript._substitute(team, outgoing, ctx, 20, true)
	_assert((team["on_field"] as Array).size() == 8 and int(team["subs_left"]) < MatchTypesScript.SUBS_MAX,
		"the stronger bench player enters through a real substitution")
	_assert(float(team["ability"]) > before, "strength updates when the substitute enters")
	var strongest: Dictionary = {}
	for unit in team["on_field"]:
		if int(unit["player"]["current_ability"]) == 95:
			strongest = unit
	_assert(not strongest.is_empty(), "the substitute is on the pitch")
	MatchEngineScript._send_off(team, strongest, ctx, 25)
	_assert(is_equal_approx(float(team["ability"]), initial),
		"dismissed star no longer contributes to average strength")
	_assert(int(team["men_down"]) == 1 and (team["on_field"] as Array).size() == 7,
		"dismissal also retains the separate numerical disadvantage")
	for unit in team["on_field"]:
		unit["fresh"] = 0.75
	MatchEngineScript._build_wheels(team)
	_assert(is_equal_approx(float(team["ability"]), initial * 0.75),
		"phase refresh accounts for accumulated fatigue")
	team["on_field"] = []
	MatchEngineScript._build_wheels(team)
	_assert(is_zero_approx(float(team["ability"])), "empty field has zero strength")


func _test_calibration() -> void:
	var rng := _rng(303)
	var home_squad := _make_squad(1, 58, rng)
	var away_squad := _make_squad(2, 58, rng)
	var home_coach := _coach_level(_make_coach(1, rng), 10)
	var away_coach := _coach_level(_make_coach(2, rng), 10)

	var goals := 0
	var home_goals := 0
	var first_score := ""
	var different_scores := 0
	var yellows := 0
	var reds := 0
	var injuries := 0
	var shots := 0
	var possession := 0.0
	var minutes := 0

	for i in CALIBRATION_MATCHES:
		var result := _play(home_squad, away_squad, home_coach, away_coach, rng, true)
		var scored_home := int(result.get("home_goals", 0))
		var scored_away := int(result.get("away_goals", 0))
		home_goals += scored_home
		goals += scored_home + scored_away
		var score_key := "%d-%d" % [scored_home, scored_away]
		if first_score.is_empty():
			first_score = score_key
		elif score_key != first_score:
			different_scores += 1
		var home_team: Dictionary = result["home_team"]
		var away_team: Dictionary = result["away_team"]
		yellows += int(home_team["yellow"]) + int(away_team["yellow"])
		reds += int(home_team["red"]) + int(away_team["red"])
		shots += int(home_team["shots"]) + int(away_team["shots"])
		possession += float(home_team["possession"]) + float(away_team["possession"])
		minutes += int(result.get("minutes_played", 0))
		for team in [home_team, away_team]:
			for entry in team["players"]:
				if int((entry as Dictionary).get("injury_rounds", 0)) > 0:
					injuries += 1
		_reset_squads([home_squad, away_squad])

	var per_match := float(goals) / float(CALIBRATION_MATCHES)
	var home_share := float(home_goals) / float(maxi(goals, 1))
	var yellow_rate := float(yellows) / float(CALIBRATION_MATCHES)
	var red_rate := float(reds) / float(CALIBRATION_MATCHES)
	var injury_rate := float(injuries) / float(CALIBRATION_MATCHES)
	var shot_rate := float(shots) / float(CALIBRATION_MATCHES)
	var possession_avg := possession / float(CALIBRATION_MATCHES)

	print("--- %d matches: %.2f goals, %.2f shots, %.2f yellow, %.3f red, %.3f injury" % [
		CALIBRATION_MATCHES, per_match, shot_rate, yellow_rate, red_rate, injury_rate
	])
	_assert(per_match >= 1.6 and per_match <= 4.6, "goals stay in a football range (%.2f)" % per_match)
	_assert(home_share > 0.50 and home_share < 0.66, "home advantage is real but small (%.2f)" % home_share)
	_assert(different_scores > 30, "the same fixture is not one scripted score (%d other results)" % different_scores)
	_assert(yellow_rate > 0.6 and yellow_rate < 4.0, "yellow cards stay plausible (%.2f)" % yellow_rate)
	_assert(red_rate < 0.30, "red cards are rare (%.3f)" % red_rate)
	_assert(injury_rate > 0.02 and injury_rate < 0.60, "injuries are occasional (%.3f)" % injury_rate)
	_assert(shot_rate > per_match * 2.0, "most shots do not go in (%.2f shots)" % shot_rate)
	_assert(absf(possession_avg - 1.0) < 0.02, "possession splits 100%% (%.3f)" % possession_avg)
	_assert(
		minutes == MatchTypesScript.REGULAR_MINUTES * CALIBRATION_MATCHES,
		"league games last 50 minutes"
	)


func _test_strength_matters() -> void:
	var league := _duel(70, 52, 200, _rng(404))
	var league_ratio := float(league["favourite"]) / float(maxi(int(league["decided"]), 1))
	print("--- CA 70 vs 52 over %d games: %d won, %d lost, %d drawn (%.2f of decided) goals %d-%d" % [
		int(league["samples"]), int(league["favourite"]), int(league["underdog"]),
		int(league["samples"]) - int(league["decided"]), league_ratio,
		int(league["fav_goals"]), int(league["dog_goals"])
	])
	_assert(league_ratio > 0.84, "the better squad wins clearly more often (%.2f)" % league_ratio)
	_assert(
		float(league["underdog"]) / float(int(league["samples"])) < 0.14,
		"upsets stay rare (%d of %d)" % [int(league["underdog"]), int(league["samples"])]
	)
	var league_margin := (float(league["fav_goals"]) - float(league["dog_goals"])) / float(int(league["samples"]))

	var mismatch := _duel(80, 44, 120, _rng(405))
	var mismatch_ratio := float(mismatch["favourite"]) / float(maxi(int(mismatch["decided"]), 1))
	var mismatch_margin := (float(mismatch["fav_goals"]) - float(mismatch["dog_goals"])) / float(int(mismatch["samples"]))
	print("--- CA 80 vs 44: favourite wins %.2f of decided games, margin %.2f" % [mismatch_ratio, mismatch_margin])
	_assert(mismatch_ratio >= league_ratio - 0.001, "a wider gap does not win less often (%.2f)" % mismatch_ratio)
	_assert(mismatch_margin > league_margin + 0.4, "a wider gap wins by more goals (%.2f vs %.2f)" % [mismatch_margin, league_margin])

	var coached := _duel_coach(68, 18, 4, 160, _rng(406))
	var coached_ratio := float(coached["favourite"]) / float(maxi(int(coached["decided"]), 1))
	print("--- equal squads, coach 18 vs 4: favourite wins %.2f goals %d-%d" % [coached_ratio, int(coached["fav_goals"]), int(coached["dog_goals"])])
	_assert(coached_ratio > 0.70, "the better coach wins the even squads (%.2f)" % coached_ratio)
	_assert(coached_ratio < 0.98, "a coach does not script the match (%.2f)" % coached_ratio)


## Plays both squads home and away so the ratio is not a home-field artefact.
func _duel_coach(
	ca: int,
	strong_coach_attr: int,
	weak_coach_attr: int,
	samples: int,
	rng: RandomNumberGenerator
) -> Dictionary:
	var strong := _make_squad(1, ca, rng)
	# Isolate coaching: identical players and tactical identity, different skills.
	var weak: Array = strong.duplicate(true)
	for player in weak:
		player["id"] = int(player["id"]) + 1000
		player["club_id"] = 2
	var strong_coach := _coach_level(_make_coach(1, rng), strong_coach_attr)
	var weak_coach := _coach_level(strong_coach.duplicate(true), weak_coach_attr)
	var favourite := 0
	var underdog := 0
	var fav_goals := 0
	var dog_goals := 0
	for i in samples:
		var swap := i % 2 == 1
		var result := MatchEngineScript.simulate(
			{
				"home": _spec(1 if not swap else 2, weak if swap else strong, weak_coach if swap else strong_coach),
				"away": _spec(2 if not swap else 1, strong if swap else weak, strong_coach if swap else weak_coach),
				"allow_draw": true,
				"discipline": DisciplineRulesScript.defaults(),
			},
			rng
		)
		var home := int(result.get("home_goals", 0))
		var away := int(result.get("away_goals", 0))
		if not swap:
			fav_goals += home
			dog_goals += away
		else:
			fav_goals += away
			dog_goals += home
		if home != away:
			if (home > away) == (not swap):
				favourite += 1
			else:
				underdog += 1
		_reset_squads([strong, weak])
	return {
		"favourite": favourite,
		"underdog": underdog,
		"decided": favourite + underdog,
		"samples": samples,
		"fav_goals": fav_goals,
		"dog_goals": dog_goals,
	}


func _duel(strong_ca: int, weak_ca: int, samples: int, rng: RandomNumberGenerator) -> Dictionary:
	var strong := _make_squad(1, strong_ca, rng)
	var weak := _make_squad(2, weak_ca, rng)
	var strong_coach := _coach_level(_make_coach(1, rng), 10)
	var weak_coach := _coach_level(_make_coach(2, rng), 10)
	var favourite := 0
	var underdog := 0
	var fav_goals := 0
	var dog_goals := 0
	for i in samples:
		var swap := i % 2 == 1
		var result := _play(
			weak if swap else strong,
			strong if swap else weak,
			weak_coach if swap else strong_coach,
			strong_coach if swap else weak_coach,
			rng,
			true
		)
		var home := int(result.get("home_goals", 0))
		var away := int(result.get("away_goals", 0))
		if not swap:
			fav_goals += home
			dog_goals += away
		else:
			fav_goals += away
			dog_goals += home
		if home != away:
			if (home > away) == (not swap):
				favourite += 1
			else:
				underdog += 1
		_reset_squads([strong, weak])
	return {
		"favourite": favourite,
		"underdog": underdog,
		"decided": favourite + underdog,
		"samples": samples,
		"fav_goals": fav_goals,
		"dog_goals": dog_goals,
	}


func _test_playoff_decides() -> void:
	var rng := _rng(505)
	var home_squad := _make_squad(1, 60, rng)
	var away_squad := _make_squad(2, 60, rng)
	var home_coach := _make_coach(1, rng)
	var away_coach := _make_coach(2, rng)
	var draws := 0
	var extra := 0
	var shootouts := 0
	for _i in 120:
		var result := _play(home_squad, away_squad, home_coach, away_coach, rng, false)
		var home := int(result.get("home_goals", 0))
		var away := int(result.get("away_goals", 0))
		var shootout: Dictionary = result.get("shootout", {})
		if home == away and shootout.is_empty():
			draws += 1
		_assert(int(result.get("winner", 0)) != 0, "playoff result names a winner")
		if bool(result.get("extra_time", false)):
			extra += 1
			_assert(
				int(result.get("minutes_played", 0))
					== MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES,
				"extra time adds 2 x 10 minutes"
			)
		if not shootout.is_empty():
			shootouts += 1
			_assert(
				int(shootout.get("home", 0)) != int(shootout.get("away", 0)),
				"a shootout always has a winner"
			)
		_reset_squads([home_squad, away_squad])
	print("--- playoff: %d went to extra time, %d to penalties" % [extra, shootouts])
	_assert(draws == 0, "playoff games never end level (%d)" % draws)
	_assert(extra > 0, "some playoff games go to extra time")


func _test_discipline_switch() -> void:
	var rng := _rng(606)
	var home_squad := _make_squad(1, 60, rng)
	var away_squad := _make_squad(2, 60, rng)
	var home_coach := _make_coach(1, rng)
	var away_coach := _make_coach(2, rng)

	var cards := 0
	for _i in 60:
		var result: Dictionary = MatchEngineScript.simulate(
			{
				"home": _spec(1, home_squad, home_coach),
				"away": _spec(2, away_squad, away_coach),
				"allow_draw": true,
				"discipline": DisciplineRulesScript.from_rules({"discipline_enabled": false}),
			},
			rng
		)
		cards += int((result["home_team"] as Dictionary)["yellow"])
		cards += int((result["away_team"] as Dictionary)["yellow"])
		cards += int((result["home_team"] as Dictionary)["red"])
		cards += int((result["away_team"] as Dictionary)["red"])
		_reset_squads([home_squad, away_squad])
	_assert(cards == 0, "cards off means no cards at all (%d)" % cards)

	var strict := 0
	var lenient := 0
	for _i in 120:
		strict += _card_count(
			home_squad, away_squad, home_coach, away_coach, rng,
			{"card_strictness": DisciplineRulesScript.STRICTNESS_MAX}
		)
		lenient += _card_count(
			home_squad, away_squad, home_coach, away_coach, rng,
			{"card_strictness": DisciplineRulesScript.STRICTNESS_MIN}
		)
	print("--- cards: %d strict vs %d lenient referees" % [strict, lenient])
	_assert(strict > lenient * 2, "strict referees book far more (%d vs %d)" % [strict, lenient])


# --- consequences --------------------------------------------------------


func _test_condition_and_stats() -> void:
	var rng := _rng(707)
	var home_squad := _make_squad(1, 62, rng)
	var away_squad := _make_squad(2, 62, rng)
	var result := _play(home_squad, away_squad, _make_coach(1, rng), _make_coach(2, rng), rng, true)
	var report: Dictionary = result["home_team"]

	var starters := 0
	var minutes := 0
	for entry in report["players"]:
		var row: Dictionary = entry
		if bool(row.get("started", false)):
			starters += 1
		minutes += int(row.get("minutes", 0))
	_assert(starters == 8, "eight players start the game (%d)" % starters)
	_assert(minutes >= 8 * MatchTypesScript.REGULAR_MINUTES * 0.9, "minutes add up (%d)" % minutes)

	var index: Dictionary = {}
	for player in home_squad:
		index[int(player.get("id", 0))] = player
	var drained := 0
	for entry in report["players"]:
		var row: Dictionary = entry
		var player: Dictionary = index[int(row.get("player_id", 0))]
		var before := PlayerConditionScript.condition_of(player)
		PlayerConditionScript.apply_match_load(player, int(row.get("minutes", 0)), 1.0)
		PlayerStatsScript.apply_entry(player, row, 1, 1)
		if PlayerConditionScript.condition_of(player) < before:
			drained += 1
	_assert(drained >= 8, "everyone who played lost condition (%d)" % drained)

	var sample: Dictionary = index[int((report["players"][0] as Dictionary).get("player_id", 0))]
	var season: Dictionary = PlayerStatsScript.season_of(sample)
	_assert(int(season.get("matches", 0)) == 1, "one match folded into the season row")
	_assert(int(season.get("minutes", 0)) > 0, "minutes reached the season row")

	var tired := PlayerConditionScript.condition_of(sample)
	PlayerConditionScript.advance_round(sample, true)
	_assert(PlayerConditionScript.condition_of(sample) > tired, "resting a round regains condition")

	# A player used every single round must sag without ever collapsing to zero.
	var iron_man: Dictionary = home_squad[10]
	_set_physics(iron_man, 10, 10)
	iron_man["condition"] = MatchTypesScript.CONDITION_START
	var low := MatchTypesScript.CONDITION_MAX
	for _round in 15:
		PlayerConditionScript.apply_match_load(iron_man, MatchTypesScript.REGULAR_MINUTES, 1.0)
		PlayerConditionScript.advance_round(iron_man, true)
		low = mini(low, PlayerConditionScript.condition_of(iron_man))
	print("--- playing every round settles at %d condition" % PlayerConditionScript.condition_of(iron_man))
	_assert(low > 45, "an every-round starter never collapses (%d)" % low)
	_assert(
		PlayerConditionScript.condition_of(iron_man) < 90,
		"an every-round starter is not fresh either (%d)" % PlayerConditionScript.condition_of(iron_man)
	)
	var rested := PlayerConditionScript.condition_of(iron_man)
	for _round in 3:
		PlayerConditionScript.advance_round(iron_man, false)
	_assert(
		PlayerConditionScript.condition_of(iron_man) > rested + 10,
		"sitting out a few rounds brings a player back"
	)

	PlayerStatsScript.roll_season(sample, 2, 1)
	_assert(PlayerStatsScript.career_of(sample).size() == 1, "the season is pushed onto the career")
	_assert(int(PlayerStatsScript.season_of(sample).get("matches", 0)) == 0, "the new season starts empty")
	_assert(int(PlayerStatsScript.career_totals(sample).get("matches", 0)) == 1, "career totals keep the match")


func _test_benchmark() -> void:
	var rng := _rng(808)
	var squads: Array = []
	var coaches: Array = []
	for i in 8:
		squads.append(_make_squad(i + 1, 50 + i * 4, rng))
		coaches.append(_make_coach(i + 1, rng))

	var started := Time.get_ticks_msec()
	for i in BENCHMARK_MATCHES:
		var home := i % squads.size()
		var away := (i + 1 + (i / squads.size())) % squads.size()
		if home == away:
			away = (away + 1) % squads.size()
		_play(squads[home], squads[away], coaches[home], coaches[away], rng, true)
	var elapsed := Time.get_ticks_msec() - started
	var per_match := float(elapsed) / float(BENCHMARK_MATCHES)
	print("--- %d matches in %d ms (%.2f ms per match)" % [BENCHMARK_MATCHES, elapsed, per_match])
	_assert(
		elapsed < BENCHMARK_BUDGET_MS,
		"%d matches under %d ms (took %d ms)" % [BENCHMARK_MATCHES, BENCHMARK_BUDGET_MS, elapsed]
	)


# --- helpers -------------------------------------------------------------


func _play(
	home_squad: Array,
	away_squad: Array,
	home_coach: Dictionary,
	away_coach: Dictionary,
	rng: RandomNumberGenerator,
	allow_draw: bool
) -> Dictionary:
	return MatchEngineScript.simulate(
		{
			"home": _spec(1, home_squad, home_coach),
			"away": _spec(2, away_squad, away_coach),
			"allow_draw": allow_draw,
			"importance": 1.0 if allow_draw else 1.12,
			"discipline": DisciplineRulesScript.defaults(),
		},
		rng
	)


func _card_count(
	home_squad: Array,
	away_squad: Array,
	home_coach: Dictionary,
	away_coach: Dictionary,
	rng: RandomNumberGenerator,
	rules: Dictionary
) -> int:
	var result: Dictionary = MatchEngineScript.simulate(
		{
			"home": _spec(1, home_squad, home_coach),
			"away": _spec(2, away_squad, away_coach),
			"allow_draw": true,
			"discipline": DisciplineRulesScript.from_rules(rules),
		},
		rng
	)
	_reset_squads([home_squad, away_squad])
	return int((result["home_team"] as Dictionary)["yellow"]) \
		+ int((result["away_team"] as Dictionary)["yellow"])


func _spec(club_id: int, squad: Array, coach: Dictionary) -> Dictionary:
	return _spec_rep(club_id, squad, coach, 500)


func _coach_level(coach: Dictionary, level: int) -> Dictionary:
	var attributes: Dictionary = coach.get("attributes", {})
	attributes[CoachTypes.ATTR_TACTICS] = level
	attributes[CoachTypes.ATTR_MOTIVATION] = level
	coach["attributes"] = attributes
	return coach


func _spec_rep(club_id: int, squad: Array, coach: Dictionary, reputation: int) -> Dictionary:
	return {
		"club_id": club_id,
		"squad": squad,
		"youth": [],
		"coach": coach,
		"reputation": reputation,
	}


func _make_squad(club_id: int, target_ca: int, rng: RandomNumberGenerator) -> Array:
	return SquadFixtures.squad(club_id, target_ca, rng)


func _make_coach(club_id: int, rng: RandomNumberGenerator) -> Dictionary:
	return SquadFixtures.coach(club_id, rng)


func _set_physics(player: Dictionary, stamina: int, recovery: int) -> void:
	var attributes: Variant = player.get("attributes", {})
	if typeof(attributes) != TYPE_DICTIONARY:
		return
	var physical: Variant = (attributes as Dictionary).get(PlayerTypes.ATTR_GROUP_PHYSICAL, {})
	if typeof(physical) != TYPE_DICTIONARY:
		return
	(physical as Dictionary)[PlayerTypes.ATTR_STAMINA] = stamina
	(physical as Dictionary)[PlayerTypes.ATTR_RECOVERY] = recovery
	MatchRatings.invalidate(player)


## The engine never mutates players, so squads are reusable — but the tests
## still normalise state to keep every sample independent.
func _reset_squads(squads: Array) -> void:
	for squad in squads:
		for player in squad:
			player["condition"] = MatchTypesScript.CONDITION_START
			player["morale"] = MatchTypesScript.MORALE_DEFAULT
			player["injury_rounds"] = 0
			player["injury_grade"] = ""
			player["suspension_matches"] = 0


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _isolate_sim_config() -> void:
	MatchSimConfigScript.config_path = "user://config/match_simulation_engine_test.json"
	if FileAccess.file_exists(MatchSimConfigScript.config_path):
		DirAccess.remove_absolute(MatchSimConfigScript.config_path)
	MatchSimConfigScript.reset_to_defaults(false)


func _restore_sim_config() -> void:
	if FileAccess.file_exists("user://config/match_simulation_engine_test.json"):
		DirAccess.remove_absolute("user://config/match_simulation_engine_test.json")
	MatchSimConfigScript.config_path = MatchSimConfigScript.DEFAULT_CONFIG_PATH
	MatchSimConfigScript.reset_to_defaults(false)


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
