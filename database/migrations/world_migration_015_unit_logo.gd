class_name WorldMigration015UnitLogo
extends Migration
## Logo path for competition units (division / cup / supercup).


func get_version() -> int:
	return 15


func get_migration_name() -> String:
	return "unit_logo"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("logo_path"):
		return true

	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN logo_path TEXT;
	""")
