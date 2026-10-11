extends Node
## Headless smoke check for CoachGeneratorScript.
## Run: godot --headless --path . res://tests/game/test_coach_generator.tscn

const CoachGeneratorScript := preload("res://game/coach_generator.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Coach generator tests ===")
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var id_state := {"next_id": 1}
	var cache := {}
	var clubs := {
		1: {"id": 1, "country_id": 1, "reputation": 820, "name": "Alpha"},
		2: {"id": 2, "country_id": 2, "reputation": 310, "name": "Beta"},
	}
	var generated: Dictionary = CoachGeneratorScript.generate_for_clubs(clubs, rng, cache, id_state, 1)
	_assert(generated.size() == 2, "One coach per club (got %d)" % generated.size())
	_assert_coach_shape(generated.get(1, {}), 1)
	_assert_coach_shape(generated.get(2, {}), 2)
	_assert(int(generated[1].get("id", 0)) != int(generated[2].get("id", 0)), "Coach ids are unique")
	_assert(str(generated[1].get("name", "")) != str(generated[2].get("name", "")), "Coach names differ")
	_assert(int(id_state.get("next_id", 0)) == 3, "next_id advanced to 3 (got %s)" % str(id_state.get("next_id", 0)))

	var payload := {
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"season_total_days": 32,
		"selected_unit_id": 0,
		"season_finished": false,
		"units": [],
		"players_by_club": {},
		"youth_players_by_club": {},
		"free_agents": [],
		"coaches_by_club": generated,
	}
	var loaded: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(loaded.get("success", false)), "Save payload with coaches loads")
	var club_coach: Dictionary = GameSession.get_club_coach(1)
	_assert(not club_coach.is_empty(), "Club 1 has a head coach")
	_assert(int(GameSession.get_coach(int(club_coach.get("id", 0))).get("id", 0)) == int(club_coach.get("id", 0)), "get_coach finds the same person")
	_assert(CoachTypesScript.transfers_of(club_coach) >= 1, "Transfers stat is present after load")
	GameSession.clear()

	var legacy: Dictionary = GameSession.apply_save_payload({
		"version": 5,
		"season_number": 1,
		"season_day": 1,
		"units": [],
		"players_by_club": {},
	})
	_assert(bool(legacy.get("success", false)), "Legacy save without coaches loads")
	_assert(GameSession.get_club_coach(1).is_empty(), "Missing coaches map is safe")
	GameSession.clear()

	var legacy_coach := {
		"id": 9,
		"club_id": 1,
		"name": "Старый тренер",
		"style": CoachTypesScript.STYLE_ATTACKING,
		"attributes": {
			CoachTypesScript.ATTR_TRANSFERS: 12,
			CoachTypesScript.ATTR_TACTICS: 12,
			CoachTypesScript.ATTR_MOTIVATION: 12,
			CoachTypesScript.ATTR_DEVELOPMENT: 12,
			CoachTypesScript.ATTR_DISCIPLINE: 12,
		},
	}
	var migrated: Dictionary = GameSession.apply_save_payload({
		"version": 5,
		"season_number": 1,
		"season_day": 1,
		"units": [],
		"players_by_club": {},
		"coaches_by_club": {1: legacy_coach},
	})
	_assert(bool(migrated.get("success", false)), "Legacy coach without tactics loads")
	var filled: Dictionary = GameSession.get_club_coach(1)
	_assert(TacticTypesScript.STYLES.has(str(filled.get("primary_style", ""))), "legacy coach gets a primary style")
	_assert(TacticTypesScript.STYLES.has(str(filled.get("backup_style", ""))), "legacy coach gets a backup style")
	_assert(str(filled.get("primary_style", "")) != str(filled.get("backup_style", "")), "legacy backup differs")
	_assert(TacticTypesScript.FORMATIONS.has(str(filled.get("primary_formation", ""))), "legacy coach gets a primary formation")
	_assert(str(filled.get("style", "")) == CoachTypesScript.STYLE_ATTACKING, "legacy mentality is kept")
	GameSession.clear()
	_finish()


func _assert_coach_shape(coach: Dictionary, club_id: int) -> void:
	_assert(not coach.is_empty(), "Coach generated for club %d" % club_id)
	_assert(int(coach.get("club_id", 0)) == club_id, "club_id matches")
	_assert(not str(coach.get("name", "")).is_empty(), "name present")
	var age := int(coach.get("age", 0))
	_assert(age >= CoachTypesScript.AGE_MIN and age <= CoachTypesScript.AGE_MAX, "age in range (%d)" % age)
	var ca := int(coach.get("current_ability", 0))
	var pa := int(coach.get("potential_ability", 0))
	_assert(ca >= 1 and ca <= 100, "CA in range (%d)" % ca)
	_assert(pa >= ca and pa <= 100, "PA >= CA (%d/%d)" % [pa, ca])
	var attributes: Dictionary = coach.get("attributes", {})
	for key in CoachTypesScript.ATTR_KEYS:
		var value := int(attributes.get(key, 0))
		_assert(value >= 1 and value <= CoachTypesScript.ATTR_MAX, "%s in 1-20 (got %d)" % [key, value])
	var transfers := CoachTypesScript.transfers_of(coach)
	_assert(transfers >= 1 and transfers <= 20, "Transfers is the key stat (%d)" % transfers)
	_assert(CoachTypesScript.STYLES.has(str(coach.get("style", ""))), "mentality style is valid")
	var primary_style := str(coach.get("primary_style", ""))
	var backup_style := str(coach.get("backup_style", ""))
	_assert(TacticTypesScript.STYLES.has(primary_style), "primary playing style is valid")
	_assert(TacticTypesScript.STYLES.has(backup_style), "backup playing style is valid")
	_assert(primary_style != backup_style, "backup style differs from primary")
	var primary_form := str(coach.get("primary_formation", ""))
	var backup_form := str(coach.get("backup_formation", ""))
	_assert(TacticTypesScript.FORMATIONS.has(primary_form), "primary formation is valid")
	_assert(TacticTypesScript.FORMATIONS.has(backup_form), "backup formation is valid")
	_assert(primary_form != backup_form, "backup formation differs from primary")
	_assert(int(coach.get("contract_years", 0)) >= 1, "contract years present")
	_assert(int(coach.get("wage", 0)) > 0, "wage present")
	var career: Array = coach.get("career", [])
	_assert(not career.is_empty(), "career starts with current club")


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
