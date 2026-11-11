extends RefCounted
const Tactics := preload("res://game/tactic_types.gd")
const Selector := preload("res://game/lineup_selector.gd")
const Types := preload("res://game/match_types.gd")
static func select_lineup(spec: Dictionary,_opponent: Dictionary,rng: RandomNumberGenerator) -> Dictionary:
	var coach: Dictionary=spec.get("coach",{})
	var plan := Tactics.pick_match_plan(coach,rng)
	var lineup := Selector.build(spec.get("squad",[]),spec.get("youth",[]),coach,plan,rng,false)
	lineup.plan_source="fixed"
	lineup.plan_reason="fixed_322"
	return Selector.finish_bench(lineup)
static func review(_team: Dictionary,_opponent: Dictionary,_minute: int) -> Dictionary: return {}
static func profile(mentality: String,_mode: String,_conserve: bool) -> Dictionary:
	var result: Dictionary=Types.style_profile(mentality).duplicate()
	var influence: float=load("res://game/match_simulation_config.gd").get_f("tactics_influence")
	for key in result: result[key]=1.0+(float(result[key])-1.0)*influence
	return result
