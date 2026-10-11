class_name ClubRepository
extends RefCounted

const NAME_MAX_LENGTH := 100
const SHORT_NAME_MAX_LENGTH := 8
const SHORT_NAME_MIN_LENGTH := 2
const FACILITY_DEFAULT := 10
const REPUTATION_DEFAULT := 500


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
			clubs.id, clubs.country_id, clubs.name, clubs.short_name, clubs.code, clubs.logo_path,
			clubs.reputation, clubs.finance_level, clubs.youth_academy, clubs.training_level,
			clubs.scouting_level, clubs.youth_search, clubs.stadium_capacity,
			clubs.primary_color, clubs.secondary_color,
			clubs.is_active, clubs.created_at, clubs.updated_at,
			countries.name AS country_name,
			countries.flag_path AS country_flag_path
		FROM clubs
		LEFT JOIN countries ON countries.id = clubs.country_id
		ORDER BY countries.name COLLATE NOCASE ASC, clubs.name COLLATE NOCASE ASC;
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
			clubs.id, clubs.country_id, clubs.name, clubs.short_name, clubs.code, clubs.logo_path,
			clubs.reputation, clubs.finance_level, clubs.youth_academy, clubs.training_level,
			clubs.scouting_level, clubs.youth_search, clubs.stadium_capacity,
			clubs.primary_color, clubs.secondary_color,
			clubs.is_active, clubs.created_at, clubs.updated_at,
			countries.name AS country_name,
			countries.flag_path AS country_flag_path
		FROM clubs
		INNER JOIN countries ON countries.id = clubs.country_id
		WHERE countries.continent_id = ?
		ORDER BY countries.name COLLATE NOCASE ASC, clubs.name COLLATE NOCASE ASC;
		""",
		[continent_id]
	)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_country(country_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна", [])
	if country_id < 1:
		return DbResult.ok_list([])

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			clubs.id, clubs.country_id, clubs.name, clubs.short_name, clubs.code, clubs.logo_path,
			clubs.reputation, clubs.finance_level, clubs.youth_academy, clubs.training_level,
			clubs.scouting_level, clubs.youth_search, clubs.stadium_capacity,
			clubs.primary_color, clubs.secondary_color,
			clubs.is_active, clubs.created_at, clubs.updated_at,
			countries.name AS country_name,
			countries.flag_path AS country_flag_path
		FROM clubs
		LEFT JOIN countries ON countries.id = clubs.country_id
		WHERE clubs.country_id = ?
		ORDER BY clubs.name COLLATE NOCASE ASC;
		""",
		[country_id]
	)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_id(club_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			clubs.id, clubs.country_id, clubs.name, clubs.short_name, clubs.code, clubs.logo_path,
			clubs.reputation, clubs.finance_level, clubs.youth_academy, clubs.training_level,
			clubs.scouting_level, clubs.youth_search, clubs.stadium_capacity,
			clubs.primary_color, clubs.secondary_color,
			clubs.is_active, clubs.created_at, clubs.updated_at,
			countries.name AS country_name,
			countries.flag_path AS country_flag_path
		FROM clubs
		LEFT JOIN countries ON countries.id = clubs.country_id
		WHERE clubs.id = ?
		LIMIT 1;
		""",
		[club_id]
	)
	if rows.is_empty():
		return DbResult.fail("Клуб не найден")
	return DbResult.ok(_normalize_row(rows[0]))


func create(data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var prepared := _prepare_payload(data, "")
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if code_exists(payload["code"]):
		payload["code"] = _allocate_unique_code(payload["code"])

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		INSERT INTO clubs (
			country_id, name, short_name, code, logo_path,
			reputation, finance_level, youth_academy, training_level,
			scouting_level, youth_search, stadium_capacity,
			primary_color, secondary_color,
			is_active, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			payload["country_id"],
			payload["name"],
			payload["short_name"],
			payload["code"],
			null,
			payload["reputation"],
			payload["finance_level"],
			payload["youth_academy"],
			payload["training_level"],
			payload["scouting_level"],
			payload["youth_search"],
			payload["stadium_capacity"],
			payload["primary_color"],
			payload["secondary_color"],
			payload["is_active"],
			now,
			now,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ClubRepository] Failed to create club")
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	var new_id: int = int(_db_manager().get_last_insert_rowid())
	var logo_result := _apply_logo(new_id, str(data.get("logo_source_path", "")), "")
	if not logo_result["success"]:
		_db_manager().execute_with_bindings("DELETE FROM clubs WHERE id = ?;", [new_id])
		return logo_result

	return get_by_id(new_id)


func update(club_id: int, data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(club_id)
	if not existing["success"]:
		return existing

	var current: Dictionary = existing["data"]
	var prepared := _prepare_payload(data, str(current.get("code", "")))
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if code_exists(payload["code"], club_id):
		return DbResult.fail("Клуб с кодом %s уже существует." % payload["code"])

	var current_logo: String = str(current.get("logo_path", ""))
	var logo_source: String = str(data.get("logo_source_path", ""))
	var clear_logo: bool = bool(data.get("clear_logo", false))

	var next_logo: String = current_logo
	if clear_logo:
		AssetStorage.delete_club_logo(club_id)
		next_logo = ""
	elif not logo_source.is_empty():
		var logo_result := _apply_logo(club_id, logo_source, current_logo)
		if not logo_result["success"]:
			return logo_result
		next_logo = str(logo_result.get("path", ""))

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		UPDATE clubs SET
			country_id = ?,
			name = ?,
			short_name = ?,
			code = ?,
			logo_path = ?,
			reputation = ?,
			finance_level = ?,
			youth_academy = ?,
			training_level = ?,
			scouting_level = ?,
			youth_search = ?,
			stadium_capacity = ?,
			primary_color = ?,
			secondary_color = ?,
			is_active = ?,
			updated_at = ?
		WHERE id = ?;
		""",
		[
			payload["country_id"],
			payload["name"],
			payload["short_name"],
			payload["code"],
			next_logo if not next_logo.is_empty() else null,
			payload["reputation"],
			payload["finance_level"],
			payload["youth_academy"],
			payload["training_level"],
			payload["scouting_level"],
			payload["youth_search"],
			payload["stadium_capacity"],
			payload["primary_color"],
			payload["secondary_color"],
			payload["is_active"],
			now,
			club_id,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ClubRepository] Failed to update club id=%d" % club_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	return get_by_id(club_id)


func delete(club_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(club_id)
	if not existing["success"]:
		return existing

	var club: Dictionary = existing["data"]
	var tournaments := _tournament_names(club_id)
	if not tournaments.is_empty():
		return DbResult.fail(
			"Невозможно удалить клуб «%s».\n\nОн участвует в турнирах: %s.\n\nСначала уберите клуб из турниров."
			% [str(club.get("name", "")), ", ".join(tournaments)]
		)

	var ok: bool = _db_manager().execute_with_bindings(
		"DELETE FROM clubs WHERE id = ?;",
		[club_id]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[ClubRepository] Failed to delete club id=%d" % club_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail("Не удалось удалить клуб.")

	AssetStorage.delete_club_logo(club_id)
	return DbResult.ok({"id": club_id})


func _tournament_names(club_id: int) -> PackedStringArray:
	var seen := {}
	var names := PackedStringArray()
	var queries := [
		"""
		SELECT DISTINCT competitions.name AS name
		FROM competition_unit_clubs
		INNER JOIN competition_units ON competition_units.id = competition_unit_clubs.unit_id
		INNER JOIN competitions ON competitions.id = competition_units.competition_id
		WHERE competition_unit_clubs.club_id = ?
		ORDER BY competitions.name COLLATE NOCASE ASC;
		""",
		"""
		SELECT DISTINCT competitions.name AS name
		FROM competition_clubs
		INNER JOIN competitions ON competitions.id = competition_clubs.competition_id
		WHERE competition_clubs.club_id = ?
		ORDER BY competitions.name COLLATE NOCASE ASC;
		""",
	]
	for sql in queries:
		var rows: Array = _db_manager().query_rows(sql, [club_id])
		for row in rows:
			var name := str(row.get("name", "")).strip_edges()
			if name.is_empty() or seen.has(name):
				continue
			seen[name] = true
			names.append(name)
	return names


func code_exists(code: String, exclude_id: int = -1) -> bool:
	if not _ensure_ready():
		return false
	var normalized: String = ContinentCode.normalize(code)
	if normalized.is_empty():
		return false
	var rows: Array
	if exclude_id >= 0:
		rows = _db_manager().query_rows(
			"SELECT id FROM clubs WHERE code = ? AND id != ? LIMIT 1;",
			[normalized, exclude_id]
		)
	else:
		rows = _db_manager().query_rows(
			"SELECT id FROM clubs WHERE code = ? LIMIT 1;",
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


func _prepare_payload(data: Dictionary, existing_code: String) -> Dictionary:
	var country_id: int = int(data.get("country_id", 0))
	if country_id < 1:
		return DbResult.fail("Не выбрана страна.")

	var name: String = str(data.get("name", "")).strip_edges()
	if name.is_empty():
		return DbResult.fail("Введите название клуба.")
	if name.length() > NAME_MAX_LENGTH:
		return DbResult.fail("Название не должно превышать %d символов." % NAME_MAX_LENGTH)

	var short_name: String = normalize_abbreviation(str(data.get("short_name", "")))
	if short_name.is_empty():
		return DbResult.fail("Введите аббревиатуру.")
	if short_name.length() < SHORT_NAME_MIN_LENGTH:
		return DbResult.fail("Аббревиатура слишком короткая.")
	if short_name.length() > SHORT_NAME_MAX_LENGTH:
		return DbResult.fail("Аббревиатура не должна превышать %d символов." % SHORT_NAME_MAX_LENGTH)

	var code: String = ContinentCode.normalize(existing_code)
	if code.is_empty():
		code = ContinentCode.normalize(short_name)
	if code.is_empty():
		code = ContinentCode.normalize(name)
	if code.is_empty() or not ContinentCode.is_valid(code):
		code = "CLUB_%s" % short_name
		if not ContinentCode.is_valid(code):
			return DbResult.fail("Не удалось сформировать системный код клуба.")

	return DbResult.ok({
		"country_id": country_id,
		"name": name,
		"short_name": short_name,
		"code": code,
		"reputation": clampi(int(data.get("reputation", REPUTATION_DEFAULT)), 0, 1000),
		"finance_level": clampi(int(data.get("finance_level", FACILITY_DEFAULT)), 0, 20),
		"youth_academy": clampi(int(data.get("youth_academy", FACILITY_DEFAULT)), 0, 20),
		"training_level": clampi(int(data.get("training_level", FACILITY_DEFAULT)), 0, 20),
		"scouting_level": clampi(int(data.get("scouting_level", FACILITY_DEFAULT)), 0, 20),
		"youth_search": clampi(int(data.get("youth_search", FACILITY_DEFAULT)), 0, 20),
		"stadium_capacity": maxi(int(data.get("stadium_capacity", 10000)), 0),
		"primary_color": null,
		"secondary_color": null,
		"is_active": 1 if bool(data.get("is_active", true)) else 0,
	})


func _allocate_unique_code(base_code: String) -> String:
	var candidate: String = base_code
	var suffix: int = 2
	while code_exists(candidate):
		candidate = "%s_%d" % [base_code, suffix]
		suffix += 1
		if suffix > 9999:
			return "%s_%d" % [base_code, Time.get_ticks_msec()]
	return candidate


func _apply_logo(club_id: int, source_path: String, _current_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": true, "path": "", "error": ""}

	var stored: Dictionary = AssetStorage.store_club_logo(source_path, club_id)
	if not stored["success"]:
		return DbResult.fail(str(stored.get("error", "Не удалось сохранить логотип.")))

	var path: String = str(stored.get("path", ""))
	var ok: bool = _db_manager().execute_with_bindings(
		"UPDATE clubs SET logo_path = ?, updated_at = ? WHERE id = ?;",
		[path, _now(), club_id]
	)
	if not ok:
		return DbResult.fail("Не удалось сохранить путь к логотипу.")
	return {"success": true, "path": path, "error": ""}


func _normalize_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(_normalize_row(row))
	return result


func _normalize_row(row: Dictionary) -> Dictionary:
	return {
		"id": int(row.get("id", 0)),
		"country_id": int(row.get("country_id", 0)),
		"name": str(row.get("name", "")),
		"short_name": str(row.get("short_name", "")) if row.get("short_name", null) != null else "",
		"code": str(row.get("code", "")),
		"logo_path": str(row.get("logo_path", "")) if row.get("logo_path", null) != null else "",
		"reputation": int(row.get("reputation", REPUTATION_DEFAULT)),
		"finance_level": int(row.get("finance_level", FACILITY_DEFAULT)),
		"youth_academy": int(row.get("youth_academy", FACILITY_DEFAULT)),
		"training_level": int(row.get("training_level", FACILITY_DEFAULT)),
		"scouting_level": int(row.get("scouting_level", FACILITY_DEFAULT)),
		"youth_search": int(row.get("youth_search", FACILITY_DEFAULT)),
		"stadium_capacity": int(row.get("stadium_capacity", 10000)),
		"is_active": int(row.get("is_active", 0)) == 1,
		"country_name": str(row.get("country_name", "")) if row.get("country_name", null) != null else "",
		"country_flag_path": str(row.get("country_flag_path", "")) if row.get("country_flag_path", null) != null else "",
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
	}


func _friendly_sql_error(sql_error: String, code: String) -> String:
	if sql_error.findn("UNIQUE") >= 0 and sql_error.findn("code") >= 0:
		return "Клуб с кодом %s уже существует." % code
	if sql_error.findn("FOREIGN KEY") >= 0:
		return "Указанная страна не существует."
	return "Не удалось сохранить клуб."


func _ensure_ready() -> bool:
	return _db_manager() != null and _db_manager().is_open()


func _now() -> String:
	return Time.get_datetime_string_from_system(true)
