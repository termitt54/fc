extends Node
## Reproducible two-game samples. Never opens a user's save or writes settings.
const Config := preload("res://game/match_simulation_config.gd")
const MatchEngineScript := preload("res://game/match_engine.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var results: Array = []

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var label := "before"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--label="):
			label = arg.trim_prefix("--label=")
	if label not in ["before", "after"]:
		get_tree().quit(2)
		return
	Config.config_path = "user://tests/match_stability_settings.json"
	var custom: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/performance/user_match_settings.json")).get("values", {})
	for settings_name in ["defaults", "user"]:
		for scenario in ["equal_fresh", "equal_no_fatigue", "equal_series", "low_stamina_keepers", "pressing_series", "coach_gap", "ability_gap", "discipline_series"]:
			var values: Dictionary = Config.default_values() if settings_name == "defaults" else custom.duplicate()
			values["injury_per_phase"] = 0.0
			if scenario == "equal_no_fatigue":
				for stamina in [1,10,20]:
					values["fresh_after_stamina_%d" % stamina] = 1.0
			Config.apply_values(values, false)
			var samples := 2000 if scenario == "equal_fresh" else 700
			var row := _scenario(settings_name, scenario, samples)
			results.append(row)
			print("STABILITY ", JSON.stringify(row))
	var file := FileAccess.open("res://tests/performance/results/match-stability-%s.json" % label, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify({"seed_base": 772001, "results":results}, "  "))
	file.close()
	get_tree().quit()

func _coach(level: int, style: String = "control") -> Dictionary:
	var attrs := {}
	for key in CoachTypes.ATTR_KEYS:
		attrs[key] = level
	return {"id":1,"attributes":attrs,"primary_style":style,"backup_style":style,
		"primary_formation":"2-3-2","backup_formation":"2-3-2"}

func _scenario(settings: String, scenario: String, samples: int) -> Dictionary:
	var summary := {"settings":settings,"scenario":scenario,"pairs":samples,"goals":0,"shots":0,"draws":0,"a_wins":0,"b_wins":0,
		"margin4":0,"margin6":0,"eight_plus":0,"reverse3":0,"reverse4":0,"reverse6":0,"reverse8_nil":0,"late_goals":0,"early_goals":0,"reds":0,
		"scores":{},"second_a_margin":0,"first_a_margin":0}
	var base_a: Array = []
	var base_b: Array = []
	var started := Time.get_ticks_msec()
	for i in samples:
		if i % 100 == 0:
			var fixture_rng := RandomNumberGenerator.new()
			fixture_rng.seed = 88201 + i / 100
			base_a = Fixtures.squad(1, 80, fixture_rng, 0)
			base_b = Fixtures.squad(2, 60, fixture_rng, 0) if scenario == "ability_gap" else base_a.duplicate(true)
			for n in base_b.size():
				base_b[n]["id"] = 2001+n
				base_b[n]["club_id"] = 2
			if scenario == "low_stamina_keepers":
				for squad in [base_a,base_b]:
					for player in squad:
						if player["position"] == "GK":
							player["attributes"]["physical"]["stamina"] = 1
							MatchRatings.invalidate(player)
		var linked := scenario.ends_with("series")
		var squad_a: Array = base_a.duplicate(true) if linked else base_a
		var squad_b: Array = base_b.duplicate(true) if linked else base_b
		var coach_a := _coach(18 if scenario == "coach_gap" else 10, "pressing" if scenario == "pressing_series" else "control")
		var coach_b := _coach(4 if scenario == "coach_gap" else 10)
		var spec_a := {"club_id":1,"squad":squad_a,"coach":coach_a,"reputation":800}
		var spec_b := {"club_id":2,"squad":squad_b,"coach":coach_b,"reputation":800}
		var rng := RandomNumberGenerator.new()
		rng.seed = 772001 + i * 97
		var margins: Array = []
		var scores: Array = []
		for leg in 2:
			var discipline := DisciplineRules.from_rules({"discipline_enabled":scenario == "discipline_series"})
			var config := {"home":spec_a if leg == 0 else spec_b,"away":spec_b if leg == 0 else spec_a,
				"neutral":true,"allow_draw":true,"discipline":discipline}
			var report := MatchEngineScript.simulate(config, rng)
			var hg := int(report["home_goals"])
			var ag := int(report["away_goals"])
			var margin := (hg-ag) * (1 if leg == 0 else -1)
			margins.append(margin)
			scores.append([hg,ag])
			summary["goals"] += hg+ag
			summary["shots"] += int(report["home_team"]["shots"])+int(report["away_team"]["shots"])
			summary["reds"] += int(report["home_team"]["red"])+int(report["away_team"]["red"])
			summary["draws"] += int(margin == 0)
			summary["a_wins"] += int(margin > 0)
			summary["b_wins"] += int(margin < 0)
			summary["margin4"] += int(absi(margin)>=4)
			summary["margin6"] += int(absi(margin)>=6)
			summary["eight_plus"] += int(maxi(hg,ag)>=8)
			var key := "%d:%d" % [hg,ag]
			summary["scores"][key] = int(summary["scores"].get(key,0))+1
			for event in report["events"]:
				if event["type"] in [MatchTypes.EVENT_GOAL,MatchTypes.EVENT_PENALTY_GOAL]:
					summary["late_goals" if int(event["minute"])>=25 else "early_goals"] += 1
			if linked and leg == 0:
				GameSession.players_by_club = {1:squad_a,2:squad_b}
				var tick := {"players":{}}
				MatchDay._apply_side(GameSession,1,report["home_team"],report,signi(margin),discipline)
				MatchDay._apply_side(GameSession,2,report["away_team"],report,-signi(margin),discipline)
				MatchDay._collect_tick(tick,1,report["home_team"])
				MatchDay._collect_tick(tick,2,report["away_team"])
				MatchDay.advance_rounds(GameSession,tick)
		for threshold in [3,4,6]:
			summary["reverse%d" % threshold] += int(margins[0]*margins[1]<0 and absi(margins[0])>=threshold and absi(margins[1])>=threshold)
		summary["reverse8_nil"] += int(margins[0]*margins[1]<0 and mini(scores[0][0],scores[0][1])==0 and mini(scores[1][0],scores[1][1])==0 and absi(margins[0])>=8 and absi(margins[1])>=8)
		summary["first_a_margin"] += margins[0]
		summary["second_a_margin"] += margins[1]
	summary["elapsed_ms"] = Time.get_ticks_msec()-started
	return summary
