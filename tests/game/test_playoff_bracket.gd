extends Node
## Playoff bracket slots stay on their wing until the final.
## Run: godot --headless --path . res://tests/game/test_playoff_bracket.tscn

const PlayoffManagerScript := preload("res://game/playoff_manager.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Playoff bracket tests ===")
	_test_overall_seeds_sit_on_opposite_halves()
	_test_cross_group_wings()
	_test_winners_stay_on_the_same_wing()
	_test_right_wing_team_does_not_jump_left()
	_test_season_result_keeps_playoff_and_table()
	_test_qualifier_ids_follow_scope()
	_test_standings_table_zones()
	_test_history_view_builds()
	_finish()


func _cross_unit(per_group: int) -> Dictionary:
	var unit := {"id": 11, "rules": {}, "clubs_by_id": {}, "matches": [], "standings": [], "divisions": [{"index": 0, "club_ids": []}, {"index": 1, "club_ids": []}], "playoff": {"enabled": true, "teams": per_group * 2, "format": PlayoffRules.FORMAT_SINGLE, "scope": "PER_DIVISION", "seeding": PlayoffRules.SEEDING_CROSS}, "winners": []}
	for group in 2:
		for rank in range(1, per_group + 1):
			var id := group * 100 + rank
			unit["divisions"][group]["club_ids"].append(id)
			unit["clubs_by_id"][id] = {"id": id, "name": "%s%d" % ["A" if group == 0 else "B", rank]}
			unit["standings"].append({"club_id": id, "division": group, "points": (per_group - rank + 1) * 3})
	return unit


func _test_cross_group_wings() -> void:
	var unit := _cross_unit(8)
	var started := PlayoffManagerScript.maybe_start(unit, 10, 1)
	var expected := [[1, 108], [3, 106], [2, 107], [4, 105], [101, 8], [103, 6], [102, 7], [104, 5]]
	var first := _series_of_round(unit, 1)
	_assert(first.size() == expected.size(), "cross seeding creates eight matches for sixteen qualifiers")
	for i in mini(first.size(), expected.size()):
		_assert(_pair_of(first[i]) == expected[i] and int(first[i]["slot"]) == i, "cross slot %d matches the requested A/B order" % i)
	_finish_current_round(unit, func(series): return int(series["home_id"]))
	var progressed := PlayoffManagerScript.after_day_simulated(unit, 11, int(started["next_match_id"]), 1)
	var quarters := _series_of_round(unit, 2)
	_assert(quarters.size() == 4 and _pair_of(quarters[0]) == [1, 3] and _pair_of(quarters[1]) == [2, 4], "A1 and A2 enter separate quarterfinals")
	_assert(_pair_of(quarters[2]) == [101, 103] and _pair_of(quarters[3]) == [102, 104], "B1 and B2 enter separate quarterfinals")
	_finish_current_round(unit, func(series): return int(series["home_id"]))
	progressed = PlayoffManagerScript.after_day_simulated(unit, 12, int(progressed["next_match_id"]), 1)
	var semis := _series_of_round(unit, 3)
	_assert(_pair_of(semis[0]) == [1, 2] and _pair_of(semis[1]) == [101, 102], "group leaders can meet their runner-up only in the semifinal")
	_finish_current_round(unit, func(series): return int(series["home_id"]))
	PlayoffManagerScript.after_day_simulated(unit, 13, int(progressed["next_match_id"]), 1)
	_assert(_pair_of(_series_of_round(unit, 4)[0]) == [1, 101], "A1 and B1 remain apart until the final")
	for per_group in [1, 2, 4, 16]:
		var scaled := _cross_unit(per_group)
		PlayoffManagerScript.maybe_start(scaled, 1, 1)
		var seen: Array = []
		for series in _series_of_round(scaled, 1):
			seen.append_array(_pair_of(series))
		seen.sort()
		var qualifiers := PlayoffManagerScript.qualifier_ids(scaled)
		qualifiers.sort()
		_assert(seen == qualifiers, "cross seeding includes each qualifier once: %d teams" % (per_group * 2))
	var unequal := _cross_unit(4)
	var eligible: Array = [1, 2, 3, 101]
	var fallback := PlayoffManagerScript._cross_seed_pairs(unequal, eligible)
	var seen: Array = []
	for pair in fallback:
		seen.append_array([pair["home_id"], pair["away_id"]])
	seen.sort()
	_assert(seen == eligible, "unequal groups never admit a team which did not qualify")


func _test_overall_seeds_sit_on_opposite_halves() -> void:
	var unit := _eight_team_unit()
	var started: Dictionary = PlayoffManagerScript.maybe_start(unit, 10, 1)
	_assert(bool(started.get("started", false)), "playoff starts after the regular season")
	var round1 := _series_of_round(unit, 1)
	_assert(round1.size() == 4, "eight teams make four first-round series")
	_assert(_pair_of(round1[0]) == [1, 8], "seed 1 opens the left wing vs 8")
	_assert(_pair_of(round1[1]) == [4, 5], "4 vs 5 stay on the left")
	_assert(_pair_of(round1[2]) == [2, 7], "seed 2 opens the right wing vs 7")
	_assert(_pair_of(round1[3]) == [3, 6], "3 vs 6 stay on the right")
	_assert(int(round1[0].get("slot", -1)) == 0, "left-top has slot 0")
	_assert(int(round1[2].get("slot", -1)) == 2, "right-top has slot 2")


func _test_winners_stay_on_the_same_wing() -> void:
	var unit := _eight_team_unit()
	PlayoffManagerScript.maybe_start(unit, 10, 1)
	_finish_current_round(unit, func(series: Dictionary) -> int:
		return int(series.get("home_id", 0))
	)
	PlayoffManagerScript.after_day_simulated(unit, 11, 20, 1)
	var qf := _series_of_round(unit, 2)
	_assert(qf.size() == 2, "four winners make two semifinals")
	_assert(_pair_of(qf[0]) == [1, 4], "left-wing winners meet on the left")
	_assert(_pair_of(qf[1]) == [2, 3], "right-wing winners meet on the right")
	_assert(int(qf[0].get("slot", -1)) == 0, "left semi keeps slot 0")
	_assert(int(qf[1].get("slot", -1)) == 1, "right semi keeps slot 1")

	_finish_current_round(unit, func(series: Dictionary) -> int:
		return int(series.get("home_id", 0))
	)
	PlayoffManagerScript.after_day_simulated(unit, 12, 40, 1)
	var final_series := _series_of_round(unit, 3)
	_assert(final_series.size() == 1, "two semi winners make the final")
	_assert(_pair_of(final_series[0]) == [1, 2], "1 and 2 meet only in the final")


func _test_right_wing_team_does_not_jump_left() -> void:
	var unit := _eight_team_unit()
	PlayoffManagerScript.maybe_start(unit, 10, 1)
	# 7 (right) and 6 (right) advance; left stays 1 and 4.
	_finish_current_round(unit, func(series: Dictionary) -> int:
		var home_id := int(series.get("home_id", 0))
		var away_id := int(series.get("away_id", 0))
		if away_id == 7 or away_id == 6:
			return away_id
		return home_id
	)
	PlayoffManagerScript.after_day_simulated(unit, 11, 20, 1)
	var qf := _series_of_round(unit, 2)
	_assert(qf.size() == 2, "semifinals exist")
	_assert(_pair_of(qf[0]) == [1, 4], "left is still 1 vs 4")
	_assert(_ids_of(qf[1]).has(7) and _ids_of(qf[1]).has(6), "7 stays on the right vs 6")
	_assert(not _ids_of(qf[0]).has(7), "7 does not jump to the left semi")


func _eight_team_unit() -> Dictionary:
	var standings: Array = []
	var club_ids: Array = []
	for i in 8:
		var club_id := i + 1
		club_ids.append(club_id)
		standings.append({
			"club_id": club_id,
			"division": 0,
			"played": 7,
			"won": 7 - i,
			"drawn": 0,
			"lost": i,
			"goals_for": 20 - i,
			"goals_against": i,
			"goal_diff": 20 - i * 2,
			"points": 21 - i * 3,
		})
	return {
		"matches": [],
		"divisions": [{"index": 0, "club_ids": club_ids}],
		"standings": standings,
		"rules": {"ranking_order": null},
		"clubs_by_id": {},
		"winners": [],
		"playoff": {
			"enabled": true,
			"started": false,
			"finished": false,
			"teams": 8,
			"format": PlayoffRules.FORMAT_SINGLE,
			"seeding": PlayoffRules.SEEDING_OVERALL,
			"scope": CompetitionUnitRepository.SCOPE_OVERALL,
			"third_place": false,
			"current_round": 0,
			"champion_id": 0,
			"series": [],
			"matches": [],
		},
	}


func _test_season_result_keeps_playoff_and_table() -> void:
	var unit := {
		"standings": [
			{"club_id": 1, "points": 40, "goal_diff": 12, "goals_for": 30, "won": 12},
			{"club_id": 2, "points": 35, "goal_diff": 8, "goals_for": 24, "won": 10},
			{"club_id": 3, "points": 30, "goal_diff": 4, "goals_for": 20, "won": 9},
			{"club_id": 4, "points": 20, "goal_diff": -2, "goals_for": 14, "won": 6},
		],
		"rules": {},
		"clubs_by_id": {
			1: {"name": "Альфа"},
			2: {"name": "Бета"},
			3: {"name": "Гамма"},
			4: {"name": "Дельта"},
		},
		"winners": [],
		"playoff": {
			"enabled": true,
			"champion_id": 1,
			"third_place": true,
			"series": [
				{"round": 1, "complete": true, "winner_id": 1, "home_id": 1, "away_id": 4, "is_third_place": false},
				{"round": 1, "complete": true, "winner_id": 2, "home_id": 2, "away_id": 3, "is_third_place": false},
				{"round": 2, "complete": true, "winner_id": 1, "home_id": 1, "away_id": 2, "is_third_place": false},
				{"round": 2, "complete": false, "winner_id": 0, "home_id": 4, "away_id": 3, "is_third_place": true},
			],
		},
	}
	PlayoffManagerScript.record_season_result(unit, 4)
	var first: Dictionary = unit["winners"][0]
	var playoff: Array = first.get("playoff", [])
	_assert(playoff.size() == 2, "before the third-place match only the final is settled")
	_assert(int(playoff[0].get("club_id", 0)) == 1 and int(playoff[1].get("club_id", 0)) == 2, "final winner is 1st, loser is 2nd")
	var regular: Array = first.get("regular", [])
	_assert(regular.size() == 3, "regular season keeps the top three")
	_assert(int(regular[0].get("club_id", 0)) == 1 and int(regular[2].get("club_id", 0)) == 3, "table order is points")

	var third: Dictionary = unit["playoff"]["series"][3]
	third["complete"] = true
	third["winner_id"] = 4
	PlayoffManagerScript.record_season_result(unit, 4)
	playoff = unit["winners"][0].get("playoff", [])
	_assert(playoff.size() == 4, "the same season gains 3rd and 4th")
	_assert(int(playoff[2].get("club_id", 0)) == 4 and int(playoff[3].get("club_id", 0)) == 3, "third-place winner is 3rd")
	_assert(unit["winners"].size() == 1, "refreshing the season does not add a second row")

	var no_third := unit.duplicate(true)
	var series: Array = no_third["playoff"]["series"]
	series.pop_back()
	no_third["playoff"]["series"] = series
	no_third["winners"] = []
	PlayoffManagerScript.record_season_result(no_third, 5)
	var ranked: Array = no_third["winners"][0].get("playoff", [])
	_assert(ranked.size() == 4, "without a third-place match the semi losers fill 3rd and 4th")
	_assert(int(ranked[2].get("club_id", 0)) == 3 and int(ranked[3].get("club_id", 0)) == 4, "the better regular-season side is 3rd")

	var league := {
		"matches": [{"stage": "REGULAR", "played": true}],
		"standings": [
			{"club_id": 1, "points": 10, "goal_diff": 4, "goals_for": 8, "won": 3},
			{"club_id": 2, "points": 7, "goal_diff": 1, "goals_for": 5, "won": 2},
		],
		"rules": {},
		"clubs_by_id": {1: {"name": "Альфа"}, 2: {"name": "Бета"}},
		"winners": [],
		"playoff": {"enabled": false},
	}
	PlayoffManagerScript.capture_season_if_ready(league, 2)
	_assert(league["winners"].size() == 1, "a league without a playoff still records the season")
	_assert((league["winners"][0].get("playoff", []) as Array).is_empty(), "no playoff places without a playoff")
	_assert(int(league["winners"][0].get("club_id", 0)) == 1, "the table leader is the recorded champion")


func _test_qualifier_ids_follow_scope() -> void:
	var unit := _eight_team_unit()
	unit["playoff"]["teams"] = 4
	_assert(PlayoffManagerScript.qualifier_ids(unit) == [1, 2, 3, 4], "overall playoff marks the top of the table")
	unit["playoff"]["enabled"] = false
	_assert(PlayoffManagerScript.qualifier_ids(unit).is_empty(), "a disabled playoff marks nobody")

	unit = _eight_team_unit()
	unit["divisions"] = [
		{"index": 0, "club_ids": [1, 2, 3, 4]},
		{"index": 1, "club_ids": [5, 6, 7, 8]},
	]
	for row in unit["standings"]:
		if int(row["club_id"]) > 4:
			row["division"] = 1
	unit["playoff"]["teams"] = 4
	unit["playoff"]["scope"] = CompetitionUnitRepository.SCOPE_PER_DIVISION
	_assert(PlayoffManagerScript.qualifier_ids(unit) == [1, 2, 5, 6], "each division sends its own top clubs")


func _test_standings_table_zones() -> void:
	var was_active := GameSession.is_active
	GameSession.is_active = true
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var unit := _eight_team_unit()
	unit["divisions"] = [
		{"index": 0, "club_ids": [1, 2, 3, 4]},
		{"index": 1, "club_ids": [5, 6, 7, 8]},
	]
	for row in unit["standings"]:
		if int(row["club_id"]) > 4:
			row["division"] = 1
	unit["rules"]["teams_promote"] = 1
	unit["rules"]["teams_relegate"] = 1
	unit["rules"]["movement_scope"] = "OVERALL"
	unit["playoff"]["teams"] = 4
	unit["playoff"]["scope"] = "OVERALL"
	screen._table_mode = screen.TABLE_MODE_DIVISIONS
	screen._clear_content()
	screen._build_table_view(unit)
	var content: Node = screen.get_node("%Content")
	var text := _gather_text(content)
	_assert("Дивизионы" in text and "Общая таблица" in text, "table mode is a compact switch")
	_assert("Вид таблицы" not in text, "the stretched table select is gone")
	_assert(content.find_children("*", "WeSelectField", true, false).is_empty(), "the table page does not host a select")
	_assert("Повышение" in text and "Плей-офф" in text and "Понижение" in text, "legend names promotion, playoff and relegation")
	_assert("Дивизион 1" in text and "Дивизион 2" in text, "division titles sit on the cards")
	var zones: Dictionary = screen._standing_zones(unit)
	_assert(str(zones.get(1, "")) == "promote", "the combined leader is in the promotion zone")
	_assert(str(zones.get(2, "")) == "playoff" and str(zones.get(4, "")) == "playoff", "the next overall places stay in the playoff")
	_assert(str(zones.get(8, "")) == "relegate", "the last club is in the relegation zone")
	screen.queue_free()
	GameSession.is_active = was_active


func _test_history_view_builds() -> void:
	var was_active := GameSession.is_active
	GameSession.is_active = true
	var packed: PackedScene = load("res://scenes/game/game_screen.tscn")
	_assert(packed != null, "winners history screen still parses")
	var screen := packed.instantiate()
	add_child(screen)
	var unit := {
		"playoff": {"enabled": true},
		"clubs_by_id": {
			1: {"name": "Альфа"},
			2: {"name": "Бета"},
			3: {"name": "Гамма"},
		},
		"winners": [
			{
				"season": 3,
				"club_id": 1,
				"club_name": "Альфа",
				"place": 1,
				"playoff": [
					{"place": 1, "club_id": 1, "club_name": "Альфа"},
					{"place": 2, "club_id": 2, "club_name": "Бета"},
					{"place": 3, "club_id": 3, "club_name": "Гамма"},
					{"place": 4, "club_id": 4, "club_name": "Дельта"},
				],
				"regular": [
					{"place": 1, "club_id": 1, "club_name": "Альфа", "points": 40, "goal_diff": 12},
					{"place": 2, "club_id": 2, "club_name": "Бета", "points": 35, "goal_diff": 8},
					{"place": 3, "club_id": 3, "club_name": "Гамма", "points": 30, "goal_diff": 4},
				],
			},
			{"season": 1, "club_id": 1, "club_name": "Альфа", "place": 1},
		],
	}
	var entries: Array = screen._history_entries(unit["winners"])
	var playoff_medals: Array = screen._history_medal_rows(entries, "playoff")
	var regular_medals: Array = screen._history_medal_rows(entries, "regular")
	_assert(playoff_medals.size() == 3, "fourth place is not a medal")
	_assert(int(playoff_medals[0].get("club_id", 0)) == 1 and int(playoff_medals[0].get("gold", 0)) == 2, "legacy champion and playoff winner both count as gold")
	_assert(int(playoff_medals[1].get("club_id", 0)) == 2 and int(playoff_medals[1].get("silver", 0)) == 1, "playoff runner-up is silver")
	_assert(int(playoff_medals[2].get("club_id", 0)) == 3 and int(playoff_medals[2].get("bronze", 0)) == 1, "playoff third is bronze")
	_assert(regular_medals.size() == 3, "regular season keeps its own medal table")
	_assert(int(regular_medals[0].get("gold", 0)) == 1 and int(regular_medals[1].get("silver", 0)) == 1 and int(regular_medals[2].get("bronze", 0)) == 1, "regular medals follow the table")
	screen._history_tab = 0
	screen._clear_content()
	screen._build_history_view(unit)
	var medals_text := _gather_text(screen.get_node("%Content"))
	_assert(medals_text.find("Медали") >= 0 and medals_text.find("Медали") < medals_text.find("История сезонов"), "medals and season history are separate tabs")
	_assert(medals_text.find("Плей-офф") < medals_text.find("Регулярный сезон"), "both competitions stay side by side")
	_assert(_labels_starting(screen.get_node("%Content"), "Сезон ").is_empty(), "the medals tab does not list seasons")
	_assert("Дельта" not in medals_text, "fourth place stays out of the medal tables")
	_assert(not ("40" in medals_text) and not ("+12" in medals_text), "medal rows have no points or goal difference")
	screen._history_tab = 1
	screen._clear_content()
	screen._build_history_view(unit)
	var text := _gather_text(screen.get_node("%Content"))
	var season_labels := _labels_starting(screen.get_node("%Content"), "Сезон ")
	_assert(season_labels.size() >= 2 and season_labels[0] == "Сезон 3" and season_labels[1] == "Сезон 1", "newer season is first")
	_assert("Бета" in text and "Гамма" in text and "Дельта" in text, "playoff places 2–4 stay in the season list")
	_assert(_has_exact_label(screen.get_node("%Content"), "4"), "the playoff column header still marks fourth place")
	_assert(not _has_place_prefix(screen.get_node("%Content")), "season rows do not repeat the place before the club")
	_assert(text.find("Плей-офф") < text.find("Регулярный сезон"), "playoff and the regular season stay side by side")
	_assert(not ("40" in text) and not ("+12" in text), "the regular season row has no points or goal difference")
	screen.queue_free()
	GameSession.is_active = was_active


func _has_exact_label(node: Node, expected: String) -> bool:
	if node is Label and str(node.text) == expected:
		return true
	for child in node.get_children():
		if _has_exact_label(child, expected):
			return true
	return false


func _has_place_prefix(node: Node) -> bool:
	if node is HBoxContainer and node.get_child_count() == 3:
		var first := node.get_child(0)
		var last := node.get_child(2)
		if first is Label and last is Button and str(first.text) in ["1", "2", "3", "4"]:
			return true
	for child in node.get_children():
		if _has_place_prefix(child):
			return true
	return false


func _labels_starting(node: Node, prefix: String) -> PackedStringArray:
	var found := PackedStringArray()
	if node is Label and str(node.text).begins_with(prefix):
		found.append(node.text)
	for child in node.get_children():
		found.append_array(_labels_starting(child, prefix))
	return found


func _gather_text(node: Node) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if node is Label or node is Button:
		parts.append(node.text)
	for child in node.get_children():
		parts.append(_gather_text(child))
	return " ".join(parts)


func _series_of_round(unit: Dictionary, round_no: int) -> Array:
	var rows: Array = []
	for series in unit.get("playoff", {}).get("series", []):
		if bool(series.get("is_third_place", false)):
			continue
		if int(series.get("round", 0)) != round_no:
			continue
		rows.append(series)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slot", int(a.get("id", 0)))) < int(b.get("slot", int(b.get("id", 0))))
	)
	return rows


func _pair_of(series: Dictionary) -> Array:
	return [int(series.get("home_id", 0)), int(series.get("away_id", 0))]


func _ids_of(series: Dictionary) -> Array:
	return [int(series.get("home_id", 0)), int(series.get("away_id", 0))]


func _finish_current_round(unit: Dictionary, pick_winner: Callable) -> void:
	var playoff: Dictionary = unit.get("playoff", {})
	var round_no: int = int(playoff.get("current_round", 1))
	for series in playoff.get("series", []):
		if int(series.get("round", 0)) != round_no:
			continue
		if bool(series.get("complete", false)):
			continue
		var winner_id: int = int(pick_winner.call(series))
		var home_id: int = int(series.get("home_id", 0))
		var away_id: int = int(series.get("away_id", 0))
		if winner_id != home_id and winner_id != away_id:
			winner_id = home_id
		for match_row in playoff.get("matches", []):
			if int(match_row.get("series_id", 0)) != int(series.get("id", 0)):
				continue
			if bool(match_row.get("played", false)):
				continue
			match_row["played"] = true
			if winner_id == int(match_row.get("home_id", 0)):
				match_row["home_goals"] = 2
				match_row["away_goals"] = 0
			else:
				match_row["home_goals"] = 0
				match_row["away_goals"] = 2
			match_row["winner_id"] = winner_id


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
