class_name PlayerGenerator
extends RefCounted
## Builds player entities. PA is assigned by YouthIntake; CA is fitted from attributes.


const PlayerTypesScript := preload("res://game/player_types.gd")
const ConfigScript := preload("res://game/youth_generation_config.gd")
const YouthIntakeScript := preload("res://game/youth_intake.gd")
const PlayerDevelopmentScript := preload("res://game/player_development.gd")
const MatchTypesScript := preload("res://game/match_types.gd")
const PlayerMarketScript := preload("res://game/player_market.gd")

const SQUAD_SIZE := PlayerTypesScript.SQUAD_SIZE

## Fallback when a country has no name pools configured.
const FALLBACK_FIRST := [
	"Алекс", "Борис", "Виктор", "Глеб", "Даниил", "Егор", "Илья", "Кирилл",
	"Лев", "Максим", "Никита", "Олег", "Павел", "Роман", "Сергей", "Тимур",
	"Фёдор", "Юрий", "Антон", "Денис", "Игорь", "Артём", "Матвей", "Степан",
]

const FALLBACK_LAST := [
	"Иванов", "Смирнов", "Кузнецов", "Попов", "Васильев", "Петров", "Соколов",
	"Михайлов", "Новиков", "Фёдоров", "Морозов", "Волков", "Алексеев", "Лебедев",
	"Семёнов", "Егоров", "Павлов", "Козлов", "Степанов", "Николаев", "Орлов",
	"Андреев", "Макаров", "Захаров",
]

static func generate_for_club(
	club_id: int,
	club: Dictionary,
	rng: RandomNumberGenerator,
	name_pool_cache: Dictionary = {},
	id_state: Dictionary = {},
	_unused_cache: Dictionary = {}
) -> Array:
	var payload: Dictionary = club.duplicate(true)
	payload["id"] = club_id
	var country_id := int(payload.get("country_id", 0))
	var countries := {
		country_id: {
			"id": country_id,
			"youth_talent": int(payload.get("youth_talent", ConfigScript.YOUTH_TALENT_DEFAULT)),
		}
	}
	var generated: Dictionary = YouthIntakeScript.generate_first_team_squads(
		[payload],
		countries,
		rng,
		id_state,
		name_pool_cache
	)
	return generated.get(club_id, [])


static func create_player(
	club_id: int,
	club: Dictionary,
	rng: RandomNumberGenerator,
	name_pool_cache: Dictionary,
	used_names: Dictionary,
	id_state: Dictionary,
	spec: Dictionary
) -> Dictionary:
	if not id_state.has("next_id"):
		id_state["next_id"] = 1
	var reputation: int = PlayerTypesScript.clamp_reputation(int(club.get("reputation", 500)))
	var pools := _pools_for_club(club, name_pool_cache)
	var name := _unique_name(rng, used_names, pools["first"], pools["last"])
	var raw_position := str(spec.get("position", PlayerTypesScript.POS_CM))
	var position := PlayerTypesScript.normalize_position(raw_position)
	if not PlayerTypesScript.is_valid_position(raw_position):
		position = roll_youth_position(rng)
	var potential_ability := PlayerTypesScript.clamp_ability(int(spec.get("potential_ability", 50)))
	var current_ability := PlayerTypesScript.clamp_ability(int(spec.get("current_ability", 40)))
	if current_ability >= potential_ability and potential_ability > 1:
		current_ability = potential_ability - 1
	current_ability = maxi(current_ability, 1)
	var age := int(spec.get("age", 17))
	var target_ca := current_ability
	var attributes := _roll_attributes(rng, position, target_ca)
	current_ability = PlayerTypesScript.calc_current_ability(attributes, position)
	if current_ability != target_ca:
		_fit_attributes_to_target(attributes, position, target_ca)
		current_ability = PlayerTypesScript.calc_current_ability(attributes, position)
	# Integer attributes cannot always land exactly on a target, so CA stays whatever
	# the attributes really say and the attributes are pushed down until they fit under PA.
	var cap := potential_ability
	while current_ability > potential_ability and cap > 1:
		cap -= 1
		_fit_attributes_to_target(attributes, position, cap)
		current_ability = PlayerTypesScript.calc_current_ability(attributes, position)
	var characters := _roll_characters(rng)
	var personality := _roll_personality(rng, characters)
	var player_rep := _roll_player_reputation(rng, current_ability, reputation)
	var value := _estimate_value(current_ability, potential_ability, age, player_rep)
	var contract_years := _roll_contract_years(rng, age, current_ability)
	var wage := _estimate_wage(current_ability, player_rep, age)
	var nationality := int(spec.get("nationality_country_id", club.get("country_id", 0)))
	var player_id: int = int(id_state["next_id"])
	id_state["next_id"] = player_id + 1
	return {
		"id": player_id,
		"club_id": club_id,
		"name": name,
		"age": age,
		"nationality_country_id": nationality,
		"position": position,
		"value": value,
		"contract_status": "club" if club_id > 0 else "free_agent",
		"contract_years": contract_years,
		"wage": wage,
		"reputation": player_rep,
		"attributes": attributes,
		"current_ability": current_ability,
		"potential_ability": potential_ability,
		"overall": current_ability,
		"characters": characters,
		"personality": personality,
		"development_factor": PlayerDevelopmentScript.roll_development_factor(rng),
		"is_youth": bool(spec.get("is_youth", false)),
		"retirement_age": PlayerDevelopmentScript.roll_retirement_age(
			rng, position, characters, attributes
		),
		"condition": MatchTypesScript.CONDITION_START,
		"morale": MatchTypesScript.MORALE_DEFAULT,
	}


static func build_position_list(rng: RandomNumberGenerator) -> PackedStringArray:
	return _build_position_list(rng)


static func roll_age(rng: RandomNumberGenerator, target_ability: int) -> int:
	return _roll_age(rng, target_ability)


static func roll_youth_position(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.08:
		return PlayerTypesScript.POS_GK
	return PlayerTypesScript.FIELD_POSITIONS[
		rng.randi_range(0, PlayerTypesScript.FIELD_POSITIONS.size() - 1)
	]


static func team_strength(players: Array) -> float:
	if players.is_empty():
		return 60.0
	var sorted: Array = players.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return PlayerTypesScript.ability_of(a) > PlayerTypesScript.ability_of(b)
	)
	var take := mini(8, sorted.size())
	var total := 0.0
	for i in take:
		total += float(PlayerTypesScript.ability_of(sorted[i]))
	return total / float(take)


static func _roll_attributes(
	rng: RandomNumberGenerator,
	position: String,
	target_ability: int
) -> Dictionary:
	var base_level := int(round(float(target_ability) / 100.0 * float(PlayerTypesScript.ATTR_MAX)))
	base_level = clampi(base_level, PlayerTypesScript.ATTR_MIN, PlayerTypesScript.ATTR_MAX)
	var bias := PlayerTypesScript.generation_bias(position)
	var attributes := {}
	for group in PlayerTypesScript.attribute_groups_for_position(position):
		var group_map := {}
		for key in PlayerTypesScript.attribute_keys_for_group(group):
			var path := "%s.%s" % [group, key]
			var offset := 0
			if bias.has(path):
				offset = 1 if int(bias[path]) >= 3 else (1 if rng.randf() < 0.45 else 0)
			else:
				offset = -rng.randi_range(0, 1)
			if position == PlayerTypesScript.POS_GK and group != PlayerTypesScript.ATTR_GROUP_GOALKEEPING \
				and group != PlayerTypesScript.ATTR_GROUP_MENTAL \
				and group != PlayerTypesScript.ATTR_GROUP_PHYSICAL:
				offset -= 1
			if position != PlayerTypesScript.POS_GK and group == PlayerTypesScript.ATTR_GROUP_SET_PIECES:
				offset -= 1
			var value := base_level + offset + rng.randi_range(-1, 1)
			group_map[key] = PlayerTypesScript.clamp_attribute(value)
		attributes[group] = group_map
	_fit_attributes_to_target(attributes, position, target_ability)
	return attributes


static func _fit_attributes_to_target(
	attributes: Dictionary,
	position: String,
	target_ability: int
) -> void:
	PlayerTypesScript.fit_attributes_to_target(attributes, position, target_ability)


static func _build_position_list(rng: RandomNumberGenerator) -> PackedStringArray:
	return PlayerTypesScript.build_squad_positions(rng)


static func _roll_age(rng: RandomNumberGenerator, target_ability: int) -> int:
	var roll := rng.randf()
	if roll < 0.18:
		return rng.randi_range(16, 20)
	if roll < 0.55:
		return rng.randi_range(21, 26)
	if roll < 0.85:
		return rng.randi_range(27, 31)
	var age := rng.randi_range(32, 38)
	if target_ability >= 80 and age > 34 and rng.randf() < 0.5:
		return rng.randi_range(28, 33)
	return age


static func _roll_characters(rng: RandomNumberGenerator) -> Array:
	var pool: Array = PlayerTypesScript.CHARACTERS.duplicate()
	var first: String = pool[rng.randi_range(0, pool.size() - 1)]
	pool.erase(first)
	var opposite: String = str(PlayerTypesScript.CHARACTER_OPPOSITES.get(first, ""))
	if not opposite.is_empty() and opposite in pool:
		pool.erase(opposite)
	var second: String = pool[rng.randi_range(0, pool.size() - 1)]
	return [first, second]


static func _roll_personality(rng: RandomNumberGenerator, characters: Array) -> Dictionary:
	var bias: Dictionary = PlayerTypesScript.combined_personality_bias(characters)
	var out := {}
	for key in PlayerTypesScript.PERSONALITY_KEYS:
		var base := rng.randi_range(6, 14)
		var offset := int(bias.get(key, 0))
		# Soften stacked biases from two characters.
		offset = clampi(offset, -6, 6)
		out[key] = PlayerTypesScript.clamp_personality(base + offset + rng.randi_range(-2, 2))
	return out


static func _roll_player_reputation(rng: RandomNumberGenerator, current_ability: int, club_rep: int) -> int:
	# Same blend the seasonal drift aims at, so a new signing starts on target.
	return PlayerTypesScript.clamp_reputation(
		PlayerMarketScript.target_reputation(current_ability, club_rep) + rng.randi_range(-40, 40)
	)


static func _estimate_value(current_ability: int, potential_ability: int, age: int, reputation: int) -> int:
	return PlayerMarketScript.value_for(current_ability, potential_ability, age, reputation)


static func _estimate_wage(current_ability: int, reputation: int, age: int) -> int:
	return PlayerMarketScript.wage_for(float(current_ability), reputation, age)


static func _roll_contract_years(rng: RandomNumberGenerator, age: int, current_ability: int) -> int:
	if age >= 34:
		return rng.randi_range(1, 2)
	if age <= 21 and current_ability >= 70:
		return rng.randi_range(3, 5)
	return rng.randi_range(1, 4)


static func _pools_for_club(club: Dictionary, cache: Dictionary) -> Dictionary:
	var country_id := int(club.get("country_id", 0))
	if cache.has(country_id):
		return cache[country_id]

	var first := PackedStringArray()
	var last := PackedStringArray()
	if country_id > 0 and WorldDatabase.is_ready():
		var loaded: Dictionary = CountryNameRepository.new().get_pools(country_id)
		first = loaded.get("first", PackedStringArray())
		last = loaded.get("last", PackedStringArray())

	if first.is_empty():
		first = PackedStringArray(FALLBACK_FIRST)
	if last.is_empty():
		last = PackedStringArray(FALLBACK_LAST)

	var pools := {"first": first, "last": last}
	cache[country_id] = pools
	return pools


static func _unique_name(
	rng: RandomNumberGenerator,
	used: Dictionary,
	first_names: PackedStringArray,
	last_names: PackedStringArray
) -> String:
	if first_names.is_empty() or last_names.is_empty():
		return "Игрок %d" % (used.size() + 1)
	for _i in 40:
		var first: String = first_names[rng.randi_range(0, first_names.size() - 1)]
		var last: String = last_names[rng.randi_range(0, last_names.size() - 1)]
		var full := "%s %s" % [first, last]
		if not used.has(full):
			used[full] = true
			return full
	return "Игрок %d" % (used.size() + 1)
