class_name ContractRenewal
extends RefCounted
## Off-season contract tick: −1 year, then keep / renew / release to free agents.


const PlayerTypesScript := preload("res://game/player_types.gd")
const PlayerGeneratorScript := preload("res://game/player_generator.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")
const Offer := preload("res://game/player_offer.gd")

const REASON_RENEWED := "renewed"
const REASON_RELEASED := "released"
const REASON_YOUTH_KEPT := "youth_kept"
const REASON_ACTIVE := "active"


static func tick_years(entity: Dictionary) -> int:
	var years := maxi(0, int(entity.get("contract_years", 0)) - 1)
	entity["contract_years"] = years
	return years


static func stay_chance(player: Dictionary, club: Dictionary, coach: Dictionary, context: Dictionary = {}) -> float:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.contract_chance(player,club,CoachTypesScript.negotiations_of(coach),context)
	var club_rep := Offer.Attraction.value(club)
	var player_rep := float(clampi(int(player.get("reputation", 0)), 0, 1000))
	var gap := player_rep - club_rep
	var willingness := Offer.evaluate(player, club, coach, {"renewal": true, "offer_wage": renewal_wage(player, context), "world_top_reputation": int(context.get("world_top_reputation", 0))})
	if not bool(willingness["accepted"]):
		return 0.0
	var chance := 0.62 - clampf(gap / 400.0, -0.25, 0.45)
	var characters: Array = PlayerTypesScript.characters_of(player)
	if PlayerTypesScript.CHAR_LOYAL in characters:
		chance += 0.18
	if PlayerTypesScript.CHAR_AMBITIOUS in characters and gap > 50.0:
		chance -= 0.12
	if PlayerTypesScript.CHAR_MERCENARY in characters:
		var wage := float(maxi(0, int(player.get("wage", 0))))
		var expected := float(PlayerMarketScript.expected_wage_of(player))
		if expected > 0.0 and wage < expected * 0.9:
			chance -= 0.12
	var talks := float(CoachTypesScript.negotiations_of(coach))
	chance += (talks - 10.0) * 0.025
	if bool(context.get("key_player", false)):
		chance += 0.15
	return clampf(chance, 0.08, 0.97)


static func roll_new_years(rng: RandomNumberGenerator, player: Dictionary) -> int:
	return PlayerGeneratorScript._roll_contract_years(
		rng,
		int(player.get("age", 24)),
		int(player.get("current_ability", player.get("overall", 50)))
	)


static func process_player(
	player: Dictionary,
	club: Dictionary,
	coach: Dictionary,
	rng: RandomNumberGenerator,
	context: Dictionary = {}
) -> String:
	if bool(player.get("is_youth", false)):
		tick_years(player)
		if int(player.get("contract_years", 0)) < 1:
			player["contract_years"] = rng.randi_range(1, 3)
		player["contract_status"] = "club"
		return REASON_YOUTH_KEPT if int(player.get("contract_years", 0)) > 0 else REASON_RELEASED

	var years := tick_years(player)
	var early := years == 1 and bool(context.get("key_player", false))
	if years > 0 and not early:
		return REASON_ACTIVE
	var offered_wage := renewal_wage(player, context)
	if _wants_to_stay(player, club, coach, rng.randf(), context):
		player["contract_years"] = maxi(2 if early else 1, roll_new_years(rng, player))
		player["contract_status"] = "club"
		# A fresh deal is signed at today's price, not the one he joined on.
		PlayerMarketScript.reprice_contract(player)
		player["wage"] = offered_wage
		return REASON_RENEWED
	if early:
		return REASON_ACTIVE
	player["contract_years"] = 0
	player["contract_status"] = "free_agent"
	player["club_id"] = 0
	return REASON_RELEASED


static func _wants_to_stay(player: Dictionary, club: Dictionary, coach: Dictionary, roll: float, context: Dictionary = {}) -> bool:
	var chance := stay_chance(player, club, coach, context)
	return chance > 0.0 and roll < chance


static func renewal_wage(player: Dictionary, context: Dictionary = {}) -> int:
	var expected := PlayerMarketScript.expected_wage_of(player)
	var retained := int(ceil(float(player.get("wage", 0)) * (1.10 if bool(context.get("key_player", false)) else 1.0)))
	return maxi(expected, retained)
