class_name WorldMigration021PlayoffRules
extends Migration
## Playoff format, series length, third place and seeding for units.


func get_version() -> int:
	return 21


func get_migration_name() -> String:
	return "playoff_rules"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if not columns.has("playoff_format"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN playoff_format TEXT NOT NULL DEFAULT 'BEST_OF';
		"""):
			return false

	if not columns.has("playoff_series_wins"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN playoff_series_wins INTEGER NOT NULL DEFAULT 3;
		"""):
			return false

	if not columns.has("playoff_third_place"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN playoff_third_place INTEGER NOT NULL DEFAULT 0;
		"""):
			return false

	if not columns.has("playoff_seeding"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN playoff_seeding TEXT NOT NULL DEFAULT 'OVERALL_TABLE';
		"""):
			return false

	return true
