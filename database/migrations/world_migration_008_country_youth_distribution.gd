class_name WorldMigration008CountryYouthDistribution
extends Migration
## Per-country youth rating distribution (replaces global table from 007).


const DEFAULTS := [
	["r90_100", 90, 100, 1, 0, 10],
	["r85_89", 85, 89, 3, 0, 20],
	["r80_84", 80, 84, 7, 0, 30],
	["r70_79", 70, 79, 18, 0, 40],
	["r60_69", 60, 69, 28, 0, 50],
	["r50_59", 50, 59, 27, 0, 60],
	["r40_49", 40, 49, 16, 0, 70],
	["r0_39", 0, 39, 0, 1, 80],
]


func get_version() -> int:
	return 8


func get_migration_name() -> String:
	return "country_youth_distribution"


func up(db: Node) -> bool:
	var create_sql := """
	CREATE TABLE IF NOT EXISTS country_youth_rating_distribution (
		country_id INTEGER NOT NULL,
		bucket_key TEXT NOT NULL,
		rating_min INTEGER NOT NULL,
		rating_max INTEGER NOT NULL,
		weight_pct INTEGER NOT NULL
			CHECK (weight_pct >= 0 AND weight_pct <= 100),
		is_hidden INTEGER NOT NULL DEFAULT 0
			CHECK (is_hidden IN (0, 1)),
		sort_order INTEGER NOT NULL,
		updated_at TEXT NOT NULL,
		PRIMARY KEY (country_id, bucket_key),
		FOREIGN KEY (country_id) REFERENCES countries(id) ON DELETE CASCADE
	);
	"""
	if not db.execute(create_sql):
		return false

	var now := Time.get_datetime_string_from_system(true)
	var countries: Array = db.query_rows("SELECT id FROM countries;")
	for country in countries:
		var country_id := int(country.get("id", 0))
		if country_id < 1:
			continue
		var existing: Array = db.query_rows(
			"""
			SELECT COUNT(*) AS cnt
			FROM country_youth_rating_distribution
			WHERE country_id = ?;
			""",
			[country_id]
		)
		if not existing.is_empty() and int(existing[0].get("cnt", 0)) > 0:
			continue
		for seed in DEFAULTS:
			if not db.execute_with_bindings(
				"""
				INSERT INTO country_youth_rating_distribution (
					country_id, bucket_key, rating_min, rating_max,
					weight_pct, is_hidden, sort_order, updated_at
				) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
				""",
				[country_id, seed[0], seed[1], seed[2], seed[3], seed[4], seed[5], now]
			):
				return false

	# Drop legacy global table from migration 007 if present.
	if not db.execute("DROP TABLE IF EXISTS youth_rating_distribution;"):
		return false

	return true
