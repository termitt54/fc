class_name YouthGraduation
extends RefCounted
## Off-season: 18+ leave the academy for first team, reserve, or the market.


const PlayerTypesScript := preload("res://game/player_types.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")

const RESERVE_CAP := 12
const RESERVE_MAX_AGE := 21
const MIN_PRICE_FACTOR := 0.55
const RESERVE_WAGE_FACTOR := 0.45

const DEST_FIRST := "first_team"
const DEST_RESERVE := "reserve"
const DEST_LISTED := "listed"
const DEST_MARKET := "market"


static func starter_count(formation: String, position: String) -> int:
	var pos := PlayerTypesScript.normalize_position(position)
	var n := 0
	for slot in TacticTypesScript.starting_xi(formation):
		if str(slot) == pos:
			n += 1
	return maxi(1, n)


static func is_starter(player: Dictionary, incumbents: Array, formation: String) -> bool:
	var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	var cap := starter_count(formation, pos)
	var same: Array = []
	for other in incumbents:
		if typeof(other) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(other.get("position", ""))) != pos:
			continue
		same.append(other)
	same.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("current_ability", 0)) > int(b.get("current_ability", 0))
	)
	var pid := int(player.get("id", 0))
	for i in mini(cap, same.size()):
		if int(same[i].get("id", 0)) == pid:
			return true
	return false


static func expendable_at_position(
	incumbents: Array,
	position: String,
	challenger_pa: int,
	formation: String
) -> Array:
	var pos := PlayerTypesScript.normalize_position(position)
	var out: Array = []
	for player in incumbents:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(player.get("position", ""))) != pos:
			continue
		if int(player.get("potential_ability", 0)) >= challenger_pa:
			continue
		if is_starter(player, incumbents, formation):
			continue
		out.append(player)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("current_ability", 0)) < int(b.get("current_ability", 0))
	)
	return out


static func can_fill_vacancy(squad: Array, position: String) -> bool:
	if squad.size() >= PlayerTypesScript.SQUAD_SIZE:
		return false
	var pos := PlayerTypesScript.normalize_position(position)
	var count := 0
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(player.get("position", ""))) == pos:
			count += 1
	if count < int(PlayerTypesScript.SQUAD_SLOT_MIN.get(pos, 0)):
		return true
	return PlayerTypesScript.can_add_squad_position(squad, pos)


static func has_weaker_protected_starters(
	incumbents: Array,
	position: String,
	challenger_pa: int,
	formation: String
) -> bool:
	var pos := PlayerTypesScript.normalize_position(position)
	for player in incumbents:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if PlayerTypesScript.normalize_position(str(player.get("position", ""))) != pos:
			continue
		if not is_starter(player, incumbents, formation):
			continue
		if int(player.get("potential_ability", 0)) < challenger_pa:
			return true
	return false


static func prepare_first_team(player: Dictionary) -> void:
	player["is_youth"] = false
	player["is_reserve"] = false
	player["for_sale"] = false
	player.erase("asking_price")
	player["contract_status"] = "club"


static func prepare_reserve(player: Dictionary) -> void:
	player["is_youth"] = false
	player["is_reserve"] = true
	player["for_sale"] = false
	player.erase("asking_price")
	player["contract_status"] = "club"
	player["contract_years"] = 1
	var wage := int(player.get("wage", 0))
	player["wage"] = maxi(
		PlayerMarketScript.WAGE_FLOOR,
		int(round(float(wage) * RESERVE_WAGE_FACTOR / 50.0) * 50)
	)


static func prepare_listing(player: Dictionary, min_price: bool) -> void:
	player["is_youth"] = false
	player["is_reserve"] = false
	player["for_sale"] = true
	var floor_price := PlayerMarketScript.VALUE_FLOOR
	var value := maxi(floor_price, int(player.get("value", 0)))
	if min_price:
		player["asking_price"] = maxi(
			floor_price, int(round(float(value) * MIN_PRICE_FACTOR / 1000.0) * 1000)
		)
	else:
		player["asking_price"] = value
	player["contract_status"] = "club"


static func destination_for_graduate(
	player: Dictionary,
	squad: Array,
	reserve: Array,
	formation: String
) -> Dictionary:
	var pos := PlayerTypesScript.normalize_position(str(player.get("position", "")))
	var pa := int(player.get("potential_ability", 0))
	if can_fill_vacancy(squad, pos):
		return {"dest": DEST_FIRST, "victim": {}}
	var expendable := expendable_at_position(squad, pos, pa, formation)
	if not expendable.is_empty():
		return {"dest": DEST_FIRST, "victim": expendable[0]}
	if reserve.size() < RESERVE_CAP and has_weaker_protected_starters(squad, pos, pa, formation):
		return {"dest": DEST_RESERVE, "victim": {}}
	if reserve.size() < RESERVE_CAP:
		return {"dest": DEST_RESERVE, "victim": {}}
	return {"dest": DEST_MARKET, "victim": {}}
