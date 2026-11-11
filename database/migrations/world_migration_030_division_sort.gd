extends Migration
## How a division unit deals its clubs into parallel divisions each season.


func get_version() -> int:
	return 30


func get_migration_name() -> String:
	return "division_sort"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true
	if columns.has("division_sort"):
		return true
	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN division_sort TEXT NOT NULL DEFAULT 'RANDOM';
	""")
