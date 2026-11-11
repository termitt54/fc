extends Node
var passed := 0
var failed := 0
const View := preload("res://scenes/game/coach_market_view.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var fixture := _fixture()
	check(GameSession.apply_save_payload(fixture.duplicate(true))["success"], "fixture loads")
	var migration_state := var_to_bytes(GameSession.coach_market)
	var migration_rng := GameSession._rng.state
	check(GameSession.coach_market["free"].size()+GameSession.national_teams.size() >= 8, "old saves get a coach market")
	check(GameSession._rng.state == 42, "coach migration preserves match RNG")
	GameSession.apply_save_payload(fixture.duplicate(true))
	check(var_to_bytes(GameSession.coach_market) == migration_state and GameSession._rng.state == migration_rng, "migration is deterministic")
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	CoachMarket.prepare(GameSession, rng)
	check(GameSession.coach_market["expectations"][1]["rank"] == 1, "board expectations follow the squad")
	var poor := GameSession.get_club_coach(1)
	var successful := GameSession.get_club_coach(3)
	var retired := GameSession.get_club_coach(4)
	retired["age"] = 74
	retired["retirement_age"] = 75
	var old_budget := GameSession.get_club_budget(1)
	var salary := int(poor["wage"])
	CoachMarket.close_season(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] != poor["id"], "a sustained underperformer is replaced")
	check(int(poor["club_id"]) == 0 and poor["employment_status"] == "free", "dismissed coach is available on the market")
	check(GameSession.get_club_budget(1) == old_budget - salary * 2, "dismissal pays remaining two years")
	check(poor["career"][0]["season_to"] == 1 and poor["career"][0]["departure_reason"] == "dismissed", "departure closes the career stint")
	check(GameSession.coach_market["events"].any(func(event: Dictionary) -> bool: return event["club_id"] == 2 and event["reason"] == "not_renewed"), "poor results cause non-renewal when the contract expires")
	check(GameSession.get_club_coach(3)["id"] == successful["id"], "successful coach stays")
	check(int(successful["contract_years"]) >= 2, "expired successful contract is renewed")
	check(int(successful["age"]) == 46, "coach ages once per season")
	check(retired["employment_status"] == "retired" and GameSession.get_coach(retired["id"]) == retired, "retired profile remains accessible")
	check(GameSession.get_club_coach(4)["id"] != retired["id"], "retirement vacancy is filled")
	var before_repeat := var_to_bytes(GameSession.coach_market)
	CoachMarket.close_season(GameSession, rng)
	check(var_to_bytes(GameSession.coach_market) == before_repeat, "closing the same season twice does not tick contracts again")
	var ids := {}
	for coach in GameSession.coaches_by_club.values() + GameSession.coach_market["free"] + GameSession.coach_market["retired"]:
		check(not ids.has(coach["id"]), "coach has only one employment location")
		ids[coach["id"]] = true
	check(GameSession.coaches_by_club.size() == 6, "all clubs have a head coach")
	# A free coach can accept a different job while retaining his former stint.
	GameSession.coach_market["free"] = [poor]
	CoachMarket.depart(GameSession, 6, "contract_expired", 1, 20)
	GameSession.coach_market["free"] = [poor]
	var hired := CoachMarket.appoint_best(GameSession, 6, CoachMarket.clubs_of(GameSession)[6], rng)
	check(hired["id"] == poor["id"] and hired["career"].size() == 2, "another club hires the same coach with a second career stint")
	check(GameSession.get_coach(hired["id"])["club_id"] == 6, "profile resolves the new employer")
	SaveStore.database_path_override = "user://tests/coach_market/games.db"
	check(GameSession.save_game("coach_test")["success"], "market state saves")
	var saved_market := var_to_bytes(GameSession.coach_market)
	GameSession.clear()
	check(GameSession.load_game("coach_test")["success"], "market state loads")
	check(var_to_bytes(GameSession.coach_market) == saved_market, "free coaches, retirees, events and expectations survive load")
	check(GameSession.get_coach(retired["id"])["employment_status"] == "retired", "retired career survives save")
	GameSession.delete_save("coach_test")
	SaveStore.database_path_override = ""
	var view := View.new()
	add_child(view)
	view.refresh()
	check(view._rows.size() == GameSession.coach_market["free"].size(), "market lists unemployed coaches")
	view._filter.select(3)
	view.refresh()
	check(view._rows.size() == GameSession.coach_market["events"].size(), "journal lists appointments and renewals")
	view.free()
	check(not CoachMarket._stint_is_poor({"appointment_matches": 20, "appointment_points": 15, "appointment_reference_ppg": 2.0}, {"poor": true, "matches": 32, "points": 39}), "new coach is judged on his own improved results, not inherited losses")
	_test_midseason(fixture)
	_test_style_fit()
	_test_board_trust(fixture)
	_test_close_matches(fixture)
	_test_refused_contract(fixture)
	_test_malformed(fixture)
	GameSession.clear()
	print("COACH MARKET: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func _test_midseason(fixture: Dictionary) -> void:
	GameSession.apply_save_payload(fixture.duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	CoachMarket.prepare(GameSession, rng)
	var coach := GameSession.get_club_coach(1)
	GameSession.season_day = 15
	CoachMarket.review(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == coach["id"], "first bad review does not fire a coach")
	GameSession.season_day = 20
	CoachMarket.review(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == coach["id"], "two reviews still leave room to recover")
	GameSession.season_day = 25
	CoachMarket.review(GameSession, rng)
	var replacement := GameSession.get_club_coach(1)
	check(replacement["id"] != coach["id"], "three sustained bad reviews fire midseason")
	check(coach["career"][0]["day_to"] == 25, "midseason departure stores the day")
	GameSession.season_day = 30
	CoachMarket.review(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == replacement["id"], "new hire gets time before another dismissal")
	CoachMarket.close_season(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == replacement["id"], "late-season hire is protected at the season review too")

func _test_close_matches(fixture: Dictionary) -> void:
	GameSession.apply_save_payload(fixture.duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	CoachMarket.prepare(GameSession, rng)
	for row in GameSession.units[0]["standings"]:
		row["points"] = 30
	check(not CoachMarket.assessments(GameSession)[1]["poor"], "tied points do not imply a board crisis")

func _test_malformed(fixture: Dictionary) -> void:
	var broken := fixture.duplicate(true)
	broken["coach_market"] = {"free": "broken"}
	check(not GameSession.apply_save_payload(broken)["success"], "malformed coach pool is rejected")

func _fixture() -> Dictionary:
	var clubs := {}
	var squads := {}
	var coaches := {}
	var standings: Array = []
	var budgets := {}
	for cid in range(1, 7):
		clubs[cid] = {"id": cid, "name": "Club %d" % cid, "country_id": 1, "reputation": 900, "finance_level": 20}
		squads[cid] = [{"id": cid, "position": "GK", "current_ability": 100 - cid * 5}]
		coaches[cid] = {"id": cid, "club_id": cid, "name": "Coach %d" % cid, "age": 45, "retirement_age": 75,
			"current_ability": 70, "potential_ability": 80, "reputation": 600, "wage": 1000,
			"attributes": {"tactics": 14, "transfers": 14, "negotiations": 14, "development": 14},
			"primary_formation": "2-3-2", "primary_style": "control", "contract_years": 1 if cid in [2, 3] else 3,
			"career": [{"club_id": cid, "club_name": clubs[cid]["name"], "season_from": 1, "season_to": 0}]}
		budgets[cid] = 1000000
	var order := [6, 3, 4, 5, 2, 1]
	for i in order.size():
		standings.append({"club_id": order[i], "played": 20, "points": 40 - i * 5, "goal_diff": 0, "goals_for": 0, "division": 0})
	return {"version": 11, "season_number": 1, "season_day": 40, "selected_unit_id": 1, "rng_seed": 42, "rng_state": 42,
		"players_by_club": squads, "coaches_by_club": coaches, "club_budgets": budgets, "free_agents": [],
		"units": [{"id": 1, "name": "League", "rules": {}, "clubs_by_id": clubs, "standings": standings, "matches": [], "playoff": {"enabled": false}, "winners": []}]}

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)


func _test_refused_contract(fixture: Dictionary) -> void:
	var changed := fixture.duplicate(true)
	changed["units"][0]["clubs_by_id"][6]["reputation"] = 200
	changed["coaches_by_club"][6]["reputation"] = 1000
	changed["coaches_by_club"][6]["contract_years"] = 1
	GameSession.apply_save_payload(changed)
	var old_id := int(GameSession.get_club_coach(6)["id"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	CoachMarket.close_season(GameSession, rng)
	check(GameSession.get_club_coach(6)["id"] != old_id, "a coach can refuse an unsuitable club despite good results")
	check(GameSession.coach_market["events"].any(func(event: Dictionary) -> bool: return event["club_id"] == 6 and event["reason"] == "contract_expired"), "coach refusal is distinguished from dismissal")


func _test_board_trust(fixture: Dictionary) -> void:
	var legacy := fixture.duplicate(true)
	legacy["season_number"] = 3
	legacy["units"][0]["winners"] = [{"season": 1, "club_id": 1}, {"season": 2, "club_id": 1}]
	GameSession.apply_save_payload(legacy)
	check(GameSession.get_club_coach(1)["board_confidence"] == 2, "legacy saves recover trust from the current coach's recent titles")
	var newcomer := GameSession.get_club_coach(1).duplicate(true)
	newcomer["career"][0]["season_from"] = 3
	check(CoachMarket._past_confidence(GameSession, newcomer, 1) == 0, "new coach does not inherit a predecessor's success")
	GameSession.apply_save_payload(fixture.duplicate(true))
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	CoachMarket.prepare(GameSession, rng)
	var coach := GameSession.get_club_coach(1)
	coach["board_confidence"] = 2
	for day in [15, 20, 25, 30]:
		GameSession.season_day = day
		CoachMarket.review(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == coach["id"], "past success buys time during a crisis")
	GameSession.season_day = 35
	CoachMarket.review(GameSession, rng)
	var replacement := GameSession.get_club_coach(1)
	check(replacement["id"] != coach["id"], "trust cannot protect an endless sustained failure")
	for row in GameSession.units[0]["standings"]:
		row["played"] += 20
	for day in [40, 45, 50, 55]:
		GameSession.season_day = day
		CoachMarket.review(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == replacement["id"], "club cannot repeatedly fire successors within the same season")
	GameSession.apply_save_payload(fixture.duplicate(true))
	GameSession.units[0]["winners"] = [{"season": 1, "club_id": 1}]
	coach = GameSession.get_club_coach(1)
	CoachMarket.close_season(GameSession, rng)
	check(GameSession.get_club_coach(1)["id"] == coach["id"], "current title is credited despite a poor regular rank")


func _test_style_fit() -> void:
	var squad: Array = []
	for i in 7:
		var player := {"id": 1000 + i, "position": "CM", "current_ability": 70, "age": 24}
		player[MatchRatings.CACHE_KEY] = {"stamp": 70024, "create": 1.0, "poise": 1.0, "dribble": 1.0, "press": 0.1, "endurance": 0.1, "defend": 0.1}
		squad.append(player)
	var fits := CoachMarket._squad_style_fits(squad)
	check(fits["attacking"] > fits["defensive"], "passing squad fits a attacking character better than a defensive character")
	GameSession.clear()
	GameSession.players_by_club[1] = squad
	GameSession.club_budgets[1] = 1000000
	var base := {"id": 1, "age": 45, "retirement_age": 75, "reputation": 600, "current_ability": 70, "wage": 1000, "career": [], "primary_formation": "2-3-2", "attributes": {"tactics": 14, "development": 14}}
	var presser := base.duplicate(true)
	presser["style"] = "defensive"
	var controller := base.duplicate(true)
	controller["id"] = 2
	controller["style"] = "attacking"
	GameSession.coach_market = {"free": [presser, controller], "retired": [], "events": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	check(CoachMarket.appoint_best(GameSession, 1, {"id": 1, "reputation": 800, "finance_level": 20}, rng)["id"] == 2, "equal coaches are chosen by compatibility with existing players")
