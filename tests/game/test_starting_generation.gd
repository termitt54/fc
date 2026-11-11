extends Node
## Exercises the actual new-game builder, including its opening free-agent pool.
const Config := preload("res://game/youth_generation_config.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	Config.birth_config_path = "user://config/starting_generation_isolated.json"
	var profile_rng := RandomNumberGenerator.new()
	profile_rng.seed = 501980
	var defender := PlayerGenerator._roll_attributes(profile_rng, "CB", 80)
	var striker := PlayerGenerator._roll_attributes(profile_rng, "ST", 80)
	PlayerTypes.fit_attributes_to_target(defender, "CB", 80)
	PlayerTypes.fit_attributes_to_target(striker, "ST", 80)
	check(absi(PlayerTypes.calc_current_ability(defender,"CB")-80)<=1 and absi(PlayerTypes.calc_current_ability(striker,"ST")-80)<=1, "Position profiles preserve the requested CA")
	check(int(defender.technical.defending)-int(defender.technical.finishing)>=4, "Starting defender is a specialist rather than an equally skilled striker")
	check(int(striker.technical.finishing)-int(striker.technical.defending)>=4, "Starting striker keeps the same role specialization as a developed academy player")
	var country_repo := CountryRepository.new()
	var club_repo := ClubRepository.new()
	var unit_repo := CompetitionUnitRepository.new()
	var comp_repo := CompetitionRepository.new()
	var continent := int(ContinentRepository.new().get_all().data[0].id)
	var countries: Array = []
	var clubs: Array = []
	# Clean country-only fixtures left by an interrupted setup in this isolated DB.
	for existing in country_repo.get_all().data:
		if str(existing.name) in ["Startup test 20", "Startup test 85"]:
			country_repo.delete(int(existing.id))
	for talent in [20, 85]:
		var country := country_repo.create({"name": "Startup test %d" % talent, "abbreviation": "ST%d" % talent, "continent_id": continent, "youth_talent": talent})
		check(country.success, "country fixture created")
		if not country.success:
			get_tree().quit(1)
			return
		countries.append(int(country.data.id))
		var club := club_repo.create({"name": "Startup club %d" % talent, "short_name": "S%d" % talent, "country_id": country.data.id})
		check(club.success, "club fixture created")
		if not club.success:
			get_tree().quit(1)
			return
		clubs.append(int(club.data.id))
	var competition := comp_repo.create({"name": "Startup generation fixture", "scope_type": CompetitionTypes.SCOPE_INTERCONTINENTAL_CLUB})
	check(competition.success, "competition fixture created")
	var unit := unit_repo.create({"competition_id": competition.data.id, "unit_kind": "DIVISION", "name": "Startup league", "competition_type": "LEAGUE", "divisions_count": 1, "teams_per_division": 2, "matches_vs_own": 1, "teams_playoff": 0})
	check(unit.success and unit_repo.set_club_ids(int(unit.data.id), clubs).success, "new-game tournament contains both clubs")
	var rows := Config.default_birth_weights()
	rows[20].fill(0)
	rows[20][1] = Config.BIRTH_WEIGHT_TOTAL
	rows[85].fill(0)
	rows[85][6] = Config.BIRTH_WEIGHT_TOTAL
	check(Config.apply_birth_weights(rows).ok, "editor percentages saved")
	Config.unload_birth()
	var rng := RandomNumberGenerator.new()
	rng.seed = 52178
	var built := SeasonBuilder.new().build_new_game(rng)
	check(built.success, "real new-game builder succeeds")
	if built.success:
		check_generation(built.data, countries, 80, 84)
	# Change the saved editor table, not a test-only generation argument.
	rows[85].fill(0)
	rows[85][4] = Config.BIRTH_WEIGHT_TOTAL
	check(Config.apply_birth_weights(rows).ok, "changed percentages saved")
	Config.unload_birth()
	rng.seed = 52178
	var rebuilt := SeasonBuilder.new().build_new_game(rng)
	check(rebuilt.success, "second new game uses newly saved table")
	if rebuilt.success:
		check_generation(rebuilt.data, countries, 70, 74)
	if built.success:
		var old_high: Array = built.data.free_agents.filter(func(p): return int(p.nationality_country_id) == int(countries[1]))
		check(old_high.all(func(p): return int(p.potential_ability) >= 80), "new generation leaves existing snapshot unchanged")
	unit_repo.delete(int(unit.data.id))
	comp_repo.delete(int(competition.data.id))
	for id in clubs:
		club_repo.delete(id)
	for id in countries:
		country_repo.delete(id)
	DirAccess.remove_absolute(Config.birth_config_path)
	Config.reset_birth_to_defaults(false)
	print("=== Starting generation: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func check_generation(snapshot: Dictionary, countries: Array, high_min: int, high_max: int) -> void:
	var counts := {int(countries[0]): 0, int(countries[1]): 0}
	var valid := true
	var capped := true
	for player in snapshot.free_agents:
		var country := int(player.nationality_country_id)
		if not counts.has(country):
			continue
		counts[country] += 1
		var pa := int(player.potential_ability)
		valid = valid and (pa >= 40 and pa <= 49 if country == int(countries[0]) else pa >= high_min and pa <= high_max)
		capped = capped and int(player.current_ability) <= pa
	check(counts[int(countries[0])] == 20 and counts[int(countries[1])] == 20, "startup creates 20 existing players for each club nationality")
	check(valid, "all initial player potentials follow the saved row for their country")
	check(capped, "adult initial ability remains below potential")
	for cid in snapshot.coaches_by_club:
		var reserves: Array = snapshot.reserve_players_by_club.get(cid, [])
		var youth: Array = snapshot.youth_players_by_club.get(cid, [])
		if reserves.is_empty() and youth.is_empty():
			continue
		check(reserves.size()>=5 and reserves.size()<=7, "New-world clubs have an existing reserve cohort")
		check(reserves.all(func(p): return int(p.age)>=18 and int(p.age)<=21 and bool(p.is_reserve)), "Reserve age bridge exists before the first retirement wave")
		check(youth.size()>=5 and youth.size()<=7, "New-world clubs have an existing academy cohort")
		check(youth.all(func(p): return int(p.age)>=15 and int(p.age)<=17 and bool(p.is_youth)), "Initial academy preserves youth ages")
	check((snapshot.players_by_club.get(int(snapshot.coaches_by_club.keys()[0]), []) as Array).is_empty(), "opening market receives generated players as free agents")
