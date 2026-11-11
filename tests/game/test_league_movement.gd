extends Node

const Movement := preload("res://game/league_movement.gd")
const Store := preload("res://game/save_store.gd")
var _passed: int = 0
var _failed: int = 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_simultaneous_pyramid()
	_test_pool_quotas_and_remainder()
	_test_overall_and_ranking()
	_test_unequal_quotas()
	_test_invalid_rules()
	_test_zone_marks()
	_test_fixture_membership()
	_test_actual_new_season_and_save()
	GameSession.clear()
	Store.database_path_override = ""
	print("=== League movement: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed else 0)

func _assert(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error(message)

func _unit(id: int, level: int, groups: Array, up: int, down: int, competition: int = 1) -> Dictionary:
	var divisions: Array = []
	var rows: Array = []
	var clubs: Dictionary = {}
	for d in groups.size():
		divisions.append({"index": d, "club_ids": groups[d].duplicate()})
		for i in groups[d].size():
			var cid := int(groups[d][i])
			clubs[cid] = {"id": cid, "name": "Club %d" % cid, "reputation": 500, "country_id": 0}
			rows.append({"club_id": cid, "division": d, "played": 6, "points": 30 - i * 5 - d, "goal_diff": 4 - i, "won": 3 - i, "goals_for": 10 - i, "goals_against": 3 + i})
	return {"id": id, "competition_id": competition, "unit_kind": "DIVISION", "competition_type": "DIVISIONS", "name": "League %d" % id,
		"rules": {"level": level, "teams_promote": up, "teams_relegate": down, "movement_scope": "OVERALL", "divisions_count": groups.size(), "teams_per_division": groups[0].size(), "matches_vs_own": 2, "matches_vs_other": 0},
		"divisions": divisions, "standings": rows, "clubs_by_id": clubs, "matches": [], "playoff": {"enabled": false}, "winners": [{"season": 1, "club_id": groups[0][0]}]}

func _ids(unit: Dictionary) -> Array:
	var ids := Movement._club_ids(unit)
	ids.sort()
	return ids

func _test_simultaneous_pyramid() -> void:
	var upper := _unit(1, 1, [[1, 2, 3, 4]], 0, 1)
	var middle := _unit(2, 2, [[5, 6, 7, 8]], 1, 1)
	var lower := _unit(3, 3, [[9, 10, 11, 12]], 1, 0)
	var unrelated := _unit(4, 1, [[20, 21]], 0, 0, 2)
	var cup := upper.duplicate(true)
	cup["unit_kind"] = "CUP"
	cup["competition_type"] = "CUP"
	var units := [lower, unrelated, upper, cup, middle]
	var result := Movement.plan(units, GameSession.sorted_standings)
	_assert(result["success"], "unordered pyramid planned")
	_assert(result.get("data", []).size() == 4, "four transfers between three leagues")
	_assert(_ids(upper) == [1, 2, 3, 4], "planning does not modify final season")
	# Apply after the season's reputation adjustment to check club data freshness.
	lower["clubs_by_id"][9]["reputation"] = 620
	Movement.apply(units, result["data"])
	_assert(_ids(upper) == [1, 2, 3, 5], "upper league swaps its last club for middle winner")
	_assert(_ids(middle) == [4, 6, 7, 9], "middle receives both neighbours without a second promotion")
	_assert(_ids(lower) == [8, 10, 11, 12], "lower receives middle loser")
	_assert(middle["clubs_by_id"][9]["reputation"] == 620, "moved club keeps post-season reputation")
	_assert(not middle["clubs_by_id"].has(5) and upper["clubs_by_id"].has(5), "club lookup moves with membership")
	_assert(_ids(cup) == [1, 2, 3, 4] and _ids(unrelated) == [20, 21], "cups and other competitions unaffected")

func _test_pool_quotas_and_remainder() -> void:
	var upper := _unit(1, 1, [[1, 2], [3, 4], [5, 6]], 0, 2)
	upper["rules"]["movement_scope"] = "PER_DIVISION"
	var lower := _unit(2, 2, [[7, 8], [9, 10], [11, 12]], 2, 0)
	lower["rules"]["movement_scope"] = "PER_DIVISION"
	var units := [upper, lower]
	var result := Movement.plan(units, GameSession.sorted_standings)
	_assert(result["success"] and result["data"].size() == 4, "two places across three pools are not rounded down to zero")
	Movement.apply(units, result["data"])
	_assert(_ids(upper) == [1, 2, 3, 5, 7, 9], "worst pool runners-up relegate, best pool winners promote")
	_assert(_ids(lower) == [4, 6, 8, 10, 11, 12], "remainder uses final ranking")
	_assert(CompetitionUnitRepository.movement_quota_hint(2, 3, "PER_DIVISION").contains("0–1"), "quota hint explains remainder")
	upper = _unit(1, 1, [[1, 2], [3, 4]], 0, 2)
	lower = _unit(2, 2, [[5, 6], [7, 8]], 2, 0)
	upper["rules"]["movement_scope"] = "PER_DIVISION"
	lower["rules"]["movement_scope"] = "PER_DIVISION"
	result = Movement.plan([upper, lower], GameSession.sorted_standings)
	Movement.apply([upper, lower], result["data"])
	_assert(_ids(upper) == [1, 3, 5, 7], "even quota takes one club per pool")

func _test_overall_and_ranking() -> void:
	var upper := _unit(1, 1, [[1, 2], [3, 4]], 0, 2)
	var lower := _unit(2, 2, [[5, 6], [7, 8]], 2, 0)
	lower["standings"][0]["points"] = 100
	lower["standings"][1]["points"] = 90
	var result := Movement.plan([upper, lower], GameSession.sorted_standings)
	Movement.apply([upper, lower], result["data"])
	_assert(_ids(upper) == [1, 3, 5, 6], "overall selection can promote two clubs from the same pool")
	upper = _unit(1, 1, [[1, 2]], 0, 1)
	lower = _unit(2, 2, [[3, 4]], 1, 0)
	lower["rules"]["ranking_order"] = ["GOAL_DIFF", "POINTS"]
	lower["standings"][1]["goal_diff"] = 99
	result = Movement.plan([upper, lower], GameSession.sorted_standings)
	Movement.apply([upper, lower], result["data"])
	_assert(_ids(upper) == [1, 4], "configured ranking criteria determine promotion")

func _test_invalid_rules() -> void:
	var upper := _unit(1, 1, [[1, 2]], 0, 1)
	_assert(not Movement.plan([upper], GameSession.sorted_standings)["success"], "missing destination produces a useful error")
	var lower := _unit(2, 1, [[3, 4]], 1, 0)
	_assert(not Movement.plan([upper, lower], GameSession.sorted_standings)["success"], "ambiguous levels rejected")
	lower["rules"]["level"] = 2
	lower["rules"]["teams_promote"] = 3
	_assert(not Movement.plan([upper, lower], GameSession.sorted_standings)["success"], "oversized quotas rejected before changes")
	lower = _unit(2, 2, [[1, 3]], 1, 0)
	_assert(not Movement.plan([upper, lower], GameSession.sorted_standings)["success"], "duplicate league membership rejected")
	upper["rules"]["teams_relegate"] = 0
	_assert(Movement.plan([upper], GameSession.sorted_standings)["data"].is_empty(), "disabled movement keeps a standalone league playable")
	var middle := _unit(2, 2, [[3, 4]], 2, 1)
	lower = _unit(3, 3, [[5, 6]], 0, 0)
	_assert(not Movement.plan([upper, middle, lower], GameSession.sorted_standings)["success"], "a club cannot promote and relegate in the same season")

func _test_unequal_quotas() -> void:
	var upper := _unit(1, 1, [[1, 2], [3, 4]], 0, 2)
	var lower := _unit(2, 2, [[5, 6], [7, 8]], 1, 0)
	var units := [upper, lower]
	var result := Movement.plan(units, GameSession.sorted_standings)
	Movement.apply(units, result["data"])
	_assert(_ids(upper) == [1, 3, 5] and _ids(lower) == [2, 4, 6, 7, 8], "unequal quotas retain every club without duplicates")
	var next := GameSession._reset_unit_for_new_season(lower)
	_assert(_ids(next) == [2, 4, 6, 7, 8], "reset never drops clubs beyond configured capacity")
	var actual_pairs: Dictionary = {}
	for match_row in next["matches"]:
		actual_pairs[int(match_row["home_id"])] = true
		actual_pairs[int(match_row["away_id"])] = true
	_assert(actual_pairs.size() == 5, "every participant receives fixtures after one-way movement")

func _test_zone_marks() -> void:
	var standalone := _unit(1, 1, [[1, 2, 3, 4]], 1, 1)
	var marks: Dictionary = Movement.zone_club_ids(standalone, GameSession.sorted_standings)
	_assert(marks["promote"] == [1], "promotion places stay visible without a higher league")
	_assert(marks["relegate"] == [4], "relegation places stay visible without a lower league")

	var pools := _unit(1, 1, [[1, 2], [3, 4], [5, 6]], 2, 0)
	pools["rules"]["movement_scope"] = "PER_DIVISION"
	marks = Movement.zone_club_ids(pools, GameSession.sorted_standings)
	_assert(marks["promote"] == [1, 3], "per-division remainder marks the same clubs movement would move")
	_assert((marks["relegate"] as Array).is_empty(), "a zero relegation quota marks nobody")

	var lower := _unit(2, 2, [[5, 6], [7, 8]], 2, 1)
	marks = Movement.zone_club_ids(lower, GameSession.sorted_standings)
	_assert(marks["promote"] == [5, 7], "overall promotion follows the combined table")
	_assert(marks["relegate"] == [8], "overall relegation takes the bottom of the combined table")

	var tight := _unit(3, 1, [[1, 2, 3]], 2, 2)
	marks = Movement.zone_club_ids(tight, GameSession.sorted_standings)
	_assert(marks["promote"] == [1, 2] and marks["relegate"] == [3], "a club is not marked for both promotion and relegation")


func _test_fixture_membership() -> void:
	var divisions := [{"index": 0, "club_ids": [1, 3]}, {"index": 1, "club_ids": [2, 4, 5]}]
	var generated := FixtureGenerator.build_regular_season([1, 2, 3, 4, 5], 2, 2, 2, 0, null, divisions)
	_assert(generated["divisions"] == divisions, "new fixtures preserve actual pools even when configured capacity differs")
	_assert(generated["matches"].size() == 8, "all clubs get correct home and away fixtures")
	for match_row in generated["matches"]:
		_assert(not (int(match_row["home_id"]) == 1 and int(match_row["away_id"]) == 2), "clubs from different pools never play when cross meetings disabled")

func _test_actual_new_season_and_save() -> void:
	Store.database_path_override = "user://tests/league_movement/games.db"
	GameSession.clear()
	var upper := _unit(1, 1, [[1, 2]], 0, 1)
	var lower := _unit(2, 2, [[3, 4]], 1, 0)
	var payload := {"version": GameSession.SAVE_VERSION, "season_number": 4, "season_day": 20, "season_finished": true,
		"units": [upper, lower], "players_by_club": {}, "youth_players_by_club": {}, "reserve_players_by_club": {}, "free_agents": [],
		"coaches_by_club": {}, "club_budgets": {1: 1000, 2: 2000, 3: 3000, 4: 4000}, "transfer_log": [], "next_player_id": 1}
	_assert(GameSession.apply_save_payload(payload)["success"], "finished session loads")
	var started := GameSession.start_new_season()
	_assert(started["success"], "actual new-season pipeline succeeds: %s" % started.get("error", ""))
	_assert(GameSession.season_number == 5, "season increments once")
	_assert(_ids(GameSession.units[0]) == [1, 3] and _ids(GameSession.units[1]) == [2, 4], "actual pipeline applies promotion and relegation before fixture reset")
	_assert(GameSession.units[0]["standings"][0]["played"] == 0, "new standings start empty")
	_assert(GameSession.units[0]["winners"] == upper["winners"], "winners history survives")
	_assert(GameSession.get_club_budget(3) == 3000, "promotion preserves club finances")
	_assert(GameSession.units[0]["matches"].size() == 2, "new league has regenerated fixtures")
	_assert(GameSession.save_game("zz_league_movement")["success"], "moved membership saves")
	GameSession.clear()
	_assert(GameSession.load_game("zz_league_movement")["success"], "moved membership loads")
	_assert(_ids(GameSession.units[0]) == [1, 3] and GameSession.units[0]["clubs_by_id"].has(3), "save roundtrip retains promoted participants and club lookup")
	GameSession.delete_save("zz_league_movement")
	GameSession.clear()
	upper["rules"]["teams_promote"] = 1
	payload["units"] = [upper, lower]
	GameSession.apply_save_payload(payload)
	var before := GameSession.units.duplicate(true)
	var rejected := GameSession.start_new_season()
	_assert(not rejected["success"], "invalid pyramid blocks season rollover")
	_assert(GameSession.season_number == 4 and GameSession.season_finished, "rejected rollover leaves season unchanged")
	_assert(GameSession.units == before, "rejected rollover leaves standings and participants unchanged")
