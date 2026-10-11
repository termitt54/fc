class_name CountryNameRepository
extends RefCounted
## First/last name pools stored per country.


const KIND_FIRST := "FIRST"
const KIND_LAST := "LAST"

var _db: Node


func _init(database: Node = null) -> void:
	_db = database


func _db_manager() -> Node:
	if _db != null:
		return _db
	return DatabaseManager


func get_pools(country_id: int) -> Dictionary:
	## Returns { "first": PackedStringArray, "last": PackedStringArray }.
	if not _ensure_ready() or country_id < 1:
		return {"first": PackedStringArray(), "last": PackedStringArray()}

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT kind, name
		FROM country_names
		WHERE country_id = ?
		ORDER BY name COLLATE NOCASE ASC;
		""",
		[country_id]
	)

	var first := PackedStringArray()
	var last := PackedStringArray()
	for row in rows:
		var kind := str(row.get("kind", ""))
		var name := str(row.get("name", "")).strip_edges()
		if name.is_empty():
			continue
		if kind == KIND_FIRST:
			first.append(name)
		elif kind == KIND_LAST:
			last.append(name)
	return {"first": first, "last": last}


func get_counts_by_country() -> Dictionary:
	## Returns { country_id: { "first": int, "last": int } }.
	if not _ensure_ready():
		return {}
	var rows: Array = _db_manager().query_rows(
		"""
		SELECT country_id, kind, COUNT(*) AS cnt
		FROM country_names
		GROUP BY country_id, kind;
		"""
	)
	var out: Dictionary = {}
	for row in rows:
		var country_id := int(row.get("country_id", 0))
		if country_id < 1:
			continue
		if not out.has(country_id):
			out[country_id] = {"first": 0, "last": 0}
		var kind := str(row.get("kind", ""))
		var cnt := int(row.get("cnt", 0))
		if kind == KIND_FIRST:
			out[country_id]["first"] = cnt
		elif kind == KIND_LAST:
			out[country_id]["last"] = cnt
	return out


func replace_for_country(country_id: int, first_names: Array, last_names: Array) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	if country_id < 1:
		return DbResult.fail("Некорректная страна")

	var first := _normalize_list(first_names)
	var last := _normalize_list(last_names)

	var db := _db_manager()
	if not db.begin_transaction():
		return DbResult.fail(db.get_last_error())

	if not db.execute_with_bindings(
		"DELETE FROM country_names WHERE country_id = ?;",
		[country_id]
	):
		db.rollback_transaction()
		return DbResult.fail(db.get_last_error())

	for name in first:
		if not db.execute_with_bindings(
			"""
			INSERT INTO country_names (country_id, kind, name)
			VALUES (?, ?, ?);
			""",
			[country_id, KIND_FIRST, name]
		):
			db.rollback_transaction()
			return DbResult.fail(db.get_last_error())

	for name in last:
		if not db.execute_with_bindings(
			"""
			INSERT INTO country_names (country_id, kind, name)
			VALUES (?, ?, ?);
			""",
			[country_id, KIND_LAST, name]
		):
			db.rollback_transaction()
			return DbResult.fail(db.get_last_error())

	if not db.commit_transaction():
		db.rollback_transaction()
		return DbResult.fail(db.get_last_error())

	return DbResult.ok(get_pools(country_id))


func _normalize_list(raw: Array) -> PackedStringArray:
	var out := PackedStringArray()
	var seen: Dictionary = {}
	for item in raw:
		var name := str(item).strip_edges()
		if name.is_empty():
			continue
		var key := name.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		out.append(name)
	return out


func _ensure_ready() -> bool:
	return WorldDatabase.is_ready() and _db_manager().is_open()
