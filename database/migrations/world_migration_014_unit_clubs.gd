class_name WorldMigration014UnitClubs
extends Migration
## Unit foreigners limit + clubs membership per competition unit.


func get_version() -> int:
	return 14


func get_migration_name() -> String:
	return "unit_clubs"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(competition_units);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if not columns.has("foreign_players_limit"):
		if not db.execute("""
			ALTER TABLE competition_units
			ADD COLUMN foreign_players_limit INTEGER NOT NULL DEFAULT 0;
		"""):
			return false

	var existing: Array = db.query_rows(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'competition_unit_clubs';"
	)
	if existing.is_empty():
		if not db.execute("""
			CREATE TABLE competition_unit_clubs (
				id INTEGER PRIMARY KEY AUTOINCREMENT,
				unit_id INTEGER NOT NULL,
				club_id INTEGER NOT NULL,
				created_at TEXT NOT NULL,

				FOREIGN KEY (unit_id)
					REFERENCES competition_units(id)
					ON UPDATE CASCADE
					ON DELETE CASCADE,

				FOREIGN KEY (club_id)
					REFERENCES clubs(id)
					ON UPDATE CASCADE
					ON DELETE RESTRICT,

				UNIQUE (unit_id, club_id)
			);
		"""):
			return false

		if not db.execute(
			"CREATE INDEX IF NOT EXISTS idx_competition_unit_clubs_unit_id ON competition_unit_clubs(unit_id);"
		):
			return false
		if not db.execute(
			"CREATE INDEX IF NOT EXISTS idx_competition_unit_clubs_club_id ON competition_unit_clubs(club_id);"
		):
			return false

	return true
