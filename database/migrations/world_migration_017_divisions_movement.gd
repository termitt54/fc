class_name WorldMigration017DivisionsMovement
extends Migration
## Promotion / relegation / playoff totals for DIVISIONS type.


func get_version() -> int:
	return 17


func get_migration_name() -> String:
	return "divisions_movement"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if not columns.has("teams_promote"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN teams_promote INTEGER NOT NULL DEFAULT 0;"
		):
			return false
	if not columns.has("teams_relegate"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN teams_relegate INTEGER NOT NULL DEFAULT 0;"
		):
			return false
	if not columns.has("teams_playoff"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN teams_playoff INTEGER NOT NULL DEFAULT 0;"
		):
			return false

	return true
