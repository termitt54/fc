extends Node
const Config = preload("res://game/match_simulation_config.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	Config.reset_to_defaults(false)
	if args.size()>=6:
		Config.config_path=args[5]
		Config.unload()
		Config.snapshot()
	if args.size()>=5:
		var calibration := NativeSimulation._configuration()
		calibration.action_constants["MIDFIELD_ATTACK_DEPTH_BASE"]=float(args[2])
		calibration.action_constants["MIDFIELD_ATTACK_DEPTH_SPAN"]=float(args[3])
		calibration.action_constants["DEFENDER_ATTACK_RUN_SPAN"]=float(args[4])
		NativeSimulation.core().configure(calibration)
	var result := {"backend":NativeSimulation.backend(),"matches":0,"goals":0,"positions":{},"subs":0,"assisted":0,"two_assists":0,"leagues":{}}
	var clock := Time.get_ticks_usec()
	for pair in fixtures:
		var rng := RandomNumberGenerator.new()
		rng.seed=int(pair.seed)
		var report := MatchEngine.simulate({"home":pair.home,"away":pair.away,"neutral":true,"allow_draw":true,"discipline":{"enabled":true}},rng)
		result.matches+=1
		var goals := int(report.home_goals)+int(report.away_goals)
		result.goals+=goals
		var league: Dictionary = result.leagues.get(pair.league,{"matches":0,"goals":0,"positions":{}})
		league.matches+=1;league.goals+=goals
		for side in ["home_team","away_team"]:
			for player in report[side].players:
				var pos := str(player.slot)
				result.positions[pos]=int(result.positions.get(pos,0))+int(player.get("goals",0))
				league.positions[pos]=int(league.positions.get(pos,0))+int(player.get("goals",0))
		for event in report.events:
			result.subs+=int(event.type=="SUB")
			if event.type in ["GOAL","PENALTY_GOAL"]:
				result.assisted+=int(event.get("assist_ids",[]).size()>0)
				result.two_assists+=int(event.get("assist_ids",[]).size()==2)
		result.leagues[pair.league]=league
	result.elapsed_ms=(Time.get_ticks_usec()-clock)/1000.0
	FileAccess.open(args[1],FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	get_tree().quit()
