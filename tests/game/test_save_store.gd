extends Node
## SQLite save roundtrip. Uses a scratch database, never user://saves/games.db.
## Run: godot --headless --path . res://tests/game/test_save_store.tscn

const SaveStoreScript := preload("res://game/save_store.gd")
const SCRATCH_PATH := "user://tests/save_store/games.db"
const SLOT := "zz_save_probe"
const LEGACY_SLOT := "zz_legacy_probe"


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Save store tests ===")
	SaveStoreScript.database_path_override = SCRATCH_PATH
	_wipe_scratch()
	if not ClassDB.class_exists("SQLite"):
		_assert(false, "SQLite class is not available")
		_finish()
		return

	_test_roundtrip()
	_test_overwrite_and_catalog()
	_test_delete()
	_test_legacy_json_migrates_once()
	_test_invalid_slot()
	_test_load_screen_opens()
	_finish()


func _test_roundtrip() -> void:
	var applied: Dictionary = GameSession.apply_save_payload(_sample_payload())
	_assert(applied["success"], "sample session accepted")
	GameSession._rng.seed = 4242
	var twin := RandomNumberGenerator.new()
	twin.seed = GameSession._rng.seed
	twin.state = GameSession._rng.state

	var started := Time.get_ticks_msec()
	var saved: Dictionary = GameSession.save_game(SLOT)
	var save_ms := Time.get_ticks_msec() - started
	_assert(saved["success"], "save writes to sqlite (%s)" % saved.get("error", ""))
	print("  save %d ms" % save_ms)

	GameSession.clear()
	_assert(not GameSession.is_active, "clear drops the session")

	started = Time.get_ticks_msec()
	var loaded: Dictionary = GameSession.load_game(SLOT)
	var load_ms := Time.get_ticks_msec() - started
	_assert(loaded["success"], "load reads sqlite (%s)" % loaded.get("error", ""))
	print("  load %d ms" % load_ms)
	_assert(GameSession.save_slot == SLOT, "loaded game keeps its slot")
	_assert(GameSession.season_number == 3, "season number")
	_assert(GameSession.season_day == 12, "season day")
	_assert(GameSession.selected_unit_id == 3, "selected unit")
	_assert(GameSession.get_club_budget(1) == 250000, "budget keeps int key")
	_assert(GameSession.get_club_players(1).size() == 1, "club squad restored")
	_assert(str(GameSession.get_club_players(1)[0].get("name", "")) == "Игрок", "player name")
	_assert(GameSession.get_club_youth_players(2).size() == 40, "youth pool")
	_assert(GameSession.free_agents.size() == 1, "free agent")
	_assert(str(GameSession.get_club_coach(1).get("name", "")) == "Тренер", "coach")
	_assert(GameSession.transfer_log.size() == 1, "transfer log")
	_assert(GameSession._next_match_id == 18, "match id counter stored, not scanned from scratch")
	_assert(GameSession._rng.randi() == twin.randi(), "rng state roundtrip")
	_assert(not FileAccess.file_exists("user://saves/%s.json" % SLOT), "save does not write json")


func _test_overwrite_and_catalog() -> void:
	GameSession.season_day = 15
	var saved: Dictionary = GameSession.save_game(SLOT)
	_assert(saved["success"], "overwrite slot")
	var listed: Dictionary = GameSession.list_saves()
	_assert(listed["success"], "catalog lists without decoding sections")
	var found := false
	var player_count := -1
	for row in listed.get("data", []):
		if typeof(row) == TYPE_DICTIONARY and str(row.get("slot", "")) == SLOT:
			found = true
			player_count = int(row.get("player_count", -1))
			_assert(int(row.get("season_day", 0)) == 15, "catalog shows the new day")
			_assert(not bool(row.get("legacy", true)), "sqlite slot is not marked legacy")
	_assert(found, "slot is in the catalog")
	_assert(player_count == 42, "catalog stores player count (got %d)" % player_count)


func _test_delete() -> void:
	var removed: Dictionary = GameSession.delete_save(SLOT)
	_assert(removed["success"], "delete slot")
	GameSession.clear()
	var missing: Dictionary = GameSession.load_game(SLOT)
	_assert(not missing["success"], "deleted slot does not load")


func _test_legacy_json_migrates_once() -> void:
	var path := "user://saves/%s.json" % LEGACY_SLOT
	_remove(path)
	var folder := "user://saves"
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_assert(false, "could not write legacy json")
		return
	file.store_string(JSON.stringify({
		"version": GameSession.SAVE_VERSION,
		"season_number": 4,
		"season_day": 2,
		"season_total_days": 10,
		"selected_unit_id": 1,
		"season_finished": false,
		"units": [{
			"id": 1,
			"label": "Лига",
			"matches": [],
			"standings": [],
			"playoff": {},
			"clubs_by_id": {"1": {"id": 1, "name": "Клуб", "finance_level": 10, "reputation": 500}},
		}],
		"players_by_club": {
			"1": [{
				"id": 7,
				"name": "Из JSON",
				"club_id": 1,
				"position": "ST",
				"current_ability": 50,
			}],
		},
		"youth_players_by_club": {},
		"reserve_players_by_club": {},
		"free_agents": [],
		"coaches_by_club": {},
		"club_budgets": {"1": 1000},
		"wages_paid_for_season": 4,
		"transfer_log": [],
		"next_player_id": 8,
		"next_coach_id": 1,
		"rng_seed": 1,
		"rng_state": 1,
	}))
	file.close()

	GameSession.clear()
	var loaded: Dictionary = GameSession.load_game(LEGACY_SLOT)
	_assert(loaded["success"], "legacy json loads (%s)" % loaded.get("error", ""))
	_assert(not FileAccess.file_exists(path), "legacy json removed after copy into sqlite")
	_assert(GameSession.get_club_players(1).size() == 1, "legacy squad coerced from string keys")
	_assert(
		GameSession.get_club_players(1)[0].has("development_factor"),
		"legacy load still migrates player fields"
	)
	GameSession.clear()
	var again: Dictionary = GameSession.load_game(LEGACY_SLOT)
	_assert(again["success"], "second load comes from sqlite")
	_assert(str(GameSession.get_club_players(1)[0].get("name", "")) == "Из JSON", "name survived migration")
	GameSession.delete_save(LEGACY_SLOT)


func _test_invalid_slot() -> void:
	var applied: Dictionary = GameSession.apply_save_payload(_sample_payload())
	_assert(applied["success"], "session ready for invalid-slot check")
	var rejected: Dictionary = GameSession.save_game("../world")
	_assert(not rejected["success"], "path-like slot is rejected")
	GameSession.clear()


func _test_load_screen_opens() -> void:
	var packed: PackedScene = load("res://scenes/load_game/load_game.tscn")
	var screen := packed.instantiate()
	add_child(screen)
	var title: Label = screen.get_node("%Title")
	var status: Label = screen.get_node("%Status")
	_assert(title.text == "Загрузить игру", "load screen title")
	_assert(screen.get_node_or_null("%List") != null, "load screen has a slot list")
	_assert(not status.visible, "load screen waits for a choice")
	screen.free()


func _sample_payload() -> Dictionary:
	var youth: Array = []
	for i in 40:
		youth.append({
			"id": 100 + i,
			"name": "Юниор %d" % i,
			"club_id": 2,
			"position": "CM",
			"age": 17,
			"current_ability": 40,
			"potential_ability": 70,
			"development_factor": 0.9,
			"is_youth": true,
			"contract_status": "club",
			"attributes": {"pace": 10},
		})
	return {
		"version": GameSession.SAVE_VERSION,
		"season_number": 3,
		"season_day": 12,
		"season_total_days": 30,
		"selected_unit_id": 3,
		"season_finished": false,
		"wages_paid_for_season": 3,
		"units": [{
			"id": 3,
			"label": "Лига",
			"matches": [{"id": 17, "season_day": 12, "played": true}],
			"standings": [],
			"playoff": {},
			"clubs_by_id": {
				1: {"id": 1, "name": "Клуб", "finance_level": 10, "reputation": 500},
				2: {"id": 2, "name": "Второй", "finance_level": 8, "reputation": 400},
			},
		}],
		"players_by_club": {
			1: [{
				"id": 5,
				"name": "Игрок",
				"club_id": 1,
				"position": "ST",
				"age": 24,
				"current_ability": 80,
				"potential_ability": 90,
				"development_factor": 0.95,
				"is_youth": false,
				"contract_status": "club",
				"attributes": {"pace": 14},
				"condition": 10000,
				"morale": 50,
			}],
		},
		"youth_players_by_club": {2: youth},
		"reserve_players_by_club": {},
		"free_agents": [{
			"id": 9,
			"name": "Свободный",
			"club_id": 0,
			"position": "GK",
			"current_ability": 30,
			"potential_ability": 40,
			"development_factor": 0.8,
			"contract_status": "free_agent",
		}],
		"coaches_by_club": {
			1: {"id": 4, "name": "Тренер", "club_id": 1, "current_ability": 60},
		},
		"club_budgets": {1: 250000, 2: 10000},
		"transfer_log": [{"player_id": 5, "fee": 1000}],
		"next_player_id": 200,
		"next_coach_id": 5,
		"rng_seed": 7,
		"rng_state": 7,
	}


func _wipe_scratch() -> void:
	for suffix in ["", "-wal", "-shm"]:
		_remove(SCRATCH_PATH + suffix)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % message)
	else:
		_failed += 1
		print("  FAIL  %s" % message)


func _finish() -> void:
	GameSession.delete_save(SLOT)
	GameSession.delete_save(LEGACY_SLOT)
	_remove("user://saves/%s.json" % LEGACY_SLOT)
	GameSession.clear()
	SaveStoreScript.database_path_override = ""
	_wipe_scratch()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
