class_name LineupSelector
extends RefCounted
## Picks the matchday 18, the starting GK+7 for a formation and the bench.
## Availability (injuries, bans) wins over ability; condition and morale bias the choice.


const MatchTypesScript := preload("res://game/match_types.gd")
const MatchSimConfigScript := preload("res://game/match_simulation_config.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerConditionScript := preload("res://game/player_condition.gd")

## Weights sum to one; general ability remains relevant in every role.
const ROLE_WEIGHTS := {
	"GK": {"gk_stop": 0.65, "gk_aerial": 0.20, "gk_one_on_one": 0.15},
	"CB": {"defend": 0.65, "aerial": 0.20, "poise": 0.15},
	"FB": {"defend": 0.45, "press": 0.20, "pace": 0.20, "create": 0.15},
	"CM": {"create": 0.60, "poise": 0.20, "defend": 0.20},
	"WM": {"create": 0.35, "dribble": 0.25, "pace": 0.20, "press": 0.20},
	"WF": {"dribble": 0.35, "off_ball": 0.25, "finish": 0.25, "pace": 0.15},
	"ST": {"finish": 0.60, "off_ball": 0.25, "aerial": 0.15},
}
const STYLE_WEIGHTS := {
	"control": {"create": 0.60, "poise": 0.25, "dribble": 0.15},
	"tiki_taka": {"create": 0.65, "dribble": 0.20, "poise": 0.15},
	"pressing": {"press": 0.45, "endurance": 0.35, "defend": 0.20},
	"vertical": {"pace": 0.35, "create": 0.35, "off_ball": 0.30},
	"kick_rush": {"aerial": 0.45, "pace": 0.30, "off_ball": 0.25},
	"park_bus": {"defend": 0.55, "poise": 0.25, "endurance": 0.20},
	"counter": {"pace": 0.40, "off_ball": 0.35, "create": 0.25},
}

## Unmodified by condition/fit so the same role value can be used for substitutes.
static func role_value(ratings: Dictionary, slot: String, style: String) -> float:
	var role := _role_rating(ratings, slot)
	if slot == "GK":
		return 100.0 * (0.35 * float(ratings.get("ability", 0.5)) + 0.65 * role)
	var style_value := _style_rating(ratings, style)
	return 100.0 * (0.35 * float(ratings.get("ability", 0.5)) + 0.45 * role + 0.20 * style_value)

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
		values[style] = _weighted_rating(ratings, STYLE_WEIGHTS.get(style, STYLE_WEIGHTS["control"]))
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
	var formation := str(plan.get("formation", TacticTypesScript.FORM_232))
	if not TacticTypesScript.is_formation(formation):
		formation = TacticTypesScript.FORM_232
	var slots: Array = TacticTypesScript.starting_xi(formation)

	var pool := _available_pool(squad)
	var used_youth := 0
	if pool.size() < slots.size():
		var reserves := _available_pool(youth)
		reserves.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(MatchRatings.of(a).get("ability", 0.0)) > float(MatchRatings.of(b).get("ability", 0.0))
		)
		for player in reserves:
			if pool.size() >= slots.size():
				break
			pool.append(player)
			used_youth += 1

	var noise := _decision_noise(coach)
	var style := str(plan.get("style", TacticTypesScript.STYLE_CONTROL))
	if not TacticTypesScript.is_style(style):
		style = TacticTypesScript.STYLE_CONTROL
	var rated := _rate_pool(pool, slots, style)
	var positions: PackedStringArray = rated["positions"]
	var scores: Dictionary = rated["scores"]
	var count := pool.size()
	var taken := []
	taken.resize(count)
	taken.fill(false)

	var starters: Array = []
	for slot_index in _slot_order(slots, positions):
		var slot := str(slots[slot_index])
		# Only a handful of distinct positions per slot, so fits are reused.
		var fit_by_position: Dictionary = {}
		var best := -1
		var best_score := -1.0
		var best_fit := 0.0
		for i in count:
			if taken[i]:
				continue
			var position := positions[i]
			var fit: float = fit_by_position.get(position, -1.0)
			if fit < 0.0:
				fit = MatchTypesScript.slot_fit(slot, position)
				fit_by_position[position] = fit
			# Keep goalkeepers out of field roles while an outfielder is available.
			if slot != "GK" and position == "GK" and _has_outfielder(positions, taken):
				continue
			var score := float(scores[slot][i]) * fit
			if noise > 0.0:
				score *= 1.0 + rng.randf_range(-noise, noise)
			if score > best_score:
				best_score = score
				best = i
				best_fit = fit
		if best < 0:
			continue
		taken[best] = true
		starters.append({
			"player": pool[best],
			"slot": slot,
			"fit": best_fit,
			"selection_score": best_score,
		})

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
		if taken[i] or positions[i] == "GK":
			continue
		var best_score := 0.0
		for slot in scores:
			if slot != "GK":
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
	for slot in slots:
		scores[slot] = PackedFloat32Array()
	for player in pool:
		var ratings := MatchRatings.of(player)
		var select := MatchSimConfigScript.condition_select_mult(PlayerConditionScript.condition_of(player))
		var morale := 0.94 + 0.12 * (float(PlayerConditionScript.morale_of(player)) / float(MatchTypesScript.MORALE_MAX))
		positions.append(str(ratings.get("position", PlayerTypes.POS_CM)))
		var common := 0.35 * float(ratings.get("ability", 0.5)) + 0.20 * _style_rating(ratings, style)
		for slot in scores:
			var values: PackedFloat32Array = scores[slot]
			var value := role_value(ratings, slot, style) if slot == "GK" else \
				100.0 * (common + 0.45 * _role_rating(ratings, slot))
			values.append(value * select * morale)
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


static func _decision_noise(_coach: Dictionary) -> float:
	return 0.0

