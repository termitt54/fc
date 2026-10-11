extends Node
## Season-end reputation from the preview and the division strength.
## Run: godot --headless --path . res://tests/game/test_season_reputation.tscn


const Reputation = preload("res://game/season_reputation.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Season reputation ===")
	_test_favorite_moves_less_than_an_outsider()
	_test_missing_the_preview_drops_a_favorite()
	_test_a_stronger_division_moves_reputation_further()
	_test_two_competitions_share_one_cap()
	_test_players_follow_minutes_and_strength()
	_test_player_result_stays_inside_the_drift_cap()
	_test_a_finished_division_rewrites_both_club_copies()
	_finish()


func _test_favorite_moves_less_than_an_outsider() -> void:
	var favorite := Reputation.table_delta(800, 820, 1, 1, 16)
	var outsider := Reputation.table_delta(800, 420, 12, 1, 16)
	_assert(favorite >= 0 and favorite <= Reputation.LEVEL_PULL, "a favorite who wins only creeps")
	_assert(outsider > favorite, "an outsider who wins the same division climbs further")


func _test_missing_the_preview_drops_a_favorite() -> void:
	var drop := Reputation.table_delta(800, 820, 1, 16, 16)
	_assert(drop < 0, "a favorite who finishes last loses reputation")
	_assert(drop <= -10, "missing the preview in a strong division is a real drop")


func _test_a_stronger_division_moves_reputation_further() -> void:
	var strong := Reputation.table_delta(900, 400, 10, 1, 16)
	var weak := Reputation.table_delta(200, 400, 10, 1, 16)
	_assert(strong > weak, "the same surprise is worth more in a stronger division")
	_assert(absi(weak) < absi(strong), "a weak division cannot outrun a strong one")


func _test_two_competitions_share_one_cap() -> void:
	var combined := Reputation.combine_club(500, [
		{"step": 30.0, "pull": 8, "strength": 900},
		{"step": 30.0, "pull": 8, "strength": 700},
	])
	_assert(combined == Reputation.CLUB_CAP, "league and cup share one annual cap")
	_assert(combined <= 20, "two titles do not double the jump")


func _test_players_follow_minutes_and_strength() -> void:
	var strong := Reputation.player_adjustment(900, 0, 30, 8.0, 60)
	var weak := Reputation.player_adjustment(200, 0, 30, 8.0, 60)
	var bench := Reputation.player_adjustment(900, 16, 0, 8.0, 60)
	_assert(strong > weak and strong > 0, "a breakout in a strong division is worth more")
	_assert(strong <= Reputation.PLAYER_RESULT_CAP, "a player result stays inside its cap")
	_assert(bench == 0, "a player without minutes does not move on results")


func _test_player_result_stays_inside_the_drift_cap() -> void:
	_assert(
		Reputation.settled_player_reputation(500, 535, 15) == 535,
		"drift already at the cap leaves no extra room"
	)
	_assert(
		Reputation.settled_player_reputation(500, 500, 12) == 512,
		"a result still lands when fame already matches ability"
	)
	_assert(
		Reputation.settled_player_reputation(500, 490, 15) == 505,
		"a good season can offset a fading drift"
	)


func _test_a_finished_division_rewrites_both_club_copies() -> void:
	var division := _division_unit()
	var cup := {
		"unit_kind": "CUP",
		"competition_type": "CUP",
		"clubs_by_id": {
			1: {"id": 1, "name": "Фаворит", "reputation": 820},
			2: {"id": 2, "name": "Аутсайдер", "reputation": 420},
		},
		"matches": [],
		"standings": [],
	}
	var plan := Reputation.plan([division, cup], 1, func(player_id: int) -> Dictionary:
		if player_id == 7:
			return {"id": 7, "current_ability": 60, "reputation": 400}
		return {}
	)
	var clubs: Dictionary = plan.get("clubs", {})
	_assert(int(clubs[2].get("delta", 0)) > int(clubs[1].get("delta", 0)), "the preview outsider gains more than the favorite")
	Reputation.write_clubs([division, cup], clubs)
	_assert(
		int(division["clubs_by_id"][2]["reputation"]) == int(cup["clubs_by_id"][2]["reputation"]),
		"both copies of the club take the new reputation"
	)
	_assert(int(division["clubs_by_id"][2]["reputation"]) > 420, "the outsider's reputation rises")
	var players: Dictionary = plan.get("players", {})
	_assert(int(players.get(7, 0)) > 0, "a regular who outplayed his ability gains reputation")
	_assert(int(players.get(8, 0)) == 0, "an unused player is left to the ordinary drift")


func _division_unit() -> Dictionary:
	return {
		"unit_kind": "DIVISION",
		"competition_type": "DIVISIONS",
		"division_strength": 800,
		"season_preview": {
			"season": 1,
			"sections": [{
				"id": "regular",
				"kind": "table",
				"index": -1,
				"rows": [
					{"club_id": 1, "place": 1, "title_chance": 70},
					{"club_id": 2, "place": 2, "title_chance": 10},
				],
			}],
		},
		"matches": [{"stage": "REGULAR", "played": true}],
		"standings": [
			{"club_id": 2, "division": 0, "points": 40, "goal_diff": 10, "goals_for": 30},
			{"club_id": 1, "division": 0, "points": 20, "goal_diff": -4, "goals_for": 12},
		],
		"clubs_by_id": {
			1: {"id": 1, "name": "Фаворит", "reputation": 820},
			2: {"id": 2, "name": "Аутсайдер", "reputation": 420},
		},
		"season_player_stats": {
			7: {"player_id": 7, "club_id": 2, "matches": 30, "rating_sum": 240.0},
			8: {"player_id": 8, "club_id": 2, "matches": 0, "rating_sum": 0.0},
		},
		"rules": {},
		"playoff": {"enabled": false},
	}


func _assert(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	print("%d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)
