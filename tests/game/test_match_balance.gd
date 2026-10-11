extends Node
## Controlled neutral-ground series, independent matches rather than a season.
## Optional user argument: --balance-report=<absolute JSON path>.

const MatchEngineScript := preload("res://game/match_engine.gd")
const Config := preload("res://game/match_simulation_config.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Tactics := preload("res://game/tactic_types.gd")
const RoleFixtures := preload("res://tests/game/role_squad_fixtures.gd")
const SAMPLES := 400
const SEED := 87021

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Config.config_path = "user://config/match_balance_test.json"
	Config.reset_to_defaults(false)
	var rows: Array = []
	if not "--balance-focus=midfield" in OS.get_cmdline_user_args():
		rows.append(_series("equal_control", 65, 65, "control", "control"))
		rows.append(_series("strong_vs_weak", 80, 50, "control", "control"))
		rows.append(_series("tired_vs_fresh", 65, 65, "control", "control", 55))
		rows.append(_series("coach_18_vs_4", 65, 65, "control", "control", 100, 18, 4))
		for style in ["tiki_taka", "vertical", "kick_rush", "pressing", "park_bus", "counter"]:
			rows.append(_series("%s_vs_control" % style, 65, 65, style, "control"))
		rows.append(_series("specialists_control_equal", 65, 65, "control", "control", 100, 10, 10, true))
		rows.append(_series("specialists_pressing_vs_control", 65, 65, "pressing", "control", 100, 10, 10, true))
	rows.append(_series("midfield_backup_plan", 65, 65, "control", "control", 100, 20, 20, false, true))
	rows.append(_series("midfield_pressure_opponent", 65, 65, "control", "pressing", 100, 20, 20, false, true))
	var report := {"seed": SEED, "samples_per_scenario": SAMPLES,
		"neutral": true, "default_knobs": Config.snapshot(), "scenarios": rows}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--balance-report="):
			var file := FileAccess.open(arg.trim_prefix("--balance-report="), FileAccess.WRITE)
			if file == null:
				push_error("Cannot write balance report")
				get_tree().quit(1)
				return
			file.store_string(JSON.stringify(report, "\t"))
			file.close()
	Config.config_path = Config.DEFAULT_CONFIG_PATH
	Config.reset_to_defaults(false)
	print("BALANCE_JSON: ", JSON.stringify(report))
	get_tree().quit(0)

func _series(label: String, ca_a: int, ca_b: int, style_a: String, style_b: String,
	condition_a: int = 100, coach_a: int = 10, coach_b: int = 10, specialised: bool = false, midfield: bool = false) -> Dictionary:
	# Same generation seed gives matching attribute patterns, ages and personalities.
	var a := _squad(1, ca_a, condition_a)
	var b := _squad(2, ca_b, 100)
	if specialised or midfield:
		a = RoleFixtures.preparation_squad() if midfield else RoleFixtures.specialised_squad()
		b = a.duplicate(true)
		for player in b:
			player["id"] = int(player["id"]) + 10000
			player["club_id"] = 2
	var sa := {"club_id": 1, "reputation": 500, "squad": a, "coach": _coach(style_a, coach_a)}
	var sb := {"club_id": 2, "reputation": 500, "squad": b, "coach": _coach(style_b, coach_b)}
	if midfield and style_b == "control":
		# Keep A fixed; this opponent has weaker pressure than the second scenario.
		for player in b:
			player["attributes"]["mental"]["work_rate"] = 8
			player["attributes"]["physical"]["stamina"] = 8
			player["attributes"]["physical"]["pace"] = 8
			player.erase("_match_ratings")
	if specialised:
		for spec in [sa, sb]:
			spec["coach"]["primary_formation"] = "2-4-1"
			spec["coach"]["backup_formation"] = "2-3-2" if spec["coach"]["backup_style"] == "tiki_taka" else "3-1-3"
	var wins := 0
	var draws := 0
	var losses := 0
	var goals_a := 0
	var goals_b := 0
	var shots := 0
	var yellow := 0
	var red := 0
	var injuries := 0
	var backup_plans := 0
	var backup_plans_a := 0
	var coaching_decisions := 0
	var blowouts := 0
	var possession_a := 0.0
	var scores: Dictionary = {}
	var begin := Time.get_ticks_usec()
	for i in SAMPLES:
		var rng := RandomNumberGenerator.new()
		rng.seed = SEED + i
		var swap := i % 2 == 1
		var result := MatchEngineScript.simulate({"home": sb if swap else sa, "away": sa if swap else sb,
			"neutral": true, "allow_draw": true}, rng)
		var ra: Dictionary = result["away_team" if swap else "home_team"]
		var rb: Dictionary = result["home_team" if swap else "away_team"]
		var ga := int(ra["goals"])
		var gb := int(rb["goals"])
		backup_plans_a += int(str(ra.get("plan_source", "primary")) == "backup")
		wins += int(ga > gb)
		draws += int(ga == gb)
		losses += int(ga < gb)
		goals_a += ga
		goals_b += gb
		blowouts += int(absi(ga - gb) >= 4)
		possession_a += float(ra["possession"])
		var score := "%d:%d" % [ga, gb]
		scores[score] = int(scores.get(score, 0)) + 1
		for team in [ra, rb]:
			backup_plans += int(str(team.get("plan_source", "primary")) == "backup")
			coaching_decisions += (team.get("decisions", []) as Array).size()
			shots += int(team["shots"])
			yellow += int(team["yellow"])
			red += int(team["red"])
			for player in team["players"]:
				injuries += int(int(player["injury_rounds"]) > 0)
	var row := {"scenario": label, "matches": SAMPLES, "wins_a": wins, "draws": draws,
		"losses_a": losses, "goals_a": goals_a, "goals_b": goals_b,
		"goals_per_match": float(goals_a + goals_b) / SAMPLES,
		"shots_per_match": float(shots) / SAMPLES, "yellow_per_match": float(yellow) / SAMPLES,
		"red_per_match": float(red) / SAMPLES, "injuries_per_match": float(injuries) / SAMPLES,
		"blowouts_4plus": blowouts, "possession_a": possession_a / SAMPLES,
		"scores": scores, "elapsed_ms": (Time.get_ticks_usec() - begin) / 1000.0}
	row["backup_plans"] = backup_plans
	row["backup_plans_a"] = backup_plans_a
	row["coaching_decisions"] = coaching_decisions
	print("BALANCE: %s W/D/L %d/%d/%d goals %.3f shots %.3f" %
		[label, wins, draws, losses, row["goals_per_match"], row["shots_per_match"]])
	return row

func _squad(club_id: int, ca: int, condition: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	# Generate in the same country too: name generation must not shift the RNG.
	var squad := Fixtures.squad(1, ca, rng, 0)
	for player in squad:
		player["id"] = int(player["id"]) + (club_id - 1) * 1000
		player["club_id"] = club_id
		player["condition"] = condition
		player["morale"] = 50
	return squad

func _coach(style: String, level: int) -> Dictionary:
	var backup := str(Tactics.relatives_for_style(style)[0])
	var formation := str(Tactics.formations_for_style(style)[0])
	var alternative := str(Tactics.formations_for_style(backup)[0])
	for candidate in Tactics.formations_for_style(backup):
		if candidate != formation:
			alternative = str(candidate)
	return {"id": 1, "primary_style": style, "backup_style": backup,
		"primary_formation": formation, "backup_formation": alternative,
		"style": Tactics.mentality_of_style(style),
		"attributes": {"tactics": level, "motivation": level, "discipline": level}}

