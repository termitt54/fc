class_name WorldMigration009YouthWeightDecimals
extends Migration
## Allow youth distribution weights with hundredths (REAL).


func get_version() -> int:
	return 9


func get_migration_name() -> String:
	return "youth_weight_decimals"


func up(db: Node) -> bool:
	if not db.execute("""
		CREATE TABLE IF NOT EXISTS country_youth_rating_distribution_v9 (
			country_id INTEGER NOT NULL,
			bucket_key TEXT NOT NULL,
			rating_min INTEGER NOT NULL,
			rating_max INTEGER NOT NULL,
			weight_pct REAL NOT NULL
				CHECK (weight_pct >= 0 AND weight_pct <= 100),
			is_hidden INTEGER NOT NULL DEFAULT 0
				CHECK (is_hidden IN (0, 1)),
			sort_order INTEGER NOT NULL,
			updated_at TEXT NOT NULL,
			PRIMARY KEY (country_id, bucket_key),
			FOREIGN KEY (country_id) REFERENCES countries(id) ON DELETE CASCADE
		);
	"""):
		return false

	if not db.execute("""
		INSERT INTO country_youth_rating_distribution_v9 (
			country_id, bucket_key, rating_min, rating_max,
			weight_pct, is_hidden, sort_order, updated_at
		)
		SELECT
			country_id, bucket_key, rating_min, rating_max,
			CAST(weight_pct AS REAL), is_hidden, sort_order, updated_at
		FROM country_youth_rating_distribution;
	"""):
		return false

	if not db.execute("DROP TABLE country_youth_rating_distribution;"):
		return false

	if not db.execute("""
		ALTER TABLE country_youth_rating_distribution_v9
		RENAME TO country_youth_rating_distribution;
	"""):
		return false

	return true
