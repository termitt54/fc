class_name SeasonBuilder
extends RefCounted
## Boots a playable season snapshot from world-editor tournaments.


const FixtureGeneratorScript := preload("res://game/fixture_generator.gd")
const PlayoffManagerScript := preload("res://game/playoff_manager.gd")
const YouthIntakeScript := preload("res://game/youth_intake.gd")
const YouthGenerationConfigScript := preload("res://game/youth_generation_config.gd")
const CoachGeneratorScript := preload("res://game/coach_generator.gd")


func build_new_game(rng: RandomNumberGenerator = null) -> Dictionary:
	if not WorldDatabase.is_ready():
		return DbResult.fail("База мира недоступна")

	var competitions_result := CompetitionRepository.new().get_all()
	if not competitions_result["success"]:
		return competitions_result

	var unit_repo := CompetitionUnitRepository.new()
	var seasons: Array = []
	var season_number := 1
	var found_start := false
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var pending_units: Array = []
	var all_clubs: Dictionary = {}

	for competition in competitions_result["data"]:
		if not bool(competition.get("is_active", true)):
			continue
		var competition_id: int = int(competition.get("id", 0))
		if competition_id < 1:
			continue

		var start_season: int = int(competition.get("start_season", 1))
		if not found_start:
			season_number = start_season
			found_start = true
		else:
			season_number = mini(season_number, start_season)

		var units_result := unit_repo.get_by_competition(competition_id)
		if not units_result["success"]:
			continue
		for unit in units_result["data"]:
			var unit_id: int = int(unit.get("id", 0))
			var club_ids_result := unit_repo.get_club_ids(unit_id)
			var club_ids: Array = club_ids_result["data"] if club_ids_result["success"] else []
			var clubs_by_id := _load_clubs(club_ids)
			for club_id in clubs_by_id.keys():
				all_clubs[int(club_id)] = clubs_by_id[club_id]
			pending_units.append({
				"competition": competition,
				"unit": unit,
				"clubs_by_id": clubs_by_id,
				"club_ids": club_ids,
			})

	if pending_units.is_empty():
		return DbResult.fail("Нет турниров с составом. Добавьте юниты в редакторе мира.")

	var generated: Dictionary = _generate_all_players(all_clubs, rng)
	var detached: Dictionary = detach_squads_as_free_agents(generated.get("players_by_club", {}))
	var players_by_club: Dictionary = detached.get("players_by_club", {})
	var free_agents: Array = detached.get("free_agents", [])
	var youth_players_by_club: Dictionary = generated.get("youth_players_by_club", {})
	var id_state: Dictionary = generated.get("id_state", {"next_id": 1})
	var coach_id_state := {"next_id": 1}
	var coaches_by_club: Dictionary = CoachGeneratorScript.generate_for_clubs(
		all_clubs, rng, {}, coach_id_state, maxi(season_number, 1)
	)

	for spec in pending_units:
		seasons.append(_build_unit_season(
			spec["competition"],
			spec["unit"],
			spec["clubs_by_id"],
			spec["club_ids"],
			rng
		))

	return DbResult.ok({
		"season_number": maxi(season_number, 1),
		"season_day": GameSession.MARKET_OPEN_DAY,
		"units": seasons,
		"players_by_club": players_by_club,
		"youth_players_by_club": youth_players_by_club,
		"free_agents": free_agents,
		"coaches_by_club": coaches_by_club,
		"next_player_id": int(id_state.get("next_id", 1)),
		"next_coach_id": int(coach_id_state.get("next_id", 1)),
	})


func _build_unit_season(
	competition: Dictionary,
	unit: Dictionary,
	clubs_by_id: Dictionary,
	club_ids: Array,
	rng: RandomNumberGenerator = null
) -> Dictionary:
	var unit_id: int = int(unit.get("id", 0))

	var competition_type: String = str(unit.get("competition_type", CompetitionTypes.TYPE_LEAGUE))
	var divisions: Array = []
	var matches: Array = []

	if competition_type == CompetitionTypes.TYPE_DIVISIONS:
		var generated: Dictionary = FixtureGeneratorScript.build_regular_season(
			club_ids,
			int(unit.get("divisions_count", CompetitionUnitRepository.DIVISIONS_COUNT_DEFAULT)),
			int(unit.get("teams_per_division", CompetitionUnitRepository.TEAMS_PER_DIVISION_DEFAULT)),
			int(unit.get("matches_vs_own", CompetitionUnitRepository.MATCHES_VS_OWN_DEFAULT)),
			int(unit.get("matches_vs_other", CompetitionUnitRepository.MATCHES_VS_OTHER_DEFAULT)),
			rng
		)
		divisions = generated["divisions"]
		matches = generated["matches"]
	else:
		divisions = [{"index": 0, "club_ids": club_ids.duplicate()}]
		matches = []

	var standings := _build_standings(divisions)
	var teams_playoff: int = int(unit.get("teams_playoff", 0))
	var playoff_enabled := teams_playoff > 0 and competition_type == CompetitionTypes.TYPE_DIVISIONS
	var playoff := {
		"enabled": playoff_enabled,
		"teams": teams_playoff,
		"format": str(unit.get("playoff_format", PlayoffRules.FORMAT_DEFAULT)),
		"series_wins": int(unit.get("playoff_series_wins", PlayoffRules.SERIES_WINS_DEFAULT)),
		"third_place": bool(unit.get("playoff_third_place", false)),
		"seeding": str(unit.get("playoff_seeding", PlayoffRules.SEEDING_DEFAULT)),
		"scope": str(unit.get("playoff_scope", CompetitionUnitRepository.PLAYOFF_SCOPE_DEFAULT)),
		"slots": [],
		"matches": [],
		"series": [],
		"started": false,
		"finished": false,
		"champion_id": 0,
		"current_round": 0,
	}

	return {
		"id": unit_id,
		"competition_id": int(competition.get("id", 0)),
		"competition_name": str(competition.get("name", "")),
		"competition_short_name": str(competition.get("short_name", "")),
		"name": str(unit.get("name", "")),
		"unit_kind": str(unit.get("unit_kind", "")),
		"competition_type": competition_type,
		"label": _unit_label(competition, unit),
		"foreign_players_limit": int(unit.get("foreign_players_limit", 0)),
		"rules": unit.duplicate(true),
		"divisions": divisions,
		"standings": standings,
		"matches": matches,
		"playoff": playoff,
		"winners": [],
		"clubs_by_id": clubs_by_id,
		"estimated_days": _estimate_unit_days(matches, playoff),
	}


func _estimate_unit_days(matches: Array, playoff: Dictionary) -> int:
	var regular_max := 1
	for match_row in matches:
		regular_max = maxi(regular_max, int(match_row.get("season_day", 1)))
	return regular_max + PlayoffManagerScript.estimate_days(playoff)


func _generate_all_players(clubs_by_id: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var clubs: Array = []
	for club_id in clubs_by_id.keys():
		var club: Dictionary = clubs_by_id[club_id]
		if typeof(club) != TYPE_DICTIONARY:
			continue
		club["id"] = int(club_id)
		clubs.append(club)

	var countries_by_id := _load_countries_for_clubs(clubs)
	var name_pool_cache: Dictionary = {}
	var id_state := {"next_id": 1}
	var first_team: Dictionary = YouthIntakeScript.generate_first_team_squads(
		clubs, countries_by_id, rng, id_state, name_pool_cache
	)
	return {
		"players_by_club": first_team,
		"youth_players_by_club": {},
		"id_state": id_state,
	}


static func detach_squads_as_free_agents(players_by_club: Dictionary) -> Dictionary:
	var free_agents: Array = []
	var empty_clubs: Dictionary = {}
	for club_id in players_by_club.keys():
		var id := int(club_id)
		empty_clubs[id] = []
		for player in players_by_club[club_id]:
			if typeof(player) != TYPE_DICTIONARY:
				continue
			player["club_id"] = 0
			player["contract_status"] = GameSession.STATUS_FREE_AGENT
			player["contract_years"] = 0
			free_agents.append(player)
	return {
		"free_agents": free_agents,
		"players_by_club": empty_clubs,
	}


func _load_countries_for_clubs(clubs: Array) -> Dictionary:
	var countries: Dictionary = {}
	var repo := CountryRepository.new()
	for club in clubs:
		var country_id := int(club.get("country_id", 0))
		if countries.has(country_id):
			continue
		if country_id > 0:
			var loaded := repo.get_by_id(country_id)
			if loaded["success"]:
				countries[country_id] = loaded["data"]
				continue
		countries[country_id] = {
			"id": country_id,
			"youth_talent": YouthGenerationConfigScript.YOUTH_TALENT_DEFAULT,
		}
	return countries


func _unit_label(competition: Dictionary, unit: Dictionary) -> String:
	var competition_name: String = str(competition.get("short_name", "")).strip_edges()
	if competition_name.is_empty():
		competition_name = str(competition.get("name", "")).strip_edges()
	var unit_name: String = str(unit.get("name", "")).strip_edges()
	if competition_name.is_empty():
		return unit_name
	if unit_name.is_empty() or unit_name == competition_name:
		return competition_name
	return "%s — %s" % [competition_name, unit_name]


func _build_standings(divisions: Array) -> Array:
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


func _load_clubs(club_ids: Array) -> Dictionary:
	var result: Dictionary = {}
	if club_ids.is_empty():
		return result
	var repo := ClubRepository.new()
	for club_id in club_ids:
		var id: int = int(club_id)
		if id < 1 or result.has(id):
			continue
		var loaded := repo.get_by_id(id)
		if loaded["success"]:
			result[id] = loaded["data"]
		else:
			result[id] = {
				"id": id,
				"name": "Клуб #%d" % id,
				"short_name": "#%d" % id,
			}
	return result
