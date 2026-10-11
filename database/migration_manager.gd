class_name MigrationManager
extends RefCounted

const SCHEMA_MIGRATIONS_SQL := """
CREATE TABLE IF NOT EXISTS schema_migrations (
	version INTEGER PRIMARY KEY,
	name TEXT NOT NULL,
	applied_at TEXT NOT NULL
);
"""


func migrate(db: Node, migrations: Array) -> bool:
	if db == null or not db.is_open():
		push_error("[MigrationManager] Database connection is not open")
		return false

	if not db.execute(SCHEMA_MIGRATIONS_SQL):
		push_error("[MigrationManager] Failed to ensure schema_migrations table")
		push_error("SQLite error: %s" % db.get_last_error())
		return false

	var ordered := migrations.duplicate()
	ordered.sort_custom(func(a: Migration, b: Migration) -> bool:
		return a.get_version() < b.get_version()
	)

	var applied_any := false
	for migration in ordered:
		if migration == null:
			push_error("[MigrationManager] Encountered null migration entry")
			return false

		var version: int = migration.get_version()
		var migration_name: String = migration.get_migration_name()

		if _is_applied(db, version):
			continue

		if not db.begin_transaction():
			push_error("[MigrationManager] Failed to begin transaction for migration %d: %s" % [version, migration_name])
			push_error("SQLite error: %s" % db.get_last_error())
			return false

		if not migration.up(db):
			db.rollback_transaction()
			push_error("[MigrationManager] Failed migration %d: %s" % [version, migration_name])
			push_error("SQLite error: %s" % db.get_last_error())
			push_error("Transaction rolled back")
			return false

		var applied_at := Time.get_datetime_string_from_system(true)
		if not db.execute_with_bindings(
			"INSERT INTO schema_migrations (version, name, applied_at) VALUES (?, ?, ?);",
			[version, migration_name, applied_at]
		):
			db.rollback_transaction()
			push_error("[MigrationManager] Failed migration %d: %s" % [version, migration_name])
			push_error("SQLite error: %s" % db.get_last_error())
			push_error("Transaction rolled back")
			return false

		if not db.commit_transaction():
			db.rollback_transaction()
			push_error("[MigrationManager] Failed to commit migration %d: %s" % [version, migration_name])
			push_error("SQLite error: %s" % db.get_last_error())
			push_error("Transaction rolled back")
			return false

		applied_any = true
		print("[MigrationManager] Applied migration %d: %s" % [version, migration_name])

	if not applied_any:
		print("[MigrationManager] Database schema is up to date")

	return true


func _is_applied(db: Node, version: int) -> bool:
	var rows: Array = db.query_rows(
		"SELECT version FROM schema_migrations WHERE version = ? LIMIT 1;",
		[version]
	)
	return not rows.is_empty()
