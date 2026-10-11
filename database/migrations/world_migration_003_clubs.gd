class_name WorldMigration003Clubs
extends Migration


func get_version() -> int:
	return 3


func get_migration_name() -> String:
	return "clubs"


func up(db: Node) -> bool:
	var clubs_sql := """
	CREATE TABLE IF NOT EXISTS clubs (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		country_id INTEGER NOT NULL,
		name TEXT NOT NULL,
		short_name TEXT,
		code TEXT NOT NULL UNIQUE,
		logo_path TEXT,
		reputation INTEGER NOT NULL DEFAULT 50 CHECK (reputation BETWEEN 1 AND 100),
		finance_level INTEGER NOT NULL DEFAULT 50 CHECK (finance_level BETWEEN 1 AND 100),
		youth_academy INTEGER NOT NULL DEFAULT 50 CHECK (youth_academy BETWEEN 1 AND 100),
		training_level INTEGER NOT NULL DEFAULT 50 CHECK (training_level BETWEEN 1 AND 100),
		stadium_capacity INTEGER NOT NULL DEFAULT 10000 CHECK (stadium_capacity >= 0),
		primary_color TEXT,
		secondary_color TEXT,
		is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
		created_at TEXT NOT NULL,
		updated_at TEXT NOT NULL,

		FOREIGN KEY (country_id)
			REFERENCES countries(id)
			ON UPDATE CASCADE
			ON DELETE RESTRICT
	);
	"""
	if not db.execute(clubs_sql):
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_clubs_country_id ON clubs(country_id);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_clubs_name ON clubs(name);"
	):
		return false

	return true
