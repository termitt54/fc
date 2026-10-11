extends Node
const Coaching := preload("res://game/match_coaching.gd")
const MatchEngineScript := preload("res://game/match_engine.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Config := preload("res://game/match_simulation_config.gd")
const Tactics := preload("res://game/tactic_types.gd")
const MatchDayScript := preload("res://game/match_day.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Config.config_path = "user://config/match_coaching_test.json"
	Config.reset_to_defaults(false)
	_test_preparation()
	_test_reviews()
	_test_tactical_substitution()
	_test_integration()
	Config.config_path = Config.DEFAULT_CONFIG_PATH
	Config.reset_to_defaults(false)
	print("=== Result: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _test_preparation() -> void:
	var rng := _rng()
	var squad := Fixtures.squad(1, 65, rng, 0)
	var coach := _coach(20)
	var spec := {"squad": squad, "coach": coach}
	var lineup := Coaching.select_lineup(spec, {}, rng)
	_check(Tactics.is_compatible(lineup["style"], lineup["formation"]), "chosen plan is compatible")
	_check(lineup["plan_source"] == "primary", "familiar plan stays when backup gain is small")
	# An available passing midfield, with no native striker or winger.
	var midfield: Array = []
	for i in 12:
		var player: Dictionary = squad[7].duplicate(true)
		player["id"] = 3000 + i
		player["position"] = "GK" if i < 2 else ("CB" if i < 4 else ("WM" if i < 8 else "CM"))
		for group in player["attributes"]:
			for key in player["attributes"][group]:
				player["attributes"][group][key] = 15
		player["attributes"]["technical"]["finishing"] = 1
		player["attributes"]["technical"]["dribbling"] = 1
		player["attributes"]["mental"]["off_the_ball"] = 1
		player.erase("_match_ratings")
		midfield.append(player)
	lineup = Coaching.select_lineup({"squad": midfield, "coach": coach}, {}, rng)
	print("PREPARATION: ", lineup["plan_source"], " ", lineup["plan_scores"])
	_check(lineup["plan_source"] == "backup", "midfield-heavy squad uses the backup 2-4-1")
	_check(lineup["formation"] == "2-4-1", "backup formation is really used for selection")
	_check((lineup["starters"] as Array).size() == 8, "backup still selects a full team")
	var pressure_opponent := {"squad": midfield, "coach": {"primary_style": "pressing"}}
	var prepared := Coaching.select_lineup({"squad": midfield, "coach": coach}, pressure_opponent, rng)
	_check(prepared["plan_source"] == "primary", "same squad avoids marginal tiki-taka plan against strong pressure")
	var cautious := Coaching.select_lineup({"squad": midfield, "coach": _coach(4)}, {}, rng)
	_check(cautious["plan_source"] == "primary", "weaker coach misses a small backup-plan advantage")
	var opposing := {"squad": squad, "coach": {"primary_style": "pressing"}}
	_check(Coaching._opponent_adjustment("counter", opposing) > Coaching._opponent_adjustment("counter", {}),
		"opponent style affects preparation score")
	var no_coach := Coaching.select_lineup({"squad": squad}, {}, rng)
	_check(no_coach["style"] == "control" and no_coach["formation"] == "2-3-2", "missing coach has safe defaults")

func _test_reviews() -> void:
	var opponent := _team(10)
	var strong := _team(18)
	strong["goals"] = 0
	opponent["goals"] = 1
	var decision := Coaching.review(strong, opponent, 25)
	_check(decision.get("approach", "") == "chase", "good coach reacts to falling behind at minute 25")
	var weak := _team(4)
	_check(Coaching.review(weak, opponent, 25).is_empty(), "weak coach has not reacted at minute 25")
	_check(Coaching.review(weak, opponent, 40).get("approach", "") == "chase", "weak coach reacts later")
	strong = _team(18)
	strong["goals"] = 2
	_check(Coaching.review(strong, opponent, 35).get("approach", "") == "protect", "late lead triggers protection")
	strong = _team(18)
	strong["men_down"] = 1
	opponent["goals"] = 0
	_check(Coaching.review(strong, opponent, 15).get("approach", "") == "compact", "dismissal triggers compact approach")
	strong = _team(18)
	for unit in strong["on_field"]:
		unit["fresh"] = 0.75
	decision = Coaching.review(strong, opponent, 25)
	_check(bool(decision.get("conserve", false)), "coach manages a tired team's intensity")
	_check(Coaching.review(strong, opponent, 26).is_empty(), "reviews have a cooldown")
	var normal := Coaching.profile("control", "normal", false)
	var chase := Coaching.profile("control", "chase", false)
	_check(chase["tempo"] > normal["tempo"] and chase["concede"] > normal["concede"], "chasing increases attacks and exposure")
	var protect := Coaching.profile("control", "protect", false)
	_check(protect["tempo"] < normal["tempo"] and protect["concede"] < normal["concede"], "protection trades attacks for safety")
	_check(Coaching.profile("control", "protect", false) == protect, "profile modifiers do not accumulate")
	strong = _team(18)
	strong["backup_style"] = "park_bus"
	_check(Coaching.review(strong, opponent, 25).is_empty(), "incompatible backup style cannot be applied during play")
	strong = _team(18)
	strong["style"] = "vertical"
	strong["primary_style"] = "vertical"
	strong["backup_style"] = "pressing"
	strong["formation"] = "3-1-3"
	strong["on_field"][0]["ratings"] = {"ability": 0.6, "create": 0.1, "poise": 0.1,
		"dribble": 0.1, "pace": 0.1, "off_ball": 0.1, "press": 1.0, "endurance": 1.0, "defend": 1.0}
	decision = Coaching.review(strong, opponent, 15)
	_check(decision.get("style", "") == "pressing", "compatible backup style is used when it suits players")
	_check(int(strong["last_style_change"]) == 15, "style switch records its cooldown")

func _test_tactical_substitution() -> void:
	var rng := _rng()
	var spec := {"club_id": 1, "squad": Fixtures.squad(1, 65, rng), "coach": _coach(18)}
	var lineup := MatchEngineScript._select_lineup(spec, rng)
	var ability := MatchEngineScript._lineup_ability(lineup)
	var team := MatchEngineScript._build_team("home", spec, lineup, ability, ability, rng, Config.snapshot())
	for unit in team["on_field"]:
		if float(unit["role_att"]) >= 0.5:
			unit["fresh"] = 0.5
	var ctx := {"rng": rng, "events": []}
	var before := int(team["subs_left"])
	MatchEngineScript._consider_tactical_sub(team, ctx, 25)
	_check(int(team["subs_left"]) == before - 1, "chasing makes one useful attacking substitution")
	_check(ctx["events"][0].get("reason", "") == "chasing_score", "substitution reason is recorded")
	team["subs_left"] = 1
	MatchEngineScript._consider_tactical_sub(team, ctx, 35)
	_check(int(team["subs_left"]) == 1, "tactical substitution reserves emergency cover")

func _test_integration() -> void:
	var rng := _rng()
	var a := {"club_id": 1, "squad": Fixtures.squad(1, 75, rng), "coach": _coach(18)}
	var b := {"club_id": 2, "squad": Fixtures.squad(2, 50, rng), "coach": _coach(4)}
	var changes := 0
	for i in 30:
		rng.seed = 91000 + i
		var result := MatchEngineScript.simulate({"home": a, "away": b, "neutral": true}, rng)
		var compact := MatchDayScript._compact_report(result)
		_check(compact["home"]["decisions"] == result["home_team"]["decisions"], "saved compact report retains coaching decisions")
		for report in [result["home_team"], result["away_team"]]:
			changes += (report["decisions"] as Array).size()
			_check(report.has("initial_style") and report.has("plan_reason"), "report preserves preparation and initial style")
			for entry in report["players"]:
				if int(entry["minutes"]) > 0:
					_check(float(entry["intensity_minutes"]) > 0.0, "played minutes have actual intensity load")
	_check(changes > 0, "coaching decisions occur in real simulated matches")
	rng.seed = 99
	var first := MatchEngineScript.simulate({"home": a, "away": b}, rng)
	rng.seed = 99
	_check(first == MatchEngineScript.simulate({"home": a, "away": b}, rng), "same seed reproduces decisions and results")
	print("COACHING: decisions in 30 games: ", changes)

func _team(skill: int) -> Dictionary:
	return {"tactics": skill, "goals": 0, "men_down": 0, "style": "control", "formation": "2-3-2",
		"primary_style": "control", "backup_style": "tiki_taka", "on_field": [{"ratings": {"ability": 0.6}, "slot": "CM", "fit": 1.0, "fresh": 1.0}]}

func _coach(skill: int) -> Dictionary:
	return {"primary_style": "control", "backup_style": "tiki_taka", "primary_formation": "2-3-2",
		"backup_formation": "2-4-1", "style": "balanced", "attributes": {"tactics": skill, "motivation": 10, "discipline": 10}}

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 58001
	return rng

func _check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)
