class_name SaveStore
extends RefCounted
## Save catalog in SQLite. Slot rows are tiny, so the load screen never touches
## the season. Each section of the session is one Godot binary blob (var_to_bytes),
## not JSON text: decode keeps integer keys and skips a parse plus a per-player walk.


const SQLITE_CLASS := "SQLite"
const DB_PATH := "user://saves/games.db"
const VERBOSITY_QUIET := 0
const ERR_NOT_FOUND := "Сохранение не найдено"
const HISTORY := preload("res://game/history_store.gd")

const SECTIONS := [
	"units",
	"players_by_club",
	"youth_players_by_club",
	"reserve_players_by_club",
	"free_agents",
	"coaches_by_club",
	"club_budgets",
	"transfer_log",
]

static var database_path_override: String = ""

var _db: Variant = null
var _last_error: String = ""


static func is_valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64:
		return false
	for i in slot.length():
		var code := slot.unicode_at(i)
		var digit := code >= 48 and code <= 57
		var upper := code >= 65 and code <= 90
		var lower := code >= 97 and code <= 122
		if not (digit or upper or lower or code == 95 or code == 45):
			return false
	return true


static func display_name(slot: String) -> String:
	if slot == "autosave":
		return "Автосохранение"
	return slot


func get_last_error() -> String:
	return _last_error


func database_path() -> String:
	if not database_path_override.is_empty():
		return database_path_override
	return DB_PATH


func list_slots() -> Dictionary:
	if not _open():
		return DbResult.fail(_last_error)
	var rows: Variant = _select(
		"""
		SELECT slot, version, saved_at, season_number, season_day, season_total_days,
			selected_unit_id, season_finished, player_count, unit_count
		FROM save_slots
		ORDER BY saved_at DESC, slot ASC;
		""",
		[]
	)
	_close()
	if rows == null:
		return DbResult.fail(_last_error)
	var items: Array = []
	for row in rows as Array:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = (row as Dictionary).duplicate(true)
		item["season_finished"] = int(item.get("season_finished", 0)) != 0
		item["legacy"] = false
		items.append(item)
	return DbResult.ok_list(items)


func load_slot(slot: String) -> Dictionary:
	if not is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	if not _open():
		return DbResult.fail(_last_error)
	var meta_rows: Variant = _select(
		"SELECT * FROM save_slots WHERE slot = ? LIMIT 1;",
		[slot]
	)
	if meta_rows == null:
		_close()
		return DbResult.fail(_last_error)
	var meta_table: Array = meta_rows
	if meta_table.is_empty():
		_close()
		return DbResult.fail(ERR_NOT_FOUND)
	var section_rows: Variant = _select(
		"SELECT section, body FROM save_sections WHERE slot = ?;",
		[slot]
	)
	var history_head: int = int(meta_table[0].get("history_head", 0))
	if not HISTORY.head_exists(_db, history_head):
		_close()
		return DbResult.fail("Повреждённое сохранение: не найдена версия истории")
	_close()
	if section_rows == null:
		return DbResult.fail(_last_error)

	var meta: Dictionary = meta_table[0]
	var bodies: Dictionary = {}
	for row in section_rows as Array:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		bodies[str(row.get("section", ""))] = row.get("body", PackedByteArray())

	var payload := {
		"_native": true,
		"version": int(meta.get("version", 0)),
		"saved_at": str(meta.get("saved_at", "")),
		"season_number": int(meta.get("season_number", 1)),
		"season_day": int(meta.get("season_day", 0)),
		"season_total_days": int(meta.get("season_total_days", 1)),
		"selected_unit_id": int(meta.get("selected_unit_id", 0)),
		"season_finished": int(meta.get("season_finished", 0)) != 0,
		"wages_paid_for_season": int(meta.get("wages_paid_for_season", 0)),
		"next_player_id": int(meta.get("next_player_id", 1)),
		"next_coach_id": int(meta.get("next_coach_id", 1)),
		"next_match_id": int(meta.get("next_match_id", 1)),
		"rng_seed": int(meta.get("rng_seed", 0)),
		"rng_state": int(meta.get("rng_state", 0)),
		"history_head": history_head,
	}
	for section in SECTIONS:
		if not bodies.has(section):
			return DbResult.fail("Повреждённое сохранение: нет секции %s" % section)
		var decoded: Variant = _decode(bodies[section])
		if decoded == null or not _section_type_ok(section, decoded):
			return DbResult.fail("Повреждённое сохранение: секция %s" % section)
		payload[section] = decoded
	return DbResult.ok(payload)


func write_slot(slot: String, meta: Dictionary, sections: Dictionary) -> Dictionary:
	if not is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	var encoded: Dictionary = {}
	for section in SECTIONS:
		if not sections.has(section):
			return DbResult.fail("Не хватает секции сохранения %s" % section)
		var bytes := _encode(sections[section])
		if bytes.is_empty():
			return DbResult.fail("Не удалось упаковать секцию %s" % section)
		encoded[section] = bytes
	if not _open():
		return DbResult.fail(_last_error)
	if not _db.query("BEGIN IMMEDIATE;"):
		var begin_error := str(_db.error_message)
		_close()
		return DbResult.fail(begin_error)
	if not HISTORY.head_exists(_db, int(meta.get("history_head", 0))):
		return _fail_write("Не найдена версия карьерной истории")

	if not _db.query_with_bindings("DELETE FROM save_sections WHERE slot = ?;", [slot]):
		return _fail_write(str(_db.error_message))

	var replaced: bool = _db.query_with_bindings(
		"""
		INSERT OR REPLACE INTO save_slots (
			slot, version, saved_at, season_number, season_day, season_total_days,
			selected_unit_id, season_finished, wages_paid_for_season,
			next_player_id, next_coach_id, next_match_id, rng_seed, rng_state,
			player_count, unit_count, history_head
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			slot,
			int(meta.get("version", 0)),
			str(meta.get("saved_at", "")),
			int(meta.get("season_number", 1)),
			int(meta.get("season_day", 0)),
			int(meta.get("season_total_days", 1)),
			int(meta.get("selected_unit_id", 0)),
			1 if bool(meta.get("season_finished", false)) else 0,
			int(meta.get("wages_paid_for_season", 0)),
			int(meta.get("next_player_id", 1)),
			int(meta.get("next_coach_id", 1)),
			int(meta.get("next_match_id", 1)),
			int(meta.get("rng_seed", 0)),
			int(meta.get("rng_state", 0)),
			int(meta.get("player_count", 0)),
			int(meta.get("unit_count", 0)),
			int(meta.get("history_head", 0)),
		]
	)
	if not replaced:
		return _fail_write(str(_db.error_message))

	for section in SECTIONS:
		var inserted: bool = _db.query_with_bindings(
			"INSERT INTO save_sections (slot, section, body) VALUES (?, ?, ?);",
			[slot, section, encoded[section]]
		)
		if not inserted:
			return _fail_write(str(_db.error_message))

	if not _db.query("COMMIT;"):
		return _fail_write(str(_db.error_message))
	_close()
	return DbResult.ok({"slot": slot})


func append_history(head: int, records: Array) -> Dictionary:
	if not _open():
		return DbResult.fail(_last_error)
	if not _db.query("BEGIN IMMEDIATE;"):
		var message: String = str(_db.error_message)
		_close()
		return DbResult.fail(message)
	var written: Dictionary = HISTORY.write_batch(_db, head, records)
	if not written["success"]:
		return _fail_write(str(written.get("error", "Не удалось записать историю")))
	if not _db.query("COMMIT;"):
		return _fail_write(str(_db.error_message))
	_close()
	return written


func delete_slot(slot: String) -> Dictionary:
	if not is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	if not _open():
		return DbResult.fail(_last_error)
	if not _db.query("BEGIN IMMEDIATE;"):
		var begin_error := str(_db.error_message)
		_close()
		return DbResult.fail(begin_error)
	if not _db.query_with_bindings("DELETE FROM save_sections WHERE slot = ?;", [slot]):
		return _fail_write(str(_db.error_message))
	if not _db.query_with_bindings("DELETE FROM save_slots WHERE slot = ?;", [slot]):
		return _fail_write(str(_db.error_message))
	if not _db.query("COMMIT;"):
		return _fail_write(str(_db.error_message))
	_close()
	return DbResult.ok({"slot": slot})


func _fail_write(message: String) -> Dictionary:
	if _db != null:
		_db.query("ROLLBACK;")
	_close()
	return DbResult.fail(message if not message.is_empty() else "Не удалось записать сохранение")


func _select(sql: String, params: Array) -> Variant:
	var ok: bool
	if params.is_empty():
		ok = _db.query(sql)
	else:
		ok = _db.query_with_bindings(sql, params)
	if not ok:
		_last_error = str(_db.error_message)
		return null
	return (_db.query_result as Array).duplicate(true)


func _section_type_ok(section: String, value: Variant) -> bool:
	match section:
		"units", "free_agents", "transfer_log":
			return typeof(value) == TYPE_ARRAY
		_:
			return typeof(value) == TYPE_DICTIONARY


func _encode(value: Variant) -> PackedByteArray:
	return var_to_bytes(value)


func _decode(raw: Variant) -> Variant:
	if not (raw is PackedByteArray):
		return null
	var bytes: PackedByteArray = raw
	if bytes.is_empty():
		return null
	return bytes_to_var(bytes)


func _open() -> bool:
	_close()
	_last_error = ""
	if not ClassDB.class_exists(SQLITE_CLASS):
		_last_error = "Плагин SQLite недоступен"
		return false
	var path := database_path()
	var folder := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			_last_error = "Не удалось создать папку сохранений"
			return false
	_db = ClassDB.instantiate(SQLITE_CLASS)
	if _db == null:
		_last_error = "Не удалось создать SQLite"
		return false
	_db.path = path
	_db.verbosity_level = VERBOSITY_QUIET
	_db.foreign_keys = true
	if not _db.open_db():
		_last_error = str(_db.error_message)
		_db = null
		return false
	if not _db.query("PRAGMA foreign_keys = ON;"):
		_last_error = str(_db.error_message)
		_close()
		return false
	_db.query("PRAGMA journal_mode = WAL;")
	_db.query("PRAGMA synchronous = NORMAL;")
	_db.query("PRAGMA temp_store = MEMORY;")
	if not _ensure_schema():
		_close()
		return false
	return true


func _close() -> void:
	if _db != null:
		_db.close_db()
	_db = null


func _ensure_schema() -> bool:
	var statements := [
		"""
		CREATE TABLE IF NOT EXISTS save_slots (
			slot TEXT PRIMARY KEY,
			version INTEGER NOT NULL,
			saved_at TEXT NOT NULL,
			season_number INTEGER NOT NULL,
			season_day INTEGER NOT NULL,
			season_total_days INTEGER NOT NULL,
			selected_unit_id INTEGER NOT NULL,
			season_finished INTEGER NOT NULL,
			wages_paid_for_season INTEGER NOT NULL,
			next_player_id INTEGER NOT NULL,
			next_coach_id INTEGER NOT NULL,
			next_match_id INTEGER NOT NULL,
			rng_seed INTEGER NOT NULL,
			rng_state INTEGER NOT NULL,
			player_count INTEGER NOT NULL,
			unit_count INTEGER NOT NULL
		);
		""",
		"""
		CREATE TABLE IF NOT EXISTS save_sections (
			slot TEXT NOT NULL,
			section TEXT NOT NULL,
			body BLOB NOT NULL,
			PRIMARY KEY (slot, section),
			FOREIGN KEY (slot) REFERENCES save_slots(slot) ON DELETE CASCADE
		);
		""",
	]
	for sql in statements:
		if not _db.query(sql):
			_last_error = str(_db.error_message)
			return false
	if not _db.query("PRAGMA table_info(save_slots);"):
		_last_error = str(_db.error_message)
		return false
	var has_history: bool = false
	for column in _db.query_result:
		if str(column.get("name", "")) == "history_head":
			has_history = true
	if not has_history and not _db.query("ALTER TABLE save_slots ADD COLUMN history_head INTEGER NOT NULL DEFAULT 0;"):
		_last_error = str(_db.error_message)
		return false
	if not HISTORY.ensure_schema(_db) or not _db.query("PRAGMA user_version = 2;"):
		_last_error = str(_db.error_message)
		return false
	return true
