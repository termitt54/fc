class_name WorldMigration013CompetitionUnits
extends Migration
## Tournament composition units: division / cup / supercup with per-unit type.


func get_version() -> int:
	return 13


func get_migration_name() -> String:
	return "competition_units"


func up(db: Node) -> bool:
	var existing: Array = db.query_rows(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'competition_units';"
	)
	if not existing.is_empty():
		return true

	if not db.execute("""
		CREATE TABLE competition_units (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			competition_id INTEGER NOT NULL,
			unit_kind TEXT NOT NULL,
			name TEXT NOT NULL,
			level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
			competition_type TEXT NOT NULL DEFAULT 'LEAGUE',
			sort_order INTEGER NOT NULL DEFAULT 0,
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,

			FOREIGN KEY (competition_id)
				REFERENCES competitions(id)
				ON UPDATE CASCADE
				ON DELETE CASCADE,

			CHECK (
				unit_kind IN (
					'DIVISION',
					'CUP',
					'SUPER_CUP'
				)
			),

			CHECK (
				competition_type IN (
					'LEAGUE',
					'CUP',
					'SUPER_CUP',
					'GROUP_AND_PLAYOFF',
					'KNOCKOUT',
					'DIVISIONS'
				)
			)
		);
	"""):
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competition_units_competition_id ON competition_units(competition_id);"
	):
		return false

	return true
