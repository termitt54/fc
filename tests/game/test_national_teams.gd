extends Node

const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		push_error("National-team tests require isolated benchmark userdata")
		get_tree().quit(1)
		return
	var repo := CountryRepository.new()
	var continent: int = int(ContinentRepository.new().get_all()["data"][0]["id"])
	for i in 2:
		if not repo.abbreviation_exists("NTEST%d" % i):
			check(repo.create({"name": "National test country %d" % i, "abbreviation": "NTEST%d" % i, "continent_id": continent})["success"], "Test country created")
	var fixture := make_fixture()
	check(GameSession.apply_save_payload(fixture.duplicate(true))["success"], "Fixture loads")
	var countries: Array = fixture["test_country_ids"]
	var country := int(countries[0])
	var nid := NationalTeams.team_id(country)
	check(not GameSession._collect_session_clubs().has(nid), "National teams excluded from transfer/economy participants")
	check(not CoachMarket.clubs_of(GameSession).has(nid), "Club boards exclude national teams")
	check(GameSession.get_club_coach(nid).get("employment_status", "") == "national", "Dedicated national coach appointed")
	check(int(GameSession.get_club_coach(nid).get("club_id", -1)) == 0, "National coach has no club job")
	check(GameSession.advance_day()["success"], "Club regular match played")
	check(not GameSession.units[1].get("international_started", false), "National tournament waits for club final")
	var guard := 0
	while not bool(GameSession.units[1].get("international_started", false)) and guard < 12:
		check(GameSession.advance_day()["success"], "Club playoff day completes")
		guard += 1
	check(PlayoffManager.is_unit_season_complete(GameSession.units[0]), "Club final completed before national window")
	check(GameSession.units[1].get("international_started", false), "National tournament starts after final")
	var team: Dictionary = GameSession.national_teams[country]
	check(team["squad_ids"].size() == 20, "20 players called up")
	var ids: Array = team["squad_ids"].duplicate()
	var roster := NationalTeams.roster(GameSession, nid)
	for player in roster:
		check(int(player["nationality_country_id"]) == country, "Nationality eligibility")
		check(int(player["club_id"]) < NationalTeams.TEAM_ID_BASE, "Call-up preserves club membership")
	var victim: Dictionary = roster[0]
	var club_yellows := int(victim.get("yellow_running", 0))
	var club_stats := PlayerStats.season_of(victim).duplicate(true)
	var injury_entry := {"player_id": victim["id"], "minutes": 90, "started": true, "rating": 7.0, "yellow": 1, "injury_rounds": 2, "injury_grade": "minor"}
	NationalTeams.apply_report(GameSession, nid, {"players": [injury_entry]}, {"minutes_played": 90}, 1, {"yellow_threshold": 5, "yellow_ban": 1, "red_ban": 2})
	check(PlayerStats.season_of(victim) == club_stats, "National stats do not alter club stats")
	check(int(victim.get("yellow_running", 0)) == club_yellows, "National cards do not alter club cards")
	check(victim.get("national_stats", []).size() == 1, "National statistics recorded")
	check(PlayerCondition.is_injured(victim), "Injury shared with club")
	victim["injury_rounds"] = 0
	var available := NationalTeams.match_squad(GameSession, nid)
	check(not available.any(func(p): return int(p["id"]) == int(victim["id"])), "Injured player withdrawn for entire tournament even after recovery")
	check(team["squad_ids"] == ids, "No replacement in locked squad")
	var saved := GameSession.save_game("zz_national_test")
	check(saved["success"], "Mid-tournament save succeeds")
	check(GameSession.load_game("zz_national_test")["success"], "Mid-tournament save loads")
	team = GameSession.national_teams[country]
	check(team["squad_ids"] == ids and int(victim["id"]) in team["withdrawn_ids"], "Call-ups and injury exclusion survive load")
	guard = 0
	while not GameSession.season_finished and guard < 25:
		check(GameSession.advance_day()["success"], "International day completes")
		guard += 1
	check(GameSession.season_finished, "Season ends only after international tournament")
	check(not (GameSession.units[1].get("winners", []) as Array).is_empty(), "International champion saved")
	check(int(GameSession.national_teams[country].rating.games) > 0, "Live national matches update Elo")
	check(GameSession.units[1].matches.all(func(row): return not bool(row.get("played", false)) or bool(row.get("elo_counted", false))), "All played international matches counted")
	var live_country: Dictionary = GameSession.national_teams[country].country
	var previous_talent := int(live_country.youth_talent)
	live_country.youth_talent = 96
	var effective_countries: Dictionary = GameSession._load_countries_for_clubs({1: {"country_id": country}})
	check(int(effective_countries[country].youth_talent) == 96, "Youth generation reads save-local dynamic talent")
	live_country.youth_talent = previous_talent
	check(GameSession.start_new_season()["success"], "Next season starts")
	check(not NationalTeams.due(GameSession.units[1], GameSession.season_number), "Four-year tournament skips off years")
	GameSession.delete_save("zz_national_test")
	# Compare both day implementations with exactly the same coaches and RNG.
	var native_fixture := capture_fixture(fixture)
	GameSession.apply_save_payload(native_fixture.duplicate(true))
	GameSession._rng.seed = 419
	for i in 7:
		if not GameSession.season_finished:
			GameSession.advance_day()
	var expected := var_to_bytes([GameSession.units, GameSession.players_by_club, GameSession.national_teams, GameSession._rng.state])
	GameSession.apply_save_payload(native_fixture.duplicate(true))
	GameSession._rng.seed = 419
	for i in 7:
		if not GameSession.season_finished:
			await GameSession.advance_day_async(1)
	check(var_to_bytes([GameSession.units, GameSession.players_by_club, GameSession.national_teams, GameSession._rng.state]) == expected, "Sync and sliced national calendars agree")
	test_selection()
	test_legacy_save(fixture)
	test_multiple_tournaments(fixture)
	test_coach_turnover(country)
	await test_cards(country, nid)
	await test_repository(countries)
	GameSession.clear()
	print("=== National teams: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func make_fixture() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 815
	var countries: Array = CountryRepository.new().get_all()["data"].slice(0, 2)
	var cids: Array = []
	var teams: Dictionary = {}
	var squads: Dictionary = {}
	var coaches: Dictionary = {}
	var clubs: Dictionary = {}
	for i in 2:
		var cid := int(countries[i]["id"])
		cids.append(cid)
		var tid := NationalTeams.team_id(cid)
		teams[tid] = NationalTeams.identity(countries[i])
		var club_id := i + 1
		clubs[club_id] = {"id": club_id, "name": "Club %d" % club_id, "country_id": cid, "reputation": 500}
		coaches[club_id] = Fixtures.coach(club_id, rng)
		squads[club_id] = Fixtures.squad(club_id, 60, rng) + Fixtures.squad(club_id + 10, 70, rng)
		for player in squads[club_id]:
			player["club_id"] = club_id
			player["nationality_country_id"] = cid
			player["season_stats"] = PlayerStats.blank(1, club_id)
	var builder := SeasonBuilder.new()
	var club_unit := builder._build_unit_season({"id": 1, "name": "League"}, {"id": 1, "competition_type": "DIVISIONS", "divisions_count": 1, "teams_per_division": 2, "matches_vs_own": 1, "teams_playoff": 2, "playoff_format": PlayoffRules.FORMAT_SINGLE}, clubs, clubs.keys(), rng)
	var national_unit := builder._build_unit_season({"id": 2, "name": "World Cup", "scope_type": "INTERNATIONAL", "periodicity": "QUADRENNIAL", "start_season": 1}, {"id": 2, "competition_type": "KNOCKOUT", "playoff_format": PlayoffRules.FORMAT_SINGLE}, teams, teams.keys(), rng)
	return {"version": GameSession.SAVE_VERSION, "season_number": 1, "season_day": 1, "units": [club_unit, national_unit], "players_by_club": squads, "coaches_by_club": coaches, "test_country_ids": cids}

func capture_fixture(fixture: Dictionary) -> Dictionary:
	GameSession.apply_save_payload(fixture.duplicate(true))
	var result := fixture.duplicate(true)
	result["national_teams"] = GameSession.national_teams.duplicate(true)
	result["coach_market"] = GameSession.coach_market.duplicate(true)
	result["next_coach_id"] = GameSession._next_coach_id
	return result

func test_selection() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 714
	var pool := Fixtures.squad(51, 65, rng, 22) + Fixtures.squad(52, 65, rng, 22) + Fixtures.squad(53, 65, rng, 22)
	var coach := Fixtures.coach(51, rng)
	coach["attributes"]["professionalism"] = 20
	var good := 0.0
	var poor := 0.0
	var by_id: Dictionary = {}
	for player in pool:
		by_id[player["id"]] = player
	for seed in 80:
		rng.seed = seed + 100
		coach["attributes"]["professionalism"] = 20
		for id in NationalTeams.select_squad(pool, coach, rng):
			good += NationalTeams.selection_value(by_id[id], coach)
		rng.seed = seed + 100
		coach["attributes"]["professionalism"] = 1
		for id in NationalTeams.select_squad(pool, coach, rng):
			poor += NationalTeams.selection_value(by_id[id], coach)
	print("NATIONAL SELECTION good=",good," poor=",poor," ratio=",good/poor)
	# Integer attributes and a finite seeded cohort: allow 0.1 percentage point around the 3% target.
	check(good > poor * 1.029, "Professional coach improves call-up value by approximately 3% across 80 seeds")
	var good_xi := 0.0
	var poor_xi := 0.0
	for seed in 80:
		for skill in [20, 1]:
			coach["attributes"]["professionalism"] = skill
			coach["national_selection"] = true
			rng.seed = 500 + seed
			var lineup := LineupSelector.build(pool, [], coach, {"formation": "2-3-2", "style": "control"}, rng)
			var value := 0.0
			for record in lineup["starters"]:
				value += LineupSelector.role_value(MatchRatings.of(record["player"]), str(record["slot"]), "control") * float(record["fit"])
			if skill == 20:
				good_xi += value
			else:
				poor_xi += value
	check(good_xi > poor_xi * 1.01, "Professional coach selects stronger starting teams across 80 seeds")
	var competent_squad := 0.0
	var competent_xi := 0.0
	coach["attributes"]["professionalism"] = 14
	for seed in 80:
		rng.seed = seed + 100
		for id in NationalTeams.select_squad(pool, coach, rng):
			competent_squad += NationalTeams.selection_value(by_id[id], coach)
		rng.seed = 500 + seed
		var lineup := LineupSelector.build(pool, [], coach, {"formation": "2-3-2", "style": "control"}, rng)
		for record in lineup["starters"]:
			competent_xi += LineupSelector.role_value(MatchRatings.of(record["player"]), str(record["slot"]), "control") * float(record["fit"])
	check(competent_squad >= good * 0.995, "Competent coach loses under 0.5% call-up value across 80 seeds")
	check(competent_xi >= good_xi * 0.995, "Competent coach loses under 0.5% starting value across 80 seeds")
	check(competent_squad > poor and competent_xi > poor_xi, "Competent coach consistently outperforms poor selection")
	var player: Dictionary = pool[0]
	player["season_stats"] = {"matches": 10, "rating_sum": 80.0}
	var good_form := NationalTeams.selection_value(player, coach)
	player["season_stats"]["rating_sum"] = 50.0
	var bad_form := NationalTeams.selection_value(player, coach)
	check(good_form > bad_form + 5.0, "Actual performances affect call-up ranking")
	check(good_form - bad_form <= 8.0001, "Form cannot outweigh a large difference in playing ability")
	var short_pool: Array = pool.slice(0, 12)
	short_pool[0]["injury_rounds"] = 3
	var short_ids := NationalTeams.select_squad(short_pool, coach, rng)
	check(short_ids.size() == 11 and int(short_pool[0]["id"]) not in short_ids, "Short national squad uses only existing healthy players")
	var builder := SeasonBuilder.new()
	var identities: Dictionary = {NationalTeams.team_id(1): {"id": NationalTeams.team_id(1)}, NationalTeams.team_id(2): {"id": NationalTeams.team_id(2)}}
	var league := builder._build_unit_season({"scope_type": "INTERNATIONAL"}, {"competition_type": "LEAGUE"}, identities, identities.keys(), rng)
	check((league["divisions"] as Array).size() == 1 and not (league["matches"] as Array).is_empty(), "Legacy national league converts to a playable group plus playoff")
	var groups := builder._build_unit_season({"scope_type": "INTERNATIONAL"}, {"competition_type": "GROUP_AND_PLAYOFF", "divisions_count": 1, "teams_per_division": 2}, identities, identities.keys(), rng)
	check(groups["playoff"]["enabled"] and not (groups["matches"] as Array).is_empty(), "Groups plus playoff creates both stages")

func test_legacy_save(fixture: Dictionary) -> void:
	var old := fixture.duplicate(true)
	old["version"] = 12
	old["rng_seed"] = 427
	old["rng_state"] = 91357
	old.erase("national_teams")
	for coach in old["coaches_by_club"].values():
		coach["attributes"].erase("professionalism")
	check(GameSession.apply_save_payload(old)["success"], "Version 12 save remains compatible")
	check(GameSession._rng.state == 91357, "National migration preserves saved match RNG")
	check(GameSession.coaches_by_club.values().all(func(c): return c["attributes"].has("professionalism")), "Old club coaches receive professionalism")
	var bad := fixture.duplicate(true)
	bad["national_teams"] = {1: {"squad_ids": "broken"}}
	check(not GameSession.apply_save_payload(bad)["success"], "Malformed national squad rejected before loading")

func test_multiple_tournaments(fixture: Dictionary) -> void:
	var payload := fixture.duplicate(true)
	var second: Dictionary = payload["units"][1].duplicate(true)
	second["id"] = 3
	second["competition_id"] = 3
	second["competition_name"] = "Continental nations"
	second["periodicity"] = "ANNUAL"
	payload["units"].append(second)
	GameSession.apply_save_payload(payload)
	var guard := 0
	while not GameSession.season_finished and guard < 30:
		GameSession.advance_day()
		guard += 1
	check(GameSession.season_finished, "Two international tournaments complete")
	var a: Dictionary = GameSession.units[1]
	var b: Dictionary = GameSession.units[2]
	var max_first_day := 0
	for match_row in a.get("matches", []):
		max_first_day = maxi(max_first_day, int(match_row["season_day"]))
	check(int(b.get("international_start_day", 0)) > max_first_day, "International tournaments never overlap")
	check((a.get("winners", []) as Array).size() == 1 and (b.get("winners", []) as Array).size() == 1, "Both international tournaments retain winners")
	check(GameSession.start_new_season()["success"], "Season with two tournaments closes")
	guard = 0
	while not GameSession.season_finished and guard < 30:
		GameSession.advance_day()
		guard += 1
	check(GameSession.season_finished, "Off-year national calendar finishes")
	check(not GameSession.units[1].get("international_started", false), "Four-year tournament is not played in second season")
	check(GameSession.units[2].get("international_started", false), "Annual tournament plays in second season")

func test_coach_turnover(country: int) -> void:
	var team: Dictionary = GameSession.national_teams[country]
	var original: Dictionary = team["coach"]
	var original_id := int(original["id"])
	original["retirement_age"] = int(original["age"]) + 1
	NationalTeams.close_season(GameSession, GameSession._rng)
	check(int(team["coach"]["id"]) != original_id, "Retired national coach replaced")
	check(GameSession.coach_market["retired"].any(func(c): return int(c["id"]) == original_id), "Retired national coach remains in archive")
	check(int(original["career"][-1].get("season_to", 0)) > 0, "National career stint closed")
	var seen: Dictionary = {}
	var unique := true
	var employed: Array = GameSession.coaches_by_club.values()
	for national in GameSession.national_teams.values():
		employed.append(national["coach"])
	for coach in employed + GameSession.coach_market["free"] + GameSession.coach_market["retired"]:
		var id := int(coach["id"])
		unique = unique and not seen.has(id)
		seen[id] = true
	check(unique, "Coach IDs unique across club, country, free market and archive")

func test_cards(country: int, nid: int) -> void:
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	screen._open_club_card(GameSession.units[1], nid)
	check(screen._national_team_card.is_open(), "International participant opens national card")
	screen._national_team_card.refresh()
	var coach := GameSession.get_club_coach(nid)
	screen._on_national_coach_requested(int(coach["id"]))
	check(screen._coach_card.is_open(), "National coach profile opens")
	screen._coach_card.close()
	check(screen._national_team_card.is_open(), "Coach close returns to national team")
	var roster := NationalTeams.roster(GameSession, nid)
	if not roster.is_empty():
		screen._on_national_player_requested(int(roster[0]["id"]))
		check(screen._player_card.is_open(), "Called-up player profile opens")
		screen._player_card.close()
		check(screen._national_team_card.is_open(), "Player close returns to national team")
	screen.queue_free()
	await get_tree().process_frame

func test_repository(countries: Array) -> void:
	var competition := CompetitionRepository.new().create({"name": "National test", "scope_type": "INTERNATIONAL", "age_group": "SENIOR"})
	check(competition["success"], "International competition created")
	if not competition["success"]:
		return
	var competition_id := int(competition["data"]["id"])
	var repo := CompetitionUnitRepository.new()
	var unit := repo.create({"competition_id": competition_id, "unit_kind": "DIVISION", "name": "Test national unit"})
	check(unit["success"], "National unit created")
	if unit["success"]:
		var uid := int(unit["data"]["id"])
		check(repo.set_country_ids(uid, countries)["success"], "National participants saved")
		check(repo.get_country_ids(uid)["data"].size() == 2, "National participants loaded")
		check(int(repo.get_by_id(uid)["data"]["clubs_count"]) == 2, "Picker counts national participants")
		check(repo.get_club_ids(uid)["data"].is_empty(), "Country IDs never stored as clubs")
	CompetitionRepository.new().delete(competition_id)
