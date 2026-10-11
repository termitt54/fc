class_name WorldMigration002Geography
extends Migration


func get_version() -> int:
	return 2


func get_migration_name() -> String:
	return "geography"


func up(db: Node) -> bool:
	var continents_sql := """
	CREATE TABLE IF NOT EXISTS continents (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		short_name TEXT,
		code TEXT NOT NULL UNIQUE,
		logo_path TEXT,
		sort_order INTEGER NOT NULL DEFAULT 0,
		is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
		created_at TEXT NOT NULL,
		updated_at TEXT NOT NULL
	);
	"""
	if not db.execute(continents_sql):
		return false

	var countries_sql := """
	CREATE TABLE IF NOT EXISTS countries (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		continent_id INTEGER NOT NULL,
		name TEXT NOT NULL,
		short_name TEXT,
		code TEXT NOT NULL UNIQUE,
		flag_path TEXT,
		reputation INTEGER NOT NULL DEFAULT 50 CHECK (reputation BETWEEN 1 AND 100),
		football_level INTEGER NOT NULL DEFAULT 50 CHECK (football_level BETWEEN 1 AND 100),
		youth_generation_min INTEGER NOT NULL DEFAULT 30 CHECK (youth_generation_min BETWEEN 1 AND 100),
		youth_generation_max INTEGER NOT NULL DEFAULT 70 CHECK (youth_generation_max BETWEEN 1 AND 100),
		talent_probability REAL NOT NULL DEFAULT 0.05 CHECK (talent_probability BETWEEN 0.0 AND 1.0),
		is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
		created_at TEXT NOT NULL,
		updated_at TEXT NOT NULL,

		FOREIGN KEY (continent_id)
			REFERENCES continents(id)
			ON UPDATE CASCADE
			ON DELETE RESTRICT,

		CHECK (youth_generation_min <= youth_generation_max)
	);
	"""
	if not db.execute(countries_sql):
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_countries_continent_id ON countries(continent_id);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_continents_name ON continents(name);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_countries_name ON countries(name);"
	):
		return false

	return true
