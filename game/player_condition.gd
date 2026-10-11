class_name PlayerCondition
extends RefCounted
## Physical condition, morale, injuries and suspensions.
## One matchday equals one round: load is paid after a match, regained per round
## at a speed driven by the hidden "Восстановление" attribute.


const MatchTypesScript := preload("res://game/match_types.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")

const BASELINE_MORALE := 55


static func ensure_state(player: Dictionary) -> void:
	if not player.has("condition"):
		player["condition"] = MatchTypesScript.CONDITION_START
	if not player.has("morale"):
		player["morale"] = MatchTypesScript.MORALE_DEFAULT
	if not player.has("injury_rounds"):
		player["injury_rounds"] = 0
	if not player.has("injury_grade"):
		player["injury_grade"] = ""
	if not player.has("suspension_matches"):
		player["suspension_matches"] = 0
	if not player.has("yellow_running"):
		player["yellow_running"] = 0


static func condition_of(player: Dictionary) -> int:
	return MatchTypesScript.clamp_condition(int(player.get("condition", MatchTypesScript.CONDITION_START)))


static func morale_of(player: Dictionary) -> int:
	return MatchTypesScript.clamp_morale(int(player.get("morale", MatchTypesScript.MORALE_DEFAULT)))


static func is_injured(player: Dictionary) -> bool:
	return int(player.get("injury_rounds", 0)) > 0


static func is_suspended(player: Dictionary) -> bool:
	return int(player.get("suspension_matches", 0)) > 0


static func is_available(player: Dictionary) -> bool:
	return not is_injured(player) and not is_suspended(player)


static func assign_injury(player: Dictionary, grade: String, rounds: int) -> void:
	if rounds < 1:
		return
	if rounds <= int(player.get("injury_rounds", 0)):
		return
	player["injury_rounds"] = rounds
	player["injury_grade"] = grade


static func add_suspension(player: Dictionary, matches: int) -> void:
	if matches < 1:
		return
	player["suspension_matches"] = int(player.get("suspension_matches", 0)) + matches


static func add_yellow(player: Dictionary, count: int = 1) -> int:
	var total := int(player.get("yellow_running", 0)) + maxi(count, 0)
	player["yellow_running"] = total
	return total


static func reset_yellows(player: Dictionary) -> void:
	player["yellow_running"] = 0


static func adjust_morale(player: Dictionary, delta: float) -> void:
	var next := float(morale_of(player)) + delta
	player["morale"] = MatchTypesScript.clamp_morale(int(round(next)))


## Condition burnt by playing. Intensity comes from the team's style.
static func apply_match_load(player: Dictionary, minutes: int, intensity: float) -> void:
	if minutes < 1:
		return
	var ratings := MatchRatings.of(player)
	var remaining := MatchSimConfigScript.curve_attr(
		PlayerTypes.stamina_of(player),
		"condition_after_stamina_1",
		"condition_after_stamina_10",
		"condition_after_stamina_20"
	)
	var base_cost := float(MatchTypesScript.CONDITION_MAX) - remaining
	var share := clampf(float(minutes) / float(MatchTypesScript.REGULAR_MINUTES), 0.0, 1.6)
	var age_penalty := 1.0 + 0.012 * float(maxi(int(player.get("age", 25)) - 31, 0))
	var cost := base_cost * share * intensity * age_penalty
	if bool(ratings.get("professional", false)):
		cost *= 0.94
	player["condition"] = MatchTypesScript.clamp_condition(
		int(round(float(condition_of(player)) - cost))
	)


## One round of rest: condition regain, injury and morale drift.
static func advance_round(player: Dictionary, played: bool) -> void:
	ensure_state(player)
	var condition := float(condition_of(player))
	var rate := MatchSimConfigScript.curve_attr(
		PlayerTypes.recovery_of(player),
		"recovery_share_1",
		"recovery_share_10",
		"recovery_share_20"
	)
	if not played:
		rate *= MatchSimConfigScript.get_f("recovery_idle_factor")
	if is_injured(player):
		rate *= 0.5
	if int(player.get("age", 25)) >= 33:
		rate *= 0.92
	var regain := MatchSimConfigScript.get_f("recovery_floor") \
		+ (float(MatchTypesScript.CONDITION_MAX) - condition) * rate
	player["condition"] = MatchTypesScript.clamp_condition(int(round(condition + regain)))

	var injury_rounds := int(player.get("injury_rounds", 0))
	if injury_rounds > 0:
		injury_rounds -= 1
		player["injury_rounds"] = injury_rounds
		if injury_rounds <= 0:
			player["injury_grade"] = ""

	var morale := float(morale_of(player))
	if absf(morale - float(BASELINE_MORALE)) > 0.5:
		var step := MatchTypesScript.MORALE_DRIFT * (float(BASELINE_MORALE) - morale)
		player["morale"] = MatchTypesScript.clamp_morale(int(round(morale + step)))


## Pre-season: everybody reports back fit. Long injuries still have to heal,
## and bans carry over unless the unit wipes yellows between seasons.
static func begin_season(player: Dictionary, wipe_yellows: bool) -> void:
	ensure_state(player)
	player["condition"] = MatchTypesScript.CONDITION_START
	if wipe_yellows:
		reset_yellows(player)
	var morale := float(morale_of(player))
	player["morale"] = MatchTypesScript.clamp_morale(
		int(round(morale + 0.5 * (float(MatchTypesScript.MORALE_DEFAULT) - morale)))
	)


## Called for every squad member of a club that has just played a match.
static func serve_suspension(player: Dictionary) -> void:
	var left := int(player.get("suspension_matches", 0))
	if left > 0:
		player["suspension_matches"] = left - 1


static func injury_duration(player: Dictionary, grade: String, rng: RandomNumberGenerator) -> int:
	var base := MatchTypesScript.roll_injury_rounds(grade, rng)
	var ratings := MatchRatings.of(player)
	var factor := 1.13 - 0.28 * float(ratings.get("recovery", 0.5))
	if bool(ratings.get("professional", false)):
		factor -= 0.05
	return maxi(1, int(round(float(base) * factor)))


static func status_label(player: Dictionary) -> String:
	if is_injured(player):
		var grade := str(player.get("injury_grade", ""))
		var rounds := int(player.get("injury_rounds", 0))
		return "%s травма · %d матч." % [MatchTypesScript.injury_grade_label(grade), rounds]
	if is_suspended(player):
		return "Дисквалификация · %d матч." % int(player.get("suspension_matches", 0))
	return "Готов"


static func morale_label(player: Dictionary) -> String:
	var morale := morale_of(player)
	if morale >= 85:
		return "Отличная"
	if morale >= 68:
		return "Хорошая"
	if morale >= 45:
		return "Нормальная"
	if morale >= 25:
		return "Низкая"
	return "Подавленная"


static func condition_label(player: Dictionary) -> String:
	var condition := condition_of(player)
	if condition >= 92:
		return "Свежий"
	if condition >= 78:
		return "В порядке"
	if condition >= 62:
		return "Подсел"
	if condition >= 45:
		return "Устал"
	return "Вымотан"
