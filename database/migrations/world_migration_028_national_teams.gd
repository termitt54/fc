extends Migration

func get_version() -> int:
	return 28

func get_migration_name() -> String:
	return "national_team_participants"

func up(db: Node) -> bool:
	return db.execute("""
		CREATE TABLE IF NOT EXISTS competition_unit_countries (
			unit_id INTEGER NOT NULL REFERENCES competition_units(id) ON DELETE CASCADE,
			country_id INTEGER NOT NULL REFERENCES countries(id) ON DELETE CASCADE,
			PRIMARY KEY (unit_id, country_id)
		);
	""")
