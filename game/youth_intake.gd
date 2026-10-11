class_name YouthIntake
extends RefCounted
## Each club births its own players from the country's talent chances.


const Config := preload("res://game/youth_generation_config.gd")

const MODE_YOUTH := "youth"
const MODE_FIRST_TEAM := "first_team"


static func generate_youth_intake(
	clubs: Array,
	countries_by_id: Dictionary,
	rng: RandomNumberGenerator,
	id_state: Dictionary = {},
	name_pool_cache: Dictionary = {}
) -> Dictionary:
	return generate(clubs, countries_by_id, rng, id_state, name_pool_cache, {"mode": MODE_YOUTH})


static func generate_first_team_squads(
	clubs: Array,
	countries_by_id: Dictionary,
	rng: RandomNumberGenerator,
	id_state: Dictionary = {},
	name_pool_cache: Dictionary = {}
) -> Dictionary:
	return generate(clubs, countries_by_id, rng, id_state, name_pool_cache, {"mode": MODE_FIRST_TEAM})


static func generate(
	clubs: Array,
	countries_by_id: Dictionary,
	rng: RandomNumberGenerator,
	id_state: Dictionary = {},
	name_pool_cache: Dictionary = {},
	options: Dictionary = {}
) -> Dictionary:
	var realized: Dictionary = realize_assignments(
		plan_intake(clubs, countries_by_id, rng, options),
		clubs,
		countries_by_id,
		rng,
		id_state,
		name_pool_cache,
		options
	)
	return realized["players_by_club"]


static func plan_intake(
	clubs: Array,
	countries_by_id: Dictionary,
	rng: RandomNumberGenerator,
	options: Dictionary = {}
) -> Array:
	var mode := str(options.get("mode", MODE_YOUTH))
	var club_slots: Dictionary = create_youth_intake_slots(clubs, rng, mode, options)
	var clubs_by_country: Dictionary = {}
	var club_by_id: Dictionary = {}
	var country_ids: Array = []

	for club in clubs:
		if typeof(club) != TYPE_DICTIONARY:
			continue
		var club_id := int(club.get("id", 0))
		if club_id < 1 or int(club_slots.get(club_id, 0)) <= 0:
			continue
		club_by_id[club_id] = club
		var country_id := int(club.get("country_id", 0))
		if not clubs_by_country.has(country_id):
			clubs_by_country[country_id] = []
			country_ids.append(country_id)
		(clubs_by_country[country_id] as Array).append(club_id)

	country_ids.sort()
	var assignments: Array = []
	for raw_country_id in country_ids:
		var country_id := int(raw_country_id)
		var club_ids: Array = clubs_by_country[country_id]
		club_ids.sort()
		var country: Dictionary = countries_by_id.get(country_id, {})
		var talent := int(country.get("youth_talent", Config.YOUTH_TALENT_DEFAULT))
		for raw_club_id in club_ids:
			var club_id := int(raw_club_id)
			var slots := int(club_slots.get(club_id, 0))
			if slots <= 0:
				continue
			var club: Dictionary = club_by_id[club_id]
			for _n in slots:
				var pa := Config.roll_birth_potential(talent, rng)
				var age := _roll_age_for_mode(rng, pa, mode)
				var academy := int(club.get("youth_academy", 10))
				var ca := generate_youth_starting_ability(rng, pa, age, academy, mode)
				assignments.append({
					"potential_ability": pa,
					"current_ability": ca,
					"age": age,
					"country_id": country_id,
					"club_id": club_id,
					"youth_academy": academy,
					"training_level": int(club.get("training_level", 10)),
					"scouting_level": int(club.get("scouting_level", 10)),
					"youth_search": int(club.get("youth_search", 10)),
					"is_youth": mode == MODE_YOUTH,
				})
	return assignments


static func realize_assignments(
	assignments: Array,
	clubs: Array,
	_countries_by_id: Dictionary,
	rng: RandomNumberGenerator,
	id_state: Dictionary,
	name_pool_cache: Dictionary,
	options: Dictionary = {}
) -> Dictionary:
	var mode := str(options.get("mode", MODE_YOUTH))
	var club_by_id: Dictionary = {}
	for club in clubs:
		if typeof(club) != TYPE_DICTIONARY:
			continue
		club_by_id[int(club.get("id", 0))] = club

	var grouped: Dictionary = {}
	for row in assignments:
		var club_id := int(row.get("club_id", 0))
		if not grouped.has(club_id):
			grouped[club_id] = []
		(grouped[club_id] as Array).append(row)

	var players_by_club: Dictionary = {}
	if not id_state.has("next_id"):
		id_state["next_id"] = 1

	for club_id in grouped.keys():
		var club: Dictionary = club_by_id.get(int(club_id), {"id": int(club_id)})
		var rows: Array = grouped[club_id]
		var positions: PackedStringArray
		if mode == MODE_FIRST_TEAM:
			positions = PlayerGenerator.build_position_list(rng)
		else:
			positions = PackedStringArray()
			for _i in rows.size():
				positions.append(PlayerGenerator.roll_youth_position(rng))

		var used_names: Dictionary = {}
		var squad: Array = []
		for i in rows.size():
			var spec: Dictionary = rows[i]
			var position := str(positions[i]) if i < positions.size() else PlayerGenerator.roll_youth_position(rng)
			squad.append(PlayerGenerator.create_player(
				int(club_id),
				club,
				rng,
				name_pool_cache,
				used_names,
				id_state,
				{
					"potential_ability": int(spec.get("potential_ability", 50)),
					"current_ability": int(spec.get("current_ability", 40)),
					"age": int(spec.get("age", 17)),
					"position": position,
					"nationality_country_id": int(spec.get("country_id", club.get("country_id", 0))),
					"is_youth": bool(spec.get("is_youth", mode == MODE_YOUTH)),
				}
			))
		players_by_club[int(club_id)] = squad

	for club in clubs:
		var club_id := int(club.get("id", 0))
		if club_id > 0 and not players_by_club.has(club_id):
			players_by_club[club_id] = []
	return {"players_by_club": players_by_club}


static func create_youth_intake_slots(
	clubs: Array,
	rng: RandomNumberGenerator,
	mode: String = MODE_YOUTH,
	options: Dictionary = {}
) -> Dictionary:
	var slots: Dictionary = {}
	var fixed := int(options.get("slots_per_club", 0))
	for club in clubs:
		if typeof(club) != TYPE_DICTIONARY:
			continue
		var club_id := int(club.get("id", 0))
		if club_id < 1:
			continue
		if fixed > 0:
			slots[club_id] = fixed
		elif mode == MODE_FIRST_TEAM:
			slots[club_id] = PlayerGenerator.SQUAD_SIZE
		else:
			slots[club_id] = rng.randi_range(Config.YOUTH_SLOTS_MIN, Config.YOUTH_SLOTS_MAX)
	return slots


static func generate_youth_starting_ability(
	rng: RandomNumberGenerator,
	potential_ability: int,
	age: int,
	youth_academy: int,
	mode: String = MODE_YOUTH
) -> int:
	var pa := clampi(potential_ability, Config.MIN_PA, Config.MAX_PA)
	var readiness := 0.0
	if mode == MODE_YOUTH or age <= 17:
		var band: Array = Config.AGE_READINESS.get(age, Config.AGE_READINESS[16])
		readiness = rng.randf_range(float(band[0]), float(band[1]))
		var academy := clampf(float(youth_academy) / 20.0, 0.0, 1.0)
		readiness += academy * Config.ACADEMY_CA_WEIGHT
		readiness += rng.randf_range(-Config.CA_NOISE, Config.CA_NOISE)
		readiness = clampf(readiness, Config.CA_READINESS_MIN, Config.CA_READINESS_MAX)
	else:
		readiness = _senior_readiness(rng, age)
	var ca := int(round(float(pa) * readiness))
	if pa <= 1:
		return 1
	return clampi(ca, 1, pa - 1)


static func collect_stats(assignments: Array) -> Dictionary:
	var pas: Array = []
	var by_country: Dictionary = {}
	var by_club: Dictionary = {}
	var counts := {"80": 0, "85": 0, "90": 0, "95": 0}
	for row in assignments:
		var pa := int(row.get("potential_ability", 0))
		pas.append(pa)
		if pa >= 80:
			counts["80"] = int(counts["80"]) + 1
		if pa >= 85:
			counts["85"] = int(counts["85"]) + 1
		if pa >= 90:
			counts["90"] = int(counts["90"]) + 1
		if pa >= 95:
			counts["95"] = int(counts["95"]) + 1
		var country_id := int(row.get("country_id", 0))
		var club_id := int(row.get("club_id", 0))
		if pa >= 85:
			by_country[country_id] = int(by_country.get(country_id, 0)) + 1
			by_club[club_id] = int(by_club.get(club_id, 0)) + 1

	pas.sort()
	var n := pas.size()
	var mean := 0.0
	var median := 0.0
	if n > 0:
		var total := 0
		for pa in pas:
			total += int(pa)
		mean = float(total) / float(n)
		if n % 2 == 1:
			median = float(pas[n / 2])
		else:
			median = (float(pas[n / 2 - 1]) + float(pas[n / 2])) * 0.5

	var distribution: Dictionary = {}
	for bucket in Config.get_pa_buckets():
		var key := "%d-%d" % [int(bucket["rating_min"]), int(bucket["rating_max"])]
		distribution[key] = 0
	for pa in pas:
		var key := _bucket_key_for_pa(int(pa))
		distribution[key] = int(distribution.get(key, 0)) + 1

	return {
		"count": n,
		"mean_pa": mean,
		"median_pa": median,
		"pa_80": int(counts["80"]),
		"pa_85": int(counts["85"]),
		"pa_90": int(counts["90"]),
		"pa_95": int(counts["95"]),
		"distribution": distribution,
		"strong_by_country": by_country,
		"strong_by_club": by_club,
	}


static func _senior_readiness(rng: RandomNumberGenerator, age: int) -> float:
	if age <= 21:
		return rng.randf_range(0.55, 0.72)
	if age <= 26:
		return rng.randf_range(0.70, 0.90)
	if age <= 31:
		return rng.randf_range(0.82, 0.97)
	return rng.randf_range(0.70, 0.90)


static func _roll_age_for_mode(rng: RandomNumberGenerator, potential_ability: int, mode: String) -> int:
	if mode == MODE_FIRST_TEAM:
		return PlayerGenerator.roll_age(rng, potential_ability)
	return _pick_weighted_value(rng, Config.YOUTH_AGES, Config.YOUTH_AGE_WEIGHTS)


static func _pick_weighted_value(rng: RandomNumberGenerator, values: Array, weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += float(w)
	var roll := rng.randf() * total
	var acc := 0.0
	for i in values.size():
		acc += float(weights[i])
		if roll <= acc:
			return int(values[i])
	return int(values[values.size() - 1])


static func _bucket_key_for_pa(potential_ability: int) -> String:
	var buckets: Array = Config.get_pa_buckets()
	for bucket in buckets:
		var lo := int(bucket["rating_min"])
		var hi := int(bucket["rating_max"])
		if potential_ability >= lo and potential_ability <= hi:
			return "%d-%d" % [lo, hi]
	var last: Dictionary = buckets[buckets.size() - 1]
	return "%d-%d" % [int(last["rating_min"]), int(last["rating_max"])]
