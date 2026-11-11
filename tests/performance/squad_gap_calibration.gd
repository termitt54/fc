extends Node
## Paired seeds, controlled player profiles, two settings profiles and real fatigue.
const Config := preload("res://game/match_simulation_config.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")

func _ready() -> void:
	call_deferred("run")

func coach(level: int = 10) -> Dictionary:
	return {"primary_style": "control", "backup_style": "control", "primary_formation": "2-3-2", "backup_formation": "2-3-2", "attributes": {"tactics": level, "motivation": level, "professionalism": 20}, "national_selection": true}

func squad(id: int, ability: int, source: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 81041
	var players: Array = Fixtures.squad(id, ability, rng, 0) if source.is_empty() else source.duplicate(true)
	for i in players.size():
		var p: Dictionary = players[i]
		p.id = id * 1000 + i + 1
		p.club_id = id
		PlayerTypes.fit_attributes_to_target(p.attributes, p.position, ability)
		p.current_ability = PlayerTypes.calc_current_ability(p.attributes, p.position)
		p.potential_ability = maxi(int(p.current_ability), 95)
		p.condition = 100
		p.morale = 50
		p.injury_rounds = 0
		p.suspension_matches = 0
		MatchRatings.invalidate(p)
	return players

func recover(players: Array, report: Dictionary) -> void:
	var used := {}
	var index := {}
	for p in players:
		index[int(p.id)] = p
	for entry in report.players:
		if int(entry.minutes) <= 0:
			continue
		var p: Dictionary = index[int(entry.player_id)]
		var intensity := float(entry.get("intensity_minutes", entry.minutes)) / float(entry.minutes)
		PlayerCondition.apply_match_load(p, int(entry.minutes), intensity)
		used[int(p.id)] = true
	for p in players:
		PlayerCondition.advance_round(p, used.has(int(p.id)))

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() not in [2, 3]:
		get_tree().quit(1)
		return
	var user: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0])).knobs
	var output := {"rows": [], "groups": []}
	for settings in ["defaults", "user"]:
		Config.apply_values(Config.default_values() if settings == "defaults" else user, false)
		var no_injuries := Config.snapshot()
		no_injuries.injury_per_phase = 0.0
		Config.apply_values(no_injuries, false)
		for scenario in ["gap0", "gap3", "gap5", "gap8", "gap12", "gap18", "gap8_bad_coach", "gap8_tired", "gap8_weak_keeper", "gap8_series"]:
			var gap := int(scenario.trim_prefix("gap"))
			var samples := 800 if scenario in ["gap0", "gap3", "gap5", "gap8", "gap12", "gap18"] else 400
			var base_b := squad(2, 72)
			var base_a := squad(1, 72 + gap, base_b)
			if scenario == "gap8_tired":
				for p in base_a:
					p.condition = 75
			if scenario == "gap8_weak_keeper":
				for p in base_a:
					if p.position == "GK":
						PlayerTypes.fit_attributes_to_target(p.attributes, "GK", 50)
						p.current_ability = PlayerTypes.calc_current_ability(p.attributes, "GK")
						MatchRatings.invalidate(p)
			var row := {"settings": settings, "scenario": scenario, "matches": 0, "wins": 0, "draws": 0, "losses": 0, "goals": 0, "shots": 0, "margin6": 0, "eight_plus": 0, "starting_gap": 0.0}
			for i in samples:
				var a := base_a.duplicate(true) if scenario == "gap8_series" else base_a
				var b := base_b.duplicate(true) if scenario == "gap8_series" else base_b
				var spec_a := {"club_id": 1, "squad": a, "coach": coach(7 if scenario == "gap8_bad_coach" else 10)}
				var spec_b := {"club_id": 2, "squad": b, "coach": coach(15 if scenario == "gap8_bad_coach" else 10)}
				var rng := RandomNumberGenerator.new()
				rng.seed = 524001 + i * 17
				for leg in (3 if scenario == "gap8_series" else 1):
					var swap := (i + leg) % 2 == 1
					var result := MatchEngine.simulate({"home": spec_b if swap else spec_a, "away": spec_a if swap else spec_b, "neutral": true, "allow_draw": true, "discipline": DisciplineRules.from_rules({"discipline_enabled": false})}, rng)
					var winner := int(result.winner) * (-1 if swap else 1)
					row.matches += 1
					row.wins += int(winner > 0)
					row.draws += int(winner == 0)
					row.losses += int(winner < 0)
					row.goals += int(result.home_goals) + int(result.away_goals)
					row.margin6 += int(absi(int(result.home_goals) - int(result.away_goals)) >= 6)
					row.eight_plus += int(maxi(int(result.home_goals), int(result.away_goals)) >= 8)
					row.shots += int(result.home_team.shots) + int(result.away_team.shots)
					var ra: Dictionary = result.away_team if swap else result.home_team
					var rb: Dictionary = result.home_team if swap else result.away_team
					row.starting_gap += float(ra.starting_ability) - float(rb.starting_ability)
					if scenario == "gap8_series":
						recover(a, ra)
						recover(b, rb)
				if i % 100 == 0:
					await get_tree().process_frame
			output.rows.append(row)
			print("GAP CALIBRATION ", JSON.stringify(row))
		# Three-round four-team group, with genuine match load between rounds.
		var group := {"settings": settings, "groups": 300, "qualified": 0, "first": 0}
		var templates: Array = []
		for i in 4:
			templates.append(squad(i + 1, [80, 74, 72, 68][i]))
		for seed in 300:
			var teams := templates.duplicate(true)
			var points := [0, 0, 0, 0]
			var diffs := [0, 0, 0, 0]
			var gf := [0, 0, 0, 0]
			var rng := RandomNumberGenerator.new()
			rng.seed = 71402 + seed
			for day in [[[0, 1], [2, 3]], [[0, 2], [1, 3]], [[0, 3], [1, 2]]]:
				for pair in day:
					var a := int(pair[0])
					var b := int(pair[1])
					var result := MatchEngine.simulate({"home": {"club_id": a + 1, "squad": teams[a], "coach": coach()}, "away": {"club_id": b + 1, "squad": teams[b], "coach": coach()}, "neutral": true, "allow_draw": true, "discipline": DisciplineRules.from_rules({"discipline_enabled": false})}, rng)
					var margin := int(result.home_goals) - int(result.away_goals)
					points[a] += 3 if margin > 0 else 1 if margin == 0 else 0
					points[b] += 3 if margin < 0 else 1 if margin == 0 else 0
					diffs[a] += margin
					diffs[b] -= margin
					gf[a] += int(result.home_goals)
					gf[b] += int(result.away_goals)
					recover(teams[a], result.home_team)
					recover(teams[b], result.away_team)
			var order := [0, 1, 2, 3]
			order.sort_custom(func(a, b): return points[a] > points[b] if points[a] != points[b] else diffs[a] > diffs[b] if diffs[a] != diffs[b] else gf[a] > gf[b] if gf[a] != gf[b] else a < b)
			group.qualified += int(order.find(0) < 2)
			group.first += int(order[0] == 0)
			if seed % 30 == 0:
				await get_tree().process_frame
		output.groups.append(group)
		print("GAP GROUP ", JSON.stringify(group))
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	var failures := validate(output, JSON.parse_string(FileAccess.get_file_as_string(args[2]))) if args.size() == 3 else 0
	get_tree().quit(1 if failures else 0)

func validate(after: Dictionary, before: Dictionary) -> int:
	var failures := 0
	for settings in ["defaults", "user"]:
		var rows := {}
		var old := {}
		for row in after.rows:
			if row.settings == settings:
				rows[row.scenario] = row
		for row in before.rows:
			if row.settings == settings:
				old[row.scenario] = row
		var tests := {}
		var previous := 0.0
		for gap in [0, 3, 5, 8, 12, 18]:
			var row: Dictionary = rows["gap%d" % gap]
			var wins: float = float(row.wins) / float(row.matches)
			tests["win rate increases with gap %d" % gap] = wins >= previous
			previous = wins
		tests["five point advantage meaningful"] = rate(rows.gap5) >= 0.55
		tests["eight point advantage reliable"] = rate(rows.gap8) >= 0.65 and float(rows.gap8.losses) / rows.gap8.matches <= 0.15
		tests["twelve point advantage stronger"] = rate(rows.gap12) >= 0.75 and float(rows.gap12.losses) / rows.gap12.matches <= 0.10
		for handicap in ["gap8_bad_coach", "gap8_tired", "gap8_weak_keeper"]:
			tests[handicap + " still matters"] = rate(rows[handicap]) < rate(rows.gap8) - 0.05
		tests["advantage survives consecutive days"] = rate(rows.gap8_series) >= rate(rows.gap8) - 0.15
		tests["equal goals stay stable"] = absf(float(rows.gap0.goals) / rows.gap0.matches - float(old.gap0.goals) / old.gap0.matches) < 0.30
		tests["equal draw rate stays stable"] = absf(float(rows.gap0.draws) / rows.gap0.matches - float(old.gap0.draws) / old.gap0.matches) < 0.06
		tests["equal eight-goal blowouts stay rare"] = float(rows.gap0.eight_plus) / rows.gap0.matches < 0.01
		var group: Dictionary = after.groups.filter(func(r): return r.settings == settings)[0]
		var old_group: Dictionary = before.groups.filter(func(r): return r.settings == settings)[0]
		tests["group favourite qualifies more reliably"] = int(group.qualified) > int(old_group.qualified) and float(group.qualified) / group.groups >= 0.93
		for label in tests:
			if not tests[label]:
				failures += 1
				print("FAIL ", settings, ": ", label)
	print("CALIBRATION VALIDATION failures=", failures)
	return failures

func rate(row: Dictionary) -> float:
	return float(row.wins) / row.matches
