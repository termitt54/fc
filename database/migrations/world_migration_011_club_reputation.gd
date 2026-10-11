class_name WorldMigration011ClubReputation
extends Migration
## Clubs: reputation scale 0..1000 (aligned with countries).


func get_version() -> int:
	return 11


func get_migration_name() -> String:
	return "club_reputation"


func up(db: Node) -> bool:
	var sql_rows: Array = db.query_rows(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'clubs';"
	)
	if sql_rows.is_empty():
		return true

	var create_sql: String = str(sql_rows[0].get("sql", ""))
	if create_sql.findn("BETWEEN 0 AND 1000") >= 0:
		return true

	if not db.execute("PRAGMA foreign_keys = OFF;"):
		return false

	if not db.execute("""
		CREATE TABLE clubs_v11 (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			country_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			short_name TEXT,
			code TEXT NOT NULL UNIQUE,
			logo_path TEXT,
			reputation INTEGER NOT NULL DEFAULT 500
				CHECK (reputation BETWEEN 0 AND 1000),
			finance_level INTEGER NOT NULL DEFAULT 10
				CHECK (finance_level BETWEEN 0 AND 20),
			youth_academy INTEGER NOT NULL DEFAULT 10
				CHECK (youth_academy BETWEEN 0 AND 20),
			training_level INTEGER NOT NULL DEFAULT 10
				CHECK (training_level BETWEEN 0 AND 20),
			scouting_level INTEGER NOT NULL DEFAULT 10
				CHECK (scouting_level BETWEEN 0 AND 20),
			youth_search INTEGER NOT NULL DEFAULT 10
				CHECK (youth_search BETWEEN 0 AND 20),
			stadium_capacity INTEGER NOT NULL DEFAULT 10000
				CHECK (stadium_capacity >= 0),
			primary_color TEXT,
			secondary_color TEXT,
			is_active INTEGER NOT NULL DEFAULT 1
				CHECK (is_active IN (0, 1)),
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			FOREIGN KEY (country_id)
				REFERENCES countries(id)
				ON UPDATE CASCADE
				ON DELETE RESTRICT
		);
	"""):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("""
		INSERT INTO clubs_v11 (
			id, country_id, name, short_name, code, logo_path,
			reputation, finance_level, youth_academy, training_level,
			scouting_level, youth_search, stadium_capacity,
			primary_color, secondary_color, is_active, created_at, updated_at
		)
		SELECT
			id, country_id, name, short_name, code, logo_path,
			CASE
				WHEN reputation IS NULL THEN 500
				WHEN reputation < 0 THEN 0
				WHEN reputation <= 100 THEN CAST(reputation * 10 AS INTEGER)
				WHEN reputation > 1000 THEN 1000
				ELSE reputation
			END,
			finance_level, youth_academy, training_level,
			scouting_level, youth_search, stadium_capacity,
			primary_color, secondary_color, is_active, created_at, updated_at
		FROM clubs;
	"""):
		db.execute("DROP TABLE IF EXISTS clubs_v11;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("DROP TABLE clubs;"):
		db.execute("DROP TABLE IF EXISTS clubs_v11;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("ALTER TABLE clubs_v11 RENAME TO clubs;"):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_clubs_country_id ON clubs(country_id);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_clubs_name ON clubs(name);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("PRAGMA foreign_keys = ON;"):
		return false
	return true
