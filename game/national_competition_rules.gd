extends RefCounted
## Pure national identity and result rules. No autoloads or global script classes.

const TEAM_ID_BASE := 1000000000

static func is_team(id: int) -> bool:
	return id > TEAM_ID_BASE

static func team_id(country_id: int) -> int:
	return TEAM_ID_BASE + country_id

static func is_unit(unit: Dictionary) -> bool:
	return bool(unit.get("national", false))

static func due(unit: Dictionary, season: int) -> bool:
	var start := int(unit.get("start_season", 1))
	if season < start:
		return false
	match str(unit.get("periodicity", "ANNUAL")):
		"ONCE": return season == start
		"BIENNIAL": return (season - start) % 2 == 0
		"QUADRENNIAL": return (season - start) % 4 == 0
	return true

static func identity(country: Dictionary) -> Dictionary:
	var row := country.duplicate(true)
	row["country_id"] = int(country.get("id", 0))
	row["id"] = team_id(row["country_id"])
	row["is_national"] = true
	row["logo_path"] = str(country.get("flag_path", ""))
	row["short_name"] = str(country.get("abbreviation", country.get("name", "")))
	return row

static func regular_complete(unit: Dictionary) -> bool:
	var has_regular := false
	for match_row in unit.get("matches", []):
		if str(match_row.get("stage", "REGULAR")) != "REGULAR":
			continue
		has_regular = true
		if not bool(match_row.get("played", false)):
			return false
	return true if has_regular else (unit.get("matches", []) as Array).is_empty()

static func is_unit_season_complete(unit: Dictionary) -> bool:
	if unit.has("cup_state"):
		return bool(unit["cup_state"].get("finished", false))
	var playoff: Dictionary = unit.get("playoff", {})
	if bool(playoff.get("enabled", false)):
		return bool(playoff.get("finished", false))
	return regular_complete(unit)

static func _rounds_for_teams(teams: int) -> int:
	var n := maxi(teams, 2)
	var rounds := 0
	while n > 1:
		n = int(ceil(float(n) / 2.0))
		rounds += 1
	return rounds

static func match_winner_club_id(match_row: Dictionary) -> int:
	if not bool(match_row.get("played", false)):
		return 0
	var home_id: int = int(match_row.get("home_id", 0))
	var away_id: int = int(match_row.get("away_id", 0))
	var stored: int = int(match_row.get("winner_id", 0))
	if stored == home_id or stored == away_id:
		return stored
	var hg: int = int(match_row.get("home_goals", 0))
	var ag: int = int(match_row.get("away_goals", 0))
	if hg > ag:
		return home_id
	if ag > hg:
		return away_id
	var shootout: Dictionary = match_row.get("shootout", {})
	if shootout.is_empty():
		var report: Dictionary = match_row.get("report", {})
		if typeof(report) == TYPE_DICTIONARY:
			shootout = report.get("shootout", {})
	if typeof(shootout) != TYPE_DICTIONARY or shootout.is_empty():
		return 0
	var home_pens := int(shootout.get("home", 0))
	var away_pens := int(shootout.get("away", 0))
	if home_pens == away_pens:
		return 0
	return home_id if home_pens > away_pens else away_id
