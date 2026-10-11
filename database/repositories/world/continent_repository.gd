class_name ContinentRepository
extends RefCounted

const NAME_MAX_LENGTH := 100
const SHORT_NAME_MAX_LENGTH := 30

const LIST_SQL := """
SELECT
	continents.id,
	continents.name,
	continents.short_name,
	continents.code,
	continents.logo_path,
	continents.sort_order,
	continents.is_active,
	continents.created_at,
	continents.updated_at,
	COUNT(DISTINCT countries.id) AS countries_count,
	COUNT(DISTINCT clubs.id) AS clubs_count
FROM continents
LEFT JOIN countries
	ON countries.continent_id = continents.id
LEFT JOIN clubs
	ON clubs.country_id = countries.id
GROUP BY continents.id
ORDER BY continents.sort_order ASC, continents.name COLLATE NOCASE ASC;
"""

const GET_BY_ID_SQL := """
SELECT
	continents.id,
	continents.name,
	continents.short_name,
	continents.code,
	continents.logo_path,
	continents.sort_order,
	continents.is_active,
	continents.created_at,
	continents.updated_at,
	COUNT(DISTINCT countries.id) AS countries_count,
	COUNT(DISTINCT clubs.id) AS clubs_count
FROM continents
LEFT JOIN countries
	ON countries.continent_id = continents.id
LEFT JOIN clubs
	ON clubs.country_id = countries.id
WHERE continents.id = ?
GROUP BY continents.id
LIMIT 1;
"""

var _db: Node


func _init(database: Node = null) -> void:
	_db = database


func _db_manager() -> Node:
	if _db != null:
		return _db
	return DatabaseManager


func get_all() -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна", [])

	var rows: Array = _db_manager().query_rows(LIST_SQL)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_id(continent_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var rows: Array = _db_manager().query_rows(GET_BY_ID_SQL, [continent_id])
	if rows.is_empty():
		return DbResult.fail("Континент не найден")

	return DbResult.ok(_normalize_row(rows[0]))


func search(search_text: String) -> Dictionary:
	# SQLite NOCASE is ASCII-only; filter in GDScript for Cyrillic-safe search.
	var all_result := get_all()
	if not all_result["success"]:
		return all_result

	var needle: String = search_text.strip_edges().to_lower()
	if needle.is_empty():
		return all_result

	var filtered: Array = []
	for row in all_result["data"]:
		var name_text: String = str(row.get("name", "")).to_lower()
		var short_name: String = str(row.get("short_name", "")).to_lower()
		var code: String = str(row.get("code", "")).to_lower()
		if (
			name_text.find(needle) >= 0
			or short_name.find(needle) >= 0
			or code.find(needle) >= 0
		):
			filtered.append(row)

	return DbResult.ok_list(filtered)


func create(data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var prepared := _prepare_payload(data, false)
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if code_exists(payload["code"]):
		return DbResult.fail("Континент с кодом %s уже существует." % payload["code"])

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		INSERT INTO continents (
			name, short_name, code, logo_path, sort_order, is_active, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			payload["name"],
			payload["short_name"],
			payload["code"],
			payload["logo_path"],
			payload["sort_order"],
			payload["is_active"],
			now,
			now,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ContinentRepository] Failed to create continent")
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	var new_id: int = int(_db_manager().get_last_insert_rowid())
	return get_by_id(new_id)


func update(continent_id: int, data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(continent_id)
	if not existing["success"]:
		return existing

	var prepared := _prepare_payload(data, true)
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if code_exists(payload["code"], continent_id):
		return DbResult.fail("Континент с кодом %s уже существует." % payload["code"])

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		UPDATE continents
		SET
			name = ?,
			short_name = ?,
			code = ?,
			logo_path = ?,
			sort_order = ?,
			is_active = ?,
			updated_at = ?
		WHERE id = ?;
		""",
		[
			payload["name"],
			payload["short_name"],
			payload["code"],
			payload["logo_path"],
			payload["sort_order"],
			payload["is_active"],
			now,
			continent_id,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ContinentRepository] Failed to update continent id=%d" % continent_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	return get_by_id(continent_id)


func set_active(continent_id: int, is_active: bool) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(continent_id)
	if not existing["success"]:
		return existing

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"UPDATE continents SET is_active = ?, updated_at = ? WHERE id = ?;",
		[1 if is_active else 0, now, continent_id]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ContinentRepository] Failed to set_active continent id=%d" % continent_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail("Не удалось изменить статус континента.")

	return get_by_id(continent_id)


func delete(continent_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(continent_id)
	if not existing["success"]:
		return existing

	var continent: Dictionary = existing["data"]
	var linked_countries: int = count_countries(continent_id)
	if linked_countries > 0:
		return DbResult.fail(
			"Невозможно удалить континент «%s».\n\nК нему привязано стран: %d.\n\nСначала удалите страны или перенесите их в другой континент."
			% [str(continent.get("name", "")), linked_countries]
		)

	var ok: bool = _db_manager().execute_with_bindings(
		"DELETE FROM continents WHERE id = ?;",
		[continent_id]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ContinentRepository] Failed to delete continent id=%d" % continent_id)
		push_error("SQLite error: %s" % sql_error)
		if sql_error.findn("FOREIGN KEY") >= 0:
			return DbResult.fail(
				"Невозможно удалить континент «%s».\n\nК нему привязаны связанные записи."
				% str(continent.get("name", ""))
			)
		return DbResult.fail("Не удалось удалить континент.")

	return DbResult.ok({"id": continent_id})


func count_countries(continent_id: int) -> int:
	if not _ensure_ready():
		return 0
	var rows: Array = _db_manager().query_rows(
		"SELECT COUNT(*) AS c FROM countries WHERE continent_id = ?;",
		[continent_id]
	)
	if rows.is_empty():
		return 0
	return int(rows[0].get("c", 0))


func code_exists(code: String, exclude_id: int = -1) -> bool:
	if not _ensure_ready():
		return false
	var normalized := ContinentCode.normalize(code)
	if normalized.is_empty():
		return false

	var rows: Array
	if exclude_id >= 0:
		rows = _db_manager().query_rows(
			"SELECT id FROM continents WHERE code = ? AND id != ? LIMIT 1;",
			[normalized, exclude_id]
		)
	else:
		rows = _db_manager().query_rows(
			"SELECT id FROM continents WHERE code = ? LIMIT 1;",
			[normalized]
		)
	return not rows.is_empty()


func _prepare_payload(data: Dictionary, _is_update: bool) -> Dictionary:
	var name := str(data.get("name", "")).strip_edges()
	if name.is_empty():
		return DbResult.fail("Введите название континента.")
	if name.length() > NAME_MAX_LENGTH:
		return DbResult.fail("Название не должно превышать %d символов." % NAME_MAX_LENGTH)

	var short_name := str(data.get("short_name", "")).strip_edges()
	if short_name.length() > SHORT_NAME_MAX_LENGTH:
		return DbResult.fail("Краткое название не должно превышать %d символов." % SHORT_NAME_MAX_LENGTH)

	var code := ContinentCode.normalize(str(data.get("code", "")))
	if code.is_empty():
		return DbResult.fail("Введите системный код.")
	if not ContinentCode.is_valid(code):
		if code[0] >= "0" and code[0] <= "9":
			return DbResult.fail("Системный код не может начинаться с цифры.")
		return DbResult.fail("Системный код содержит недопустимые символы.")

	var sort_order := int(data.get("sort_order", 0))
	var is_active := 1 if bool(data.get("is_active", true)) else 0
	var logo_path = data.get("logo_path", null)
	if logo_path != null:
		logo_path = str(logo_path).strip_edges()
		if logo_path.is_empty():
			logo_path = null

	return DbResult.ok({
		"name": name,
		"short_name": short_name if not short_name.is_empty() else null,
		"code": code,
		"logo_path": logo_path,
		"sort_order": sort_order,
		"is_active": is_active,
	})


func _normalize_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(_normalize_row(row))
	return result


func _normalize_row(row: Dictionary) -> Dictionary:
	return {
		"id": int(row.get("id", 0)),
		"name": str(row.get("name", "")),
		"short_name": str(row.get("short_name", "")) if row.get("short_name", null) != null else "",
		"code": str(row.get("code", "")),
		"logo_path": str(row.get("logo_path", "")) if row.get("logo_path", null) != null else "",
		"sort_order": int(row.get("sort_order", 0)),
		"is_active": int(row.get("is_active", 0)) == 1,
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
		"countries_count": int(row.get("countries_count", 0)),
		"clubs_count": int(row.get("clubs_count", 0)),
	}


func _friendly_sql_error(sql_error: String, code: String) -> String:
	if sql_error.findn("UNIQUE") >= 0 and sql_error.findn("code") >= 0:
		return "Континент с кодом %s уже существует." % code
	return "Не удалось сохранить континент."


func _ensure_ready() -> bool:
	return _db_manager() != null and _db_manager().is_open()


func _now() -> String:
	return Time.get_datetime_string_from_system(true)
