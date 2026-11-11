extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const Config := preload("res://game/match_simulation_config.gd")
const Native := preload("res://game/native_simulation.gd")
var passed := 0
var failed := 0
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: passed+=1
	else:
		failed+=1
		print("FAIL: ",message)
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.reset_to_defaults(false)
	var core: Variant = Native.core()
	check(core!=null,"C++ extension is loaded")
	if core==null:
		get_tree().quit(1)
		return
	print("NATIVE BACKEND ",Native.backend())
	Native.enabled = false
	var rng := RandomNumberGenerator.new()
	rng.seed=548182
	for trial in 25:
		var squad := Fixtures.squad(trial+1,30+trial*2,rng)
		for player in squad:
			player.erase("_match_ratings")
			var native_player: Dictionary = player.duplicate(true)
			var expected := MatchRatings.of(player)
			var actual: Dictionary = core.build_ratings(native_player)
			check(expected==actual,"C++ derived ratings equal GDScript")
			for position in PlayerTypes.POSITIONS:
				check(core.ability_exact(player.attributes,position)==PlayerTypes.calc_ability_exact(player.attributes,position),"C++ CA calculation equals GDScript")
		var source := squad.duplicate(true)
		var converted := squad.duplicate(true)
		for formation in ["2-3-2","3-2-2","2-4-1"]:
			var slots: Array=TacticTypes.starting_xi(formation)
			for style in LineupSelector.STYLE_WEIGHTS:
				var expected := LineupSelector._rate_pool(source,slots,style)
				var actual: Dictionary=core.rate_pool(converted,slots,style)
				check(expected==actual,"C++ positional scores preserve float32 outputs")
		for national in [false,true]:
			var coach := Fixtures.coach(trial+1,rng)
			coach["national_selection"]=national
			for formation in TacticTypes.FORMATIONS:
				var plan := {"formation":formation,"style":CoachTypes.primary_style_of(coach)}
				var a := RandomNumberGenerator.new()
				var b := RandomNumberGenerator.new()
				a.seed=trial*501+77
				b.seed=a.seed
				var expected := LineupSelector.build(squad.duplicate(true),[],coach,plan,a)
				var actual: Dictionary = core.build_lineup(squad.duplicate(true),[],coach,plan,b,true)
				check(lineup_view(expected)==lineup_view(actual),"Native starting team and bench equal reference")
				check(a.state==b.state,"Native selection consumes the same random draws")
		for player in squad:
			for injury in [0,2]:
				player.injury_rounds=injury
				player.condition=rng.randi_range(0,100)
				player.morale=rng.randi_range(0,100)
				var expected: Dictionary=player.duplicate(true)
				var actual: Dictionary=player.duplicate(true)
				PlayerCondition.advance_round(expected,true)
				core.recover_player(actual,true)
				check(expected==actual,"C++ recovery retains condition, injury and morale")
	_test_preview_reputation(core)
	_test_generation_market(core)
	_test_lifecycle(core)
	_test_legacy_positions(core)
	_test_agents(core)
	_test_extremes(core)
	_test_matches(core)
	print("=== Native simulation: %d passed, %d failed ===" % [passed,failed])
	Native.enabled = true
	get_tree().quit(1 if failed else 0)

func lineup_view(lineup: Dictionary) -> Dictionary:
	var view := {"formation":lineup.formation,"style":lineup.style,"short":lineup.short,"youth":lineup.used_youth,"starters":[],"bench":[]}
	for row in lineup.starters:
		view.starters.append([row.player.id,row.slot,row.fit,row.selection_score])
	for player in lineup.bench:
		view.bench.append(player.id)
	return view

func _test_matches(core: Variant) -> void:
	var fixtures_rng := RandomNumberGenerator.new()
	fixtures_rng.seed=904472
	for trial in 500:
		if trial%50==0: print("MATCH PARITY ",trial," / 500")
		var home := Fixtures.squad(1,50+trial%40,fixtures_rng)
		var away := Fixtures.squad(2,50+(trial*3)%40,fixtures_rng)
		var hc := Fixtures.coach(1,fixtures_rng)
		var ac := Fixtures.coach(2,fixtures_rng)
		hc["national_selection"] = trial%5==0
		ac["national_selection"] = trial%5==0
		var spec := {"home":{"club_id":1,"squad":home,"coach":hc,"reputation":800},"away":{"club_id":2,"squad":away,"coach":ac,"reputation":500},"neutral":trial%2==0,"allow_draw":trial%3!=0}
		var a := RandomNumberGenerator.new()
		var z := RandomNumberGenerator.new()
		a.seed=80871+trial
		z.seed=a.seed
		var expected := MatchEngine.simulate(spec.duplicate(true),a)
		var actual: Dictionary=core.simulate(spec.duplicate(true),z,Config.fingerprint())
		check(expected==actual,"Complete native match report equals GDScript")
		check(a.state==z.state,"Complete native match keeps the same RNG state")
		if expected!=actual or a.state!=z.state:
			print("NATIVE FIRST DIFFERENCE trial=",trial," RNG=",a.state,"/",z.state)
			print(difference(expected,actual,"report"))
			FileAccess.open("user://tests/native-expected.json",FileAccess.WRITE).store_string(JSON.stringify(expected,"\t"))
			FileAccess.open("user://tests/native-actual.json",FileAccess.WRITE).store_string(JSON.stringify(actual,"\t"))
			return

func difference(a: Variant,z: Variant,path: String) -> String:
	if typeof(a)!=typeof(z):return "%s type %s / %s" % [path,typeof(a),typeof(z)]
	if a is Dictionary:
		if a.keys()!=z.keys():return "%s keys %s / %s" % [path,a.keys(),z.keys()]
		for key in a:
			if a[key]!=z[key]:return difference(a[key],z[key],path+"."+str(key))
	elif a is Array:
		if a.size()!=z.size():return "%s size %s / %s" % [path,a.size(),z.size()]
		for j in a.size():
			if a[j]!=z[j]:return difference(a[j],z[j],path+"["+str(j)+"]")
	return "%s value %s / %s" % [path,a,z]

func _test_lifecycle(core: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 318881
	for trial in 20:
		var squad := Fixtures.squad(trial+1,30+trial*3,rng)
		for player in squad:
			var profile := PlayerTypes.roll_aptitudes(rng,player.position)
			for target in [12.0,51.25,95.0]:
				for preferred in ["", "physical"]:
					for aptitudes in [{}, profile]:
						var expected: Dictionary = player.attributes.duplicate(true)
						var actual: Dictionary = player.attributes.duplicate(true)
						PlayerTypes.fit_attributes_to_exact(expected,player.position,target,preferred,aptitudes)
						core.fit_attributes(actual,player.position,target,preferred,aptitudes)
						check(expected==actual,"Native attribute fitting equals reference")
			var expected: Dictionary = player.duplicate(true)
			var actual: Dictionary = player.duplicate(true)
			for stint in 3:
				var entry := {"minutes":45,"rating":6.7+stint*0.1,"started":stint==0,"goals":stint,"assists":1,"motm":true,"injury_rounds":stint,"clean_sheet":true}
				PlayerStats.apply_entry(expected,entry,7,10+stint)
				core.apply_entry_stats(actual,entry,7,10+stint)
				check(expected==actual,"Native stats folding and club stints equal reference")
			for minutes in [0,15,50,60]:
				expected=player.duplicate(true)
				actual=player.duplicate(true)
				PlayerCondition.apply_match_load(expected,minutes,1.23)
				core.apply_match_load(actual,minutes,1.23)
				check(expected==actual,"Native post-match condition equals reference")

func _test_generation_market(core: Variant) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 95014
	for position in PlayerTypes.POSITIONS:
		for target in [20,45,65,85,99]:
			var a := RandomNumberGenerator.new()
			var z := RandomNumberGenerator.new()
			a.seed = 551+target
			z.seed = a.seed
			for aptitudes in [{}, PlayerTypes.roll_aptitudes(rng,position)]:
				var expected := PlayerGenerator._roll_attributes(a,position,target,aptitudes)
				var actual: Dictionary = core.roll_attributes(z,position,target,aptitudes)
				check(expected==actual,"Native generated attributes equal reference")
				check(a.state==z.state,"Native attribute generation retains RNG")
	for talent in [0,50,74,85,98,100]:
		for count in [0,1,7,200]:
			var a := RandomNumberGenerator.new()
			var z := RandomNumberGenerator.new()
			a.seed = 5001+talent+count
			z.seed = a.seed
			var weights := YouthGenerationConfig.birth_weights(talent)
			check(YouthGenerationConfig.roll_birth_cohort(talent,count,a)==core.roll_birth(weights,count,z,true),"Native country cohorts equal reference")
			check(a.state==z.state,"Native cohort generation retains RNG")
		for j in 100:
			var a := RandomNumberGenerator.new()
			var z := RandomNumberGenerator.new()
			a.seed = j*1024+talent
			z.seed = a.seed
			check(YouthGenerationConfig.roll_birth_potential(talent,a)==core.roll_birth(YouthGenerationConfig.birth_weights(talent),1,z,false)[0],"Native individual potential equals reference")
			check(a.state==z.state,"Native individual potential retains RNG")
	var squad := Fixtures.squad(1,70,rng)
	for j in squad.size():
		if j % 2 == 0:
			squad[j][PlayerTypes.APTITUDES_KEY] = PlayerTypes.roll_aptitudes(rng,squad[j].position)
	for player in squad:
		for age in [16,24,31,38]:
			var expected: Dictionary = player.duplicate(true)
			var actual: Dictionary = player.duplicate(true)
			expected.age=age
			actual.age=age
			var a := RandomNumberGenerator.new()
			var z := RandomNumberGenerator.new()
			a.seed = 78601+age+player.id
			z.seed=a.seed
			var setup := {"facility":13,"coaching":19}
			PlayerDevelopment.develop_player(expected,setup,a,0.68,25)
			core.develop_player(actual,setup,z,0.68,25)
			check(expected==actual,"Native seasonal development equals reference: "+difference(expected,actual,"player"))
			check(a.state==z.state,"Native development retains RNG")
		for reputation in [0,300,700,1000]:
			var args := {"ability":player.current_ability,"potential":player.potential_ability,"age":player.age,"reputation":reputation}
			check(core.market_amount("wage",args)==PlayerMarket.wage_for(player.current_ability,reputation,player.age),"Native player wages equal reference")
			check(core.market_amount("value",args)==PlayerMarket.value_for(player.current_ability,player.potential_ability,player.age,reputation),"Native transfer values equal reference")
			check(core.market_amount("coach_wage",args)==PlayerMarket.coach_wage_for(player.current_ability,reputation,player.age),"Native coach wages equal reference")
			check(core.market_amount("target_reputation",args)==PlayerMarket.target_reputation(player.current_ability,reputation),"Native target fame equals reference")
			var club := {"reputation":reputation}
			for free in [true,false]:
				check(core.market_amount("move",{"player":player,"club":club,"free_agent":free})==PlayerMarket.wage_for_move(player,club,free),"Native transfer salary equals reference")
			var profile := PlayerOffer.profile(player,800)
			check(core.offer_profile(player,800)==profile,"Native sporting demands equal reference")
			var coach := {"attributes":{"negotiations":17}}
			for renewal in [false,true]:
				var context := {"renewal":renewal,"squad_ability":65,"source_reputation":600,"offer_wage":12000}
				check(core.evaluate_offer(profile,club,17,context)==PlayerOffer.evaluate_profile(profile,club,coach,context),"Native offer evaluation equals reference")

func _test_preview_reputation(core: Variant) -> void:
	for size in [0,1,3,8,16]:
		var clubs := []
		for j in size:
			clubs.append({"club_id":j+1,"club_name":"Team "+str(j),"regular":0.6+j*0.01,"knockout":0.7-j*0.01})
		var a := RandomNumberGenerator.new()
		var z := RandomNumberGenerator.new()
		a.seed=11551+size
		z.seed=a.seed
		check(SeasonPreview._simulate_table(clubs,a)==core.preview_table(clubs,z),"Native Monte Carlo league preview equals reference")
		check(a.state==z.state,"Native league preview retains RNG")
		for seeded in [false,true]:
			for single in [true,false]:
				a.seed=115551+size
				z.seed=a.seed
				var expected := SeasonPreview._one_knockout(clubs,a,seeded) if single else SeasonPreview._simulate_knockout(clubs,a,seeded)
				var actual: Dictionary = core.preview_knockout(clubs,z,seeded,single)
				check(expected==actual,"Native knockout preview equals reference: "+difference(expected,actual,"preview"))
				check(a.state==z.state,"Native knockout preview retains RNG")
	for strength in [0,500,1000]:
		for reputation in [0,500,1000]:
			for actual in [1,4,8]:
				var args := {"strength":strength,"current":reputation,"predicted":3,"actual":actual,"field":8,"participants":550.0}
				check(core.reputation_calc("table_step",args)==SeasonReputation._table_step(strength,reputation,3,actual,8,550.0),"Native club reputation table formula equals reference")
				check(core.reputation_calc("pull",args)==SeasonReputation._level_pull(strength,actual,8,reputation,550.0),"Native club reputation convergence equals reference")
				check(core.reputation_calc("bonus",args)==SeasonReputation._achievement_bonus(strength,reputation,actual,550.0),"Native club achievement formula equals reference")
				var p := {"strength":strength,"club_delta":-10,"matches":20,"rating":7.0,"ability":72,"minutes":450,"season_minutes":1000,"reputation":reputation}
				check(int(core.reputation_calc("player",p))==SeasonReputation.player_adjustment(strength,-10,20,7.0,72,450,1000,reputation),"Native player reputation equals reference")
	var rng := RandomNumberGenerator.new()
	rng.seed=93001
	var players := Fixtures.squad(1,70,rng)
	for player in players:
		for reputation in [0,500,1000]:
			var club := {"reputation":reputation}
			var coach := {"attributes":{"negotiations":17,"transfers":13}}
			for key_player in [false,true]:
				var context := {"key_player":key_player,"world_top_reputation":800}
				check(core.contract_chance(player,club,17,context)==ContractRenewal.stay_chance(player,club,coach,context),"Native contract retention equals reference")
			for needed in ["GK","CM",TransferMarket.POS_FLEX]:
				var a := RandomNumberGenerator.new()
				var z := RandomNumberGenerator.new()
				a.seed=55172
				z.seed=a.seed
				check(core.score_transfer(club,player,CoachTypes.transfers_of(coach),needed,z)==TransferMarket._score_player(club,coach,player,needed,a),"Native recruitment score equals reference")
				check(a.state==z.state,"Native recruitment retains RNG")

func _test_extremes(core: Variant) -> void:
	var fixtures_rng := RandomNumberGenerator.new()
	fixtures_rng.seed=129501
	for edge in ["min","max"]:
		var knobs := Config.default_values()
		for knob in Config.schema():
			knobs[knob.key] = knob[edge]
		Config.apply_values(knobs,false)
		core.set_knobs(Config.snapshot())
		for trial in 40:
			var home := Fixtures.squad(1,55+trial%30,fixtures_rng)
			var away := Fixtures.squad(2,70,fixtures_rng)
			if trial%4==0:
				home=home.slice(0,trial%9)
			if trial%5==0:
				away=away.slice(0,trial%10)
			var spec := {"home":{"club_id":1,"squad":home,"coach":Fixtures.coach(1,fixtures_rng)},"away":{"club_id":2,"squad":away,"coach":Fixtures.coach(2,fixtures_rng)},"allow_draw":false}
			var a := RandomNumberGenerator.new()
			var z := RandomNumberGenerator.new()
			a.seed=8155+trial
			z.seed=a.seed
			var expected := MatchEngine.simulate(spec.duplicate(true),a)
			var actual: Dictionary = core.simulate(spec.duplicate(true),z,Config.fingerprint())
			check(expected==actual,"Extreme knobs and depleted teams: "+edge+" "+str(trial))
			check(a.state==z.state,"Extreme match RNG equals reference")
			if expected!=actual:
				print(difference(expected,actual,"report"))
				return
	Config.reset_to_defaults(false)
	core.set_knobs(Config.snapshot())
	var pool := Fixtures.squad(1,70,fixtures_rng)+Fixtures.squad(2,80,fixtures_rng)
	pool[0].injury_rounds=3
	for professionalism in [1,10,20]:
		var coach := Fixtures.coach(3,fixtures_rng)
		coach.attributes.professionalism=professionalism
		var a := RandomNumberGenerator.new()
		var z := RandomNumberGenerator.new()
		a.seed=775
		z.seed=a.seed
		check(NationalTeams.select_squad(pool.duplicate(true),coach.duplicate(true),a)==core.national_roster(pool.duplicate(true),CoachTypes.primary_style_of(coach),CoachTypes.selection_uncertainty(coach)*18.0,z),"Native national 20-player call-up equals reference")
		check(a.state==z.state,"Native national call-up retains RNG")
	var clubs := []
	var divisions := []
	for group in 4:
		var members := []
		for j in 6:
			var club := {"club_id":group*6+j+1,"club_name":"Team "+str(group*6+j),"regular":0.6+j*0.01,"knockout":0.7-j*0.01}
			clubs.append(club)
			members.append(club)
		divisions.append({"clubs":members})
	for national in [false,true]:
		for scope in ["PER_DIVISION","OVERALL"]:
			for count in [8,14,16]:
				var unit := {"national":national,"rules":{"playoff_scope":scope}}
				var a := RandomNumberGenerator.new()
				var z := RandomNumberGenerator.new()
				a.seed=78151
				z.seed=a.seed
				var expected := SeasonPreview._simulate_playoff(unit,divisions,clubs,count,a)
				var actual: Array = core.preview_playoff(divisions,clubs,count,scope=="PER_DIVISION",national,z)
				check(expected==actual,"Native group and playoff Monte Carlo equals reference")
				check(a.state==z.state,"Native playoff preview retains RNG")

func _test_agents(core: Variant) -> void:
	var helper: Node = load("res://tests/game/test_transfer_market.gd").new()
	for trial in 28:
		var agents := []
		var fixture_rng := RandomNumberGenerator.new()
		fixture_rng.seed = 111+trial
		for nation in [1,2,3]:
			for position in PlayerTypes.build_squad_positions(fixture_rng):
				agents.append(helper._player(position,nation,300+trial*11,50+trial%20))
		var limit := 3 if trial%2 else -1
		helper._load_two_club_market(agents,limit,15,13)
		GameSession.units[0].clubs_by_id[2].country_id=2
		var club: Dictionary = GameSession.units[0].clubs_by_id[1]
		if trial % 2 == 0:
			club["club_elo"] = {"games": 20, "sporting_reputation": float(club.get("reputation", 500)) + 120.0}
		var coach: Dictionary = GameSession.get_club_coach(1)
		var squad := GameSession.get_club_players(1)
		var needed: String = PlayerTypes.POSITIONS[trial%PlayerTypes.POSITIONS.size()]
		var relaxed := trial%3==0
		if trial%4==0:
			needed=TransferMarket.POS_FLEX
		var index := TransferMarket._build_agent_index(GameSession.free_agents,700)
		check(index==core.agent_index(GameSession.free_agents,700),"Native free-agent index equals reference")
		index.native_reserves=TransferMarket._build_native_reserves(GameSession)
		var legal := {}
		for position in PlayerTypes.POSITIONS:
			legal[position]=TransferMarket._position_ok(position,needed,relaxed,squad)
		var indices: Array = index.all if needed==TransferMarket.POS_FLEX or relaxed else index.positions.get(needed,[])
		var context := TransferMarket._offer_context(squad)
		context.squad_ability=-1.0
		context.world_top_reputation=700
		context.free_agent=true
		var selection := {"club":club,"club_id":1,"context":context,"legal":legal,"reserves":index.native_reserves,"indices":indices,"skill":CoachTypes.transfers_of(coach),"negotiations":CoachTypes.negotiations_of(coach),"foreign_cap":false,"needed":needed}
		var a := RandomNumberGenerator.new()
		var z := RandomNumberGenerator.new()
		a.seed=77121+trial
		z.seed=a.seed
		var actual: int = core.choose_agent(GameSession.free_agents,index,selection,z)
		if actual>=0:
			TransferMarket._roll_contract_years(z,int(GameSession.free_agents[actual].age))
		var signed := TransferMarket._try_sign(GameSession,a,1,club,squad,needed,relaxed,false,index)
		var expected := int(index.consumed.keys()[0]) if signed else -1
		check(actual==expected,"Native full free-agent candidate scan equals reference")
		check(a.state==z.state,"Native full recruitment scan retains RNG")
		GameSession.clear()
	helper.free()

func _test_legacy_positions(core: Variant) -> void:
	var fixture_rng := RandomNumberGenerator.new()
	fixture_rng.seed=81502
	for position in ["DM","AM","W","","UNKNOWN"]:
		var home := Fixtures.squad(1,70,fixture_rng)
		var away := Fixtures.squad(2,65,fixture_rng)
		for player in home:
			if player.position=="CM" or player.position=="CB":
				player.position=position
				MatchRatings.invalidate(player)
		var spec := {"home":{"club_id":1,"squad":home,"coach":Fixtures.coach(1,fixture_rng)},"away":{"club_id":2,"squad":away,"coach":Fixtures.coach(2,fixture_rng)},"allow_draw":false}
		var a := RandomNumberGenerator.new()
		var z := RandomNumberGenerator.new()
		a.seed=8201
		z.seed=a.seed
		var expected := MatchEngine.simulate(spec.duplicate(true),a)
		var actual: Dictionary = core.simulate(spec.duplicate(true),z,Config.fingerprint())
		check(expected==actual,"Legacy position normalization equals reference: "+position)
		check(a.state==z.state,"Legacy position RNG equals reference")
