extends Node
const Config := preload("res://game/match_simulation_config.gd")
const Match :=  preload("res://game/match_engine.gd")
const Coaching := preload("res://game/match_coaching.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0
var report := {}

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", message)

func coach() -> Dictionary:
	return {"attributes":{"tactics":12,"motivation":10}, "primary_style":"control","backup_style":"control","primary_formation":"2-3-2","backup_formation":"2-3-2"}

func squad(id: int, ca: int = 65) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 580000 + id
	return Fixtures.squad(id, ca, rng, 0)

func simulate(a: Array, b: Array, seed_value: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return Match.simulate({"home":{"club_id":1,"squad":a,"coach":coach()},"away":{"club_id":2,"squad":b,"coach":coach()},"neutral":true,"allow_draw":true,"discipline":{"enabled":false}},rng)

func subs(result: Dictionary, side: String) -> Array:
	return result.events.filter(func(e): return e.type == "SUB" and e.side == side)

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.config_path = "user://tests/rotation-settings-v6.json"
	Config.apply_values({"injury_per_phase":0.0},false)
	var a := squad(1)
	var b := squad(2)
	var total := 0
	var none := 0
	var max_count := 0
	for i in 300:
		var result := simulate(a,b,320000+i)
		for side in ["home","away"]:
			var changes := subs(result,side)
			total += changes.size()
			none += int(changes.is_empty())
			max_count = maxi(max_count,changes.size())
			for event in changes:
				check(int(event.minute)>=25 and int(event.minute)<50,"Planned changes occur in the useful part of the match")
			for player in result[side+"_team"].players:
				if not player.started:
					check(int(player.minutes)>0,"A substitute actually gets playing time")
	var mean := float(total)/600.0
	check(mean>=2.0 and mean<=5.0,"Comparable squads use the bench regularly")
	check(max_count<=5,"Default limit of five is respected")
	report["default"] = {"matches":300,"subs_per_team":mean,"teams_without_subs":none,"team_appearances":600,"max_subs":max_count}
	for limit in [0,2]:
		Config.apply_values({"injury_per_phase":0.0,"subs_max":limit,"subs_first_minute":35.0},false)
		for i in 20:
			var result := simulate(a,b,440000+i)
			for side in ["home","away"]:
				check(subs(result,side).size()<=limit,"Configured substitution limit is enforced")
				for event in subs(result,side):
					check(event.minute>=35,"Configured first minute also applies to tactical changes")
	Config.apply_values({"injury_per_phase":0.0},false)
	var starts := {}
	var appearances := {}
	var changes_between_days := 0
	var previous := {}
	for day in 12:
		var result := simulate(a,b,550000+day)
		var current := {}
		var played := {}
		for entry in result.home_team.players:
			played[int(entry.player_id)] = int(entry.minutes)>0
			if entry.minutes>0 and not entry.is_gk:
				appearances[int(entry.player_id)] = true
			if entry.started and not entry.is_gk:
				starts[int(entry.player_id)] = true
				current[int(entry.player_id)] = true
			for player in a:
				if int(player.id)==int(entry.player_id):
					PlayerCondition.apply_match_load(player,int(entry.minutes),float(entry.intensity_minutes)/maxi(1,int(entry.minutes)))
		if day>0:
			for id in current:
				changes_between_days += int(not previous.has(id))
		previous = current
		for player in a:
			PlayerCondition.advance_round(player,bool(played.get(int(player.id),false)))
	check(starts.size()>=10,"Consecutive matchdays rotate field starters when replacements are comparable")
	check(appearances.size()>=12,"Rotation gives meaningful participation to the bench")
	check(changes_between_days>=5,"Rotation is repeated rather than a one-off selection change")
	report["twelve_matchdays"] = {"distinct_field_starters":starts.size(),"field_players_used":appearances.size(),"new_starters_across_days":changes_between_days}
	_test_emergency_and_quality()
	_test_rules_and_editor()
	var output := OS.get_cmdline_user_args()
	if not output.is_empty():
		FileAccess.open(output[0],FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	Config.config_path = Config.DEFAULT_CONFIG_PATH
	Config.reset_to_defaults(false)
	print("ROTATION REPORT ",JSON.stringify(report))
	print("=== Match rotation: %d passed, %d failed ===" % [passed,failed])
	get_tree().quit(1 if failed else 0)

func _test_rules_and_editor() -> void:
	Config.apply_values({"coach_influence":0.0,"tactics_influence":0.0},false)
	check(not Match.new().has_method("_coach_factor"),"No flat collective coach execution bonus remains")
	check(not Match.new().has_method("_coach_edge"),"No flat episode coaching edge remains")
	for value in Coaching.profile("defensive","chase",true).values():
		check(is_equal_approx(float(value),1.0),"Zero tactics influence neutralises tactical profile modifiers")
	Config.reset_to_defaults(false)
	check(Coaching.profile("defensive","normal",false).intensity<Coaching.profile("attacking","normal",false).intensity,"Defensive character retains a slightly lower running demand")
	var values := Config.default_values()
	values.fresh_after_stamina_20 = 0.30
	check(not Config.validation_error(values).is_empty(),"Contradictory stamina settings have a plain-language explanation")
	values = Config.default_values()
	values.subs_first_minute=40.0
	values.subs_reserve_until=25.0
	check(not Config.validation_error(values).is_empty(),"Contradictory substitution times are explained")
	check(Config.GROUPS.size()==5,"Settings have exactly five requested sections")
	var tab := (load("res://scenes/settings/tabs/match_sim_tab.tscn") as PackedScene).instantiate()
	add_child(tab)
	check(tab._fields.size()==Config.schema().size(),"All settings are retained across visible and hidden sections")
	for group in Config.GROUPS:
		tab._select_group(str(group.id))
		var visible_count := 0
		for panel in tab._group_panels.values():
			visible_count += int(panel.visible)
		check(visible_count==1,"Only the chosen settings section is shown")
	check(not tab._fields.has("quality_exponent"),"Obsolete CA-based influence is not offered in spatial settings")
	for field in tab._fields.values():
		check(field.hint.contains("Рекомендуется:"),"Every control explains its recommended value")
	Config.apply_values({"subs_max":2.0,"subs_first_minute":35.0},true)
	Config.unload()
	check(Config.get_f("subs_max")==2.0 and Config.get_f("subs_first_minute")==35.0,"Substitution rules survive save and reload")
	DirAccess.remove_absolute(Config.config_path)
	tab.queue_free()

func _test_emergency_and_quality() -> void:
	Config.reset_to_defaults(false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99281
	var spec := {"club_id":1,"squad":squad(8,80),"coach":coach()}
	var lineup := Match._select_lineup(spec,rng)
	var team := Match._build_team("home",spec,lineup,80.0,80.0,rng,Config.snapshot())
	var ctx := {"rng":rng,"events":[],"knobs":Config.snapshot()}
	var outgoing: Dictionary = {}
	for unit in team.on_field:
		if not unit.ratings.is_gk:
			outgoing = unit
			break
	outgoing.fresh = 0.5
	team.bench = squad(9,20).filter(func(p): return p.position != "GK")
	check(not Match._substitute(team,outgoing,ctx,30,false),"A weak bench is not used only to fill a substitution quota")
	check(not Match._substitute(team,outgoing,ctx,5,false),"Planned substitutions wait until the configured minute")
	team.subs_left = 1
	check(not Match._substitute(team,outgoing,ctx,30,false),"The last substitution is reserved until the configured minute")
	check(Match._substitute(team,outgoing,ctx,5,true,"injury"),"An injury bypasses timing, reserve and quality gates")
	check(team.subs_left==0,"Emergency substitutions still consume the limit")
	check(not Match._substitute(team,team.on_field[0],ctx,10,true,"injury"),"Emergency substitutions cannot exceed the limit")
