extends Migration

func get_version() -> int:
	return 31

func get_migration_name() -> String:
	return "cup_formats"

func up(db: Node) -> bool:
	return db.execute("""
		CREATE TABLE IF NOT EXISTS cup_formats (
			unit_id INTEGER PRIMARY KEY REFERENCES competition_units(id) ON DELETE CASCADE,
			config_json TEXT NOT NULL
		);
	""")
