extends Migration
## youth_talent 0..1000 becomes 0..100. 500 → 50, 781 → 78, 1000 → 100.


func get_version() -> int:
	return 26


func get_migration_name() -> String:
	return "youth_talent_scale"


func up(db: Node) -> bool:
	var info: Array = db.query_rows("PRAGMA table_info(countries);")
	var has_youth_talent := false
	for row in info:
		if str(row.get("name", "")) == "youth_talent":
			has_youth_talent = true
			break
	if not has_youth_talent:
		return true

	return db.execute(
		"""
		UPDATE countries
		SET youth_talent = MIN(100, MAX(0, (youth_talent + 5) / 10))
		WHERE youth_talent > 100;
		"""
	)
