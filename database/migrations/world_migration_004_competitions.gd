class_name WorldMigration004Competitions
extends Migration


func get_version() -> int:
	return 4


func get_migration_name() -> String:
	return "competitions"


func up(db: Node) -> bool:
	var competitions_sql := """
	CREATE TABLE IF NOT EXISTS competitions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		name TEXT NOT NULL,
		short_name TEXT,
		code TEXT NOT NULL UNIQUE,
		competition_type TEXT NOT NULL DEFAULT 'LEAGUE',
		scope_type TEXT NOT NULL DEFAULT 'DOMESTIC',
		continent_id INTEGER,
		country_id INTEGER,
		level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
		reputation INTEGER NOT NULL DEFAULT 50 CHECK (reputation BETWEEN 1 AND 100),
		is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
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
				'GROUP_AND_PLAYOFF',
				'KNOCKOUT'
			)
		),

		CHECK (
			scope_type IN (
				'DOMESTIC',
				'CONTINENTAL',
				'INTERNATIONAL',
				'CUSTOM'
			)
		)
	);
	"""
	if not db.execute(competitions_sql):
		return false

	var rules_sql := """
	CREATE TABLE IF NOT EXISTS competition_rules (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		competition_id INTEGER NOT NULL UNIQUE,
		teams_count INTEGER NOT NULL DEFAULT 2 CHECK (teams_count >= 2),
		rounds_between_teams INTEGER NOT NULL DEFAULT 2 CHECK (rounds_between_teams >= 1),
		points_for_win INTEGER NOT NULL DEFAULT 3,
		points_for_draw INTEGER NOT NULL DEFAULT 1,
		points_for_loss INTEGER NOT NULL DEFAULT 0,
		promotion_places INTEGER NOT NULL DEFAULT 0 CHECK (promotion_places >= 0),
		relegation_places INTEGER NOT NULL DEFAULT 0 CHECK (relegation_places >= 0),
		has_playoffs INTEGER NOT NULL DEFAULT 0 CHECK (has_playoffs IN (0, 1)),
		has_regular_season_champion INTEGER NOT NULL DEFAULT 1
			CHECK (has_regular_season_champion IN (0, 1)),
		start_day INTEGER NOT NULL DEFAULT 1,
		match_interval_days INTEGER NOT NULL DEFAULT 7 CHECK (match_interval_days >= 1),

		FOREIGN KEY (competition_id)
			REFERENCES competitions(id)
			ON UPDATE CASCADE
			ON DELETE RESTRICT
	);
	"""
	if not db.execute(rules_sql):
		return false

	var competition_clubs_sql := """
	CREATE TABLE IF NOT EXISTS competition_clubs (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		competition_id INTEGER NOT NULL,
		club_id INTEGER NOT NULL,
		group_number INTEGER,
		seed_number INTEGER,
		is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),

		FOREIGN KEY (competition_id)
			REFERENCES competitions(id)
			ON UPDATE CASCADE
			ON DELETE RESTRICT,

		FOREIGN KEY (club_id)
			REFERENCES clubs(id)
			ON UPDATE CASCADE
			ON DELETE RESTRICT,

		UNIQUE (competition_id, club_id)
	);
	"""
	if not db.execute(competition_clubs_sql):
		return false

	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competitions_country_id ON competitions(country_id);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competitions_continent_id ON competitions(continent_id);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competition_clubs_competition_id ON competition_clubs(competition_id);"
	):
		return false
	if not db.execute(
		"CREATE INDEX IF NOT EXISTS idx_competition_clubs_club_id ON competition_clubs(club_id);"
	):
		return false

	return true
