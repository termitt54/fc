class_name WorldMigration016DivisionsRules
extends Migration
## Rule fields for competition type DIVISIONS.


func get_version() -> int:
	return 16


func get_migration_name() -> String:
	return "divisions_rules"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if not columns.has("divisions_count"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN divisions_count INTEGER NOT NULL DEFAULT 2;"
		):
			return false
	if not columns.has("teams_per_division"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN teams_per_division INTEGER NOT NULL DEFAULT 4;"
		):
			return false
	if not columns.has("matches_vs_own"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN matches_vs_own INTEGER NOT NULL DEFAULT 2;"
		):
			return false
	if not columns.has("matches_vs_other"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN matches_vs_other INTEGER NOT NULL DEFAULT 0;"
		):
			return false
	if not columns.has("points_win"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN points_win INTEGER NOT NULL DEFAULT 3;"
		):
			return false
	if not columns.has("points_draw"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN points_draw INTEGER NOT NULL DEFAULT 1;"
		):
			return false
	if not columns.has("points_loss"):
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN points_loss INTEGER NOT NULL DEFAULT 0;"
		):
			return false

	return true
