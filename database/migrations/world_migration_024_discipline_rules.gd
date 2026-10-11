class_name WorldMigration024DisciplineRules
extends Migration
## Per-unit discipline settings: cards, referee strictness, bans and yellow reset.


func get_version() -> int:
	return 24


func get_migration_name() -> String:
	return "discipline_rules"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	var additions := {
		"discipline_enabled": "INTEGER NOT NULL DEFAULT 1",
		"card_strictness": "INTEGER NOT NULL DEFAULT 100",
		"yellow_ban_threshold": "INTEGER NOT NULL DEFAULT 5",
		"yellow_ban_matches": "INTEGER NOT NULL DEFAULT 1",
		"red_ban_matches": "INTEGER NOT NULL DEFAULT 2",
		"double_yellow_red": "INTEGER NOT NULL DEFAULT 1",
		"yellow_reset": "TEXT NOT NULL DEFAULT 'SEASON'",
	}

	for column in additions.keys():
		if columns.has(column):
			continue
		if not db.execute(
			"ALTER TABLE competition_units ADD COLUMN %s %s;" % [column, str(additions[column])]
		):
			return false

	return true
