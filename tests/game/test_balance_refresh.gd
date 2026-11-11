extends Node
const Config = preload("res://game/match_simulation_config.gd")
const Rating = preload("res://game/national_rating.gd")
var passed := 0
var failed := 0
func check(ok: bool, label: String) -> void:
	if ok: passed+=1
	else: failed+=1;print("FAIL: ",label)
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	Config.config_path="user://tests/balance-refresh/config.json"
	Config.reset_to_defaults(false)
	for stamina in [1,10,15,20]:
		var outcomes := []
		for native in [false,true]:
			NativeSimulation.enabled=native
			var player := {"id":stamina,"age":25,"position":"CM","condition":100,"attributes":{"physical":{"stamina":stamina,"recovery":10}}}
			PlayerCondition.apply_match_load(player,50,1.0)
			outcomes.append(player.condition)
		check(outcomes[0]==outcomes[1],"stamina native/reference parity %d" % stamina)
		var expected := 30 if stamina==1 else 60 if stamina==10 else 71 if stamina==15 else 82
		check(outcomes[0]==expected,"visible full-match stamina effect %d" % stamina)
	check(Config.curve_attr(20,"fresh_after_stamina_1","fresh_after_stamina_10","fresh_after_stamina_20")-Config.curve_attr(10,"fresh_after_stamina_1","fresh_after_stamina_10","fresh_after_stamina_20")>=0.19,"live freshness differs by twenty percentage points")
	DirAccess.make_dir_recursive_absolute(Config.config_path.get_base_dir())
	FileAccess.open(Config.config_path,FileAccess.WRITE).store_string(JSON.stringify({"version":7,"values":{"shot_conversion_base":0.4,"condition_after_stamina_20":68,"fresh_after_stamina_20":0.73}}))
	Config.unload()
	check(Config.get_f("condition_after_stamina_20")==82 and Config.get_f("fresh_after_stamina_20")==0.92,"old stamina settings migrate")
	check(Config.get_f("shot_conversion_base")==0.4,"migration preserves scoring settings")
	Config.apply_values({"condition_after_stamina_20":90},true);Config.unload()
	check(Config.get_f("condition_after_stamina_20")==90,"manual version8 stamina overrides survive reload")
	var rng := RandomNumberGenerator.new();rng.seed=111126
	var total := 0
	for trajectory in 300:
		var up := {"youth_talent":80};var down := {"youth_talent":80}
		var a := {};var b := {}
		for edition in 68:
			var evidence := rng.randfn(0,0.9)
			Rating.advance_talent(up,a,evidence,edition*2+2)
			Rating.advance_talent(down,b,-evidence,edition*2+2)
		check(up.youth_talent+down.youth_talent==160,"mirrored fair evidence has no directional bias")
		total+=int(up.youth_talent)+int(down.youth_talent)-160
	check(total==0,"fair trajectory mean drift is zero")
	var team := {"country":{"reputation":800,"youth_talent":85},"rating":{"elo":2500,"initial_elo":1760,"trend":-5.5}}
	Rating.ensure_team(team,137)
	check(team.rating.talent_elo==2500 and team.rating.trend==0,"biased old trend resets without altering talent or Elo")
	check(team.country.youth_talent==85,"migration does not rewrite country talent")
	team.rating.trend=2.0;Rating.ensure_team(team,138)
	check(team.rating.trend==2.0,"reference migration runs once")
	Config.reset_to_defaults(false);NativeSimulation.enabled=true
	print("Balance refresh: %d passed, %d failed" % [passed,failed])
	get_tree().quit(0 if failed==0 else 1)
