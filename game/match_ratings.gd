class_name MatchRatings
extends RefCounted
## Derived match ratings (0..1) folded out of the 34 raw attributes.
## Computed once per player and cached until development changes his ability:
## this is what keeps a 500-match day inside the frame budget.


const CACHE_KEY := "_match_ratings"

const MIX := {
	"create": [
		["technical", "passing", 3.0],
		["mental", "vision", 3.0],
		["mental", "decisions", 2.0],
		["technical", "technique", 2.0],
		["technical", "first_touch", 2.0],
	],
	"dribble": [
		["technical", "dribbling", 3.0],
		["physical", "agility", 2.0],
		["physical", "balance", 1.5],
		["physical", "acceleration", 1.5],
		["technical", "technique", 1.0],
	],
	"finish": [
		["technical", "finishing", 4.0],
		["mental", "composure", 2.0],
		["technical", "technique", 1.5],
		["technical", "first_touch", 1.0],
	],
	"long_shot": [
		["set_pieces", "long_shots", 3.0],
		["technical", "technique", 1.5],
		["physical", "strength", 1.0],
	],
	"aerial": [
		["physical", "strength", 2.5],
		["mental", "bravery", 1.5],
		["physical", "balance", 1.0],
	],
	"defend": [
		["technical", "tackling", 3.0],
		["technical", "marking", 3.0],
		["mental", "anticipation", 2.5],
		["mental", "concentration", 2.0],
		["physical", "strength", 1.5],
	],
	"press": [
		["mental", "work_rate", 3.0],
		["physical", "stamina", 2.5],
		["mental", "anticipation", 1.5],
		["physical", "pace", 1.5],
	],
	"pace": [
		["physical", "pace", 2.0],
		["physical", "acceleration", 2.0],
	],
	"endurance": [
		["physical", "stamina", 3.0],
		["mental", "work_rate", 1.0],
	],
	"set_piece": [
		["set_pieces", "corners", 2.0],
		["set_pieces", "free_kicks", 2.0],
		["technical", "crossing", 1.5],
	],
	"penalty": [
		["set_pieces", "penalties", 3.0],
		["mental", "composure", 2.0],
	],
	"off_ball": [
		["mental", "off_the_ball", 3.0],
		["mental", "anticipation", 1.5],
	],
	"poise": [
		["mental", "composure", 2.0],
		["mental", "concentration", 1.5],
		["mental", "decisions", 1.5],
	],
}

const GK_MIX := {
	"gk_stop": [
		["goalkeeping", "reflexes", 3.5],
		["goalkeeping", "handling", 2.5],
		["goalkeeping", "positioning", 2.5],
		["mental", "concentration", 1.5],
		["physical", "agility", 1.0],
	],
	"gk_one_on_one": [
		["goalkeeping", "one_on_ones", 3.0],
		["goalkeeping", "rushing_out", 1.5],
		["mental", "bravery", 1.5],
	],
	"gk_aerial": [
		["goalkeeping", "aerial_reach", 2.5],
		["goalkeeping", "handling", 1.5],
		["goalkeeping", "communication", 1.0],
	],
	"gk_penalty": [
		["goalkeeping", "reflexes", 2.0],
		["goalkeeping", "one_on_ones", 2.0],
		["mental", "concentration", 1.5],
	],
}


static func of(player: Dictionary) -> Dictionary:
	var stamp := _stamp(player)
	var cached: Variant = player.get(CACHE_KEY, null)
	if typeof(cached) == TYPE_DICTIONARY and int((cached as Dictionary).get("stamp", -1)) == stamp:
		return cached
	var built := _build(player, stamp)
	player[CACHE_KEY] = built
	return built


static func invalidate(player: Dictionary) -> void:
	player.erase(CACHE_KEY)


static func strip_cache(players: Array) -> void:
	for player in players:
		if typeof(player) == TYPE_DICTIONARY:
			(player as Dictionary).erase(CACHE_KEY)


static func _stamp(player: Dictionary) -> int:
	return int(player.get("current_ability", 0)) * 1000 + int(player.get("age", 0))


static func _build(player: Dictionary, stamp: int) -> Dictionary:
	var attributes: Variant = player.get("attributes", null)
	var attrs: Dictionary = attributes if typeof(attributes) == TYPE_DICTIONARY else {}
	var position := PlayerTypes.normalize_position(str(player.get("position", "")))
	var is_gk := position == PlayerTypes.POS_GK

	var out: Dictionary = {"stamp": stamp, "position": position, "is_gk": is_gk}
	for key in MIX.keys():
		out[key] = _mix(attrs, MIX[key])
	if is_gk:
		for key in GK_MIX.keys():
			out[key] = _mix(attrs, GK_MIX[key])
	else:
		for key in GK_MIX.keys():
			out[key] = 0.25

	var personality: Variant = player.get("personality", null)
	var traits: Dictionary = personality if typeof(personality) == TYPE_DICTIONARY else {}
	var aggression := _scale(int(traits.get("aggression", 10)))
	var temperament := _scale(int(traits.get("temperament", 10)))
	var sportsmanship := _scale(int(traits.get("sportsmanship", 10)))
	out["leadership"] = _scale(int(traits.get("leadership", 10)))
	out["pressure"] = _scale(int(traits.get("pressure", 10)))
	out["ego"] = _scale(int(traits.get("ego", 10)))
	out["professionalism"] = _scale(int(traits.get("professionalism", 10)))

	var characters: Array = PlayerTypes.characters_of(player)
	var hot_head := characters.has(PlayerTypes.CHAR_HOT_HEAD)
	var ice_cold := characters.has(PlayerTypes.CHAR_ICE_COLD)
	out["hot_head"] = hot_head
	out["ice_cold"] = ice_cold
	out["fearless"] = characters.has(PlayerTypes.CHAR_FEARLESS)
	out["inconsistent"] = characters.has(PlayerTypes.CHAR_INCONSISTENT)
	out["individualist"] = characters.has(PlayerTypes.CHAR_INDIVIDUALIST)
	out["team_player"] = characters.has(PlayerTypes.CHAR_TEAM_PLAYER)
	out["professional"] = characters.has(PlayerTypes.CHAR_PROFESSIONAL)
	out["ambitious"] = characters.has(PlayerTypes.CHAR_AMBITIOUS)

	# Rough tackles come from temper, not from being bad at defending.
	var foul := 0.35 + 0.5 * aggression + 0.3 * temperament - 0.25 * sportsmanship
	if hot_head:
		foul += 0.35
	if ice_cold:
		foul -= 0.2
	out["foul_risk"] = clampf(foul, 0.15, 2.1)

	var variance := 0.05 + 0.10 * (1.0 - float(out["poise"]))
	if out["inconsistent"]:
		variance += 0.11
	if out["professional"]:
		variance -= 0.03
	out["variance"] = clampf(variance, 0.03, 0.28)

	out["recovery"] = _scale(PlayerTypes.recovery_of(player))
	out["ability"] = clampf(float(PlayerTypes.ability_of(player)) / 100.0, 0.01, 1.0)
	return out


static func _mix(attrs: Dictionary, spec: Array) -> float:
	var total := 0.0
	var weight := 0.0
	for entry in spec:
		var group: Variant = attrs.get(entry[0], null)
		var value := 10
		if typeof(group) == TYPE_DICTIONARY:
			value = int((group as Dictionary).get(entry[1], 10))
		var w := float(entry[2])
		total += float(clampi(value, PlayerTypes.ATTR_MIN, PlayerTypes.ATTR_MAX)) * w
		weight += w
	if weight <= 0.0:
		return 0.5
	return clampf(total / weight / float(PlayerTypes.ATTR_MAX), 0.02, 1.0)


static func _scale(value: int) -> float:
	return clampf(float(value) / 20.0, 0.0, 1.0)
