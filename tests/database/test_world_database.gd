extends Node
## Headless verification for world.db foundation.
##
## This suite has to start from no database at all, so it wipes one. It must
## therefore never point at the real world: countries, clubs and competitions
## live there and there is no backup. It runs against a scratch copy instead,
## and refuses to wipe anything else.
## Run: godot --headless --path . res://tests/database/test_world_database.tscn

const SCRATCH_DIR := "user://tests/world_db_scratch"
const SCRATCH_PATH := "user://tests/world_db_scratch/world.db"

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== World database tests ===")

	if not ClassDB.class_exists("SQLite"):
		_fail("SQLite class is not available (godot-sqlite plugin missing or not loaded)")
		_finish()
		return

	_redirect_to_scratch()
	if not _wipe_scratch_database():
		_finish()
		return
	if not WorldDatabase.initialize():
		_fail("First initialize() failed: %s" % WorldDatabase.get_last_error())
		_restore_real_database()
		_finish()
		return
	_pass("WorldDatabase ready after first initialization")

	_assert_schema()
	_assert_second_run_is_idempotent()
	_assert_foreign_keys_and_cleanup()
	_assert_constraints()

	_restore_real_database()
	_finish()


func _redirect_to_scratch() -> void:
	WorldDatabase.close()
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	WorldDatabase.db_dir = SCRATCH_DIR
	WorldDatabase.db_path = SCRATCH_PATH


## Hands the autoload back to the real world so nothing later in the run,
## and no editor session, keeps writing into the scratch copy.
func _restore_real_database() -> void:
	WorldDatabase.close()
	WorldDatabase.db_dir = WorldDatabase.WORLD_DB_DIR
	WorldDatabase.db_path = WorldDatabase.WORLD_DB_PATH
	WorldDatabase.initialize()


func _wipe_scratch_database() -> bool:
	var dir_path := WorldDatabase.db_dir
	# The guard that matters: a wipe may only ever touch the scratch directory.
	if dir_path != SCRATCH_DIR:
		_fail("refusing to wipe '%s' — only %s may be erased" % [dir_path, SCRATCH_DIR])
		return false

	if not DirAccess.dir_exists_absolute(dir_path):
		return true

	var dir := DirAccess.open(dir_path)
	if dir == null:
		return true

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name != "." and file_name != "..":
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(dir_path)
	return true


func _assert_schema() -> void:
	var abs_path := ProjectSettings.globalize_path(WorldDatabase.get_database_path())
	if not FileAccess.file_exists(WorldDatabase.get_database_path()):
		_fail("world.db file was not created at %s" % abs_path)
	else:
		_pass("world.db exists at %s" % abs_path)

	var required_tables := [
		"schema_migrations",
		"world_meta",
		"continents",
		"countries",
		"clubs",
		"competitions",
		"competition_rules",
		"competition_clubs",
	]
	for table_name in required_tables:
		var rows: Array = DatabaseManager.query_rows(
			"SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
			[table_name]
		)
		if rows.is_empty():
			_fail("Missing table: %s" % table_name)
		else:
			_pass("Table exists: %s" % table_name)

	var migrations: Array = DatabaseManager.query_rows(
		"SELECT version, name FROM schema_migrations ORDER BY version ASC;"
	)
	# Versions must be a gapless 1..N run, so the count never needs a hardcoded number.
	var gap := 0
	for i in migrations.size():
		if int((migrations[i] as Dictionary).get("version", 0)) != i + 1:
			gap = i + 1
			break
	if migrations.is_empty():
		_fail("schema_migrations is empty")
	elif gap > 0:
		_fail("schema_migrations has a gap at version %d" % gap)
	else:
		_pass("schema_migrations has %d gapless rows" % migrations.size())

	var meta: Array = DatabaseManager.query_rows("SELECT COUNT(*) AS c FROM world_meta;")
	if meta.is_empty() or int(meta[0]["c"]) != 1:
		_fail("Expected exactly 1 world_meta row")
	else:
		_pass("world_meta has exactly 1 row")


func _assert_second_run_is_idempotent() -> void:
	var migrations_before: Array = DatabaseManager.query_rows(
		"SELECT version, name, applied_at FROM schema_migrations ORDER BY version ASC;"
	)
	var meta_before: Array = DatabaseManager.query_rows("SELECT * FROM world_meta WHERE id = 1;")

	if not WorldDatabase.initialize():
		_fail("Second initialize() failed: %s" % WorldDatabase.get_last_error())
		return

	var migrations_after: Array = DatabaseManager.query_rows(
		"SELECT version, name, applied_at FROM schema_migrations ORDER BY version ASC;"
	)
	var meta_after: Array = DatabaseManager.query_rows("SELECT * FROM world_meta WHERE id = 1;")
	var meta_count: Array = DatabaseManager.query_rows("SELECT COUNT(*) AS c FROM world_meta;")

	if migrations_after.size() != migrations_before.size():
		_fail("Migration count changed on second run")
	elif str(migrations_after) != str(migrations_before):
		_fail("schema_migrations content changed on second run")
	else:
		_pass("Second run did not re-apply migrations")

	if meta_count.is_empty() or int(meta_count[0]["c"]) != 1:
		_fail("world_meta row count changed on second run")
	elif str(meta_after) != str(meta_before):
		_fail("world_meta content changed on second run")
	else:
		_pass("Second run preserved world_meta")


func _assert_foreign_keys_and_cleanup() -> void:
	var now := Time.get_datetime_string_from_system(true)

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO continents (name, short_name, code, sort_order, is_active, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?);
		""",
		["Test Continent", "TC", "TST_CONT", 0, 1, now, now]
	):
		_fail("Failed to insert test continent: %s" % DatabaseManager.get_last_error())
		return

	var continent_rows: Array = DatabaseManager.query_rows(
		"SELECT id FROM continents WHERE code = ?;",
		["TST_CONT"]
	)
	var continent_id: int = int(continent_rows[0]["id"])

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, reputation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?);
		""",
		[continent_id, "Test Country", "TST", 500, now, now]
	):
		_fail("Failed to insert test country: %s" % DatabaseManager.get_last_error())
		_cleanup_test_rows()
		return

	var delete_ok: bool = DatabaseManager.execute_with_bindings(
		"DELETE FROM continents WHERE id = ?;",
		[continent_id]
	)
	if delete_ok:
		_fail("Deleting continent with related country was incorrectly allowed")
	else:
		_pass("ON DELETE RESTRICT blocked continent deletion")

	_cleanup_test_rows()
	_pass("Foreign key test data cleaned up")


func _assert_constraints() -> void:
	var now := Time.get_datetime_string_from_system(true)

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO continents (name, code, created_at, updated_at)
		VALUES (?, ?, ?, ?);
		""",
		["Constraint Continent", "CST_CONT", now, now]
	):
		_fail("Failed to insert constraint-test continent: %s" % DatabaseManager.get_last_error())
		return

	var continent_rows: Array = DatabaseManager.query_rows(
		"SELECT id FROM continents WHERE code = ?;",
		["CST_CONT"]
	)
	var continent_id: int = int(continent_rows[0]["id"])

	_expect_fail(
		"reputation > 1000 rejected",
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, reputation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?);
		""",
		[continent_id, "Bad Rep High", "BADHI", 1001, now, now]
	)

	_expect_fail(
		"reputation < 0 rejected",
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, reputation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?);
		""",
		[continent_id, "Bad Rep Low", "BADLO", -1, now, now]
	)

	_expect_fail(
		"duplicate continent code rejected",
		"""
		INSERT INTO continents (name, code, created_at, updated_at)
		VALUES (?, ?, ?, ?);
		""",
		["Duplicate Code", "CST_CONT", now, now]
	)

	_expect_fail(
		"country with missing continent_id rejected",
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?);
		""",
		[999999, "Orphan Country", "ORPH", now, now]
	)

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?);
		""",
		[continent_id, "Constraint Country", "CST", now, now]
	):
		_fail("Failed to insert constraint-test country: %s" % DatabaseManager.get_last_error())
		_cleanup_constraint_rows()
		return

	var country_rows: Array = DatabaseManager.query_rows(
		"SELECT id FROM countries WHERE abbreviation = ?;",
		["CST"]
	)
	var country_id: int = int(country_rows[0]["id"])

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO clubs (country_id, name, code, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?);
		""",
		[country_id, "Constraint Club", "CST_CLUB", now, now]
	):
		_fail("Failed to insert constraint-test club: %s" % DatabaseManager.get_last_error())
		_cleanup_constraint_rows()
		return

	var club_rows: Array = DatabaseManager.query_rows(
		"SELECT id FROM clubs WHERE code = ?;",
		["CST_CLUB"]
	)
	var club_id: int = int(club_rows[0]["id"])

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO competitions (
			name, code, competition_type, scope_type, country_id, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?);
		""",
		["Constraint League", "CST_CUP", "LEAGUE", "DOMESTIC", country_id, now, now]
	):
		_fail("Failed to insert constraint-test competition: %s" % DatabaseManager.get_last_error())
		_cleanup_constraint_rows()
		return

	var competition_rows: Array = DatabaseManager.query_rows(
		"SELECT id FROM competitions WHERE code = ?;",
		["CST_CUP"]
	)
	var competition_id: int = int(competition_rows[0]["id"])

	if not DatabaseManager.execute_with_bindings(
		"""
		INSERT INTO competition_clubs (competition_id, club_id, is_active)
		VALUES (?, ?, 1);
		""",
		[competition_id, club_id]
	):
		_fail("Failed to insert first competition_clubs row: %s" % DatabaseManager.get_last_error())
		_cleanup_constraint_rows()
		return

	_expect_fail(
		"duplicate competition_clubs membership rejected",
		"""
		INSERT INTO competition_clubs (competition_id, club_id, is_active)
		VALUES (?, ?, 1);
		""",
		[competition_id, club_id]
	)

	_cleanup_constraint_rows()
	_pass("Constraint test data cleaned up")


func _expect_fail(label: String, sql: String, params: Array) -> void:
	var ok: bool = DatabaseManager.execute_with_bindings(sql, params)
	if ok:
		_fail("%s — query unexpectedly succeeded" % label)
	else:
		_pass(label)


func _cleanup_test_rows() -> void:
	DatabaseManager.execute_with_bindings(
		"DELETE FROM countries WHERE abbreviation = ?;",
		["TST"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM continents WHERE code = ?;",
		["TST_CONT"]
	)


func _cleanup_constraint_rows() -> void:
	DatabaseManager.execute_with_bindings(
		"DELETE FROM competition_clubs WHERE competition_id IN (SELECT id FROM competitions WHERE code = ?);",
		["CST_CUP"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM competition_rules WHERE competition_id IN (SELECT id FROM competitions WHERE code = ?);",
		["CST_CUP"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM competitions WHERE code = ?;",
		["CST_CUP"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM clubs WHERE code = ?;",
		["CST_CLUB"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM countries WHERE abbreviation = ?;",
		["CST"]
	)
	DatabaseManager.execute_with_bindings(
		"DELETE FROM continents WHERE code = ?;",
		["CST_CONT"]
	)


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
