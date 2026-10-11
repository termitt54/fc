class_name UnitSeasonStats
extends RefCounted

const MatchTypesScript := preload("res://game/match_types.gd")
## Player leaderboards for one tournament unit, current season only.
## Figures are taken from matches of this unit, not from a player's other competitions.


const KEY := "season_player_stats"
const LIMIT := 12

const BOARDS := [
	{"title": "Бомбардиры", "field": "goals", "column": "Г"},
	{"title": "Ассистенты", "field": "assists", "column": "Пас"},
	{"title": "Средняя оценка", "field": "rating", "column": "Оц."},
	{"title": "Сухие матчи", "field": "clean_sheets", "column": "СМ"},
	{"title": "Жёлтые карточки", "field": "yellow", "column": "ЖК"},
	{"title": "Красные карточки", "field": "red", "column": "КК"},
]


static func empty_bag() -> Dictionary:
	return {}


static func ensure(unit: Dictionary) -> Dictionary:
	if unit.has(KEY) and typeof(unit.get(KEY)) == TYPE_DICTIONARY:
		return unit[KEY]
	var bag := _from_played_matches(unit)
	unit[KEY] = bag
	return bag


static func record_report(unit: Dictionary, club_id: int, report: Dictionary) -> void:
	if report.is_empty():
		return
	var bag := ensure(unit)
	for entry in report.get("players", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var minutes := int(entry.get("minutes", 0))
		if minutes < 1:
			continue
		var player_id := int(entry.get("player_id", 0))
		if player_id < 1:
			continue
		var row: Dictionary = bag.get(player_id, {})
		row["player_id"] = player_id
		row["club_id"] = club_id
		var name := str(entry.get("name", "")).strip_edges()
		if not name.is_empty():
			row["name"] = name
		var position := str(entry.get("position", "")).strip_edges()
		if not position.is_empty():
			row["position"] = position
		row["matches"] = int(row.get("matches", 0)) + 1
		row["goals"] = int(row.get("goals", 0)) + int(entry.get("goals", 0))
		row["assists"] = int(row.get("assists", 0)) + int(entry.get("assists", 0))
		row["yellow"] = int(row.get("yellow", 0)) + int(entry.get("yellow", 0))
		row["red"] = int(row.get("red", 0)) + int(entry.get("red", 0))
		row["clean_sheets"] = int(row.get("clean_sheets", 0)) + (1 if bool(entry.get("clean_sheet", false)) else 0)
		row["rating_sum"] = float(row.get("rating_sum", 0.0)) + float(entry.get("rating", 0.0))
		bag[player_id] = row
	unit[KEY] = bag


static func leaders(unit: Dictionary, field: String, limit: int = LIMIT) -> Array:
	var bag := ensure(unit)
	var rows: Array = []
	for player_id in bag.keys():
		var row: Dictionary = bag[player_id]
		if _metric(row, field) <= 0.0:
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left := _metric(a, field)
		var right := _metric(b, field)
		if absf(left - right) > 0.001:
			return left > right
		if field == "goals":
			var assist_gap := int(b.get("assists", 0)) - int(a.get("assists", 0))
			if assist_gap != 0:
				return assist_gap < 0
		return str(a.get("name", "")) < str(b.get("name", ""))
	)
	if rows.size() > limit:
		rows = rows.slice(0, limit)
	return rows


static func has_leaders(unit: Dictionary) -> bool:
	for board in BOARDS:
		if not leaders(unit, str(board["field"]), 1).is_empty():
			return true
	return false


static func format_metric(row: Dictionary, field: String) -> String:
	if field == "rating":
		return "%.2f" % _metric(row, field)
	return str(int(_metric(row, field)))


static func _metric(row: Dictionary, field: String) -> float:
	if field == "rating":
		var matches := int(row.get("matches", 0))
		if matches < 1:
			return 0.0
		return float(row.get("rating_sum", 0.0)) / float(matches)
	return float(int(row.get(field, 0)))


static func _from_played_matches(unit: Dictionary) -> Dictionary:
	var bag := {}
	for match_row in unit.get("matches", []):
		if typeof(match_row) != TYPE_DICTIONARY or not bool(match_row.get("played", false)):
			continue
		var report: Variant = match_row.get("report", null)
		if typeof(report) != TYPE_DICTIONARY:
			continue
		for event in (report as Dictionary).get("highlights", []):
			if typeof(event) != TYPE_DICTIONARY:
				continue
			var type := str(event.get("type", ""))
			var player_id := int(event.get("player_id", 0))
			if player_id < 1:
				continue
			var row: Dictionary = bag.get(player_id, {})
			row["player_id"] = player_id
			row["club_id"] = int(event.get("club_id", row.get("club_id", 0)))
			var name := str(event.get("player", "")).strip_edges()
			if not name.is_empty():
				row["name"] = name
			if type == MatchTypesScript.EVENT_GOAL or type == MatchTypesScript.EVENT_PENALTY_GOAL:
				row["goals"] = int(row.get("goals", 0)) + 1
			elif type == MatchTypesScript.EVENT_RED:
				row["red"] = int(row.get("red", 0)) + 1
			bag[player_id] = row
	return bag
