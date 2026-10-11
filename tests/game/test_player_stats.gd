extends Node
## Career stints, substitute apps, and mid-season transfer fees.
## Run: godot --headless --path . res://tests/game/test_player_stats.tscn

const PlayerStatsScript := preload("res://game/player_stats.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Player stats tests ===")
	_test_substitute_apps()
	_test_mid_season_split_and_fee()
	_test_free_transfer_label()
	_test_timeline_and_totals()
	_test_fee_from_transfer_log()
	_test_minutes_across_clubs()
	_finish()


func _test_substitute_apps() -> void:
	var row := {"matches": 20, "starts": 17}
	_assert(PlayerStatsScript.substitute_apps(row) == 3, "subs are matches minus starts")
	_assert(PlayerStatsScript.substitute_apps({"matches": 8}) == 8, "missing starts counts as all subs")


func _test_mid_season_split_and_fee() -> void:
	var player := _player(1, 10)
	PlayerStatsScript.ensure_state(player, 3)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 2, 1), 3, 10)
	PlayerStatsScript.apply_entry(player, _entry(false, 20, 0, 0), 3, 10)
	PlayerStatsScript.begin_club_stint(player, 3, 20, 2_500_000)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 1, 0), 3, 20)

	var old_stint: Dictionary = PlayerStatsScript.career_of(player)[0]
	_assert(int(old_stint.get("club_id", 0)) == 10, "first club is archived")
	_assert(int(old_stint.get("matches", 0)) == 2, "first club keeps both appearances")
	_assert(int(old_stint.get("starts", 0)) == 1, "first club keeps the start")
	_assert(PlayerStatsScript.substitute_apps(old_stint) == 1, "one substitute appearance at the first club")
	_assert(not old_stint.has("transfer_fee"), "the club he left does not show a fee")

	var current: Dictionary = PlayerStatsScript.season_of(player)
	_assert(int(current.get("club_id", 0)) == 20, "current stint is the buying club")
	_assert(int(current.get("matches", 0)) == 1, "new club starts a fresh row")
	_assert(int(current.get("goals", 0)) == 1, "goals after the move stay on the new club")
	_assert(int(current.get("transfer_fee", -1)) == 2_500_000, "buying club stores the fee")


func _test_free_transfer_label() -> void:
	var player := _player(2, 4)
	PlayerStatsScript.ensure_state(player, 1)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 0, 0), 1, 4)
	PlayerStatsScript.begin_club_stint(player, 1, 7, 0)
	_assert(PlayerStatsScript.season_of(player).has("transfer_fee"), "zero fee is stored")
	_assert(int(PlayerStatsScript.season_of(player).get("transfer_fee", -1)) == 0, "a free move stores 0, not missing")


func _test_timeline_and_totals() -> void:
	var player := _player(3, 1)
	PlayerStatsScript.ensure_state(player, 1)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 1, 0), 1, 1)
	PlayerStatsScript.roll_season(player, 2, 1)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 2, 1), 2, 1)
	PlayerStatsScript.begin_club_stint(player, 2, 9, 1000)
	PlayerStatsScript.apply_entry(player, _entry(false, 15, 0, 1), 2, 9)

	var rows: Array = PlayerStatsScript.timeline(player)
	_assert(rows.size() == 3, "timeline has one finished season plus two stints")
	_assert(int((rows[0] as Dictionary).get("club_id", 0)) == 9, "newest stint is first")
	_assert(int((rows[1] as Dictionary).get("club_id", 0)) == 1, "the club he left this season is next")
	_assert(int((rows[2] as Dictionary).get("season", 0)) == 1, "older seasons follow")
	_assert(PlayerStatsScript.seasons_played(player) == 2, "two clubs in one season still count as one season")
	_assert(int(PlayerStatsScript.career_totals(player).get("matches", 0)) == 3, "totals sum every stint")
	_assert(int(PlayerStatsScript.career_totals(player).get("goals", 0)) == 3, "goals from both clubs add up")


func _test_fee_from_transfer_log() -> void:
	var player := _player(4, 8)
	player["career_stats"] = [
		{
			"season": 5,
			"club_id": 3,
			"matches": 10,
			"starts": 10,
			"goals": 2,
			"rating_sum": 70.0,
		},
		{
			"season": 5,
			"club_id": 8,
			"matches": 12,
			"starts": 12,
			"goals": 4,
			"rating_sum": 80.0,
		},
	]
	var log := [{
		"player_id": 4,
		"season": 5,
		"club_id": 8,
		"direction": "in",
		"fee": 750000,
		"other_club": "Динамо",
	}]
	var rows: Array = PlayerStatsScript.with_transfer_fees(PlayerStatsScript.timeline(player), log, 4)
	_assert(rows.size() == 2, "two clubs in one season stay two stints")
	var bought: Dictionary = rows[0]
	var left: Dictionary = rows[1]
	_assert(int(bought.get("club_id", 0)) == 8, "newest club is first")
	_assert(int(bought.get("transfer_fee", -1)) == 750000, "log fills a missing fee on the buying club")
	_assert(not left.has("transfer_fee"), "the club he left does not get a fee from the log")

	var single := _player(6, 8)
	single["career_stats"] = [{
		"season": 5,
		"club_id": 8,
		"matches": 12,
		"starts": 12,
		"rating_sum": 80.0,
	}]
	var summer_log := [{
		"player_id": 6,
		"season": 5,
		"club_id": 8,
		"direction": "in",
		"fee": 750000,
		"other_club": "Динамо",
	}]
	var summer: Array = PlayerStatsScript.with_transfer_fees(PlayerStatsScript.timeline(single), summer_log, 6)
	_assert(not (summer[0] as Dictionary).has("transfer_fee"), "a single-club season does not show a window fee")


func _test_minutes_across_clubs() -> void:
	var player := _player(5, 2)
	PlayerStatsScript.ensure_state(player, 4)
	PlayerStatsScript.apply_entry(player, _entry(true, 90, 0, 0), 4, 2)
	PlayerStatsScript.begin_club_stint(player, 4, 3, 1)
	PlayerStatsScript.apply_entry(player, _entry(true, 45, 0, 0), 4, 3)
	_assert(PlayerStatsScript.minutes_in_season(player, 4) == 135, "season minutes include both clubs")


func _player(id: int, club_id: int) -> Dictionary:
	return {"id": id, "club_id": club_id, "name": "Test"}


func _entry(started: bool, minutes: int, goals: int, assists: int) -> Dictionary:
	return {
		"minutes": minutes,
		"started": started,
		"goals": goals,
		"assists": assists,
		"saves": 0,
		"conceded": 0,
		"clean_sheet": false,
		"yellow": 0,
		"red": 0,
		"injury_rounds": 0,
		"pen_scored": 0,
		"pen_missed": 0,
		"pen_saved": 0,
		"motm": false,
		"rating": 7.0,
	}


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
