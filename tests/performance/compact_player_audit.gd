extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var output := {}
func _ready() -> void:
	call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	var config := load("res://game/match_simulation_config.gd")
	config.config_path = "user://tests/compact-audit.json"
	config.apply_values({}, false)
	var rng := RandomNumberGenerator.new()
	rng.seed = 816231
	var start := Time.get_ticks_usec()
	var squads := []
	for i in 128:
		squads.append(Fixtures.squad(i + 1, 65, rng, 8))
	output.generation_ms = (Time.get_ticks_usec() - start) / 1000.0
	var clean := squads.duplicate(true)
	for squad in clean:
		MatchRatings.strip_cache(squad)
	output.player_count = 128 * 18
	output.player_bytes = var_to_bytes(clean).size()
	output.scenarios = []
	for pair in [[65,65],[85,75],[85,50]]:
		rng.seed = 45878
		var a: Array = Fixtures.squad(1, pair[0], rng, 0)
		var b: Array = Fixtures.squad(2, pair[1], rng, 0)
		# Neutral character isolates the skill model; older builds use no traits.
		for player in a + b:
			player.characters = ["BALANCED"]
			player.personality = {}
			MatchRatings.invalidate(player)
		var coach := {"attributes":{"tactics":12,"motivation":10},"primary_style":"control","backup_style":"control","primary_formation":"2-3-2","backup_formation":"2-3-2"}
		var cfg := {"home":{"club_id":1,"squad":a,"coach":coach},"away":{"club_id":2,"squad":b,"coach":coach},"neutral":true,"allow_draw":true}
		var wins := 0
		var draws := 0
		var goals := 0
		var subs := 0
		start = Time.get_ticks_usec()
		for i in 1000:
			rng.seed = 773000 + i
			var result: Dictionary = MatchEngine.simulate(cfg, rng)
			wins += int(result.home_goals > result.away_goals)
			draws += int(result.home_goals == result.away_goals)
			goals += result.home_goals + result.away_goals
			for event in result.events:
				subs += int(event.type == "SUB")
		output.scenarios.append({"ca":pair,"matches":1000,"wins":wins,"draws":draws,"losses":1000-wins-draws,"goals_per_match":goals/1000.0,"subs_per_team":subs/2000.0,"ms":(Time.get_ticks_usec()-start)/1000.0})
	output.backend = NativeSimulation.backend()
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print(JSON.stringify(output))
	get_tree().quit()
