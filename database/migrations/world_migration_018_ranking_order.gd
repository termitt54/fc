class_name WorldMigration018RankingOrder
extends Migration
## JSON priority list of standing ranking criteria per unit.


func get_version() -> int:
	return 18


func get_migration_name() -> String:
	return "ranking_order"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("ranking_order"):
		return true

	return db.execute("""
		ALTER TABLE competition_units
		ADD COLUMN ranking_order TEXT NOT NULL DEFAULT '["POINTS","GOAL_DIFF","GOALS_FOR","H2H_POINTS","H2H_GOAL_DIFF","H2H_GOALS"]';
	""")
