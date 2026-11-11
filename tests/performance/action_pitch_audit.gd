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
		var totals := {"ca_labels":pair,"matches":1000,"wins":0,"draws":0,"goals":0,"shots":0,"subs":0,"passes":0,"completed_passes":0,"dribbles":0,"successful_dribbles":0,"maximum_team_goals":0}
		totals.positions={}
		totals.primary_positions={}
		totals.penalty_goals=0
		totals.assisted_goals=0
		totals.two_assist_goals=0
		for world in 20:
			var a := Fixtures.squad(1,pair[0],rng(94832+world),4)
			var b := Fixtures.squad(2,pair[1],rng(441+world),4)
			if pair[0]==pair[1]:
				b=a.duplicate(true)
				for p in b: p.id+=1000
			for j in 50:
				var reverse := j%2==1
				var result := simulate(b if reverse else a,a if reverse else b,980003+world*50+j)
				var goals_a: int=result.away_goals if reverse else result.home_goals
				var goals_b: int=result.home_goals if reverse else result.away_goals
				totals.wins+=int(goals_a>goals_b)
				totals.draws+=int(goals_a==goals_b)
				totals.goals+=goals_a+goals_b
				totals.maximum_team_goals=maxi(totals.maximum_team_goals,maxi(goals_a,goals_b))
				for key in ["home_team","away_team"]:
					totals.shots+=int(result[key].shots)
					for player in result[key].players:
						var primary: String=player.position
						totals.primary_positions[primary]=int(totals.primary_positions.get(primary,0))+int(player.goals)
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
		totals.losses=1000-totals.wins-totals.draws
		totals.goals_per_match=totals.goals/1000.0
		totals.shots_per_match=totals.shots/1000.0
		totals.subs_per_team=totals.subs/2000.0
		output.scenarios.append(totals)
	output.balance_ms=(Time.get_ticks_usec()-started)/1000.0
	output.interventions=[]
	Config.apply_values({"injury_per_phase":0.0},false)
	var all_players := Fixtures.squad(1,60,rng(4317),0)
	var a: Array = []
	for index in [0,2,3,4,9,10,15,16]: a.append(all_players[index])
	var b: Array=a.duplicate(true)
	for p in a+b:
		p.characters=["BALANCED"]
		p.condition=100
		p.morale=60
		for group in p.attributes.values():
			for key in group: group[key]=10
		MatchRatings.invalidate(p)
	for p in b: p.id+=1000
	var cases := [["technical","finishing",7],["technical","passing",4],["technical","technique",4],["technical","dribbling",7],["technical","defending",1],["physical","pace",7],["physical","stamina",4],["physical","strength",1],["set_pieces","delivery",4],["set_pieces","penalties",7],["goalkeeping","reflexes",0],["goalkeeping","handling",0],["goalkeeping","positioning",0],["goalkeeping","exits",0],["goalkeeping","aerial_reach",0]]
	for test_case in cases:
		var comparison := {"skill":test_case[1],"player_id":a[test_case[2]].id,"samples_per_value":120,"values":[]}
		for value in [5,20]:
			var modified: Array=a.duplicate(true)
			modified[test_case[2]].attributes[test_case[0]][test_case[1]]=value
			MatchRatings.invalidate(modified[test_case[2]])
			var totals := {"value":value,"goals":0,"conceded":0,"player_goals":0,"player_minutes":0,"shots":0,"on_target":0,"passes":0,"completed_passes":0,"dribbles":0,"successful_dribbles":0,"tackles":0,"interceptions":0,"blocks":0,"crosses":0,"completed_crosses":0,"saves":0,"distance_metres":0,"catches":0,"parries":0,"aerial_wins":0,"receipts":0,"miscontrols":0,"final_freshness":0}
			for j in 120:
				var r := simulate(modified,b,17000+j,true)
				totals.goals+=r.home_goals
				totals.conceded+=r.away_goals
				for entry in r.home_team.players:
					if int(entry.player_id)!=int(comparison.player_id): continue
					totals.player_goals+=entry.goals
					totals.player_minutes+=entry.minutes
					for stat in ["shots","on_target","passes","completed_passes","dribbles","successful_dribbles","tackles","interceptions","blocks","crosses","completed_crosses","saves","distance_metres","catches","parries","aerial_wins","receipts","miscontrols","final_freshness"]: totals[stat]+=int(entry.get(stat,0))
			comparison.values.append(totals)
		output.interventions.append(comparison)
	output.recovery=[]
	for value in [5,10,15,20]:
		var player: Dictionary=a[3].duplicate(true)
		player.age=25
		player.condition=40
		player.attributes.physical.recovery=value
		PlayerCondition.advance_round(player,true)
		output.recovery.append({"recovery":value,"condition_before":40,"condition_after":player.condition})
	output.total_ms=(Time.get_ticks_usec()-started)/1000.0
	var f := FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	f.store_string(JSON.stringify(output,"\t"))
	print(JSON.stringify(output))
	get_tree().quit()
