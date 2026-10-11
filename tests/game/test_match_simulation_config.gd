extends Node
## Match simulation config: defaults, clamp, save/load, engine overlay.
## Run: godot --headless --path . res://tests/game/test_match_simulation_config.tscn

const MatchTypesScript := preload("res://game/match_types.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const MatchEngineScript := preload("res://game/match_engine.gd")
const SquadFixtures := preload("res://tests/game/squad_fixtures.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")
const LineupSelectorScript := preload("res://game/lineup_selector.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")

const TEST_PATH := "user://config/match_simulation_test.json"

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_isolate()
	print("=== Match simulation config tests ===")
	_test_defaults_match_engine_constants()
	_test_schema_covers_groups()
	_test_clamp_and_unknown_keys()
	_test_save_load_roundtrip()
	_test_engine_uses_live_knobs()
	_test_fitness_curves()
	_test_stamina_and_recovery_knobs()
	_test_tired_star_loses_slot()
	_test_settings_tab_builds()
	_restore()
	_finish()


func _test_defaults_match_engine_constants() -> void:
	var values := MatchSimConfigScript.default_values()
	_assert(
		is_equal_approx(float(values["chances_per_phase"]), MatchTypesScript.CHANCES_PER_PHASE),
		"default chances_per_phase matches MatchTypes"
	)
	_assert(
		is_equal_approx(float(values["home_advantage"]), MatchTypesScript.HOME_ADVANTAGE),
		"default home_advantage matches MatchTypes"
	)
	_assert(
		is_equal_approx(float(values["condition_after_stamina_10"]), MatchTypesScript.CONDITION_AFTER_STAMINA_10),
		"default condition_after_stamina_10 matches MatchTypes"
	)
	_assert(
		is_equal_approx(float(values["recovery_share_10"]), MatchTypesScript.RECOVERY_SHARE_10),
		"default recovery_share_10 matches MatchTypes"
	)
	_assert(
		is_equal_approx(float(values["fresh_after_stamina_10"]), MatchTypesScript.FRESH_AFTER_STAMINA_10),
		"default fresh_after_stamina_10 matches MatchTypes"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("shot_conversion_base"), MatchTypesScript.SHOT_CONVERSION_BASE),
		"get_f returns the default before any overlay"
	)


func _test_schema_covers_groups() -> void:
	var seen := {}
	for knob in MatchSimConfigScript.schema():
		var key := str(knob.get("key", ""))
		_assert(not key.is_empty(), "every knob has a key")
		_assert(not seen.has(key), "knob keys are unique (%s)" % key)
		seen[key] = true
		_assert(float(knob["max"]) > float(knob["min"]), "%s has a range" % key)
		_assert(
			float(knob["default"]) >= float(knob["min"]) and float(knob["default"]) <= float(knob["max"]),
			"%s default sits inside the slider" % key
		)
	for group in MatchSimConfigScript.GROUPS:
		var group_id := str(group.get("id", ""))
		var found := false
		for knob in MatchSimConfigScript.schema():
			if str(knob.get("group", "")) == group_id:
				found = true
				break
		_assert(found, "group %s has at least one knob" % group_id)
	_assert(
		MatchSimConfigScript.format_value(MatchSimConfigScript.knob_by_key("home_advantage"), 0.075) == "7.5%",
		"percent knobs render as percents"
	)


func _test_clamp_and_unknown_keys() -> void:
	var result: Dictionary = MatchSimConfigScript.apply_values(
		{"chances_per_phase": 99.0, "not_a_knob": 1.0, "yellow_per_phase": -4.0},
		false
	)
	_assert(bool(result.get("ok", false)), "apply_values accepts a partial overlay")
	_assert(
		is_equal_approx(
			MatchSimConfigScript.get_f("chances_per_phase"),
			float(MatchSimConfigScript.knob_by_key("chances_per_phase")["max"])
		),
		"over-max chances_per_phase is clamped"
	)
	_assert(
		is_equal_approx(
			MatchSimConfigScript.get_f("yellow_per_phase"),
			float(MatchSimConfigScript.knob_by_key("yellow_per_phase")["min"])
		),
		"negative yellow_per_phase is clamped to min"
	)
	_assert(not MatchSimConfigScript.snapshot().has("not_a_knob"), "unknown keys are dropped")
	MatchSimConfigScript.reset_to_defaults(false)


func _test_save_load_roundtrip() -> void:
	var custom := MatchSimConfigScript.default_values()
	custom["chances_per_phase"] = 1.80
	custom["home_advantage"] = 0.15
	var saved: Dictionary = MatchSimConfigScript.apply_values(custom, true)
	_assert(bool(saved.get("ok", false)), "custom knobs save")
	_assert(FileAccess.file_exists(TEST_PATH), "config file is written")

	MatchSimConfigScript.unload()
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("chances_per_phase"), 1.80),
		"reloaded chances_per_phase"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("home_advantage"), 0.15),
		"reloaded home_advantage"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("shot_conversion_base"), MatchTypesScript.SHOT_CONVERSION_BASE),
		"unmentioned knobs stay on defaults after reload"
	)

	var snap := MatchSimConfigScript.snapshot()
	snap["chances_per_phase"] = 0.4
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("chances_per_phase"), 1.80),
		"mutating a snapshot does not change runtime"
	)

	MatchSimConfigScript.reset_to_defaults(false)
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("chances_per_phase"), MatchTypesScript.CHANCES_PER_PHASE),
		"reset restores defaults without touching disk"
	)
	MatchSimConfigScript.unload()
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("chances_per_phase"), 1.80),
		"disk still has the saved overlay until persist-reset"
	)
	MatchSimConfigScript.reset_to_defaults(true)
	MatchSimConfigScript.unload()
	_assert(
		is_equal_approx(MatchSimConfigScript.get_f("chances_per_phase"), MatchTypesScript.CHANCES_PER_PHASE),
		"persist reset writes defaults back to disk"
	)


func _test_engine_uses_live_knobs() -> void:
	var rng_low := _rng(909)
	var rng_high := _rng(909)
	var low_goals := _goals_over(
		80,
		{"chances_per_phase": 0.40, "shot_conversion_base": 0.10},
		rng_low
	)
	var high_goals := _goals_over(
		80,
		{"chances_per_phase": 2.40, "shot_conversion_base": 0.55},
		rng_high
	)
	print("--- low scoring %.2f vs high scoring %.2f goals / match" % [low_goals, high_goals])
	_assert(high_goals > low_goals * 1.6, "raising chance knobs scores clearly more (%.2f vs %.2f)" % [
		high_goals, low_goals
	])
	MatchSimConfigScript.reset_to_defaults(false)


func _test_fitness_curves() -> void:
	_assert(
		is_equal_approx(MatchSimConfigScript.lerp_three(1, 10.0, 40.0, 80.0), 10.0),
		"curve at 1 is the first point"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.lerp_three(10, 10.0, 40.0, 80.0), 40.0),
		"curve at 10 is the middle point"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.lerp_three(20, 10.0, 40.0, 80.0), 80.0),
		"curve at 20 is the last point"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.lerp_three(19, 10.0, 40.0, 80.0), 76.0),
		"recovery 19 sits below 20"
	)
	MatchSimConfigScript.reset_to_defaults(false)
	_assert(
		is_equal_approx(MatchSimConfigScript.condition_play_mult(100), 1.0),
		"full condition plays at 100%"
	)
	MatchSimConfigScript.apply_values({"condition_play_floor": 0.50}, false)
	_assert(
		is_equal_approx(MatchSimConfigScript.condition_play_mult(0), 0.50),
		"play floor is used at empty condition"
	)
	_assert(
		is_equal_approx(MatchSimConfigScript.condition_play_mult(50), 0.75),
		"play floor interpolates at half condition"
	)
	MatchSimConfigScript.reset_to_defaults(false)


func _test_stamina_and_recovery_knobs() -> void:
	MatchSimConfigScript.reset_to_defaults(false)
	MatchSimConfigScript.apply_values(
		{
			"condition_after_stamina_1": 10.0,
			"condition_after_stamina_10": 25.0,
			"condition_after_stamina_20": 70.0,
			"recovery_share_1": 0.10,
			"recovery_share_10": 0.30,
			"recovery_share_20": 0.80,
			"recovery_floor": 0.0,
		},
		false
	)
	var weak := _physics_player(1, 10)
	var strong := _physics_player(20, 10)
	PlayerConditionScript.apply_match_load(weak, MatchTypesScript.REGULAR_MINUTES, 1.0)
	PlayerConditionScript.apply_match_load(strong, MatchTypesScript.REGULAR_MINUTES, 1.0)
	_assert(
		PlayerConditionScript.condition_of(weak) == 10,
		"stamina 1 ends a match at the 1-point slider (%d)" % PlayerConditionScript.condition_of(weak)
	)
	_assert(
		PlayerConditionScript.condition_of(strong) == 70,
		"stamina 20 ends a match at the 20-point slider (%d)" % PlayerConditionScript.condition_of(strong)
	)

	var slow := _physics_player(10, 1)
	var fast := _physics_player(10, 20)
	slow["condition"] = 40
	fast["condition"] = 40
	PlayerConditionScript.advance_round(slow, true)
	PlayerConditionScript.advance_round(fast, true)
	_assert(
		PlayerConditionScript.condition_of(fast) > PlayerConditionScript.condition_of(slow),
		"recovery 20 closes more of the gap than recovery 1 (%d vs %d)" % [
			PlayerConditionScript.condition_of(fast),
			PlayerConditionScript.condition_of(slow),
		]
	)
	MatchSimConfigScript.reset_to_defaults(false)


func _test_tired_star_loses_slot() -> void:
	MatchSimConfigScript.reset_to_defaults(false)
	var rng := _rng(414)
	var squad: Array = SquadFixtures.squad(1, 62, rng)
	var coach: Dictionary = SquadFixtures.coach(1, rng)
	var attrs: Variant = coach.get("attributes", {})
	if typeof(attrs) == TYPE_DICTIONARY:
		(attrs as Dictionary)[CoachTypesScript.ATTR_TACTICS] = 20

	var mids: Array = []
	for player in squad:
		if str(player.get("position", "")) == PlayerTypesScript.POS_CM:
			mids.append(player)
	_assert(mids.size() >= 2, "fixture squad has at least two central mids")
	mids.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return PlayerTypesScript.ability_of(a) > PlayerTypesScript.ability_of(b)
	)
	var star: Dictionary = mids[0]
	var deputy: Dictionary = mids[1]
	# Isolate readiness rather than assuming the second-highest CA fits this style.
	for candidate in [star, deputy]:
		for group in candidate["attributes"]:
			for key in candidate["attributes"][group]:
				candidate["attributes"][group][key] = 20 if candidate == star else 18
		candidate.erase("_match_ratings")
	star["condition"] = 50
	deputy["condition"] = MatchTypesScript.CONDITION_START
	var star_id := int(star.get("id", 0))
	var deputy_id := int(deputy.get("id", 0))

	var lineup: Dictionary = LineupSelectorScript.build(
		squad,
		[],
		coach,
		{"style": TacticTypesScript.STYLE_CONTROL, "formation": TacticTypesScript.FORM_232},
		rng
	)
	var started := {}
	for record in lineup.get("starters", []):
		started[int((record["player"] as Dictionary).get("id", 0))] = true
	_assert(started.has(deputy_id), "fresh deputy starts when the star is on 50 condition")
	_assert(not started.has(star_id), "tired star sits for the fresh deputy")

	star["condition"] = MatchTypesScript.CONDITION_START
	lineup = LineupSelectorScript.build(
		squad,
		[],
		coach,
		{"style": TacticTypesScript.STYLE_CONTROL, "formation": TacticTypesScript.FORM_232},
		rng
	)
	started.clear()
	for record in lineup.get("starters", []):
		started[int((record["player"] as Dictionary).get("id", 0))] = true
	_assert(started.has(star_id), "the same star starts when he is fresh")
	MatchSimConfigScript.reset_to_defaults(false)


func _physics_player(stamina: int, recovery: int) -> Dictionary:
	var player := {
		"id": 1,
		"age": 25,
		"position": PlayerTypesScript.POS_CM,
		"condition": MatchTypesScript.CONDITION_START,
		"morale": MatchTypesScript.MORALE_DEFAULT,
		"attributes": {
			PlayerTypesScript.ATTR_GROUP_PHYSICAL: {
				PlayerTypesScript.ATTR_STAMINA: stamina,
				PlayerTypesScript.ATTR_RECOVERY: recovery,
			},
		},
		"personality": {},
		"characters": [],
	}
	PlayerConditionScript.ensure_state(player)
	return player


func _test_settings_tab_builds() -> void:
	var packed := load("res://scenes/settings/tabs/match_sim_tab.tscn")
	_assert(packed != null, "match sim tab scene loads")
	var tab: Control = packed.instantiate()
	add_child(tab)
	var fields: Dictionary = tab.get("_fields")
	_assert(
		fields.size() == MatchSimConfigScript.schema().size(),
		"tab builds a slider per knob (%d)" % fields.size()
	)
	var collected: Dictionary = tab.call("_collect_values")
	_assert(
		is_equal_approx(float(collected.get("chances_per_phase", 0.0)), MatchTypesScript.CHANCES_PER_PHASE),
		"tab opens on default chances_per_phase"
	)
	tab.queue_free()


func _goals_over(samples: int, overlay: Dictionary, rng: RandomNumberGenerator) -> float:
	MatchSimConfigScript.reset_to_defaults(false)
	MatchSimConfigScript.apply_values(overlay, false)
	var home := SquadFixtures.squad(1, 58, rng)
	var away := SquadFixtures.squad(2, 58, rng)
	var home_coach := SquadFixtures.coach(1, rng)
	var away_coach := SquadFixtures.coach(2, rng)
	var goals := 0
	for _i in samples:
		var result: Dictionary = MatchEngineScript.simulate(
			{
				"home": {
					"club_id": 1,
					"squad": home,
					"youth": [],
					"coach": home_coach,
					"reputation": 500,
				},
				"away": {
					"club_id": 2,
					"squad": away,
					"youth": [],
					"coach": away_coach,
					"reputation": 500,
				},
				"allow_draw": true,
				"discipline": DisciplineRulesScript.defaults(),
			},
			rng
		)
		goals += int(result.get("home_goals", 0)) + int(result.get("away_goals", 0))
		for squad in [home, away]:
			for player in squad:
				player["condition"] = MatchTypesScript.CONDITION_START
				player["morale"] = MatchTypesScript.MORALE_DEFAULT
				player["injury_rounds"] = 0
				player["injury_grade"] = ""
				player["suspension_matches"] = 0
	return float(goals) / float(samples)


func _isolate() -> void:
	MatchSimConfigScript.config_path = TEST_PATH
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	MatchSimConfigScript.reset_to_defaults(false)


func _restore() -> void:
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(TEST_PATH)
	MatchSimConfigScript.config_path = MatchSimConfigScript.DEFAULT_CONFIG_PATH
	MatchSimConfigScript.reset_to_defaults(false)


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


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
