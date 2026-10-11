class_name WorldMigration010ClubsFacilities
extends Migration
## Clubs: facility levels 0..20, scouting + youth search, drop stadium from model defaults.


func get_version() -> int:
	return 10


func get_migration_name() -> String:
	return "clubs_facilities"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(clubs);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("scouting_level") and columns.has("youth_search"):
		return true

	if not db.execute("PRAGMA foreign_keys = OFF;"):
		return false

	if not db.execute("""
		CREATE TABLE clubs_v10 (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			country_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			short_name TEXT,
			code TEXT NOT NULL UNIQUE,
			logo_path TEXT,
			reputation INTEGER NOT NULL DEFAULT 50
				CHECK (reputation BETWEEN 1 AND 100),
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

	if columns.has("id"):
		if not db.execute("""
			INSERT INTO clubs_v10 (
				id, country_id, name, short_name, code, logo_path,
				reputation, finance_level, youth_academy, training_level,
				scouting_level, youth_search, stadium_capacity,
				primary_color, secondary_color, is_active, created_at, updated_at
			)
			SELECT
				id,
				country_id,
				name,
				short_name,
				code,
				logo_path,
				reputation,
				MIN(20, MAX(0,
					CASE
						WHEN finance_level IS NULL THEN 10
						WHEN finance_level <= 20 THEN finance_level
						ELSE CAST(ROUND(finance_level / 5.0) AS INTEGER)
					END
				)),
				MIN(20, MAX(0,
					CASE
						WHEN youth_academy IS NULL THEN 10
						WHEN youth_academy <= 20 THEN youth_academy
						ELSE CAST(ROUND(youth_academy / 5.0) AS INTEGER)
					END
				)),
				MIN(20, MAX(0,
					CASE
						WHEN training_level IS NULL THEN 10
						WHEN training_level <= 20 THEN training_level
						ELSE CAST(ROUND(training_level / 5.0) AS INTEGER)
					END
				)),
				10,
				10,
				COALESCE(stadium_capacity, 10000),
				primary_color,
				secondary_color,
				is_active,
				created_at,
				updated_at
			FROM clubs;
		"""):
			db.execute("DROP TABLE IF EXISTS clubs_v10;")
			db.execute("PRAGMA foreign_keys = ON;")
			return false

	if not db.execute("DROP TABLE clubs;"):
		db.execute("DROP TABLE IF EXISTS clubs_v10;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("ALTER TABLE clubs_v10 RENAME TO clubs;"):
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
