class_name PlayerDevelopment
extends RefCounted
## Seasonal CA growth and ageing. PA is a ceiling, not a guaranteed result:
## a young player closes a share of the gap to it every season, holds a peak in
## his late twenties, then loses ground from DECLINE_START_AGE onwards.
## CA lives in the attributes, so every change goes through the fitter in
## PlayerTypes — writing player["current_ability"] on its own does nothing.
## tests/game/test_player_development.gd guards the curve.


const Config := preload("res://game/youth_generation_config.gd")

const RETIREMENT_AGE_MEAN := 37.0
const RETIREMENT_AGE_SPREAD := 1.9
const RETIREMENT_AGE_MIN := 33
const RETIREMENT_AGE_MAX := 42
const RETIREMENT_DECLINE_CA := 42
const RETIREMENT_DECLINE_CHANCE := 0.35

## Share of the remaining gap to the personal ceiling closed per season. Growth
## is proportional to what is left, so a talent converges on his potential while
## a limited player plateaus early instead of both crawling by the same step.
## Young seasons close a larger share: a full-potential talent can reach the
## high 80s by 18, while a typical prospect is still in the 70s.
const GROWTH_GAP_SHARES := [
	{"max_age": 18, "share": 0.30},
	{"max_age": 21, "share": 0.25},
	{"max_age": 24, "share": 0.17},
	{"max_age": 27, "share": 0.09},
	{"max_age": 29, "share": 0.04},
]
const GROWTH_NOISE_MIN := 0.6
const GROWTH_NOISE_MAX := 1.4

## Ageing. The loss grows with every season past the start age and is spent on
## physical attributes first.
const DECLINE_START_AGE := 30
const DECLINE_PER_YEAR := 0.45
const DECLINE_NOISE_MIN := 0.6
const DECLINE_NOISE_MAX := 1.4
const DECLINE_PROFESSIONAL_FACTOR := 0.85

## Playing time. A man who never gets on the pitch still trains, so growth is
## damped rather than stopped.
const MINUTES_GROWTH_FLOOR := 0.45
const MINUTES_SHARE_UNKNOWN := 0.6

## The club side of a season: the base a player trains at and the head coach who
## runs it. They share one multiplier, so giving the coach a say does not widen
## the spread the training base already had. The base weighs more of the two.
const LEVEL_MAX := 20
const LEVEL_NEUTRAL := 10
const FACILITY_WEIGHT := 0.6
const COACHING_WEIGHT := 0.4

## The player's own application. Personality already carries his characters —
## PROFESSIONAL and AMBITIOUS bias exactly these two scales at generation — so
## the characters count here without a second bonus. Using mental attributes
## instead would feed CA back into its own growth rate and would only bite for
## the positions that weight them.
const DRIVE_KEYS := ["professionalism", "ambition"]
const DRIVE_FLOOR := 0.80
const DRIVE_SPAN := 0.40

## Academy and reserve football is not simulated, so those squads develop on a
## notional workload instead of their (empty) first-team minutes.
const YOUTH_PLAYING_SHARE := 0.80
const RESERVE_PLAYING_SHARE := 0.70
const FREE_AGENT_PLAYING_SHARE := 0.25


## Personal end-of-career age: around 37, later for keepers and pros.
static func roll_retirement_age(
	rng: RandomNumberGenerator,
	position: String,
	characters: Array = [],
	attributes: Dictionary = {}
) -> int:
	var age := RETIREMENT_AGE_MEAN + rng.randfn(0.0, RETIREMENT_AGE_SPREAD)
	if PlayerTypes.normalize_position(position) == PlayerTypes.POS_GK:
		age += 2.0
	if characters.has(PlayerTypes.CHAR_PROFESSIONAL):
		age += 1.0
	if characters.has(PlayerTypes.CHAR_INCONSISTENT):
		age -= 0.6
	if not attributes.is_empty():
		var endurance := float(
			PlayerTypes.get_attribute_value(attributes, PlayerTypes.ATTR_GROUP_PHYSICAL, "stamina")
			+ PlayerTypes.get_attribute_value(attributes, PlayerTypes.ATTR_GROUP_PHYSICAL, PlayerTypes.ATTR_RECOVERY)
		) / 2.0
		age += (endurance - 10.0) * 0.12
	return clampi(int(round(age)), RETIREMENT_AGE_MIN, RETIREMENT_AGE_MAX)


static func ensure_retirement_age(player: Dictionary, rng: RandomNumberGenerator) -> int:
	var stored := int(player.get("retirement_age", 0))
	if stored >= RETIREMENT_AGE_MIN:
		return stored
	var attributes: Variant = player.get("attributes", null)
	var rolled := roll_retirement_age(
		rng,
		str(player.get("position", "")),
		PlayerTypes.characters_of(player),
		attributes if typeof(attributes) == TYPE_DICTIONARY else {}
	)
	player["retirement_age"] = rolled
	return rolled


## Checked in the off-season, after ageing.
static func should_retire(player: Dictionary, rng: RandomNumberGenerator) -> bool:
	var age := int(player.get("age", 20))
	var limit := ensure_retirement_age(player, rng)
	if age >= limit:
		return true
	if age >= limit - 2 and int(player.get("current_ability", 50)) < RETIREMENT_DECLINE_CA:
		return rng.randf() < RETIREMENT_DECLINE_CHANCE
	return false


static func roll_development_factor(rng: RandomNumberGenerator) -> float:
	return snappedf(
		rng.randf_range(Config.DEVELOPMENT_FACTOR_MIN, Config.DEVELOPMENT_FACTOR_MAX),
		0.01
	)


static func ability_ceiling(potential_ability: int, development_factor: float) -> int:
	var pa := PlayerTypes.clamp_ability(potential_ability)
	if development_factor >= 1.0:
		return pa
	var scaled := int(round(float(pa) * development_factor))
	return clampi(scaled, 1, pa)


## Everything the club brings to one season of training. Built once per squad,
## because youth train at the academy and everybody else at the main base.
static func training_setup(facility_level: int, coach: Dictionary = {}) -> Dictionary:
	var coaching := LEVEL_NEUTRAL
	if not coach.is_empty():
		coaching = CoachTypes.development_of(coach)
	return {
		"facility": clampi(facility_level, 0, LEVEL_MAX),
		"coaching": clampi(coaching, 0, LEVEL_MAX),
	}


static func develop_player(
	player: Dictionary,
	setup: Dictionary,
	rng: RandomNumberGenerator,
	playing_share: float = MINUTES_SHARE_UNKNOWN,
	season: int = 0
) -> void:
	if player.is_empty():
		return
	var raw: Variant = player.get("attributes", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return
	var attributes: Dictionary = raw
	if attributes.is_empty():
		return

	var position := str(player.get("position", ""))
	var exact := PlayerTypes.calc_ability_exact(attributes, position)
	var before_ca := PlayerTypes.calc_current_ability(attributes, position)
	var before_attrs := _copy_attributes(attributes)
	var age := int(player.get("age", 20))
	var target := exact
	if age >= DECLINE_START_AGE:
		target -= _decline_step(player, age, rng)
	else:
		target += _growth_step(player, age, setup, playing_share, exact, rng)

	var pa := PlayerTypes.clamp_ability(int(player.get("potential_ability", 100)))
	target = clampf(target, 1.0, float(pa))
	var prefer := PlayerTypes.ATTR_GROUP_PHYSICAL if target < exact else ""
	PlayerTypes.fit_attributes_to_exact(attributes, position, target, prefer)

	var next_ca := mini(PlayerTypes.calc_current_ability(attributes, position), pa)
	player["current_ability"] = next_ca
	player["overall"] = next_ca
	MatchRatings.invalidate(player)
	if season >= 1:
		_record_development(
			player,
			season,
			before_ca,
			next_ca,
			_attribute_deltas(before_attrs, attributes)
		)


## Playing time is read from the season row that has not been archived yet:
## start_new_season() develops the squads before it rolls the stats over.
## Pass assumed_share for squads whose football is not simulated.
static func develop_squad(
	players: Array,
	setup: Dictionary,
	rng: RandomNumberGenerator,
	assumed_share: float = -1.0,
	season: int = 0
) -> void:
	var reference := _minutes_reference(players)
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var share := assumed_share
		if share < 0.0:
			share = _playing_share(player, reference)
		develop_player(player, setup, rng, share, season)


static func age_squad(players: Array) -> void:
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		player["age"] = int(player.get("age", 16)) + 1


## CA after each off-season, plus the attribute steps of the latest one.
## The first recorded season keeps the CA the player had before that step.
static func _record_development(
	player: Dictionary,
	season: int,
	ca_before: int,
	ca_after: int,
	deltas: Dictionary
) -> void:
	var raw: Variant = player.get("development_history", null)
	var history: Array = raw if typeof(raw) == TYPE_ARRAY else []
	if history.is_empty() and season > 1:
		history.append({"season": season - 1, "ca": ca_before})
	if not history.is_empty() and int((history.back() as Dictionary).get("season", 0)) == season:
		(history.back() as Dictionary)["ca"] = ca_after
	else:
		history.append({"season": season, "ca": ca_after})
	player["development_history"] = history
	player["development_deltas"] = deltas


static func _copy_attributes(attributes: Dictionary) -> Dictionary:
	var copy := {}
	for group in attributes.keys():
		var raw: Variant = attributes[group]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var group_copy := {}
		for key in (raw as Dictionary).keys():
			group_copy[str(key)] = int((raw as Dictionary)[key])
		copy[str(group)] = group_copy
	return copy


static func _attribute_deltas(before: Dictionary, after: Dictionary) -> Dictionary:
	var groups := {}
	for group in before.keys():
		groups[str(group)] = true
	for group in after.keys():
		groups[str(group)] = true
	var deltas := {}
	for group in groups.keys():
		var earlier: Dictionary = before.get(group, {})
		var later: Dictionary = after.get(group, {})
		var keys := {}
		for key in earlier.keys():
			keys[str(key)] = true
		for key in later.keys():
			keys[str(key)] = true
		var group_delta := {}
		for key in keys.keys():
			var step := int(later.get(key, 0)) - int(earlier.get(key, 0))
			if step != 0:
				group_delta[str(key)] = step
		if not group_delta.is_empty():
			deltas[str(group)] = group_delta
	return deltas


static func gap_share_for_age(age: int) -> float:
	for band in GROWTH_GAP_SHARES:
		if age <= int(band["max_age"]):
			return float(band["share"])
	return 0.0


static func _growth_step(
	player: Dictionary,
	age: int,
	setup: Dictionary,
	playing_share: float,
	exact: float,
	rng: RandomNumberGenerator
) -> float:
	var share := gap_share_for_age(age)
	if share <= 0.0:
		return 0.0
	var pa := int(player.get("potential_ability", player.get("current_ability", 50)))
	var factor := float(player.get("development_factor", 0.92))
	var gap := maxf(float(ability_ceiling(pa, factor)) - exact, 0.0)
	if gap <= 0.0:
		return 0.0
	var minutes_mod := MINUTES_GROWTH_FLOOR \
		+ (1.0 - MINUTES_GROWTH_FLOOR) * sqrt(clampf(playing_share, 0.0, 1.0))
	return gap * share \
		* _coaching_mod(setup) \
		* _drive_mod(player) \
		* minutes_mod \
		* rng.randf_range(GROWTH_NOISE_MIN, GROWTH_NOISE_MAX)


## Training base and head coach folded into the multiplier range the base used
## to own on its own. A neutral club (both 10) lands exactly on 1.0.
static func _coaching_mod(setup: Dictionary) -> float:
	var facility := clampf(float(int(setup.get("facility", LEVEL_NEUTRAL))) / float(LEVEL_MAX), 0.0, 1.0)
	var coaching := clampf(float(int(setup.get("coaching", LEVEL_NEUTRAL))) / float(LEVEL_MAX), 0.0, 1.0)
	var quality := FACILITY_WEIGHT * facility + COACHING_WEIGHT * coaching
	return Config.TRAINING_GROWTH_FLOOR + Config.TRAINING_GROWTH_SPAN * quality


## How hard the player works at it. Neutral personality (10) lands on 1.0.
static func _drive_mod(player: Dictionary) -> float:
	var raw: Variant = player.get("personality", null)
	if typeof(raw) != TYPE_DICTIONARY:
		return 1.0
	var personality: Dictionary = raw
	var total := 0.0
	for key in DRIVE_KEYS:
		total += float(PlayerTypes.clamp_personality(int(personality.get(key, LEVEL_NEUTRAL))))
	var scaled := clampf(
		total / float(DRIVE_KEYS.size() * PlayerTypes.PERSONALITY_MAX), 0.0, 1.0
	)
	return DRIVE_FLOOR + DRIVE_SPAN * scaled


static func _decline_step(player: Dictionary, age: int, rng: RandomNumberGenerator) -> float:
	var years := float(age - DECLINE_START_AGE + 1)
	var loss := DECLINE_PER_YEAR * years * rng.randf_range(DECLINE_NOISE_MIN, DECLINE_NOISE_MAX)
	if PlayerTypes.characters_of(player).has(PlayerTypes.CHAR_PROFESSIONAL):
		loss *= DECLINE_PROFESSIONAL_FACTOR
	return maxf(loss, 0.0)


## A full season is whatever the busiest man in the squad managed, so clubs on
## different schedules are compared on the same scale.
static func _minutes_reference(players: Array) -> int:
	var best := 0
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		best = maxi(best, _season_minutes(player))
	return best


static func _playing_share(player: Dictionary, reference: int) -> float:
	if reference <= 0:
		return MINUTES_SHARE_UNKNOWN
	return clampf(float(_season_minutes(player)) / float(reference), 0.0, 1.0)


static func _season_minutes(player: Dictionary) -> int:
	return maxi(0, PlayerStats.minutes_in_season(player))
