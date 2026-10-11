class_name PlayerStats
extends RefCounted
## Per-player statistics. A match is never stored: it is folded into the season
## stint, and at the season break each stint is pushed onto the career list.
## A mid-season club change closes the current stint and opens a new one.


const FIELDS := [
	"matches",
	"starts",
	"minutes",
	"goals",
	"assists",
	"saves",
	"conceded",
	"clean_sheets",
	"yellow",
	"red",
	"injuries",
	"pen_scored",
	"pen_missed",
	"pen_saved",
	"motm",
]

const TRANSFER_FEE_KEY := "transfer_fee"
const _LOG_SKIP_COUNTERPARTS := [
	"свободный агент",
	"вытеснен",
	"окончание контракта",
	"не продан",
]


static func blank(season: int = 0, club_id: int = 0) -> Dictionary:
	var row := {"season": season, "club_id": club_id, "rating_sum": 0.0}
	for field in FIELDS:
		row[field] = 0
	return row


static func season_of(player: Dictionary) -> Dictionary:
	var raw: Variant = player.get("season_stats", null)
	if typeof(raw) == TYPE_DICTIONARY:
		return raw
	var row := blank(0, int(player.get("club_id", 0)))
	player["season_stats"] = row
	return row


static func career_of(player: Dictionary) -> Array:
	var raw: Variant = player.get("career_stats", null)
	if typeof(raw) == TYPE_ARRAY:
		return raw
	var rows: Array = []
	player["career_stats"] = rows
	return rows


static func ensure_state(player: Dictionary, season: int = 0) -> void:
	var row := season_of(player)
	if int(row.get("season", 0)) < 1 and season > 0:
		row["season"] = season
	for field in FIELDS:
		if not row.has(field):
			row[field] = 0
	if not row.has("rating_sum"):
		row["rating_sum"] = 0.0
	career_of(player)


## Close the current stint if the player is joining another club this season.
static func begin_club_stint(player: Dictionary, season: int, club_id: int, fee: int) -> void:
	ensure_state(player, season)
	var row := season_of(player)
	var row_club := int(row.get("club_id", 0))
	var row_season := int(row.get("season", 0))
	var changed := row_club > 0 and row_club != club_id
	var same_season := row_season == season or row_season < 1
	var played := int(row.get("matches", 0)) > 0
	_ensure_stint(player, season, club_id, changed and same_season and played, fee)


## Folds one match performance into the player's current club stint.
static func apply_entry(player: Dictionary, entry: Dictionary, season: int, club_id: int) -> void:
	var minutes := int(entry.get("minutes", 0))
	if minutes <= 0:
		return
	var row := _ensure_stint(player, season, club_id, false, 0)
	row["matches"] = int(row.get("matches", 0)) + 1
	if bool(entry.get("started", false)):
		row["starts"] = int(row.get("starts", 0)) + 1
	row["minutes"] = int(row.get("minutes", 0)) + minutes
	row["goals"] = int(row.get("goals", 0)) + int(entry.get("goals", 0))
	row["assists"] = int(row.get("assists", 0)) + int(entry.get("assists", 0))
	row["saves"] = int(row.get("saves", 0)) + int(entry.get("saves", 0))
	row["conceded"] = int(row.get("conceded", 0)) + int(entry.get("conceded", 0))
	if bool(entry.get("clean_sheet", false)):
		row["clean_sheets"] = int(row.get("clean_sheets", 0)) + 1
	row["yellow"] = int(row.get("yellow", 0)) + int(entry.get("yellow", 0))
	row["red"] = int(row.get("red", 0)) + int(entry.get("red", 0))
	if int(entry.get("injury_rounds", 0)) > 0:
		row["injuries"] = int(row.get("injuries", 0)) + 1
	row["pen_scored"] = int(row.get("pen_scored", 0)) + int(entry.get("pen_scored", 0))
	row["pen_missed"] = int(row.get("pen_missed", 0)) + int(entry.get("pen_missed", 0))
	row["pen_saved"] = int(row.get("pen_saved", 0)) + int(entry.get("pen_saved", 0))
	if bool(entry.get("motm", false)):
		row["motm"] = int(row.get("motm", 0)) + 1
	row["rating_sum"] = float(row.get("rating_sum", 0.0)) + float(entry.get("rating", 0.0))


## Season break: archive the current stint and start a fresh one.
static func roll_season(player: Dictionary, next_season: int, club_id: int) -> void:
	var row := season_of(player)
	if int(row.get("matches", 0)) > 0:
		var career := career_of(player)
		career.append(_compact(row))
	player["season_stats"] = blank(next_season, club_id)


static func average_rating(row: Dictionary) -> float:
	var matches := int(row.get("matches", 0))
	if matches < 1:
		return 0.0
	return snappedf(float(row.get("rating_sum", 0.0)) / float(matches), 0.01)


static func substitute_apps(row: Dictionary) -> int:
	return maxi(0, int(row.get("matches", 0)) - int(row.get("starts", 0)))


static func career_totals(player: Dictionary) -> Dictionary:
	var totals := blank(0, 0)
	for row in career_of(player):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_add_into(totals, row)
	_add_into(totals, season_of(player))
	return totals


static func seasons_played(player: Dictionary) -> int:
	var seen: Dictionary = {}
	for row in career_of(player):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("matches", 0)) < 1:
			continue
		seen[int(row.get("season", 0))] = true
	if int(season_of(player).get("matches", 0)) > 0:
		seen[int(season_of(player).get("season", 0))] = true
	return seen.size()


## Career stints plus the current season, newest first.
static func timeline(player: Dictionary) -> Array:
	var rows: Array = []
	for entry in career_of(player):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("matches", 0)) < 1:
			continue
		rows.append(entry)
	var current := season_of(player)
	if int(current.get("matches", 0)) > 0:
		rows.append(current)
	rows.reverse()
	return rows


static func minutes_in_season(player: Dictionary, season: int = 0) -> int:
	var current := season_of(player)
	var target := season if season > 0 else int(current.get("season", 0))
	var total := 0
	if int(current.get("season", 0)) == target:
		total += int(current.get("minutes", 0))
	for entry in career_of(player):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("season", 0)) != target:
			continue
		total += int(entry.get("minutes", 0))
	return total


## Copy timeline rows and fill missing transfer fees from the session log.
## A fee is only shown when the player represented more than one club that season.
static func with_transfer_fees(rows: Array, transfer_log: Array, player_id: int) -> Array:
	var stints_in_season: Dictionary = {}
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var season := int(entry.get("season", 0))
		stints_in_season[season] = int(stints_in_season.get(season, 0)) + 1
	var out: Array = []
	for entry in rows:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = (entry as Dictionary).duplicate()
		var season := int(row.get("season", 0))
		if not row.has(TRANSFER_FEE_KEY) and int(stints_in_season.get(season, 0)) > 1:
			var fee: Variant = _inbound_fee(transfer_log, player_id, season, int(row.get("club_id", 0)))
			if fee != null:
				row[TRANSFER_FEE_KEY] = int(fee)
		out.append(row)
	return out


static func _ensure_stint(
	player: Dictionary,
	season: int,
	club_id: int,
	stamp_fee: bool,
	fee: int
) -> Dictionary:
	var row := season_of(player)
	if int(row.get("season", 0)) != season and season > 0:
		row["season"] = season
	var row_club := int(row.get("club_id", 0))
	if row_club > 0 and row_club != club_id and int(row.get("matches", 0)) > 0:
		career_of(player).append(_compact(row))
		var fresh := blank(season, club_id)
		if stamp_fee:
			fresh[TRANSFER_FEE_KEY] = maxi(0, fee)
		player["season_stats"] = fresh
		return fresh
	if row_club != club_id:
		row["club_id"] = club_id
		if stamp_fee and row_club > 0:
			row[TRANSFER_FEE_KEY] = maxi(0, fee)
	return row


static func _inbound_fee(transfer_log: Array, player_id: int, season: int, club_id: int) -> Variant:
	var found: Variant = null
	for entry in transfer_log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if str(entry.get("direction", "")) != "in":
			continue
		if int(entry.get("player_id", 0)) != player_id:
			continue
		if int(entry.get("season", 0)) != season:
			continue
		if int(entry.get("club_id", 0)) != club_id:
			continue
		if not _is_purchase_move(entry):
			continue
		found = maxi(0, int(entry.get("fee", 0)))
	return found


static func _is_purchase_move(entry: Dictionary) -> bool:
	if int(entry.get("fee", 0)) > 0:
		return true
	var other := str(entry.get("other_club", "")).strip_edges()
	if other.is_empty():
		return false
	return not _LOG_SKIP_COUNTERPARTS.has(other)


static func _add_into(totals: Dictionary, row: Dictionary) -> void:
	for field in FIELDS:
		totals[field] = int(totals.get(field, 0)) + int(row.get(field, 0))
	totals["rating_sum"] = float(totals.get("rating_sum", 0.0)) + float(row.get("rating_sum", 0.0))


static func _compact(row: Dictionary) -> Dictionary:
	var out := {
		"season": int(row.get("season", 0)),
		"club_id": int(row.get("club_id", 0)),
		"rating_sum": snappedf(float(row.get("rating_sum", 0.0)), 0.1),
	}
	for field in FIELDS:
		var value := int(row.get(field, 0))
		if value != 0:
			out[field] = value
	if row.has(TRANSFER_FEE_KEY):
		out[TRANSFER_FEE_KEY] = maxi(0, int(row.get(TRANSFER_FEE_KEY, 0)))
	return out
