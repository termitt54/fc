extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Config := preload("res://game/match_simulation_config.gd")
var output := {}
func _ready() -> void: call_deferred("run")
func rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed=seed_value
	return r
func coach() -> Dictionary:
	var c := {"attributes":{"tactics":12,"motivation":10,"discipline":10},"primary_style":"control","backup_style":"control","primary_formation":"2-3-2","backup_formation":"2-3-2"}
	TacticTypes.ensure_coach_tactics(c)
	return c
func simulate(a: Array,b: Array,seed_value: int,controlled: bool = false) -> Dictionary:
	return MatchEngine.simulate({"home":{"club_id":1,"squad":a,"coach":coach()},"away":{"club_id":2,"squad":b,"coach":coach()},"neutral":true,"allow_draw":true,"discipline":{"enabled":not controlled}},rng(seed_value))
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.reset_to_defaults(false)
	output.backend=NativeSimulation.backend()
	output.scenarios=[]
	var started := Time.get_ticks_usec()
	for pair in [[65,65],[85,75],[85,50]]:
		var totals := {"ca_labels":pair,"matches":200,"wins":0,"draws":0,"goals":0,"shots":0,"subs":0,"passes":0,"completed_passes":0,"dribbles":0,"successful_dribbles":0,"maximum_team_goals":0}
		totals.positions={}
		totals.penalty_goals=0
		totals.assisted_goals=0
		totals.two_assist_goals=0
		for world in 5:
			var a := Fixtures.squad(1,pair[0],rng(94832+world),4)
			var b := Fixtures.squad(2,pair[1],rng(441+world),4)
			if pair[0]==pair[1]:
				b=a.duplicate(true)
				for p in b: p.id+=1000
			for j in 40:
				var reverse := j%2==1
				var result := simulate(b if reverse else a,a if reverse else b,980003+world*40+j)
				var goals_a: int=result.away_goals if reverse else result.home_goals
				var goals_b: int=result.home_goals if reverse else result.away_goals
				totals.wins+=int(goals_a>goals_b)
				totals.draws+=int(goals_a==goals_b)
				totals.goals+=goals_a+goals_b
				totals.maximum_team_goals=maxi(totals.maximum_team_goals,maxi(goals_a,goals_b))
				for key in ["home_team","away_team"]:
					totals.shots+=int(result[key].shots)
					for player in result[key].players:
						var slot: String=player.slot
						if not totals.positions.has(slot): totals.positions[slot]={"goals":0,"shots":0,"minutes":0}
						for stat in ["goals","shots","minutes"]: totals.positions[slot][stat]+=int(player.get(stat,0))
					for stat in ["passes","completed_passes","dribbles","successful_dribbles"]: totals[stat]+=int(result[key].actions[stat])
				for event in result.events:
					totals.subs+=int(event.type=="SUB")
					if event.type in ["GOAL","PENALTY_GOAL"]:
						totals.penalty_goals+=int(event.type=="PENALTY_GOAL")
						var count: int=event.get("assist_ids",[]).size()
						totals.assisted_goals+=int(count>0)
						totals.two_assist_goals+=int(count==2)
		totals.losses=200-totals.wins-totals.draws
		totals.goals_per_match=totals.goals/200.0
		totals.shots_per_match=totals.shots/200.0
		totals.subs_per_team=totals.subs/400.0
		output.scenarios.append(totals)
	output.balance_ms=(Time.get_ticks_usec()-started)/200.0
	var f := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	f.store_string(JSON.stringify(output,"\t"))
	print(JSON.stringify(output))
	get_tree().quit()
