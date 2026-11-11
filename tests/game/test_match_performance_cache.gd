extends Node
const Config := preload("res://game/match_simulation_config.gd")
const Types := preload("res://game/match_types.gd")
const Condition := preload("res://game/player_condition.gd")
var passed := 0
var failed := 0
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ",message)
func reference_rest(player: Dictionary, played: bool) -> void:
	Condition.ensure_state(player)
	var condition := float(Condition.condition_of(player))
	var rate := Config.curve_attr(PlayerTypes.recovery_of(player),"recovery_share_1","recovery_share_10","recovery_share_20")
	if not played:
		rate *= Config.get_f("recovery_idle_factor")
	if Condition.is_injured(player):
		rate *= 0.5
	if int(player.get("age",25))>=33:
		rate *= 0.92
	var regain := Config.get_f("recovery_floor")+(float(Types.CONDITION_MAX)-condition)*rate
	player.condition = Types.clamp_condition(int(round(condition+regain)))
	var injury := int(player.get("injury_rounds",0))
	if injury>0:
		injury -= 1
		player.injury_rounds = injury
		if injury<=0:
			player.injury_grade = ""
	var morale := float(Condition.morale_of(player))
	if absf(morale-float(Condition.BASELINE_MORALE))>0.5:
		var step := Types.MORALE_DRIFT*(float(Condition.BASELINE_MORALE)-morale)
		player.morale = Types.clamp_morale(int(round(morale+step)))
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	Config.config_path = "user://tests/performance-cache.json"
	for overlay in [{},{"condition_play_floor":0.43,"condition_select_floor":0.28,"lineup_rest_below":67,"rotation_fatigue_weight":2.1,"recovery_idle_factor":1.6},{"rotation_fatigue_weight":0,"recovery_floor":0}]:
		Config.apply_values(overlay,false)
		for c in range(-5,106):
			var clamped := float(Types.clamp_condition(c))
			var expected := Config.get_f("condition_play_floor")+(1-Config.get_f("condition_play_floor"))*(clamped/100.0)
			check(Config.condition_play_mult(c)==expected,"Cached on-pitch multiplier keeps exact double precision")
			var floor_v := Config.get_f("condition_select_floor")
			var rest := Config.get_f("lineup_rest_below")
			var linear := floor_v+(1-floor_v)*(clamped/100.0)
			expected = pow(linear if clamped>=rest else linear*(clamped/rest),Config.get_f("rotation_fatigue_weight"))
			check(Config.condition_select_mult(c)==expected,"Selection cache follows current config, including zero influence")
		for attr in range(-2,24):
			for prefix in ["recovery_share_","condition_after_stamina_","fresh_after_stamina_"]:
				check(Config.curve_attr(attr,prefix+"1",prefix+"10",prefix+"20")==Config.lerp_three(attr,Config.get_f(prefix+"1"),Config.get_f(prefix+"10"),Config.get_f(prefix+"20")),"Attribute table preserves the original interpolation")
		for c in [0,55,99,100,110]:
			for injury in [0,1,4]:
				for morale in [0,50,55,56,60,100]:
					for age in [20,34]:
						for played in [false,true]:
							var player := {"condition":c,"morale":morale,"injury_rounds":injury,"injury_grade":"minor","age":age,"attributes":{"physical":{"recovery":7}}}
							var expected_player := player.duplicate(true)
							reference_rest(expected_player,played)
							Condition.advance_round(player,played)
							check(player==expected_player,"Recovery fast path retains healing, morale and legacy clamps")
	Config.apply_values({"condition_play_floor":0.54,"recovery_share_10":0.42},true)
	Config.condition_play_mult(50)
	Config.curve_attr(10,"recovery_share_1","recovery_share_10","recovery_share_20")
	Config.unload()
	check(Config.condition_play_mult(50)==0.77,"Reload clears the condition table")
	check(Config.curve_attr(10,"recovery_share_1","recovery_share_10","recovery_share_20")==0.42,"Reload clears attribute tables")
	DirAccess.remove_absolute(Config.config_path)
	Config.config_path = Config.DEFAULT_CONFIG_PATH
	Config.reset_to_defaults(false)
	print("=== Match performance cache: %d passed, %d failed ===" % [passed,failed])
	get_tree().quit(1 if failed else 0)
