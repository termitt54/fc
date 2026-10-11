extends Node
## Repository tests on a temporary DB. Does not modify user://database/world.db.
## Run: godot --headless --path . res://tests/database/test_continent_repository.tscn

const TEST_DB_PATH := ":memory:"

var _failed := 0
var _passed := 0
var _repo: ContinentRepository


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== ContinentRepository tests ===")

	if not ClassDB.class_exists("SQLite"):
		_fail("SQLite class is unavailable")
		_finish()
		return

	if not _prepare_temp_database():
		_finish()
		return

	_repo = ContinentRepository.new(DatabaseManager)

	_test_create()
	_test_uniqueness()
	_test_normalization()
	_test_update_timestamps()
	_test_active_toggle()
	_test_safe_delete()
	_test_search()

	_cleanup_temp_database()
	if not WorldDatabase.initialize():
		_fail("Failed to restore WorldDatabase after tests: %s" % WorldDatabase.get_last_error())
	else:
		_pass("WorldDatabase restored")

	_finish()


func _prepare_temp_database() -> bool:
	# Isolated in-memory DB — never touches user://database/world.db
	WorldDatabase.close()

	if not DatabaseManager.open_database(TEST_DB_PATH):
		_fail("Failed to open temp DB: %s" % DatabaseManager.get_last_error())
		return false

	var migrator := MigrationManager.new()
	var migrations: Array = [
		WorldMigration001System.new(),
		WorldMigration002Geography.new(),
		WorldMigration003Clubs.new(),
		WorldMigration004Competitions.new(),
		WorldMigration006CountriesV2.new(),
	]
	if not migrator.migrate(DatabaseManager, migrations):
		_fail("Failed to migrate temp DB: %s" % DatabaseManager.get_last_error())
		return false

	_pass("Temp database ready: %s" % TEST_DB_PATH)
	return true


func _cleanup_temp_database() -> void:
	DatabaseManager.close_database()


func _test_create() -> void:
	var result := _repo.create({
		"name": "Европа",
		"short_name": "УЕФА",
		"code": "EUROPE",
		"sort_order": 10,
		"is_active": true,
	})
	if not result["success"]:
		_fail("create failed: %s" % result["error"])
		return

	var data: Dictionary = result["data"]
	var by_id := _repo.get_by_id(int(data["id"]))
	if not by_id["success"]:
		_fail("get_by_id failed after create")
		return

	var row: Dictionary = by_id["data"]
	if (
		row["name"] == "Европа"
		and row["short_name"] == "УЕФА"
		and row["code"] == "EUROPE"
		and int(row["sort_order"]) == 10
		and bool(row["is_active"])
		and int(row["countries_count"]) == 0
		and int(row["clubs_count"]) == 0
	):
		_pass("create + get_by_id fields ok")
	else:
		_fail("create fields mismatch: %s" % str(row))


func _test_uniqueness() -> void:
	var duplicate := _repo.create({
		"name": "Европа 2",
		"code": "EUROPE",
		"sort_order": 0,
		"is_active": true,
	})
	if duplicate["success"]:
		_fail("duplicate code was accepted")
	elif str(duplicate["error"]).findn("EUROPE") >= 0:
		_pass("duplicate code rejected with friendly message")
	else:
		_fail("duplicate rejected but message unexpected: %s" % duplicate["error"])


func _test_normalization() -> void:
	var normalized := ContinentCode.normalize("north america")
	if normalized != "NORTH_AMERICA":
		_fail("normalize expected NORTH_AMERICA, got %s" % normalized)
		return

	var result := _repo.create({
		"name": "Северная Америка",
		"code": "north america",
		"sort_order": 20,
		"is_active": true,
	})
	if not result["success"]:
		_fail("create with raw code failed: %s" % result["error"])
		return
	if str(result["data"]["code"]) == "NORTH_AMERICA":
		_pass("code normalization on create")
	else:
		_fail("stored code mismatch: %s" % result["data"]["code"])


func _test_update_timestamps() -> void:
	var created := _repo.create({
		"name": "Азия",
		"code": "ASIA",
		"sort_order": 30,
		"is_active": true,
	})
	if not created["success"]:
		_fail("create Asia failed: %s" % created["error"])
		return

	var continent_id := int(created["data"]["id"])
	var created_at := str(created["data"]["created_at"])
	OS.delay_msec(1100)

	var updated := _repo.update(continent_id, {
		"name": "Азия Обновлённая",
		"short_name": "АФК",
		"code": "ASIA",
		"sort_order": 31,
		"is_active": true,
	})
	if not updated["success"]:
		_fail("update failed: %s" % updated["error"])
		return

	var row: Dictionary = updated["data"]
	if str(row["created_at"]) != created_at:
		_fail("created_at changed on update")
	elif str(row["updated_at"]) == created_at:
		_fail("updated_at did not change")
	elif str(row["name"]) != "Азия Обновлённая":
		_fail("name was not updated")
	else:
		_pass("update keeps created_at and refreshes updated_at")


func _test_active_toggle() -> void:
	var created := _repo.create({
		"name": "Африка",
		"code": "AFRICA",
		"sort_order": 40,
		"is_active": true,
	})
	if not created["success"]:
		_fail("create Africa failed: %s" % created["error"])
		return

	var continent_id := int(created["data"]["id"])
	var disabled := _repo.set_active(continent_id, false)
	if not disabled["success"] or bool(disabled["data"]["is_active"]):
		_fail("set_active(false) failed")
		return

	var still_there := _repo.get_by_id(continent_id)
	if not still_there["success"]:
		_fail("continent missing after deactivate")
		return

	var enabled := _repo.set_active(continent_id, true)
	if enabled["success"] and bool(enabled["data"]["is_active"]):
		_pass("active toggle keeps row and restores flag")
	else:
		_fail("set_active(true) failed")


func _test_safe_delete() -> void:
	var created := _repo.create({
		"name": "Океания",
		"code": "OCEANIA",
		"sort_order": 50,
		"is_active": true,
	})
	if not created["success"]:
		_fail("create Oceania failed: %s" % created["error"])
		return

	var continent_id := int(created["data"]["id"])
	var now := Time.get_datetime_string_from_system(true)
	var country_ok: bool = DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?);
		""",
		[continent_id, "Test Country", "TOCE", now, now]
	)
	if not country_ok:
		_fail("failed to insert linked country: %s" % DatabaseManager.get_last_error())
		return

	var blocked := _repo.delete(continent_id)
	if blocked["success"]:
		_fail("delete with countries was allowed")
		return
	if str(blocked["error"]).findn("стран") < 0:
		_fail("delete block message unexpected: %s" % blocked["error"])
		return
	_pass("delete blocked when countries exist")

	DatabaseManager.execute_with_bindings(
		"DELETE FROM countries WHERE abbreviation = ?;",
		["TOCE"]
	)
	var deleted := _repo.delete(continent_id)
	if deleted["success"]:
		_pass("delete succeeds after countries removed")
	else:
		_fail("delete failed after cleanup: %s" % deleted["error"])


func _test_search() -> void:
	_repo.create({"name": "Южная Америка", "short_name": "КОНМЕБОЛ", "code": "SOUTH_AMERICA", "sort_order": 60, "is_active": true})
	_repo.create({"name": "Кастом", "short_name": "CST", "code": "CUSTOM_X", "sort_order": 70, "is_active": true})

	var by_name := _repo.search("южн")
	var by_short := _repo.search("конме")
	var by_code := _repo.search("custom")

	if not by_name["success"] or by_name["data"].is_empty():
		_fail("search by name failed")
	elif not by_short["success"] or by_short["data"].is_empty():
		_fail("search by short_name failed")
	elif not by_code["success"] or by_code["data"].is_empty():
		_fail("search by code failed")
	else:
		_pass("search by name/short/code is case-insensitive")


func _pass(message: String) -> void:
	_passed += 1
	print("[PASS] %s" % message)


func _fail(message: String) -> void:
	_failed += 1
	push_error("[FAIL] %s" % message)
	print("[FAIL] %s" % message)


func _finish() -> void:
	print("=== Results: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(_failed)
