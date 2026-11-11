extends Node
const Planner = preload("res://game/transfer_planner.gd")
const Job = preload("res://game/transfer_market_job.gd")
const Attraction = preload("res://game/club_attraction_config.gd")
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok:passed+=1
	else:failed+=1;print("FAIL: ",label)
func _ready() -> void:call_deferred("run")
func attributes(pos: String,skill: int) -> Dictionary:
	var result := {}
	for group in PlayerTypes.attribute_groups_for_position(pos):
		result[group]={}
		for key in PlayerTypes.attribute_keys_for_group(group):result[group][key]=skill
	return result
func squad(cid: int) -> Array:
	var result := []
	var positions := ["GK","GK","CB","CB","CB","CB","CB","CB","CB","CB","CM","CM","CM","CM","CM","CM","ST","ST","ST","ST"]
	for i in positions.size():result.append({"id":cid*100+i+1,"club_id":cid,"name":"P%d" % (cid*100+i+1),"position":positions[i],"age":25,"nationality_country_id":1,"current_ability":50,"potential_ability":90,"player_model_version":2,"reputation":400,"attributes":attributes(positions[i],10),"characters":["PROFESSIONAL"],"condition":100,"morale":55,"contract_years":3,"contract_status":"club","wage":2000,"value":50000,"value_pricing_version":2})
	return result
func fixture() -> Dictionary:
	var clubs := {};var pools := {};var coaches := {};var budgets := {}
	for id in [1,2,3]:
		clubs[id]={"id":id,"name":"Club%d" % id,"country_id":1,"reputation":700 if id==1 else 500}
		pools[id]=squad(id);coaches[id]={"id":id,"name":"Coach","attributes":{"transfers":15,"negotiations":12,"tactics":12,"professionalism":15},"style":"attacking"};budgets[id]=50000000
	return {"version":15,"season_number":2,"season_day":-5,"season_finished":false,"history_head":0,"units":[{"id":1,"clubs_by_id":clubs,"rules":{"foreign_players_limit":8},"matches":[],"divisions":[]}],"players_by_club":pools,"coaches_by_club":coaches,"club_budgets":budgets,"free_agents":[],"reserve_players_by_club":{},"youth_players_by_club":{},"transfer_log":[],"next_player_id":1000,"wages_paid_for_season":1}
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	SaveStore.database_path_override="user://tests/planner-tests.db"
	Attraction.config_path="user://tests/planner-attraction.json";Attraction.apply_values(Attraction.defaults(),false)
	test_shortlist()
	test_role_plan()
	test_competing_free_offers()
	test_replay()
	GameSession.clear();SaveStore.database_path_override=""
	print("Transfer planner: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)
func test_shortlist() -> void:
	var generator := RandomNumberGenerator.new();generator.seed=121126
	var native: Variant=NativeSimulation.core()
	check(native!=null and native.has_method("planner_shortlist"),"bulk C++ shortlist is installed")
	for trial in 100:
		var candidates := []
		for i in 150:candidates.append({"id":i+1,"owner":generator.randi_range(0,6),"nation":generator.randi_range(1,3),"fee":generator.randi_range(0,2000000),"quality":generator.randf_range(20,90),"pa":generator.randi_range(40,100),"age":generator.randi_range(18,37)})
		var need := {"allow_foreign":trial%2==0,"succession":trial%3==0,"baseline":60.0,"minimum":62.0,"out_quality":45.0,"ca":70,"noise_seed":121126+trial}
		var a := RandomNumberGenerator.new();a.seed=123
		var b := RandomNumberGenerator.new();b.seed=123
		var before := a.state
		var reference := Planner.shortlist_reference(candidates,need,1,1,1000000,[1,4,7],trial%20,a,8)
		var actual: Array=native.planner_shortlist(candidates,need,1,1,1000000,[1,4,7],trial%20,b,8)
		check(actual==reference,"native/reference shortlist equality")
		need["_native_index"]=native.planner_index(candidates)
		check(native.planner_shortlist(candidates,need,1,1,1000000,[1,4,7],trial%20,b,8)==reference,"packed shared index retains exact ranking")
		check(a.state==b.state and a.state==before,"cache construction does not consume simulation RNG")
	var candidates := [{"id":1,"owner":2,"nation":1,"fee":100,"quality":30.0,"pa":95,"age":25},{"id":2,"owner":2,"nation":1,"fee":100,"quality":80.0,"pa":80,"age":25}]
	var need := {"allow_foreign":true,"succession":false,"baseline":60.0,"minimum":62.0,"ca":60}
	check(Planner.shortlist_reference(candidates,need,1,1,1000,[],20,RandomNumberGenerator.new(),8)==[1],"a nominal star with poor role skills cannot outrank useful attributes")
func test_role_plan() -> void:
	var payload := fixture()
	for player in payload.players_by_club[1]:
		if player.position=="CB":player.attributes=attributes("CB",6)
	check(GameSession.apply_save_payload(payload).success,"planning fixture loads")
	var rng := RandomNumberGenerator.new();rng.seed=811
	var planner := Planner.new(TransferMarket,GameSession,GameSession._collect_session_clubs(),rng)
	var needs: Array=planner.needs(1)
	check(needs.size()==4 and needs[0].position=="CB","weakest starting role is evaluated across all positions")
	check(float(needs[0].baseline)<float(needs[-1].baseline),"priority is based on starting-role attributes")
	for need in needs:check(int(need.outgoing.club_id)==1,"outgoing player belongs to this club")
	var info := TransferMarket._squad_market_info(GameSession,1,GameSession.get_club_players(1))
	for player in GameSession.get_club_players(1):check(TransferMarket._seller_can_spare_info(info,player)==TransferMarket._seller_can_spare(GameSession,1,GameSession.get_club_players(1),player),"indexed seller protection equals canonical rule")
	var before := float(needs[0].baseline)
	for day in range(-5,0):
		GameSession.season_day=day
		TransferMarket.run_day(GameSession,rng)
	var defenders := []
	for player in GameSession.get_club_players(1):
		if player.position=="CB":defenders.append(planner.quality(player))
	defenders.sort();defenders.reverse()
	check(float(defenders[0])+float(defenders[1])+float(defenders[2])>before*3.0,"successful recruitment improves the actual three starting defenders")
	for club in GameSession._collect_session_clubs().values():
		check(int(club.get("transfer_plan",{}).get("purchases",0))<=Planner.MAX_PURCHASES,"optional upgrades stay bounded per window")
func test_competing_free_offers() -> void:
	var payload := fixture();payload.units[0].clubs_by_id.erase(3);payload.players_by_club.erase(3);payload.coaches_by_club.erase(3);payload.club_budgets.erase(3)
	payload.units[0].clubs_by_id[1].reputation=700;payload.units[0].clubs_by_id[2].reputation=710
	for cid in [1,2]:
		payload.club_budgets[cid]=0
		payload.players_by_club[cid].remove_at(2)
		for player in payload.players_by_club[cid]:
			player.current_ability=75;player.attributes=attributes(player.position,15)
			if player.position=="ST":player.current_ability=50 if cid==1 else 85;player.attributes=attributes("ST",10 if cid==1 else 17)
	var star: Dictionary=squad(9)[16];star.id=999;star.club_id=0;star.current_ability=70;star.attributes=attributes("ST",14);star.reputation=400;star.contract_status="free_agent"
	payload.free_agents=[star]
	check(GameSession.apply_save_payload(payload).success,"competing-offers fixture loads")
	var rng := RandomNumberGenerator.new();rng.seed=153
	GameSession.season_day=-1;TransferMarket.run_day(GameSession,rng)
	check(GameSession.get_club_players(1).any(func(q):return int(q.id)==999),"first-team role wins against a slightly more prestigious reserve offer")
	check(not GameSession.get_club_players(2).any(func(q):return int(q.id)==999),"one free agent cannot join two clubs")
func digest() -> String:
	var players := []
	for id in [1,2,3]:
		for player in GameSession.get_club_players(id):players.append([id,player.id,player.get("wage",0),player.get("contract_years",0)])
	return str([players,GameSession.club_budgets,GameSession.transfer_log,GameSession._rng.state]).sha256_text()
func window(payload: Dictionary,sliced: bool,resume: bool) -> String:
	assert(GameSession.apply_save_payload(payload.duplicate(true)).success)
	GameSession._rng.seed=91827
	for day in range(-5,0):
		GameSession.season_day=day
		if sliced:
			var job := Job.new(TransferMarket,GameSession,GameSession._rng)
			while not job.step():pass
		else:TransferMarket.run_day(GameSession,GameSession._rng)
		if resume and day==-3:
			check(GameSession.save_game("planner_resume").success,"mid-window save")
			check(GameSession.load_game("planner_resume").success,"mid-window reload")
	for id in [1,2,3]:check(PlayerTypes.is_squad_shape_legal(GameSession.get_club_players(id)),"window preserves 20-player positional structure")
	return digest()
func test_replay() -> void:
	var payload := fixture()
	for player in payload.players_by_club[2]:player.attributes=attributes(player.position,15);player.current_ability=75
	for pos in PlayerTypes.POSITIONS:
		for i in 10:
			var player: Dictionary=squad(10+i)[0];player.id=1000+payload.free_agents.size();player.position=pos;player.club_id=0;player.attributes=attributes(pos,13);player.current_ability=65;player.contract_status="free_agent";payload.free_agents.append(player)
	var sync := window(payload,false,false)
	check(sync==window(payload,true,false),"sync and sliced market have identical results and RNG")
	check(sync==window(payload,true,true),"mid-window save/load preserves decisions despite rebuilding transient caches")
