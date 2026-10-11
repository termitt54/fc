class_name CoachGenerator
extends RefCounted
## Builds a head coach for each club at new-game start.


const PlayerGeneratorScript := preload("res://game/player_generator.gd")
const PlayerDevelopmentScript := preload("res://game/player_development.gd")
const CoachTypesScript := preload("res://game/coach_types.gd")
const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")


static func generate_for_clubs(
	clubs_by_id: Dictionary,
	rng: RandomNumberGenerator,
	name_pool_cache: Dictionary = {},
	id_state: Dictionary = {},
	season_number: int = 1
) -> Dictionary:
	if not id_state.has("next_id"):
		id_state["next_id"] = 1
	var used_names: Dictionary = {}
	var country_ids: Array = []
	for club_id in clubs_by_id.keys():
		var club: Dictionary = clubs_by_id[club_id]
		if typeof(club) != TYPE_DICTIONARY:
			continue
		var country_id := int(club.get("country_id", 0))
		if country_id > 0 and not country_ids.has(country_id):
			country_ids.append(country_id)

	var out: Dictionary = {}
	for club_id in clubs_by_id.keys():
		var club: Dictionary = clubs_by_id[club_id]
		if typeof(club) != TYPE_DICTIONARY:
			continue
		var id := int(club_id)
		club["id"] = id
		out[id] = generate_for_club(
			id, club, rng, name_pool_cache, used_names, id_state, season_number, country_ids
		)
	return out


static func generate_for_club(
	club_id: int,
	club: Dictionary,
	rng: RandomNumberGenerator,
	name_pool_cache: Dictionary = {},
	used_names: Dictionary = {},
	id_state: Dictionary = {},
	season_number: int = 1,
	country_ids: Array = []
) -> Dictionary:
	if not id_state.has("next_id"):
		id_state["next_id"] = 1
	var club_rep := PlayerTypes.clamp_reputation(int(club.get("reputation", 500)))
	var pools: Dictionary = PlayerGeneratorScript._pools_for_club(club, name_pool_cache)
	var name := PlayerGeneratorScript._unique_name(
		rng, used_names, pools.get("first", PackedStringArray()), pools.get("last", PackedStringArray())
	)
	if name.begins_with("Игрок "):
		name = "Тренер %d" % int(id_state["next_id"])

	var age := _roll_age(rng)
	var current_ability := _roll_current_ability(rng, club_rep)
	var potential_ability := _roll_potential_ability(rng, current_ability, age)
	var attributes := _roll_attributes(rng, current_ability)
	current_ability = CoachTypesScript.calc_current_ability(attributes)
	if current_ability > potential_ability:
		_fit_attributes_to_target(rng, attributes, float(potential_ability) / 5.0)
		current_ability = mini(CoachTypesScript.calc_current_ability(attributes), potential_ability)
	current_ability = PlayerTypes.clamp_ability(current_ability)
	potential_ability = PlayerTypes.clamp_ability(maxi(potential_ability, current_ability))

	var reputation := _roll_reputation(rng, current_ability, club_rep)
	var wage := _estimate_wage(current_ability, reputation, age)
	var contract_years := _roll_contract_years(rng, age)
	var nationality := _pick_nationality(rng, int(club.get("country_id", 0)), country_ids)
	var tactics: Dictionary = TacticTypesScript.roll_coach_identity(rng)
	var coach_id: int = int(id_state["next_id"])
	id_state["next_id"] = coach_id + 1
	var club_name := str(club.get("name", "")).strip_edges()
	if club_name.is_empty():
		club_name = "Клуб #%d" % club_id

	return {
		"id": coach_id,
		"club_id": club_id,
		"name": name,
		"age": age,
		"nationality_country_id": nationality,
		"reputation": reputation,
		"current_ability": current_ability,
		"potential_ability": potential_ability,
		"overall": current_ability,
		"contract_years": contract_years,
		"wage": wage,
		"style": str(tactics.get("style", CoachTypesScript.STYLE_BALANCED)),
		"primary_style": str(tactics.get("primary_style", "")),
		"backup_style": str(tactics.get("backup_style", "")),
		"primary_formation": str(tactics.get("primary_formation", "")),
		"backup_formation": str(tactics.get("backup_formation", "")),
		"attributes": attributes,
		"development_factor": PlayerDevelopmentScript.roll_development_factor(rng),
		"career": [{
			"season_from": maxi(season_number, 1),
			"season_to": 0,
			"club_id": club_id,
			"club_name": club_name,
			"role": CoachTypesScript.ROLE_HEAD_COACH,
		}],
	}


static func _roll_age(rng: RandomNumberGenerator) -> int:
	# Peak band 42–54, with a long tail up to late 60s.
	var roll := rng.randf()
	if roll < 0.12:
		return rng.randi_range(CoachTypesScript.AGE_MIN, 41)
	if roll < 0.72:
		return rng.randi_range(42, 54)
	if roll < 0.92:
		return rng.randi_range(55, 61)
	return rng.randi_range(62, CoachTypesScript.AGE_MAX)


static func _roll_current_ability(rng: RandomNumberGenerator, club_rep: int) -> int:
	var base := 30.0 + float(club_rep) * 0.052
	var ca := int(round(base + rng.randfn(0.0, 5.5)))
	return PlayerTypes.clamp_ability(clampi(ca, 26, 90))


static func _roll_potential_ability(rng: RandomNumberGenerator, current_ability: int, age: int) -> int:
	var headroom := 12
	if age >= 60:
		headroom = 3
	elif age >= 54:
		headroom = 6
	elif age <= 42:
		headroom = 16
	var pa := current_ability + rng.randi_range(1, maxi(1, headroom))
	return PlayerTypes.clamp_ability(maxi(current_ability, pa))


static func _roll_attributes(rng: RandomNumberGenerator, target_ca: int) -> Dictionary:
	var target := clampf(float(target_ca) / 5.0, 1.0, 20.0)
	var attrs: Dictionary = {}
	for key in CoachTypesScript.ATTR_KEYS:
		var spread := 3.6 if key == CoachTypesScript.ATTR_TRANSFERS else 2.1
		attrs[key] = CoachTypesScript.clamp_attr(int(round(target + rng.randfn(0.0, spread))))
	_fit_attributes_to_target(rng, attrs, target)
	return attrs


static func _fit_attributes_to_target(
	rng: RandomNumberGenerator,
	attrs: Dictionary,
	target: float
) -> void:
	for _i in 24:
		var total := 0.0
		for key in CoachTypesScript.ATTR_KEYS:
			total += float(int(attrs.get(key, 1)))
		var mean := total / float(CoachTypesScript.ATTR_KEYS.size())
		if absf(mean - target) < 0.35:
			return
		var key: String = CoachTypesScript.ATTR_KEYS[rng.randi_range(0, CoachTypesScript.ATTR_KEYS.size() - 1)]
		var value := int(attrs.get(key, 1))
		if mean < target:
			attrs[key] = CoachTypesScript.clamp_attr(value + 1)
		else:
			attrs[key] = CoachTypesScript.clamp_attr(value - 1)


static func _roll_reputation(rng: RandomNumberGenerator, current_ability: int, club_rep: int) -> int:
	var from_ability := int(round(float(current_ability) / 100.0 * 820.0))
	var blended := int(round(float(from_ability) * 0.65 + float(club_rep) * 0.35))
	return PlayerTypes.clamp_reputation(blended + rng.randi_range(-35, 35))


static func _estimate_wage(current_ability: int, reputation: int, age: int) -> int:
	return PlayerMarketScript.coach_wage_for(current_ability, reputation, age)


static func _roll_contract_years(rng: RandomNumberGenerator, age: int) -> int:
	if age >= 60:
		return rng.randi_range(1, 2)
	if age >= 54:
		return rng.randi_range(1, 3)
	return rng.randi_range(2, 4)


static func _pick_nationality(rng: RandomNumberGenerator, club_country_id: int, country_ids: Array) -> int:
	if club_country_id > 0 and (country_ids.size() < 2 or rng.randf() > 0.18):
		return club_country_id
	var options: Array = []
	for country_id in country_ids:
		var id := int(country_id)
		if id > 0 and id != club_country_id:
			options.append(id)
	if options.is_empty():
		return club_country_id
	return int(options[rng.randi_range(0, options.size() - 1)])

