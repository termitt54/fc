class_name PlayerOffer
extends RefCounted

const Attraction = preload("res://game/club_attraction.gd")
## One player's sporting/financial reservations for every recruitment path.
## Profiles can be built once for a large free-agent pool; no RNG or squad scans.

static func profile(player: Dictionary, world_top_reputation: int = 0) -> Dictionary:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.offer_profile(player,world_top_reputation)
	var result := {"reputation": int(player.get("reputation", 0)), "ability": PlayerMarket.ability_of(player),
		"age": int(player.get("age", 24)), "characters": PlayerTypes.characters_of(player),
		"free_years": int(player.get("free_agent_seasons", 0)), "club_id": int(player.get("club_id", 0)),
		"wage": int(player.get("wage", 0))}
	var ambitious: bool = result["characters"].has(PlayerTypes.CHAR_AMBITIOUS)
	var veteran := minf(float(maxi(0, int(result["age"]) - 31)) * 12.0, 84.0)
	var unemployment := float(mini(int(result["free_years"]), 3)) * 35.0
	result["flexibility"] = 100.0 + veteran + unemployment - (40.0 if ambitious else 0.0)
	result["desired"] = maxf(float(result["reputation"]), sporting_ambition(int(result["ability"]), world_top_reputation))
	result["minimum_club_reputation"] = float(result["desired"]) - float(result["flexibility"])
	result["minimum_squad_ability"] = float(result["ability"]) - (18.0 if ambitious else 25.0) - unemployment / 10.0 - veteran / 10.0
	return result

static func evaluate(player: Dictionary, club: Dictionary, coach: Dictionary, context: Dictionary = {}) -> Dictionary:
	return evaluate_profile(profile(player, int(context.get("world_top_reputation", 0))), club, coach, context)

static func evaluate_profile(player: Dictionary, club: Dictionary, coach: Dictionary, context: Dictionary = {}) -> Dictionary:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.evaluate_offer(player,club,CoachTypes.negotiations_of(coach),context)
	var club_rep := Attraction.value(club)
	var characters: Array = player["characters"]
	var ambitious := characters.has(PlayerTypes.CHAR_AMBITIOUS)
	var talks := float(CoachTypes.negotiations_of(coach) - 10) * 2.0
	var flexibility := float(player["flexibility"]) + talks
	# Unknown/mispriced fame cannot make an elite footballer accept any club.
	var desired := float(player["desired"])
	var staying := bool(context.get("renewal", false))
	if staying:
		flexibility += 100.0
	if staying and characters.has(PlayerTypes.CHAR_LOYAL):
		flexibility += 160.0
	var source_rep := float(context.get("source_reputation", 0))
	var downgrade := source_rep - club_rep
	if desired - club_rep > flexibility:
		return {"accepted": false, "score": -1.0, "reason": "club_prestige"}
	if not staying and source_rep > 0.0 and downgrade > flexibility + (0.0 if ambitious else 80.0):
		return {"accepted": false, "score": -1.0, "reason": "sporting_downgrade"}
	var quality := float(context.get("squad_ability", -1.0))
	if quality >= 0.0 and quality < float(player["minimum_squad_ability"]):
		return {"accepted": false, "score": -1.0, "reason": "squad_level"}
	var offer := float(context.get("offer_wage", -1))
	var salary_floor := float(player["wage"]) * (0.90 if characters.has(PlayerTypes.CHAR_MERCENARY) else 0.70)
	if offer >= 0.0 and offer < salary_floor:
		return {"accepted": false, "score": -1.0, "reason": "salary"}
	var role := str(context.get("role", "rotation"))
	var role_bonus := 20.0 if role == "first_team" else (-20.0 if role == "reserve" else 0.0)
	return {"accepted": true, "reason": "acceptable", "score": club_rep * 0.5 + maxf(quality, 0.0) + role_bonus - maxf(downgrade, 0.0) * 0.10}


## Ability sets sporting ambitions without granting unearned public fame.
static func sporting_reputation(ability: int) -> float:
	return clampf(float(ability) * 8.0 if ability <= 50 else 400.0 + float(ability - 50) * 14.0, 0.0, 1000.0)



## A sporting ambition must refer to clubs that exist in this world. Public fame
## remains an independent lower bound: a famous player can still demand more.
static func sporting_ambition(ability: int, world_top_reputation: int = 0) -> float:
	var desired := sporting_reputation(ability)
	if world_top_reputation > 0:
		desired = minf(desired, float(world_top_reputation) + 60.0)
	return desired

static func world_top_reputation(clubs: Dictionary) -> int:
	var top := 0
	for club in clubs.values():
		top = maxi(top, int(round(Attraction.value(club))))
	return top
