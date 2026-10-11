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
