extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Config := preload("res://game/match_simulation_config.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	Config.reset_to_defaults(false)
	var rng := RandomNumberGenerator.new()
	rng.seed=406
	var a := Fixtures.squad(1,68,rng)
	var b: Array=a.duplicate(true)
	for p in b:
		p.id+=1000
		p.club_id=2
	var coach := Fixtures.coach(1,rng)
	coach.attributes.tactics=18
	coach.attributes.motivation=18
	var weak: Dictionary=coach.duplicate(true)
	weak.attributes.tactics=4
	weak.attributes.motivation=4
	print("COACH PLANS ",coach)
	for influence in [0,1]:
		Config.apply_values({"coach_influence":influence},false)
		var w := 0
		var g := 0
		var c := 0
		var plans := {}
		var performance := {"home_passes":0,"away_passes":0,"home_completed":0,"away_completed":0,"home_shots":0,"away_shots":0}
		for i in 160:
			rng.seed=87111+i
			var r := MatchEngine.simulate({"home":{"club_id":1,"squad":a,"coach":coach},"away":{"club_id":2,"squad":b,"coach":weak},"neutral":true},rng)
			for side in ["home","away"]:
				performance[side+"_passes"]+=r[side+"_team"].actions.passes
				performance[side+"_completed"]+=r[side+"_team"].actions.completed_passes
				performance[side+"_shots"]+=r[side+"_team"].shots
			w+=int(r.home_goals>r.away_goals)
			g+=r.home_goals
			c+=r.away_goals
			var key: String=r.home_team.initial_style+"/"+r.away_team.initial_style+"/"+r.home_team.formation+"/"+r.away_team.formation
			plans[key]=int(plans.get(key,0))+1
		print("COACH influence=",influence," wins ",w," goals ",g,":",c," plans ",plans," performance ",performance)
	get_tree().quit()
