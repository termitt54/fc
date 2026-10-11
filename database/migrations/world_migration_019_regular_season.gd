class_name WorldMigration019RegularSeason
extends Migration
## Toggle for unified regular-season table / champion.


func get_version() -> int:
	return 19


func get_migration_name() -> String:
	return "regular_season"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("regular_season_enabled"):
		return true

	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN regular_season_enabled INTEGER NOT NULL DEFAULT 0;
	""")
