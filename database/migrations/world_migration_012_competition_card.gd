class_name WorldMigration012CompetitionCard
extends Migration
## Competition card: periodicity, start season, age group, expanded type/format.


func get_version() -> int:
	return 12


func get_migration_name() -> String:
	return "competition_card"


func up(db: Node) -> bool:
	var sql_rows: Array = db.query_rows(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'competitions';"
	)
	if sql_rows.is_empty():
		return true

	var create_sql: String = str(sql_rows[0].get("sql", ""))
	if create_sql.findn("periodicity") >= 0 and create_sql.findn("SUPER_CUP") >= 0:
		return true

	if not db.execute("PRAGMA foreign_keys = OFF;"):
		return false

	if not db.execute("""
		CREATE TABLE competitions_v12 (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			name TEXT NOT NULL,
			short_name TEXT,
			code TEXT NOT NULL UNIQUE,
			competition_type TEXT NOT NULL DEFAULT 'LEAGUE',
			scope_type TEXT NOT NULL DEFAULT 'DOMESTIC',
			continent_id INTEGER,
			country_id INTEGER,
			periodicity TEXT NOT NULL DEFAULT 'ANNUAL',
			start_season INTEGER NOT NULL DEFAULT 1,
			age_group TEXT,
			level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
			reputation INTEGER NOT NULL DEFAULT 50
				CHECK (reputation BETWEEN 1 AND 100),
			is_active INTEGER NOT NULL DEFAULT 1
				CHECK (is_active IN (0, 1)),
			created_at TEXT NOT NULL,
			updated_at TEXT NOT NULL,

			FOREIGN KEY (continent_id)
				REFERENCES continents(id)
				ON UPDATE CASCADE
				ON DELETE RESTRICT,

			FOREIGN KEY (country_id)
				REFERENCES countries(id)
				ON UPDATE CASCADE
				ON DELETE RESTRICT,

			CHECK (
				competition_type IN (
					'LEAGUE',
					'CUP',
					'SUPER_CUP',
					'GROUP_AND_PLAYOFF',
					'KNOCKOUT',
					'DIVISIONS'
				)
			),

			CHECK (
				scope_type IN (
					'DOMESTIC',
					'CONTINENTAL',
					'INTERNATIONAL',
					'INTERCONTINENTAL_CLUB'
				)
			),

			CHECK (
				periodicity IN (
					'ANNUAL',
					'BIENNIAL',
					'QUADRENNIAL',
					'ONCE'
				)
			),

			CHECK (
				age_group IS NULL OR age_group IN (
					'SENIOR',
					'U21',
					'U18'
				)
			)
		);
	"""):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("""
		INSERT INTO competitions_v12 (
			id, name, short_name, code, competition_type, scope_type,
			continent_id, country_id, periodicity, start_season, age_group,
			level, reputation, is_active, created_at, updated_at
		)
		SELECT
			id,
			name,
			short_name,
			code,
			competition_type,
			CASE
				WHEN scope_type = 'CUSTOM' THEN 'INTERCONTINENTAL_CLUB'
				ELSE scope_type
			END,
			continent_id,
			country_id,
			'ANNUAL',
			1,
			CASE
				WHEN scope_type = 'INTERNATIONAL' THEN 'SENIOR'
				ELSE NULL
			END,
			level,
			reputation,
			is_active,
			created_at,
			updated_at
		FROM competitions;
	"""):
		db.execute("DROP TABLE IF EXISTS competitions_v12;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("DROP TABLE competitions;"):
		db.execute("DROP TABLE IF EXISTS competitions_v12;")
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("ALTER TABLE competitions_v12 RENAME TO competitions;"):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competitions_country_id ON competitions(country_id);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competitions_continent_id ON competitions(continent_id);"
	):
		db.execute("PRAGMA foreign_keys = ON;")
		return false

	if not db.execute("PRAGMA foreign_keys = ON;"):
		return false
	return true
