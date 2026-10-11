extends Node
## Low-level SQLite access. No world/game business logic.
## Uses ClassDB so scripts parse even before the GDExtension finishes loading.

const SQLITE_CLASS := "SQLite"
const VERBOSITY_QUIET := 0

var _db: Variant = null
var _path: String = ""
var _is_open: bool = false
var _last_error: String = ""


func open_database(path: String) -> bool:
	if path.is_empty():
		_set_error("Database path is empty")
		return false

	if _is_open:
		close_database()

	if not ClassDB.class_exists(SQLITE_CLASS):
		_set_error("SQLite class is unavailable. Install and enable the godot-sqlite plugin.")
		return false

	_db = ClassDB.instantiate(SQLITE_CLASS)
	if _db == null:
		_set_error("Failed to instantiate SQLite class")
		return false

	_db.path = path
	_db.verbosity_level = VERBOSITY_QUIET
	# Must be set before open_db() for the plugin to enable FK support.
	_db.foreign_keys = true

	if not _db.open_db():
		var plugin_error: String = str(_db.error_message)
		_db = null
		_is_open = false
		_path = ""
		_set_error("Failed to open database '%s': %s" % [path, plugin_error])
		return false

	_path = path
	_is_open = true
	_last_error = ""

	if not execute("PRAGMA foreign_keys = ON;"):
		var pragma_error := _last_error
		close_database()
		_set_error("Failed to enable foreign keys for '%s': %s" % [path, pragma_error])
		return false

	return true


func close_database() -> void:
	if _db != null:
		_db.close_db()
	_db = null
	_path = ""
	_is_open = false


func is_open() -> bool:
	return _is_open and _db != null


func get_database_path() -> String:
	return _path


func get_last_error() -> String:
	return _last_error


func get_last_insert_rowid() -> int:
	if not is_open() or _db == null:
		return -1
	return int(_db.last_insert_rowid)


func execute(sql: String) -> bool:
	if not _ensure_open():
		return false
	if not _db.query(sql):
		_set_error(str(_db.error_message))
		return false
	_last_error = ""
	return true


func execute_with_bindings(sql: String, params: Array) -> bool:
	if not _ensure_open():
		return false
	if not _db.query_with_bindings(sql, params):
		_set_error(str(_db.error_message))
		return false
	_last_error = ""
	return true


func query_rows(sql: String, params: Array = []) -> Array:
	if not _ensure_open():
		return []

	var ok: bool
	if params.is_empty():
		ok = _db.query(sql)
	else:
		ok = _db.query_with_bindings(sql, params)

	if not ok:
		_set_error(str(_db.error_message))
		return []

	_last_error = ""
	var result: Array = _db.query_result
	return result.duplicate(true)


func begin_transaction() -> bool:
	return execute("BEGIN TRANSACTION;")


func commit_transaction() -> bool:
	return execute("COMMIT;")


func rollback_transaction() -> bool:
	return execute("ROLLBACK;")


func _ensure_open() -> bool:
	if is_open():
		return true
	_set_error("Database connection is not open")
	return false


func _set_error(message: String) -> void:
	_last_error = message
