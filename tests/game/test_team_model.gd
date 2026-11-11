extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0
func check(ok: bool,label: String) -> void:
	if ok: passed+=1
	else: failed+=1; print("FAIL: ",label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	check(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"),"isolated userdata")
	var rng := RandomNumberGenerator.new()
	rng.seed=405
	for seed_value in 500:
		rng.seed=seed_value
		var slots := PlayerTypes.build_squad_positions(rng)
		var squad: Array=[]
		for pos in slots: squad.append({"position":pos})
		check(PlayerTypes.is_squad_shape_legal(squad),"twenty-player generation obeys all role limits")
	for pair in [["FB","CB"],["WM","CM"],["WF","ST"]]:
		check(PlayerTypes.normalize_position(pair[0])==pair[1],"legacy flank role migrates to its line")
	var source := Fixtures.squad(1,65,rng,0)
	var three_keepers: Array=source.duplicate(true)
	three_keepers[-1]=three_keepers[0].duplicate(true)
	three_keepers[-1].id=1020
	var all_twenty := MatchEngine._select_lineup({"squad":three_keepers,"coach":{"style":"attacking"}},rng)
	check(all_twenty.starters.size()+all_twenty.bench.size()==20,"the third goalkeeper also belongs to the twenty-player matchday roster")
	check(all_twenty.bench.filter(func(p):return p.position=="GK").size()==2,"two reserve keepers remain available when the roster has three")
	for i in 5:
		var player: Dictionary=source[[0,2,9,15,16][i]].duplicate(true)
		player.id=2001+i
		source.append(player)
	var preserved := {}
	for player in source: preserved[int(player.id)]=player.duplicate(true)
	GameSession.players_by_club={1:source}
	GameSession.reserve_players_by_club={}
	GameSession.youth_players_by_club={}
	GameSession.free_agents=[]
	GameSession._rng.seed=144
	var state := GameSession._rng.state
	GameSession._migrate_twenty_player_rosters()
	check(PlayerTypes.is_squad_shape_legal(GameSession.players_by_club[1]),"legacy club roster shrinks to legal twenty")
	check(GameSession.reserve_players_by_club[1].size()==5 and GameSession.reserve_players_by_club[1].all(func(p):return bool(p.get("is_reserve",false))),"five surplus players go to reserve with reserve status")
	var seen := {}
	for player in GameSession.players_by_club[1]+GameSession.reserve_players_by_club[1]:
		check(not seen.has(int(player.id)) and player.attributes==preserved[int(player.id)].attributes and player.name==preserved[int(player.id)].name and player.get("characters",[])==preserved[int(player.id)].get("characters",[]) and player.get("season_stats",{})==preserved[int(player.id)].get("season_stats",{}),"migration preserves every player, attributes and history")
		seen[int(player.id)]=true
	check(seen.size()==25 and GameSession._rng.state==state,"migration neither deletes players nor consumes random numbers")
	GameSession._migrate_twenty_player_rosters()
	check(GameSession.reserve_players_by_club[1].size()==5,"migration idempotent")
	var old_ids: Array=preserved.keys()
	GameSession.national_teams={1:{"squad_ids":old_ids.duplicate(),"withdrawn_ids":[old_ids[0]],"coach":{"style":"attacking"}}}
	GameSession._national_player_index.clear()
	NationalTeams.compact_registrations(GameSession)
	var ids: Array=GameSession.national_teams[1].squad_ids
	check(ids.size()==20 and ids.all(func(id):return old_ids.has(id)),"old national registration shrinks without fresh call-ups")
	var index := NationalTeams.index_players(GameSession)
	check(PlayerTypes.is_squad_shape_legal(ids.map(func(id):return index[id])),"national registration keeps role coverage")
	check(GameSession._rng.state==state,"national migration consumes no match randomness")
	var coach := {"style":"attacking","attributes":{"professionalism":20}}
	var candidates: Array=source.filter(func(p):return p.position=="ST")
	var selected := NationalTeams.select_squad(candidates,coach,rng)
	check(selected.size()<=5 and selected.size()<20,"short country pool remains incomplete and cannot fill all roles with strikers")
	var spec := {"club_id":1,"squad":Fixtures.squad(1,65,rng,0),"coach":coach}
	var lineup := MatchEngine._select_lineup(spec,rng)
	var team := MatchEngine._build_team("home",spec,lineup,0,0,rng,load("res://game/match_simulation_config.gd").snapshot())
	var opposition := MatchEngine._build_team("away",spec,lineup,0,0,rng,load("res://game/match_simulation_config.gd").snapshot())
	var scorer: Dictionary=team.on_field[7]
	var first: Dictionary=team.on_field[4]
	var second: Dictionary=team.on_field[1]
	var ctx := {"events":[]}
	MatchEngine._score_goal(team,opposition,scorer,first,ctx,5,"GOAL",second)
	check(ctx.events[0].assist_ids==[first.player.id,second.player.id],"goal stores two actual assistants")
	check(first.entry.assists==1 and second.entry.assists==1 and scorer.entry.goals==1,"both assistants credited exactly once")
	MatchEngine._score_goal(team,opposition,scorer,first,ctx,6,"GOAL",first)
	check(ctx.events[1].assist_ids.size()==1 and first.entry.assists==2,"duplicate assistant excluded")
	MatchEngine._score_goal(team,opposition,scorer,scorer,ctx,7,"GOAL",second)
	check(ctx.events[2].assist_ids==[second.player.id],"scorer cannot assist himself")
	MatchEngine._score_goal(team,opposition,team.on_field[0],{},ctx,8,"GOAL")
	check(team.on_field[0].entry.goals==1,"goalkeeper can score")
	print("=== Team model: ",passed," passed, ",failed," failed ===")
	get_tree().quit(1 if failed else 0)
