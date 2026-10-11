class_name WorldMigration023CountryYouthTalent
extends Migration
## Replace per-country youth rating percents with a single youth_talent 0..1000.

const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")


func get_version() -> int:
	return 23


func get_migration_name() -> String:
	return "country_youth_talent"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(countries);")
	var has_youth_talent := false
	for row in info:
		if str(row.get("name", "")) == "youth_talent":
			has_youth_talent = true
			break

	if not has_youth_talent:
		if not db.execute(
			"""
			ALTER TABLE countries
			ADD COLUMN youth_talent INTEGER NOT NULL DEFAULT 500;
			"""
		):
			return false

	if not _migrate_legacy_distribution(db):
		return false

	if not db.execute("DROP TABLE IF EXISTS country_youth_rating_distribution;"):
		return false
	if not db.execute("DROP TABLE IF EXISTS youth_rating_distribution;"):
		return false

	return true


func _migrate_legacy_distribution(db: Node) -> bool:
	var tables: Array = db.query_rows(
		"""
		SELECT name FROM sqlite_master
		WHERE type = 'table' AND name = 'country_youth_rating_distribution';
		"""
	)
	if tables.is_empty():
		return true

	var countries: Array = db.query_rows("SELECT id FROM countries;")
	for country in countries:
		var country_id := int(country.get("id", 0))
		if country_id < 1:
			continue
		var buckets: Array = db.query_rows(
			"""
			SELECT rating_min, rating_max, weight_pct, is_hidden
			FROM country_youth_rating_distribution
			WHERE country_id = ?;
			""",
			[country_id]
		)
		var visible: Array = []
		for bucket in buckets:
			if int(bucket.get("is_hidden", 0)) == 1:
				continue
			visible.append({
				"rating_min": int(bucket.get("rating_min", 0)),
				"rating_max": int(bucket.get("rating_max", 0)),
				"weight_pct": float(bucket.get("weight_pct", 0.0)),
			})
		var talent: int = YouthGenerationConfigScript.talent_from_legacy_buckets(visible)
		if not db.execute_with_bindings(
			"UPDATE countries SET youth_talent = ? WHERE id = ?;",
			[talent, country_id]
		):
			return false

	return true
