class_name CountryRepository
extends RefCounted

const NAME_MAX_LENGTH := 100
const ABBREVIATION_MAX_LENGTH := 8
const ABBREVIATION_MIN_LENGTH := 2
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")

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

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			countries.id,
			countries.continent_id,
			countries.name,
			countries.abbreviation,
			countries.flag_path,
			countries.reputation,
			countries.youth_talent,
			countries.created_at,
			countries.updated_at,
			COUNT(clubs.id) AS clubs_count
		FROM countries
		LEFT JOIN clubs ON clubs.country_id = countries.id
		GROUP BY countries.id
		ORDER BY countries.name COLLATE NOCASE ASC;
		"""
	)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_continent(continent_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна", [])
	if continent_id < 1:
		return DbResult.ok_list([])

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			countries.id,
			countries.continent_id,
			countries.name,
			countries.abbreviation,
			countries.flag_path,
			countries.reputation,
			countries.youth_talent,
			countries.created_at,
			countries.updated_at,
			COUNT(clubs.id) AS clubs_count
		FROM countries
		LEFT JOIN clubs ON clubs.country_id = countries.id
		WHERE countries.continent_id = ?
		GROUP BY countries.id
		ORDER BY countries.reputation DESC, countries.name COLLATE NOCASE ASC;
		""",
		[continent_id]
	)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_id(country_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			countries.id,
			countries.continent_id,
			countries.name,
			countries.abbreviation,
			countries.flag_path,
			countries.reputation,
			countries.youth_talent,
			countries.created_at,
			countries.updated_at,
			COUNT(clubs.id) AS clubs_count
		FROM countries
		LEFT JOIN clubs ON clubs.country_id = countries.id
		WHERE countries.id = ?
		GROUP BY countries.id
		LIMIT 1;
		""",
		[country_id]
	)
	if rows.is_empty():
		return DbResult.fail("Страна не найдена")
	return DbResult.ok(_normalize_row(rows[0]))


func create(data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var prepared := _prepare_payload(data)
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if abbreviation_exists(payload["abbreviation"]):
		return DbResult.fail("Страна с аббревиатурой %s уже существует." % payload["abbreviation"])

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		INSERT INTO countries (
			continent_id, name, abbreviation, flag_path, reputation, youth_talent, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			payload["continent_id"],
			payload["name"],
			payload["abbreviation"],
			null,
			payload["reputation"],
			payload["youth_talent"],
			now,
			now,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CountryRepository] Failed to create country")
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["abbreviation"]))

	var new_id: int = int(_db_manager().get_last_insert_rowid())
	var flag_result := _apply_flag(new_id, str(data.get("flag_source_path", "")), "")
	if not flag_result["success"]:
		_db_manager().execute_with_bindings("DELETE FROM countries WHERE id = ?;", [new_id])
		return flag_result

	var names_result := _save_name_pools(new_id, data)
	if not names_result["success"]:
		_db_manager().execute_with_bindings("DELETE FROM countries WHERE id = ?;", [new_id])
		return names_result

	return get_by_id(new_id)


func update(country_id: int, data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(country_id)
	if not existing["success"]:
		return existing

	var prepared := _prepare_payload(data)
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if abbreviation_exists(payload["abbreviation"], country_id):
		return DbResult.fail("Страна с аббревиатурой %s уже существует." % payload["abbreviation"])

	var current: Dictionary = existing["data"]
	var current_flag: String = str(current.get("flag_path", ""))
	var flag_source: String = str(data.get("flag_source_path", ""))
	var clear_flag: bool = bool(data.get("clear_flag", false))

	var next_flag: String = current_flag
	if clear_flag:
		AssetStorage.delete_country_flag(country_id)
		next_flag = ""
	elif not flag_source.is_empty():
		var flag_result := _apply_flag(country_id, flag_source, current_flag)
		if not flag_result["success"]:
			return flag_result
		next_flag = str(flag_result.get("path", ""))

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		UPDATE countries SET
			continent_id = ?,
			name = ?,
			abbreviation = ?,
			flag_path = ?,
			reputation = ?,
			youth_talent = ?,
			updated_at = ?
		WHERE id = ?;
		""",
		[
			payload["continent_id"],
			payload["name"],
			payload["abbreviation"],
			next_flag if not next_flag.is_empty() else null,
			payload["reputation"],
			payload["youth_talent"],
			now,
			country_id,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CountryRepository] Failed to update country id=%d" % country_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["abbreviation"]))

	var names_result := _save_name_pools(country_id, data)
	if not names_result["success"]:
		return names_result

	return get_by_id(country_id)


func delete(country_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(country_id)
	if not existing["success"]:
		return existing

	var country: Dictionary = existing["data"]
	var clubs_count: int = int(country.get("clubs_count", 0))
	if clubs_count > 0:
		return DbResult.fail(
			"Невозможно удалить страну «%s».\n\nК ней привязано клубов: %d.\n\nСначала удалите клубы."
			% [str(country.get("name", "")), clubs_count]
		)

	var ok: bool = _db_manager().execute_with_bindings(
		"DELETE FROM countries WHERE id = ?;",
		[country_id]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CountryRepository] Failed to delete country id=%d" % country_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail("Не удалось удалить страну.")

	AssetStorage.delete_country_flag(country_id)
	return DbResult.ok({"id": country_id})


func abbreviation_exists(abbreviation: String, exclude_id: int = -1) -> bool:
	if not _ensure_ready():
		return false
	var normalized: String = normalize_abbreviation(abbreviation)
	if normalized.is_empty():
		return false
	var rows: Array
	if exclude_id >= 0:
		rows = _db_manager().query_rows(
			"SELECT id FROM countries WHERE abbreviation = ? AND id != ? LIMIT 1;",
			[normalized, exclude_id]
		)
	else:
		rows = _db_manager().query_rows(
			"SELECT id FROM countries WHERE abbreviation = ? LIMIT 1;",
			[normalized]
		)
	return not rows.is_empty()


static func normalize_abbreviation(value: String) -> String:
	var raw := value.strip_edges().to_upper()
	var cleaned := ""
	for i in raw.length():
		var ch := raw[i]
		var code := ch.unicode_at(0)
		var is_az := code >= 65 and code <= 90
		var is_digit := code >= 48 and code <= 57
		if is_az or is_digit:
			cleaned += ch
	return cleaned


func _prepare_payload(data: Dictionary) -> Dictionary:
	var continent_id: int = int(data.get("continent_id", 0))
	if continent_id < 1:
		return DbResult.fail("Не выбран континент.")

	var name: String = str(data.get("name", "")).strip_edges()
	if name.is_empty():
		return DbResult.fail("Введите название страны.")
	if name.length() > NAME_MAX_LENGTH:
		return DbResult.fail("Название не должно превышать %d символов." % NAME_MAX_LENGTH)

	var abbreviation: String = normalize_abbreviation(str(data.get("abbreviation", "")))
	if abbreviation.is_empty():
		return DbResult.fail("Введите аббревиатуру.")
	if abbreviation.length() < ABBREVIATION_MIN_LENGTH:
		return DbResult.fail("Аббревиатура слишком короткая.")
	if abbreviation.length() > ABBREVIATION_MAX_LENGTH:
		return DbResult.fail("Аббревиатура не должна превышать %d символов." % ABBREVIATION_MAX_LENGTH)

	var reputation: int = clampi(int(data.get("reputation", 500)), 0, 1000)
	var youth_talent: int = YouthGenerationConfigScript.clamp_youth_talent(
		int(data.get("youth_talent", YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT))
	)

	return DbResult.ok({
		"continent_id": continent_id,
		"name": name,
		"abbreviation": abbreviation,
		"reputation": reputation,
		"youth_talent": youth_talent,
	})


func _save_name_pools(country_id: int, data: Dictionary) -> Dictionary:
	if not data.has("first_names") and not data.has("last_names"):
		return DbResult.ok()
	var first: Array = data.get("first_names", [])
	var last: Array = data.get("last_names", [])
	if typeof(first) != TYPE_ARRAY:
		first = []
	if typeof(last) != TYPE_ARRAY:
		last = []
	var name_repo := CountryNameRepository.new(_db_manager())
	return name_repo.replace_for_country(country_id, first, last)


func _apply_flag(country_id: int, source_path: String, _current_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": true, "path": "", "error": ""}

	var stored: Dictionary = AssetStorage.store_country_flag(source_path, country_id)
	if not stored["success"]:
		return DbResult.fail(str(stored.get("error", "Не удалось сохранить флаг.")))

	var path: String = str(stored.get("path", ""))
	var ok: bool = _db_manager().execute_with_bindings(
		"UPDATE countries SET flag_path = ?, updated_at = ? WHERE id = ?;",
		[path, _now(), country_id]
	)
	if not ok:
		return DbResult.fail("Не удалось сохранить путь к флагу.")
	return {"success": true, "path": path, "error": ""}


func _normalize_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(_normalize_row(row))
	return result


func _normalize_row(row: Dictionary) -> Dictionary:
	return {
		"id": int(row.get("id", 0)),
		"continent_id": int(row.get("continent_id", 0)),
		"name": str(row.get("name", "")),
		"abbreviation": str(row.get("abbreviation", "")),
		"flag_path": str(row.get("flag_path", "")) if row.get("flag_path", null) != null else "",
		"reputation": int(row.get("reputation", 500)),
		"youth_talent": YouthGenerationConfigScript.clamp_youth_talent(
			int(row.get("youth_talent", YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT))
		),
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
		"clubs_count": int(row.get("clubs_count", 0)),
	}


func _friendly_sql_error(sql_error: String, abbreviation: String) -> String:
	if sql_error.findn("UNIQUE") >= 0:
		return "Страна с аббревиатурой %s уже существует." % abbreviation
	if sql_error.findn("FOREIGN KEY") >= 0:
		return "Указанный континент не существует."
	return "Не удалось сохранить страну."


func _ensure_ready() -> bool:
	return _db_manager() != null and _db_manager().is_open()


func _now() -> String:
	return Time.get_datetime_string_from_system(true)
