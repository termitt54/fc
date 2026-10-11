class_name WorldMigration020MovementScope
extends Migration
## Overall-table vs per-division scope for movement and playoff quotas.


func get_version() -> int:
	return 20


func get_migration_name() -> String:
	return "movement_scope"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if not columns.has("movement_scope"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN movement_scope TEXT NOT NULL DEFAULT 'PER_DIVISION';
		"""):
			return false

	if not columns.has("playoff_scope"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN playoff_scope TEXT NOT NULL DEFAULT 'PER_DIVISION';
		"""):
			return false

	return true
