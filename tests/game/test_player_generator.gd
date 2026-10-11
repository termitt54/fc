extends Node
## Headless smoke check for PlayerGenerator entity slice.
## Run: godot --headless --path . res://tests/game/test_player_generator.tscn

const YouthIntakeScript := preload("res://game/youth_intake.gd")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Player generator tests ===")
	YouthGenerationConfigScript.birth_config_path = "user://tests/player_generator_birth.json"
	if FileAccess.file_exists(YouthGenerationConfigScript.birth_config_path):
		DirAccess.remove_absolute(YouthGenerationConfigScript.birth_config_path)
	YouthGenerationConfigScript.unload_birth()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var id_state := {"next_id": 1}
	var club_a := {"id": 1, "country_id": 1, "reputation": 700, "name": "Alpha"}
	var club_b := {"id": 2, "country_id": 1, "reputation": 400, "name": "Beta"}
	var cache := {}

	var squad_a: Array = PlayerGenerator.generate_for_club(1, club_a, rng, cache, id_state)
	var squad_b: Array = PlayerGenerator.generate_for_club(2, club_b, rng, cache, id_state)

	_assert(squad_a.size() == PlayerTypes.SQUAD_SIZE, "Club A has %d players (got %d)" % [PlayerTypes.SQUAD_SIZE, squad_a.size()])
	_assert(squad_b.size() == PlayerTypes.SQUAD_SIZE, "Club B has %d players (got %d)" % [PlayerTypes.SQUAD_SIZE, squad_b.size()])
	_assert(PlayerTypes.is_squad_shape_legal(squad_a), "Club A respects the squad law")
	_assert(PlayerTypes.is_squad_shape_legal(squad_b), "Club B respects the squad law")

	var ids := {}
	var gk_count := 0
	for player in squad_a:
		_assert_player_shape(player, 1)
		var pid := int(player.get("id", 0))
		_assert(not ids.has(pid), "Unique id within club A: %d" % pid)
		ids[pid] = true
		if str(player.get("position", "")) == PlayerTypes.POS_GK:
			gk_count += 1
	_assert(gk_count >= 2 and gk_count <= 3, "Club A has 2-3 GK (got %d)" % gk_count)

	for player in squad_b:
		_assert_player_shape(player, 2)
		var pid := int(player.get("id", 0))
		_assert(not ids.has(pid), "Globally unique id: %d" % pid)
		ids[pid] = true

	_assert(int(id_state["next_id"]) == 51, "next_id advanced to 51 (got %s)" % str(id_state["next_id"]))
	var strength := PlayerGenerator.team_strength(squad_a)
	_assert(strength > 40.0 and strength < 100.0, "team_strength in range (%.1f)" % strength)

	_assert_squad_not_elite_heavy(squad_a, "Club A")
	_assert_distribution_rarity(rng, cache)

	_finish()


func _assert_player_shape(player: Dictionary, club_id: int) -> void:
	var name := str(player.get("name", ""))
	_assert(int(player.get("club_id", 0)) == club_id, "club_id matches for %s" % name)
	_assert(not name.is_empty(), "name present")
	_assert(PlayerTypes.is_valid_position(str(player.get("position", ""))), "valid position for %s" % name)
	var characters: Array = PlayerTypes.characters_of(player)
	_assert(characters.size() == PlayerTypes.CHARACTERS_PER_PLAYER, "2 characters for %s" % name)
	for code in characters:
		_assert(PlayerTypes.is_valid_character(str(code)), "valid character %s for %s" % [code, name])
	if characters.size() == 2:
		var a := str(characters[0])
		var b := str(characters[1])
		_assert(a != b, "distinct characters for %s" % name)
		var opposite := str(PlayerTypes.CHARACTER_OPPOSITES.get(a, ""))
		_assert(opposite.is_empty() or opposite != b, "non-opposite characters for %s" % name)
	var age := int(player.get("age", 0))
	_assert(age >= 16 and age <= 38, "age in range for %s (%d)" % [name, age])
	var ca := int(player.get("current_ability", -1))
	var pa := int(player.get("potential_ability", -1))
	_assert(ca >= 1 and ca <= 100, "CA in range for %s" % name)
	_assert(pa >= ca and pa <= 100, "PA >= CA for %s (%d/%d)" % [name, pa, ca])
	_assert(int(player.get("overall", -1)) == ca, "overall mirrors CA for %s" % name)
	_assert(int(player.get("reputation", -1)) >= 0 and int(player.get("reputation", -1)) <= 1000, "reputation for %s" % name)
	_assert(int(player.get("value", 0)) > 0, "value > 0 for %s" % name)
	_assert(int(player.get("contract_years", 0)) >= 1 and int(player.get("contract_years", 0)) <= 5, "contract for %s" % name)
	_assert(int(player.get("wage", 0)) > 0, "wage > 0 for %s" % name)
	var personality: Dictionary = player.get("personality", {})
	_assert(personality.size() == PlayerTypes.PERSONALITY_KEYS.size(), "personality keys for %s" % name)
	for key in PlayerTypes.PERSONALITY_KEYS:
		var v := int(personality.get(key, -1))
		_assert(v >= 1 and v <= 20, "personality.%s for %s (%d)" % [key, name, v])

	var position := str(player.get("position", ""))
	var attributes: Dictionary = player.get("attributes", {})
	_assert(not attributes.is_empty(), "attributes present for %s" % name)
	for group in PlayerTypes.attribute_groups_for_position(position):
		_assert(attributes.has(group), "attr group %s for %s" % [group, name])
		var group_data: Dictionary = attributes.get(group, {})
		for key in PlayerTypes.attribute_keys_for_group(group):
			var av := int(group_data.get(key, -1))
			_assert(av >= 1 and av <= 20, "attr %s.%s for %s (%d)" % [group, key, name, av])
	if position == PlayerTypes.POS_GK:
		_assert(attributes.has(PlayerTypes.ATTR_GROUP_GOALKEEPING), "GK attrs for %s" % name)
	else:
		_assert(not attributes.has(PlayerTypes.ATTR_GROUP_GOALKEEPING), "no GK attrs for outfield %s" % name)
	var derived := PlayerTypes.calc_current_ability(attributes, position)
	_assert(derived == ca, "CA derived from attrs for %s (%d vs %d)" % [name, derived, ca])


func _assert_squad_not_elite_heavy(squad: Array, label: String) -> void:
	var elite_ca := 0
	var elite_pa := 0
	for player in squad:
		if int(player.get("current_ability", 0)) >= 90:
			elite_ca += 1
		if int(player.get("potential_ability", 0)) >= 90:
			elite_pa += 1
	_assert(elite_ca <= 1, "%s has at most one 90+ CA (got %d)" % [label, elite_ca])
	_assert(elite_pa <= 2, "%s has at most two 90+ PA (got %d)" % [label, elite_pa])


func _assert_distribution_rarity(rng: RandomNumberGenerator, _cache: Dictionary) -> void:
	YouthGenerationConfigScript.reset_to_defaults(false)
	var clubs: Array = []
	for club_i in 12:
		clubs.append({
			"id": 10 + club_i,
			"country_id": 1 if club_i < 6 else 2,
			"reputation": 800,
			"youth_academy": 10,
			"training_level": 10,
			"scouting_level": 10,
			"youth_search": 10,
			"name": "Top %d" % club_i,
		})
	var countries := {
		1: {"id": 1, "youth_talent": 70},
		2: {"id": 2, "youth_talent": 70},
	}
	var assignments: Array = YouthIntakeScript.plan_intake(
		clubs, countries, rng, {"mode": YouthIntakeScript.MODE_FIRST_TEAM}
	)
	var elite_ca := 0
	var elite_pa := 0
	var total := assignments.size()
	for row in assignments:
		if int(row.get("current_ability", 0)) >= 90:
			elite_ca += 1
		if int(row.get("potential_ability", 0)) >= 90:
			elite_pa += 1
	var ca_pct := 100.0 * float(elite_ca) / float(maxi(total, 1))
	var pa_pct := 100.0 * float(elite_pa) / float(maxi(total, 1))
	_assert(total == 300, "world first-team pool is 12×25 (got %d)" % total)
	_assert(ca_pct <= 5.0, "90+ CA is rare even at top clubs (%.2f%% of %d)" % [ca_pct, total])
	_assert(pa_pct <= 15.0, "talent 70 keeps 90+ PA to its top group (%.2f%% of %d)" % [pa_pct, total])
	YouthGenerationConfigScript.unload()


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label)


func _pass(label: String) -> void:
	_passed += 1
	print("PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	print("FAIL: %s" % label)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
