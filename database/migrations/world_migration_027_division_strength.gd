extends Migration
## Strength of each division on the 0..1000 reputation scale.


func get_version() -> int:
	return 27


func get_migration_name() -> String:
	return "division_strength"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("division_strength"):
		return true

	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN division_strength TEXT NOT NULL DEFAULT '[]';
	""")
