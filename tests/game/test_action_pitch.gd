extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Rules := preload("res://game/action_rules.gd")
const Pitch := preload("res://game/action_pitch.gd")
const Config := preload("res://game/match_simulation_config.gd")
var passed := 0
var failed := 0
func _ready() -> void: call_deferred("run")
func check(ok: bool,message: String) -> void:
	if ok: passed+=1
	else:
		failed+=1
		print("FAIL: ",message)
func random(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed=seed_value
	return rng
func coach() -> Dictionary:
	var c := {"attributes":{"tactics":12,"motivation":10,"discipline":10},"primary_style":"control","backup_style":"control","primary_formation":"2-3-2","backup_formation":"2-3-2"}
	TacticTypes.ensure_coach_tactics(c)
	return c
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.reset_to_defaults(false)
	check(Rules.PITCH_LENGTH==60 and Rules.PITCH_WIDTH==40 and not Rules.OFFSIDE,"agreed pitch and no offside")
	check(Rules.duel(10,20)<Rules.duel(10,10)*0.5,"defence 20 more than halves dribble success against 10")
	check(Rules.duel(20,19)>Rules.duel(19,19)+0.03,"one skill point changes equal duel by over three percentage points")
	for key in range(1,20):
		check(Rules.running_speed(key+1)>Rules.running_speed(key),"pace is actual running speed")
		check(Rules.reaction_delay(key+1)<Rules.reaction_delay(key),"reflexes are response time")
		check(Rules.trap_time(key+1)<Rules.trap_time(key),"technique is first-touch time")
		check(Rules.shot_sigma(key+1,12)<Rules.shot_sigma(key,12),"finishing is shot dispersion")
	var solved: PackedInt32Array=load("res://game/lineup_assignment.gd").solve([[9.0,8.0,0.0],[8.0,0.0,0.0]])
	check(solved==PackedInt32Array([1,0]),"role assignment considers all players together rather than stealing a scarce role")
	var matrix_rng := random(834151)
	for trial in 120:
		var matrix: Array=[]
		for row in 3:
			var values: Array=[]
			for column in 5: values.append(float(matrix_rng.randi_range(-5,30)))
			matrix.append(values)
		var best := -INF
		for i in 5:
			for j in 5:
				for k in 5:
					if i!=j and j!=k and i!=k: best=maxf(best,matrix[0][i]+matrix[1][j]+matrix[2][k])
		var chosen: PackedInt32Array=load("res://game/lineup_assignment.gd").solve(matrix)
		var value: float=matrix[0][chosen[0]]+matrix[1][chosen[1]]+matrix[2][chosen[2]]
		check(is_equal_approx(value,best),"global role assignment agrees with exhaustive independent search")
	var penalties := []
	for value in [5,10,15,19,20]:
		var goals := 0
		var rng := random(3412)
		for j in 20000: goals+=int(Rules.penalty_trial(value,12,12,rng)==2)
		penalties.append(goals)
	for j in range(1,penalties.size()): check(penalties[j]>penalties[j-1],"penalty skill improves physical shot outcomes")
	print("PENALTY GOALS / 20000 ",penalties)
	var conceded := []
	for value in [5,20]:
		var samples := random(62813)
		var goals := 0
		for j in 20000: goals+=int(Rules.penalty_trial(16,12,value,samples)==2)
		conceded.append(goals)
	check(conceded[1]<conceded[0],"better keeper positioning cannot make penalty coverage worse")
	var rng := random(10421)
	var a := Fixtures.squad(1,65,rng)
	var b := Fixtures.squad(2,65,rng)
	var cfg := {"home":{"club_id":1,"squad":a,"coach":coach()},"away":{"club_id":2,"squad":b,"coach":coach()},"neutral":true,"allow_draw":true,"trace_actions":true}
	var mutated: Dictionary = cfg.duplicate(true)
	mutated.home.reputation=1000
	mutated.away.reputation=1
	for side in ["home","away"]:
		for p in mutated[side].squad:
			p.current_ability=1 if side=="home" else 100
			p.potential_ability=100
			MatchRatings.invalidate(p)
	for j in 12:
		var actual := MatchEngine.simulate(cfg.duplicate(true),random(67200+j))
		var changed := MatchEngine.simulate(mutated.duplicate(true),random(67200+j))
		check(actual==changed,"CA, PA and reputation cannot alter any match event or statistic")
		validate(actual)
	# One phase with fixed active players: unused bench skills cannot enter any action.
	var lineup_a := MatchEngine._select_lineup(cfg.home,random(25),cfg.away)
	var lineup_b := MatchEngine._select_lineup(cfg.away,random(26),cfg.home)
	var home := MatchEngine._build_team("home",cfg.home,lineup_a,0,0,random(10),Config.snapshot())
	var away := MatchEngine._build_team("away",cfg.away,lineup_b,0,0,random(11),Config.snapshot())
	var home_copy: Dictionary=home.duplicate(true)
	var away_copy: Dictionary=away.duplicate(true)
	for p in home_copy.bench+away_copy.bench:
		for group in p.attributes.values():
			for key in group: group[key]=20
	var ctx := {"rng":random(431),"knobs":Config.snapshot(),"events":[],"trace_actions":true,"discipline":{},"importance":1}
	var ctx_copy: Dictionary=ctx.duplicate(true)
	ctx_copy.rng=random(431)
	Pitch.play(home,away,ctx,0,false)
	Pitch.play(home_copy,away_copy,ctx_copy,0,false)
	check(ctx.events==ctx_copy.events and home.on_field.map(func(u):return u.entry)==home_copy.on_field.map(func(u):return u.entry) and away.on_field.map(func(u):return u.entry)==away_copy.on_field.map(func(u):return u.entry),"unused bench has no direct contribution")
	check(ctx.rng.state==ctx_copy.rng.state,"unused bench cannot consume action randomness")
	var emergency := Pitch.new()
	var depleted: Dictionary=home.duplicate(true)
	depleted.on_field=depleted.on_field.filter(func(u):return u.slot!="GK")
	emergency.teams=[depleted,away]
	emergency.build_actors(false)
	var stand_ins: Array=emergency.actors.filter(func(actor):return actor.side==0 and actor.slot=="GK")
	check(stand_ins.size()==1,"a field player covers the goal when no native keeper remains")
	check(stand_ins[0].skill[Pitch.REFLEX]==1,"emergency keeper does not acquire professional goalkeeping attributes")
	var eight: Array=[]
	for index in [0,2,3,4,9,10,15,16]: eight.append(a[index].duplicate(true))
	for p in eight:
		for group in p.attributes.values():
			for key in group: group[key]=10
		MatchRatings.invalidate(p)
	eight[-1].attributes.technical.finishing=20
	MatchRatings.invalidate(eight[-1])
	var chosen := MatchEngine._select_lineup({"club_id":1,"squad":eight,"coach":{}},random(91))
	var strikers: Array=chosen.starters.filter(func(row):return row.slot=="ST")
	check(strikers.size()==2 and strikers.any(func(row):return int(row.player.id)==int(eight[-1].id)),"improving a finisher keeps him in the striker role")
	var old_backend := NativeSimulation.enabled
	NativeSimulation.enabled=false
	for j in 5:
		var case_cfg: Dictionary=cfg.duplicate(true)
		if j==4:
			# Diagnostic worlds may reuse IDs across sides; their skills must stay separate.
			for p in case_cfg.away.squad:
				p.id=int(p.id)-1000
				p.attributes.technical.finishing=3
				p.attributes.physical.pace=6
				MatchRatings.invalidate(p)
		var reference_rng := random(8361+j)
		var native_rng := random(8361+j)
		var reference := MatchEngine.simulate(case_cfg.duplicate(true),reference_rng)
		var native: Variant=NativeSimulation.core(false)
		# Explicit native handle while reference stays disabled.
		if native==null:
			NativeSimulation.enabled=true
			native=NativeSimulation.core()
			NativeSimulation.enabled=false
		var result: Dictionary=native.simulate(case_cfg.duplicate(true),native_rng,Config.fingerprint())
		if reference!=result:
			print("PARITY DIFFERENCE ",first_difference(reference,result))
			for event_index in mini(reference.events.size(),result.events.size()):
				if reference.events[event_index]!=result.events[event_index]:
					print("FIRST EVENT ",event_index," ",reference.events[event_index]," / ",result.events[event_index])
					break
		check(reference==result and reference_rng.state==native_rng.state,"independent reference and C++ actions match exactly")
	NativeSimulation.enabled=old_backend
	print("=== Action pitch: ",passed," passed, ",failed," failed ===")
	get_tree().quit(1 if failed else 0)
func first_difference(a: Variant,b: Variant,path: String="") -> String:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return path+"/"+str(key)+" missing"
			if a[key]!=b[key]: return first_difference(a[key],b[key],path+"/"+str(key))
		for key in b:
			if not a.has(key): return path+"/"+str(key)+" extra"
	elif a is Array and b is Array:
		if a.size()!=b.size(): return path+" sizes "+str(a.size())+" / "+str(b.size())
		for j in a.size():
			if a[j]!=b[j]: return first_difference(a[j],b[j],path+"/"+str(j))
	return path+": "+str(a)+" / "+str(b)
func validate(result: Dictionary) -> void:
	var known := {}
	var entries := {}
	for side in ["home_team","away_team"]:
		for row in result[side].players:
			known[int(row.player_id)]=true
			entries[int(row.player_id)]=row
			check(int(row.minutes)>=0 and int(row.minutes)<=int(result.minutes_played),"valid appearance duration")
		check(result[side].actions.completed_passes<=result[side].actions.passes,"completed passes cannot exceed attempts")
	var second := -1.0
	for event in result.events:
		var now := float(event.get("second",int(event.minute)*60))
		check(now>=second,"events follow match clock")
		second=now
		if event.type in ["PASS","CROSS","SHOT","DRIBBLE","CONTACT","INTERCEPTION","BLOCK","CARRY","SAVE","FOUL"]:
			check(known.has(int(event.player_id)),"only an actual participant can act")
			if event.has("x"): check(is_finite(float(event.x)) and is_finite(float(event.y)),"finite event coordinates")
