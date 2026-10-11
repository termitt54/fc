class_name PlayerMarket
extends RefCounted
## One price scale for players and coaches: salaries, market values, fame drift.
##
## Everything is anchored on the reference prize scale
## (ClubFinance.INCOME_MIN..INCOME_MAX). The curves are calibrated so a squad
## that matches its club's tier costs roughly 10–25% of that scale, which leaves
## the rest for transfers. Both ability and reputation enter as steep power laws:
## ability spans barely 2x between the worst and the best club, so reputation has
## to carry the remaining spread to stretch wages across the 500x prize range.


const PlayerTypesScript := preload("res://game/player_types.gd")

const ABILITY_PIVOT := 50.0
const REPUTATION_PIVOT := 500.0

## Salaries are per season, never weekly.
const WAGE_AT_PIVOT := 16700
const WAGE_ABILITY_EXP := 5.5
const WAGE_REPUTATION_EXP := 2.25
const WAGE_FLOOR := 400
const WAGE_STEP := 100

## Earnings peak in the late twenties: kids sit on rookie terms, veterans take cuts.
const WAGE_AGE_BANDS: Array = [
	[19, 0.55], [21, 0.75], [24, 0.92], [31, 1.00], [33, 0.92], [35, 0.80],
]
const WAGE_AGE_TAIL := 0.65

## A fee is the salary times a resale multiple, which collapses with age.
const VALUE_AGE_BANDS: Array = [
	[18, 48.0], [21, 42.0], [24, 36.0], [27, 30.0], [29, 22.8], [31, 14.4], [33, 7.2], [35, 3.0],
]
const VALUE_AGE_TAIL := 0.90

## Buyers pay for the gap to potential, and the younger the player the more of it.
const POTENTIAL_AGE_BANDS: Array = [
	[17, 0.70], [19, 0.60], [21, 0.45], [23, 0.30], [25, 0.15], [27, 0.05],
]
const POTENTIAL_AGE_TAIL := 0.0

const VALUE_FLOOR := 3000
const VALUE_STEP := 1000

## Coaches follow the same shape on a flatter curve: their ability band is narrower.
const COACH_WAGE_AT_PIVOT := 50000
const COACH_WAGE_ABILITY_EXP := 2.5
const COACH_WAGE_REPUTATION_EXP := 1.8
const COACH_WAGE_FLOOR := 1300
const COACH_VETERAN_AGE := 62
const COACH_VETERAN_FACTOR := 0.88

## Fame tracks ability, but it lags: one season can only move it so far.
const REPUTATION_FROM_ABILITY := 850.0
const REPUTATION_ABILITY_WEIGHT := 0.7
const REPUTATION_CLUB_WEIGHT := 0.3
const REPUTATION_DRIFT_MAX := 35


static func wage_for(ability: float, reputation: int, age: int) -> int:
	var rated := maxf(ability, 1.0)
	var rep := maxf(float(PlayerTypesScript.clamp_reputation(reputation)), 1.0)
	var raw := float(WAGE_AT_PIVOT) \
		* pow(rated / ABILITY_PIVOT, WAGE_ABILITY_EXP) \
		* pow(rep / REPUTATION_PIVOT, WAGE_REPUTATION_EXP) \
		* _band(WAGE_AGE_BANDS, WAGE_AGE_TAIL, age)
	return maxi(WAGE_FLOOR, _round_to(raw, WAGE_STEP))


static func value_for(
	current_ability: int,
	potential_ability: int,
	age: int,
	reputation: int
) -> int:
	var ca := float(PlayerTypesScript.clamp_ability(current_ability))
	var pa := float(PlayerTypesScript.clamp_ability(maxi(potential_ability, current_ability)))
	var effective := ca + (pa - ca) * _band(POTENTIAL_AGE_BANDS, POTENTIAL_AGE_TAIL, age)
	var raw := float(wage_for(effective, reputation, age)) \
		* _band(VALUE_AGE_BANDS, VALUE_AGE_TAIL, age)
	return maxi(VALUE_FLOOR, _round_to(raw, VALUE_STEP))


static func coach_wage_for(current_ability: int, reputation: int, age: int) -> int:
	var rated := maxf(float(current_ability), 1.0)
	var rep := maxf(float(PlayerTypesScript.clamp_reputation(reputation)), 1.0)
	var raw := float(COACH_WAGE_AT_PIVOT) \
		* pow(rated / ABILITY_PIVOT, COACH_WAGE_ABILITY_EXP) \
		* pow(rep / REPUTATION_PIVOT, COACH_WAGE_REPUTATION_EXP)
	if age >= COACH_VETERAN_AGE:
		raw *= COACH_VETERAN_FACTOR
	return maxi(COACH_WAGE_FLOOR, _round_to(raw, WAGE_STEP))


static func ability_of(entity: Dictionary) -> int:
	return int(entity.get("current_ability", entity.get("overall", 50)))


static func expected_wage_of(player: Dictionary) -> int:
	return wage_for(
		float(ability_of(player)),
		int(player.get("reputation", 0)),
		int(player.get("age", 24))
	)


static func expected_value_of(player: Dictionary) -> int:
	var ca := ability_of(player)
	return value_for(
		ca,
		int(player.get("potential_ability", ca)),
		int(player.get("age", 24)),
		int(player.get("reputation", 0))
	)


## Market value is an appraisal, so it is free to move every season.
static func refresh_value(player: Dictionary) -> int:
	var value := expected_value_of(player)
	player["value"] = value
	if bool(player.get("for_sale", false)) and int(player.get("asking_price", 0)) < value:
		player["asking_price"] = value
	return value


## A salary is contract text: it only changes when the deal is signed again.
static func reprice_contract(player: Dictionary) -> int:
	var wage := expected_wage_of(player)
	player["wage"] = wage
	return wage


## How much of the current deal survives a move. A paid transfer can concede
## a little; a free agent can concede more. Neither is reset to the new club.
const MOVE_KEEP_SHARE := 0.85
const MOVE_FREE_KEEP_SHARE := 0.70
## One signing can at most double the wage he is already on.
const MOVE_RAISE_CAP := 2.0
## The offer listens to his own fame first, then to what this club pays.
const MOVE_PERSONAL_WEIGHT := 0.65
const MOVE_LOCAL_WEIGHT := 0.35


## New contract at another club. His current wage is the anchor: the destination's
## local scale can nudge the offer, it cannot replace a 200k deal with 10k.
static func wage_for_move(player: Dictionary, club: Dictionary, free_agent: bool = false) -> int:
	var current := maxi(0, int(player.get("wage", 0)))
	var personal := expected_wage_of(player)
	var local := wage_for(
		float(ability_of(player)),
		target_reputation(ability_of(player), int(club.get("reputation", int(REPUTATION_PIVOT)))),
		int(player.get("age", 24))
	)
	var offer := int(round(
		float(personal) * MOVE_PERSONAL_WEIGHT + float(local) * MOVE_LOCAL_WEIGHT
	))
	var anchor := maxi(current, personal)
	var keep := MOVE_FREE_KEEP_SHARE if free_agent else MOVE_KEEP_SHARE
	var reservation := int(round(float(anchor) * keep))
	var ceiling := int(round(float(maxi(current, WAGE_FLOOR)) * MOVE_RAISE_CAP))
	# Already underpaid relative to his own market: the new deal can catch up.
	ceiling = maxi(ceiling, personal)
	ceiling = maxi(ceiling, reservation)
	return maxi(WAGE_FLOOR, _round_to(float(clampi(offer, reservation, ceiling)), WAGE_STEP))


static func sign_wage(player: Dictionary, club: Dictionary, free_agent: bool = false) -> int:
	var wage := wage_for_move(player, club, free_agent)
	player["wage"] = wage
	return wage


static func target_reputation(current_ability: int, club_reputation: int) -> int:
	var from_ability := float(PlayerTypesScript.clamp_ability(current_ability)) \
		/ 100.0 * REPUTATION_FROM_ABILITY
	var club := float(PlayerTypesScript.clamp_reputation(club_reputation))
	return PlayerTypesScript.clamp_reputation(int(round(
		from_ability * REPUTATION_ABILITY_WEIGHT + club * REPUTATION_CLUB_WEIGHT
	)))


## Fame chases ability without ever jumping: a breakout season is worth ~35 points.
static func drift_reputation(player: Dictionary, club_reputation: int) -> int:
	var current := PlayerTypesScript.clamp_reputation(int(player.get("reputation", 0)))
	var target := target_reputation(ability_of(player), club_reputation)
	var step := clampi(target - current, -REPUTATION_DRIFT_MAX, REPUTATION_DRIFT_MAX)
	var next_value := PlayerTypesScript.clamp_reputation(current + step)
	player["reputation"] = next_value
	return next_value


## Season tick for a whole squad: fame first, then the price that follows from it.
static func refresh_squad(players: Array, club_reputation: int) -> void:
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = player
		drift_reputation(entry, club_reputation)
		refresh_value(entry)


static func _band(bands: Array, tail: float, age: int) -> float:
	for entry in bands:
		if age <= int(entry[0]):
			return float(entry[1])
	return tail


static func _round_to(value: float, step: int) -> int:
	if value <= 0.0:
		return 0
	return int(round(value / float(step))) * step
