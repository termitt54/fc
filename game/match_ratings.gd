class_name MatchRatings
extends RefCounted
## Derived ratings from the compact 11 + 5 skill model.
## Computed once per player and cached until development changes his ability:
## this is what keeps a 500-match day inside the frame budget.


const CACHE_KEY := "_match_ratings"

const MIX := {
	"create": [["technical", "passing", 4.0], ["technical", "technique", 2.0]],
	"dribble": [["technical", "dribbling", 4.0], ["physical", "pace", 1.0], ["technical", "technique", 1.0]],
	"finish": [["technical", "finishing", 4.0], ["technical", "technique", 1.0]],
	"aerial": [["physical", "strength", 1.0]],
	"defend": [["technical", "defending", 4.0], ["physical", "strength", 1.0]],
	"press": [["technical", "defending", 2.0], ["physical", "stamina", 2.0], ["physical", "pace", 1.0]],
	"pace": [["physical", "pace", 1.0]],
	"endurance": [["physical", "stamina", 1.0]],
	"set_piece": [["set_pieces", "delivery", 1.0]],
	"penalty": [["set_pieces", "penalties", 1.0]],
	"off_ball": [["technical", "technique", 1.0], ["technical", "finishing", 1.0], ["physical", "pace", 1.0]],
	"poise": [["technical", "technique", 1.0]],
}

const GK_MIX := {
	"gk_stop": [["goalkeeping", "reflexes", 3.5], ["goalkeeping", "handling", 2.5], ["goalkeeping", "positioning", 2.5]],
	"gk_one_on_one": [["goalkeeping", "exits", 1.0]],
	"gk_aerial": [["goalkeeping", "aerial_reach", 2.5], ["goalkeeping", "handling", 1.5]],
	"gk_penalty": [["goalkeeping", "reflexes", 2.0], ["goalkeeping", "exits", 2.0], ["goalkeeping", "positioning", 1.5]],
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
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.build_ratings(player)
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
			out[key] = 0.05

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

	# Character is the only personality source; no hidden numeric scales.
	out["pressure"] = 0.5
	out["ego"] = 0.5
	out["foul_risk"] = 0.85 if hot_head else 0.3
	var variance := 0.10
	if out["inconsistent"]:
		variance += 0.11
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
