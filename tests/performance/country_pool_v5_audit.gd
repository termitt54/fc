extends "res://tests/performance/country_talent_match_audit.gd"

var scenarios := [[98,71,4,4], [98,71,7,3], [85,74,4,4], [85,50,4,1], [85,50,4,4]]

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	Config.birth_config_path = "user://tests/v5_country_defaults.json"
	Config.reset_birth_to_defaults(false)
	var knobs := MatchConfig.default_values()
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("An absolute report path is required")
		get_tree().quit(1)
		return
	var acceptance := args.has("acceptance")
	if args.size() > 2:
		audit_engine = load(args[2])
	if acceptance:
		scenarios = [[85,75,4,4], [85,75,10,10], [85,50,4,4], [98,71,4,4]]
	if args.size() > 1:
		var settings: Variant = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
		if not settings is Dictionary or not settings.has("values"):
			push_error("A valid match settings JSON is required")
			get_tree().quit(1)
			return
		knobs = settings.values
	knobs.injury_per_phase = 0.0
	MatchConfig.apply_values(knobs, false)
	var rows: Array = []
	for spec in scenarios:
		var result := {"talents":[spec[0],spec[1]], "clubs":[spec[2],spec[3]], "worlds":50, "wins":0,"draws":0,"losses":0,"gap":0.0,"gf":0,"ga":0,"matches":0,"keeper_gap":0.0,"pa_gap":0.0,"losses_by_4":0,"losses_by_6":0,"max_loss_margin":0}
		for world in 50:
			var teams: Array = []
			var keepers: Array = []
			var means: Array = []
			for side in 2:
				var rng := RandomNumberGenerator.new()
				rng.seed = 556000 + world
				var clubs: Array = []
				for i in int(spec[side+2]):
					clubs.append({"id":i+1,"country_id":1,"reputation":500,"youth_academy":10})
				var by_club := YouthIntake.generate_first_team_squads(clubs,{1:{"youth_talent":int(spec[side])}},rng,{"next_id":1},{})
				var pool: Array = []
				for squad in by_club.values():
					pool.append_array(squad)
				var best_keeper := 0
				var total_pa := 0
				for player in pool:
					player.condition = 100
					player.morale = 50
					total_pa += int(player.potential_ability)
					if player.position == "GK":
						best_keeper = maxi(best_keeper,int(player.current_ability))
				keepers.append(best_keeper)
				means.append(float(total_pa)/pool.size())
				teams.append(callup(pool,coach(),667000+world))
			var match_result := duel(teams[0],teams[1],20,778000+world*20,coach(),coach())
			for key in ["wins","draws","losses","gf","ga","gap","matches","losses_by_4","losses_by_6"]:
				result[key] += match_result[key]
			result.max_loss_margin = maxi(int(result.max_loss_margin), int(match_result.max_loss_margin))
			result.keeper_gap += float(keepers[0]-keepers[1])/50.0
			result.pa_gap += float(means[0]-means[1])/50.0
		rows.append(result)
		print("COUNTRY V5 ",JSON.stringify(result))
	var file := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"\t"))
	var failures: Array = []
	if acceptance:
		for row in rows:
			var win_rate := float(row.wins)/float(row.matches)
			if row.talents==[85,75] and (win_rate<0.65 or win_rate>0.75):
				failures.append({"scenario":row.talents,"clubs":row.clubs,"win_rate":win_rate})
			if row.talents==[85,50] and win_rate<0.98:
				failures.append({"scenario":row.talents,"win_rate":win_rate})
			if row.talents==[98,71] and win_rate<0.85:
				failures.append({"scenario":row.talents,"win_rate":win_rate})
	print("COUNTRY ACCEPTANCE failures=",failures)
	get_tree().quit(1 if not failures.is_empty() else 0)
