extends Node

var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	test_pots()
	test_elo_pots()
	await test_repository_editor()
	test_edition()
	test_playable_tournament()
	print("International draw: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func identities(count: int) -> Dictionary:
	var result: Dictionary = {}
	for i in count:
		var id := NationalTeams.team_id(i + 1)
		result[id] = {"id": id, "name": "Country %d" % i, "reputation": 1000 - i * 20}
	return result

func test_pots() -> void:
	var teams := identities(24)
	var rng := RandomNumberGenerator.new()
	var variants: Dictionary = {}
	for seed_value in 40:
		rng.seed = seed_value + 51
		var groups := InternationalDraw.draw(teams, 4, {}, rng)
		variants[JSON.stringify(groups)] = true
		var seen: Array = []
		for group in groups:
			var pots: Array = []
			for id in group["club_ids"]:
				seen.append(id)
				pots.append(int((int(id) - NationalTeams.TEAM_ID_BASE - 1) / 4))
			pots.sort()
			check(pots == [0, 1, 2, 3, 4, 5], "Each group receives one team from each reputation pot")
		seen.sort()
		check(seen == teams.keys(), "All participants drawn once")
	check(variants.size() > 30, "Draw varies across editions")
	rng.seed = 75
	var first := InternationalDraw.draw(teams, 4, {}, rng)
	rng.seed = 75
	check(first == InternationalDraw.draw(teams, 4, {}, rng), "Seeded draw is reproducible")
	rng.seed = 75
	check(first != InternationalDraw.draw(teams, 4, {"mode": InternationalDraw.RANDOM}, rng), "Random mode does not use reputation pots")
	check(InternationalDraw.rules({"mode": "future", "constraints": {"host": 7}})["constraints"]["host"] == 7, "Extensible rules preserve future constraints")
	var uneven := InternationalDraw.draw(identities(23), 4, {}, rng)
	var sizes: Array = []
	for group in uneven:
		sizes.append(group["club_ids"].size())
	sizes.sort()
	check(sizes == [5, 6, 6, 6], "Uneven groups stay balanced without losing a participant")
	check(InternationalDraw.qualifier_count(24, 6, 0) == 8, "Automatic playoff size is a power of two")
	var preview_unit := SeasonBuilder.new()._build_unit_season({"scope_type": "INTERNATIONAL"}, {"competition_type": "GROUP_AND_PLAYOFF", "divisions_count": 3, "teams_per_division": 4, "teams_playoff": 8}, identities(12), identities(12).keys(), rng)
	InternationalDraw.prepare(preview_unit, 1, rng, 1)
	var preview := SeasonPreview.build(preview_unit, 1, {}, {})
	var qualification_total := 0.0
	for section in preview["sections"]:
		check(str(section["title"]) != "Регулярный сезон", "National preview contains no regular champion")
		if section["id"] == "playoff":
			for row in section["rows"]:
				qualification_total += float(row.get("qualify_chance", 0))
	check(absf(qualification_total - 800.0) < 2.0, "Preview includes all eight berths from three groups, including best third places")
	# A changed current reputation moves this team from last pot to first.
	teams[NationalTeams.team_id(24)]["reputation"] = 2000
	var changed := InternationalDraw.draw(teams, 4, {}, rng)
	for group in changed:
		var top := 0
		for id in group["club_ids"]:
			if int(id) in [NationalTeams.team_id(24), NationalTeams.team_id(1), NationalTeams.team_id(2), NationalTeams.team_id(3)]:
				top += 1
		check(top == 1, "Pots reflect changed reputation")

func test_repository_editor() -> void:
	var comp := CompetitionRepository.new().create({"name": "Draw integration test", "scope_type": "INTERNATIONAL", "age_group": "SENIOR"})
	check(comp["success"], "International competition created")
	if not comp["success"]:
		return
	var cid := int(comp["data"]["id"])
	var repo := CompetitionUnitRepository.new()
	var created := repo.create({"competition_id": cid, "unit_kind": "DIVISION", "name": "Groups", "competition_type": "DIVISIONS", "regular_season_enabled": true, "playoff_third_place": false, "matches_vs_other": 3, "teams_promote": 2})
	check(created["success"], "Unit insert includes draw rules migration")
	if created["success"]:
		var unit: Dictionary = created["data"]
		check(unit["competition_type"] == "GROUP_AND_PLAYOFF" and unit["playoff_third_place"], "Repository enforces national format and bronze")
		check(not unit["regular_season_enabled"] and unit["teams_promote"] == 0 and unit["matches_vs_other"] == 0, "League-only settings cannot leak into national tournaments")
		var updated := repo.update(int(unit["id"]), {"group_draw_rules": {"mode": InternationalDraw.RANDOM, "constraints": {"future": 3}}})
		check(updated["success"] and updated["data"]["group_draw_rules"]["mode"] == InternationalDraw.RANDOM, "Draw mode update roundtrips through SQLite")
		check(repo.get_by_competition(cid)["data"][0]["group_draw_rules"]["constraints"]["future"] == 3, "Future draw rules survive all repository reads")
		var elo_rules := InternationalDraw.rules(updated.data.group_draw_rules)
		elo_rules.mode = InternationalDraw.ELO
		updated = repo.update(int(unit.id), {"group_draw_rules": elo_rules})
		check(updated.success and repo.get_by_id(int(unit.id)).data.group_draw_rules.mode == InternationalDraw.ELO, "Elo draw mode survives SQLite update and read")
		var dialog: Control = load("res://scenes/world_editor/dialogs/competition_form_dialog.tscn").instantiate()
		add_child(dialog)
		dialog.open_edit(comp["data"])
		await get_tree().process_frame
		var text := texts(dialog)
		check("ГРУППОВОЙ ЭТАП" in text and "ЖЕРЕБЬЁВКА ГРУПП" in text and "Обязательный" in text, "Editor exposes group draw and mandatory bronze")
		check("Легионеры" not in text and "Рег. чемп." not in text and "+ Кубок" not in text, "National editor hides league settings")
		var found := false
		for field in dialog.find_children("*", "VBoxContainer", true, false):
			if field is WeSelectField and field.label == "Распределение по группам":
				found = field.selected_id == InternationalDraw.ELO and field._ids.has(InternationalDraw.ELO)
		check(found and text.contains("по текущему Elo"), "Editor exposes selected Elo option with matching explanation")
		dialog.free()
	CompetitionRepository.new().delete(cid)

func texts(node: Node) -> String:
	var result := ""
	if node is Control and not node.visible:
		return result
	if node is Label or node is Button:
		result += node.text + "\n"
	for child in node.get_children():
		result += texts(child)
	return result

func test_edition() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 415
	var teams := identities(8)
	var builder := SeasonBuilder.new()
	var unit := builder._build_unit_season({"id": 3, "scope_type": "INTERNATIONAL", "periodicity": "QUADRENNIAL"}, {"id": 3, "competition_type": "GROUP_AND_PLAYOFF", "divisions_count": 2, "teams_per_division": 4, "teams_playoff": 4, "matches_vs_own": 1, "playoff_format": "SINGLE", "group_draw_rules": {"mode": InternationalDraw.ELO}}, teams, teams.keys(), rng)
	var next_id := InternationalDraw.prepare(unit, 1, rng, 500)
	check(unit["matches"].size() == 12 and next_id == 512, "Two groups of four produce twelve matches with fresh IDs")
	for match_row in unit["matches"]:
		var home_group := -1
		var away_group := -2
		for group in unit["divisions"]:
			if int(match_row["home_id"]) in group["club_ids"]:
				home_group = group["index"]
			if int(match_row["away_id"]) in group["club_ids"]:
				away_group = group["index"]
		check(home_group == away_group, "Group fixtures never cross groups")
		match_row["played"] = true
		match_row["home_goals"] = 1
		match_row["away_goals"] = 0
	for row in unit["standings"]:
		row["played"] = 3
		row["points"] = int(row["club_id"]) % 4 * 3
	check(PlayoffManager.qualifier_ids(unit).size() == 4, "Two teams per group qualify")
	unit["playoff"]["teams"] = 5
	check(PlayoffManager.qualifier_ids(unit).size() == 5, "Extra qualifying berth is not discarded")
	unit["playoff"]["teams"] = 4
	var started := PlayoffManager.maybe_start(unit, 12, next_id)
	next_id = started["next_match_id"]
	check(unit["playoff"]["series"].size() == 2, "Group finish starts semifinals")
	for day in range(13, 17):
		for match_row in unit["matches"]:
			if not match_row["played"]:
				match_row["played"] = true
				match_row["home_goals"] = 2
				match_row["away_goals"] = 0
		var progressed := PlayoffManager.after_day_simulated(unit, day, next_id, 1)
		next_id = progressed["next_match_id"]
	check(PlayoffManager.is_unit_season_complete(unit), "Group tournament and bronze finish")
	var bronze := 0
	for match_row in unit["matches"]:
		if match_row.get("is_third_place", false):
			bronze += 1
	check(bronze == 1, "Exactly one mandatory bronze match")
	check(unit["winners"][0]["regular"].is_empty() and unit["winners"][0]["playoff"].size() == 4, "Only tournament medals enter national winners history")
	var next := GameSession._reset_unit_for_new_season(unit)
	check(not next.has("group_draw") and not next["international_started"], "New season discards previous draw marker")
	check(not NationalTeams.due(next, 2) and NationalTeams.due(next, 5), "Quadrennial schedule retained")
	var old_draw: Array = unit["group_draw"]["groups"]
	InternationalDraw.prepare(next, 5, rng, next_id)
	check(next["group_draw"]["season"] == 5 and next["group_draw"]["groups"] != old_draw, "Next edition receives a fresh draw")
	# Serialized in-progress groups are loaded as data, without drawing again.
	var payload := {"version": GameSession.SAVE_VERSION, "season_number": 5, "season_day": 20, "units": [next], "players_by_club": {}, "rng_seed": 12, "rng_state": 456}
	next["international_started"] = true
	check(GameSession.apply_save_payload(payload)["success"], "Drawn tournament payload loads")
	var locked: Dictionary = GameSession.units[0]["group_draw"].duplicate(true)
	var state: int = GameSession._rng.state
	NationalTeams.start_window(GameSession)
	check(GameSession.units[0]["group_draw"] == locked and GameSession._rng.state == state, "Already-started tournament never redraws on resume")
	GameSession.units[0] = GameSession._reset_unit_for_new_season(GameSession.units[0])
	GameSession.season_number = 6
	state = GameSession._rng.state
	NationalTeams.start_window(GameSession)
	check(not GameSession.units[0].has("group_draw") and GameSession._rng.state == state, "Off year consumes no draw randomness")
	GameSession.season_number = 9
	for cid in GameSession.national_teams:
		GameSession.national_teams[cid].rating.elo = 1500 + int(cid) * 10.25
		GameSession.national_teams[cid].country.elo = 0 # stale display copy
	NationalTeams.start_window(GameSession)
	check(GameSession.units[0].get("international_started", false) and int(GameSession.units[0]["group_draw"]["season"]) == 9, "Real national window draws the due edition")
	check(GameSession.units[0].group_draw.rules.mode == InternationalDraw.ELO, "Real tournament edition uses saved Elo mode")
	for id in GameSession.units[0].clubs_by_id:
		check(GameSession.units[0].clubs_by_id[id].elo == GameSession.national_teams[int(id) - NationalTeams.TEAM_ID_BASE].rating.elo, "Live draw reads current rating instead of stale country display")
	locked = GameSession.units[0]["group_draw"].duplicate(true)
	check(GameSession.save_game("zz_draw_test")["success"], "Draw saves to SQLite")
	check(GameSession.load_game("zz_draw_test")["success"], "Draw reloads from SQLite")
	state = GameSession._rng.state
	NationalTeams.start_window(GameSession)
	check(GameSession.units[0]["group_draw"] == locked and GameSession._rng.state == state, "SQLite save preserves groups and does not redraw")
	GameSession.delete_save("zz_draw_test")


func test_elo_pots() -> void:
	var teams := identities(24)
	var order := [1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 4, 8, 12, 16, 17, 18, 19, 20, 21, 22, 23, 24]
	var pots := {}
	for i in order.size():
		var id := NationalTeams.team_id(order[i])
		teams[id].elo = 3000.5 - i * 40.25
		pots[id] = int(i / 4)
	var rng := RandomNumberGenerator.new()
	for seed_value in 20:
		rng.seed = 814 + seed_value
		var groups := InternationalDraw.draw(teams, 4, {"mode": InternationalDraw.ELO}, rng)
		var seen := []
		for group in groups:
			var actual := []
			for id in group.club_ids:
				actual.append(pots[id])
				seen.append(id)
			actual.sort()
			check(actual == [0, 1, 2, 3, 4, 5], "Elo draw gives one national team from each Elo pot")
		seen.sort()
		check(seen == teams.keys(), "Elo draw retains every participant exactly once")
	check(InternationalDraw._draw_score({"reputation": 100, "elo": 2800.25}, InternationalDraw.REPUTATION) == 100, "Reputation mode no longer substitutes Elo")
	check(InternationalDraw._draw_score({"reputation": 100, "elo": 2800.25}, InternationalDraw.ELO) == 2800.25, "Elo draw preserves decimals and scores over 1000")
	check(InternationalDraw._draw_score({"reputation": 900}, InternationalDraw.ELO) == 1880, "Unplayed team uses shared initial national Elo formula")
	check(InternationalDraw.rules('{"mode":"ELO_POTS","constraints":{"future":7}}').mode == InternationalDraw.ELO, "Elo mode survives JSON rule decoding")
	check(InternationalDraw.options().size() == 3, "All three international draw methods are offered")
	rng.seed = 73
	var first := InternationalDraw.draw(teams, 4, {"mode": InternationalDraw.ELO}, rng)
	rng.seed = 73
	check(first == InternationalDraw.draw(teams, 4, {"mode": InternationalDraw.ELO}, rng), "Elo draw is reproducible with same seed")
	rng.seed = 73
	check(first != InternationalDraw.draw(teams, 4, {"mode": InternationalDraw.REPUTATION}, rng), "Elo and reputation modes use distinct rankings")

func test_playable_tournament() -> void:
	var countries: Array = CountryRepository.new().get_all()["data"]
	var repo := CountryRepository.new()
	var continent: int = int(ContinentRepository.new().get_all()["data"][0]["id"])
	while countries.size() < 8:
		var result := repo.create({"name": "Draw country %d" % countries.size(), "abbreviation": "DRW%d" % countries.size(), "continent_id": continent})
		check(result["success"], "Draw test country created")
		if not result["success"]:
			return
		countries.append(result["data"])
	var teams: Dictionary = {}
	var squads: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 197
	var fixtures := preload("res://tests/game/squad_fixtures.gd")
	for i in 8:
		var country: Dictionary = countries[i]
		var id := NationalTeams.team_id(int(country["id"]))
		teams[id] = NationalTeams.identity(country)
		var squad: Array = fixtures.squad(100 + i, 65, rng)
		for player in squad:
			player["nationality_country_id"] = int(country["id"])
			player["season_stats"] = PlayerStats.blank(1, 100 + i)
		squads[100 + i] = squad
	var unit := SeasonBuilder.new()._build_unit_season({"id": 7, "scope_type": "INTERNATIONAL"}, {"id": 7, "competition_type": "GROUP_AND_PLAYOFF", "divisions_count": 2, "teams_per_division": 4, "teams_playoff": 4, "matches_vs_own": 1, "playoff_format": "SINGLE"}, teams, teams.keys(), rng)
	check(GameSession.apply_save_payload({"version": GameSession.SAVE_VERSION, "season_number": 1, "season_day": 1, "units": [unit], "players_by_club": squads, "rng_seed": 776})["success"], "Playable group tournament loads")
	var days := 0
	while not GameSession.season_finished and days < 20:
		check(GameSession.advance_day()["success"], "Group tournament day simulates")
		days += 1
	unit = GameSession.units[0]
	check(GameSession.season_finished, "Actual simulation reaches tournament finish")
	check(unit["matches"].size() == 16 and unit["matches"].all(func(row): return bool(row.get("played", false))), "Simulation plays twelve group games, two semifinals, final and bronze")
	check(unit["winners"].size() == 1 and unit["winners"][0]["playoff"].size() == 4, "Simulation records all four international places")
