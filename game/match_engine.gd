class_name MatchEngine
extends RefCounted
## 8v8 match engine. Two 25-minute halves; playoffs add extra time and a
## penalty shootout decided by the taker and the keeper.
##
## Every attack is a duel. The creator against the defender, the finisher
## against the keeper. Equal players produce the slider rate; a skill gap
## moves that rate. A red card takes the player off and weakens the side
## for every phase after it. The coach's tactics and motivation shape how
## well the same players execute.
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
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()

	var home_spec: Dictionary = config.get("home", {})
	var away_spec: Dictionary = config.get("away", {})
	var neutral := bool(config.get("neutral", false))
	var allow_draw := bool(config.get("allow_draw", true))
	var importance := float(config.get("importance", 1.0))
	var discipline: Dictionary = config.get("discipline", DisciplineRulesScript.defaults())

	var knobs := MatchSimConfigScript.snapshot()
	var home_lineup := _select_lineup(home_spec, rng, away_spec)
	var away_lineup := _select_lineup(away_spec, rng, home_spec)
	var home_ability := _lineup_ability(home_lineup)
	var away_ability := _lineup_ability(away_lineup)

	var home := _build_team(SIDE_HOME, home_spec, home_lineup, home_ability, away_ability, rng, knobs)
	var away := _build_team(SIDE_AWAY, away_spec, away_lineup, away_ability, home_ability, rng, knobs)

	var ctx := {
		"rng": rng,
		"discipline": discipline,
		"importance": importance,
		"events": [],
		"knobs": knobs,
		"home_bonus": 0.0 if neutral else _home_bonus(home_spec, knobs),
	}

	for phase in MatchTypesScript.REGULAR_PHASES:
		_run_phase(home, away, phase, MatchTypesScript.PHASE_MINUTES * phase, ctx, false)

	var minute := MatchTypesScript.REGULAR_MINUTES
	var extra_time := false
	var shootout: Dictionary = {}

	if not allow_draw and home["goals"] == away["goals"]:
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
		if home["goals"] == away["goals"]:
			shootout = _run_shootout(home, away, ctx, minute)

	_close_minutes(home, minute)
	_close_minutes(away, minute)

	var home_goals: int = int(home["goals"])
	var away_goals: int = int(away["goals"])
	var winner := 0
	if home_goals != away_goals:
		winner = 1 if home_goals > away_goals else -1
	elif not shootout.is_empty():
		winner = 1 if int(shootout.get("home", 0)) > int(shootout.get("away", 0)) else -1

	_finalize_team(home, away_goals, winner, minute)
	_finalize_team(away, home_goals, -winner, minute)
	_award_motm(home, away)

	return {
		"home_goals": home_goals,
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
	own_ability: float,
	opponent_ability: float,
	rng: RandomNumberGenerator,
	knobs: Dictionary
) -> Dictionary:
	var coach: Dictionary = spec.get("coach", {})
	var style := str(lineup.get("style", TacticTypesScript.STYLE_CONTROL))
	var profile: Dictionary = MatchTypesScript.style_profile(style)
	var gap := clampf((opponent_ability - own_ability) / 100.0, -0.4, 0.4)

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
		"tactics": _coach_attr(coach, CoachTypes.ATTR_TACTICS),
		"ability": own_ability,
		"discipline_skill": _coach_attr(coach, CoachTypes.ATTR_DISCIPLINE),
		"on_field": [],
		"bench": lineup.get("bench", []),
		"subs_left": MatchTypesScript.SUBS_MAX,
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

	var morale := MatchTypesScript.morale_multiplier(PlayerConditionScript.morale_of(player))
	var form := 1.0
	# Facing a clearly stronger side rattles everyone except the fearless.
	if ability_gap > 0.0 and not bool(ratings.get("fearless", false)):
		form -= ability_gap * (0.12 - 0.06 * float(ratings.get("pressure", 0.5)))
	# Motivation 10 is neutral. 20 pulls the squad up, 1 leaves ability on the bench.
	var motivation_boost := 0.92 + 0.16 * (float(team["motivation"]) / 20.0)

	# The collective day is part of every duel, not just of the chance count.
	var base := fit * form * morale * motivation_boost * float(team["form"])
	var attack := 0.52 * float(ratings.get("finish", 0.4)) \
		+ 0.28 * float(ratings.get("off_ball", 0.4)) \
		+ 0.20 * float(ratings.get("dribble", 0.4))
	var control := 0.62 * float(ratings.get("create", 0.4)) + 0.38 * float(ratings.get("press", 0.4))
	var defence := 0.72 * float(ratings.get("defend", 0.4)) + 0.28 * float(ratings.get("press", 0.4))
	if bool(ratings.get("is_gk", false)):
		defence = 0.5 * float(ratings.get("gk_stop", 0.4)) + 0.5 * float(ratings.get("gk_aerial", 0.4))

	var role: Dictionary = MatchTypesScript.slot_role(slot)
	var role_att := float(role.get("att", 0.0))
	var role_ctrl := float(role.get("ctrl", 0.0))
	var role_def := float(role.get("def", 0.0))
	return {
		"player": player,
		"entry": entry,
		"ratings": ratings,
		"slot": slot,
		"role": role,
		"role_att": role_att,
		"role_ctrl": role_ctrl,
		"role_def": role_def,
		# Role weight already folded in: the phase loop only scales by freshness.
		"w_att": attack * base * role_att,
		"w_ctrl": control * base * role_ctrl,
		"w_def": defence * base * role_def,
		"fit": fit,
		"base": base,
		"attack": attack * base,
		"control": control * base,
		"defence": defence * base,
		"fresh": MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(player)),
		"drain": _drain_per_phase(ratings, player, team),
		"on_since": minute,
		"yellow": 0,
		"off": false,
	}


static func _drain_per_phase(_ratings: Dictionary, player: Dictionary, team: Dictionary) -> float:
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
	return base * float(team["intensity"]) * (1.35 - 0.35 * condition) * age_factor


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
	_build_wheels(home)
	_build_wheels(away)

	var home_ctrl := float(home["ctrl_power"]) * float(home["profile"].get("ctrl", 1.0))
	var away_ctrl := float(away["ctrl_power"]) * float(away["profile"].get("ctrl", 1.0))
	var total_ctrl := home_ctrl + away_ctrl
	var home_share := 0.5 if total_ctrl <= 0.0 else home_ctrl / total_ctrl
	home["possession_sum"] = float(home["possession_sum"]) + home_share
	away["possession_sum"] = float(away["possession_sum"]) + (1.0 - home_share)
	home["phases"] = int(home["phases"]) + 1
	away["phases"] = int(away["phases"]) + 1
	home["intensity_sum"] = float(home["intensity_sum"]) + float(home["intensity"])
	away["intensity_sum"] = float(away["intensity_sum"]) + float(away["intensity"])

	var fatigue_scale := 1.0 if not extra else 1.35
	var home_exp := _chance_expectation(home, away, home_share, float(ctx["home_bonus"]), ctx)
	var away_exp := _chance_expectation(away, home, 1.0 - home_share, 0.0, ctx)
	if extra:
		home_exp *= 0.9
		away_exp *= 0.9

	var order_home_first := rng.randf() < home_share
	if order_home_first:
		_run_attacks(home, away, home_exp, phase, minute_start, ctx)
		_run_attacks(away, home, away_exp, phase, minute_start, ctx)
	else:
		_run_attacks(away, home, away_exp, phase, minute_start, ctx)
		_run_attacks(home, away, home_exp, phase, minute_start, ctx)

	_roll_discipline(home, ctx, minute_start)
	_roll_discipline(away, ctx, minute_start)
	_roll_injuries(home, ctx, minute_start, fatigue_scale)
	_roll_injuries(away, ctx, minute_start, fatigue_scale)

	_apply_fatigue(home, fatigue_scale)
	_apply_fatigue(away, fatigue_scale)

	var minute_end := minute_start + MatchTypesScript.PHASE_MINUTES
	if phase + 1 >= MatchTypesScript.SUBS_FATIGUE_PHASE_FROM:
		_consider_fatigue_subs(home, away, ctx, minute_end)
		_consider_fatigue_subs(away, home, ctx, minute_end)


static func _build_wheels(team: Dictionary) -> void:
	var att_w := PackedFloat32Array()
	var ctrl_w := PackedFloat32Array()
	var def_w := PackedFloat32Array()
	var att_power := 0.0
	var ctrl_power := 0.0
	var def_power := 0.0
	var att_weight := 0.0
	var def_weight := 0.0
	var ctrl_weight := 0.0
	var effective_ability := 0.0

	for unit in team["on_field"]:
		var fresh := float(unit["fresh"])
		effective_ability += float(unit["ratings"].get("ability", 0.5)) * 100.0 \
			* float(unit["fit"]) * fresh
		var a_val := float(unit["w_att"]) * fresh
		var c_val := float(unit["w_ctrl"]) * fresh
		var d_val := float(unit["w_def"]) * fresh
		att_w.append(a_val)
		ctrl_w.append(c_val)
		def_w.append(d_val)
		att_power += a_val
		ctrl_power += c_val
		def_power += d_val
		att_weight += float(unit["role_att"])
		ctrl_weight += float(unit["role_ctrl"])
		def_weight += float(unit["role_def"])

	team["att_wheel"] = att_w
	team["ctrl_wheel"] = ctrl_w
	team["def_wheel"] = def_w
	team["att_total"] = att_power
	team["ctrl_total"] = ctrl_power
	team["def_total"] = def_power
	team["att_norm"] = 0.0 if att_weight <= 0.0 else att_power / att_weight
	team["ctrl_power"] = 0.0 if ctrl_weight <= 0.0 else ctrl_power / ctrl_weight
	team["def_norm"] = 0.0 if def_weight <= 0.0 else def_power / def_weight
	# Headcount is handled separately by men_down; do not penalise it twice here.
	var count := (team["on_field"] as Array).size()
	team["ability"] = 0.0 if count == 0 else effective_ability / float(count)


static func _chance_expectation(
	team: Dictionary,
	opponent: Dictionary,
	possession: float,
	home_bonus: float,
	ctx: Dictionary
) -> float:
	var attack := float(team["att_norm"])
	var defence := maxf(float(opponent["def_norm"]), 0.05)
	var knobs: Dictionary = ctx.get("knobs", {})
	var ratio := pow(
		clampf(
			attack / defence,
			MatchTypesScript.QUALITY_RATIO_MIN,
			MatchTypesScript.QUALITY_RATIO_MAX
		),
		float(knobs.get("quality_exponent", MatchTypesScript.QUALITY_EXPONENT))
	)
	var tempo := float(team["profile"].get("tempo", 1.0))
	var concede := float(opponent["profile"].get("concede", 1.0))
	var share := 0.5 + possession
	var man_down := float(knobs.get("man_down_penalty", MatchTypesScript.MAN_DOWN_PENALTY))
	var men_down := 1.0 - man_down * float(opponent["men_down"])
	var own_down := 1.0 - man_down * float(team["men_down"])
	var expectation := float(knobs.get("chances_per_phase", MatchTypesScript.CHANCES_PER_PHASE)) \
		* ratio * _squad_factor(team, opponent) * _coach_factor(team, opponent) \
		* tempo * concede * share
	expectation *= (1.0 + home_bonus) * own_down / maxf(men_down, 0.4)
	return clampf(expectation, 0.04, 1.65)


static func _run_attacks(
	team: Dictionary,
	opponent: Dictionary,
	expectation: float,
	_phase: int,
	minute_start: int,
	ctx: Dictionary
) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var knobs: Dictionary = ctx.get("knobs", {})
	var count := _sample_poisson(expectation, rng)
	for _i in count:
		var minute := minute_start + rng.randi_range(1, MatchTypesScript.PHASE_MINUTES)
		var set_piece := rng.randf() < float(knobs.get("set_piece_share", MatchTypesScript.SET_PIECE_SHARE))
		_resolve_chance(team, opponent, ctx, minute, set_piece)
	if rng.randf() < float(knobs.get("penalty_per_phase", MatchTypesScript.PENALTY_PER_PHASE)):
		_resolve_penalty(team, opponent, ctx, minute_start + rng.randi_range(1, MatchTypesScript.PHASE_MINUTES))


static func _resolve_chance(
	team: Dictionary,
	opponent: Dictionary,
	ctx: Dictionary,
	minute: int,
	set_piece: bool
) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var creator_index := _pick_weighted(team["ctrl_wheel"], float(team["ctrl_total"]), rng)
	if creator_index < 0:
		return
	var creator: Dictionary = team["on_field"][creator_index]
	var defender_index := _pick_weighted(opponent["def_wheel"], float(opponent["def_total"]), rng)
	if defender_index < 0:
		return
	var defender: Dictionary = opponent["on_field"][defender_index]

	var creator_ratings: Dictionary = creator["ratings"]
	var defender_ratings: Dictionary = defender["ratings"]
	var creator_fresh := float(creator["fresh"])

	var creation := 0.0
	if set_piece:
		creation = float(creator_ratings.get("set_piece", 0.4)) * float(creator["base"])
	else:
		creation = (
			0.62 * float(creator_ratings.get("create", 0.4))
			+ 0.38 * float(creator_ratings.get("dribble", 0.4))
		) * float(creator["base"]) * creator_fresh

	var resistance := float(defender_ratings.get("defend", 0.4)) * float(defender["base"]) * float(defender["fresh"])
	if set_piece:
		resistance = float(defender_ratings.get("aerial", 0.4)) * float(defender["base"]) * 0.9

	var knobs: Dictionary = ctx.get("knobs", {})
	creation = _touch(creation, creator, rng, knobs)
	resistance = _touch(resistance, defender, rng, knobs)
	var edge := creation - resistance + _coach_edge(team)
	# The slider is the rate when the two players are equal. The gap between
	# them is what moves the chance, not a coin flip beside their attributes.
	var p_create := clampf(
		float(knobs.get("chance_create_base", MatchTypesScript.CHANCE_CREATE_BASE)) + 0.45 * edge,
		0.04,
		0.96
	)
	if rng.randf() >= p_create:
		return

	var shooter_index := creator_index
	var solo := set_piece == false and _takes_it_himself(creator, rng)
	if not solo:
		shooter_index = _pick_weighted(team["att_wheel"], float(team["att_total"]), rng)
		if shooter_index < 0 or shooter_index == creator_index:
			shooter_index = creator_index
			solo = true
	var shooter: Dictionary = team["on_field"][shooter_index]
	var shooter_ratings: Dictionary = shooter["ratings"]

	team["shots"] = int(team["shots"]) + 1

	var quality := clampf(
		0.50 + 0.85 * edge + (float(team["profile"].get("quality", 1.0)) - 1.0),
		0.05,
		1.0
	)
	var finishing := float(shooter_ratings.get("finish", 0.4))
	if set_piece:
		finishing = maxf(finishing, float(shooter_ratings.get("aerial", 0.4)) * 0.9)
	finishing *= float(shooter["base"]) * float(shooter["fresh"])
	finishing = _touch(finishing, shooter, rng, knobs)

	var on_target := clampf(
		float(knobs.get("shot_on_target_base", MatchTypesScript.SHOT_ON_TARGET_BASE))
			+ 0.45 * (finishing - 0.5) + 0.16 * (quality - 0.5),
		0.06,
		0.95
	)
	if rng.randf() >= on_target:
		return
	team["on_target"] = int(team["on_target"]) + 1

	var keeper: Dictionary = _keeper_of(opponent)
	var keeper_skill := 0.42
	if not keeper.is_empty():
		keeper_skill = float((keeper["ratings"] as Dictionary).get("gk_stop", 0.42)) \
			* float(keeper["base"]) * float(keeper["fresh"])

	var clutch := 0.0
	if bool(shooter_ratings.get("ice_cold", false)) and minute >= 40:
		clutch = 0.035
	var conversion := clampf(
		float(knobs.get("shot_conversion_base", MatchTypesScript.SHOT_CONVERSION_BASE))
			+ 0.42 * (finishing - keeper_skill)
			+ 0.22 * (quality - 0.5)
			+ clutch,
		0.02,
		0.90
	)

	if rng.randf() < conversion:
		_score_goal(team, opponent, shooter, creator if not solo else {}, ctx, minute, MatchTypesScript.EVENT_GOAL)
	elif not keeper.is_empty():
		var keeper_entry: Dictionary = keeper["entry"]
		keeper_entry["saves"] = int(keeper_entry["saves"]) + 1


static func _resolve_penalty(team: Dictionary, opponent: Dictionary, ctx: Dictionary, minute: int) -> void:
	var rng: RandomNumberGenerator = ctx["rng"]
	var taker := _best_on_field(team, "penalty")
	if taker.is_empty():
		return
	var keeper := _keeper_of(opponent)
	var taker_ratings: Dictionary = taker["ratings"]
	var skill := float(taker_ratings.get("penalty", 0.5))
	if bool(taker_ratings.get("ice_cold", false)):
		skill += 0.06
	var keeper_skill := 0.45
	if not keeper.is_empty():
		keeper_skill = float((keeper["ratings"] as Dictionary).get("gk_penalty", 0.45))
	var knobs: Dictionary = ctx.get("knobs", {})
	var chance := clampf(
		float(knobs.get("penalty_conversion_base", MatchTypesScript.PENALTY_CONVERSION_BASE))
			+ 0.30 * (skill - 0.5) - 0.22 * (keeper_skill - 0.5),
		0.45,
		0.95
	)
	var entry: Dictionary = taker["entry"]
	team["shots"] = int(team["shots"]) + 1
	if rng.randf() < chance:
		team["on_target"] = int(team["on_target"]) + 1
		entry["pen_scored"] = int(entry["pen_scored"]) + 1
		_score_goal(team, opponent, taker, {}, ctx, minute, MatchTypesScript.EVENT_PENALTY_GOAL)
		return
	entry["pen_missed"] = int(entry["pen_missed"]) + 1
	if not keeper.is_empty() and rng.randf() < 0.55:
		team["on_target"] = int(team["on_target"]) + 1
		var keeper_entry: Dictionary = keeper["entry"]
		keeper_entry["saves"] = int(keeper_entry["saves"]) + 1
		keeper_entry["pen_saved"] = int(keeper_entry["pen_saved"]) + 1
	_log(ctx, minute, MatchTypesScript.EVENT_PENALTY_MISS, team, entry)


static func _score_goal(
	team: Dictionary,
	opponent: Dictionary,
	scorer: Dictionary,
	assistant: Dictionary,
	ctx: Dictionary,
	minute: int,
	event_type: String
) -> void:
	team["goals"] = int(team["goals"]) + 1
	var entry: Dictionary = scorer["entry"]
	entry["goals"] = int(entry["goals"]) + 1
	var assist_name := ""
	if not assistant.is_empty():
		var assist_entry: Dictionary = assistant["entry"]
		assist_entry["assists"] = int(assist_entry["assists"]) + 1
		assist_name = str(assist_entry["name"])
	var keeper := _keeper_of(opponent)
	if not keeper.is_empty():
		var keeper_entry: Dictionary = keeper["entry"]
		keeper_entry["conceded"] = int(keeper_entry["conceded"]) + 1
	var event := _log(ctx, minute, event_type, team, entry)
	if not assist_name.is_empty():
		event["assist"] = assist_name


static func _takes_it_himself(unit: Dictionary, rng: RandomNumberGenerator) -> bool:
	var ratings: Dictionary = unit["ratings"]
	var role: Dictionary = unit["role"]
	var base := 0.16 + 0.22 * float(role.get("att", 0.0))
	if bool(ratings.get("individualist", false)):
		base += 0.16
	if bool(ratings.get("team_player", false)):
		base -= 0.09
	base += 0.10 * (float(ratings.get("ego", 0.5)) - 0.5)
	return rng.randf() < clampf(base, 0.03, 0.62)


# --- discipline, injuries, substitutions ---------------------------------


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
	team["fouls"] = int(team["fouls"]) + 1

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
	_build_wheels(team)


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
		if bool((unit["ratings"] as Dictionary).get("professional", false)):
			risk *= 0.85
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

	if int(team["subs_left"]) > 0:
		_substitute(team, victim, ctx, minute, true)
	else:
		_close_unit(victim, minute)
		team["on_field"].erase(victim)
		team["men_down"] = int(team["men_down"]) + 1
		_build_wheels(team)


static func _consider_fatigue_subs(
	team: Dictionary,
	_opponent: Dictionary,
	ctx: Dictionary,
	minute: int
) -> void:
	if int(team["subs_left"]) < 1 or (team["bench"] as Array).is_empty():
		return
	var worst: Dictionary = {}
	var worst_fresh := 1.0
	for unit in team["on_field"]:
		if bool((unit["ratings"] as Dictionary).get("is_gk", false)):
			continue
		var fresh := float(unit["fresh"])
		if fresh < worst_fresh:
			worst_fresh = fresh
			worst = unit
	if worst.is_empty() or worst_fresh > 0.78:
		return
	_substitute(team, worst, ctx, minute, false)


static func _substitute(
	team: Dictionary,
	unit: Dictionary,
	ctx: Dictionary,
	minute: int,
	forced: bool,
	reason: String = "fatigue"
) -> void:
	var bench: Array = team["bench"]
	if bench.is_empty() or int(team["subs_left"]) < 1:
		return
	var slot := str(unit["slot"])
	var need_gk := bool((unit["ratings"] as Dictionary).get("is_gk", false))
	var best_index := -1
	var best_score := -1.0
	for i in bench.size():
		var candidate: Dictionary = bench[i]
		var candidate_ratings := MatchRatings.of(candidate)
		var position := str(candidate_ratings.get("position", PlayerTypes.POS_CM))
		if need_gk != bool(candidate_ratings.get("is_gk", false)):
			continue
		var score := LineupSelectorScript.role_value(candidate_ratings, slot, str(team["style"])) \
			* MatchTypesScript.slot_fit(slot, position)
		score *= MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(candidate))
		if score > best_score:
			best_score = score
			best_index = i
	if best_index < 0:
		return
	if not forced:
		var current := LineupSelectorScript.role_value(unit["ratings"], slot, str(team["style"])) \
			* float(unit["fit"]) * float(unit["fresh"])
		if best_score <= current * 1.02:
			return

	var incoming: Dictionary = bench[best_index]
	bench.remove_at(best_index)
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
	_build_wheels(team)

	var event := _log(ctx, minute, MatchTypesScript.EVENT_SUB, team, fresh_unit["entry"])
	event["out"] = str((unit["entry"] as Dictionary)["name"])
	event["forced"] = forced
	event["reason"] = "injury" if forced else reason


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


static func _apply_fatigue(team: Dictionary, scale: float) -> void:
	for unit in team["on_field"]:
		unit["fresh"] = maxf(float(unit["fresh"]) - float(unit["drain"]) * scale, 0.42)
		unit["entry"]["intensity_minutes"] += MatchTypesScript.PHASE_MINUTES * float(team["intensity"])


# --- shootout ------------------------------------------------------------


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


static func _touch(skill: float, unit: Dictionary, rng: RandomNumberGenerator, knobs: Dictionary) -> float:
	var ratings: Dictionary = unit.get("ratings", {})
	var spread := float(knobs.get("team_form_spread", MatchTypesScript.TEAM_FORM_SPREAD))
	var wobble := rng.randfn(0.0, float(ratings.get("variance", 0.08)) * spread)
	return clampf(skill + wobble, 0.02, 1.0)


static func _coach_edge(team: Dictionary) -> float:
	return (float(int(team.get("tactics", 10))) - 10.0) / 20.0 * 0.10


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
	var keeper_skill := 0.45
	if not keeper.is_empty():
		keeper_skill = float((keeper["ratings"] as Dictionary).get("gk_penalty", 0.45))
	var skill := float(ratings.get("penalty", 0.5))
	if bool(ratings.get("ice_cold", false)):
		skill += 0.07
	skill += 0.06 * (float(ratings.get("pressure", 0.5)) - 0.5)
	var knobs: Dictionary = ctx.get("knobs", {})
	var chance := clampf(
		float(knobs.get("penalty_conversion_base", MatchTypesScript.PENALTY_CONVERSION_BASE))
			+ 0.30 * (skill - 0.5) - 0.22 * (keeper_skill - 0.5),
		0.40,
		0.95
	)
	var entry: Dictionary = unit["entry"]
	if rng.randf() < chance:
		entry["shootout_scored"] = int(entry["shootout_scored"]) + 1
		return true
	entry["shootout_missed"] = int(entry["shootout_missed"]) + 1
	if not keeper.is_empty() and rng.randf() < 0.5:
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
	return {
		"club_id": int(team["club_id"]),
		"coach_id": int(team["coach_id"]),
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


static func _best_on_field(team: Dictionary, key: String) -> Dictionary:
	var best: Dictionary = {}
	var best_value := -1.0
	for unit in team["on_field"]:
		var ratings: Dictionary = unit["ratings"]
		if bool(ratings.get("is_gk", false)):
			continue
		var value := float(ratings.get(key, 0.0))
		if value > best_value:
			best_value = value
			best = unit
	return best


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


static func _sample_poisson(lambda: float, rng: RandomNumberGenerator) -> int:
	if lambda <= 0.0:
		return 0
	var limit := exp(-lambda)
	var product := rng.randf()
	var count := 0
	while product > limit and count < 8:
		count += 1
		product *= rng.randf()
	return count


static func _lineup_ability(lineup: Dictionary) -> float:
	var starters: Array = lineup.get("starters", [])
	if starters.is_empty():
		return 0.0
	var total := 0.0
	for record in starters:
		var player: Dictionary = record["player"]
		total += float(MatchRatings.of(player).get("ability", 0.5)) * 100.0 \
			* float(record["fit"]) \
			* MatchSimConfigScript.condition_play_mult(PlayerConditionScript.condition_of(player))
	return total / float(starters.size())


## The lineup gap is the match. Eighteen ability points is a clear chance edge.
static func _squad_factor(team: Dictionary, opponent: Dictionary) -> float:
	var gap := clampf(
		(float(team.get("ability", 50.0)) - float(opponent.get("ability", 50.0))) / 45.0,
		-1.0,
		1.0
	)
	return clampf(1.0 + gap * 0.18, 0.78, 1.22)


## Tactics is the plan against this opponent. Equal coaches change nothing.
static func _coach_factor(team: Dictionary, opponent: Dictionary) -> float:
	var delta := (float(int(team.get("tactics", 10))) - float(int(opponent.get("tactics", 10)))) / 20.0
	return clampf(1.0 + delta * 0.34, 0.72, 1.38)


## A bad day nudges the team. It does not overturn the squad or the coach.
static func _day_form(_rng: RandomNumberGenerator, _knobs: Dictionary) -> float:
	return 1.0


static func _home_bonus(spec: Dictionary, knobs: Dictionary) -> float:
	var reputation := clampf(float(spec.get("reputation", 500)) / 1000.0, 0.0, 1.0)
	return float(knobs.get("home_advantage", MatchTypesScript.HOME_ADVANTAGE)) \
		+ float(knobs.get("home_reputation_bonus", MatchTypesScript.HOME_REPUTATION_BONUS)) * reputation


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
