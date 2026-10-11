extends Node
## Contract tick, stay chance, youth auto-renew.
## Run: godot --headless --path . res://tests/game/test_contract_renewal.tscn

const ContractRenewalScript := preload("res://game/contract_renewal.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Contract renewal tests ===")
	_test_tick_years()
	_test_loyal_stays_more_than_ambitious()
	_test_negotiations_help()
	_test_active_contract_stays()
	_test_renew_and_release_rolls()
	_test_youth_never_released()
	_test_session_releases_expired()
	_test_legacy_coach_gets_negotiations()
	GameSession.clear()
	_finish()


func _test_tick_years() -> void:
	var player := {"contract_years": 3}
	_assert(ContractRenewalScript.tick_years(player) == 2, "3 years become 2")
	_assert(int(player.get("contract_years", 0)) == 2, "player stores 2")
	player["contract_years"] = 0
	_assert(ContractRenewalScript.tick_years(player) == 0, "zero does not go negative")


func _test_loyal_stays_more_than_ambitious() -> void:
	var club := {"reputation": 400}
	var coach := {"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 10}}
	var loyal := {
		"reputation": 700,
		"wage": 8000,
		"age": 26,
		"current_ability": 70,
		"characters": [PlayerTypesScript.CHAR_LOYAL],
	}
	var ambitious := {
		"reputation": 700,
		"wage": 8000,
		"age": 26,
		"current_ability": 70,
		"characters": [PlayerTypesScript.CHAR_AMBITIOUS],
	}
	var loyal_p := ContractRenewalScript.stay_chance(loyal, club, coach)
	var ambitious_p := ContractRenewalScript.stay_chance(ambitious, club, coach)
	_assert(loyal_p > ambitious_p, "loyal stay chance > ambitious (%s vs %s)" % [loyal_p, ambitious_p])


func _test_negotiations_help() -> void:
	var club := {"reputation": 500}
	var player := {"reputation": 620, "wage": 5000, "age": 24, "current_ability": 60, "characters": []}
	var weak := ContractRenewalScript.stay_chance(player, club, {
		"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 3},
	})
	var strong := ContractRenewalScript.stay_chance(player, club, {
		"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 18},
	})
	_assert(strong > weak, "negotiations raise stay chance (%s vs %s)" % [strong, weak])


func _test_active_contract_stays() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var player := _player(1, 3, false)
	var outcome := ContractRenewalScript.process_player(player, {"reputation": 500}, {}, rng)
	_assert(outcome == ContractRenewalScript.REASON_ACTIVE, "multi-year contract is not renegotiated")
	_assert(int(player.get("contract_years", 0)) == 2, "years ticked to 2")
	_assert(int(player.get("club_id", 0)) == 1, "still at the club")


func _test_renew_and_release_rolls() -> void:
	var club_big := {"reputation": 800}
	var club_small := {"reputation": 200}
	var good_coach := {"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 20}}
	var weak_coach := {"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 1}}
	var stay := _player(2, 1, false)
	stay["reputation"] = 200
	_assert(
		ContractRenewalScript._wants_to_stay(stay, club_big, good_coach, 0.5),
		"underrated player accepts a 0.5 roll at a bigger club"
	)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var stay_out := ContractRenewalScript.process_player(stay, club_big, good_coach, rng)
	_assert(stay_out == ContractRenewalScript.REASON_RENEWED, "expired fit player renews (got %s)" % stay_out)
	_assert(int(stay.get("contract_years", 0)) >= 1, "renewed contract has years")

	var leave := _player(3, 1, false)
	leave["reputation"] = 900
	leave["characters"] = [PlayerTypesScript.CHAR_AMBITIOUS]
	_assert(
		not ContractRenewalScript._wants_to_stay(leave, club_small, weak_coach, 0.2),
		"overqualified ambitious player refuses a 0.2 roll at a small club"
	)
	rng.seed = 1
	var leave_out := ""
	for _i in 40:
		var candidate := leave.duplicate(true)
		leave_out = ContractRenewalScript.process_player(candidate, club_small, weak_coach, rng)
		if leave_out == ContractRenewalScript.REASON_RELEASED:
			leave = candidate
			break
	_assert(leave_out == ContractRenewalScript.REASON_RELEASED, "overqualified player is released (got %s)" % leave_out)
	_assert(int(leave.get("club_id", 0)) == 0, "released player has no club")
	_assert(str(leave.get("contract_status", "")) == "free_agent", "status is free agent")


func _test_youth_never_released() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var youth := _player(4, 1, true)
	youth["reputation"] = 900
	var outcome := ContractRenewalScript.process_player(
		youth, {"reputation": 100}, {"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 1}}, rng
	)
	_assert(outcome == ContractRenewalScript.REASON_YOUTH_KEPT, "youth is auto-kept (got %s)" % outcome)
	_assert(int(youth.get("club_id", 0)) == 1, "youth stays at the club")
	_assert(int(youth.get("contract_years", 0)) >= 1, "youth contract is topped up")


func _test_session_releases_expired() -> void:
	var keeper := _player(10, 2, false)
	var leaver := _player(11, 1, false)
	leaver["reputation"] = 950
	leaver["characters"] = [PlayerTypesScript.CHAR_AMBITIOUS]
	var youth := _player(12, 1, true)
	youth["club_id"] = 1
	GameSession.apply_save_payload({
		"version": GameSession.SAVE_VERSION,
		"season_number": 2,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"units": [{
			"id": 1,
			"clubs_by_id": {1: {"id": 1, "name": "Alpha", "reputation": 180, "finance_level": 10}},
			"matches": [],
		}],
		"players_by_club": {1: [keeper, leaver]},
		"youth_players_by_club": {1: [youth]},
		"free_agents": [],
		"coaches_by_club": {
			1: {
				"id": 1,
				"club_id": 1,
				"wage": 1000,
				"attributes": {CoachTypesScript.ATTR_NEGOTIATIONS: 1},
			},
		},
		"club_budgets": {1: 500000},
	})
	GameSession._rng.seed = 1
	var released := 0
	for _i in 30:
		leaver["club_id"] = 1
		leaver["contract_years"] = 1
		leaver["contract_status"] = "club"
		GameSession.players_by_club[1] = [keeper.duplicate(true), leaver.duplicate(true)]
		GameSession.youth_players_by_club[1] = [youth.duplicate(true)]
		GameSession.free_agents.clear()
		var result: Dictionary = GameSession._process_contract_renewals()
		released = int(result.get("released", 0))
		if released >= 1:
			break
	_assert(released >= 1, "expired first-team player can be released")
	var still_there := false
	for player in GameSession.get_club_players(1):
		if int(player.get("id", 0)) == 10:
			still_there = true
			_assert(int(player.get("contract_years", 0)) == 1, "active contract ticked to 1")
	_assert(still_there, "player with years left stays")
	var youth_ok := false
	for player in GameSession.get_club_youth_players(1):
		if int(player.get("id", 0)) == 12:
			youth_ok = true
			_assert(int(player.get("contract_years", 0)) >= 1, "youth still contracted")
	_assert(youth_ok, "youth remains in the academy")
	GameSession.clear()


func _test_legacy_coach_gets_negotiations() -> void:
	GameSession.apply_save_payload({
		"version": 8,
		"season_number": 1,
		"season_day": 1,
		"units": [],
		"players_by_club": {},
		"coaches_by_club": {
			1: {
				"id": 4,
				"club_id": 1,
				"attributes": {
					CoachTypesScript.ATTR_TRANSFERS: 14,
					CoachTypesScript.ATTR_TACTICS: 12,
					CoachTypesScript.ATTR_MOTIVATION: 10,
					CoachTypesScript.ATTR_DEVELOPMENT: 8,
					CoachTypesScript.ATTR_DISCIPLINE: 11,
				},
			},
		},
	})
	var coach: Dictionary = GameSession.get_club_coach(1)
	var talks := CoachTypesScript.negotiations_of(coach)
	_assert(talks >= 1 and talks <= 20, "legacy coach gets negotiations (%d)" % talks)
	GameSession.clear()


func _player(id: int, years: int, youth: bool) -> Dictionary:
	return {
		"id": id,
		"club_id": 1,
		"name": "P%d" % id,
		"position": PlayerTypesScript.POS_CM,
		"age": 16 if youth else 25,
		"wage": 4000,
		"reputation": 500,
		"current_ability": 55,
		"potential_ability": 70,
		"contract_years": years,
		"contract_status": "club",
		"is_youth": youth,
		"characters": [],
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
