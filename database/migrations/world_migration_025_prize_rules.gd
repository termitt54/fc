class_name WorldMigration025PrizeRules
extends Migration
## JSON prize table per competition unit (regular places + playoff finishes).


func get_version() -> int:
	return 25


func get_migration_name() -> String:
	return "prize_rules"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("prize_rules"):
		return true

	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN prize_rules TEXT NOT NULL DEFAULT '{}';
	""")
