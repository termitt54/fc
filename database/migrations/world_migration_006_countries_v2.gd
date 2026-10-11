class_name WorldMigration006CountriesV2
extends Migration
## Countries: name, abbreviation, flag_path, reputation 0..1000.


func get_version() -> int:
	return 6


func get_migration_name() -> String:
	return "countries_v2"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(countries);")
	var columns: Dictionary = {}
	for row in info:
		columns[str(row.get("name", ""))] = true

	if columns.has("abbreviation") and not columns.has("code"):
		return true

	if not db.execute("PRAGMA foreign_keys = OFF;"):
		return false

	if not db.execute("""
		CREATE TABLE countries_v2 (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			continent_id INTEGER NOT NULL,
			name TEXT NOT NULL,
			abbreviation TEXT NOT NULL UNIQUE,
			flag_path TEXT,
			reputation INTEGER NOT NULL DEFAULT 500
				CHECK (reputation BETWEEN 0 AND 1000),
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,
			FOREIGN KEY (continent_id)
				REFERENCES continents(id)
				ON UPDATE CASCADE
				ON DELETE RESTRICT
		);
	"""):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if columns.has("id"):
		if not db.execute("""
			INSERT INTO countries_v2 (
				id, continent_id, name, abbreviation, flag_path, reputation, created_at, updated_at
			)
			SELECT
				id,
				continent_id,
				name,
				UPPER(TRIM(
					CASE
						WHEN short_name IS NOT NULL AND TRIM(short_name) != '' THEN short_name
						ELSE code
					END
				)),
				flag_path,
				CASE
					WHEN reputation IS NULL THEN 500
					WHEN reputation < 0 THEN 0
					WHEN reputation <= 100 THEN CAST(reputation * 10 AS INTEGER)
					WHEN reputation > 1000 THEN 1000
					ELSE reputation
				END,
				created_at,
				updated_at
			FROM countries;
		"""):
			db.execute("DROP TABLE IF EXISTS countries_v2;")
			db.execute("PRAGMA foreign_keys = ON;")
			return false

	if not db.execute("DROP TABLE countries;"):
		db.execute("DROP TABLE IF EXISTS countries_v2;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("ALTER TABLE countries_v2 RENAME TO countries;"):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_countries_continent_id ON countries(continent_id);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_countries_name ON countries(name);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	db.execute("PRAGMA foreign_keys = ON;")
	return true
