extends Node
## Youth intake: each country rolls its own PA, then clubs compete inside that country.
## Run: godot --headless --path . res://tests/game/test_youth_intake.tscn

const TEST_DB_PATH := ":memory:"
const YouthIntakeScript := preload("res://game/youth_intake.gd")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_isolate_pa_config()
	print("=== Youth intake tests ===")
	_test_slot_counts_and_caps()
	_test_youth_talent_bias()
	_test_country_owns_its_generation()
	_test_youth_recruitment_bias()
	_test_academy_affects_ca_not_pa()
	_test_training_and_scouting_do_not_change_intake_pa()
	_test_deterministic_rng()
	_test_legacy_save_payload()
	_test_free_agents_and_market_clock()
	_test_country_persistence_and_legacy_migration()
	_test_pa_config_save_load()
	_test_saved_birth_table_drives_intake()
	_finish()


func _test_slot_counts_and_caps() -> void:
	var rng := _rng(11)
	var clubs := _two_country_clubs(4, 4)
	var countries := {
		1: {"id": 1, "youth_talent": 80},
		2: {"id": 2, "youth_talent": 20},
	}
	var assignments: Array = YouthIntakeScript.plan_intake(
		clubs, countries, rng, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6}
	)
	_assert(assignments.size() == 48, "Test 1: created players equal world slots (got %d)" % assignments.size())

	var by_country := {1: 0, 2: 0}
	var by_club: Dictionary = {}
	for row in assignments:
		var country_id := int(row.get("country_id", 0))
		var club_id := int(row.get("club_id", 0))
		by_country[country_id] = int(by_country.get(country_id, 0)) + 1
		by_club[club_id] = int(by_club.get(club_id, 0)) + 1
	_assert(int(by_country[1]) == 24, "Test 2: country 1 not overfilled (%d)" % int(by_country[1]))
	_assert(int(by_country[2]) == 24, "Test 2: country 2 not overfilled (%d)" % int(by_country[2]))
	var overflow := false
	for club_id in by_club.keys():
		if int(by_club[club_id]) > 6:
			overflow = true
	_assert(not overflow, "Test 2: no club received more than its slots")
	_assert(by_club.size() == 8, "Test 2: every club received players")


func _test_youth_talent_bias() -> void:
	var clubs: Array = []
	for country_id in [1, 2, 3]:
		for i in 4:
			clubs.append(_club(country_id * 100 + i, country_id, {"name": "C%d-%d" % [country_id, i]}))
	var countries := {
		1: {"id": 1, "youth_talent": 50},
		2: {"id": 2, "youth_talent": 75},
		3: {"id": 3, "youth_talent": 80},
	}
	var best := {1: 0.0, 2: 0.0, 3: 0.0}
	var mean := {1: 0.0, 2: 0.0, 3: 0.0}
	var runs := 40
	for i in runs:
		var rng := _rng(3000 + i)
		var assignments: Array = YouthIntakeScript.plan_intake(
			clubs, countries, rng, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6}
		)
		var by_country := {1: [], 2: [], 3: []}
		for row in assignments:
			var cid := int(row.get("country_id", 0))
			(by_country[cid] as Array).append(int(row.get("potential_ability", 0)))
		for cid in [1, 2, 3]:
			var pas: Array = by_country[cid]
			best[cid] = float(best[cid]) + _best_mean(pas, 8)
			mean[cid] = float(mean[cid]) + _mean_of(pas)
	for cid in [1, 2, 3]:
		best[cid] = float(best[cid]) / float(runs)
		mean[cid] = float(mean[cid]) / float(runs)
	_assert(
		float(mean[3]) >= float(mean[2]) + 0.4,
		"Test 3: squad mean talent 80 beats 75 (%.1f vs %.1f)" % [float(mean[3]), float(mean[2])]
	)
	_assert(
		float(mean[2]) >= float(mean[1]) + 3.0,
		"Test 3: squad mean talent 75 beats 50 (%.1f vs %.1f)" % [float(mean[2]), float(mean[1])]
	)
	_assert(
		float(best[3]) >= float(best[1]) + 3.0,
		"Test 3: best-8 talent 80 beats 50 (%.1f vs %.1f)" % [float(best[3]), float(best[1])]
	)


func _test_country_owns_its_generation() -> void:
	_assert(YouthGenerationConfigScript.TALENT_BIRTH_WEIGHTS.size() == 101, "Test 4: every talent 0..100 has birth chances")
	var weights_10: Array = YouthGenerationConfigScript.birth_weights(10)
	var weights_80: Array = YouthGenerationConfigScript.birth_weights(80)
	var sum_10 := 0
	var sum_80 := 0
	for weight in weights_10:
		sum_10 += int(weight)
	for weight in weights_80:
		sum_80 += int(weight)
	_assert(sum_10 == 1000, "Test 4: talent 10 chances sum to 100 percent")
	_assert(sum_80 == 1000, "Test 4: talent 80 chances sum to 100 percent")
	_assert(int(weights_10[5]) == 0, "Test 4: talent 10 does not birth 90-100")
	var weights_100: Array = YouthGenerationConfigScript.birth_weights(100)
	_assert(int(weights_100[4]) == 40, "Test 4: talent 100 births 80-89 in 4 percent")
	_assert(int(weights_100[5]) == 5, "Test 4: talent 100 births 90-100 in 0.5 percent")
	var clubs: Array = [_club(1, 1, {"name": "Strong"})]
	for i in 40:
		clubs.append(_club(100 + i, 2, {"name": "W%d" % i}))
	var countries := {
		1: {"id": 1, "youth_talent": 80},
		2: {"id": 2, "youth_talent": 20},
	}
	var strong_sum := 0
	var strong_n := 0
	var weak_sum := 0
	var weak_n := 0
	var weak_max := 0
	for i in 30:
		var rng := _rng(4000 + i)
		var assignments: Array = YouthIntakeScript.plan_intake(
			clubs, countries, rng, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6}
		)
		for row in assignments:
			var pa := int(row.get("potential_ability", 0))
			if int(row.get("country_id", 0)) == 1:
				strong_sum += pa
				strong_n += 1
			else:
				weak_sum += pa
				weak_n += 1
				weak_max = maxi(weak_max, pa)
	var strong_mean := float(strong_sum) / float(strong_n)
	var weak_mean := float(weak_sum) / float(weak_n)
	_assert(weak_max <= 89, "Test 4: talent 20 does not birth 90+ (max %d)" % weak_max)
	_assert(strong_n == 180, "Test 4: talent 80 filled only its own slots (%d)" % strong_n)
	_assert(
		strong_mean >= weak_mean + 8.0,
		"Test 4: one talent-80 club beats a large talent-20 pool (%.1f vs %.1f)" % [strong_mean, weak_mean]
	)


func _test_youth_recruitment_bias() -> void:
	var clubs := [
		_club(1, 1, {"youth_search": 20, "reputation": 500, "name": "Scout"}),
		_club(2, 1, {"youth_search": 5, "reputation": 500, "name": "Local"}),
	]
	var countries := {1: {"id": 1, "youth_talent": 60}}
	var mean_hi := 0.0
	var mean_lo := 0.0
	var n := 180
	for i in n:
		var rng := _rng(2000 + i)
		var assignments: Array = YouthIntakeScript.plan_intake(
			clubs, countries, rng, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6}
		)
		var sum_hi := 0
		var sum_lo := 0
		var c_hi := 0
		var c_lo := 0
		for row in assignments:
			var pa := int(row.get("potential_ability", 0))
			if int(row.get("club_id", 0)) == 1:
				sum_hi += pa
				c_hi += 1
			else:
				sum_lo += pa
				c_lo += 1
		if c_hi > 0:
			mean_hi += float(sum_hi) / float(c_hi)
		if c_lo > 0:
			mean_lo += float(sum_lo) / float(c_lo)
	mean_hi /= float(n)
	mean_lo /= float(n)
	_assert(
		absf(mean_hi - mean_lo) < 3.0,
		"Test 5: search does not move players between clubs (%.2f vs %.2f)" % [mean_hi, mean_lo]
	)


func _test_academy_affects_ca_not_pa() -> void:
	var rng := _rng(33)
	var pa := 85
	var sum_low := 0
	var sum_high := 0
	for _i in 200:
		sum_low += YouthIntakeScript.generate_youth_starting_ability(rng, pa, 16, 5, YouthIntakeScript.MODE_YOUTH)
		sum_high += YouthIntakeScript.generate_youth_starting_ability(rng, pa, 16, 18, YouthIntakeScript.MODE_YOUTH)
	var mean_low := float(sum_low) / 200.0
	var mean_high := float(sum_high) / 200.0
	_assert(mean_high > mean_low + 2.0, "Test 6: academy raises CA (%.1f vs %.1f)" % [mean_high, mean_low])

	var clubs := [
		_club(1, 1, {"youth_academy": 5, "youth_search": 10, "name": "LowAcad"}),
		_club(2, 1, {"youth_academy": 18, "youth_search": 10, "name": "HighAcad"}),
	]
	var countries := {1: {"id": 1, "youth_talent": 50}}
	var rng_a := _rng(44)
	var rng_b := _rng(44)
	var a: Array = YouthIntakeScript.plan_intake(clubs, countries, rng_a, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	var b: Array = YouthIntakeScript.plan_intake(clubs, countries, rng_b, {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	_assert(_pa_list(a) == _pa_list(b), "Test 6: academy does not change world PA list")


func _test_training_and_scouting_do_not_change_intake_pa() -> void:
	var base := [
		_club(1, 1, {"training_level": 0, "scouting_level": 0, "name": "A"}),
		_club(2, 1, {"training_level": 0, "scouting_level": 0, "name": "B"}),
	]
	var trained := [
		_club(1, 1, {"training_level": 20, "scouting_level": 0, "name": "A"}),
		_club(2, 1, {"training_level": 20, "scouting_level": 0, "name": "B"}),
	]
	var scouted := [
		_club(1, 1, {"training_level": 0, "scouting_level": 20, "name": "A"}),
		_club(2, 1, {"training_level": 0, "scouting_level": 20, "name": "B"}),
	]
	var countries := {1: {"id": 1, "youth_talent": 64}}
	var a: Array = YouthIntakeScript.plan_intake(base, countries, _rng(55), {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	var b: Array = YouthIntakeScript.plan_intake(trained, countries, _rng(55), {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	var c: Array = YouthIntakeScript.plan_intake(scouted, countries, _rng(55), {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	_assert(_pa_list(a) == _pa_list(b), "Test 7: training facilities do not change intake PA")
	_assert(_assignment_pairs(a) == _assignment_pairs(b), "Test 7: training does not change club assignment")
	_assert(_pa_list(a) == _pa_list(c), "Test 8: scouting does not change intake PA")
	_assert(_assignment_pairs(a) == _assignment_pairs(c), "Test 8: scouting does not change club assignment")


func _test_deterministic_rng() -> void:
	var clubs := _two_country_clubs(3, 3)
	var countries := {
		1: {"id": 1, "youth_talent": 82},
		2: {"id": 2, "youth_talent": 31},
	}
	var a: Array = YouthIntakeScript.plan_intake(clubs, countries, _rng(999), {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	var b: Array = YouthIntakeScript.plan_intake(clubs, countries, _rng(999), {"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 6})
	_assert(_assignment_pairs(a) == _assignment_pairs(b), "Test 11: same seed yields the same youth intake")


func _test_legacy_save_payload() -> void:
	var payload := {
		"version": 3,
		"season_number": 2,
		"season_day": 4,
		"season_total_days": 40,
		"selected_unit_id": 0,
		"season_finished": false,
		"units": [],
		"players_by_club": {
			"1": [{
				"id": 7,
				"club_id": 1,
				"name": "Legacy",
				"age": 22,
				"position": "CM",
				"current_ability": 61,
				"overall": 61,
			}]
		},
	}
	var result: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(result.get("success", false)), "Test 10: legacy save payload loads")
	_assert(GameSession.youth_players_by_club.is_empty() or GameSession.get_club_youth_players(1).is_empty(), "Test 10: missing youth map is safe")
	var player: Dictionary = GameSession.get_player(7)
	_assert(not player.is_empty(), "Test 10: legacy player is reachable")
	_assert(player.has("development_factor"), "Test 10: development_factor backfilled")
	_assert(int(player.get("potential_ability", 0)) == 61, "Test 10: PA backfilled from CA")
	_assert(GameSession.free_agents.is_empty(), "Test 10: missing free_agents is safe")
	_assert(str(player.get("contract_status", "")) == GameSession.STATUS_CLUB, "Test 10: club contract backfilled")
	GameSession.clear()


func _test_free_agents_and_market_clock() -> void:
	_assert(GameSession.next_calendar_day(-2) == -1, "Test 12: market day -2 advances to -1")
	_assert(GameSession.next_calendar_day(-1) == 1, "Test 12: market day -1 skips 0 and goes to 1")
	_assert(GameSession.next_calendar_day(1) == 2, "Test 12: match day 1 advances to 2")

	var squads := {
		1: [{
			"id": 11,
			"club_id": 1,
			"name": "Alpha",
			"contract_years": 3,
			"contract_status": GameSession.STATUS_CLUB,
			"nationality_country_id": 1,
			"current_ability": 70,
			"potential_ability": 80,
			"age": 24,
			"position": "ST",
			"is_youth": false,
		}],
		2: [{
			"id": 12,
			"club_id": 2,
			"name": "Beta",
			"contract_years": 2,
			"contract_status": GameSession.STATUS_CLUB,
			"nationality_country_id": 1,
			"current_ability": 64,
			"potential_ability": 72,
			"age": 21,
			"position": "CM",
			"is_youth": false,
		}],
	}
	var detached: Dictionary = SeasonBuilder.detach_squads_as_free_agents(squads)
	var free_agents: Array = detached.get("free_agents", [])
	var empty_clubs: Dictionary = detached.get("players_by_club", {})
	_assert(free_agents.size() == 2, "Test 12: both generated players become free agents")
	_assert((empty_clubs.get(1, ["x"]) as Array).is_empty(), "Test 12: club 1 squad is empty after detach")
	_assert((empty_clubs.get(2, ["x"]) as Array).is_empty(), "Test 12: club 2 squad is empty after detach")
	for player in free_agents:
		_assert(int(player.get("club_id", -1)) == 0, "Test 12: free agent has no club")
		_assert(str(player.get("contract_status", "")) == GameSession.STATUS_FREE_AGENT, "Test 12: status is free agent")
		_assert(int(player.get("contract_years", -1)) == 0, "Test 12: free agent contract years cleared")

	var payload := {
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.MARKET_OPEN_DAY,
		"season_total_days": 32,
		"selected_unit_id": 0,
		"season_finished": false,
		"units": [],
		"players_by_club": {"1": [], "2": []},
		"youth_players_by_club": {},
		"free_agents": free_agents,
	}
	var result: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(result.get("success", false)), "Test 12: market save payload loads")
	_assert(GameSession.season_day == GameSession.MARKET_OPEN_DAY, "Test 12: season starts on the opening market day")
	_assert(GameSession.get_club_players(1).is_empty(), "Test 12: clubs have no first-team players")
	_assert(GameSession.get_market_player_rows().size() == 2, "Test 12: market lists free agents")
	_assert(GameSession.get_all_player_rows().size() == 2, "Test 12: players directory includes free agents")
	_assert(GameSession.is_market_day(), "Test 12: the opening day is a market day")

	# The window runs MARKET_OPEN_DAY..MARKET_LAST_DAY, so walk it instead of
	# hard-coding how many days it is wide.
	while GameSession.season_day < GameSession.MARKET_LAST_DAY:
		var day := GameSession.season_day
		var stepped: Dictionary = GameSession.advance_day()
		_assert(bool(stepped.get("success", false)), "Test 12: can advance from market day %d" % day)
		_assert(
			GameSession.is_market_day(),
			"Test 12: day %d is still inside the window" % GameSession.season_day
		)
	_assert(GameSession.season_day == GameSession.MARKET_LAST_DAY, "Test 12: window ends on the last market day")
	var advanced: Dictionary = GameSession.advance_day()
	_assert(bool(advanced.get("success", false)), "Test 12: can advance from the last market day")
	_assert(GameSession.season_day == GameSession.FIRST_MATCH_DAY, "Test 12: after market window comes day 1")
	_assert(not GameSession.is_market_day(), "Test 12: day 1 is not a market day")
	GameSession.clear()


func _test_country_persistence_and_legacy_migration() -> void:
	if not ClassDB.class_exists("SQLite"):
		_fail("SQLite unavailable for country persistence tests")
		return
	WorldDatabase.close()
	if not DatabaseManager.open_database(TEST_DB_PATH):
		_fail("Failed to open temp DB: %s" % DatabaseManager.get_last_error())
		return
	var migrator := MigrationManager.new()
	var until_22: Array = _migrations_until(22)
	if not migrator.migrate(DatabaseManager, until_22):
		_fail("Failed to migrate temp DB to 22: %s" % DatabaseManager.get_last_error())
		_restore_world_db()
		return

	var now := Time.get_datetime_string_from_system(true)
	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO continents (name, code, created_at, updated_at)
		VALUES (?, ?, ?, ?);
		""",
		["Youth Cont", "YTHC", now, now]
	):
		_fail("Failed to insert continent")
		_restore_world_db()
		return
	var continent_id := int(DatabaseManager.query_rows("SELECT id FROM continents WHERE code = 'YTHC';")[0]["id"])
	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO countries (continent_id, name, abbreviation, reputation, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?);
		""",
		[continent_id, "Legacyland", "LGL", 500, now, now]
	):
		_fail("Failed to insert country before youth_talent: %s" % DatabaseManager.get_last_error())
		_restore_world_db()
		return
	var country_id := int(DatabaseManager.query_rows("SELECT id FROM countries WHERE abbreviation = 'LGL';")[0]["id"])
	var elite_seeds := [
		["r90_100", 90, 100, 8.0, 0, 10],
		["r85_89", 85, 89, 12.0, 0, 20],
		["r80_84", 80, 84, 20.0, 0, 30],
		["r70_79", 70, 79, 30.0, 0, 40],
		["r60_69", 60, 69, 20.0, 0, 50],
		["r50_59", 50, 59, 10.0, 0, 60],
		["r40_49", 40, 49, 0.0, 0, 70],
		["r0_39", 0, 39, 0.0, 1, 80],
	]
	for seed in elite_seeds:
		DatabaseManager.execute_with_bindings(
			"""
			INSERT INTO country_youth_rating_distribution (
				country_id, bucket_key, rating_min, rating_max, weight_pct, is_hidden, sort_order, updated_at
			) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
			""",
			[country_id, seed[0], seed[1], seed[2], seed[3], seed[4], seed[5], now]
		)

	if not migrator.migrate(DatabaseManager, _migrations_until(23)):
		_fail("Migration 23 failed: %s" % DatabaseManager.get_last_error())
		_restore_world_db()
		return

	var dropped: Array = DatabaseManager.query_rows(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'country_youth_rating_distribution';"
	)
	_assert(dropped.is_empty(), "Test 10: legacy distribution table dropped")

	var raw_rows: Array = DatabaseManager.query_rows(
		"SELECT youth_talent FROM countries WHERE abbreviation = 'LGL';"
	)
	var raw_talent := int(raw_rows[0]["youth_talent"])
	_assert(raw_talent > 500, "Test 10: elite legacy table maps above the old default (%d)" % raw_talent)

	if not migrator.migrate(DatabaseManager, _migrations_until(26)):
		_fail("Migration 26 failed: %s" % DatabaseManager.get_last_error())
		_restore_world_db()
		return

	var repo := CountryRepository.new(DatabaseManager)
	var loaded := repo.get_by_id(country_id)
	_assert(bool(loaded.get("success", false)), "Test 9: country loads after migration")
	var talent := int(loaded.get("data", {}).get("youth_talent", -1))
	_assert(talent == 75, "Test 10: elite legacy talent scales 751 → 75 (got %d)" % talent)

	var updated := repo.update(country_id, {
		"continent_id": continent_id,
		"name": "Legacyland",
		"abbreviation": "LGL",
		"reputation": 500,
		"youth_talent": 78,
	})
	_assert(bool(updated.get("success", false)), "Test 9: youth_talent updates")
	var again := repo.get_by_id(country_id)
	_assert(int(again.get("data", {}).get("youth_talent", 0)) == 78, "Test 9: youth_talent round-trips")

	var created := repo.create({
		"continent_id": continent_id,
		"name": "Newland",
		"abbreviation": "NWL",
		"reputation": 400,
		"youth_talent": 94,
	})
	_assert(bool(created.get("success", false)), "Test 9: create with youth_talent")
	if created["success"]:
		_assert(int(created["data"].get("youth_talent", 0)) == 94, "Test 9: created youth_talent stored")

	_restore_world_db()


func _test_pa_config_save_load() -> void:
	var custom := {
		"r95_100": 1.00,
		"r90_94": 2.00,
		"r85_89": 3.00,
		"r80_84": 4.00,
		"r70_79": 20.00,
		"r60_69": 30.00,
		"r20_59": 40.00,
	}
	var saved: Dictionary = YouthGenerationConfigScript.apply_pa_weights(custom)
	_assert(bool(saved.get("ok", false)), "Test 11: custom PA weights save")
	_assert(
		FileAccess.file_exists(YouthGenerationConfigScript.config_path),
		"Test 11: config file written"
	)

	YouthGenerationConfigScript.unload()
	var loaded: Array = YouthGenerationConfigScript.get_pa_buckets()
	var by_key := {}
	for bucket in loaded:
		by_key[YouthGenerationConfigScript.pa_bucket_key(bucket)] = float(bucket.get("weight_pct", -1.0))
	_assert(is_equal_approx(float(by_key.get("r20_59", 0.0)), 40.0), "Test 11: reloaded r20_59")
	_assert(is_equal_approx(float(by_key.get("r95_100", 0.0)), 1.0), "Test 11: reloaded r95_100")

	var before_weight := float(YouthGenerationConfigScript.get_pa_buckets()[0]["weight_pct"])
	var rejected: Dictionary = YouthGenerationConfigScript.apply_pa_weights({"r95_100": 50.0})
	_assert(not bool(rejected.get("ok", true)), "Test 11: incomplete weights rejected")
	var after_weight := float(YouthGenerationConfigScript.get_pa_buckets()[0]["weight_pct"])
	_assert(is_equal_approx(before_weight, after_weight), "Test 11: rejected save keeps runtime")

	var only_floor := {
		"r95_100": 0.0,
		"r90_94": 0.0,
		"r85_89": 0.0,
		"r80_84": 0.0,
		"r70_79": 0.0,
		"r60_69": 0.0,
		"r20_59": 100.0,
	}
	var floor_ok: Dictionary = YouthGenerationConfigScript.apply_pa_weights(only_floor)
	_assert(bool(floor_ok.get("ok", false)), "Test 11: 100% floor bucket saves")
	var assignments: Array = YouthIntakeScript.plan_intake(
		_two_country_clubs(2, 2),
		{
			1: {"id": 1, "youth_talent": 50},
			2: {"id": 2, "youth_talent": 50},
		},
		_rng(99),
		{"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 5}
	)
	var saw_above_floor := false
	for row in assignments:
		if int(row.get("potential_ability", 0)) > 59:
			saw_above_floor = true
			break
	_assert(saw_above_floor, "Test 11: birth follows the talent table, not the settings buckets")
	YouthGenerationConfigScript.reset_to_defaults(false)


func _test_saved_birth_table_drives_intake() -> void:
	var rows: Array = YouthGenerationConfigScript.default_birth_weights()
	rows[80] = [1000, 0, 0, 0, 0, 0]
	var saved: Dictionary = YouthGenerationConfigScript.apply_birth_weights(rows)
	_assert(bool(saved.get("ok", false)), "Test 13: birth table saves")
	YouthGenerationConfigScript.unload_birth()
	var assignments: Array = YouthIntakeScript.plan_intake(
		[_club(1, 1, {"name": "OnlyLow"})],
		{1: {"id": 1, "youth_talent": 80}},
		_rng(13),
		{"mode": YouthIntakeScript.MODE_YOUTH, "slots_per_club": 8}
	)
	var all_in_band := assignments.size() == 8
	for row in assignments:
		var potential_ability := int(row.get("potential_ability", 0))
		if potential_ability < 40 or potential_ability > 49:
			all_in_band = false
	_assert(all_in_band, "Test 13: saved talent row is what gets born")
	rows[80] = [100, 0, 0, 0, 0, 0]
	var rejected: Dictionary = YouthGenerationConfigScript.apply_birth_weights(rows)
	_assert(not bool(rejected.get("ok", true)), "Test 13: a row that is not 100% is rejected")
	var tab := (load("res://scenes/settings/tabs/global_pa_tab.tscn") as PackedScene).instantiate()
	add_child(tab)
	var row_count := tab.get_node("%Rows").get_child_count()
	_assert(row_count == 102, "Test 13: header and every talent 0–100 are on screen (%d)" % row_count)
	tab.queue_free()
	YouthGenerationConfigScript.reset_birth_to_defaults(false)


func _isolate_pa_config() -> void:
	YouthGenerationConfigScript.config_path = "user://config/youth_generation_test.json"
	_delete_file_if_exists(YouthGenerationConfigScript.config_path)
	YouthGenerationConfigScript.reset_to_defaults(false)
	YouthGenerationConfigScript.birth_config_path = "user://config/youth_talent_birth_test.json"
	_delete_file_if_exists(YouthGenerationConfigScript.birth_config_path)
	YouthGenerationConfigScript.unload_birth()
	YouthGenerationConfigScript.reset_birth_to_defaults(false)


func _restore_pa_config() -> void:
	_delete_file_if_exists("user://config/youth_generation_test.json")
	_delete_file_if_exists("user://config/youth_talent_birth_test.json")
	YouthGenerationConfigScript.config_path = YouthGenerationConfigScript.DEFAULT_CONFIG_PATH
	YouthGenerationConfigScript.birth_config_path = YouthGenerationConfigScript.DEFAULT_BIRTH_CONFIG_PATH
	YouthGenerationConfigScript.reset_to_defaults(false)
	YouthGenerationConfigScript.unload_birth()


func _delete_file_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _two_country_clubs(n1: int, n2: int) -> Array:
	var clubs: Array = []
	for i in n1:
		clubs.append(_club(i + 1, 1, {"name": "A%d" % i}))
	for i in n2:
		clubs.append(_club(100 + i, 2, {"name": "B%d" % i}))
	return clubs


func _club(id: int, country_id: int, extra: Dictionary = {}) -> Dictionary:
	var club := {
		"id": id,
		"country_id": country_id,
		"reputation": 500,
		"youth_academy": 10,
		"training_level": 10,
		"scouting_level": 10,
		"youth_search": 10,
		"name": "Club %d" % id,
	}
	for key in extra.keys():
		club[key] = extra[key]
	return club


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _best_mean(values: Array, take: int) -> float:
	var sorted: Array = values.duplicate()
	sorted.sort()
	sorted.reverse()
	var n := mini(take, sorted.size())
	if n <= 0:
		return 0.0
	var total := 0
	for i in n:
		total += int(sorted[i])
	return float(total) / float(n)


func _mean_of(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var total := 0
	for value in values:
		total += int(value)
	return float(total) / float(values.size())


func _pa_list(assignments: Array) -> Array:
	var out: Array = []
	for row in assignments:
		out.append(int(row.get("potential_ability", 0)))
	return out


func _assignment_pairs(assignments: Array) -> Array:
	var out: Array = []
	for row in assignments:
		out.append([
			int(row.get("potential_ability", 0)),
			int(row.get("country_id", 0)),
			int(row.get("club_id", 0)),
		])
	return out


func _migrations_until(max_version: int) -> Array:
	var all: Array = [
		WorldMigration001System.new(),
		WorldMigration002Geography.new(),
		WorldMigration003Clubs.new(),
		WorldMigration004Competitions.new(),
		WorldMigration005SeedContinents.new(),
		WorldMigration006CountriesV2.new(),
		WorldMigration007YouthRatingDistribution.new(),
		WorldMigration008CountryYouthDistribution.new(),
		WorldMigration009YouthWeightDecimals.new(),
		WorldMigration010ClubsFacilities.new(),
		WorldMigration011ClubReputation.new(),
		WorldMigration012CompetitionCard.new(),
		WorldMigration013CompetitionUnits.new(),
		WorldMigration014UnitClubs.new(),
		WorldMigration015UnitLogo.new(),
		preload("res://database/migrations/world_migration_016_divisions_rules.gd").new(),
		preload("res://database/migrations/world_migration_017_divisions_movement.gd").new(),
		preload("res://database/migrations/world_migration_018_ranking_order.gd").new(),
		preload("res://database/migrations/world_migration_019_regular_season.gd").new(),
		preload("res://database/migrations/world_migration_020_movement_scope.gd").new(),
		preload("res://database/migrations/world_migration_021_playoff_rules.gd").new(),
		preload("res://database/migrations/world_migration_022_country_names.gd").new(),
		preload("res://database/migrations/world_migration_023_country_youth_talent.gd").new(),
		preload("res://database/migrations/world_migration_024_discipline_rules.gd").new(),
		preload("res://database/migrations/world_migration_025_prize_rules.gd").new(),
		preload("res://database/migrations/world_migration_026_youth_talent_scale.gd").new(),
		preload("res://database/migrations/world_migration_027_division_strength.gd").new(),
	]
	var out: Array = []
	for migration in all:
		if int(migration.get_version()) <= max_version:
			out.append(migration)
	return out


func _restore_world_db() -> void:
	DatabaseManager.close_database()
	WorldDatabase.initialize()


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
	_restore_pa_config()
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
