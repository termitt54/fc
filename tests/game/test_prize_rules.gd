extends Node
## Prize table layout and payouts for DIVISIONS units.
## Run: godot --headless --path . res://tests/game/test_prize_rules.tscn

const PrizeRulesScript := preload("res://database/repositories/world/prize_rules.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Prize rules tests ===")
	_test_overall_regular_rows()
	_test_division_and_playoff_rows()
	_test_regular_payouts()
	_test_per_division_payouts()
	_test_playoff_payouts_stack()
	_test_session_pays_once()
	GameSession.clear()
	_finish()


func _test_overall_regular_rows() -> void:
	var unit := {
		"divisions_count": 2,
		"teams_per_division": 4,
		"regular_season_enabled": true,
		"teams_playoff": 0,
	}
	var rows: Array = PrizeRulesScript.describe_rows(unit)
	_assert(rows.size() == 8, "unified table has 8 place rows (%d)" % rows.size())
	_assert(str(rows[0].get("section", "")) == "Регулярный сезон", "overall section is regular season")
	_assert(not PrizeRulesScript.playoff_enabled(unit), "no playoff rows without teams")


func _test_division_and_playoff_rows() -> void:
	var unit := {
		"divisions_count": 2,
		"teams_per_division": 4,
		"regular_season_enabled": false,
		"teams_playoff": 8,
		"playoff_third_place": true,
	}
	var rows: Array = PrizeRulesScript.describe_rows(unit)
	var keys: Array = []
	for row in rows:
		keys.append(str(row.get("key", "")))
	_assert(PrizeRulesScript.regular_place_count(unit) == 4, "each division has 4 places")
	_assert(keys.has("regular_1"), "division 1st is editable")
	_assert(keys.has("playoff_champion"), "champion is editable")
	_assert(keys.has("playoff_runner_up"), "finalist is editable")
	_assert(keys.has("playoff_third"), "third place is editable")
	_assert(keys.has("playoff_fourth"), "fourth place is editable")
	_assert(keys.has("playoff_out_1"), "quarterfinal exit is editable")
	_assert(not keys.has("playoff_out_2"), "semifinal is covered by 3rd/4th, not an exit row")


func _test_regular_payouts() -> void:
	var unit := {
		"divisions_count": 1,
		"teams_per_division": 3,
		"regular_season_enabled": true,
		"teams_playoff": 0,
		"prize_rules": {
			"regular_1": 100000,
			"regular_2": 40000,
			"regular_3": 10000,
		},
	}
	var table := [
		{"club_id": 7, "points": 12},
		{"club_id": 8, "points": 8},
		{"club_id": 9, "points": 4},
	]
	var paid: Dictionary = PrizeRulesScript.payouts(unit, func(_div): return table, {})
	_assert(int(paid.get(7, 0)) == 100000, "1st takes the top prize")
	_assert(int(paid.get(8, 0)) == 40000, "2nd takes the middle prize")
	_assert(int(paid.get(9, 0)) == 10000, "3rd takes the last prize")


func _test_per_division_payouts() -> void:
	var unit := {
		"divisions_count": 2,
		"teams_per_division": 2,
		"regular_season_enabled": false,
		"teams_playoff": 0,
		"prize_rules": {"regular_1": 50000, "regular_2": 10000},
	}
	var by_div := {
		0: [{"club_id": 1}, {"club_id": 2}],
		1: [{"club_id": 3}, {"club_id": 4}],
	}
	var paid: Dictionary = PrizeRulesScript.payouts(
		unit,
		func(div): return by_div.get(int(div), []),
		{}
	)
	_assert(int(paid.get(1, 0)) == 50000, "each division winner is paid")
	_assert(int(paid.get(3, 0)) == 50000, "the other division winner is paid the same")
	_assert(int(paid.get(2, 0)) == 10000, "division runner-up is paid")
	_assert(int(paid.get(4, 0)) == 10000, "the other runner-up is paid")


func _test_playoff_payouts_stack() -> void:
	var unit := {
		"divisions_count": 1,
		"teams_per_division": 4,
		"regular_season_enabled": true,
		"teams_playoff": 4,
		"playoff_third_place": true,
		"prize_rules": {
			"regular_1": 1000,
			"regular_2": 0,
			"regular_3": 0,
			"regular_4": 0,
			"playoff_champion": 8000,
			"playoff_runner_up": 4000,
			"playoff_third": 2000,
			"playoff_fourth": 1000,
		},
	}
	var table := [
		{"club_id": 1},
		{"club_id": 2},
		{"club_id": 3},
		{"club_id": 4},
	]
	var playoff := {
		"enabled": true,
		"finished": true,
		"series": [
			_series(1, false, 1, 4, 1),
			_series(1, false, 2, 3, 2),
			_series(2, false, 1, 2, 1),
			_series(2, true, 4, 3, 3),
		],
	}
	var paid: Dictionary = PrizeRulesScript.payouts(unit, func(_div): return table, playoff)
	_assert(int(paid.get(1, 0)) == 9000, "champion also keeps regular 1st (%d)" % int(paid.get(1, 0)))
	_assert(int(paid.get(2, 0)) == 4000, "finalist is paid")
	_assert(int(paid.get(3, 0)) == 2000, "third place is paid")
	_assert(int(paid.get(4, 0)) == 1000, "fourth place is paid")


func _test_session_pays_once() -> void:
	var rules := {
		"divisions_count": 1,
		"teams_per_division": 2,
		"regular_season_enabled": true,
		"teams_playoff": 0,
		"prize_rules": {"regular_1": 75000, "regular_2": 25000},
		"ranking_order": ["POINTS"],
	}
	GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.FIRST_MATCH_DAY,
		"units": [{
			"id": 1,
			"rules": rules,
			"playoff": {"enabled": false, "finished": false, "series": []},
			"standings": [
				{"club_id": 1, "division": 0, "points": 6, "goal_diff": 4, "goals_for": 8, "won": 2},
				{"club_id": 2, "division": 0, "points": 0, "goal_diff": -4, "goals_for": 2, "won": 0},
			],
			"matches": [],
			"clubs_by_id": {
				1: {"id": 1, "name": "Alpha"},
				2: {"id": 2, "name": "Beta"},
			},
		}],
		"players_by_club": {},
		"club_budgets": {1: 0, 2: 0},
		"wages_paid_for_season": 1,
	})
	GameSession._apply_unit_prizes()
	_assert(GameSession.get_club_budget(1) == 75000, "session credits 1st place")
	_assert(GameSession.get_club_budget(2) == 25000, "session credits 2nd place")
	GameSession._apply_unit_prizes()
	_assert(GameSession.get_club_budget(1) == 75000, "prizes are not paid twice")
	GameSession.clear()


func _series(round_no: int, third: bool, home_id: int, away_id: int, winner_id: int) -> Dictionary:
	return {
		"round": round_no,
		"is_third_place": third,
		"complete": true,
		"home_id": home_id,
		"away_id": away_id,
		"winner_id": winner_id,
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % message)
	else:
		_failed += 1
		print("  FAIL  %s" % message)


func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
