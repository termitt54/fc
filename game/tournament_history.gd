class_name TournamentHistory
extends RefCounted
## Compact immutable edition, with identities and statistics from that season.

static func snapshot(unit: Dictionary, season: int) -> Dictionary:
	var copy: Dictionary = {}
	for field in ["id", "competition_id", "name", "label", "competition_name", "competition_type", "national", "international_started", "rules", "divisions", "standings", "clubs_by_id", "group_draw"]:
		if unit.has(field):
			var value: Variant = unit[field]
			copy[field] = value.duplicate(true) if value is Dictionary or value is Array else value
	copy["season"] = season
	if unit.has("cup_state"):
		copy["cup_config"] = unit.get("cup_config", {}).duplicate(true)
		copy["cup_state"] = unit["cup_state"].duplicate(true)
	copy[UnitSeasonStats.KEY] = UnitSeasonStats.ensure(unit).duplicate(true)
	copy["matches"] = []
	for match_row in unit.get("matches", []):
		var compact: Dictionary = {}
		for field in ["id", "season_day", "matchday", "stage", "series_id", "game_index", "is_third_place", "home_id", "away_id", "home_goals", "away_goals", "played", "winner_id", "extra_time", "shootout"]:
			if match_row.has(field):
				var value: Variant = match_row[field]
				compact[field] = value.duplicate(true) if value is Dictionary or value is Array else value
		# Old match reports may be the only source of penalty scores.
		if match_row.has("cup_stage"):
			compact["cup_stage"] = match_row["cup_stage"]
		if not compact.has("shootout") and match_row.get("report", {}).has("shootout"):
			compact["shootout"] = match_row["report"]["shootout"].duplicate(true)
		copy["matches"].append(compact)
	copy["playoff"] = {}
	for field in unit.get("playoff", {}):
		if field == "matches":
			continue
		var value: Variant = unit["playoff"][field]
		copy["playoff"][field] = value.duplicate(true) if value is Dictionary or value is Array else value
	copy["playoff"]["matches"] = copy["matches"].filter(func(row): return str(row.get("stage", "REGULAR")) == "PLAYOFF")
	copy["winners"] = unit.get("winners", []).filter(func(row): return int(row.get("season", 0)) == season).duplicate(true)
	return copy

static func series_matches(unit: Dictionary, series: Dictionary) -> Array:
	var id := int(series.get("id", 0))
	if id <= 0:
		return []
	var rows: Array = unit.get("matches", []).filter(func(row): return str(row.get("stage", "")) == "PLAYOFF" and int(row.get("series_id", 0)) == id)
	rows.sort_custom(func(a, b): return int(a.get("game_index", 0)) < int(b.get("game_index", 0)))
	return rows

static func score(match_row: Dictionary) -> String:
	if not bool(match_row.get("played", false)):
		return "— : —"
	var result := "%d : %d" % [int(match_row.get("home_goals", 0)), int(match_row.get("away_goals", 0))]
	var shootout: Dictionary = match_row.get("shootout", match_row.get("report", {}).get("shootout", {}))
	if not shootout.is_empty():
		result += " (пен. %d : %d)" % [int(shootout.get("home", 0)), int(shootout.get("away", 0))]
	elif bool(match_row.get("extra_time", false)):
		result += " (д.в.)"
	return result
