class_name WorldMigration001System
extends Migration


func get_version() -> int:
	return 1


func get_migration_name() -> String:
	return "system"


func up(db: Node) -> bool:
	var create_sql := """
	CREATE TABLE IF NOT EXISTS world_meta (
		id INTEGER PRIMARY KEY CHECK (id = 1),
		world_name TEXT NOT NULL,
		database_version INTEGER NOT NULL DEFAULT 1,
		created_at TEXT NOT NULL,
		updated_at TEXT NOT NULL
	);
	"""
	if not db.execute(create_sql):
		return false

	var existing: Array = db.query_rows(
		"SELECT id FROM world_meta WHERE id = 1 LIMIT 1;"
	)
	if not existing.is_empty():
		return true

	var now := Time.get_datetime_string_from_system(true)
	return db.execute_with_bindings(
		"""
		INSERT INTO world_meta (id, world_name, database_version, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?);
		""",
		[1, "Основной мир", 1, now, now]
	)
