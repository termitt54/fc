class_name CompetitionUnitRepository
extends RefCounted

const NAME_MAX_LENGTH := 100
const FOREIGN_LIMIT_MIN := -1
const FOREIGN_LIMIT_MAX := 99
const DIVISIONS_COUNT_DEFAULT := 2
const TEAMS_PER_DIVISION_DEFAULT := 4
const MATCHES_VS_OWN_DEFAULT := 2
const MATCHES_VS_OTHER_DEFAULT := 0
const POINTS_WIN_DEFAULT := 3
const POINTS_DRAW_DEFAULT := 1
const POINTS_LOSS_DEFAULT := 0
const TEAMS_PROMOTE_DEFAULT := 0
const TEAMS_RELEGATE_DEFAULT := 0
const TEAMS_PLAYOFF_DEFAULT := 0
const REGULAR_SEASON_DEFAULT := false
const SCOPE_OVERALL := "OVERALL"
const SCOPE_PER_DIVISION := "PER_DIVISION"
const MOVEMENT_SCOPE_DEFAULT := SCOPE_PER_DIVISION
const PLAYOFF_SCOPE_DEFAULT := SCOPE_PER_DIVISION
const RULE_COUNT_MAX := 99
const POINTS_MAX := 99
const DIVISION_STRENGTH_MIN := 0
const DIVISION_STRENGTH_MAX := 1000
const DIVISION_STRENGTH_DEFAULT := 800

const SCOPES := [
	SCOPE_OVERALL,
	SCOPE_PER_DIVISION,
]


static func normalize_division_strength(stored: Variant) -> int:
	if typeof(stored) == TYPE_INT or typeof(stored) == TYPE_FLOAT:
		return clampi(int(stored), DIVISION_STRENGTH_MIN, DIVISION_STRENGTH_MAX)
	if typeof(stored) == TYPE_ARRAY:
		if stored.is_empty():
			return DIVISION_STRENGTH_DEFAULT
		return clampi(int(stored[0]), DIVISION_STRENGTH_MIN, DIVISION_STRENGTH_MAX)
	if typeof(stored) != TYPE_STRING:
		return DIVISION_STRENGTH_DEFAULT
	var text := str(stored).strip_edges()
	if text.is_empty() or text == "[]":
		return DIVISION_STRENGTH_DEFAULT
	if text.is_valid_int():
		return clampi(int(text), DIVISION_STRENGTH_MIN, DIVISION_STRENGTH_MAX)
	if not text.begins_with("["):
		return DIVISION_STRENGTH_DEFAULT
	var decoded: Variant = JSON.parse_string(text)
	if typeof(decoded) == TYPE_ARRAY:
		if (decoded as Array).is_empty():
			return DIVISION_STRENGTH_DEFAULT
		return clampi(int((decoded as Array)[0]), DIVISION_STRENGTH_MIN, DIVISION_STRENGTH_MAX)
	if typeof(decoded) == TYPE_FLOAT or typeof(decoded) == TYPE_INT:
		return clampi(int(decoded), DIVISION_STRENGTH_MIN, DIVISION_STRENGTH_MAX)
	return DIVISION_STRENGTH_DEFAULT


static func serialize_division_strength(stored: Variant) -> String:
	return str(normalize_division_strength(stored))


static func per_division_quota(total_teams: int, divisions_count: int) -> int:
	if divisions_count < 1:
		return 0
	return int(total_teams / divisions_count)


static func scope_label(scope_code: String) -> String:
	match scope_code:
		SCOPE_OVERALL:
			return "Общ. табл."
		SCOPE_PER_DIVISION:
			return "Кажд. див."
		_:
			return scope_code


static func normalize_scope(scope_code: Variant, fallback: String = SCOPE_PER_DIVISION) -> String:
	var code := str(scope_code).strip_edges().to_upper()
	if code in SCOPES:
		return code
	return fallback


static func scope_options() -> Array:
	var items: Array = []
	for code in SCOPES:
		items.append({"id": code, "label": scope_label(code)})
	return items


static func quota_hint(total_teams: int, divisions_count: int, scope_code: String) -> String:
	if normalize_scope(scope_code) == SCOPE_OVERALL:
		return "из общ. табл."
	return "по %d/див." % per_division_quota(total_teams, divisions_count)


var _db: Node


func _init(database: Node = null) -> void:
	_db = database


func _db_manager() -> Node:
	if _db != null:
		return _db
	return DatabaseManager


func get_by_competition(competition_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна", [])
	if competition_id < 1:
		return DbResult.ok_list([])

	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			u.id, u.competition_id, u.unit_kind, u.name, u.level,
			u.competition_type, u.foreign_players_limit, u.logo_path,
			u.divisions_count, u.teams_per_division,
			u.matches_vs_own, u.matches_vs_other,
			u.points_win, u.points_draw, u.points_loss,
			u.teams_promote, u.teams_relegate, u.teams_playoff,
			u.ranking_order, u.regular_season_enabled,
			u.movement_scope, u.playoff_scope,
			u.playoff_format, u.playoff_series_wins,
			u.playoff_third_place, u.playoff_seeding, u.prize_rules, u.division_strength,
			u.discipline_enabled, u.card_strictness,
			u.yellow_ban_threshold, u.yellow_ban_matches,
			u.red_ban_matches, u.double_yellow_red, u.yellow_reset,
			u.sort_order, u.created_at, u.updated_at,
			COUNT(uc.club_id) AS clubs_count
		FROM competition_units u
		LEFT JOIN competition_unit_clubs uc ON uc.unit_id = u.id
		WHERE u.competition_id = ?
		GROUP BY u.id
		ORDER BY u.sort_order ASC, u.id ASC;
		""",
		[competition_id]
	)
	return DbResult.ok_list(_normalize_rows(rows))


func get_by_id(unit_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	var rows: Array = _db_manager().query_rows(
		"""
		SELECT
			u.id, u.competition_id, u.unit_kind, u.name, u.level,
			u.competition_type, u.foreign_players_limit, u.logo_path,
			u.divisions_count, u.teams_per_division,
			u.matches_vs_own, u.matches_vs_other,
			u.points_win, u.points_draw, u.points_loss,
			u.teams_promote, u.teams_relegate, u.teams_playoff,
			u.ranking_order, u.regular_season_enabled,
			u.movement_scope, u.playoff_scope,
			u.playoff_format, u.playoff_series_wins,
			u.playoff_third_place, u.playoff_seeding, u.prize_rules, u.division_strength,
			u.discipline_enabled, u.card_strictness,
			u.yellow_ban_threshold, u.yellow_ban_matches,
			u.red_ban_matches, u.double_yellow_red, u.yellow_reset,
			u.sort_order, u.created_at, u.updated_at,
			COUNT(uc.club_id) AS clubs_count
		FROM competition_units u
		LEFT JOIN competition_unit_clubs uc ON uc.unit_id = u.id
		WHERE u.id = ?
		GROUP BY u.id
		LIMIT 1;
		""",
		[unit_id]
	)
	if rows.is_empty():
		return DbResult.fail("Элемент состава не найден")
	return DbResult.ok(_normalize_row(rows[0]))


func create(data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var prepared := _prepare_payload(data)
	if not prepared["success"]:
		return prepared
	var payload: Dictionary = prepared["data"]

	var now := _now()
	var ok: bool = _db_manager().execute_with_bindings(
		"""
		INSERT INTO competition_units (
			competition_id, unit_kind, name, level,
			competition_type, foreign_players_limit, logo_path,
			divisions_count, teams_per_division,
			matches_vs_own, matches_vs_other,
			points_win, points_draw, points_loss,
			teams_promote, teams_relegate, teams_playoff,
			ranking_order, regular_season_enabled,
			movement_scope, playoff_scope,
			playoff_format, playoff_series_wins,
			playoff_third_place, playoff_seeding, prize_rules, division_strength,
			discipline_enabled, card_strictness,
			yellow_ban_threshold, yellow_ban_matches,
			red_ban_matches, double_yellow_red, yellow_reset,
			sort_order, created_at, updated_at
		) VALUES (
			?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?,
			?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
		);
		""",
		[
			payload["competition_id"],
			payload["unit_kind"],
			payload["name"],
			payload["level"],
			payload["competition_type"],
			payload["foreign_players_limit"],
			payload["logo_path"],
			payload["divisions_count"],
			payload["teams_per_division"],
			payload["matches_vs_own"],
			payload["matches_vs_other"],
			payload["points_win"],
			payload["points_draw"],
			payload["points_loss"],
			payload["teams_promote"],
			payload["teams_relegate"],
			payload["teams_playoff"],
			payload["ranking_order"],
			payload["regular_season_enabled"],
			payload["movement_scope"],
			payload["playoff_scope"],
			payload["playoff_format"],
			payload["playoff_series_wins"],
			payload["playoff_third_place"],
			payload["playoff_seeding"],
			payload["prize_rules"],
			payload["division_strength"],
			payload["discipline_enabled"],
			payload["card_strictness"],
			payload["yellow_ban_threshold"],
			payload["yellow_ban_matches"],
			payload["red_ban_matches"],
			payload["double_yellow_red"],
			payload["yellow_reset"],
			payload["sort_order"],
			now,
			now,
		]
	)
	if not ok:
		return DbResult.fail("Не удалось добавить элемент состава.")
	return get_by_id(int(_db_manager().get_last_insert_rowid()))


func update(unit_id: int, data: Dictionary) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")

	var existing := get_by_id(unit_id)
	if not existing["success"]:
		return existing

	var merged: Dictionary = existing["data"].duplicate(true)
	for key in data.keys():
		merged[key] = data[key]

	var prepared := _prepare_payload(merged)
	if not prepared["success"]:
		return prepared
	var payload: Dictionary = prepared["data"]

	var ok: bool = _db_manager().execute_with_bindings(
		"""
		UPDATE competition_units SET
			unit_kind = ?,
			name = ?,
			level = ?,
			competition_type = ?,
			foreign_players_limit = ?,
			logo_path = ?,
			divisions_count = ?,
			teams_per_division = ?,
			matches_vs_own = ?,
			matches_vs_other = ?,
			points_win = ?,
			points_draw = ?,
			points_loss = ?,
			teams_promote = ?,
			teams_relegate = ?,
			teams_playoff = ?,
			ranking_order = ?,
			regular_season_enabled = ?,
			movement_scope = ?,
			playoff_scope = ?,
			playoff_format = ?,
			playoff_series_wins = ?,
			playoff_third_place = ?,
			playoff_seeding = ?,
			prize_rules = ?,
			division_strength = ?,
			discipline_enabled = ?,
			card_strictness = ?,
			yellow_ban_threshold = ?,
			yellow_ban_matches = ?,
			red_ban_matches = ?,
			double_yellow_red = ?,
			yellow_reset = ?,
			sort_order = ?,
			updated_at = ?
		WHERE id = ?;
		""",
		[
			payload["unit_kind"],
			payload["name"],
			payload["level"],
			payload["competition_type"],
			payload["foreign_players_limit"],
			payload["logo_path"],
			payload["divisions_count"],
			payload["teams_per_division"],
			payload["matches_vs_own"],
			payload["matches_vs_other"],
			payload["points_win"],
			payload["points_draw"],
			payload["points_loss"],
			payload["teams_promote"],
			payload["teams_relegate"],
			payload["teams_playoff"],
			payload["ranking_order"],
			payload["regular_season_enabled"],
			payload["movement_scope"],
			payload["playoff_scope"],
			payload["playoff_format"],
			payload["playoff_series_wins"],
			payload["playoff_third_place"],
			payload["playoff_seeding"],
			payload["prize_rules"],
			payload["division_strength"],
			payload["discipline_enabled"],
			payload["card_strictness"],
			payload["yellow_ban_threshold"],
			payload["yellow_ban_matches"],
			payload["red_ban_matches"],
			payload["double_yellow_red"],
			payload["yellow_reset"],
			payload["sort_order"],
			_now(),
			unit_id,
		]
	)
	if not ok:
		return DbResult.fail("Не удалось сохранить элемент состава.")
	return get_by_id(unit_id)


func set_logo(unit_id: int, source_path: String) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	var existing := get_by_id(unit_id)
	if not existing["success"]:
		return existing

	if source_path.is_empty():
		AssetStorage.delete_unit_logo(unit_id)
		return update(unit_id, {"logo_path": ""})

	var stored: Dictionary = AssetStorage.store_unit_logo(source_path, unit_id)
	if not stored["success"]:
		return DbResult.fail(str(stored.get("error", "Не удалось сохранить логотип.")))
	return update(unit_id, {"logo_path": str(stored.get("path", ""))})


func delete(unit_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	var existing := get_by_id(unit_id)
	if not existing["success"]:
		return existing
	AssetStorage.delete_unit_logo(unit_id)
	var ok: bool = _db_manager().execute_with_bindings(
		"DELETE FROM competition_units WHERE id = ?;",
		[unit_id]
	)
	if not ok:
		return DbResult.fail("Не удалось удалить элемент состава.")
	return DbResult.ok({"id": unit_id})


func get_club_ids(unit_id: int) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна", [])
	var rows: Array = _db_manager().query_rows(
		"SELECT club_id FROM competition_unit_clubs WHERE unit_id = ? ORDER BY club_id ASC;",
		[unit_id]
	)
	var ids: Array = []
	for row in rows:
		ids.append(int(row.get("club_id", 0)))
	return DbResult.ok_list(ids)


func set_club_ids(unit_id: int, club_ids: Array) -> Dictionary:
	if not _ensure_ready():
		return DbResult.fail("База данных недоступна")
	var existing := get_by_id(unit_id)
	if not existing["success"]:
		return existing

	if not _db_manager().execute_with_bindings(
		"DELETE FROM competition_unit_clubs WHERE unit_id = ?;",
		[unit_id]
	):
		return DbResult.fail("Не удалось обновить список клубов.")

	var now := _now()
	var unique := {}
	for raw_id in club_ids:
		var club_id: int = int(raw_id)
		if club_id < 1 or unique.has(club_id):
			continue
		unique[club_id] = true
		if not _db_manager().execute_with_bindings(
			"""
			INSERT INTO competition_unit_clubs (unit_id, club_id, created_at)
			VALUES (?, ?, ?);
			""",
			[unit_id, club_id, now]
		):
			return DbResult.fail("Не удалось сохранить выбранные клубы.")

	return get_by_id(unit_id)


func next_sort_order(competition_id: int) -> int:
	var rows: Array = _db_manager().query_rows(
		"SELECT COALESCE(MAX(sort_order), 0) AS m FROM competition_units WHERE competition_id = ?;",
		[competition_id]
	)
	if rows.is_empty():
		return 10
	return int(rows[0].get("m", 0)) + 10


func count_by_kind(competition_id: int, unit_kind: String) -> int:
	var rows: Array = _db_manager().query_rows(
		"SELECT COUNT(*) AS c FROM competition_units WHERE competition_id = ? AND unit_kind = ?;",
		[competition_id, unit_kind]
	)
	if rows.is_empty():
		return 0
	return int(rows[0].get("c", 0))


func _prepare_payload(data: Dictionary) -> Dictionary:
	var competition_id: int = int(data.get("competition_id", 0))
	if competition_id < 1:
		return DbResult.fail("Не выбран турнир.")

	var unit_kind: String = str(data.get("unit_kind", "")).strip_edges().to_upper()
	if not CompetitionTypes.is_valid_unit_kind(unit_kind):
		return DbResult.fail("Некорректный вид элемента состава.")

	var name: String = str(data.get("name", "")).strip_edges()
	if name.is_empty():
		return DbResult.fail("Введите название.")
	if name.length() > NAME_MAX_LENGTH:
		return DbResult.fail("Название не должно превышать %d символов." % NAME_MAX_LENGTH)

	var competition_type: String = str(
		data.get("competition_type", CompetitionTypes.default_type_for_unit(unit_kind))
	).strip_edges().to_upper()
	if not CompetitionTypes.is_valid_type(competition_type):
		return DbResult.fail("Некорректный тип.")

	var logo_path: String = str(data.get("logo_path", "")).strip_edges()

	return DbResult.ok({
		"competition_id": competition_id,
		"unit_kind": unit_kind,
		"name": name,
		"level": maxi(int(data.get("level", 1)), 1),
		"competition_type": competition_type,
		"foreign_players_limit": clampi(
			int(data.get("foreign_players_limit", 0)),
			FOREIGN_LIMIT_MIN,
			FOREIGN_LIMIT_MAX
		),
		"logo_path": logo_path,
		"divisions_count": clampi(int(data.get("divisions_count", DIVISIONS_COUNT_DEFAULT)), 1, RULE_COUNT_MAX),
		"teams_per_division": clampi(int(data.get("teams_per_division", TEAMS_PER_DIVISION_DEFAULT)), 1, RULE_COUNT_MAX),
		"matches_vs_own": clampi(int(data.get("matches_vs_own", MATCHES_VS_OWN_DEFAULT)), 0, RULE_COUNT_MAX),
		"matches_vs_other": clampi(int(data.get("matches_vs_other", MATCHES_VS_OTHER_DEFAULT)), 0, RULE_COUNT_MAX),
		"points_win": clampi(int(data.get("points_win", POINTS_WIN_DEFAULT)), 0, POINTS_MAX),
		"points_draw": clampi(int(data.get("points_draw", POINTS_DRAW_DEFAULT)), 0, POINTS_MAX),
		"points_loss": clampi(int(data.get("points_loss", POINTS_LOSS_DEFAULT)), 0, POINTS_MAX),
		"teams_promote": clampi(int(data.get("teams_promote", TEAMS_PROMOTE_DEFAULT)), 0, RULE_COUNT_MAX),
		"teams_relegate": clampi(int(data.get("teams_relegate", TEAMS_RELEGATE_DEFAULT)), 0, RULE_COUNT_MAX),
		"teams_playoff": clampi(int(data.get("teams_playoff", TEAMS_PLAYOFF_DEFAULT)), 0, RULE_COUNT_MAX),
		"ranking_order": RankingCriteria.serialize(data.get("ranking_order", RankingCriteria.DEFAULT_ORDER)),
		"regular_season_enabled": 1 if bool(data.get("regular_season_enabled", REGULAR_SEASON_DEFAULT)) else 0,
		"movement_scope": normalize_scope(data.get("movement_scope", MOVEMENT_SCOPE_DEFAULT), MOVEMENT_SCOPE_DEFAULT),
		"playoff_scope": normalize_scope(data.get("playoff_scope", PLAYOFF_SCOPE_DEFAULT), PLAYOFF_SCOPE_DEFAULT),
		"playoff_format": PlayoffRules.normalize_format(data.get("playoff_format", PlayoffRules.FORMAT_DEFAULT)),
		"playoff_series_wins": PlayoffRules.normalize_series_wins(
			data.get("playoff_series_wins", PlayoffRules.SERIES_WINS_DEFAULT)
		),
		"playoff_third_place": 1 if bool(data.get("playoff_third_place", PlayoffRules.THIRD_PLACE_DEFAULT)) else 0,
		"playoff_seeding": PlayoffRules.normalize_seeding(data.get("playoff_seeding", PlayoffRules.SEEDING_DEFAULT)),
		"division_strength": serialize_division_strength(data.get("division_strength", DIVISION_STRENGTH_DEFAULT)),
		"prize_rules": PrizeRules.serialize(data.get("prize_rules", {}), {
			"divisions_count": clampi(int(data.get("divisions_count", DIVISIONS_COUNT_DEFAULT)), 1, RULE_COUNT_MAX),
			"teams_per_division": clampi(int(data.get("teams_per_division", TEAMS_PER_DIVISION_DEFAULT)), 1, RULE_COUNT_MAX),
			"teams_playoff": clampi(int(data.get("teams_playoff", TEAMS_PLAYOFF_DEFAULT)), 0, RULE_COUNT_MAX),
			"regular_season_enabled": bool(data.get("regular_season_enabled", REGULAR_SEASON_DEFAULT)),
			"playoff_third_place": bool(data.get("playoff_third_place", PlayoffRules.THIRD_PLACE_DEFAULT)),
		}),
		"discipline_enabled": 1 if bool(data.get("discipline_enabled", DisciplineRules.ENABLED_DEFAULT)) else 0,
		"card_strictness": DisciplineRules.normalize_strictness(
			data.get("card_strictness", DisciplineRules.STRICTNESS_DEFAULT)
		),
		"yellow_ban_threshold": DisciplineRules.normalize_yellow_threshold(
			data.get("yellow_ban_threshold", DisciplineRules.YELLOW_THRESHOLD_DEFAULT)
		),
		"yellow_ban_matches": DisciplineRules.normalize_yellow_ban(
			data.get("yellow_ban_matches", DisciplineRules.YELLOW_BAN_DEFAULT)
		),
		"red_ban_matches": DisciplineRules.normalize_red_ban(
			data.get("red_ban_matches", DisciplineRules.RED_BAN_DEFAULT)
		),
		"double_yellow_red": 1 if bool(
			data.get("double_yellow_red", DisciplineRules.DOUBLE_YELLOW_RED_DEFAULT)
		) else 0,
		"yellow_reset": DisciplineRules.normalize_reset(
			data.get("yellow_reset", DisciplineRules.RESET_DEFAULT)
		),
		"sort_order": int(data.get("sort_order", 0)),
	})


func _normalize_rows(rows: Array) -> Array:
	var result: Array = []
	for row in rows:
		result.append(_normalize_row(row))
	return result


func _normalize_row(row: Dictionary) -> Dictionary:
	return {
		"id": int(row.get("id", 0)),
		"competition_id": int(row.get("competition_id", 0)),
		"unit_kind": str(row.get("unit_kind", "")),
		"name": str(row.get("name", "")),
		"level": int(row.get("level", 1)),
		"competition_type": str(row.get("competition_type", CompetitionTypes.TYPE_LEAGUE)),
		"foreign_players_limit": int(row.get("foreign_players_limit", 0)),
		"logo_path": str(row.get("logo_path", "")) if row.get("logo_path", null) != null else "",
		"divisions_count": int(row.get("divisions_count", DIVISIONS_COUNT_DEFAULT)),
		"teams_per_division": int(row.get("teams_per_division", TEAMS_PER_DIVISION_DEFAULT)),
		"matches_vs_own": int(row.get("matches_vs_own", MATCHES_VS_OWN_DEFAULT)),
		"matches_vs_other": int(row.get("matches_vs_other", MATCHES_VS_OTHER_DEFAULT)),
		"points_win": int(row.get("points_win", POINTS_WIN_DEFAULT)),
		"points_draw": int(row.get("points_draw", POINTS_DRAW_DEFAULT)),
		"points_loss": int(row.get("points_loss", POINTS_LOSS_DEFAULT)),
		"teams_promote": int(row.get("teams_promote", TEAMS_PROMOTE_DEFAULT)),
		"teams_relegate": int(row.get("teams_relegate", TEAMS_RELEGATE_DEFAULT)),
		"teams_playoff": int(row.get("teams_playoff", TEAMS_PLAYOFF_DEFAULT)),
		"ranking_order": RankingCriteria.parse_stored(row.get("ranking_order", null)),
		"regular_season_enabled": int(row.get("regular_season_enabled", 0)) == 1,
		"movement_scope": normalize_scope(row.get("movement_scope", MOVEMENT_SCOPE_DEFAULT), MOVEMENT_SCOPE_DEFAULT),
		"playoff_scope": normalize_scope(row.get("playoff_scope", PLAYOFF_SCOPE_DEFAULT), PLAYOFF_SCOPE_DEFAULT),
		"playoff_format": PlayoffRules.normalize_format(row.get("playoff_format", PlayoffRules.FORMAT_DEFAULT)),
		"playoff_series_wins": PlayoffRules.normalize_series_wins(
			row.get("playoff_series_wins", PlayoffRules.SERIES_WINS_DEFAULT)
		),
		"playoff_third_place": int(row.get("playoff_third_place", 0)) == 1,
		"playoff_seeding": PlayoffRules.normalize_seeding(row.get("playoff_seeding", PlayoffRules.SEEDING_DEFAULT)),
		"division_strength": normalize_division_strength(row.get("division_strength", DIVISION_STRENGTH_DEFAULT)),
		"prize_rules": PrizeRules.parse_stored(row.get("prize_rules", null), {
			"divisions_count": int(row.get("divisions_count", DIVISIONS_COUNT_DEFAULT)),
			"teams_per_division": int(row.get("teams_per_division", TEAMS_PER_DIVISION_DEFAULT)),
			"teams_playoff": int(row.get("teams_playoff", TEAMS_PLAYOFF_DEFAULT)),
			"regular_season_enabled": int(row.get("regular_season_enabled", 0)) == 1,
			"playoff_third_place": int(row.get("playoff_third_place", 0)) == 1,
		}),
		"discipline_enabled": int(row.get("discipline_enabled", 1)) == 1,
		"card_strictness": DisciplineRules.normalize_strictness(
			row.get("card_strictness", DisciplineRules.STRICTNESS_DEFAULT)
		),
		"yellow_ban_threshold": DisciplineRules.normalize_yellow_threshold(
			row.get("yellow_ban_threshold", DisciplineRules.YELLOW_THRESHOLD_DEFAULT)
		),
		"yellow_ban_matches": DisciplineRules.normalize_yellow_ban(
			row.get("yellow_ban_matches", DisciplineRules.YELLOW_BAN_DEFAULT)
		),
		"red_ban_matches": DisciplineRules.normalize_red_ban(
			row.get("red_ban_matches", DisciplineRules.RED_BAN_DEFAULT)
		),
		"double_yellow_red": int(row.get("double_yellow_red", 1)) == 1,
		"yellow_reset": DisciplineRules.normalize_reset(
			row.get("yellow_reset", DisciplineRules.RESET_DEFAULT)
		),
		"sort_order": int(row.get("sort_order", 0)),
		"clubs_count": int(row.get("clubs_count", 0)),
		"created_at": str(row.get("created_at", "")),
		"updated_at": str(row.get("updated_at", "")),
	}


func _ensure_ready() -> bool:
	return _db_manager() != null and _db_manager().is_open()


func _now() -> String:
	return Time.get_datetime_string_from_system(true)
