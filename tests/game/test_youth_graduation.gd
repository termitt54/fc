extends Node
## Youth graduation: first team, reserve, or market.
## Run: godot --headless --path . res://tests/game/test_youth_graduation.tscn

const YouthGraduationScript := preload("res://game/youth_graduation.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")


var _failed := 0
var _passed := 0
var _next_id := 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Youth graduation tests ===")
	_test_starter_count()
	_test_vacancy_goes_first_team()
	_test_expendable_is_replaced()
	_test_protected_pa_not_dumped()
	_test_reserve_when_no_slot()
	_test_session_graduates()
	GameSession.clear()
	_finish()


func _test_starter_count() -> void:
	_assert(
		YouthGraduationScript.starter_count(TacticTypesScript.FORM_322, PlayerTypesScript.POS_FB) == 2,
		"3-2-2 has two full-backs in the XI"
	)
	_assert(
		YouthGraduationScript.starter_count(TacticTypesScript.FORM_232, PlayerTypesScript.POS_GK) == 1,
		"every formation has a goalkeeper"
	)


func _test_vacancy_goes_first_team() -> void:
	var squad := _squad_without_st()
	var kid := _kid(PlayerTypesScript.POS_ST, 48, 82)
	var choice: Dictionary = YouthGraduationScript.destination_for_graduate(
		kid, squad, [], TacticTypesScript.FORM_232
	)
	_assert(str(choice.get("dest", "")) == YouthGraduationScript.DEST_FIRST, "vacancy at ST goes to first team")
	_assert(choice.get("victim", {}).is_empty(), "vacancy does not dump anyone")


func _test_expendable_is_replaced() -> void:
	var weak := _senior(PlayerTypesScript.POS_ST, 40, 55, 99, false)
	var star := _senior(PlayerTypesScript.POS_ST, 78, 80, 1, true)
	var squad := _full_with([star, weak])
	var kid := _kid(PlayerTypesScript.POS_ST, 45, 84)
	var formation := TacticTypesScript.FORM_232
	var expendable: Array = YouthGraduationScript.expendable_at_position(squad, PlayerTypesScript.POS_ST, 84, formation)
	_assert(not expendable.is_empty(), "there is an expendable striker")
	_assert(int(expendable[0].get("id", 0)) == 99, "lowest unprotected CA is dumped, not the starter")
	var choice: Dictionary = YouthGraduationScript.destination_for_graduate(kid, squad, [], formation)
	_assert(str(choice.get("dest", "")) == YouthGraduationScript.DEST_FIRST, "graduate takes the first team slot")
	_assert(int(choice.get("victim", {}).get("id", 0)) == 99, "victim is the expendable")


func _test_protected_pa_not_dumped() -> void:
	var prospect := _senior(PlayerTypesScript.POS_ST, 42, 90, 7, false)
	var squad := _full_with([prospect])
	var kid := _kid(PlayerTypesScript.POS_ST, 40, 80)
	var expendable: Array = YouthGraduationScript.expendable_at_position(
		squad, PlayerTypesScript.POS_ST, 80, TacticTypesScript.FORM_232
	)
	var dumped := false
	for row in expendable:
		if int(row.get("id", 0)) == 7:
			dumped = true
	_assert(not dumped, "higher-PA 19-year-old is not expendable")


func _test_reserve_when_no_slot() -> void:
	var starters: Array = []
	for i in 3:
		starters.append(_senior(PlayerTypesScript.POS_ST, 70 + i, 88, 20 + i, true))
	var squad := _full_with(starters)
	for player in squad:
		if str(player.get("position", "")) == PlayerTypesScript.POS_ST:
			player["potential_ability"] = 90
	var kid := _kid(PlayerTypesScript.POS_ST, 46, 86)
	var choice: Dictionary = YouthGraduationScript.destination_for_graduate(
		kid, squad, [], TacticTypesScript.FORM_232
	)
	_assert(str(choice.get("dest", "")) == YouthGraduationScript.DEST_RESERVE, "prospect without a slot goes to reserve")


func _test_session_graduates() -> void:
	var youth := [
		_kid(PlayerTypesScript.POS_ST, 40, 70),
		_kid(PlayerTypesScript.POS_CM, 38, 66),
	]
	youth[0]["age"] = 18
	youth[1]["age"] = 16
	GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 2,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"units": [{
			"id": 1,
			"clubs_by_id": {1: {"id": 1, "name": "Alpha", "reputation": 500, "finance_level": 10}},
			"matches": [],
		}],
		"players_by_club": {1: _squad_without_st()},
		"youth_players_by_club": {1: youth},
		"reserve_players_by_club": {},
		"free_agents": [],
		"coaches_by_club": {1: {"id": 1, "primary_formation": TacticTypesScript.FORM_232, "attributes": {}}},
		"club_budgets": {1: 400000},
	})
	var result: Dictionary = GameSession._process_youth_graduation()
	_assert(int(result.get("promoted", 0)) >= 1, "18-year-old is promoted into the ST vacancy")
	var still_youth := false
	for player in GameSession.get_club_youth_players(1):
		if int(player.get("age", 0)) >= 18:
			still_youth = true
		if int(player.get("id", 0)) == int(youth[1].get("id", 0)):
			_assert(int(player.get("age", 0)) == 16, "16-year-old stays in the academy")
	_assert(not still_youth, "nobody 18+ remains in youth")
	GameSession.clear()


func _kid(pos: String, ca: int, pa: int) -> Dictionary:
	var id := _next_id
	_next_id += 1
	return {
		"id": id,
		"club_id": 1,
		"name": "Kid %d" % id,
		"position": pos,
		"age": 18,
		"current_ability": ca,
		"potential_ability": pa,
		"value": 80000,
		"wage": 3000,
		"is_youth": true,
		"contract_status": "club",
		"contract_years": 2,
	}


func _senior(pos: String, ca: int, pa: int, id: int, _starter_hint: bool) -> Dictionary:
	return {
		"id": id,
		"club_id": 1,
		"name": "Sr %d" % id,
		"position": pos,
		"age": 27,
		"current_ability": ca,
		"potential_ability": pa,
		"value": 60000,
		"wage": 5000,
		"is_youth": false,
		"contract_status": "club",
		"contract_years": 2,
	}


func _squad_without_st() -> Array:
	var positions := [
		PlayerTypesScript.POS_GK, PlayerTypesScript.POS_GK,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB, PlayerTypesScript.POS_CB,
		PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB, PlayerTypesScript.POS_FB,
		PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CM,
		PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM, PlayerTypesScript.POS_WM,
		PlayerTypesScript.POS_ST, PlayerTypesScript.POS_ST,
		PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF, PlayerTypesScript.POS_WF,
		PlayerTypesScript.POS_CB, PlayerTypesScript.POS_FB,
	]
	var squad: Array = []
	for i in positions.size():
		squad.append(_senior(str(positions[i]), 55, 60, 200 + i, false))
	return squad


func _full_with(strikers: Array) -> Array:
	var squad := _squad_without_st()
	for extra in strikers:
		squad.append(extra)
	while squad.size() < PlayerTypesScript.SQUAD_SIZE:
		squad.append(_senior(PlayerTypesScript.POS_CB, 50, 55, 400 + squad.size(), false))
	if squad.size() > PlayerTypesScript.SQUAD_SIZE:
		squad.resize(PlayerTypesScript.SQUAD_SIZE)
	# Ensure requested strikers are in the 25.
	for i in strikers.size():
		squad[squad.size() - 1 - i] = strikers[i]
	return squad


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
