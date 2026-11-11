extends Node
const MatchEngineScript := preload("res://game/match_engine.gd")
const Config := preload("res://game/match_simulation_config.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(message)

func _run() -> void:
	Config.config_path = "user://tests/match_stability.json"
	Config.apply_values({"fresh_after_stamina_1":0.1,"fresh_after_stamina_10":0.3,"fresh_after_stamina_20":0.7,
		"condition_after_stamina_1":10.0,"condition_after_stamina_10":40.0,"condition_after_stamina_20":70.0,
		"injury_per_phase":0.20}, false)
	_test_workload()
	_test_dismissal()
	_test_no_keeper_replacement()
	_test_injury()
	_test_report()
	_test_keeper_callup()
	_test_squad_edge()
	_test_scoring_pace_preserves_strength()
	_test_distribution()
	print("=== Match stability: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _test_squad_edge() -> void:
	var rules: Script=load("res://game/action_rules.gd")
	var previous := 0.0
	for value in range(1,21):
		var edge: float=rules.duel(value,10)
		check(edge>previous,"each individual skill point improves its duel")
		check(absf(edge+rules.duel(10,value)-1.0)<0.00001,"individual duels are symmetric")
		previous=edge
	check(not MatchEngineScript.new().has_method("_squad_factor"),"collective CA factor has been removed")

func _test_scoring_pace_preserves_strength() -> void:
	var fixture := _fixture()
	var a: Dictionary=fixture.spec
	var b: Dictionary=a.duplicate(true)
	b.club_id=2
	for p in b.squad: p.id+=1000
	var counts := []
	var saved := Config.snapshot()
	for pace in [0.4,2.4]:
		Config.apply_values({"chances_per_phase":pace},false)
		var actions := 0
		for j in 30:
			var rng := RandomNumberGenerator.new()
			rng.seed=81511+j
			var r := MatchEngineScript.simulate({"home":a,"away":b,"neutral":true},rng)
			for side in ["home_team","away_team"]: actions+=r[side].actions.passes+r[side].actions.dribbles+r[side].shots
		counts.append(actions)
	check(counts[1]>counts[0],"tempo changes the number of real actions, not a team chance quota")
	Config.apply_values(saved,false)


func _fixture() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91827
	var squad := Fixtures.squad(1,80,rng,0)
	for player in squad:
		player["attributes"]["physical"]["stamina"] = 10
		MatchRatings.invalidate(player)
	var coach := {"attributes":{"tactics":10,"motivation":10},"primary_style":"control","backup_style":"control",
		"primary_formation":"2-3-2","backup_formation":"2-3-2"}
	var spec := {"club_id":1,"squad":squad,"coach":coach}
	var lineup := MatchEngineScript._select_lineup(spec,rng)
	var team := MatchEngineScript._build_team("home",spec,lineup,80.0,80.0,rng,Config.snapshot())
	return {"squad":squad,"team":team,"rng":rng,"spec":spec,
		"ctx":{"events":[],"rng":rng,"knobs":Config.snapshot(),"discipline":DisciplineRules.defaults(),"importance":1.0}}

func _test_workload() -> void:
	var fixture := _fixture()
	var team: Dictionary = fixture["team"]
	var keeper: Dictionary = MatchEngineScript._keeper_of(team)
	var outfield: Dictionary = {}
	for unit in team["on_field"]:
		if unit["slot"] != "GK":
			outfield = unit
			break
	var opposition: Dictionary=_fixture().team
	opposition.side="away"
	for n in 10:
		load("res://game/action_pitch.gd").play(team,opposition,fixture.ctx,n*5,false)
	check(float(keeper["fresh"])>0.70,"Keeper retains goalkeeping effectiveness through ordinary match")
	check(float(outfield["fresh"])<float(keeper["fresh"])-0.15,"Outfield workload still matters")
	var keeper_player: Dictionary = keeper["player"].duplicate(true)
	var field_player: Dictionary = keeper_player.duplicate(true)
	field_player["position"] = "CB"
	MatchRatings.invalidate(field_player)
	PlayerCondition.apply_match_load(keeper_player,50,1.0)
	PlayerCondition.apply_match_load(field_player,50,1.0)
	check(PlayerCondition.condition_of(keeper_player)>PlayerCondition.condition_of(field_player)+20,"Daily goalkeeper load follows role")
	check(PlayerCondition.condition_of(field_player)<60,"Outfield match load not weakened")
	var rested: Dictionary = keeper["player"].duplicate(true)
	for n in 6:
		PlayerCondition.apply_match_load(rested,50,1.0)
		PlayerCondition.advance_round(rested,true)
	check(PlayerCondition.condition_of(rested)>=75,"Keeper does not collapse through six consecutive matchdays")
	check(PlayerCondition.condition_of(rested)<100,"Keeper still accumulates fatigue")
	var before := PlayerCondition.condition_of(rested)
	PlayerCondition.apply_match_load(rested,0,1.0)
	check(PlayerCondition.condition_of(rested)==before,"Unused keeper gets no match load")

func _test_dismissal() -> void:
	var fixture := _fixture()
	var team: Dictionary = fixture["team"]
	var keeper := MatchEngineScript._keeper_of(team)
	var original_id := int(keeper["player"]["id"])
	MatchEngineScript._send_off(team,keeper,fixture["ctx"],10)
	check(team["on_field"].size()==7,"Keeper red card still leaves team a player down")
	check(int(team["men_down"])==1,"Substitution cannot cancel numerical disadvantage")
	check(team["subs_left"]==4,"Emergency keeper consumes one substitution")
	var replacement := MatchEngineScript._keeper_of(team)
	check(bool(replacement["ratings"]["is_gk"]),"Native reserve goalkeeper enters after red card")
	check(int(replacement["player"]["id"])!=original_id,"Dismissed goalkeeper cannot return")
	check(team["on_field"].count(keeper)==0,"Sent-off player stays outside field")
	check(fixture["ctx"]["events"].back().get("reason","")=="goalkeeper_dismissal","Emergency substitution has correct reason")
	check(int(keeper["entry"]["minutes"])==10,"Dismissed player's minutes close at card")
	MatchEngineScript._close_minutes(team,50)
	check(int(replacement["entry"]["minutes"])==40,"Reserve keeper minutes start at substitution")
	check(int(team["subs_left"])>=0,"Substitutions remain bounded")

func _test_no_keeper_replacement() -> void:
	var fixture := _fixture()
	var team: Dictionary = fixture["team"]
	team["bench"] = []
	MatchEngineScript._send_off(team,MatchEngineScript._keeper_of(team),fixture["ctx"],10)
	check(team["on_field"].size()==7,"No reserve: team remains seven players")
	check(not bool(MatchEngineScript._keeper_of(team)["ratings"]["is_gk"]),"No reserve does not invent a goalkeeper")
	check(team["subs_left"]==5,"Unavailable substitution is not consumed")
	fixture = _fixture()
	team = fixture["team"]
	team["subs_left"] = 0
	MatchEngineScript._send_off(team,MatchEngineScript._keeper_of(team),fixture["ctx"],10)
	check(team["on_field"].size()==7 and team["subs_left"]==0,"No substitution windows: no extra player enters")

func _test_injury() -> void:
	var fixture := _fixture()
	var team: Dictionary = fixture["team"]
	var keeper := MatchEngineScript._keeper_of(team)
	team["on_field"] = [keeper]
	team["bench"] = []
	for n in 100:
		MatchEngineScript._roll_injuries(team,fixture["ctx"],20,1.0)
		if not str(keeper["entry"]["injury_grade"]).is_empty():
			break
	check(not str(keeper["entry"]["injury_grade"]).is_empty(),"Deterministic injury fixture triggers injury")
	check(team["on_field"].is_empty(),"Injured goalkeeper leaves field even without a suitable replacement")
	check(team["men_down"]==1,"Unreplaceable injury records numerical disadvantage")
	check(team["subs_left"]==5,"Failed injury substitution does not spend window")
	check(keeper["entry"]["minutes"]==20,"Injured goalkeeper stops accumulating minutes")

func _test_report() -> void:
	var fixture := _fixture()
	var report := MatchEngineScript.simulate({"home":fixture["spec"],"away":fixture["spec"],"neutral":true},fixture["rng"])
	var compact := MatchDay._compact_report(report)
	check(compact.get("engine","")=="individual-spatial-v3" and compact.home.has("actions"),"Match report preserves action-engine version and actual actions")
	check(compact["home"].get("starting_condition",0)==100.0,"Match report preserves pre-match readiness")
	check(compact["home"].get("starting_keeper",{}).get("native",false),"Match report identifies starting goalkeeper")
	check(compact["home"]["starting_keeper"]["player_id"]>0,"Match report preserves goalkeeper ID")
	check(compact["home"]["starting_keeper"]["condition"]==100,"Goalkeeper readiness is saved before fatigue")
	check(compact.get("settings_version", 0) == Config.CONFIG_VERSION,"Report records the running settings revision")
	check(compact.get("settings_fingerprint", "") == Config.fingerprint(),"Report records the exact settings used by the engine")

func _test_distribution() -> void:
	Config.reset_to_defaults(false)
	Config.apply_values({"chances_per_phase":MatchTypes.CHANCES_PER_PHASE,"shot_on_target_base":0.63,"shot_conversion_base":0.30,"injury_per_phase":0.0},false)
	var goals := 0
	var extreme := 0
	var blowouts := 0
	var home_wins := 0
	var away_wins := 0
	var squad: Array = []
	var coach := {"attributes":{"tactics":10,"motivation":10},"primary_style":"control","backup_style":"control",
		"primary_formation":"2-3-2","backup_formation":"2-3-2"}
	for i in 800:
		var rng := RandomNumberGenerator.new()
		rng.seed = 772001+i*97
		if i%100==0:
			var fixture_rng := RandomNumberGenerator.new()
			fixture_rng.seed = 88201+i/100
			squad = Fixtures.squad(1,80,fixture_rng,0)
		var report := MatchEngineScript.simulate({"home":{"club_id":1,"squad":squad,"coach":coach},
			"away":{"club_id":2,"squad":squad,"coach":coach},"neutral":true,
			"discipline":DisciplineRules.from_rules({"discipline_enabled":false})},rng)
		var hg := int(report["home_goals"])
		var ag := int(report["away_goals"])
		goals += hg+ag
		extreme += int(maxi(hg,ag)>=8)
		blowouts += int(absi(hg-ag)>=8)
		home_wins += int(hg>ag)
		away_wins += int(ag>hg)
	var average := goals/800.0
	print("STABILITY regression: goals=",average," eight_plus=",extreme," eight_goal_margin=",blowouts," wins=",home_wins,"/",away_wins)
	check(average>=2.5 and average<7.0,"Aggressive scoring settings do not make equal strong keepers collapse")
	check(extreme<24,"Eight-goal scores remain a rare tail in equal squads")
	check(blowouts<8,"Eight-goal reversals remain exceptional even with aggressive accuracy")
	check(absf(home_wins-away_wins)/800.0<0.10,"No artificial home or team-ID stabilisation")

func _test_keeper_callup() -> void:
	var fixture := _fixture()
	var squad: Array = fixture["squad"]
	var reserve: Dictionary = squad[0].duplicate(true)
	reserve["id"] = 90001
	var injured_reserve: Dictionary = reserve.duplicate(true)
	injured_reserve["id"] = 90002
	PlayerCondition.assign_injury(injured_reserve,MatchTypes.INJURY_GRADE_LIGHT,3)
	PlayerCondition.assign_injury(squad[0],MatchTypes.INJURY_GRADE_LIGHT,3)
	PlayerCondition.add_suspension(squad[1],2)
	var lineup := LineupSelector.build(squad,[injured_reserve,reserve],fixture["spec"]["coach"],{"style":"control","formation":"2-3-2"},fixture["rng"])
	var keeper: Dictionary = {}
	for record in lineup["starters"]:
		if record["slot"] == "GK":
			keeper = record["player"]
	check(int(keeper.get("id",0))==90001,"Club calls available reserve keeper despite having eight outfield players")
	check(lineup["starters"].size()==8,"Reserve callup preserves full lineup")
	check(lineup["used_youth"]==1,"Injured reserve goalkeeper cannot be called up")
	var ids := {}
	for record in lineup["starters"]:
		ids[record["player"]["id"]] = true
	for player in lineup["bench"]:
		ids[player["id"]] = true
	check(ids.size()==lineup["starters"].size()+lineup["bench"].size(),"Reserve callup never duplicates player in match roster")
	fixture = _fixture()
	squad = fixture["squad"]
	PlayerCondition.add_suspension(squad[1],2)
	lineup = LineupSelector.build(squad,[reserve],fixture["spec"]["coach"],{"style":"control","formation":"2-3-2"},fixture["rng"])
	check(lineup["bench"].any(func(p): return PlayerTypes.normalize_position(p["position"])=="GK"),"A lone available first-team keeper gets emergency reserve cover")
	lineup = LineupSelector.build(squad,[],fixture["spec"]["coach"],{"style":"control","formation":"2-3-2"},fixture["rng"])
	check(lineup["used_youth"]==0,"Fixed roster without reserve pool never invents replacements")
