class_name MatchEngine
extends RefCounted
## 8v8 match engine. Two 25-minute halves; playoffs add extra time and a
## penalty shootout decided by the taker and the keeper.
##
## Possession moves between individual actors on a 60 x 40 m pitch.
## ActionPitch resolves movement, passing, first touch, duels, shots and saves.
## Only the current eight players on each side can act. CA, PA, reputation,
## summed team ratings and the unused bench cannot generate chances or goals.
##
## The engine never mutates players: it returns per-player entries and the caller
## applies condition, morale, cards and injuries.


const MatchTypesScript := preload("res://game/match_types.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const LineupSelectorScript := preload("res://game/lineup_selector.gd")
const Coaching := preload("res://game/match_coaching.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")
const DisciplineRulesScript := preload("res://database/repositories/world/discipline_rules.gd")

const SIDE_HOME := "home"
const SIDE_AWAY := "away"


static func simulate(config: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	# Migration is deterministic and uses its own seed, never the match RNG.
	# Normalise before choosing a backend so old saves also use the fast path.
	for side in ["home","away"]:
		var spec: Dictionary=config.get(side,{})
		TacticTypesScript.ensure_coach_tactics(spec.get("coach",{}))
	var native: Variant = NativeSimulation.core()
	if native != null and not config.has("aggregate_offset") and NativeSimulation.supports_match(config):
		return native.simulate(config,rng,MatchSimConfigScript.fingerprint())
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var home_spec: Dictionary = config.get("home", {})
	var away_spec: Dictionary = config.get("away", {})
	var neutral := bool(config.get("neutral", false))
	var allow_draw := bool(config.get("allow_draw", true))
	var aggregate_offset := int(config.get("aggregate_offset", 0))
	var importance := float(config.get("importance", 1.0))
	var discipline: Dictionary = config.get("discipline", DisciplineRulesScript.defaults())

	var knobs := MatchSimConfigScript.snapshot()
	var home_lineup := _select_lineup(home_spec, rng, away_spec)
	var away_lineup := _select_lineup(away_spec, rng, home_spec)

	var home := _build_team(SIDE_HOME, home_spec, home_lineup, 0.0, 0.0, rng, knobs)
	var away := _build_team(SIDE_AWAY, away_spec, away_lineup, 0.0, 0.0, rng, knobs)

	var ctx := {
		"rng": rng,
		"discipline": discipline,
		"importance": importance,
		"events": [],
		"trace_actions": bool(config.get("trace_actions", false)),
		"knobs": knobs,
		"home_bonus": 0.0,
	}

	for phase in MatchTypesScript.REGULAR_PHASES:
		_run_phase(home, away, phase, MatchTypesScript.PHASE_MINUTES * phase, ctx, false)

	var minute := MatchTypesScript.REGULAR_MINUTES
	var extra_time := false
	var shootout: Dictionary = {}

	if not allow_draw and int(home["goals"]) + aggregate_offset == int(away["goals"]):
		extra_time = true
		for phase in MatchTypesScript.ET_PHASES:
			_run_phase(
				home,
				away,
				MatchTypesScript.REGULAR_PHASES + phase,
				MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.PHASE_MINUTES * phase,
				ctx,
				true
			)
		minute = MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES
		if int(home["goals"]) + aggregate_offset == int(away["goals"]):
			shootout = _run_shootout(home, away, ctx, minute)

	_close_minutes(home, minute)
	_close_minutes(away, minute)

	var home_goals: int = int(home["goals"])
	var away_goals: int = int(away["goals"])
	var winner := 0
	if not shootout.is_empty():
		winner = 1 if int(shootout.get("home", 0)) > int(shootout.get("away", 0)) else -1
	elif home_goals != away_goals:
		winner = 1 if home_goals > away_goals else -1

	_finalize_team(home, away_goals, winner, minute)
	_finalize_team(away, home_goals, -winner, minute)
	_award_motm(home, away)

	return {
		"engine": "individual-spatial-v3",
		"pitch": {"length_m":60.0,"width_m":40.0,"goal_width_m":5.0,"goal_height_m":2.0,"offside":false},
		"home_goals": home_goals,
		"settings_version": MatchSimConfigScript.CONFIG_VERSION,
		"settings_fingerprint": MatchSimConfigScript.fingerprint(),
		"away_goals": away_goals,
		"winner": winner,
		"extra_time": extra_time,
		"shootout": shootout,
		"minutes_played": minute,
		"home_team": _team_report(home, minute),
		"away_team": _team_report(away, minute),
		"events": ctx["events"],
	}


# --- setup ---------------------------------------------------------------


static func _select_lineup(spec: Dictionary, rng: RandomNumberGenerator, opponent: Dictionary = {}) -> Dictionary:
	return Coaching.select_lineup(spec, opponent, rng)


static func _build_team(
	side: String,
	spec: Dictionary,
	lineup: Dictionary,
	_own_ability: float,
	_opponent_ability: float,
	rng: RandomNumberGenerator,
	knobs: Dictionary
) -> Dictionary:
	var coach: Dictionary = spec.get("coach", {})
	var style := str(lineup.get("style", TacticTypesScript.STYLE_CONTROL))
	var profile: Dictionary = Coaching.profile(style, "normal", false)
	var gap := 0.0

	var team := {
		"side": side,
		"club_id": int(spec.get("club_id", 0)),
		"reputation": int(spec.get("reputation", 500)),
		"coach_id": int(coach.get("id", 0)),
		"form": _day_form(rng, knobs),
		"style": style,
		"initial_style": style,
		"primary_style": str(coach.get("primary_style", style)),
		"backup_style": str(coach.get("backup_style", style)),
		"plan_source": str(lineup.get("plan_source", "primary")),
		"plan_reason": str(lineup.get("plan_reason", "preferred_plan")),
		"plan_scores": lineup.get("plan_scores", {}),
		"approach": "normal",
		"conserve": false,
		"last_review": 0,
		"last_style_change": -20,
		"decisions": [],
		"intensity_sum": 0.0,
		"formation": str(lineup.get("formation", TacticTypesScript.FORM_232)),
		"profile": profile,
		"intensity": float(profile.get("intensity", 1.0)),
		"motivation": _coach_attr(coach, CoachTypes.ATTR_MOTIVATION),
		"coach_influence": float(knobs.get("coach_influence", 1.0)),
		"tactics": _coach_attr(coach, CoachTypes.ATTR_TACTICS),
		"ability": 0.0,
		"starting_ability": 0.0,
		"starting_condition": 0.0,
		"starting_keeper": {},
		"discipline_skill": _coach_attr(coach, CoachTypes.ATTR_DISCIPLINE),
		"on_field": [],
		"bench": lineup.get("bench", []),
		"subs_left": int(knobs.get("subs_max", MatchTypesScript.SUBS_MAX)),
		"entries": [],
		"by_id": {},
		"goals": 0,
		"shots": 0,
		"on_target": 0,
		"fouls": 0,
		"yellow": 0,
		"red": 0,
		"possession_sum": 0.0,
		"phases": 0,
		"men_down": 0,
	}

	for record in lineup.get("starters", []):
		var unit := _make_unit(record["player"], str(record["slot"]), float(record["fit"]), team, gap, rng, 0)
		team["on_field"].append(unit)
		team["starting_condition"] += PlayerConditionScript.condition_of(record["player"])
		if str(record["slot"]) == "GK":
			team["starting_keeper"] = {"player_id": int(record["player"].get("id", 0)),
				"ability": 0.0,
				"condition": PlayerConditionScript.condition_of(record["player"]),
				"native": bool(unit["ratings"].get("is_gk", false))}
	team["starting_condition"] /= maxi((team["on_field"] as Array).size(), 1)
	return team


static func _make_unit(
	player: Dictionary,
	slot: String,
	fit: float,
	team: Dictionary,
	ability_gap: float,
	_rng: RandomNumberGenerator,
	minute: int
) -> Dictionary:
	var ratings := MatchRatings.of(player)
	var entry := _new_entry(player, slot, minute == 0)
	team["entries"].append(entry)
	team["by_id"][int(player.get("id", 0))] = entry

	var role: Dictionary = MatchTypesScript.slot_role(slot)
	var role_att := float(role.get("att", 0.0))
	return {
		"player": player,
		"entry": entry,
		"ratings": ratings,
		"slot": slot,
		"role": role,
		"role_att": role_att,
		"fit": fit,
		"fresh": MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(player)),
		"drain": _drain_per_phase(ratings, player, team),
		"on_since": minute,
		"yellow": 0,
		"off": false,
	}


static func _drain_per_phase(_ratings: Dictionary, player: Dictionary, team: Dictionary) -> float:
	if not team.has("_drain_cache"):
		team["_drain_cache"] = {}
	var cache: Dictionary = team["_drain_cache"]
	var id := int(player.get("id", 0))
	var intensity := float(team["intensity"])
	if not cache.has(id):
		cache[id] = {}
	var by_intensity: Dictionary = cache[id]
	if id > 0 and by_intensity.has(intensity):
		return float(by_intensity[intensity])
	var remain := clampf(
		MatchSimConfigScript.curve_attr(
			PlayerTypes.stamina_of(player),
			"fresh_after_stamina_1",
			"fresh_after_stamina_10",
			"fresh_after_stamina_20"
		),
		0.0,
		1.0
	)
	var base := (1.0 - remain) / float(MatchTypesScript.REGULAR_PHASES)
	var condition := float(PlayerConditionScript.condition_of(player)) / float(MatchTypesScript.CONDITION_MAX)
	var age_factor := 1.0 + 0.010 * float(maxi(int(player.get("age", 25)) - 30, 0))
	var drain := base * intensity * (1.35 - 0.35 * condition) * age_factor \
		* PlayerConditionScript.match_workload_factor(player)
	by_intensity[intensity] = drain
	return drain


static func _new_entry(player: Dictionary, slot: String, started: bool) -> Dictionary:
	var position := PlayerTypes.normalize_position(str(player.get("position", "")))
	return {
		"player_id": int(player.get("id", 0)),
		"name": str(player.get("name", "")),
		"slot": slot,
		"position": position,
		"started": started,
		"minutes": 0,
		"intensity_minutes": 0.0,
		"goals": 0,
		"assists": 0,
		"saves": 0,
		"conceded": 0,
		"clean_sheet": false,
		"yellow": 0,
		"red": 0,
		"suspension": 0,
		"injury_grade": "",
		"injury_rounds": 0,
		"pen_scored": 0,
		"pen_missed": 0,
		"pen_saved": 0,
		"shootout_scored": 0,
		"shootout_missed": 0,
		"rating": MatchTypesScript.RATING_BASE,
		"motm": false,
		"is_gk": position == PlayerTypes.POS_GK,
	}


# --- phase loop ----------------------------------------------------------


static func _run_phase(
	home: Dictionary,
	away: Dictionary,
	phase: int,
	minute_start: int,
	ctx: Dictionary,
	extra: bool
) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	_review_coaching(home, away, minute_start, ctx)
	_review_coaching(away, home, minute_start, ctx)
	load("res://game/action_pitch.gd").play(home, away, ctx, minute_start, extra)
	home["phases"] = int(home["phases"]) + 1
	away["phases"] = int(away["phases"]) + 1
	home["intensity_sum"] = float(home["intensity_sum"]) + float(home["intensity"])
	away["intensity_sum"] = float(away["intensity_sum"]) + float(away["intensity"])
	var fatigue_scale := 1.35 if extra else 1.0
	_roll_discipline(home, ctx, minute_start+5)
	_roll_discipline(away, ctx, minute_start+5)
	_roll_injuries(home, ctx, minute_start+5, fatigue_scale)
	_roll_injuries(away, ctx, minute_start+5, fatigue_scale)



	var minute_end := minute_start + MatchTypesScript.PHASE_MINUTES
	if minute_end >= int(ctx["knobs"].get("subs_first_minute", 25)) and minute_end != MatchTypesScript.REGULAR_MINUTES and minute_end < MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES:
		_consider_fatigue_subs(home, away, ctx, minute_end)
		_consider_fatigue_subs(away, home, ctx, minute_end)


static func _score_goal(
	team: Dictionary,
	opponent: Dictionary,
	scorer: Dictionary,
	assistant: Dictionary,
	ctx: Dictionary,
	minute: int,
	event_type: String,
	secondary: Dictionary = {}
) -> void:
	team["goals"] = int(team["goals"]) + 1
	var entry: Dictionary = scorer["entry"]
	entry["goals"] = int(entry["goals"]) + 1
	var assist_name := ""
	var assist_ids: Array=[]
	var assist_names: Array=[]
	for helper in [assistant,secondary]:
		if helper.is_empty(): continue
		var ae: Dictionary=helper.entry
		var id := int(ae.player_id)
		if id==int(entry.player_id) or id in assist_ids: continue
		ae.assists=int(ae.assists)+1
		assist_ids.append(id)
		assist_names.append(str(ae.name))
	assist_name=", ".join(assist_names)
	var keeper := _keeper_of(opponent)
	if not keeper.is_empty():
		var keeper_entry: Dictionary = keeper["entry"]
		keeper_entry["conceded"] = int(keeper_entry["conceded"]) + 1
	var event := _log(ctx, minute, event_type, team, entry)
	if not assist_name.is_empty():
		event["assist"] = assist_name
	event.assist_ids=assist_ids
	event.assist_names=assist_names


static func _roll_discipline(team: Dictionary, ctx: Dictionary, minute: int) -> void:
	var discipline: Dictionary = ctx["discipline"]
	if not bool(discipline.get("enabled", true)):
		return
	var rng: RandomNumberGenerator = ctx["rng"]
	var coach_factor := 1.15 - 0.30 * (float(team["discipline_skill"]) / 20.0)
	# Referees keep a shorter leash when the stakes are higher.
	var knobs: Dictionary = ctx.get("knobs", {})
	var expectation := float(knobs.get("yellow_per_phase", MatchTypesScript.YELLOW_PER_PHASE)) \
		* float(discipline.get("strictness", 1.0)) \
		* coach_factor \
		* float(ctx["importance"])
	if rng.randf() >= expectation:
		return

	var offender := _pick_offender(team, rng)
	if offender.is_empty():
		return
	var entry: Dictionary = offender["entry"]

	if rng.randf() < float(knobs.get("red_direct_share", MatchTypesScript.RED_DIRECT_SHARE)):
		entry["red"] = 1
		entry["suspension"] = int(discipline.get("red_ban", 2))
		team["red"] = int(team["red"]) + 1
		_send_off(team, offender, ctx, minute)
		return

	entry["yellow"] = int(entry["yellow"]) + 1
	offender["yellow"] = int(offender["yellow"]) + 1
	team["yellow"] = int(team["yellow"]) + 1
	_log(ctx, minute, MatchTypesScript.EVENT_YELLOW, team, entry)

	if bool(discipline.get("double_yellow_red", true)) and int(offender["yellow"]) >= 2:
		entry["red"] = 1
		entry["suspension"] = maxi(1, int(discipline.get("red_ban", 2)) - 1)
		team["red"] = int(team["red"]) + 1
		_send_off(team, offender, ctx, minute)


static func _pick_offender(team: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var weights := PackedFloat32Array()
	var total := 0.0
	for unit in team["on_field"]:
		var ratings: Dictionary = unit["ratings"]
		var risk := float(ratings.get("foul_risk", 0.6))
		if bool(ratings.get("is_gk", false)):
			risk *= 0.2
		risk *= 1.0 + 0.5 * (1.0 - float(unit["fresh"]))
		risk *= float(unit.get("phase_fouls",0))
		weights.append(risk)
		total += risk
	var index := _pick_weighted(weights, total, rng)
	if index < 0:
		return {}
	return team["on_field"][index]


static func _send_off(team: Dictionary, unit: Dictionary, ctx: Dictionary, minute: int) -> void:
	var entry: Dictionary = unit["entry"]
	_log(ctx, minute, MatchTypesScript.EVENT_RED, team, entry)
	_close_unit(unit, minute)
	team["on_field"].erase(unit)
	team["men_down"] = int(team["men_down"]) + 1
	if str(unit["slot"]) == "GK":
		_replace_dismissed_keeper(team, ctx, minute)


static func _replace_dismissed_keeper(team: Dictionary, ctx: Dictionary, minute: int) -> void:
	if int(team["subs_left"]) <= 0:
		return
	var has_keeper := false
	for candidate in team["bench"]:
		if bool(MatchRatings.of(candidate).get("is_gk", false)):
			has_keeper = true
			break
	if not has_keeper:
		return
	# Sacrifice the least defensive outfield role, preserving the numerical loss.
	var outgoing: Dictionary = {}
	var defensive_value := INF
	for player_unit in team["on_field"]:
		var value := float(player_unit.ratings.get("defend",0.5))*float(player_unit.role.get("def",0.0))*float(player_unit.fresh)
		if value < defensive_value:
			defensive_value = value
			outgoing = player_unit
	if not outgoing.is_empty():
		_substitute(team, outgoing, ctx, minute, true, "goalkeeper_dismissal", "GK")


static func _roll_injuries(team: Dictionary, ctx: Dictionary, minute: int, fatigue_scale: float) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var knobs: Dictionary = ctx.get("knobs", {})
	if rng.randf() >= float(knobs.get("injury_per_phase", MatchTypesScript.INJURY_PER_PHASE)) * fatigue_scale:
		return
	var weights := PackedFloat32Array()
	var total := 0.0
	for unit in team["on_field"]:
		var player: Dictionary = unit["player"]
		var risk := 0.5 + 1.4 * (1.0 - float(unit["fresh"]))
		risk += 0.04 * float(maxi(int(player.get("age", 25)) - 29, 0))
		weights.append(risk)
		total += risk
	var index := _pick_weighted(weights, total, rng)
	if index < 0:
		return
	var victim: Dictionary = team["on_field"][index]
	var entry: Dictionary = victim["entry"]
	var grade := MatchTypesScript.roll_injury_grade(rng)
	entry["injury_grade"] = grade
	entry["injury_rounds"] = PlayerConditionScript.injury_duration(victim["player"], grade, rng)
	_log(ctx, minute, MatchTypesScript.EVENT_INJURY, team, entry)

	var replaced := false
	if int(team["subs_left"]) > 0:
		replaced = _substitute(team, victim, ctx, minute, true)
	if not replaced:
		_close_unit(victim, minute)
		team["on_field"].erase(victim)
		team["men_down"] = int(team["men_down"]) + 1


## Evaluate every outgoing role: a tired player with no suitable cover must not
## prevent a useful change elsewhere. Never spend the last window early.
static func _consider_fatigue_subs(team: Dictionary, opponent: Dictionary, ctx: Dictionary, minute: int) -> void:
	var knobs: Dictionary = ctx["knobs"]
	if int(team["subs_left"]) < 1 or (team["bench"] as Array).is_empty():
		return
	if int(team["subs_left"]) == 1 and minute < int(knobs.get("subs_reserve_until", 40)):
		return
	var best: Dictionary = {}
	var best_id := 0
	var best_gain := -INF
	var end_minute := MatchTypesScript.REGULAR_MINUTES if minute < MatchTypesScript.REGULAR_MINUTES else MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES
	var phases := maxf(1.0, float(end_minute-minute)/MatchTypesScript.PHASE_MINUTES)
	var gain_required := 1.0 + float(knobs.get("subs_min_gain", 0.02))
	var quality_required := float(knobs.get("subs_min_quality", 0.85))
	for unit in team["on_field"]:
		if bool(unit["ratings"].get("is_gk", false)) or minute - int(unit["on_since"]) < 10:
			continue
		if float(unit["fresh"]) > float(knobs.get("subs_freshness_threshold", 0.94)):
			continue
		var slot := str(unit["slot"])
		var original := LineupSelectorScript.role_value(unit["ratings"], slot, str(team["style"])) * float(unit["fit"])
		var current := original * (float(unit["fresh"]) + maxf(0.42,float(unit["fresh"])-float(unit["drain"])*phases)) * 0.5
		for option in _bench_role_options(team,slot):
			if team["bench_used"].has(int(option[0])) or float(option[1]) < original * quality_required:
				continue
			var incoming := float(option[1]) * (float(option[2])+maxf(0.42,float(option[2])-float(option[3])*phases)) * 0.5
			if incoming <= current * gain_required:
				continue
			var gain := incoming-current
			if gain > best_gain:
				best = unit
				best_id = int(option[0])
				best_gain = gain
	if not best.is_empty():
		var reason := "chasing_score" if int(team["goals"]) < int(opponent["goals"]) else "protect_lead" if int(team["goals"]) > int(opponent["goals"]) else "fatigue"
		_substitute(team, best, ctx, minute, false, reason, "", best_id, false)


## Reuse each bench player's role and running load until the tactical plan changes.
static func _bench_role_options(team: Dictionary, slot: String) -> Array:
	if not team.has("bench_used"):
		team["bench_used"] = {}
	if not team.has("bench_options_by_style"):
		team["bench_options_by_style"] = {}
	var styles: Dictionary = team["bench_options_by_style"]
	var style := str(team["style"])
	var intensity := float(team["intensity"])
	if not styles.has(style):
		styles[style] = {}
	var intensities: Dictionary = styles[style]
	if not intensities.has(intensity):
		intensities[intensity] = {}
	var options: Dictionary = intensities[intensity]
	if not options.has(slot):
		var slots := [slot]
		for unit in team["on_field"]:
			var role := str(unit["slot"])
			if not options.has(role) and not slots.has(role):
				slots.append(role)
		for role in slots:
			options[role] = []
		# Prepare each player once for this plan, rather than once for every role.
		for player in team["bench"]:
			var prepared := _prepare_bench_player(player, team)
			var ratings: Dictionary = prepared.ratings
			for role in slots:
				if (role == "GK") != bool(ratings.get("is_gk", false)):
					continue
				(options[role] as Array).append([player.get("id",0),
					LineupSelectorScript.role_value(ratings,role,style)*MatchTypesScript.slot_fit(role,str(ratings.get("position","CM"))),
					prepared.fresh,prepared.drain])
	return options[slot]


static func _remaining_role_value(unit: Dictionary, team: Dictionary, minute: int) -> float:
	var phases := maxf(1.0, float(MatchTypesScript.REGULAR_MINUTES - minute) / MatchTypesScript.PHASE_MINUTES)
	if minute >= MatchTypesScript.REGULAR_MINUTES:
		phases = maxf(1.0, float(MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES - minute) / MatchTypesScript.PHASE_MINUTES)
	var fresh := float(unit["fresh"])
	var end := maxf(0.42, fresh - float(unit["drain"]) * phases)
	return LineupSelectorScript.role_value(unit["ratings"], str(unit["slot"]), str(team["style"])) * float(unit["fit"]) * (fresh + end) * 0.5


static func _prepare_bench_player(player: Dictionary, team: Dictionary) -> Dictionary:
	if not team.has("bench_evaluation"):
		team["bench_evaluation"] = {}
	var cache: Dictionary = team["bench_evaluation"]
	var id := int(player.get("id", 0))
	var prepared: Dictionary = cache.get(id, {})
	# Bench players do not pay load inside simulate(). Only a changed tactical
	# intensity/style invalidates their projection; do not rebuild it per pair.
	if prepared.is_empty() or float(prepared.intensity) != float(team["intensity"]) or str(prepared.style) != str(team["style"]):
		prepared = {"ratings": MatchRatings.of(player), "intensity": team["intensity"], "style": team["style"], "roles": {},
			"fresh": MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(player)),
			"drain": _drain_per_phase(MatchRatings.of(player), player, team)}
		cache[id] = prepared
	return prepared


static func _replacement_value(player: Dictionary, slot: String, team: Dictionary, minute: int) -> float:
	var prepared := _prepare_bench_player(player, team)
	var ratings: Dictionary = prepared.ratings
	if (slot == "GK") != bool(ratings.get("is_gk", false)):
		return -1.0
	if not prepared.roles.has(slot):
		prepared.roles[slot] = LineupSelectorScript.role_value(ratings, slot, str(team["style"])) * MatchTypesScript.slot_fit(slot, str(ratings.get("position", "CM")))
	var end_minute := MatchTypesScript.REGULAR_MINUTES if minute < MatchTypesScript.REGULAR_MINUTES else MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES
	var phases := maxf(1.0, float(end_minute - minute) / MatchTypesScript.PHASE_MINUTES)
	return float(prepared.roles[slot]) * (float(prepared.fresh) + maxf(0.42, float(prepared.fresh) - float(prepared.drain) * phases)) * 0.5


static func _acceptable_replacement(unit: Dictionary, player: Dictionary, slot: String, team: Dictionary, incoming: float, current: float, knobs: Dictionary) -> bool:
	if incoming <= current * (1.0 + float(knobs.get("subs_min_gain", 0.02))):
		return false
	var original := LineupSelectorScript.role_value(unit["ratings"], slot, str(team["style"])) * float(unit["fit"])
	var ratings := MatchRatings.of(player)
	var replacement := LineupSelectorScript.role_value(ratings, slot, str(team["style"])) * MatchTypesScript.slot_fit(slot, str(ratings.get("position", "CM")))
	return replacement >= original * float(knobs.get("subs_min_quality", 0.85))


static func _substitute(
	team: Dictionary,
	unit: Dictionary,
	ctx: Dictionary,
	minute: int,
	forced: bool,
	reason: String = "fatigue",
	slot_override: String = "",
	preferred_id: int = 0,
	refresh_wheels: bool = true
) -> bool:
	var bench: Array = team["bench"]
	if bench.is_empty() or int(team["subs_left"]) < 1:
		return false
	var knobs: Dictionary = ctx.get("knobs", {})
	if knobs.is_empty():
		knobs = MatchSimConfigScript.snapshot()
	if not forced:
		if minute < int(knobs.get("subs_first_minute", 25)) or minute == MatchTypesScript.REGULAR_MINUTES or minute >= MatchTypesScript.REGULAR_MINUTES + MatchTypesScript.ET_MINUTES:
			return false
		if int(team["subs_left"]) == 1 and minute < int(knobs.get("subs_reserve_until", 40)):
			return false
	var slot := slot_override if not slot_override.is_empty() else str(unit["slot"])
	var need_gk := slot == "GK"
	var best_index := -1
	var best_score := -1.0
	for i in bench.size():
		var candidate: Dictionary = bench[i]
		if preferred_id>0 and int(candidate.get("id",0)) != preferred_id:
			continue
		var candidate_ratings := MatchRatings.of(candidate)
		if need_gk != bool(candidate_ratings.get("is_gk", false)):
			continue
		var score := _replacement_value(candidate, slot, team, minute)
		if not forced and not _acceptable_replacement(unit, candidate, slot, team, score, _remaining_role_value(unit, team, minute), knobs):
			continue
		if score > best_score:
			best_score = score
			best_index = i
	if best_index < 0:
		return false

	var incoming: Dictionary = bench[best_index]
	bench.remove_at(best_index)
	if team.has("bench_used"):
		team["bench_used"][int(incoming.get("id",0))] = true
	team["subs_left"] = int(team["subs_left"]) - 1

	_close_unit(unit, minute)
	var index := (team["on_field"] as Array).find(unit)
	var fresh_unit := _make_unit(
		incoming,
		slot,
		MatchTypesScript.slot_fit(slot, str(MatchRatings.of(incoming).get("position", PlayerTypes.POS_CM))),
		team,
		0.0,
		ctx["rng"],
		minute
	)
	if index >= 0:
		(team["on_field"] as Array)[index] = fresh_unit
	else:
		(team["on_field"] as Array).append(fresh_unit)

	var event := _log(ctx, minute, MatchTypesScript.EVENT_SUB, team, fresh_unit["entry"])
	event["out"] = str((unit["entry"] as Dictionary)["name"])
	event["forced"] = forced
	event["reason"] = "injury" if forced and reason == "fatigue" else reason
	return true


static func _review_coaching(team: Dictionary, opponent: Dictionary, minute: int, ctx: Dictionary) -> void:
	var decision := Coaching.review(team, opponent, minute)
	if decision.is_empty():
		return
	team["style"] = decision["style"]
	team["approach"] = decision["approach"]
	team["conserve"] = decision["conserve"]
	team["profile"] = Coaching.profile(team["style"], team["approach"], team["conserve"])
	team["intensity"] = float(team["profile"]["intensity"])
	for unit in team["on_field"]:
		unit["drain"] = _drain_per_phase(unit["ratings"], unit["player"], team)
	(team["decisions"] as Array).append(decision)
	var event := decision.duplicate()
	event["type"] = "TACTICAL_CHANGE"
	event["club_id"] = team["club_id"]
	event["side"] = team["side"]
	(ctx["events"] as Array).append(event)
	if decision["approach"] == "chase" and int(team["tactics"]) >= 7:
		_consider_tactical_sub(team, ctx, minute)


static func _consider_tactical_sub(team: Dictionary, ctx: Dictionary, minute: int) -> void:
	# Leave an emergency replacement; do not spend the whole bench on one review.
	if int(team["subs_left"]) <= 1:
		return
	var target: Dictionary = {}
	var largest_gain := 0.0
	for unit in team["on_field"]:
		if bool(unit["ratings"]["is_gk"]) or float(unit["role_att"]) < 0.5:
			continue
		var slot := str(unit["slot"])
		var current := LineupSelectorScript.role_value(unit["ratings"], slot, team["style"]) \
			* float(unit["fit"]) * float(unit["fresh"])
		for player in team["bench"]:
			var ratings := MatchRatings.of(player)
			if bool(ratings["is_gk"]):
				continue
			var incoming := LineupSelectorScript.role_value(ratings, slot, team["style"]) \
				* MatchTypesScript.slot_fit(slot, str(ratings["position"])) \
				* MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(player))
			if incoming > current * 1.02 and incoming - current > largest_gain:
				largest_gain = incoming - current
				target = unit
	if not target.is_empty():
		var event_count := (ctx["events"] as Array).size()
		_substitute(team, target, ctx, minute, false, "chasing_score")
		if (ctx["events"] as Array).size() > event_count:
			(team["decisions"] as Array).append((ctx["events"] as Array).back().duplicate())


static func _run_shootout(home: Dictionary, away: Dictionary, ctx: Dictionary, minute: int) -> Dictionary:
	var home_takers := _shootout_order(home)
	var away_takers := _shootout_order(away)
	if home_takers.is_empty() or away_takers.is_empty():
		return {"home": 1, "away": 0} if home_takers.size() >= away_takers.size() else {"home": 0, "away": 1}

	var home_score := 0
	var away_score := 0
	var round_index := 0
	while round_index < MatchTypesScript.SHOOTOUT_MAX_ROUNDS:
		var sudden := round_index >= MatchTypesScript.SHOOTOUT_ROUNDS
		if _shoot(home_takers, away, round_index, ctx, minute):
			home_score += 1
		if _shoot(away_takers, home, round_index, ctx, minute):
			away_score += 1
		round_index += 1
		if sudden:
			if home_score != away_score:
				break
		else:
			var left := MatchTypesScript.SHOOTOUT_ROUNDS - round_index
			if absi(home_score - away_score) > left:
				break
			if round_index >= MatchTypesScript.SHOOTOUT_ROUNDS and home_score != away_score:
				break
	if home_score == away_score:
		# Still level after the takers' own penalties: the better finisher, then the ground.
		var home_pen := _shootout_score(home_takers[0])
		var away_pen := _shootout_score(away_takers[0])
		if home_pen >= away_pen:
			home_score += 1
		else:
			away_score += 1
	return {"home": home_score, "away": away_score}


static func _shoot(
	takers: Array,
	opponent: Dictionary,
	round_index: int,
	ctx: Dictionary,
	minute: int
) -> bool:
	var rng: RandomNumberGenerator = ctx["rng"]
	var unit: Dictionary = takers[round_index % takers.size()]
	var ratings: Dictionary = unit["ratings"]
	var keeper := _keeper_of(opponent)
	var attrs: Dictionary = unit.player.get("attributes",{})
	var skill := float((attrs.get("set_pieces",{}) as Dictionary).get("penalties",10))*(0.55+0.45*float(unit.fresh))
	if bool(ratings.get("ice_cold",false)): skill=minf(20,skill+1)
	var keeper_attrs: Dictionary = (keeper.get("player",{}) as Dictionary).get("attributes",{})
	var goalkeeping: Dictionary = keeper_attrs.get("goalkeeping",{})
	var fresh := 0.55+0.45*float(keeper.get("fresh",1))
	var fallback := 10 if bool((keeper.get("ratings",{}) as Dictionary).get("is_gk",false)) else 1
	var outcome: int = load("res://game/action_rules.gd").penalty_trial(skill,float(goalkeeping.get("reflexes",fallback))*fresh,float(goalkeeping.get("positioning",fallback))*fresh,rng,float(ctx.knobs.get("penalty_conversion_base",MatchTypesScript.PENALTY_CONVERSION_BASE))/MatchTypesScript.PENALTY_CONVERSION_BASE,not keeper.is_empty())
	var entry: Dictionary = unit["entry"]
	if outcome == 2:
		entry["shootout_scored"] = int(entry["shootout_scored"]) + 1
		return true
	entry["shootout_missed"] = int(entry["shootout_missed"]) + 1
	if not keeper.is_empty() and outcome == 1:
		var keeper_entry: Dictionary = keeper["entry"]
		keeper_entry["pen_saved"] = int(keeper_entry["pen_saved"]) + 1
	_log(ctx, minute, MatchTypesScript.EVENT_SHOOTOUT, {"side": ""}, entry)
	return false


static func _shootout_order(team: Dictionary) -> Array:
	var takers: Array = []
	for unit in team["on_field"]:
		takers.append(unit)
	takers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _shootout_score(a) > _shootout_score(b)
	)
	return takers


static func _shootout_score(unit: Dictionary) -> float:
	var ratings: Dictionary = unit["ratings"]
	var score := float(ratings.get("penalty", 0.4))
	if bool(ratings.get("is_gk", false)):
		score *= 0.25
	if bool(ratings.get("ice_cold", false)):
		score += 0.08
	return score


# --- wrap-up -------------------------------------------------------------


static func _close_minutes(team: Dictionary, minute: int) -> void:
	for unit in team["on_field"]:
		_close_unit(unit, minute)


static func _close_unit(unit: Dictionary, minute: int) -> void:
	if bool(unit.get("off", false)):
		return
	unit["off"] = true
	var entry: Dictionary = unit["entry"]
	entry["minutes"] = int(entry["minutes"]) + maxi(minute - int(unit["on_since"]), 0)


static func _finalize_team(team: Dictionary, conceded: int, result: int, minutes: int) -> void:
	var result_bonus := 0.0
	if result > 0:
		result_bonus = 0.28
	elif result < 0:
		result_bonus = -0.22
	for entry in team["entries"]:
		var played := float(entry["minutes"]) / float(maxi(minutes, 1))
		var rating := MatchTypesScript.RATING_BASE
		rating += 0.95 * float(entry["goals"])
		rating += 0.55 * float(entry["assists"])
		rating += 0.07 * float(entry["saves"])
		rating += 0.30 * float(entry["pen_scored"]) + 0.45 * float(entry["pen_saved"])
		rating -= 0.45 * float(entry["pen_missed"])
		rating -= 0.35 * float(entry["yellow"])
		rating -= 1.40 * float(entry["red"])
		rating += result_bonus * played
		if bool(entry["is_gk"]) and float(entry["minutes"]) > 0.0:
			if conceded == 0:
				rating += 0.45
			else:
				rating -= 0.22 * float(maxi(conceded - 1, 0))
		if float(entry["minutes"]) <= 0.0:
			rating = 0.0
		entry["rating"] = snappedf(MatchTypesScript.clamp_rating(rating), 0.1) if rating > 0.0 else 0.0
		entry["clean_sheet"] = bool(entry["is_gk"]) and conceded == 0 and int(entry["minutes"]) > 0


static func _award_motm(home: Dictionary, away: Dictionary) -> void:
	var best: Dictionary = {}
	var best_rating := -1.0
	for team in [home, away]:
		for entry in team["entries"]:
			var rating := float(entry["rating"])
			if rating > best_rating:
				best_rating = rating
				best = entry
	if not best.is_empty() and best_rating > 0.0:
		best["motm"] = true


static func _team_report(team: Dictionary, _minutes: int) -> Dictionary:
	var phases := maxi(int(team["phases"]), 1)
	var actions := {}
	for key in ["passes", "completed_passes", "dribbles", "successful_dribbles", "interceptions", "blocks", "crosses", "completed_crosses", "distance_metres"]:
		var total := 0
		for entry in team.entries: total+=int(entry.get(key,0))
		actions[key]=total
	return {
		"club_id": int(team["club_id"]),
		"coach_id": int(team["coach_id"]),
		"starting_ability": float(team["starting_ability"]),
		"starting_condition": float(team["starting_condition"]),
		"starting_keeper": (team["starting_keeper"] as Dictionary).duplicate(),
		"style": str(team["style"]),
		"initial_style": str(team["initial_style"]),
		"plan_source": str(team["plan_source"]),
		"plan_reason": str(team["plan_reason"]),
		"plan_scores": team["plan_scores"],
		"decisions": team["decisions"],
		"formation": str(team["formation"]),
		"goals": int(team["goals"]),
		"shots": int(team["shots"]),
		"on_target": int(team["on_target"]),
		"fouls": int(team["fouls"]),
		"yellow": int(team["yellow"]),
		"red": int(team["red"]),
		"possession": snappedf(float(team["possession_sum"]) / float(phases), 0.001),
		"intensity": float(team["intensity_sum"]) / phases,
		"players": team["entries"],
		"actions": actions,
	}


# --- helpers -------------------------------------------------------------


static func _keeper_of(team: Dictionary) -> Dictionary:
	for unit in team["on_field"]:
		if bool((unit["ratings"] as Dictionary).get("is_gk", false)):
			return unit
	if (team["on_field"] as Array).is_empty():
		return {}
	# No keeper left on the pitch: the outfielder in goal is far weaker.
	var stand_in: Dictionary = (team["on_field"] as Array)[0]
	return stand_in


static func _pick_weighted(weights: PackedFloat32Array, total: float, rng: RandomNumberGenerator) -> int:
	if total <= 0.0 or weights.is_empty():
		return -1
	var ticket := rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if ticket <= acc:
			return i
	return weights.size() - 1


static func _day_form(_rng: RandomNumberGenerator, _knobs: Dictionary) -> float:
	return 1.0


static func _coach_attr(coach: Dictionary, key: String) -> int:
	var attributes: Variant = coach.get("attributes", null)
	if typeof(attributes) == TYPE_DICTIONARY:
		return clampi(int((attributes as Dictionary).get(key, 10)), 1, 20)
	return 10


static func _log(
	ctx: Dictionary,
	minute: int,
	type: String,
	team: Dictionary,
	entry: Dictionary
) -> Dictionary:
	var event := {
		"minute": minute,
		"type": type,
		"side": str(team.get("side", "")),
		"club_id": int(team.get("club_id", 0)),
		"player_id": int(entry.get("player_id", 0)),
		"player": str(entry.get("name", "")),
	}
	(ctx["events"] as Array).append(event)
	return event
