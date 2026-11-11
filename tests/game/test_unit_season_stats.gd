extends Node
## Leaderboards of one tournament: goals from new matches and from saved highlights.
## Run: godot --headless --path . res://tests/game/test_unit_season_stats.tscn

const Stats := preload("res://game/unit_season_stats.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Unit season stats ===")
	_test_leaders_follow_this_unit()
	_test_highlights_fill_goals_once()
	_test_actual_minutes_and_legacy_rows()
	_test_career_totals_span_seasons()
	_finish()


func _test_leaders_follow_this_unit() -> void:
	var unit := {"matches": []}
	Stats.record_report(unit, 1, {
		"players": [
			_entry(5, "Альфа", 90, 2, 0, 7.2),
			_entry(6, "Бета", 90, 2, 1, 8.0),
		],
	})
	Stats.record_report(unit, 2, {
		"players": [
			_entry(7, "Гамма", 90, 1, 0, 6.5, true),
		],
	})
	var scorers := Stats.leaders(unit, "goals")
	_assert(scorers.size() == 3, "three scorers")
	_assert(int(scorers[0].get("player_id", 0)) == 6, "assists break a tie on goals")
	_assert(int(scorers[1].get("player_id", 0)) == 5, "the other brace is second")
	_assert(int(scorers[2].get("goals", 0)) == 1, "a single goal is last")
	var assists := Stats.leaders(unit, "assists")
	_assert(assists.size() == 1 and int(assists[0].get("player_id", 0)) == 6, "only the assist maker is listed")
	var sheets := Stats.leaders(unit, "clean_sheets")
	_assert(sheets.size() == 1 and int(sheets[0].get("player_id", 0)) == 7, "clean sheet is counted")
	var rated := Stats.leaders(unit, "rating")
	_assert(str(rated[0].get("name", "")) == "Бета", "highest average rating leads")
	_assert(Stats.format_metric(rated[0], "rating") == "8.00", "rating prints with two decimals")


func _test_highlights_fill_goals_once() -> void:
	var unit := {
		"matches": [{
			"played": true,
			"report": {
				"highlights": [
					{"type": "GOAL", "player_id": 5, "player": "Альфа", "club_id": 1},
					{"type": "GOAL", "player_id": 5, "player": "Альфа", "club_id": 1},
					{"type": "RED", "player_id": 8, "player": "Дельта", "club_id": 2},
				],
			},
		}],
	}
	var first := Stats.leaders(unit, "goals")
	_assert(first.size() == 1 and int(first[0].get("goals", 0)) == 2, "saved goals become the scoring chart")
	var reds := Stats.leaders(unit, "red")
	_assert(reds.size() == 1 and int(reds[0].get("red", 0)) == 1, "saved red cards are listed")
	Stats.record_report(unit, 1, {"players": [_entry(5, "Альфа", 80, 1, 0, 7.0)]})
	var again := Stats.leaders(unit, "goals")
	_assert(int(again[0].get("goals", 0)) == 3, "a later match adds to the backfill instead of replacing it")
	Stats.ensure(unit)
	_assert(int(Stats.leaders(unit, "goals")[0].get("goals", 0)) == 3, "a second read does not count the old match again")


func _test_actual_minutes_and_legacy_rows() -> void:
	var unit := {"matches": []}
	Stats.record_report(unit, 1, {"players": [_entry(5, "Cameo", 1, 0, 0, 7.0)]})
	Stats.record_report(unit, 1, {"players": [_entry(5, "Cameo", 2, 0, 0, 7.0)]})
	var bag := Stats.ensure(unit)
	_assert(int(bag[5]["minutes"]) == 3, "two cameos store three actual minutes")
	bag[5].erase("minutes")
	Stats.record_report(unit, 1, {"players": [_entry(5, "Cameo", 1, 0, 0, 7.0)]})
	_assert(not Stats.ensure(unit)[5].has("minutes"), "a legacy row does not pretend partial minutes are a complete total")


func _test_career_totals_span_seasons() -> void:
	var season_one := {
		5: {"player_id": 5, "name": "Альфа", "club_id": 1, "matches": 10, "goals": 8, "assists": 1, "yellow": 2, "red": 0, "clean_sheets": 0, "rating_sum": 70.0},
		6: {"player_id": 6, "name": "Бета", "club_id": 2, "matches": 10, "goals": 4, "assists": 6, "yellow": 0, "red": 1, "clean_sheets": 3, "rating_sum": 80.0},
	}
	var season_two := {
		5: {"player_id": 5, "name": "Альфа", "club_id": 2, "matches": 4, "goals": 1, "assists": 0, "yellow": 1, "red": 0, "clean_sheets": 0, "rating_sum": 24.0},
	}
	var history := Stats.combine([season_one, season_two])
	var scorers := Stats.leaders_in(history, "goals")
	_assert(scorers.size() == 2 and int(scorers[0].get("player_id", 0)) == 5, "career scoring chart is led by the long-term scorer")
	_assert(int(scorers[0].get("goals", 0)) == 9 and int(scorers[0].get("matches", 0)) == 14, "goals and matches add across seasons")
	_assert(int(scorers[0].get("club_id", 0)) == 1, "the club with more matches is shown")
	_assert(int(scorers[0].get("yellow", 0)) == 3, "cards add across seasons")
	_assert(Stats.format_metric(scorers[0], "rating") == "6.71", "rating is the match-weighted average")
	_assert(not scorers[0].has("_clubs"), "club split stays out of the visible row")
	_assert(not season_one[5].has("_clubs"), "a stored season is not rewritten while combining")
	var sheets := Stats.leaders_in(history, "clean_sheets")
	_assert(sheets.size() == 1 and int(sheets[0].get("clean_sheets", 0)) == 3, "clean sheets from an earlier season remain")
	var current := {
		5: {"player_id": 5, "name": "Альфа", "club_id": 2, "matches": 20, "goals": 10, "assists": 0, "yellow": 0, "red": 0, "clean_sheets": 0, "rating_sum": 140.0},
	}
	var career := Stats.combine([history, current])
	var again := Stats.leaders_in(career, "goals")
	_assert(int(again[0].get("goals", 0)) == 19 and int(again[0].get("club_id", 0)) == 2, "the live season joins the archive and can change the main club")
	_assert(int(history[5]["_clubs"][1]) == 10 and int(history[5]["_clubs"][2]) == 4, "the archived split is kept for the next season")
	_assert(not Stats.has_leaders_in({}), "an empty career has no leaders")
	_assert(Stats.has_leaders_in(history), "a career with goals has leaders")

func _entry(
	player_id: int,
	player_name: String,
	minutes: int,
	goals: int,
	assists: int,
	rating: float,
	clean_sheet: bool = false
) -> Dictionary:
	return {
		"player_id": player_id,
		"name": player_name,
		"position": "ST",
		"minutes": minutes,
		"goals": goals,
		"assists": assists,
		"yellow": 0,
		"red": 0,
		"clean_sheet": clean_sheet,
		"rating": rating,
	}


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
