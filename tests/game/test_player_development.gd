extends Node
## Headless checks for PlayerDevelopment: growth must reach the attributes, a
## talent must converge on his potential, minutes must matter and age must bite.
## Run: godot --headless --path . res://tests/game/test_player_development.tscn

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Player development tests ===")
	_test_growth_reaches_attributes()
	_test_season_records_ca_and_attribute_steps()
	_test_talent_converges_on_potential()
	_test_potential_decides_the_outcome()
	_test_minutes_change_growth()
	_test_training_setup_reads_the_club()
	_test_training_base_changes_growth()
	_test_head_coach_changes_growth()
	_test_base_outweighs_the_coach()
	_test_drive_changes_growth()
	_test_squad_minutes_are_read_from_stats()
	_test_age_takes_ca_away()
	_test_ageing_eats_physical_first()
	_test_thirty_year_old_never_grows()
	_test_missing_attributes_are_survivable()
	_finish()


## The old model wrote current_ability and then recomputed it from randomly
## nudged attributes, which threw away all but a few percent of the growth.
func _test_growth_reaches_attributes() -> void:
	var rng := _rng(11)
	var player := _make_player(rng, PlayerTypes.POS_ST, 40, 90, 17)
	var before := int(player["current_ability"])
	PlayerDevelopment.develop_player(player, _setup(10, 10), rng, 1.0)
	var after := int(player["current_ability"])
	_assert(after - before >= 4, "a 17-year-old talent gains real CA in one season (%d -> %d)" % [before, after])
	_assert_ca_matches_attributes(player, "after one season of growth")


func _test_season_records_ca_and_attribute_steps() -> void:
	var rng := _rng(21)
	var player := _make_player(rng, PlayerTypes.POS_ST, 40, 90, 17)
	var before := int(player["current_ability"])
	PlayerDevelopment.develop_player(player, _setup(10, 10), rng, 1.0, 2)
	var history: Array = player.get("development_history", [])
	_assert(history.size() == 2, "first off-season keeps the previous CA and the new one")
	_assert(
		int(history[0].get("season", 0)) == 1 and int(history[0].get("ca", -1)) == before,
		"season 1 stores the CA from before the step"
	)
	_assert(
		int(history[1].get("season", 0)) == 2
			and int(history[1].get("ca", -1)) == int(player["current_ability"]),
		"season 2 stores the CA after development"
	)
	var deltas: Dictionary = player.get("development_deltas", {})
	var moved := 0
	for group in deltas.keys():
		var group_delta: Dictionary = deltas[group]
		for key in group_delta.keys():
			moved += absi(int(group_delta[key]))
	_assert(moved > 0, "attribute steps are stored for the season change")
	PlayerDevelopment.develop_player(player, _setup(10, 10), rng, 1.0, 3)
	history = player.get("development_history", [])
	_assert(history.size() == 3, "the next season appends one CA point")
	_assert(int(history[2].get("season", 0)) == 3, "the third point is season 3")

	var quiet := _make_player(_rng(22), PlayerTypes.POS_ST, 40, 90, 17)
	PlayerDevelopment.develop_player(quiet, _setup(10, 10), _rng(22), 1.0)
	_assert(not quiet.has("development_history"), "a step without a season does not open a history")


func _test_talent_converges_on_potential() -> void:
	var finals: Array[int] = []
	for seed_i in 12:
		var rng := _rng(200 + seed_i)
		var player := _make_player(rng, PlayerTypes.POS_ST, 40, 90, 16, 1.0)
		_simulate(rng, player, 28, _setup(10, 10), 1.0)
		finals.append(int(player["current_ability"]))
		_assert_ca_matches_attributes(player, "after a full career")
		_assert(
			int(player["current_ability"]) <= int(player["potential_ability"]),
			"CA never passes PA (%d/%d)" % [int(player["current_ability"]), int(player["potential_ability"])]
		)
	var mean := _mean(finals)
	_assert(mean >= 76.5, "PA 90 talent reaches 85%%+ of potential by 28 (mean CA %.1f)" % mean)
	_assert(mean <= 90.0, "PA 90 talent stays under his potential (mean CA %.1f)" % mean)


func _test_potential_decides_the_outcome() -> void:
	var high: Array[int] = []
	var low: Array[int] = []
	for seed_i in 8:
		var rng_high := _rng(300 + seed_i)
		var talent := _make_player(rng_high, PlayerTypes.POS_CM, 40, 90, 16, 1.0)
		_simulate(rng_high, talent, 28, _setup(10, 10), 1.0)
		high.append(int(talent["current_ability"]))

		var rng_low := _rng(300 + seed_i)
		var limited := _make_player(rng_low, PlayerTypes.POS_CM, 40, 60, 16, 1.0)
		_simulate(rng_low, limited, 28, _setup(10, 10), 1.0)
		low.append(int(limited["current_ability"]))
	var gap := _mean(high) - _mean(low)
	_assert(gap >= 12.0, "PA 90 ends far above PA 60 from the same start (%.1f CA apart)" % gap)


func _test_minutes_change_growth() -> void:
	var starters: Array[int] = []
	var benched: Array[int] = []
	for seed_i in 8:
		var rng_a := _rng(400 + seed_i)
		var starter := _make_player(rng_a, PlayerTypes.POS_WF, 40, 90, 16, 1.0)
		_simulate(rng_a, starter, 24, _setup(10, 10), 1.0)
		starters.append(int(starter["current_ability"]))

		var rng_b := _rng(400 + seed_i)
		var reserve := _make_player(rng_b, PlayerTypes.POS_WF, 40, 90, 16, 1.0)
		_simulate(rng_b, reserve, 24, _setup(10, 10), 0.0)
		benched.append(int(reserve["current_ability"]))
	var gap := _mean(starters) - _mean(benched)
	_assert(gap >= 5.0, "a starter outgrows a player who never plays (%.1f CA apart)" % gap)


func _test_training_setup_reads_the_club() -> void:
	var setup := PlayerDevelopment.training_setup(
		14, {"attributes": {CoachTypes.ATTR_DEVELOPMENT: 17}}
	)
	_assert(int(setup["facility"]) == 14, "setup keeps the training base level")
	_assert(int(setup["coaching"]) == 17, "setup reads the coach development attribute")
	var uncoached := PlayerDevelopment.training_setup(14)
	_assert(
		int(uncoached["coaching"]) == PlayerDevelopment.LEVEL_NEUTRAL,
		"a squad with no coach gets neutral coaching"
	)
	var clamped := PlayerDevelopment.training_setup(
		99, {"attributes": {CoachTypes.ATTR_DEVELOPMENT: 99}}
	)
	_assert(
		int(clamped["facility"]) == PlayerDevelopment.LEVEL_MAX
			and int(clamped["coaching"]) == PlayerDevelopment.LEVEL_MAX,
		"setup clamps both levels onto the 0-20 scale"
	)


func _test_training_base_changes_growth() -> void:
	var good := _cohort_mean(1000, 10, 21, _setup(20, 10))
	var poor := _cohort_mean(1000, 10, 21, _setup(1, 10))
	_assert(
		good - poor >= 3.0,
		"a strong training base grows players faster (%.1f CA apart)" % (good - poor)
	)


func _test_head_coach_changes_growth() -> void:
	var good := _cohort_mean(1100, 10, 21, _setup(10, 20))
	var poor := _cohort_mean(1100, 10, 21, _setup(10, 1))
	_assert(
		good - poor >= 2.0,
		"a coach who develops players is worth CA (%.1f apart)" % (good - poor)
	)


## FACILITY_WEIGHT is the larger of the two, so the base has to win this.
func _test_base_outweighs_the_coach() -> void:
	var base_only := _cohort_mean(1200, 10, 21, _setup(20, 1))
	var coach_only := _cohort_mean(1200, 10, 21, _setup(1, 20))
	_assert(
		base_only > coach_only,
		"a great base under a poor coach beats the reverse (%.1f vs %.1f)" % [base_only, coach_only]
	)


func _test_drive_changes_growth() -> void:
	var driven := _cohort_mean(1300, 10, 21, _setup(10, 10), PlayerTypes.PERSONALITY_MAX)
	var idle := _cohort_mean(1300, 10, 21, _setup(10, 10), PlayerTypes.PERSONALITY_MIN)
	_assert(
		driven - idle >= 3.0,
		"professionalism and ambition speed a player up (%.1f CA apart)" % (driven - idle)
	)


## develop_squad has to derive the share itself, because the session only knows
## minutes through the season row that has not been archived yet.
func _test_squad_minutes_are_read_from_stats() -> void:
	var rng := _rng(500)
	var squad: Array = []
	for i in 24:
		var player := _make_player(rng, PlayerTypes.POS_CM, 40, 90, 18, 1.0)
		player["season_stats"] = {"season": 1, "minutes": 900 if i < 12 else 0}
		squad.append(player)
	PlayerDevelopment.develop_squad(squad, _setup(10, 10), rng)

	var played: Array[int] = []
	var unused: Array[int] = []
	for i in squad.size():
		var ca := int((squad[i] as Dictionary)["current_ability"])
		if i < 12:
			played.append(ca)
		else:
			unused.append(ca)
	_assert(
		_mean(played) > _mean(unused),
		"squad growth follows season minutes (%.1f played vs %.1f unused)" % [_mean(played), _mean(unused)]
	)


func _test_age_takes_ca_away() -> void:
	var drops: Array[int] = []
	for seed_i in 10:
		var rng := _rng(600 + seed_i)
		var player := _make_player(rng, PlayerTypes.POS_CM, 80, 85, 30, 1.0)
		var before := int(player["current_ability"])
		_simulate(rng, player, 36, _setup(10, 10), 1.0)
		drops.append(before - int(player["current_ability"]))
		_assert_ca_matches_attributes(player, "after ageing")
	var mean := _mean(drops)
	_assert(mean >= 6.0, "a veteran loses real ground from 30 to 36 (mean %.1f CA)" % mean)
	_assert(mean <= 25.0, "ageing does not erase the player (mean %.1f CA)" % mean)


func _test_ageing_eats_physical_first() -> void:
	var rng := _rng(700)
	var player := _make_player(rng, PlayerTypes.POS_CM, 80, 85, 30, 1.0)
	var before := _weighted_group_total(player, PlayerTypes.ATTR_GROUP_PHYSICAL)
	var before_tech := _weighted_group_total(player, PlayerTypes.ATTR_GROUP_TECHNICAL)
	_simulate(rng, player, 36, _setup(10, 10), 1.0)
	var physical_loss := before - _weighted_group_total(player, PlayerTypes.ATTR_GROUP_PHYSICAL)
	var technical_loss := before_tech - _weighted_group_total(player, PlayerTypes.ATTR_GROUP_TECHNICAL)
	_assert(physical_loss > 0, "ageing costs physical attributes (%d points)" % physical_loss)
	_assert(
		physical_loss > technical_loss,
		"physical goes before technical (%d vs %d points)" % [physical_loss, technical_loss]
	)


func _test_thirty_year_old_never_grows() -> void:
	for seed_i in 6:
		var rng := _rng(800 + seed_i)
		var player := _make_player(rng, PlayerTypes.POS_FB, 50, 95, 30, 1.0)
		var before := int(player["current_ability"])
		PlayerDevelopment.develop_player(player, _setup(20, 20), rng, 1.0)
		_assert(
			int(player["current_ability"]) <= before,
			"a 30-year-old with room to spare still does not improve (%d -> %d)"
				% [before, int(player["current_ability"])]
		)


func _test_missing_attributes_are_survivable() -> void:
	var rng := _rng(900)
	var bare := {"age": 20, "position": PlayerTypes.POS_CM, "current_ability": 50, "potential_ability": 80}
	PlayerDevelopment.develop_player(bare, _setup(10, 10), rng, 1.0)
	_assert(int(bare["current_ability"]) == 50, "a player without attributes is left alone")
	PlayerDevelopment.develop_squad([bare, null, 7], _setup(10, 10), rng)
	_assert(true, "develop_squad survives a squad with junk entries")


# --- helpers --------------------------------------------------------------


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _make_player(
	rng: RandomNumberGenerator,
	position: String,
	current_ability: int,
	potential_ability: int,
	age: int,
	development_factor: float = 1.0
) -> Dictionary:
	var club := {"id": 1, "country_id": 0, "reputation": 500, "name": "Test"}
	var player: Dictionary = PlayerGenerator.create_player(
		1,
		club,
		rng,
		{},
		{},
		{"next_id": 1},
		{
			"position": position,
			"current_ability": current_ability,
			"potential_ability": potential_ability,
			"age": age,
		}
	)
	player["development_factor"] = development_factor
	return player


func _simulate(
	rng: RandomNumberGenerator,
	player: Dictionary,
	last_age: int,
	setup: Dictionary,
	playing_share: float
) -> void:
	while int(player["age"]) <= last_age:
		PlayerDevelopment.develop_player(player, setup, rng, playing_share)
		player["age"] = int(player["age"]) + 1


func _setup(facility: int, coach_development: int) -> Dictionary:
	return PlayerDevelopment.training_setup(
		facility, {"attributes": {CoachTypes.ATTR_DEVELOPMENT: coach_development}}
	)


## Personality is rolled at generation, so the drive scales are pinned by hand.
func _with_drive(player: Dictionary, level: int) -> Dictionary:
	var personality: Dictionary = player.get("personality", {})
	for key in PlayerDevelopment.DRIVE_KEYS:
		personality[str(key)] = level
	player["personality"] = personality
	return player


## Mean final CA of a cohort grown from the same seeds under one setup, so two
## setups can be compared without the season noise drowning the difference.
func _cohort_mean(
	seed_base: int,
	count: int,
	last_age: int,
	setup: Dictionary,
	drive: int = -1
) -> float:
	var finals: Array[int] = []
	for seed_i in count:
		var rng := _rng(seed_base + seed_i)
		var player := _make_player(rng, PlayerTypes.POS_CM, 40, 90, 16, 1.0)
		if drive >= 0:
			_with_drive(player, drive)
		_simulate(rng, player, last_age, setup, 1.0)
		finals.append(int(player["current_ability"]))
	return _mean(finals)


## Only the attributes the position is graded on can move CA, so the check has
## to ignore the rest of the profile.
func _weighted_group_total(player: Dictionary, group: String) -> int:
	var attributes: Dictionary = player.get("attributes", {})
	var total := 0
	for path in PlayerTypes.ability_weights(str(player.get("position", ""))).keys():
		var parts := str(path).split(".")
		if parts.size() == 2 and parts[0] == group:
			total += PlayerTypes.get_attribute_value(attributes, group, parts[1])
	return total


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += float(value)
	return total / float(values.size())


func _assert_ca_matches_attributes(player: Dictionary, label: String) -> void:
	var derived := PlayerTypes.calc_current_ability(
		player.get("attributes", {}), str(player.get("position", ""))
	)
	var stored := int(player.get("current_ability", -1))
	_assert(derived == stored, "CA stays derived from attributes %s (%d vs %d)" % [label, derived, stored])


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
