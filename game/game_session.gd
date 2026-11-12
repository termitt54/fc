extends Node

const NationalRatingScript = preload("res://game/national_rating.gd")
const ClubRatingScript = preload("res://game/club_rating.gd")
## Runtime new-game session: season clock + loaded tournament units.


const SeasonBuilderScript := preload("res://game/season_builder.gd")
const LeagueMovementScript := preload("res://game/league_movement.gd")
const MatchDayScript := preload("res://game/match_day.gd")
const MatchRatingsScript := preload("res://game/match_ratings.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const PlayerStatsScript := preload("res://game/player_stats.gd")
const UnitSeasonStatsScript := preload("res://game/unit_season_stats.gd")
const CareerArchiveScript := preload("res://game/career_archive.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")
const PlayoffManagerScript := preload("res://game/playoff_manager.gd")
const FixtureGeneratorScript := preload("res://game/fixture_generator.gd")
const YouthIntakeScript := preload("res://game/youth_intake.gd")
const PlayerDevelopmentScript := preload("res://game/player_development.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")
const YouthGraduationScript := preload("res://game/youth_graduation.gd")
const TransferMarketScript := preload("res://game/transfer_market.gd")
const SeasonPreviewScript := preload("res://game/season_preview.gd")
const SeasonReputationScript := preload("res://game/season_reputation.gd")
const ClubFinanceScript := preload("res://game/club_finance.gd")
const PrizeRulesScript := preload("res://database/repositories/world/prize_rules.gd")
const ContractRenewalScript := preload("res://game/contract_renewal.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const SaveStoreScript := preload("res://game/save_store.gd")
const HistoryStoreScript := preload("res://game/history_store.gd")
const SimulationWorkScript := preload("res://game/simulation_work.gd")
const TransferMarketJobScript := preload("res://game/transfer_market_job.gd")

const CoachMarketScript := preload("res://game/coach_market.gd")

const SAVE_VERSION := 15
const DEFAULT_SLOT := "autosave"
const MARKET_OPEN_DAY := -5
const MARKET_LAST_DAY := -1
const FIRST_MATCH_DAY := 1
const STATUS_FREE_AGENT := "free_agent"
const STATUS_CLUB := "club"

signal session_changed
signal selection_changed
signal processing_changed
signal simulation_progress(stage: String, done: int, total: int)

var is_processing := false
var last_work_profile: Dictionary = {}

var season_number: int = 1
var season_day: int = MARKET_OPEN_DAY
var season_total_days: int = 1
var units: Array = []
var selected_unit_id: int = 0
var players_by_club: Dictionary = {}
var youth_players_by_club: Dictionary = {}
var reserve_players_by_club: Dictionary = {}
var free_agents: Array = []
var coaches_by_club: Dictionary = {}
var coach_market: Dictionary = {}
var national_teams: Dictionary = {}
var _national_player_index: Dictionary = {}
var club_budgets: Dictionary = {}
var wages_paid_for_season: int = 0
var transfer_log: Array = []
var last_error: String = ""
var is_active: bool = false
var season_finished: bool = false
var save_slot: String = DEFAULT_SLOT
var retired_players: Array = []
var history_head: int = 0
var _pending_history: Array = []
var _career_stats_cache_key := ""
var _career_stats_history: Dictionary = {}
## Transient diagnostics, never saved or used by simulation decisions.
var last_market_profile: Dictionary = {}
var market_planner_cache: Dictionary = {} # Transient window data, never serialized.
var last_day_profile: Dictionary = {}
var last_new_season_profile: Dictionary = {}

var _rng := RandomNumberGenerator.new()
var _next_match_id: int = 1
var _next_player_id: int = 1
var _next_coach_id: int = 1


func start_new_game(seed_override: int = -1) -> Dictionary:
	market_planner_cache.clear()
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	last_error = ""
	history_head = 0
	_pending_history.clear()
	_career_stats_cache_key = ""
	_career_stats_history = {}
	save_slot = DEFAULT_SLOT
	if seed_override >= 0:
		_rng.seed = seed_override
	else:
		_rng.randomize()
	var built: Dictionary = SeasonBuilderScript.new().build_new_game(_rng)
	if not built["success"]:
		last_error = str(built.get("error", "Не удалось начать игру"))
		is_active = false
		units.clear()
		players_by_club.clear()
		youth_players_by_club.clear()
		reserve_players_by_club.clear()
		free_agents.clear()
		coaches_by_club.clear()
		coach_market.clear()
		national_teams.clear()
		_national_player_index.clear()
		club_budgets.clear()
		wages_paid_for_season = 0
		transfer_log.clear()
		selected_unit_id = 0
		season_finished = false
		session_changed.emit()
		return built

	var data: Dictionary = built["data"]
	season_number = int(data.get("season_number", 1))
	season_day = int(data.get("season_day", MARKET_OPEN_DAY))
	units = data.get("units", [])
	players_by_club = _coerce_club_player_map(data.get("players_by_club", {}))
	youth_players_by_club = _coerce_club_player_map(data.get("youth_players_by_club", {}))
	reserve_players_by_club = _coerce_club_player_map(data.get("reserve_players_by_club", {}))
	free_agents = _coerce_player_list(data.get("free_agents", []))
	coaches_by_club = _coerce_club_coach_map(data.get("coaches_by_club", {}))
	coach_market = {}
	national_teams = {}
	_national_player_index.clear()
	club_budgets.clear()
	wages_paid_for_season = 0
	transfer_log.clear()
	retired_players.clear()
	_migrate_loaded_players(players_by_club)
	_migrate_loaded_players(youth_players_by_club)
	_migrate_loaded_players(reserve_players_by_club)
	_migrate_player_list(free_agents)
	_seed_club_budgets()
	_next_player_id = int(data.get("next_player_id", _max_player_id() + 1))
	_next_coach_id = int(data.get("next_coach_id", _max_coach_id() + 1))
	selected_unit_id = int(units[0].get("id", 0)) if not units.is_empty() else 0
	_next_match_id = _max_match_id() + 1
	season_finished = false
	_recompute_season_length()
	is_active = true
	ClubRatingScript.ensure(self)
	_begin_calendar_day()
	NationalTeams.ensure(self)
	session_changed.emit()
	selection_changed.emit()
	return DbResult.ok({
		"season_number": season_number,
		"season_day": season_day,
		"units_count": units.size(),
	})


func clear() -> void:
	market_planner_cache.clear()
	if is_processing:
		return
	last_work_profile.clear()
	last_market_profile.clear()
	last_day_profile.clear()
	last_new_season_profile.clear()
	history_head = 0
	_pending_history.clear()
	_career_stats_cache_key = ""
	_career_stats_history = {}
	is_active = false
	season_number = 1
	season_day = MARKET_OPEN_DAY
	season_total_days = 1
	units.clear()
	players_by_club.clear()
	youth_players_by_club.clear()
	reserve_players_by_club.clear()
	free_agents.clear()
	coaches_by_club.clear()
	coach_market.clear()
	national_teams.clear()
	_national_player_index.clear()
	club_budgets.clear()
	wages_paid_for_season = 0
	transfer_log.clear()
	retired_players.clear()
	selected_unit_id = 0
	last_error = ""
	season_finished = false
	save_slot = DEFAULT_SLOT
	session_changed.emit()
	selection_changed.emit()


func list_saves() -> Dictionary:
	var stored: Dictionary = SaveStoreScript.new().list_slots()
	if not stored["success"]:
		return stored
	var items: Array = stored.get("data", [])
	var known: Dictionary = {}
	for item in items:
		if typeof(item) == TYPE_DICTIONARY:
			known[str(item.get("slot", ""))] = true
	items.append_array(_legacy_json_entries(known))
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var stamp_a := str(a.get("saved_at", ""))
		var stamp_b := str(b.get("saved_at", ""))
		if stamp_a == stamp_b:
			return str(a.get("slot", "")) < str(b.get("slot", ""))
		return stamp_a > stamp_b
	)
	return DbResult.ok_list(items)


func save_game(slot_name: String = "") -> Dictionary:
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	if not is_active:
		return DbResult.fail("Нет активной игры для сохранения")
	var slot := slot_name.strip_edges()
	if slot.is_empty():
		slot = save_slot
	if not SaveStoreScript.is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	var history_written: Dictionary = _flush_history()
	if not history_written["success"]:
		return history_written
	if _next_match_id < 1:
		_next_match_id = _max_match_id() + 1
	_strip_rating_caches()
	var meta := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"season_number": season_number,
		"season_day": season_day,
		"season_total_days": season_total_days,
		"selected_unit_id": selected_unit_id,
		"season_finished": season_finished,
		"wages_paid_for_season": wages_paid_for_season,
		"next_player_id": _next_player_id,
		"next_coach_id": _next_coach_id,
		"next_match_id": _next_match_id,
		"rng_seed": _rng.seed,
		"rng_state": _rng.state,
		"player_count": _count_saved_players(),
		"unit_count": units.size(),
		"history_head": history_head,
	}
	var sections := {
		"units": units,
		"players_by_club": players_by_club,
		"youth_players_by_club": youth_players_by_club,
		"reserve_players_by_club": reserve_players_by_club,
		"free_agents": free_agents,
		"coaches_by_club": coaches_by_club,
		"coach_market": coach_market,
		"national_teams": national_teams,
		"club_budgets": club_budgets,
		"transfer_log": transfer_log,
	}
	var written: Dictionary = SaveStoreScript.new().write_slot(slot, meta, sections)
	if not written["success"]:
		return written
	save_slot = slot
	return DbResult.ok({"slot": slot})


func load_game(slot_name: String = "") -> Dictionary:
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	var slot := slot_name.strip_edges()
	if slot.is_empty():
		slot = save_slot
	if not SaveStoreScript.is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")

	var stored: Dictionary = SaveStoreScript.new().load_slot(slot)
	if stored["success"]:
		var prepared: Dictionary = _prepare_legacy_history(slot, stored["data"])
		if not prepared["success"]:
			return prepared
		var applied: Dictionary = apply_save_payload(stored["data"])
		if applied["success"]:
			save_slot = slot
		return applied
	if str(stored.get("error", "")) != SaveStoreScript.ERR_NOT_FOUND:
		return stored

	var legacy := _read_legacy_json(slot)
	if not legacy["success"]:
		return legacy
	var prepared_legacy: Dictionary = _prepare_legacy_history(slot, legacy["data"])
	if not prepared_legacy["success"]:
		return prepared_legacy
	var applied_legacy: Dictionary = apply_save_payload(legacy["data"])
	if not applied_legacy["success"]:
		return applied_legacy
	save_slot = slot
	var migrated := save_game(slot)
	if migrated["success"]:
		_remove_file("user://saves/%s.json" % slot)
	return applied_legacy if migrated["success"] else migrated


func delete_save(slot_name: String) -> Dictionary:
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	var slot := slot_name.strip_edges()
	if not SaveStoreScript.is_valid_slot(slot):
		return DbResult.fail("Некорректное имя сохранения")
	var removed: Dictionary = SaveStoreScript.new().delete_slot(slot)
	if not removed["success"]:
		return removed
	_remove_file("user://saves/%s.json" % slot)
	_remove_file("user://saves/%s_history.db" % slot)
	_remove_file("user://saves/%s_history.db-wal" % slot)
	_remove_file("user://saves/%s_history.db-shm" % slot)
	return DbResult.ok({"slot": slot})


func apply_save_payload(payload: Dictionary) -> Dictionary:
	market_planner_cache.clear()
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	var version := int(payload.get("version", 0))
	if version > SAVE_VERSION or version < 0:
		return DbResult.fail("Неподдерживаемая версия сохранения")
	for section in ["units", "free_agents", "transfer_log"]:
		if payload.has(section) and typeof(payload[section]) != TYPE_ARRAY:
			return DbResult.fail("Повреждённое сохранение: секция %s" % section)
	for section in ["players_by_club", "youth_players_by_club", "reserve_players_by_club", "coaches_by_club", "club_budgets", "coach_market", "national_teams"]:
		if payload.has(section) and typeof(payload[section]) != TYPE_DICTIONARY:
			return DbResult.fail("Повреждённое сохранение: секция %s" % section)
	var national_raw: Dictionary = payload.get("national_teams", {})
	for raw_team in national_raw.values():
		if typeof(raw_team) != TYPE_DICTIONARY:
			return DbResult.fail("Повреждённое сохранение: сборная")
		for key in ["country", "coach", "discipline"]:
			if typeof(raw_team.get(key, {})) != TYPE_DICTIONARY:
				return DbResult.fail("Повреждённое сохранение: данные сборной")
		for key in ["squad_ids", "withdrawn_ids"]:
			if typeof(raw_team.get(key, [])) != TYPE_ARRAY:
				return DbResult.fail("Повреждённое сохранение: заявка сборной")
	var market_raw: Dictionary = payload.get("coach_market", {})
	for pool in ["free", "retired", "events"]:
		if typeof(market_raw.get(pool, [])) != TYPE_ARRAY:
			return DbResult.fail("Повреждённое сохранение: рынок тренеров")
		for row in market_raw.get(pool, []):
			if typeof(row) != TYPE_DICTIONARY:
				return DbResult.fail("Повреждённое сохранение: запись рынка тренеров")
	if typeof(market_raw.get("expectations", {})) != TYPE_DICTIONARY:
		return DbResult.fail("Повреждённое сохранение: ожидания клубов")
	if int(payload.get("history_head", 0)) < 0:
		return DbResult.fail("Повреждённое сохранение: версия истории")
	last_error = ""
	history_head = int(payload.get("history_head", 0))
	_pending_history.clear()
	retired_players.clear()
	var native := bool(payload.get("_native", false)) and version >= 13
	season_number = int(payload.get("season_number", 1))
	season_day = int(payload.get("season_day", MARKET_OPEN_DAY))
	season_total_days = int(payload.get("season_total_days", 1))
	selected_unit_id = int(payload.get("selected_unit_id", 0))
	season_finished = bool(payload.get("season_finished", false))
	if native:
		units = payload.get("units", [])
		players_by_club = payload.get("players_by_club", {})
		youth_players_by_club = payload.get("youth_players_by_club", {})
		reserve_players_by_club = payload.get("reserve_players_by_club", {})
		free_agents = payload.get("free_agents", [])
		coaches_by_club = payload.get("coaches_by_club", {})
		club_budgets = payload.get("club_budgets", {})
		transfer_log = payload.get("transfer_log", [])
		wages_paid_for_season = int(payload.get("wages_paid_for_season", 0))
		_next_match_id = int(payload.get("next_match_id", 0))
		if _next_match_id < 1:
			_next_match_id = _max_match_id() + 1
	else:
		units = payload.get("units", [])
		players_by_club = _coerce_club_player_map(payload.get("players_by_club", {}))
		youth_players_by_club = _coerce_club_player_map(payload.get("youth_players_by_club", {}))
		reserve_players_by_club = _coerce_club_player_map(payload.get("reserve_players_by_club", {}))
		free_agents = _coerce_player_list(payload.get("free_agents", []))
		coaches_by_club = _coerce_club_coach_map(payload.get("coaches_by_club", {}))
		club_budgets = ClubFinanceScript.coerce_budgets(payload.get("club_budgets", {}))
		transfer_log = _coerce_player_list(payload.get("transfer_log", []))
		_migrate_loaded_coaches()
		if payload.has("wages_paid_for_season"):
			wages_paid_for_season = int(payload.get("wages_paid_for_season", 0))
		elif season_day >= FIRST_MATCH_DAY:
			wages_paid_for_season = season_number
		else:
			wages_paid_for_season = 0
		_next_match_id = _max_match_id() + 1
	# Native section storage can still contain players from an older model.
	_migrate_loaded_players(players_by_club)
	_migrate_loaded_players(youth_players_by_club)
	_migrate_loaded_players(reserve_players_by_club)
	_migrate_player_list(free_agents)
	if version < 15:
		_migrate_twenty_player_rosters()
	national_teams = _coerce_club_coach_map(payload.get("national_teams", {}))
	coach_market = payload.get("coach_market", {}).duplicate(true)
	coach_market["expectations"] = _coerce_club_coach_map(coach_market.get("expectations", {}))
	CoachMarketScript.ensure(self)
	_ensure_club_budgets()
	_next_player_id = int(payload.get("next_player_id", _max_player_id() + 1))
	_next_coach_id = maxi(int(payload.get("next_coach_id", 1)), _max_coach_id() + 1)
	if payload.has("rng_seed"):
		_rng.seed = int(payload.get("rng_seed", 0))
	if payload.has("rng_state"):
		_rng.state = int(payload.get("rng_state", _rng.state))
	for team in national_teams.values():
		team["discipline"] = _coerce_club_coach_map(team.get("discipline", {}))
	CoachMarketScript.initialize_loaded_pool(self)
	NationalTeams.ensure(self)
	ClubRatingScript.ensure(self)
	is_active = true
	session_changed.emit()
	selection_changed.emit()
	return DbResult.ok({
		"season_number": season_number,
		"version": version,
	})


func get_unit_options() -> Array:
	var items: Array = []
	for unit in units:
		items.append({
			"id": int(unit.get("id", 0)),
			"label": str(unit.get("label", unit.get("name", ""))),
		})
	return items


func get_selected_unit() -> Dictionary:
	for unit in units:
		if int(unit.get("id", 0)) == selected_unit_id:
			return unit
	if not units.is_empty():
		return units[0]
	return {}


func select_unit(unit_id: int) -> void:
	if unit_id == selected_unit_id:
		return
	for unit in units:
		if int(unit.get("id", 0)) == unit_id:
			selected_unit_id = unit_id
			selection_changed.emit()
			return


func club_name(unit: Dictionary, club_id: int, short: bool = false) -> String:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	var club: Dictionary = clubs.get(club_id, {})
	if club.is_empty():
		club = get_club_identity(club_id)
	if club.is_empty():
		return "Клуб #%d" % club_id
	if short:
		var short_name: String = str(club.get("short_name", "")).strip_edges()
		if not short_name.is_empty():
			return short_name
	return str(club.get("name", "Клуб #%d" % club_id))


func get_club_players(club_id: int) -> Array:
	if NationalTeams.is_team(club_id):
		return NationalTeams.roster(self, club_id)
	if players_by_club.has(club_id):
		return players_by_club[club_id]
	return []


func get_club_youth_players(club_id: int) -> Array:
	if youth_players_by_club.has(club_id):
		return youth_players_by_club[club_id]
	return []


func get_club_reserve_players(club_id: int) -> Array:
	if reserve_players_by_club.has(club_id):
		return reserve_players_by_club[club_id]
	return []


func get_club_coach(club_id: int) -> Dictionary:
	if NationalTeams.is_team(club_id):
		return (national_teams.get(club_id - NationalTeams.TEAM_ID_BASE, {}) as Dictionary).get("coach", {})
	if coaches_by_club.has(club_id):
		var coach: Variant = coaches_by_club[club_id]
		if typeof(coach) == TYPE_DICTIONARY:
			return coach
	return {}


func get_club_budget(club_id: int) -> int:
	return int(club_budgets.get(club_id, 0))


func get_club_wage_bill(club_id: int) -> int:
	return ClubFinanceScript.wage_bill(
		get_club_players(club_id),
		get_club_youth_players(club_id) + get_club_reserve_players(club_id),
		get_club_coach(club_id)
	)


func adjust_club_budget(club_id: int, delta: int) -> int:
	if club_id < 1:
		return 0
	var next := int(club_budgets.get(club_id, 0)) + delta
	club_budgets[club_id] = next
	return next


func get_coach(coach_id: int) -> Dictionary:
	for team in national_teams.values():
		var coach: Dictionary = team.get("coach", {})
		if int(coach.get("id", 0)) == coach_id:
			return coach
	if coach_id < 1:
		return {}
	for club_id in coaches_by_club.keys():
		var coach: Variant = coaches_by_club[club_id]
		if typeof(coach) != TYPE_DICTIONARY:
			continue
		if int(coach.get("id", 0)) == coach_id:
			return coach
	for pool in ["free", "retired"]:
		for coach in coach_market.get(pool, []):
			if int(coach.get("id", 0)) == coach_id:
				return coach
	return {}


func get_player(player_id: int) -> Dictionary:
	if player_id < 1:
		return {}
	for player in free_agents:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if int(player.get("id", 0)) == player_id:
			return player
	var found := _find_player_in_map(players_by_club, player_id)
	if not found.is_empty():
		return found
	found = _find_player_in_map(reserve_players_by_club, player_id)
	if not found.is_empty():
		return found
	return _find_player_in_map(youth_players_by_club, player_id)


func get_all_player_rows() -> Array:
	var clubs := _collect_session_clubs()
	var countries := _countries_by_id()
	var rows: Array = []
	_append_free_agent_rows(rows, countries)
	_append_player_rows(rows, players_by_club, clubs, countries, false)
	_append_player_rows(rows, reserve_players_by_club, clubs, countries, false)
	_append_player_rows(rows, youth_players_by_club, clubs, countries, true)
	return rows


## Profile lookup only: retired players must never re-enter simulation pools.
## Query one indexed record in the current history branch, not the whole archive.
func get_player_profile(player_id: int) -> Dictionary:
	var active := get_player(player_id)
	if not active.is_empty() or player_id < 1:
		return active
	for record in _pending_history:
		if int(record.get("identity", {}).get("player_id", 0)) == player_id:
			return _archived_profile(record["identity"], record.get("player", {}), record.get("seasons", []))
	if history_head <= 0:
		return {}
	var archive := CareerArchiveScript.new()
	if not archive.open_head(history_head):
		return {}
	var identity: Dictionary = archive.get_player(player_id)
	var seasons: Array = archive.seasons_of(player_id) if not identity.is_empty() else []
	archive.close()
	if identity.is_empty():
		return {}
	return _archived_profile(identity, identity.get("snapshot", {}), seasons)


func _archived_profile(identity: Dictionary, snapshot: Dictionary, seasons: Array) -> Dictionary:
	var profile := snapshot.duplicate(true)
	if profile.is_empty():
		profile = identity.duplicate(true)
		profile.erase("snapshot")
		profile["id"] = int(identity.get("player_id", 0))
		profile["club_id"] = int(identity.get("final_club_id", 0))
		profile["career_stats"] = seasons.duplicate(true)
	profile["is_retired"] = true
	profile["retired_season"] = int(identity.get("retired_season", 0))
	return profile


## Historical clubs can now participate in a different league.
func get_club_identity(club_id: int) -> Dictionary:
	if NationalTeams.is_team(club_id):
		var country: Dictionary = national_teams.get(club_id - NationalTeams.TEAM_ID_BASE, {}).get("country", {})
		return NationalTeams.identity(country) if not country.is_empty() else {}
	for unit in units:
		var clubs: Dictionary = unit.get("clubs_by_id", {})
		if clubs.has(club_id):
			return clubs[club_id]
	if club_id > 0 and WorldDatabase.is_ready():
		var result: Dictionary = ClubRepository.new().get_by_id(club_id)
		if result.get("success", false):
			return result.get("data", {})
	return {}


func get_market_player_rows() -> Array:
	var countries := _countries_by_id()
	var rows: Array = []
	_append_listed_player_rows(rows, countries)
	_append_free_agent_rows(rows, countries)
	return rows


## One row per club: full name, country, reputation, squad ratings and budget.
func get_club_rows() -> Array:
	var clubs := _collect_session_clubs()
	var countries := _countries_by_id()
	var rows: Array = []
	for club_id in clubs.keys():
		var id := int(club_id)
		var club: Dictionary = clubs[id] if typeof(clubs[id]) == TYPE_DICTIONARY else {}
		var country_id := int(club.get("country_id", 0))
		var country: Dictionary = countries.get(country_id, {})
		var country_name := str(country.get("name", "")).strip_edges()
		if country_name.is_empty() and country_id > 0:
			country_name = "Страна #%d" % country_id
		var name := str(club.get("name", "")).strip_edges()
		if name.is_empty():
			name = "Клуб #%d" % id
		var rating := _club_player_rating(id)
		rows.append({
			"id": id,
			"name": name,
			"logo_path": str(club.get("logo_path", "")),
			"country_id": country_id,
			"country_name": country_name,
			"flag_path": str(country.get("flag_path", "")),
			"reputation": int(club.get("reputation", 0)),
			"strength_total": int(rating["total"]),
			"strength_avg": float(rating["average"]),
			"player_count": int(rating["count"]),
			"budget": get_club_budget(id),
		})
	return rows


func _club_player_rating(club_id: int) -> Dictionary:
	var total := 0
	var count := 0
	for pool in [get_club_players(club_id), get_club_reserve_players(club_id), get_club_youth_players(club_id)]:
		for player in pool:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			total += int(player.get("current_ability", player.get("overall", 0)))
			count += 1
	return {
		"total": total,
		"average": 0.0 if count == 0 else float(total) / float(count),
		"count": count,
	}


func get_club_transfers(club_id: int) -> Array:
	var rows: Array = []
	if club_id < 1:
		return rows
	for entry in transfer_log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("club_id", 0)) != club_id:
			continue
		rows.append(entry)
	rows.reverse()
	return rows


func get_player_transfers(player_id: int) -> Array:
	var rows: Array = []
	if player_id < 1:
		return rows
	for entry in transfer_log:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("player_id", 0)) != player_id:
			continue
		rows.append(entry)
	return rows


func _begin_calendar_day() -> void:
	if season_day == MARKET_OPEN_DAY:
		CoachMarketScript.open_market(self, _rng)
	if season_day == FIRST_MATCH_DAY:
		CoachMarketScript.prepare(self, _rng)
	last_market_profile = {}
	if is_market_day(season_day):
		var result: Dictionary
		result = TransferMarketScript.run_day(self, _rng)
		last_market_profile = result.get("profile", {})


func _begin_calendar_day_async(work: RefCounted) -> void:
	if season_day == MARKET_OPEN_DAY:
		CoachMarketScript.open_market(self, _rng)
	if season_day == FIRST_MATCH_DAY:
		CoachMarketScript.prepare(self, _rng)
	last_market_profile = {}
	if is_market_day(season_day):
		var job: RefCounted = TransferMarketJobScript.new(TransferMarketScript, self, _rng)
		while not job.step():
			await work.checkpoint(job.label(), job.cursor)
		last_market_profile = job.profile


func is_free_agent(player: Dictionary) -> bool:
	if player.is_empty():
		return false
	if str(player.get("contract_status", "")) == STATUS_FREE_AGENT:
		return true
	return int(player.get("club_id", 0)) < 1


func is_market_day(day: int = -99999) -> bool:
	var check := season_day if day == -99999 else day
	return check >= MARKET_OPEN_DAY and check <= MARKET_LAST_DAY


func next_calendar_day(day: int) -> int:
	if day == MARKET_LAST_DAY:
		return FIRST_MATCH_DAY
	return day + 1


func market_days() -> Array:
	return [MARKET_OPEN_DAY, MARKET_LAST_DAY]


func sorted_standings(unit: Dictionary, division: int = -1) -> Array:
	var rows: Array = []
	for row in unit.get("standings", []):
		if division >= 0 and int(row.get("division", 0)) != division:
			continue
		rows.append(row.duplicate(true))

	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_standings(a, b, ranking) < 0
	)
	return rows


func matches_by_day(unit: Dictionary) -> Dictionary:
	var by_day: Dictionary = {}
	for match_row in unit.get("matches", []):
		var day: int = int(match_row.get("season_day", 0))
		if not by_day.has(day):
			by_day[day] = []
		(by_day[day] as Array).append(match_row)
	var days: Array = by_day.keys()
	days.sort()
	var ordered: Dictionary = {}
	for day in days:
		ordered[day] = by_day[day]
	return ordered


func advance_day() -> Dictionary:
	if is_processing:
		return DbResult.fail("Игровой день уже рассчитывается")
	last_work_profile = {}
	return _advance_day_sync()


func advance_day_async(budget_ms: int = 8) -> Dictionary:
	if is_processing:
		return DbResult.fail("Игровой день уже рассчитывается")
	if not is_active or season_finished:
		return DbResult.fail("Сезон завершён")
	is_processing = true
	processing_changed.emit()
	var work: RefCounted = SimulationWorkScript.new(self, budget_ms)
	await work.checkpoint("Подготовка дня", 0, 0, true)
	var result: Dictionary = await _advance_day_impl(work)
	last_work_profile = work.finish()
	is_processing = false
	processing_changed.emit()
	return result


func _advance_day_sync() -> Dictionary:
	if not is_active or season_finished:
		return DbResult.fail("Сезон завершён")
	var phase_start := Time.get_ticks_usec()
	last_day_profile = {}
	var history_written: Dictionary = _flush_history()
	if not history_written["success"]:
		return history_written

	last_day_profile["history_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	var tick: Dictionary
	tick = _simulate_day(season_day)
	last_day_profile["matches_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()

	if not is_market_day(season_day):
		for unit in units:
			if CupCompetition.enabled(unit):
				_next_match_id = CupCompetition.after_day(unit, units, season_day, _next_match_id)
				continue
			if NationalTeams.is_unit(unit) and not bool(unit.get("international_started", false)):
				continue
			var started: Dictionary = PlayoffManagerScript.maybe_start(unit, season_day, _next_match_id)
			_next_match_id = int(started.get("next_match_id", _next_match_id))
			if bool(started.get("started", false)) and _yellow_reset_of(unit) == DisciplineRulesScript.RESET_PLAYOFF:
				MatchDayScript.reset_yellows_for_unit(self, unit)
			var progressed: Dictionary = PlayoffManagerScript.after_day_simulated(
				unit, season_day, _next_match_id, season_number
			)
			_next_match_id = int(progressed.get("next_match_id", _next_match_id))
			NationalRatingScript.close_completed(self)
			PlayoffManagerScript.capture_season_if_ready(unit, season_number)
		last_day_profile["playoff_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
		phase_start = Time.get_ticks_usec()
		MatchDayScript.advance_rounds(self, tick)
		last_day_profile["recovery_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
		phase_start = Time.get_ticks_usec()
		_apply_unit_prizes()

	if not is_market_day(season_day):
		NationalTeams.start_window(self)
	CoachMarketScript.review(self, _rng)
	season_day = next_calendar_day(season_day)
	_pay_season_wages_if_due()
	last_day_profile["prizes_and_wages_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	_begin_calendar_day()
	last_day_profile["market_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if season_day == FIRST_MATCH_DAY:
		_publish_season_previews()
	_recompute_season_length()
	_refresh_season_finished()
	last_day_profile["preview_and_calendar_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	session_changed.emit()
	return DbResult.ok({
		"season_day": season_day,
		"season_finished": season_finished,
	})


func _advance_day_impl(work: RefCounted = null) -> Dictionary:
	if not is_active or season_finished:
		return DbResult.fail("Сезон завершён")
	var phase_start := Time.get_ticks_usec()
	last_day_profile = {}
	var history_written: Dictionary = _flush_history()
	if not history_written["success"]:
		return history_written

	last_day_profile["history_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	var tick: Dictionary
	if work != null:
		tick = await _simulate_day_async(season_day, work)
	else:
		tick = _simulate_day(season_day)
	last_day_profile["matches_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()

	if not is_market_day(season_day):
		for unit in units:
			if CupCompetition.enabled(unit):
				_next_match_id = CupCompetition.after_day(unit, units, season_day, _next_match_id)
				continue
			if NationalTeams.is_unit(unit) and not bool(unit.get("international_started", false)):
				continue
			if work != null:
				await work.checkpoint("Плей-офф")
			var started: Dictionary = PlayoffManagerScript.maybe_start(unit, season_day, _next_match_id)
			_next_match_id = int(started.get("next_match_id", _next_match_id))
			if bool(started.get("started", false)) and _yellow_reset_of(unit) == DisciplineRulesScript.RESET_PLAYOFF:
				MatchDayScript.reset_yellows_for_unit(self, unit)
			var progressed: Dictionary = PlayoffManagerScript.after_day_simulated(
				unit, season_day, _next_match_id, season_number
			)
			_next_match_id = int(progressed.get("next_match_id", _next_match_id))
			NationalRatingScript.close_completed(self)
			PlayoffManagerScript.capture_season_if_ready(unit, season_number)
		last_day_profile["playoff_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
		phase_start = Time.get_ticks_usec()
		if work != null:
			await MatchDayScript.advance_rounds_async(self, tick, work)
		else:
			MatchDayScript.advance_rounds(self, tick)
		last_day_profile["recovery_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
		phase_start = Time.get_ticks_usec()
		_apply_unit_prizes()

	if not is_market_day(season_day):
		NationalTeams.start_window(self)
	CoachMarketScript.review(self, _rng)
	season_day = next_calendar_day(season_day)
	_pay_season_wages_if_due()
	last_day_profile["prizes_and_wages_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if work != null:
		await _begin_calendar_day_async(work)
	else:
		_begin_calendar_day()
	last_day_profile["market_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	if season_day == FIRST_MATCH_DAY:
		if work != null:
			await _publish_season_previews_async(work)
		else:
			_publish_season_previews()
	_recompute_season_length()
	_refresh_season_finished()
	last_day_profile["preview_and_calendar_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	session_changed.emit()
	return DbResult.ok({
		"season_day": season_day,
		"season_finished": season_finished,
	})


func start_new_season() -> Dictionary:
	if is_processing:
		return DbResult.fail("Дождитесь завершения игрового дня")
	if not is_active:
		return DbResult.fail("Нет активной игры")
	if not season_finished and not _all_units_complete():
		return DbResult.fail("Сезон ещё не завершён")
	var club_units: Array = units.filter(func(unit): return not NationalTeams.is_unit(unit))
	var movement_plan := LeagueMovementScript.plan(units, sorted_standings)
	if not movement_plan["success"]:
		return movement_plan
	# Validate next year's cup participants before any season state is mutated.
	if units.any(func(u): return CupCompetition.enabled(u)):
		var projected_units: Array = []
		for u in units:
			var projected: Dictionary = u.duplicate(false)
			projected["divisions"] = u.get("divisions", []).duplicate(true)
			projected["clubs_by_id"] = u.get("clubs_by_id", {}).duplicate(false)
			projected_units.append(projected)
		LeagueMovementScript.apply(projected_units, movement_plan["data"])
		for projected in projected_units:
			if CupCompetition.enabled(projected):
				var cup_validation := CupCompetition.validate_world(projected, projected_units)
				if not cup_validation.is_empty():
					return DbResult.fail("Следующий сезон: " + "\n".join(cup_validation))
	var history_written: Dictionary = _flush_history()
	if not history_written["success"]:
		return history_written

	var closed_season := season_number
	var phase_start := Time.get_ticks_usec()
	last_new_season_profile = {}
	_apply_unit_prizes()
	var reputation_plan := SeasonReputationScript.plan(club_units, closed_season, func(player_id: int) -> Dictionary:
		return get_player(player_id)
	)
	SeasonReputationScript.write_clubs(units, reputation_plan.get("clubs", {}))
	last_new_season_profile["reputation_and_prizes_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	CoachMarketScript.close_season(self, _rng)
	NationalRatingScript.close_completed(self)
	NationalTeams.close_season(self, _rng)
	_national_player_index.clear()
	season_number += 1
	season_day = MARKET_OPEN_DAY
	season_finished = false

	LeagueMovementScript.apply(units, movement_plan["data"])
	for i in units.size():
		units[i] = _reset_unit_for_new_season(units[i])
	var cup_errors := CupCompetition.initialize_all(units, season_number, _rng.seed)
	if not cup_errors.is_empty():
		return DbResult.fail("\n".join(cup_errors))
	ClubRatingScript.ensure(self)
	last_new_season_profile["reset_competitions_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0

	phase_start = Time.get_ticks_usec()
	_develop_and_age_players()
	SeasonReputationScript.write_players(
		reputation_plan.get("players", {}),
		reputation_plan.get("before", {}),
		func(player_id: int) -> Dictionary:
			return get_player(player_id)
	)
	last_new_season_profile["player_development_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	retired_players = _retire_players()
	var retired_count := retired_players.size()
	_roll_player_stats()
	var archived: Dictionary = _archive_retired(retired_players, closed_season)
	last_new_season_profile["retirement_stats_archive_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	_process_contract_renewals()
	last_new_season_profile["contracts_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	_process_youth_graduation()
	last_new_season_profile["youth_graduation_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	phase_start = Time.get_ticks_usec()
	_begin_season_for_players()
	_run_youth_intake()
	last_new_season_profile["season_state_and_intake_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	wages_paid_for_season = 0

	_next_match_id = _max_match_id() + 1
	_recompute_season_length()
	phase_start = Time.get_ticks_usec()
	_begin_calendar_day()
	last_new_season_profile["market_ms"] = float(Time.get_ticks_usec() - phase_start) / 1000.0
	session_changed.emit()
	if not archived["success"]:
		last_error = "Сезон начат, но история не записана. Повторите сохранение: " + str(archived.get("error", ""))
		return DbResult.fail(last_error)
	return DbResult.ok({
		"season_number": season_number,
		"season_day": season_day,
		"retired": retired_count,
		"league_movements": movement_plan["data"],
	})


func _simulate_day(day: int) -> Dictionary:
	var tick := {"clubs": {}, "players": {}}
	for unit in units:
		if NationalTeams.is_unit(unit) and not bool(unit.get("international_started", false)):
			continue
		var rules: Dictionary = unit.get("rules", {})
		var points_win: int = int(rules.get("points_win", 3))
		var points_draw: int = int(rules.get("points_draw", 1))
		var points_loss: int = int(rules.get("points_loss", 0))
		for match_row in unit.get("matches", []):
			if int(match_row.get("season_day", 0)) != day:
				continue
			if bool(match_row.get("played", false)):
				continue
			MatchDayScript.simulate(self, unit, match_row, tick, _rng)
			if str(match_row.get("stage", "REGULAR")) == "REGULAR":
				_apply_regular_result(
					unit,
					int(match_row.get("home_id", 0)),
					int(match_row.get("away_id", 0)),
					int(match_row["home_goals"]),
					int(match_row["away_goals"]),
					points_win,
					points_draw,
					points_loss
				)
	return tick


func _simulate_day_async(day: int, work: RefCounted = null) -> Dictionary:
	var tick := {"clubs": {}, "players": {}}
	var scanned := 0
	for unit in units:
		if NationalTeams.is_unit(unit) and not bool(unit.get("international_started", false)):
			continue
		var rules: Dictionary = unit.get("rules", {})
		var points_win: int = int(rules.get("points_win", 3))
		var points_draw: int = int(rules.get("points_draw", 1))
		var points_loss: int = int(rules.get("points_loss", 0))
		for match_row in unit.get("matches", []):
			scanned += 1
			var due := int(match_row.get("season_day", 0)) == day and not bool(match_row.get("played", false))
			# Keep cancellation/UI checkpoints bounded while scanning the calendar,
			# without creating an awaited call for every game of the entire season.
			if work != null and (due or scanned % 128 == 0):
				await work.checkpoint("Матчи")
			if not due:
				continue
			MatchDayScript.simulate(self, unit, match_row, tick, _rng)
			if str(match_row.get("stage", "REGULAR")) == "REGULAR":
				_apply_regular_result(
					unit,
					int(match_row.get("home_id", 0)),
					int(match_row.get("away_id", 0)),
					int(match_row["home_goals"]),
					int(match_row["away_goals"]),
					points_win,
					points_draw,
					points_loss
				)
	return tick


func _yellow_reset_of(unit: Dictionary) -> String:
	return DisciplineRulesScript.normalize_reset(
		(unit.get("rules", {}) as Dictionary).get("yellow_reset", DisciplineRulesScript.RESET_DEFAULT)
	)


func _apply_regular_result(
	unit: Dictionary,
	home_id: int,
	away_id: int,
	home_goals: int,
	away_goals: int,
	points_win: int,
	points_draw: int,
	points_loss: int
) -> void:
	var home_row := _standing_row(unit, home_id)
	var away_row := _standing_row(unit, away_id)
	if home_row.is_empty() or away_row.is_empty():
		return

	home_row["played"] = int(home_row.get("played", 0)) + 1
	away_row["played"] = int(away_row.get("played", 0)) + 1
	home_row["goals_for"] = int(home_row.get("goals_for", 0)) + home_goals
	home_row["goals_against"] = int(home_row.get("goals_against", 0)) + away_goals
	away_row["goals_for"] = int(away_row.get("goals_for", 0)) + away_goals
	away_row["goals_against"] = int(away_row.get("goals_against", 0)) + home_goals

	if home_goals > away_goals:
		home_row["won"] = int(home_row.get("won", 0)) + 1
		away_row["lost"] = int(away_row.get("lost", 0)) + 1
		home_row["points"] = int(home_row.get("points", 0)) + points_win
		away_row["points"] = int(away_row.get("points", 0)) + points_loss
	elif away_goals > home_goals:
		away_row["won"] = int(away_row.get("won", 0)) + 1
		home_row["lost"] = int(home_row.get("lost", 0)) + 1
		away_row["points"] = int(away_row.get("points", 0)) + points_win
		home_row["points"] = int(home_row.get("points", 0)) + points_loss
	else:
		home_row["drawn"] = int(home_row.get("drawn", 0)) + 1
		away_row["drawn"] = int(away_row.get("drawn", 0)) + 1
		home_row["points"] = int(home_row.get("points", 0)) + points_draw
		away_row["points"] = int(away_row.get("points", 0)) + points_draw

	home_row["goal_diff"] = int(home_row.get("goals_for", 0)) - int(home_row.get("goals_against", 0))
	away_row["goal_diff"] = int(away_row.get("goals_for", 0)) - int(away_row.get("goals_against", 0))


func _standing_row(unit: Dictionary, club_id: int) -> Dictionary:
	for row in unit.get("standings", []):
		if int(row.get("club_id", 0)) == club_id:
			return row
	return {}


func _reset_unit_for_new_season(unit: Dictionary) -> Dictionary:
	var next: Dictionary = unit.duplicate(true)
	var club_ids: Array = []
	for division in next.get("divisions", []):
		for club_id in division.get("club_ids", []):
			club_ids.append(int(club_id))

	var competition_type: String = str(next.get("competition_type", ""))
	var rules: Dictionary = next.get("rules", {})
	var matches: Array = []
	var divisions: Array = next.get("divisions", [])

	if competition_type == CompetitionTypes.TYPE_DIVISIONS and not NationalTeams.is_unit(next):
		var generated: Dictionary = FixtureGeneratorScript.build_regular_season(
			club_ids,
			int(rules.get("divisions_count", CompetitionUnitRepository.DIVISIONS_COUNT_DEFAULT)),
			int(rules.get("teams_per_division", CompetitionUnitRepository.TEAMS_PER_DIVISION_DEFAULT)),
			int(rules.get("matches_vs_own", CompetitionUnitRepository.MATCHES_VS_OWN_DEFAULT)),
			int(rules.get("matches_vs_other", CompetitionUnitRepository.MATCHES_VS_OTHER_DEFAULT)),
			_rng,
			[],
			str(rules.get("division_sort", "")),
			FixtureGeneratorScript.division_scores_of(club_ids, next.get("clubs_by_id", {}), str(rules.get("division_sort", "")), ClubRatingScript.strength_of(next))
		)
		divisions = generated["divisions"]
		matches = generated["matches"]

	next["divisions"] = divisions
	next["matches"] = matches
	next["standings"] = _empty_standings(divisions)
	next["season_player_stats"] = UnitSeasonStatsScript.empty_bag()
	var playoff: Dictionary = next.get("playoff", {})
	playoff["started"] = false
	playoff["finished"] = false
	playoff["current_round"] = 0
	playoff["series"] = []
	playoff["matches"] = []
	playoff["champion_id"] = 0
	playoff["slots"] = []
	next["playoff"] = playoff
	next.erase("prizes_paid_for_season")
	next.erase("season_preview")
	if NationalTeams.is_unit(next):
		next["international_started"] = false
		next.erase("international_start_day")
		next.erase("group_draw")
		next.erase("national_rating")
	# winners history preserved
	return next


func _empty_standings(divisions: Array) -> Array:
	var rows: Array = []
	for division in divisions:
		var div_index: int = int(division.get("index", 0))
		for club_id in division.get("club_ids", []):
			rows.append({
				"club_id": int(club_id),
				"division": div_index,
				"played": 0,
				"won": 0,
				"drawn": 0,
				"lost": 0,
				"goals_for": 0,
				"goals_against": 0,
				"goal_diff": 0,
				"points": 0,
			})
	return rows


func _recompute_season_length() -> void:
	var max_day := 1
	var pending_international_days := 0
	for unit in units:
		if NationalTeams.is_unit(unit):
			if not NationalTeams.due(unit, season_number):
				continue
			if not bool(unit.get("international_started", false)):
				pending_international_days += int(unit.get("estimated_days", 1))
				continue
		for match_row in unit.get("matches", []):
			max_day = maxi(max_day, int(match_row.get("season_day", 1)))
		var playoff: Dictionary = unit.get("playoff", {})
		if bool(playoff.get("enabled", false)) and not bool(playoff.get("started", false)):
			var regular_max := 1
			for match_row in unit.get("matches", []):
				if str(match_row.get("stage", "REGULAR")) == "REGULAR":
					regular_max = maxi(regular_max, int(match_row.get("season_day", 1)))
			max_day = maxi(max_day, regular_max + PlayoffManagerScript.estimate_days(playoff))
	season_total_days = max_day + pending_international_days


func _refresh_season_finished() -> void:
	season_finished = _all_units_complete()


func _all_units_complete() -> bool:
	if units.is_empty():
		return false
	for unit in units:
		if CupCompetition.enabled(unit):
			if not bool(unit.get("cup_state", {}).get("finished", false)):
				return false
			continue
		if NationalTeams.is_unit(unit):
			if not NationalTeams.due(unit, season_number):
				continue
			if not bool(unit.get("international_started", false)):
				return false
		if not PlayoffManagerScript.is_unit_season_complete(unit):
			return false
	return true


func _max_match_id() -> int:
	var max_id := 0
	for unit in units:
		for match_row in unit.get("matches", []):
			max_id = maxi(max_id, int(match_row.get("id", 0)))
	return max_id


func _compare_standings(a: Dictionary, b: Dictionary, ranking: Array) -> int:
	for code in ranking:
		var cmp := 0
		match str(code):
			RankingCriteria.POINTS:
				cmp = int(b.get("points", 0)) - int(a.get("points", 0))
			RankingCriteria.GOAL_DIFF:
				cmp = int(b.get("goal_diff", 0)) - int(a.get("goal_diff", 0))
			RankingCriteria.GOALS_FOR:
				cmp = int(b.get("goals_for", 0)) - int(a.get("goals_for", 0))
			RankingCriteria.WINS:
				cmp = int(b.get("won", 0)) - int(a.get("won", 0))
			_:
				cmp = 0
		if cmp != 0:
			return cmp
	return int(a.get("club_id", 0)) - int(b.get("club_id", 0))


func _find_player_in_map(by_club: Dictionary, player_id: int) -> Dictionary:
	for club_id in by_club.keys():
		var squad: Array = by_club[club_id]
		for player in squad:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if int(player.get("id", 0)) == player_id:
				return player
	return {}


func _count_saved_players() -> int:
	var total := free_agents.size()
	for by_club in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in by_club.keys():
			var squad: Variant = by_club[club_id]
			if typeof(squad) == TYPE_ARRAY:
				total += squad.size()
	return total


func _legacy_json_entries(known: Dictionary) -> Array:
	var folder := DirAccess.open("user://saves")
	if folder == null:
		return []
	var items: Array = []
	for file_name in folder.get_files():
		var name := str(file_name)
		if not name.ends_with(".json"):
			continue
		var slot := name.trim_suffix(".json")
		if not SaveStoreScript.is_valid_slot(slot) or known.has(slot):
			continue
		var path := "user://saves/%s" % name
		var modified := FileAccess.get_modified_time(path)
		items.append({
			"slot": slot,
			"legacy": true,
			"version": 0,
			"saved_at": Time.get_datetime_string_from_unix_time(modified, true),
			"season_number": 0,
			"season_day": 0,
			"season_finished": false,
			"player_count": 0,
			"unit_count": 0,
		})
	return items


func _read_legacy_json(slot: String) -> Dictionary:
	var path := "user://saves/%s.json" % slot
	if not FileAccess.file_exists(path):
		return DbResult.fail(SaveStoreScript.ERR_NOT_FOUND)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return DbResult.fail("Не удалось прочитать файл сохранения")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return DbResult.fail("Повреждённый файл сохранения")
	return DbResult.ok(parsed)


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _coerce_club_player_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = raw
	for key in source.keys():
		var club_id := int(key)
		var squad: Array = source[key] if typeof(source[key]) == TYPE_ARRAY else []
		var players: Array = []
		for player in squad:
			if typeof(player) == TYPE_DICTIONARY:
				players.append(player)
		out[club_id] = players
	return out


func _coerce_club_coach_map(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = raw
	for key in source.keys():
		var club_id := int(key)
		var value: Variant = source[key]
		if typeof(value) == TYPE_DICTIONARY:
			out[club_id] = value
		elif typeof(value) == TYPE_ARRAY and not value.is_empty() and typeof(value[0]) == TYPE_DICTIONARY:
			out[club_id] = value[0]
	return out


func _migrate_loaded_coaches() -> void:
	for club_id in coaches_by_club.keys():
		var coach: Variant = coaches_by_club[club_id]
		if typeof(coach) != TYPE_DICTIONARY:
			continue
		if not coach.has("development_factor"):
			coach["development_factor"] = 0.92
		if not coach.has("potential_ability"):
			coach["potential_ability"] = int(coach.get("current_ability", 50))
		if not coach.has("attributes"):
			var transfers := CoachTypesScript.clamp_attr(int(coach.get("transfers", 10)))
			coach["attributes"] = {
				CoachTypesScript.ATTR_TRANSFERS: transfers,
				CoachTypesScript.ATTR_NEGOTIATIONS: transfers,
				CoachTypesScript.ATTR_TACTICS: transfers,
				CoachTypesScript.ATTR_MOTIVATION: transfers,
				CoachTypesScript.ATTR_DEVELOPMENT: transfers,
				CoachTypesScript.ATTR_DISCIPLINE: transfers,
			}
		var attributes: Dictionary = coach.get("attributes", {})
		if not attributes.has(CoachTypesScript.ATTR_TRANSFERS):
			attributes[CoachTypesScript.ATTR_TRANSFERS] = CoachTypesScript.clamp_attr(
				int(coach.get("transfers", 10))
			)
		if not attributes.has(CoachTypesScript.ATTR_NEGOTIATIONS):
			var total := 0
			var count := 0
			for key in CoachTypesScript.ATTR_KEYS:
				if key == CoachTypesScript.ATTR_NEGOTIATIONS:
					continue
				if not attributes.has(key):
					continue
				total += CoachTypesScript.clamp_attr(int(attributes.get(key, 10)))
				count += 1
			var fallback := CoachTypesScript.transfers_of(coach)
			if count > 0:
				fallback = CoachTypesScript.clamp_attr(int(round(float(total) / float(count))))
			attributes[CoachTypesScript.ATTR_NEGOTIATIONS] = fallback
		coach["attributes"] = attributes
		TacticTypesScript.ensure_coach_tactics(coach)
		if not coach.has("career"):
			coach["career"] = []
		if not coach.has("overall"):
			coach["overall"] = int(coach.get("current_ability", 50))
		coaches_by_club[int(club_id)] = coach


func _migrate_loaded_players(by_club: Dictionary) -> void:
	for club_id in by_club.keys():
		var squad: Array = by_club[club_id]
		_migrate_player_list(squad)


func _migrate_player_list(players: Array) -> void:
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		player.erase("number")
		PlayerMarketScript.migrate_value(player)
		player["position"] = PlayerTypes.normalize_position(str(player.get("position", "")))
		MatchRatingsScript.invalidate(player)
		player.erase("secondary_positions")
		if not player.has("development_factor"):
			player["development_factor"] = 0.92
		if not player.has("potential_ability"):
			player["potential_ability"] = int(player.get("current_ability", 50))
		if not player.has("is_youth"):
			player["is_youth"] = false
		if not player.has("contract_status"):
			player["contract_status"] = STATUS_FREE_AGENT if int(player.get("club_id", 0)) < 1 else STATUS_CLUB
		if PlayerTypes.backfill_attributes(player, _rng):
			MatchRatingsScript.invalidate(player)
		PlayerConditionScript.ensure_state(player)
		PlayerStatsScript.ensure_state(player, season_number)


func _strip_rating_caches() -> void:
	for map in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in map.keys():
			MatchRatingsScript.strip_cache(map[club_id])
	MatchRatingsScript.strip_cache(free_agents)


func _coerce_player_list(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for item in raw:
		if typeof(item) == TYPE_DICTIONARY:
			out.append(item)
	return out


func _append_listed_player_rows(rows: Array, countries: Dictionary) -> void:
	var clubs := _collect_session_clubs()
	for club_id in players_by_club.keys():
		var id := int(club_id)
		var club: Dictionary = clubs.get(id, {})
		var club_name := str(club.get("name", "")).strip_edges()
		if club_name.is_empty():
			club_name = "Клуб #%d" % id
		for player in players_by_club[club_id]:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if not bool(player.get("for_sale", false)):
				continue
			var country_id := int(player.get("nationality_country_id", 0))
			var country: Dictionary = countries.get(country_id, {})
			var country_name := str(country.get("name", "")).strip_edges()
			var ca := int(player.get("current_ability", player.get("overall", 0)))
			rows.append({
				"id": int(player.get("id", 0)),
				"name": str(player.get("name", "")).strip_edges(),
				"age": int(player.get("age", 0)),
				"ca": ca,
				"pa": int(player.get("potential_ability", ca)),
				"position": str(player.get("position", "")),
				"club_id": id,
				"club_name": club_name,
				"logo_path": str(club.get("logo_path", "")),
				"country_id": country_id,
				"country_name": country_name,
				"flag_path": str(country.get("flag_path", "")),
				"is_youth": bool(player.get("is_youth", false)),
				"is_free_agent": false,
				"is_listed": true,
				"asking_price": int(player.get("asking_price", player.get("value", 0))),
			})


func _append_free_agent_rows(rows: Array, countries: Dictionary) -> void:
	for player in free_agents:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var country_id := int(player.get("nationality_country_id", 0))
		var country: Dictionary = countries.get(country_id, {})
		var country_name := str(country.get("name", "")).strip_edges()
		if country_name.is_empty() and country_id > 0:
			country_name = "Страна #%d" % country_id
		var ca := int(player.get("current_ability", player.get("overall", 0)))
		rows.append({
			"id": int(player.get("id", 0)),
			"name": str(player.get("name", "")).strip_edges(),
			"age": int(player.get("age", 0)),
			"ca": ca,
			"pa": int(player.get("potential_ability", ca)),
			"position": str(player.get("position", "")),
			"club_id": 0,
			"club_name": "Свободный агент",
			"logo_path": "",
			"country_id": country_id,
			"country_name": country_name,
			"flag_path": str(country.get("flag_path", "")),
			"is_youth": bool(player.get("is_youth", false)),
			"is_free_agent": true,
		})


func _append_player_rows(
	rows: Array,
	by_club: Dictionary,
	clubs: Dictionary,
	countries: Dictionary,
	fallback_youth: bool
) -> void:
	for club_id in by_club.keys():
		var id := int(club_id)
		var club: Dictionary = clubs.get(id, {})
		var club_name := str(club.get("name", "")).strip_edges()
		if club_name.is_empty():
			club_name = "Клуб #%d" % id
		var logo_path := str(club.get("logo_path", ""))
		for player in by_club[club_id]:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			var country_id := int(player.get("nationality_country_id", club.get("country_id", 0)))
			var country: Dictionary = countries.get(country_id, {})
			var country_name := str(country.get("name", "")).strip_edges()
			if country_name.is_empty() and country_id > 0:
				country_name = "Страна #%d" % country_id
			var ca := int(player.get("current_ability", player.get("overall", 0)))
			rows.append({
				"id": int(player.get("id", 0)),
				"name": str(player.get("name", "")).strip_edges(),
				"age": int(player.get("age", 0)),
				"ca": ca,
				"pa": int(player.get("potential_ability", ca)),
				"position": str(player.get("position", "")),
				"club_id": id,
				"club_name": club_name,
				"logo_path": logo_path,
				"country_id": country_id,
				"country_name": country_name,
				"flag_path": str(country.get("flag_path", "")),
				"is_youth": bool(player.get("is_youth", fallback_youth)),
				"is_free_agent": int(player.get("club_id", id)) < 1,
			})


func _countries_by_id() -> Dictionary:
	var out: Dictionary = {}
	if not WorldDatabase.is_ready():
		return out
	var loaded := CountryRepository.new().get_all()
	if not bool(loaded.get("success", false)):
		return out
	for country in loaded.get("data", []):
		if typeof(country) != TYPE_DICTIONARY:
			continue
		out[int(country.get("id", 0))] = country
	return out


func _collect_session_clubs() -> Dictionary:
	var clubs: Dictionary = {}
	for unit in units:
		if NationalTeams.is_unit(unit):
			continue
		var by_id: Dictionary = unit.get("clubs_by_id", {})
		for club_id in by_id.keys():
			clubs[int(club_id)] = by_id[club_id]
	return clubs


func _seed_club_budgets() -> void:
	club_budgets.clear()
	_ensure_club_budgets()


func _ensure_club_budgets() -> void:
	var clubs := _collect_session_clubs()
	for club_id in clubs.keys():
		var id := int(club_id)
		if club_budgets.has(id):
			continue
		var club: Dictionary = clubs[id] if typeof(clubs[id]) == TYPE_DICTIONARY else {}
		club_budgets[id] = ClubFinanceScript.starting_budget(
			int(club.get("finance_level", 10)),
			int(club.get("reputation", 500))
		)


func _apply_unit_prizes() -> void:
	for i in units.size():
		var unit: Dictionary = units[i]
		if NationalTeams.is_unit(unit):
			continue
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		if int(unit.get("prizes_paid_for_season", 0)) == season_number:
			continue
		if not PlayoffManagerScript.is_unit_season_complete(unit):
			continue
		var rules: Dictionary = unit.get("rules", {})
		if rules.is_empty():
			rules = unit
		elif not rules.has("competition_type"):
			rules = rules.merged({"competition_type": unit.get("competition_type", CompetitionTypes.TYPE_LEAGUE)})
		var snapshot: Dictionary = unit
		var payouts: Dictionary = PrizeRulesScript.payouts(
			rules,
			func(division): return sorted_standings(snapshot, int(division)),
			unit.get("playoff", {})
		)
		for club_id in payouts.keys():
			var id := int(club_id)
			club_budgets[id] = ClubFinanceScript.credit(
				int(club_budgets.get(id, 0)),
				int(payouts[club_id])
			)
		unit["prizes_paid_for_season"] = season_number
		units[i] = unit


func _publish_season_previews(work: RefCounted = null) -> void:
	for i in units.size():
		var unit: Dictionary = units[i]
		if NationalTeams.is_unit(unit):
			continue
		var existing: Dictionary = unit.get("season_preview", {})
		if int(existing.get("season", 0)) == season_number:
			continue
		unit["season_preview"] = SeasonPreviewScript.build(
			unit, season_number, players_by_club, coaches_by_club
		)
		units[i] = unit


func _publish_season_previews_async(work: RefCounted = null) -> void:
	for i in units.size():
		if work != null:
			await work.checkpoint("Превью турниров", i, units.size())
		var unit: Dictionary = units[i]
		if NationalTeams.is_unit(unit):
			continue
		var existing: Dictionary = unit.get("season_preview", {})
		if int(existing.get("season", 0)) == season_number:
			continue
		unit["season_preview"] = SeasonPreviewScript.build(
			unit, season_number, players_by_club, coaches_by_club
		)
		units[i] = unit


func _pay_season_wages_if_due() -> void:
	if season_day != FIRST_MATCH_DAY:
		return
	if wages_paid_for_season == season_number:
		return
	var clubs := _collect_session_clubs()
	for club_id in clubs.keys():
		var id := int(club_id)
		var current := int(club_budgets.get(id, 0))
		club_budgets[id] = ClubFinanceScript.apply_wages(
			current,
			get_club_players(id),
			get_club_youth_players(id) + get_club_reserve_players(id),
			get_club_coach(id)
		)
	wages_paid_for_season = season_number


func _process_contract_renewals() -> Dictionary:
	var released := 0
	var renewed := 0
	var clubs := _collect_session_clubs()
	var world_top := PlayerOffer.world_top_reputation(clubs)
	for club_id in clubs.keys():
		var id := int(club_id)
		var club_raw: Variant = clubs.get(id, {})
		var club: Dictionary = club_raw if typeof(club_raw) == TYPE_DICTIONARY else {}
		var coach := get_club_coach(id)
		var core: Dictionary = TransferMarket._squad_market_info(self, id, get_club_players(id))["starters"]
		var kept: Array = []
		for player in get_club_players(id):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			var outcome := ContractRenewalScript.process_player(player, club, coach, _rng, {"key_player": core.has(int(player.get("id", 0))), "world_top_reputation": world_top})
			if outcome == ContractRenewalScript.REASON_RELEASED:
				free_agents.append(player)
				released += 1
				_log_contract_end(id, club, player)
			else:
				kept.append(player)
				if outcome == ContractRenewalScript.REASON_RENEWED:
					renewed += 1
		players_by_club[id] = kept
		var youth_kept: Array = []
		for player in get_club_youth_players(id):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			ContractRenewalScript.process_player(player, club, coach, _rng)
			youth_kept.append(player)
		youth_players_by_club[id] = youth_kept
	return {"released": released, "renewed": renewed}


func _process_youth_graduation() -> Dictionary:
	var promoted := 0
	var reserved := 0
	var listed := 0
	var clubs := _collect_session_clubs()
	for club_id in clubs.keys():
		var id := int(club_id)
		var club_raw: Variant = clubs.get(id, {})
		var club: Dictionary = club_raw if typeof(club_raw) == TYPE_DICTIONARY else {}
		var coach := get_club_coach(id)
		var formation := CoachTypesScript.primary_formation_of(coach)
		var squad: Array = get_club_players(id)
		var reserve: Array = get_club_reserve_players(id)
		var kept_youth: Array = []
		var graduates: Array = []
		for player in get_club_youth_players(id):
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if int(player.get("age", 0)) >= 18:
				graduates.append(player)
			else:
				kept_youth.append(player)
		graduates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var pa := int(a.get("potential_ability", 0)) - int(b.get("potential_ability", 0))
			if pa != 0:
				return pa > 0
			return int(a.get("current_ability", 0)) > int(b.get("current_ability", 0))
		)
		for player in graduates:
			var choice: Dictionary = YouthGraduationScript.destination_for_graduate(
				player, squad, reserve, formation
			)
			var dest := str(choice.get("dest", YouthGraduationScript.DEST_MARKET))
			if dest == YouthGraduationScript.DEST_FIRST:
				var victim: Dictionary = choice.get("victim", {})
				if not victim.is_empty():
					_release_to_market(id, club, victim, false)
					var kept_squad: Array = []
					for row in squad:
						if int(row.get("id", 0)) != int(victim.get("id", 0)):
							kept_squad.append(row)
					squad = kept_squad
				YouthGraduationScript.prepare_first_team(player)
				player["club_id"] = id
				squad.append(player)
				promoted += 1
			elif dest == YouthGraduationScript.DEST_RESERVE:
				YouthGraduationScript.prepare_reserve(player)
				player["club_id"] = id
				reserve.append(player)
				reserved += 1
			else:
				YouthGraduationScript.prepare_listing(player, true)
				player["club_id"] = 0
				player["contract_status"] = STATUS_FREE_AGENT
				player["contract_years"] = 0
				player["for_sale"] = false
				free_agents.append(player)
				listed += 1
				_log_contract_end(id, club, player)
		var kept_reserve: Array = []
		for player in reserve:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			if int(player.get("age", 0)) > YouthGraduationScript.RESERVE_MAX_AGE:
				YouthGraduationScript.prepare_listing(player, true)
				player["club_id"] = 0
				player["contract_status"] = STATUS_FREE_AGENT
				player["contract_years"] = 0
				player["for_sale"] = false
				player["is_reserve"] = false
				free_agents.append(player)
				listed += 1
				_log_contract_end(id, club, player)
				continue
			var pa := int(player.get("potential_ability", 0))
			var pos := str(player.get("position", ""))
			var expendable: Array = YouthGraduationScript.expendable_at_position(
				squad, pos, pa, formation
			)
			if YouthGraduationScript.can_fill_vacancy(squad, pos) or not expendable.is_empty():
				if not expendable.is_empty() and not YouthGraduationScript.can_fill_vacancy(squad, pos):
					var victim: Dictionary = expendable[0]
					_release_to_market(id, club, victim, false)
					var kept_squad: Array = []
					for row in squad:
						if int(row.get("id", 0)) != int(victim.get("id", 0)):
							kept_squad.append(row)
					squad = kept_squad
				YouthGraduationScript.prepare_first_team(player)
				player["club_id"] = id
				player["contract_years"] = maxi(1, int(player.get("contract_years", 1)))
				squad.append(player)
				promoted += 1
			else:
				player["contract_years"] = 1
				player["is_reserve"] = true
				kept_reserve.append(player)
		players_by_club[id] = squad
		reserve_players_by_club[id] = kept_reserve
		youth_players_by_club[id] = kept_youth
	return {"promoted": promoted, "reserved": reserved, "listed": listed}


func _release_to_market(club_id: int, club: Dictionary, player: Dictionary, min_price: bool) -> void:
	YouthGraduationScript.prepare_listing(player, min_price)
	player["club_id"] = 0
	player["contract_status"] = STATUS_FREE_AGENT
	player["contract_years"] = 0
	player["for_sale"] = false
	player["is_reserve"] = false
	free_agents.append(player)
	_log_contract_end(club_id, club, player)


func _log_contract_end(club_id: int, club: Dictionary, player: Dictionary) -> void:
	var club_name := str(club.get("name", "")).strip_edges()
	if club_name.is_empty():
		club_name = "Клуб #%d" % club_id
	transfer_log.append({
		"season": int(season_number),
		"day": int(season_day),
		"club_id": club_id,
		"club_name": club_name,
		"player_id": int(player.get("id", 0)),
		"player_name": str(player.get("name", "Игрок")),
		"position": str(player.get("position", "")),
		"direction": "out",
		"fee": 0,
		"other_club": "окончание контракта",
	})


func _load_countries_for_clubs(clubs: Dictionary) -> Dictionary:
	var countries: Dictionary = {}
	var repo := CountryRepository.new()
	for club_id in clubs.keys():
		var club: Dictionary = clubs[club_id]
		var country_id := int(club.get("country_id", 0))
		if countries.has(country_id):
			continue
		if country_id > 0 and WorldDatabase.is_ready():
			var loaded := repo.get_by_id(country_id)
			if loaded["success"]:
				countries[country_id] = loaded["data"]
				continue
		countries[country_id] = {
			"id": country_id,
			"youth_talent": YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT,
		}
	for country_id in countries:
		var team: Dictionary = national_teams.get(country_id, {})
		if not team.is_empty(): countries[country_id] = team.country
	return countries


func _develop_and_age_players() -> void:
	var clubs := _collect_session_clubs()
	for club_id in clubs.keys():
		var id := int(club_id)
		var club: Dictionary = clubs[club_id]
		var coach: Dictionary = get_club_coach(id)
		var base: Dictionary = PlayerDevelopmentScript.training_setup(
			int(club.get("training_level", 10)), coach
		)
		# Youth work at the academy, the reserve and the first team at the base.
		var academy: Dictionary = PlayerDevelopmentScript.training_setup(
			int(club.get("youth_academy", 10)), coach
		)
		PlayerDevelopmentScript.develop_squad(
			get_club_players(id), base, _rng, -1.0, season_number
		)
		PlayerDevelopmentScript.age_squad(get_club_players(id))
		PlayerDevelopmentScript.develop_squad(
			get_club_youth_players(id),
			academy,
			_rng,
			PlayerDevelopmentScript.YOUTH_PLAYING_SHARE,
			season_number
		)
		PlayerDevelopmentScript.age_squad(get_club_youth_players(id))
		PlayerDevelopmentScript.develop_squad(
			get_club_reserve_players(id),
			base,
			_rng,
			PlayerDevelopmentScript.RESERVE_PLAYING_SHARE,
			season_number
		)
		PlayerDevelopmentScript.age_squad(get_club_reserve_players(id))
		# A season of growth only pays off once fame and price catch up to it.
		var club_rep := int(club.get("reputation", 500))
		PlayerMarketScript.refresh_squad(get_club_players(id), club_rep)
		PlayerMarketScript.refresh_squad(get_club_youth_players(id), club_rep)
		PlayerMarketScript.refresh_squad(get_club_reserve_players(id), club_rep)
	# Nobody trains a free agent: neutral base, no coach.
	PlayerDevelopmentScript.develop_squad(
		free_agents,
		PlayerDevelopmentScript.training_setup(PlayerDevelopmentScript.LEVEL_NEUTRAL),
		_rng,
		PlayerDevelopmentScript.FREE_AGENT_PLAYING_SHARE,
		season_number
	)
	PlayerDevelopmentScript.age_squad(free_agents)
	# Being clubless drags a reputation down towards the bottom of the market.
	PlayerMarketScript.refresh_squad(free_agents, 0)


## Ability decline and old age take players out of the save for good.
func _retire_players() -> Array:
	var retired: Array = []
	for map in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in map.keys():
			var squad: Array = map[club_id]
			var keep: Array = []
			for player in squad:
				if typeof(player) != TYPE_DICTIONARY:
					continue
				if PlayerDevelopmentScript.should_retire(player, _rng):
					player["club_id"] = int(club_id)
					retired.append(player)
				else:
					keep.append(player)
			map[club_id] = keep
	var free_kept: Array = []
	for player in free_agents:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if PlayerDevelopmentScript.should_retire(player, _rng):
			player["club_id"] = 0
			retired.append(player)
		else:
			free_kept.append(player)
	free_agents = free_kept
	return retired


func _archive_retired(retired: Array, season: int) -> Dictionary:
	var kept: Array = []
	for player in retired:
		# A transfer-log mention or an unused squad medal is not a played career.
		if not HistoryStoreScript.has_playing_history(player):
			continue
		kept.append(player)
		_pending_history.append(HistoryStoreScript.snapshot(player, season))
	# Do not retain discarded profiles in the session's retired_players buffer either.
	retired.assign(kept)
	return _flush_history()


func _flush_history() -> Dictionary:
	for unit in units:
		if int(unit.get("history_archived_season", 0)) == season_number or int(unit.get("id", 0)) < 1:
			continue
		if NationalTeams.is_unit(unit) and not bool(unit.get("international_started", false)):
			continue
		if (unit.get("matches", []) as Array).is_empty() or not PlayoffManagerScript.is_unit_season_complete(unit):
			continue
		_pending_history.append({"kind": "tournament_season", "unit_id": int(unit["id"]), "season": season_number, "unit": TournamentHistory.snapshot(unit, season_number)})
		unit["history_archived_season"] = season_number
	if _pending_history.is_empty():
		return DbResult.ok({"history_head": history_head})
	var written: Dictionary = SaveStoreScript.new().append_history(history_head, _pending_history)
	if written["success"]:
		history_head = int(written["data"]["history_head"])
		_pending_history.clear()
	return written


func get_tournament_season(unit_id: int, season: int) -> Dictionary:
	for unit in units:
		if int(unit.get("id", 0)) == unit_id and season == season_number:
			return DbResult.ok(TournamentHistory.snapshot(unit, season))
	for record in _pending_history:
		if str(record.get("kind", "")) == "tournament_season" and int(record.get("unit_id", 0)) == unit_id and int(record.get("season", 0)) == season:
			return DbResult.ok(record["unit"].duplicate(true))
	return SaveStoreScript.new().tournament_season(history_head, unit_id, season)


## All editions of this tournament, including the live season. Club splits stay inside the bag.
func career_player_stats(unit: Dictionary) -> Dictionary:
	var unit_id := int(unit.get("id", 0))
	var pending := _pending_stat_bags(unit_id)
	var key := "%d:%d:%d" % [history_head, unit_id, pending.size()]
	if _career_stats_cache_key != key:
		var loaded := SaveStoreScript.new().tournament_stat_bags(history_head, unit_id, season_number)
		if not loaded.get("success", false):
			return {"ok": false, "error": str(loaded.get("error", "Не удалось прочитать архив турнира")), "bag": {}}
		var bags: Array = loaded.get("data", [])
		bags.append_array(pending)
		_career_stats_history = UnitSeasonStatsScript.combine(bags)
		_career_stats_cache_key = key
	var bag := UnitSeasonStatsScript.combine([
		_career_stats_history,
		UnitSeasonStatsScript.ensure(unit),
	])
	return {"ok": true, "bag": bag}


func _pending_stat_bags(unit_id: int) -> Array:
	var bags: Array = []
	for record in _pending_history:
		if typeof(record) != TYPE_DICTIONARY or str(record.get("kind", "")) != "tournament_season":
			continue
		if int(record.get("unit_id", 0)) != unit_id or int(record.get("season", 0)) == season_number:
			continue
		var snap: Variant = record.get("unit", {})
		if typeof(snap) != TYPE_DICTIONARY:
			continue
		var bag: Variant = (snap as Dictionary).get(UnitSeasonStatsScript.KEY, {})
		if typeof(bag) == TYPE_DICTIONARY and not (bag as Dictionary).is_empty():
			bags.append(bag)
	return bags


func _prepare_legacy_history(slot: String, payload: Dictionary) -> Dictionary:
	if int(payload.get("version", 0)) >= 11:
		return DbResult.ok({})
	var active: Dictionary = {}
	for section in ["players_by_club", "youth_players_by_club", "reserve_players_by_club"]:
		if typeof(payload.get(section, {})) != TYPE_DICTIONARY:
			return DbResult.fail("Повреждённое сохранение: секция %s" % section)
		var map: Dictionary = payload.get(section, {})
		for squad in map.values():
			if typeof(squad) == TYPE_ARRAY:
				for player in squad:
					if typeof(player) == TYPE_DICTIONARY:
						active[int(player.get("id", 0))] = true
	if typeof(payload.get("free_agents", [])) != TYPE_ARRAY:
		return DbResult.fail("Повреждённое сохранение: секция free_agents")
	for player in payload.get("free_agents", []):
		if typeof(player) == TYPE_DICTIONARY:
			active[int(player.get("id", 0))] = true
	var legacy: Dictionary = CareerArchiveScript.read_legacy(slot, int(payload.get("season_number", 1)), active)
	if not legacy["success"]:
		return legacy
	var imported: Dictionary = SaveStoreScript.new().append_history(0, legacy["data"])
	if imported["success"]:
		payload["history_head"] = int(imported["data"]["history_head"])
	return imported


func _roll_player_stats() -> void:
	for map in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in map.keys():
			for player in map[club_id]:
				if typeof(player) == TYPE_DICTIONARY:
					PlayerStatsScript.roll_season(player, season_number, int(club_id))
	for player in free_agents:
		if typeof(player) == TYPE_DICTIONARY:
			PlayerStatsScript.roll_season(player, season_number, 0)


func _begin_season_for_players() -> void:
	var reset_yellows: Dictionary = {}
	for unit in units:
		if _yellow_reset_of(unit) == DisciplineRulesScript.RESET_NEVER:
			continue
		for club_id in (unit.get("clubs_by_id", {}) as Dictionary).keys():
			reset_yellows[int(club_id)] = true
	for map in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in map.keys():
			var wipe: bool = reset_yellows.has(int(club_id))
			for player in map[club_id]:
				if typeof(player) != TYPE_DICTIONARY:
					continue
				PlayerConditionScript.begin_season(player, wipe)
	for player in free_agents:
		if typeof(player) == TYPE_DICTIONARY:
			PlayerConditionScript.begin_season(player, true)


func _run_youth_intake() -> void:
	var clubs_by_id := _collect_session_clubs()
	var clubs: Array = []
	for club_id in clubs_by_id.keys():
		var club: Dictionary = clubs_by_id[club_id]
		club["id"] = int(club_id)
		clubs.append(club)
	if clubs.is_empty():
		return
	var countries := _load_countries_for_clubs(clubs_by_id)
	var id_state := {"next_id": maxi(_next_player_id, _max_player_id() + 1)}
	var intake: Dictionary = YouthIntakeScript.generate_youth_intake(
		clubs, countries, _rng, id_state, {}
	)
	for club_id in intake.keys():
		var id := int(club_id)
		var existing: Array = youth_players_by_club.get(id, [])
		existing.append_array(intake[club_id])
		youth_players_by_club[id] = existing
	_next_player_id = int(id_state.get("next_id", _next_player_id))


func _max_player_id() -> int:
	var max_id := 0
	for map in [players_by_club, youth_players_by_club, reserve_players_by_club]:
		for club_id in map.keys():
			for player in map[club_id]:
				if typeof(player) == TYPE_DICTIONARY:
					max_id = maxi(max_id, int(player.get("id", 0)))
	for player in free_agents:
		if typeof(player) == TYPE_DICTIONARY:
			max_id = maxi(max_id, int(player.get("id", 0)))
	return max_id


func _max_coach_id() -> int:
	var max_id := 0
	for team in national_teams.values():
		max_id = maxi(max_id, int((team.get("coach", {}) as Dictionary).get("id", 0)))
	for club_id in coaches_by_club.keys():
		var coach: Variant = coaches_by_club[club_id]
		if typeof(coach) == TYPE_DICTIONARY:
			max_id = maxi(max_id, int(coach.get("id", 0)))
	for pool in ["free", "retired"]:
		for coach in coach_market.get(pool, []):
			max_id = maxi(max_id, int(coach.get("id", 0)))
	return max_id


func _migrate_twenty_player_rosters() -> void:
	for club_id in players_by_club:
		var source: Array=players_by_club[club_id].duplicate()
		source.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
			if int(a.get("current_ability",0))==int(b.get("current_ability",0)): return int(a.id)<int(b.id)
			return int(a.get("current_ability",0))>int(b.get("current_ability",0)))
		var chosen: Array=[]
		var seen := {}
		for position in PlayerTypes.POSITIONS:
			var need := PlayerTypes.squad_slot_min(position)
			for player in source:
				if need<=0: break
				if str(player.position)==position and not seen.has(int(player.id)):
					chosen.append(player); seen[int(player.id)]=true; need-=1
		for player in source:
			if not seen.has(int(player.id)) and PlayerTypes.can_add_squad_position(chosen,str(player.position)):
				chosen.append(player); seen[int(player.id)]=true
		var reserve: Array=reserve_players_by_club.get(club_id,[])
		for player in source:
			if not seen.has(int(player.id)):
				player.is_reserve=true
				player.is_youth=false
				reserve.append(player)
		players_by_club[club_id]=chosen
		reserve_players_by_club[club_id]=reserve
