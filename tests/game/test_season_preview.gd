extends Node
## Season preview: squad, club reputation and the head coach, shaped by the tournament.
## Run: godot --headless --path . res://tests/game/test_season_preview.tscn

const Preview := preload("res://game/season_preview.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Season preview ===")
	_test_stronger_squad_leads_the_league()
	_test_reputation_breaks_an_even_squad()
	_test_coach_breaks_an_even_squad()
	_test_league_without_playoff_has_no_knockout()
	_test_divisions_playoff_is_separate()
	_test_cup_names_a_stage_and_a_winner()
	_test_super_cup_is_one_match()
	_test_groups_then_a_knockout()
	var screen: PackedScene = load("res://scenes/game/game_screen.tscn")
	_assert(screen != null, "the preview tab still parses on the game screen")
	_finish()


func _test_stronger_squad_leads_the_league() -> void:
	var built := Preview.build(_league_unit(0), 3, _squads([80, 62, 58, 55]), _coaches([10, 10, 10, 10]))
	var table := _section(built, "regular")
	_assert(not table.is_empty(), "a league has a regular-season preview")
	var rows: Array = table.get("rows", [])
	_assert(int(rows[0].get("club_id", 0)) == 1, "the strongest squad is the predicted champion")
	_assert(
		float(rows[0].get("title_chance", 0.0)) > float(rows[1].get("title_chance", 0.0)),
		"the leader's title chance is the highest"
	)


func _test_reputation_breaks_an_even_squad() -> void:
	var unit := _league_unit(0)
	unit["clubs_by_id"] = {
		1: {"name": "Имя", "reputation": 920},
		2: {"name": "Ровный", "reputation": 400},
		3: {"name": "Тихий", "reputation": 400},
		4: {"name": "Малый", "reputation": 380},
	}
	var built := Preview.build(unit, 3, _squads([64, 64, 64, 64]), _coaches([10, 10, 10, 10]))
	var rows: Array = _section(built, "regular").get("rows", [])
	_assert(int(rows[0].get("club_id", 0)) == 1, "reputation puts the famous club first when squads match")


func _test_coach_breaks_an_even_squad() -> void:
	var built := Preview.build(_league_unit(0), 4, _squads([64, 64, 64, 64]), _coaches([18, 6, 6, 6]))
	var rows: Array = _section(built, "regular").get("rows", [])
	_assert(int(rows[0].get("club_id", 0)) == 1, "a clearly better coach leads an even squad")


func _test_league_without_playoff_has_no_knockout() -> void:
	var built := Preview.build(_league_unit(0), 1, _squads([70, 60, 55, 50]), _coaches([10, 10, 10, 10]))
	_assert(_section(built, "playoff").is_empty(), "no playoff is configured, so none is previewed")
	_assert(_section(built, "cup").is_empty(), "a league is not a cup")


func _test_divisions_playoff_is_separate() -> void:
	var unit := {
		"id": 9,
		"competition_type": CompetitionTypes.TYPE_DIVISIONS,
		"rules": {"teams_playoff": 4, "playoff_scope": "PER_DIVISION", "regular_season_enabled": false},
		"divisions": [
			{"index": 0, "club_ids": [1, 2, 3, 4]},
			{"index": 1, "club_ids": [5, 6, 7, 8]},
		],
		"clubs_by_id": {},
	}
	for i in range(1, 9):
		unit["clubs_by_id"][i] = {"name": "К%s" % i, "reputation": 500}
	var squads := {}
	var coaches := {}
	for i in range(1, 9):
		var ca := 78 if i == 1 or i == 5 else 58
		squads[i] = _side(ca)
		coaches[i] = _coach(10)
	var built := Preview.build(unit, 2, squads, coaches)
	var divisions := 0
	for section in built.get("sections", []):
		if str(section.get("id", "")) == "division":
			divisions += 1
	_assert(divisions == 2, "each division has its own preview")
	_assert(_section(built, "regular").is_empty(), "without a unified table there is no overall champion")
	var playoff := _section(built, "playoff")
	_assert(not playoff.is_empty(), "a configured playoff is previewed on its own")
	var chances := 0.0
	for row in playoff.get("rows", []):
		chances += float(row.get("title_chance", 0.0))
	_assert(chances > 98.0, "playoff title chances cover the field (%.1f)" % chances)


func _test_cup_names_a_stage_and_a_winner() -> void:
	var unit := _typed_unit(CompetitionTypes.TYPE_CUP, 8)
	var squads := {}
	var coaches := {}
	for i in range(1, 9):
		squads[i] = _side(84 if i == 1 else 52)
		coaches[i] = _coach(12 if i == 1 else 8)
	var built := Preview.build(unit, 5, squads, coaches)
	var cup := _section(built, "cup")
	_assert(not cup.is_empty(), "a cup has a knockout preview")
	_assert(_section(built, "regular").is_empty(), "a cup has no league table")
	var rows: Array = cup.get("rows", [])
	var total := 0.0
	var staged := true
	for row in rows:
		total += float(row.get("title_chance", 0.0))
		if str(row.get("stage", "")).is_empty():
			staged = false
	_assert(staged, "every club has a stage it is likely to reach")
	_assert(total > 99.0 and total < 101.0, "cup title chances sum to 100 (%.1f)" % total)
	_assert(int(rows[0].get("club_id", 0)) == 1, "the strongest side is the cup favourite")


func _test_super_cup_is_one_match() -> void:
	var unit := _typed_unit(CompetitionTypes.TYPE_SUPER_CUP, 2)
	var built := Preview.build(unit, 1, {1: _side(80), 2: _side(58)}, {1: _coach(14), 2: _coach(8)})
	var rows: Array = _section(built, "super_cup").get("rows", [])
	_assert(rows.size() == 2, "a super cup previews both finalists")
	var total := float(rows[0].get("title_chance", 0.0)) + float(rows[1].get("title_chance", 0.0))
	_assert(absf(total - 100.0) < 0.2, "the two chances are one match")
	_assert(float(rows[0].get("title_chance", 0.0)) > 60.0, "the stronger finalist is the favourite")


func _test_groups_then_a_knockout() -> void:
	var unit := _typed_unit(CompetitionTypes.TYPE_GROUP_AND_PLAYOFF, 8)
	var squads := {}
	var coaches := {}
	for i in range(1, 9):
		squads[i] = _side(76 if i <= 2 else 54)
		coaches[i] = _coach(11)
	var built := Preview.build(unit, 2, squads, coaches)
	_assert(not _section(built, "groups").is_empty(), "a group tournament previews the group stage")
	_assert(not _section(built, "playoff").is_empty(), "and then the knockout")
	_assert(_section(built, "regular").is_empty(), "groups are not a league table")


func _league_unit(playoff_teams: int) -> Dictionary:
	return {
		"id": 4,
		"competition_type": CompetitionTypes.TYPE_LEAGUE,
		"rules": {"teams_playoff": playoff_teams, "regular_season_enabled": true},
		"divisions": [{"index": 0, "club_ids": [1, 2, 3, 4]}],
		"clubs_by_id": {
			1: {"name": "Альфа", "reputation": 600},
			2: {"name": "Бета", "reputation": 600},
			3: {"name": "Гамма", "reputation": 600},
			4: {"name": "Дельта", "reputation": 600},
		},
	}


func _typed_unit(type_code: String, count: int) -> Dictionary:
	var ids: Array = []
	var clubs := {}
	for i in count:
		var id := i + 1
		ids.append(id)
		clubs[id] = {"name": "К%d" % id, "reputation": 500}
	return {
		"id": 6,
		"competition_type": type_code,
		"rules": {},
		"divisions": [{"index": 0, "club_ids": ids}],
		"clubs_by_id": clubs,
	}


func _squads(levels: Array) -> Dictionary:
	var squads := {}
	for i in levels.size():
		squads[i + 1] = _side(int(levels[i]))
	return squads


func _coaches(levels: Array) -> Dictionary:
	var coaches := {}
	for i in levels.size():
		coaches[i + 1] = _coach(int(levels[i]))
	return coaches


func _side(ca: int) -> Array:
	var rows: Array = []
	for i in 16:
		rows.append({"current_ability": ca - int(i / 2), "is_youth": false})
	return rows


func _coach(level: int) -> Dictionary:
	return {"attributes": {"tactics": level, "motivation": level}}


func _section(preview: Dictionary, section_id: String) -> Dictionary:
	for section in preview.get("sections", []):
		if typeof(section) == TYPE_DICTIONARY and str(section.get("id", "")) == section_id:
			return section
	return {}


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
