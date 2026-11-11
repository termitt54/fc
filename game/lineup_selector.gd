class_name LineupSelector
extends RefCounted
## Picks the matchday 20, the starting GK+7 for a formation and the bench.
## Availability (injuries, bans) wins over ability; condition and morale bias the choice.


const MatchTypesScript := preload("res://game/match_types.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")

## Weights sum to one; only role-specific skills determine footballing suitability.
const ROLE_WEIGHTS := {
	"GK":{"gk_stop":0.65,"gk_aerial":0.20,"gk_one_on_one":0.15},
	"CB":{"defend":0.60,"aerial":0.20,"create":0.20},
	"CM":{"create":0.50,"poise":0.20,"defend":0.15,"finish":0.15},
	"ST":{"finish":0.55,"off_ball":0.20,"dribble":0.15,"aerial":0.10},
}
const STYLE_WEIGHTS := {"attacking":{},"defensive":{}}

## Unmodified by condition/fit so the same role value can be used for substitutes.
static func role_value(ratings: Dictionary, slot: String, style: String) -> float:
	if not ratings.has("_selection_values"):
		ratings["_selection_values"] = {}
	var styles: Dictionary = ratings["_selection_values"]
	if not styles.has(style):
		styles[style] = {}
	var values: Dictionary = styles[style]
	if values.has(slot):
		return float(values[slot])
	var value := 100.0 * _role_rating(ratings,slot)
	values[slot] = value
	return value

## Lives inside MatchRatings' existing cache, invalidated and stripped with it.
static func _role_rating(ratings: Dictionary, slot: String) -> float:
	if not ratings.has("_selection_roles"):
		ratings["_selection_roles"] = {}
	var values: Dictionary = ratings["_selection_roles"]
	if not values.has(slot):
		values[slot] = _weighted_rating(ratings, ROLE_WEIGHTS.get(slot, ROLE_WEIGHTS["CM"]))
	return float(values[slot])

static func _style_rating(ratings: Dictionary, style: String) -> float:
	if not ratings.has("_selection_styles"):
		ratings["_selection_styles"] = {}
	var values: Dictionary = ratings["_selection_styles"]
	if not values.has(style):
		values[style] = _weighted_rating(ratings, STYLE_WEIGHTS.get(style, STYLE_WEIGHTS["attacking"]))
	return float(values[style])

static func _weighted_rating(ratings: Dictionary, weights: Dictionary) -> float:
	var value := 0.0
	for key in weights:
		value += float(ratings.get(key, 0.5)) * float(weights[key])
	return value


static func build(
	squad: Array,
	youth: Array,
	coach: Dictionary,
	plan: Dictionary,
	rng: RandomNumberGenerator,
	include_bench: bool = true
) -> Dictionary:
	var native: Variant = NativeSimulation.core()
	if native != null:
		return native.build_lineup(squad,youth,coach,plan,rng,include_bench)
	var formation := str(plan.get("formation", TacticTypesScript.FORM_232))
	if not TacticTypesScript.is_formation(formation):
		formation = TacticTypesScript.FORM_232
	var slots: Array = TacticTypesScript.starting_xi(formation)

	var pool := _available_pool(squad)
	var used_youth := 0
	var keepers := 0
	for player in pool:
		if PlayerTypes.normalize_position(str(player.get("position", ""))) == PlayerTypes.POS_GK:
			keepers += 1
			if keepers >= 2:
				break
	if pool.size() < slots.size() or keepers < 2:
		var selected_ids := {}
		for player in pool:
			selected_ids[int(player.get("id", 0))] = true
		var reserves := _available_pool(youth)
		reserves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return role_value(MatchRatings.of(a), str(a.get("position", "CM")), "attacking") > role_value(MatchRatings.of(b), str(b.get("position", "CM")), "attacking")
		)
		# A full outfield pool is not a reason to play without a goalkeeper.
		# Cover the start and one emergency reserve; national squads supply no youth.
		for player in reserves:
			if keepers >= 2:
				break
			var id := int(player.get("id", 0))
			if selected_ids.has(id) or PlayerTypes.normalize_position(str(player.get("position", ""))) != PlayerTypes.POS_GK:
				continue
			pool.append(player)
			selected_ids[id] = true
			keepers += 1
			used_youth += 1
		for player in reserves:
			if pool.size() >= slots.size():
				break
			var id := int(player.get("id", 0))
			if selected_ids.has(id):
				continue
			pool.append(player)
			selected_ids[id] = true
			used_youth += 1

	var noise := _decision_noise(coach)
	var style := str(plan.get("style", TacticTypesScript.STYLE_CONTROL))
	if not TacticTypesScript.is_style(style):
		style = TacticTypesScript.STYLE_CONTROL
	var rated := _rate_pool(pool, slots, style)
	var positions: PackedStringArray = rated["positions"]
	var scores: Dictionary = rated["scores"]
	var count := pool.size()
	var outfield_count := 0
	for position in positions: outfield_count+=int(position!="GK")
	var taken := []
	taken.resize(count)
	taken.fill(false)
	var weights: Array = []
	for slot in slots:
		var row := PackedFloat64Array()
		for j in maxi(count,slots.size()):
			var value := 0.0
			if j<count:
				value=maxf(0.0001,float(scores[slot][j])*MatchTypesScript.slot_fit(str(slot),positions[j]))
				if str(slot)!="GK" and positions[j]=="GK" and outfield_count>=slots.size()-1: value=-1000000
				elif noise>0: value*=1.0+rng.randf_range(-noise,noise)
			elif str(slot)=="GK" and count>0: value=-1000000
			row.append(value)
		weights.append(row)
	var assignment: PackedInt32Array=load("res://game/lineup_assignment.gd").solve(weights)
	var starters: Array = []
	for row in slots.size():
		var selected: int=assignment[row]
		if selected<0 or selected>=count: continue
		taken[selected]=true
		starters.append({"player":pool[selected],"slot":str(slots[row]),
			"fit":MatchTypesScript.slot_fit(str(slots[row]),positions[selected]),"selection_score":float(weights[row][selected])})

	var lineup := {
		"formation": formation, "style": style, "starters": starters, "bench": [],
		"short": starters.size() < slots.size(), "used_youth": used_youth,
		"_bench_context": {"pool": pool, "positions": positions, "taken": taken, "scores": scores},
	}
	return finish_bench(lineup) if include_bench else lineup


## Preparation compares starting teams, then fills only the chosen bench.
static func finish_bench(lineup: Dictionary) -> Dictionary:
	var context: Dictionary = lineup.get("_bench_context", {})
	if not context.is_empty():
		lineup["bench"] = _build_bench(context["pool"], context["positions"], context["taken"], context["scores"])
		lineup.erase("_bench_context")
	return lineup

static func _build_bench(pool: Array, positions: PackedStringArray, taken: Array, scores: Dictionary) -> Array:
	var count := pool.size()
	var bench: Array = []
	# Reserve a keeper first, then cover every distinct field role of this plan.
	var keeper := _best_cover("GK", positions, taken, scores)
	if keeper >= 0:
		taken[keeper] = true
		bench.append(pool[keeper])
	for slot in scores:
		if slot == "GK":
			continue
		var cover := _best_cover(slot, positions, taken, scores)
		if cover >= 0:
			taken[cover] = true
			bench.append(pool[cover])
	var rest: Array = []
	var rest_scores: Dictionary = {}
	for i in count:
		if taken[i]:
			continue
		var best_score := 0.0
		for slot in scores:
			if (slot == "GK") == (positions[i] == "GK"):
				best_score = maxf(best_score, float(scores[slot][i]) * MatchTypesScript.slot_fit(slot, positions[i]))
		rest.append(i)
		rest_scores[i] = best_score
	rest.sort_custom(func(a: int, b: int) -> bool: return rest_scores[a] > rest_scores[b])
	for i in rest:
		if bench.size() >= TacticTypesScript.MATCH_BENCH:
			break
		bench.append(pool[i])

	return bench


static func available_count(squad: Array) -> int:
	var count := 0
	for player in squad:
		if typeof(player) == TYPE_DICTIONARY and PlayerConditionScript.is_available(player):
			count += 1
	return count


static func _available_pool(players: Array) -> Array:
	var pool: Array = []
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		PlayerConditionScript.ensure_state(player)
		if PlayerConditionScript.is_available(player):
			pool.append(player)
	return pool


## Cache candidate scores per distinct role; calculate style contribution once.
static func _rate_pool(pool: Array, slots: Array, style: String) -> Dictionary:
	var positions := PackedStringArray()
	var scores: Dictionary = {}
	# Keep the original unique-slot insertion order and float32 rounding.
	for slot in slots:
		scores[slot] = null
	var prepared: Array = []
	for player in pool:
		var ratings := MatchRatings.of(player)
		var select := MatchSimConfigScript.condition_select_mult(PlayerConditionScript.condition_of(player))
		var morale := 0.94 + 0.12 * (float(PlayerConditionScript.morale_of(player)) / float(MatchTypesScript.MORALE_MAX))
		positions.append(str(ratings.get("position", PlayerTypes.POS_CM)))
		var common := (4.0/13.0) * _style_rating(ratings, style)
		prepared.append([ratings,select,morale,common,
			float(player.get("_national_form_bonus", 0.0)) if bool(player.get("_national_selection", false)) else 0.0,
			bool(player.get("_national_selection", false))])
	# Append outside the dictionary: PackedFloat32Array is copy-on-write.
	# Fetching it from scores for every player copied the growing array repeatedly.
	for slot in scores:
		var values := PackedFloat32Array()
		for row in prepared:
			var ratings: Dictionary = row[0]
			var value := role_value(ratings, slot, style)
			if bool(row[5]):
				value += float(row[4])
			values.append(value * float(row[1]) * float(row[2]))
		scores[slot] = values
	return {"positions": positions, "scores": scores}

static func _has_outfielder(positions: PackedStringArray, taken: Array) -> bool:
	for i in positions.size():
		if not taken[i] and positions[i] != "GK":
			return true
	return false

static func _best_cover(slot: String, positions: PackedStringArray, taken: Array,
	scores: Dictionary) -> int:
	var best := -1
	var best_score := -1.0
	for i in positions.size():
		if taken[i] or positions[i] != slot:
			continue
		var score := float(scores[slot][i]) * MatchTypesScript.slot_fit(slot, positions[i])
		if score > best_score:
			best = i
			best_score = score
	return best


## Scarce slots are filled first so a lone goalkeeper never ends up at wing-back.
static func _slot_order(slots: Array, positions: PackedStringArray) -> Array:
	var natives: Dictionary = {}
	for position in positions:
		natives[position] = int(natives.get(position, 0)) + 1
	var order: Array = []
	for i in slots.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var slot_a := str(slots[a])
		var slot_b := str(slots[b])
		var count_a := int(natives.get(slot_a, 0))
		var count_b := int(natives.get(slot_b, 0))
		if count_a != count_b:
			return count_a < count_b
		return a < b
	)
	return order


static func _decision_noise(coach: Dictionary) -> float:
	if bool(coach.get("national_selection", false)):
		return CoachTypes.selection_uncertainty(coach) * 0.20
	return 0.0

