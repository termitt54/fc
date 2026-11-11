extends "res://tests/performance/country_talent_match_audit.gd"

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	var worlds := int(args[1]) if args.size()>1 else 10
	var duels := int(args[2]) if args.size()>2 else 100
	Config.reset_birth_to_defaults(false)
	MatchConfig.apply_values(MatchConfig.default_values(),false)
	var checkpoints := {1:{},5:{},10:{},20:{},30:{}}
	var world_rates: Array = []
	for world in worlds:
		var world_wins := 0
		var world_matches := 0
		var pools: Array = []
		var generators: Array = []
		var clubs: Array = []
		for i in 4:
			clubs.append({"id":i+1,"country_id":1,"reputation":700,"youth_academy":10})
		for talent in [85,75]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 446600+world
			generators.append(rng)
			var initial := YouthIntake.generate_first_team_squads(clubs,{1:{"youth_talent":talent}},rng,{"next_id":1},{})
			var pool: Array = []
			for squad in initial.values():
				pool.append_array(squad)
			for player in pool:
				player.id=int(player.id)+pools.size()*1000000
			pools.append(pool)
		var next_ids := [{"next_id":101},{"next_id":1000101}]
		for year in range(1,31):
			if checkpoints.has(year):
				var row: Dictionary = checkpoints[year]
				if row.is_empty():
					row.merge({"wins":0,"draws":0,"losses":0,"gf":0,"ga":0,"gap":0.0,"matches":0,"mean_ca_85":0.0,"mean_ca_75":0.0,"prime_ca_85":0.0,"prime_ca_75":0.0})
				var teams: Array = []
				for side in 2:
					var total_ca := 0.0
					var prime_ca := 0.0
					var prime_count := 0
					for player in pools[side]:
						total_ca += int(player.current_ability)
						if player.age>=22 and player.age<=29:
							prime_ca += int(player.current_ability)
							prime_count += 1
						player.condition = 100
						player.morale = 50
					var suffix := "85" if side==0 else "75"
					row["mean_ca_"+suffix] += total_ca/pools[side].size()/float(worlds)
					row["prime_ca_"+suffix] += prime_ca/maxi(1,prime_count)/float(worlds)
					teams.append(callup(pools[side],coach(),670000+year+world))
					if world==0:
						var profiles: Array = []
						for player in teams[side]:
							profiles.append({"age":player.age,"ca":player.current_ability,"pa":player.potential_ability,"pos":player.position,"ratings":MatchRatings.of(player)})
						row["profiles_"+suffix] = profiles
				var outcome := duel(teams[0],teams[1],duels,880000+year*1000+world*duels,coach(),coach())
				world_wins+=int(outcome.wins)
				world_matches+=int(outcome.matches)
				for key in ["wins","draws","losses","gf","ga","gap","matches"]:
					row[key] += outcome[key]
				print("GENERATIONS world=",world," year=",year)
			for side in 2:
				var rng: RandomNumberGenerator = generators[side]
				var kept: Array = []
				for player in pools[side]:
					PlayerDevelopment.develop_player(player,PlayerDevelopment.training_setup(10,coach()),rng,0.6)
					player.age += 1
					if not PlayerDevelopment.should_retire(player,rng):
						kept.append(player)
				var intake := YouthIntake.generate_youth_intake(clubs,{1:{"youth_talent":85 if side==0 else 75}},rng,next_ids[side],{})
				for squad in intake.values():
					kept.append_array(squad)
				pools[side] = kept
		world_rates.append(float(world_wins)/maxi(1,world_matches))
	var file := FileAccess.open(args[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(checkpoints,"\t"))
	var failures: Array = []
	var total_wins := 0
	var total_matches := 0
	for year in checkpoints:
		var summary: Dictionary = checkpoints[year].duplicate()
		summary.erase("profiles_85")
		summary.erase("profiles_75")
		print("GENERATIONS RESULTS year=",year," ",JSON.stringify(summary))
		total_wins += int(summary.wins)
		total_matches += int(summary.matches)
		if float(summary.mean_ca_85)-float(summary.mean_ca_75)<7.0 or float(summary.prime_ca_85)-float(summary.prime_ca_75)<7.0:
			failures.append({"year":year,"reason":"country_pool_convergence"})
	# Repeated matches share a generated world: they are clustered samples, not
	# 5,000 independent player pools. Assess uncertainty across independent worlds.
	var rate := float(total_wins)/maxi(1,total_matches)
	var variance := 0.0
	for world_rate in world_rates: variance+=pow(float(world_rate)-rate,2)
	variance/=maxi(1,world_rates.size()-1)
	var t95 := 2.262157 if worlds<30 else 2.05
	var half_width := t95*sqrt(variance/maxi(1,worlds))
	var confidence := [maxf(0.0,rate-half_width),minf(1.0,rate+half_width)]
	var acceptance := {"unit":"independent_world","world_rates":world_rates,"win_rate":rate,"confidence_95":confidence,"target":[0.65,0.75]}
	FileAccess.open(args[0].get_basename()+"-acceptance.json",FileAccess.WRITE).store_string(JSON.stringify(acceptance,"\t"))
	print("GENERATIONS ESTIMATE ",JSON.stringify(acceptance))
	if worlds>=10 and duels>=100 and (float(confidence[1])<0.65 or float(confidence[0])>0.75):
		failures.append({"reason":"generation_match_balance","win_rate":rate,"confidence_95":confidence})
	print("GENERATIONS ACCEPTANCE failures=",failures)
	get_tree().quit(1 if not failures.is_empty() else 0)
