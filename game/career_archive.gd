class_name CareerArchive
extends RefCounted
## Read-only view of the immutable history referenced by a save or session head.

const STORE := preload("res://game/save_store.gd")
const HISTORY := preload("res://game/history_store.gd")

var _db: Variant = null
var _slot: String = ""
var _head: int = 0
var _last_error: String = ""


static func path_for(slot: String) -> String:
	# Legacy archives are preserved for migration; new history lives in games.db.
	return "user://saves/%s_history.db" % slot


func open(slot: String) -> bool:
	if not STORE.is_valid_slot(slot):
		_last_error = "Некорректное имя сохранения"
		return false
	if not _open_database():
		return false
	_slot = slot
	var rows: Variant = _select("SELECT history_head FROM save_slots WHERE slot = ?;", [slot])
	if rows == null:
		close()
		return false
	_head = int(rows[0]["history_head"]) if not rows.is_empty() else 0
	return _validate_head()


func open_head(head: int) -> bool:
	if not _open_database():
		return false
	_head = head
	return _validate_head()


func close() -> void:
	if _db != null:
		_db.close_db()
	_db = null
	_slot = ""
	_head = 0


func is_open() -> bool:
	return _db != null


func get_last_error() -> String:
	return _last_error


func get_slot() -> String:
	return _slot


func count() -> int:
	if not is_open():
		return 0
	var rows: Variant = _select(HISTORY.ANCESTORS + "SELECT COUNT(*) AS c FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry);", [_head, _head])
	return int(rows[0]["c"]) if rows != null and not rows.is_empty() else 0


func get_player(player_id: int) -> Dictionary:
	var record: Dictionary = _record(player_id)
	if record.is_empty():
		return {}
	var identity: Dictionary = record["identity"].duplicate(true)
	identity["snapshot"] = record.get("player", {}).duplicate(true)
	return identity


func seasons_of(player_id: int) -> Array:
	var record: Dictionary = _record(player_id)
	return record.get("seasons", []).duplicate(true)


func top_scorers(limit: int = 50) -> Array:
	if not is_open():
		return []
	var rows: Variant = _select(HISTORY.ANCESTORS + "SELECT player_id, name, position, goals, assists, matches, retired_season FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry) ORDER BY goals DESC, matches ASC, player_id ASC LIMIT ?;", [_head, _head, maxi(limit, 1)])
	return rows if rows != null else []


func _record(player_id: int) -> Dictionary:
	if not is_open():
		return {}
	var rows: Variant = _select(HISTORY.ANCESTORS + "SELECT body FROM save_history_players WHERE history_id IN (SELECT id FROM ancestry) AND player_id = ? ORDER BY history_id DESC LIMIT 1;", [_head, _head, player_id])
	if rows == null or rows.is_empty():
		return {}
	var decoded: Variant = bytes_to_var(rows[0]["body"])
	if typeof(decoded) != TYPE_DICTIONARY or typeof(decoded.get("identity")) != TYPE_DICTIONARY or typeof(decoded.get("player", {})) != TYPE_DICTIONARY or typeof(decoded.get("seasons")) != TYPE_ARRAY:
		_last_error = "Повреждённая запись карьерной истории"
		return {}
	return decoded


func _select(sql: String, params: Array) -> Variant:
	if not _db.query_with_bindings(sql, params):
		_last_error = str(_db.error_message)
		return null
	return (_db.query_result as Array).duplicate(true)


func _validate_head() -> bool:
	if HISTORY.head_exists(_db, _head):
		return true
	_last_error = "Не найдена версия карьерной истории"
	close()
	return false


func _open_database() -> bool:
	close()
	_last_error = ""
	# Let SaveStore create/migrate schema before opening the read-only view.
	var catalog: Dictionary = STORE.new().list_slots()
	if not catalog["success"]:
		_last_error = str(catalog.get("error", ""))
		return false
	_db = ClassDB.instantiate("SQLite")
	_db.path = STORE.new().database_path()
	# The addon's read_only VFS cannot read WAL databases. Use native SQLite
	# with query_only instead; this view cannot execute mutating SQL.
	_db.verbosity_level = 0
	if not _db.open_db():
		_last_error = str(_db.error_message)
		_db = null
		return false
	if not _db.query("PRAGMA query_only = ON;"):
		_last_error = str(_db.error_message)
		close()
		return false
	return true


## Import only history closed before the loaded season; never mutate old files.
static func read_legacy(slot: String, season: int, active_ids: Dictionary) -> Dictionary:
	if not STORE.is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	var path: String = path_for(slot)
	if not FileAccess.file_exists(path):
		return DbResult.ok([])
	var db: Variant = ClassDB.instantiate("SQLite")
	db.path = path
	db.read_only = true
	db.verbosity_level = 0
	if not db.open_db():
		return DbResult.fail(str(db.error_message))
	if not db.query_with_bindings("SELECT * FROM retired_players WHERE retired_season < ? ORDER BY player_id;", [season]):
		var message: String = str(db.error_message)
		db.close_db()
		return DbResult.fail(message)
	var identities: Array = (db.query_result as Array).duplicate(true)
	if not db.query_with_bindings("SELECT s.* FROM retired_seasons s JOIN retired_players p ON p.player_id = s.player_id WHERE p.retired_season < ? ORDER BY s.player_id, s.season;", [season]):
		var message: String = str(db.error_message)
		db.close_db()
		return DbResult.fail(message)
	var seasons: Dictionary = {}
	for row in db.query_result:
		var pid: int = int(row["player_id"])
		if not seasons.has(pid):
			seasons[pid] = []
		seasons[pid].append(row.duplicate(true))
	db.close_db()
	var records: Array = []
	for identity in identities:
		var pid: int = int(identity["player_id"])
		if not active_ids.has(pid):
			records.append({"identity": identity, "player": {}, "seasons": seasons.get(pid, [])})
	return DbResult.ok(records)
