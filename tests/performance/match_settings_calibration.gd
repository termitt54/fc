extends Node
## Candidate settings on varied squads and copied national rosters; no live writes.
const Config := preload("res://game/match_simulation_config.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size() == 2)
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	var profiles: Dictionary = fixture["profiles"]
	var count := int(fixture.get("samples", 300))
	var output: Array = []
	for label in profiles:
		Config.apply_values(profiles[label], false)
		for pair in [[65,65], [80,80], [80,72], [80,62], [85,50]]:
			var a: Dictionary
			var b: Dictionary
			var row := _row(str(label), "%d:%d" % pair, count)
			for i in count:
				if i % 50 == 0:
					var rng := RandomNumberGenerator.new()
					rng.seed = 751000 + i
					var sa := Fixtures.squad(1, int(pair[0]), rng, 0)
					var sb := sa.duplicate(true) if pair[0] == pair[1] else Fixtures.squad(2, int(pair[1]), rng, 0)
					for squad in [sa,sb]:
						for player in squad:
							player.condition = 100
							player.morale = 50
					for n in sb.size():
						sb[n].id = 2000 + n
						sb[n].club_id = 2
					a = {"club_id":1, "squad":sa, "coach":_coach()}
					b = {"club_id":2, "squad":sb, "coach":_coach()}
				_sample(row, a, b, i)
			output.append(row)
			print("CALIBRATION ", JSON.stringify(row))
		for pair in fixture.get("pairs", []):
			var row := _row(str(label), "%s:%s" % pair, count)
			for i in count:
				_sample(row, fixture.teams[pair[0]], fixture.teams[pair[1]], i)
			output.append(row)
			print("CALIBRATION ", JSON.stringify(row))
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	get_tree().quit()

func _coach() -> Dictionary:
	return {"primary_style":"control", "backup_style":"control", "primary_formation":"2-3-2", "backup_formation":"2-3-2", "attributes":{"tactics":12,"motivation":12,"professionalism":20}}

func _row(label: String, pair: String, count: int) -> Dictionary:
	return {"profile":label,"pair":pair,"samples":count,"wins":0,"draws":0,"losses":0,"gf":0,"ga":0,"shots":0,"target":0,"margin4":0,"margin6":0,"eight_plus":0,"late_goals":0,"reds":0,"start_a":0.0,"start_b":0.0}

func _sample(row: Dictionary, a: Dictionary, b: Dictionary, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 921000 + i
	var swap := i % 2 == 1
	var result := MatchEngine.simulate({"home":b if swap else a,"away":a if swap else b,"neutral":true,"allow_draw":true,"discipline":{"enabled":false}}, rng)
	var gf := int(result.away_goals if swap else result.home_goals)
	var ga := int(result.home_goals if swap else result.away_goals)
	row["wins" if gf > ga else "losses" if gf < ga else "draws"] += 1
	row.gf += gf
	row.ga += ga
	row.shots += int(result.home_team.shots) + int(result.away_team.shots)
	row.target += int(result.home_team.on_target) + int(result.away_team.on_target)
	row.margin4 += int(absi(gf-ga) >= 4)
	row.margin6 += int(absi(gf-ga) >= 6)
	row.eight_plus += int(maxi(gf,ga) >= 8)
	row.reds += int(result.home_team.get("red",0)) + int(result.away_team.get("red",0))
	row.start_a += float(result.away_team.starting_ability if swap else result.home_team.starting_ability) / row.samples
	row.start_b += float(result.home_team.starting_ability if swap else result.away_team.starting_ability) / row.samples
	for event in result.get("events", []):
		if int(event.get("minute",0)) >= 40 and str(event.get("type","")) in ["GOAL","PENALTY_GOAL"]:
			row.late_goals += 1
