extends RefCounted
## Immutable history batches. Saves point to a head; old heads never change.

const RATINGS := preload("res://game/match_ratings.gd")

const ANCESTORS := "WITH RECURSIVE ancestry(id) AS (SELECT ? WHERE ? > 0 UNION ALL SELECT n.parent_id FROM save_history_nodes n JOIN ancestry a ON n.id = a.id WHERE n.parent_id IS NOT NULL) "


static func ensure_schema(db: Variant) -> bool:
	for sql in [
		"CREATE TABLE IF NOT EXISTS save_history_nodes (id INTEGER PRIMARY KEY AUTOINCREMENT, parent_id INTEGER REFERENCES save_history_nodes(id));",
		"CREATE TABLE IF NOT EXISTS save_history_players (history_id INTEGER NOT NULL REFERENCES save_history_nodes(id), player_id INTEGER NOT NULL, name TEXT NOT NULL, position TEXT NOT NULL, goals INTEGER NOT NULL, assists INTEGER NOT NULL, matches INTEGER NOT NULL, retired_season INTEGER NOT NULL, body BLOB NOT NULL, PRIMARY KEY(history_id, player_id));",
		"CREATE INDEX IF NOT EXISTS idx_history_player ON save_history_players(player_id, history_id DESC);",
		"CREATE TABLE IF NOT EXISTS save_history_tournaments (history_id INTEGER NOT NULL REFERENCES save_history_nodes(id), unit_id INTEGER NOT NULL, season INTEGER NOT NULL, body BLOB NOT NULL, PRIMARY KEY(history_id, unit_id, season));",
		"CREATE INDEX IF NOT EXISTS idx_history_tournament ON save_history_tournaments(unit_id, season, history_id DESC);",
	]:
		if not db.query(sql):
			return false
	return true


static func head_exists(db: Variant, head: int) -> bool:
	if head == 0:
		return true
	return head > 0 and db.query_with_bindings("SELECT id FROM save_history_nodes WHERE id = ?;", [head]) and not (db.query_result as Array).is_empty()


## Caller owns BEGIN/COMMIT/ROLLBACK. Records are prepared immutable snapshots.
static func write_batch(db: Variant, head: int, records: Array) -> Dictionary:
	if not head_exists(db, head):
		return DbResult.fail("Не найдена версия карьерной истории")
	if records.is_empty():
		return DbResult.ok({"history_head": head})
	if not db.query_with_bindings("INSERT INTO save_history_nodes(parent_id) VALUES (?);", [head if head > 0 else null]):
		return DbResult.fail(str(db.error_message))
	if not db.query("SELECT last_insert_rowid() AS id;"):
		return DbResult.fail(str(db.error_message))
	var next_head: int = int(db.query_result[0]["id"])
	var seen: Dictionary = {}
	for record in records:
		if record is Dictionary and str(record.get("kind", "")) == "tournament_season":
			var unit_id := int(record.get("unit_id", 0))
			var season := int(record.get("season", 0))
			var key := "%d:%d" % [unit_id, season]
			if unit_id < 1 or season < 1 or seen.has(key) or not record.get("unit") is Dictionary:
				return DbResult.fail("Некорректная запись истории турнира")
			seen[key] = true
			if not db.query_with_bindings(ANCESTORS + "SELECT 1 FROM save_history_tournaments WHERE history_id IN (SELECT id FROM ancestry) AND unit_id = ? AND season = ? LIMIT 1;", [head, head, unit_id, season]):
				return DbResult.fail(str(db.error_message))
			if not (db.query_result as Array).is_empty():
				continue
			var raw := var_to_bytes(record["unit"])
			var body := PackedByteArray()
			body.resize(4)
			body.encode_u32(0, raw.size())
			body.append_array(raw.compress(FileAccess.COMPRESSION_ZSTD))
			if not db.query_with_bindings("INSERT INTO save_history_tournaments(history_id, unit_id, season, body) VALUES (?, ?, ?, ?);", [next_head, unit_id, season, body]):
				return DbResult.fail(str(db.error_message))
			continue
		if typeof(record) != TYPE_DICTIONARY or typeof(record.get("identity")) != TYPE_DICTIONARY or typeof(record.get("player", {})) != TYPE_DICTIONARY or typeof(record.get("seasons")) != TYPE_ARRAY:
			return DbResult.fail("Некорректная запись карьерной истории")
		var identity: Dictionary = record["identity"]
		var pid: int = int(identity.get("player_id", 0))
		if pid < 1 or seen.has(pid):
			return DbResult.fail("Повторный или некорректный ID архивного игрока")
		if not has_archived_playing_history(record):
			continue
		seen[pid] = true
		if not db.query_with_bindings(ANCESTORS + "SELECT 1 FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry) AND player_id = ? LIMIT 1;", [head, head, pid]):
			return DbResult.fail(str(db.error_message))
		if not (db.query_result as Array).is_empty():
			return DbResult.fail("Игрок уже завершил карьеру в этой ветке истории: %d" % pid)
		if not db.query_with_bindings("INSERT INTO save_history_players(history_id, player_id, name, position, goals, assists, matches, retired_season, body) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);", [next_head, pid, str(identity.get("name", "")), str(identity.get("position", "")), int(identity.get("goals", 0)), int(identity.get("assists", 0)), int(identity.get("matches", 0)), int(identity.get("retired_season", 0)), var_to_bytes(record)]):
			return DbResult.fail(str(db.error_message))
	return DbResult.ok({"history_head": next_head})


## Development alone is not a playing career. Keep even partial legacy statistics.
static func has_playing_history(player: Dictionary) -> bool:
	var rows: Array = [PlayerStats.career_totals(player)]
	var national: Variant = player.get("national_stats", [])
	if typeof(national) == TYPE_ARRAY:
		rows.append_array(national)
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		for field in PlayerStats.FIELDS:
			if field == "injuries": continue
			if int(row.get(field, 0)) > 0:
				return true
		if float(row.get("rating_sum", 0.0)) > 0.0:
			return true
	return false

static func has_archived_playing_history(record: Dictionary) -> bool:
	if has_playing_history(record.get("player", {})): return true
	var rows: Array = [record.get("identity", {})]
	rows.append_array(record.get("seasons", []))
	for row in rows:
		for field in PlayerStats.FIELDS:
			if field != "injuries" and int(row.get(field, 0)) > 0: return true
		if float(row.get("rating_sum", 0.0)) > 0: return true
	return false


static func snapshot(player: Dictionary, season: int) -> Dictionary:
	var copy: Dictionary = player.duplicate(true)
	RATINGS.strip_cache([copy])
	var totals: Dictionary = PlayerStats.career_totals(copy)
	var identity := {"player_id": int(copy.get("id", 0)), "name": str(copy.get("name", "")), "position": str(copy.get("position", "")), "nationality_country_id": int(copy.get("nationality_country_id", 0)), "final_club_id": int(copy.get("club_id", 0)), "age": int(copy.get("age", 0)), "retired_season": season, "current_ability": int(copy.get("current_ability", 0)), "potential_ability": int(copy.get("potential_ability", 0)), "characters": ",".join(PackedStringArray(PlayerTypes.characters_of(copy))), "seasons": PlayerStats.seasons_played(copy), "rating_sum": float(totals.get("rating_sum", 0.0))}
	for field in PlayerStats.FIELDS:
		identity[field] = int(totals.get(field, 0))
	var seasons: Array = PlayerStats.career_of(copy).duplicate(true)
	var current: Dictionary = PlayerStats.season_of(copy)
	if int(current.get("matches", 0)) > 0:
		seasons.append(current.duplicate(true))
	return {"identity": identity, "player": copy, "seasons": seasons}
