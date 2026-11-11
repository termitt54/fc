extends Migration

func get_version() -> int:
	return 29

func get_migration_name() -> String:
	return "international_group_draw"

func up(db: Node) -> bool:
	if not db.execute("ALTER TABLE competition_units ADD COLUMN group_draw_rules TEXT NOT NULL DEFAULT '{}';"):
		return false
	return db.execute("""
		UPDATE competition_units SET competition_type = 'GROUP_AND_PLAYOFF',
		regular_season_enabled = 0, teams_promote = 0, teams_relegate = 0,
		matches_vs_other = 0, matches_vs_own = MAX(1, matches_vs_own), playoff_third_place = 1
		WHERE competition_id IN (SELECT id FROM competitions WHERE scope_type = 'INTERNATIONAL');
	""")
