class_name CompetitionRepository
extends RefCounted

const NAME_MAX_LENGTH := 100
const SHORT_NAME_MAX_LENGTH := 40
const REPUTATION_DEFAULT := 50
const START_SEASON_MIN := 1
const START_SEASON_MAX := 9999

const LIST_SQL := """
SELECT
	competitions.id,
	competitions.name,
	competitions.short_name,
	competitions.code,
	competitions.competition_type,
	competitions.scope_type,
	competitions.continent_id,
	competitions.country_id,
	competitions.periodicity,
	competitions.start_season,
	competitions.age_group,
	competitions.level,
	competitions.reputation,
	competitions.is_active,
	competitions.created_at,
	competitions.updated_at,
	countries.name AS country_name,
	continents.name AS continent_name,
	COUNT(competition_clubs.id) AS clubs_count
FROM competitions
LEFT JOIN countries ON countries.id = competitions.country_id
LEFT JOIN continents ON continents.id = competitions.continent_id
LEFT JOIN competition_clubs ON competition_clubs.competition_id = competitions.id
GROUP BY competitions.id
ORDER BY
	competitions.scope_type ASC,
	countries.name COLLATE NOCASE ASC,
	continents.name COLLATE NOCASE ASC,
	competitions.name COLLATE NOCASE ASC;
"""

const GET_BY_ID_SQL := """
SELECT
	competitions.id,
	competitions.name,
	competitions.short_name,
	competitions.code,
	competitions.competition_type,
	competitions.scope_type,
	competitions.continent_id,
	competitions.country_id,
	competitions.periodicity,
	competitions.start_season,
	competitions.age_group,
	competitions.level,
	competitions.reputation,
	competitions.is_active,
	competitions.created_at,
	competitions.updated_at,
	countries.name AS country_name,
	continents.name AS continent_name,
	COUNT(competition_clubs.id) AS clubs_count
FROM competitions
LEFT JOIN countries ON countries.id = competitions.country_id
LEFT JOIN continents ON continents.id = competitions.continent_id
LEFT JOIN competition_clubs ON competition_clubs.competition_id = competitions.id
WHERE competitions.id = ?
GROUP BY competitions.id
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


func get_by_id(competition_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	var rows: Array = _db_manager().query_rows(GET_BY_ID_SQL, [competition_id])
	if rows.is_empty():
		return DbResult.fail("Турнир не найден")
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
		INSERT INTO competitions (
			name, short_name, code, competition_type, scope_type,
			continent_id, country_id, periodicity, start_season, age_group,
			level, reputation, is_active, created_at, updated_at
		) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
		""",
		[
			payload["name"],
			payload["short_name"],
			payload["code"],
			payload["competition_type"],
			payload["scope_type"],
			payload["continent_id"],
			payload["country_id"],
			payload["periodicity"],
			payload["start_season"],
			payload["age_group"],
			payload["level"],
			payload["reputation"],
			payload["is_active"],
			now,
			now,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CompetitionRepository] Failed to create competition")
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	var new_id: int = int(_db_manager().get_last_insert_rowid())
	var rules_ok := _ensure_default_rules(new_id)
	if not rules_ok["success"]:
		_db_manager().execute_with_bindings("DELETE FROM competitions WHERE id = ?;", [new_id])
		return rules_ok

	return get_by_id(new_id)


func update(competition_id: int, data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(competition_id)
	if not existing["success"]:
		return existing

	var current: Dictionary = existing["data"]
	var prepared := _prepare_payload(data, str(current.get("code", "")))
	if not prepared["success"]:
		return prepared

	var payload: Dictionary = prepared["data"]
	if code_exists(payload["code"], competition_id):
		return DbResult.fail("Турнир с кодом %s уже существует." % payload["code"])

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		UPDATE competitions SET
			name = ?,
			short_name = ?,
			code = ?,
			competition_type = ?,
			scope_type = ?,
			continent_id = ?,
			country_id = ?,
			periodicity = ?,
			start_season = ?,
			age_group = ?,
			level = ?,
			reputation = ?,
			is_active = ?,
			updated_at = ?
		WHERE id = ?;
		""",
		[
			payload["name"],
			payload["short_name"],
			payload["code"],
			payload["competition_type"],
			payload["scope_type"],
			payload["continent_id"],
			payload["country_id"],
			payload["periodicity"],
			payload["start_season"],
			payload["age_group"],
			payload["level"],
			payload["reputation"],
			payload["is_active"],
			now,
			competition_id,
		]
	)
	if not ok:
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CompetitionRepository] Failed to update competition id=%d" % competition_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail(_friendly_sql_error(sql_error, payload["code"]))

	return get_by_id(competition_id)


func delete(competition_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(competition_id)
	if not existing["success"]:
		return existing

	var competition: Dictionary = existing["data"]
	var clubs_count: int = int(competition.get("clubs_count", 0))
	if clubs_count > 0:
		return DbResult.fail(
			"Невозможно удалить турнир «%s».\n\nВ нём состоят клубов: %d.\n\nСначала уберите клубы из турнира."
			% [str(competition.get("name", "")), clubs_count]
		)

	if not _db_manager().execute_with_bindings(
		"DELETE FROM competition_rules WHERE competition_id = ?;",
		[competition_id]
	):
		return DbResult.fail("Не удалось удалить правила турнира.")

	if not _db_manager().execute_with_bindings(
		"DELETE FROM competitions WHERE id = ?;",
		[competition_id]
	):
		var sql_error: String = str(_db_manager().get_last_error())
		push_error("[CompetitionRepository] Failed to delete competition id=%d" % competition_id)
		push_error("SQLite error: %s" % sql_error)
		return DbResult.fail("Не удалось удалить турнир.")

	return DbResult.ok({"id": competition_id})


func code_exists(code: String, exclude_id: int = -1) -> bool:
	if not _ensure_ready():
		return false
	var normalized: String = ContinentCode.normalize(code)
	if normalized.is_empty():
		return false
	var rows: Array
	if exclude_id >= 0:
		rows = _db_manager().query_rows(
			"SELECT id FROM competitions WHERE code = ? AND id != ? LIMIT 1;",
			[normalized, exclude_id]
		)
	else:
		rows = _db_manager().query_rows(
			"SELECT id FROM competitions WHERE code = ? LIMIT 1;",
			[normalized]
		)
	return not rows.is_empty()


func _ensure_default_rules(competition_id: int) -> Dictionary:
	var existing: Array = _db_manager().query_rows(
		"SELECT id FROM competition_rules WHERE competition_id = ? LIMIT 1;",
		[competition_id]
	)
	if not existing.is_empty():
		return DbResult.ok({"competition_id": competition_id})

	var ok: bool = _db_manager().execute_with_bindings(
		"""
		INSERT INTO competition_rules (
			competition_id, teams_count, rounds_between_teams,
			points_for_win, points_for_draw, points_for_loss,
			promotion_places, relegation_places,
			has_playoffs, has_regular_season_champion,
			start_day, match_interval_days
		) VALUES (?, 2, 2, 3, 1, 0, 0, 0, 0, 1, 1, 7);
		""",
		[competition_id]
	)
	if not ok:
		return DbResult.fail("Не удалось создать базовые правила турнира.")
	return DbResult.ok({"competition_id": competition_id})


func _prepare_payload(data: Dictionary, existing_code: String) -> Dictionary:
	var name: String = str(data.get("name", "")).strip_edges()
	if name.is_empty():
		return DbResult.fail("Введите наименование турнира.")
	if name.length() > NAME_MAX_LENGTH:
		return DbResult.fail("Наименование не должно превышать %d символов." % NAME_MAX_LENGTH)

	var short_name: String = str(data.get("short_name", "")).strip_edges()
	if short_name.length() > SHORT_NAME_MAX_LENGTH:
		return DbResult.fail("Краткое название не должно превышать %d символов." % SHORT_NAME_MAX_LENGTH)

	# Type lives on competition_units; keep a legacy default on the card row.
	var competition_type: String = str(data.get("competition_type", CompetitionTypes.TYPE_LEAGUE)).strip_edges().to_upper()
	if not CompetitionTypes.is_valid_type(competition_type):
		competition_type = CompetitionTypes.TYPE_LEAGUE

	var scope_type: String = str(data.get("scope_type", CompetitionTypes.SCOPE_DOMESTIC)).strip_edges().to_upper()
	if scope_type == "CUSTOM":
		scope_type = CompetitionTypes.SCOPE_INTERCONTINENTAL_CLUB
	if not CompetitionTypes.is_valid_scope(scope_type):
		return DbResult.fail("Некорректный формат турнира.")

	var periodicity: String = str(data.get("periodicity", CompetitionTypes.PERIOD_ANNUAL)).strip_edges().to_upper()
	if not CompetitionTypes.is_valid_period(periodicity):
		return DbResult.fail("Некорректная периодичность турнира.")

	var start_season: int = clampi(
		int(data.get("start_season", _default_start_season())),
		START_SEASON_MIN,
		START_SEASON_MAX
	)

	var country_id: int = int(data.get("country_id", 0))
	var continent_id: int = int(data.get("continent_id", 0))
	var age_group = null

	match scope_type:
		CompetitionTypes.SCOPE_DOMESTIC:
			if country_id < 1:
				return DbResult.fail("Выберите страну для национального турнира.")
			continent_id = 0
		CompetitionTypes.SCOPE_CONTINENTAL:
			if continent_id < 1:
				return DbResult.fail("Выберите континент для континентального турнира.")
			country_id = 0
		CompetitionTypes.SCOPE_INTERNATIONAL:
			country_id = 0
			continent_id = 0
			var age_code: String = str(data.get("age_group", CompetitionTypes.AGE_SENIOR)).strip_edges().to_upper()
			if age_code == "MAIN":
				age_code = CompetitionTypes.AGE_SENIOR
			if not CompetitionTypes.is_valid_age_group(age_code):
				return DbResult.fail("Выберите возрастную группу.")
			age_group = age_code
		_:
			country_id = 0
			continent_id = 0

	var code: String = ContinentCode.normalize(existing_code)
	if code.is_empty():
		code = ContinentCode.normalize(str(data.get("code", "")))
	if code.is_empty():
		code = ContinentCode.normalize(short_name if not short_name.is_empty() else name)
	if code.is_empty() or not ContinentCode.is_valid(code):
		code = "COMP_%d" % Time.get_ticks_msec()
		if not ContinentCode.is_valid(code):
			return DbResult.fail("Не удалось сформировать системный код турнира.")

	return DbResult.ok({
		"name": name,
		"short_name": short_name if not short_name.is_empty() else null,
		"code": code,
		"competition_type": competition_type,
		"scope_type": scope_type,
		"continent_id": continent_id if continent_id > 0 else null,
		"country_id": country_id if country_id > 0 else null,
		"periodicity": periodicity,
		"start_season": start_season,
		"age_group": age_group,
		"level": maxi(int(data.get("level", 1)), 1),
		"reputation": clampi(int(data.get("reputation", REPUTATION_DEFAULT)), 1, 100),
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


func _normalize_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(_normalize_row(row))
	return result


func _normalize_row(row: Dictionary) -> Dictionary:
	var scope_type: String = str(row.get("scope_type", CompetitionTypes.SCOPE_DOMESTIC))
	if scope_type == "CUSTOM":
		scope_type = CompetitionTypes.SCOPE_INTERCONTINENTAL_CLUB
	return {
		"id": int(row.get("id", 0)),
		"name": str(row.get("name", "")),
		"short_name": str(row.get("short_name", "")) if row.get("short_name", null) != null else "",
		"code": str(row.get("code", "")),
		"competition_type": str(row.get("competition_type", CompetitionTypes.TYPE_LEAGUE)),
		"scope_type": scope_type,
		"continent_id": int(row.get("continent_id", 0)) if row.get("continent_id", null) != null else 0,
		"country_id": int(row.get("country_id", 0)) if row.get("country_id", null) != null else 0,
		"periodicity": str(row.get("periodicity", CompetitionTypes.PERIOD_ANNUAL)),
		"start_season": int(row.get("start_season", _default_start_season())),
		"age_group": str(row.get("age_group", "")) if row.get("age_group", null) != null else "",
		"level": int(row.get("level", 1)),
		"reputation": int(row.get("reputation", REPUTATION_DEFAULT)),
		"is_active": int(row.get("is_active", 0)) == 1,
		"country_name": str(row.get("country_name", "")) if row.get("country_name", null) != null else "",
		"continent_name": str(row.get("continent_name", "")) if row.get("continent_name", null) != null else "",
		"clubs_count": int(row.get("clubs_count", 0)),
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
	}


func _default_start_season() -> int:
	return 1


func _friendly_sql_error(sql_error: String, code: String) -> String:
	if sql_error.findn("UNIQUE") >= 0 and sql_error.findn("code") >= 0:
		return "Турнир с кодом %s уже существует." % code
	if sql_error.findn("FOREIGN KEY") >= 0:
		return "Указанная страна или континент не существуют."
	return "Не удалось сохранить турнир."


func _ensure_ready() -> bool:
	return _db_manager() != null and _db_manager().is_open()


func _now() -> String:
	return Time.get_datetime_string_from_system(true)
