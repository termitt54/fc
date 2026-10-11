class_name WorldMigration005SeedContinents
extends Migration
## Default world continents used by football geography.


func get_version() -> int:
	return 5


func get_migration_name() -> String:
	return "seed_continents"


func up(db: Node) -> bool:
	var now := Time.get_datetime_string_from_system(true)
	var continents: Array = [
		{"name": "Europe", "short_name": "EUR", "code": "EUROPE", "sort_order": 10},
		{"name": "South America", "short_name": "SAM", "code": "SOUTH_AMERICA", "sort_order": 20},
		{"name": "North America", "short_name": "NAM", "code": "NORTH_AMERICA", "sort_order": 30},
		{"name": "Africa", "short_name": "AFR", "code": "AFRICA", "sort_order": 40},
		{"name": "Asia", "short_name": "ASI", "code": "ASIA", "sort_order": 50},
		{"name": "Oceania", "short_name": "OCE", "code": "OCEANIA", "sort_order": 60},
	]

	for item in continents:
		var existing: Array = db.query_rows(
			"SELECT id FROM continents WHERE code = ? LIMIT 1;",
			[str(item["code"])]
		)
		if not existing.is_empty():
			continue

		if not db.execute_with_bindings(
			"""
			INSERT INTO continents (
				name, short_name, code, logo_path, sort_order, is_active, created_at, updated_at
			) VALUES (?, ?, ?, NULL, ?, 1, ?, ?);
			""",
			[
				str(item["name"]),
				str(item["short_name"]),
				str(item["code"]),
				int(item["sort_order"]),
				now,
				now,
			]
		):
			return false

	return true
