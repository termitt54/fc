extends RefCounted
## Bounded coaching decisions: two familiar plans, current match facts only.
const Tactics := preload("res://game/tactic_types.gd")
const Selector := preload("res://game/lineup_selector.gd")
const Types := preload("res://game/match_types.gd")
const Condition := preload("res://game/player_condition.gd")

static func select_lineup(spec: Dictionary, opponent: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var coach: Dictionary = spec.get("coach", {})
	var primary := Tactics.pick_match_plan(coach, rng)
	var first := Selector.build(spec.get("squad", []), spec.get("youth", []), coach, primary, rng, false)
	first["plan_source"] = "primary"
	first["plan_reason"] = "preferred_plan"
	if coach.is_empty():
		return Selector.finish_bench(first)
	var backup := {"style": str(coach["backup_style"]), "formation": str(coach["backup_formation"])}
	var second := Selector.build(spec.get("squad", []), spec.get("youth", []), coach, backup, rng, false)
	var opposing_profile := _opponent_profile(opponent)
	var first_score := _plan_score(first, opposing_profile)
	var second_score := _plan_score(second, opposing_profile)
	var skill := _skill(coach)
	# Better coaches recognise smaller advantages; familiarity prevents oscillation.
	var threshold := 8.0 - 0.25 * skill
	var chosen := second if second_score > first_score + threshold else first
	chosen["plan_source"] = "backup" if chosen == second else "primary"
	chosen["plan_reason"] = "squad_and_opponent" if chosen == second else "preferred_plan"
	chosen["plan_scores"] = {"primary": first_score, "backup": second_score, "threshold": threshold}
	return Selector.finish_bench(chosen)

static func _plan_score(lineup: Dictionary, opposing_profile: Dictionary) -> float:
	var total := 0.0
	var style := str(lineup["style"])
	for row in lineup["starters"]:
		total += float(row["selection_score"])
	# Divide by eight even for an incomplete side: empty positions are not free.
	return total / 8.0 + _context_adjustment(style, opposing_profile)

static func _opponent_adjustment(style: String, opponent: Dictionary) -> float:
	return _context_adjustment(style, _opponent_profile(opponent))

static func _opponent_profile(opponent: Dictionary) -> Dictionary:
	var coach: Dictionary = opponent.get("coach", {})
	var opposing_style := str(coach.get("primary_style", "control"))
	var pressure := 0.0
	var pace := 0.0
	var count := 0
	for player in opponent.get("squad", []):
		if typeof(player) != TYPE_DICTIONARY or not Condition.is_available(player):
			continue
		var ratings := MatchRatings.of(player)
		pressure += float(ratings.get("press", 0.5))
		pace += float(ratings.get("pace", 0.5))
		count += 1
	if count == 0:
		return {}
	pressure /= count
	pace /= count
	return {"style": opposing_style, "pressure": pressure, "pace": pace}

static func _context_adjustment(style: String, opposing_profile: Dictionary) -> float:
	if opposing_profile.is_empty():
		return 0.0
	var opposing_style := str(opposing_profile["style"])
	var pressure := float(opposing_profile["pressure"])
	var pace := float(opposing_profile["pace"])
	# Small preparation hints, never automatic victory bonuses in the engine.
	var value := 0.0
	if style == "counter" and opposing_style in ["pressing", "vertical"]:
		value += 2.0
	if style == "tiki_taka":
		value -= 5.0 * maxf(pressure - 0.5, 0.0)
	if style == "kick_rush":
		value += 5.0 * maxf(pressure - 0.5, 0.0)
	if style == "pressing":
		value -= 4.0 * maxf(pace - 0.5, 0.0)
	return value

static func _skill(coach: Dictionary) -> int:
	var attributes: Variant = coach.get("attributes", {})
	if typeof(attributes) != TYPE_DICTIONARY:
		return 10
	return clampi(int(attributes.get("tactics", 10)), 1, 20)

static func review(team: Dictionary, opponent: Dictionary, minute: int) -> Dictionary:
	var skill := int(team.get("tactics", 10))
	var interval := 15 if skill <= 6 else (10 if skill <= 13 else 5)
	if minute < 15 or minute - int(team.get("last_review", 0)) < interval:
		return {}
	team["last_review"] = minute
	var difference := int(team["goals"]) - int(opponent["goals"])
	var mode := "normal"
	if int(team["men_down"]) > int(opponent["men_down"]) and not (difference < 0 and minute >= 40):
		mode = "compact"
	elif difference < 0 and minute >= (25 if skill >= 14 else 35):
		mode = "chase"
	elif difference > 0 and minute >= (35 if skill >= 14 else 40):
		mode = "protect"
	var fresh := 0.0
	var count := (team["on_field"] as Array).size()
	for unit in team["on_field"]:
		fresh += float(unit["fresh"])
	var conserve := count > 0 and fresh / count < 0.80 and mode != "chase" and skill >= 7
	var style := str(team["style"])
	var alternate := str(team.get("backup_style", style))
	if style == alternate:
		alternate = str(team.get("primary_style", style))
	# During play only change style if it fits the unchanged formation and players.
	if Tactics.is_compatible(alternate, str(team["formation"])) and minute - int(team.get("last_style_change", -20)) >= 15:
		var gain := 0.0
		for unit in team["on_field"]:
			if str(unit["slot"]) != "GK":
				gain += 20.0 * (Selector._style_rating(unit["ratings"], alternate) \
					- Selector._style_rating(unit["ratings"], style)) * float(unit["fit"]) * float(unit["fresh"])
		gain /= maxi(count, 1)
		var current_profile := Types.style_profile(style)
		var alternative_profile := Types.style_profile(alternate)
		if mode == "chase":
			gain += 12.0 * (float(alternative_profile["tempo"]) - float(current_profile["tempo"]))
		elif mode in ["protect", "compact"]:
			gain += 12.0 * (float(current_profile["concede"]) - float(alternative_profile["concede"]))
		if gain > 8.0 - 0.25 * skill:
			style = alternate
			team["last_style_change"] = minute
	if mode == str(team.get("approach", "normal")) and conserve == bool(team.get("conserve", false)) and style == str(team["style"]):
		return {}
	return {"minute": minute, "reason": mode if not conserve else "fatigue_management",
		"style": style, "approach": mode, "conserve": conserve}

static func profile(style: String, mode: String, conserve: bool) -> Dictionary:
	var result := Types.style_profile(style).duplicate()
	var modifiers := {}
	if mode == "chase":
		modifiers = {"tempo": 1.15, "concede": 1.12, "intensity": 1.12}
	elif mode == "protect":
		modifiers = {"tempo": 0.86, "concede": 0.90, "intensity": 0.90}
	elif mode == "compact":
		modifiers = {"tempo": 0.82, "concede": 0.90, "intensity": 0.93}
	for key in modifiers:
		result[key] = float(result[key]) * float(modifiers[key])
	if conserve:
		result["intensity"] = float(result["intensity"]) * 0.90
	return result
