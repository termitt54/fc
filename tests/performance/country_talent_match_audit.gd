extends Node
## Country talent -> generated profiles -> national call-up -> actual match engine.
const Config := preload("res://game/youth_generation_config.gd")
const MatchConfig := preload("res://game/match_simulation_config.gd")
const EngineScript := preload("res://game/match_engine.gd")
var audit_engine: Variant = EngineScript
const WORLDS := 100
const MATCHES := 20
var report := {"cohorts": [], "matches": [], "existing": []}
var output := ""

func _ready() -> void:
	call_deferred("run")

func coach() -> Dictionary:
	return {"primary_style": "control", "backup_style": "control", "primary_formation": "2-3-2", "backup_formation": "2-3-2", "national_selection": true,
		"attributes": {"tactics": 12, "motivation": 12, "professionalism": 20}}

func callup(pool: Array, manager: Dictionary, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var index := {}
	for player in pool:
		index[int(player.id)] = player
	var selected: Array = []
	for id in NationalTeams.select_squad(pool, manager, rng):
		selected.append(index[id])
	return selected

func duel(a: Array, b: Array, count: int, seed_value: int, ca: Dictionary, cb: Dictionary) -> Dictionary:
	var row := {"wins": 0, "draws": 0, "losses": 0, "gf": 0, "ga": 0, "gap": 0.0, "matches": count, "losses_by_4": 0, "losses_by_6": 0, "max_loss_margin": 0}
	for i in count:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value + i
		var home := {"club_id": 1, "squad": a, "coach": ca}
		var away := {"club_id": 2, "squad": b, "coach": cb}
		var swap := i % 2 == 1
		var result: Dictionary = audit_engine.simulate({"home": away if swap else home, "away": home if swap else away, "neutral": true, "allow_draw": true, "discipline": {"enabled": false}}, rng)
		var gf := int(result.away_goals if swap else result.home_goals)
		var ga := int(result.home_goals if swap else result.away_goals)
		row.gf += gf
		row.ga += ga
		row.losses_by_4 += int(ga - gf >= 4)
		row.losses_by_6 += int(ga - gf >= 6)
		row.max_loss_margin = maxi(int(row.max_loss_margin), ga - gf)
		row["wins" if gf > ga else "losses" if gf < ga else "draws"] += 1
		row.gap += float(result["away_team" if swap else "home_team"].get("starting_ability", 0.0)) - float(result["home_team" if swap else "away_team"].get("starting_ability", 0.0))
	return row

func write_report() -> void:
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size() in [1, 2])
	var real_sizes := args.size() == 2 and args[1] == "database-volumes"
	assert(args.size() == 1 or real_sizes)
	var snapshot := args[0].replace("\\", "/").simplify_path()
	var root := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	assert(snapshot.begins_with(root + "/user-") and snapshot.ends_with("-snapshot"))
	output = snapshot.path_join("country-talent-matches-volumes.json" if real_sizes else "country-talent-matches.json")
	Config.birth_config_path = snapshot.path_join("config/youth_talent_birth.json")
	Config.unload_birth()
	MatchConfig.config_path = snapshot.path_join("config/match_simulation.json")
	MatchConfig.unload()
	var knobs := MatchConfig.snapshot()
	knobs.injury_per_phase = 0.0
	MatchConfig.apply_values(knobs, false)
	report["birth_rows"] = {}
	report["probabilities"] = {}
	for talent in [50, 74, 85]:
		report.birth_rows[talent] = Config.birth_weights(talent)
		report.probabilities[talent] = {"pa70": Config.potential_probability(talent, 70), "pa80": Config.potential_probability(talent, 80), "pa90": Config.potential_probability(talent, 90), "pa100": Config.potential_probability(talent, 100)}
	for club_count in ([0] if real_sizes else [3, 10]):
		var sums := {}
		var totals := {74: {"wins": 0, "draws": 0, "losses": 0, "gf": 0, "ga": 0, "gap": 0.0, "matches": 0}, 50: {"wins": 0, "draws": 0, "losses": 0, "gf": 0, "ga": 0, "gap": 0.0, "matches": 0}}
		for seed_index in WORLDS:
			var teams := {}
			for talent in [50, 74, 85]:
				var rng := RandomNumberGenerator.new()
				rng.seed = 88000 + seed_index
				var clubs: Array = []
				var actual_count: int = (7 if talent == 85 else 4 if talent == 74 else 1) if real_sizes else int(club_count)
				for i in actual_count:
					clubs.append({"id": i + 1, "name": "Club", "country_id": 1, "reputation": 500, "youth_academy": 10})
				var players := YouthIntake.generate_first_team_squads(clubs, {1: {"youth_talent": talent}}, rng, {"next_id": 1}, {})
				var pool: Array = []
				for squad in players.values():
					pool.append_array(squad)
				if not sums.has(talent):
					sums[talent] = {"pa": 0.0, "ca": 0.0, "roster_ca": 0.0, "roster_pa": 0.0}
				for player in pool:
					sums[talent].pa += float(player.potential_ability) / pool.size() / WORLDS
					sums[talent].ca += float(player.current_ability) / pool.size() / WORLDS
					player.condition = 100
					player.morale = 50
				teams[talent] = callup(pool, coach(), 99000 + seed_index)
				for player in teams[talent]:
					sums[talent].roster_ca += float(player.current_ability) / 25.0 / WORLDS
					sums[talent].roster_pa += float(player.potential_ability) / 25.0 / WORLDS
			for other in [74, 50]:
				var result := duel(teams[85], teams[other], MATCHES, 1000000 + seed_index * MATCHES, coach(), coach())
				for key in totals[other]:
					totals[other][key] += result[key]
			if seed_index % 20 == 0:
				print("COUNTRY AUDIT clubs=", club_count, " worlds=", seed_index)
		for talent in sums:
			report.cohorts.append({"talent": talent, "clubs": (7 if talent == 85 else 4 if talent == 74 else 1) if real_sizes else club_count, "worlds": WORLDS, "means": sums[talent]})
		for other in totals:
			report.matches.append({"clubs_each": club_count, "clubs": [7, 4 if other == 74 else 1] if real_sizes else [club_count, club_count], "talents": [85, other], "results": totals[other]})
		write_report()
	if real_sizes:
		print("COUNTRY VOLUME AUDIT COMPLETE ", JSON.stringify(report))
		get_tree().quit()
		return
	SaveStore.database_path_override = snapshot.path_join("games.db")
	WorldDatabase.db_dir = snapshot
	WorldDatabase.db_path = snapshot.path_join("world.db")
	assert(WorldDatabase.initialize())
	var loaded := SaveStore.new().load_slot("autosave")
	assert(loaded.success and GameSession.apply_save_payload(loaded.data).success)
	var pools := {1: [], 21: []}
	for player in NationalTeams.index_players(GameSession).values():
		var cid := int(player.get("nationality_country_id", 0))
		if pools.has(cid):
			player.condition = 100
			player.morale = 50
			player.injury_rounds = 0
			pools[cid].append(player)
	for equal_coaches in [true, false]:
		var ca: Dictionary = coach() if equal_coaches else GameSession.national_teams[1].coach.merged({"national_selection": true})
		var cb: Dictionary = coach() if equal_coaches else GameSession.national_teams[21].coach.merged({"national_selection": true})
		var a := callup(pools[1], ca, 4041)
		var b := callup(pools[21], cb, 4041)
		report.existing.append({"equal_coaches": equal_coaches, "candidates": [pools[1].size(), pools[21].size()], "results": duel(a, b, 1000, 915000, ca, cb)})
	write_report()
	print("COUNTRY AUDIT COMPLETE ", JSON.stringify(report))
	get_tree().quit()
