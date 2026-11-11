extends Node
## Read-only simulation samples; never opens a user save.
const Config := preload("res://game/youth_generation_config.gd")
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
const RUNS := 300

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	Config.birth_config_path = "user://nonexistent_balance_defaults.json"
	Config.reset_birth_to_defaults(false)
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		Config.birth_config_path = args[1]
		Config.unload_birth()
	var out := {"runs": RUNS, "generation": {}, "selection": {}}
	for talent in [50, 70, 78, 81, 85, 100]:
		var sums := {"pa": 0.0, "ca": 0.0, "top8_ca": 0.0, "pa80_share": 0.0}
		for seed in RUNS:
			var rng := RandomNumberGenerator.new()
			rng.seed = 97000 + seed
			var rows := YouthIntake.plan_intake([
				{"id": 1, "country_id": 1, "youth_academy": 15},
				{"id": 2, "country_id": 1, "youth_academy": 15},
				{"id": 3, "country_id": 1, "youth_academy": 15}],
				{1: {"youth_talent": talent}}, rng, {"mode": YouthIntake.MODE_FIRST_TEAM})
			var cas: Array = []
			for row in rows:
				sums.pa += float(row.potential_ability) / rows.size() / RUNS
				sums.ca += float(row.current_ability) / rows.size() / RUNS
				sums.pa80_share += (1.0 if int(row.potential_ability) >= 80 else 0.0) / rows.size() / RUNS
				cas.append(int(row.current_ability))
			cas.sort()
			for i in 8:
				sums.top8_ca += float(cas[cas.size() - 1 - i]) / 8.0 / RUNS
		out.generation[talent] = sums
	var rng := RandomNumberGenerator.new()
	rng.seed = 1492
	var pool := Fixtures.squad(51, 65, rng, 22) + Fixtures.squad(52, 65, rng, 22) + Fixtures.squad(53, 65, rng, 22)
	var coach := Fixtures.coach(51, rng)
	coach.national_selection = true
	var index := {}
	for player in pool:
		index[int(player.id)] = player
	for skill in [1, 10, 14, 18, 20]:
		coach.attributes.professionalism = skill
		var squad_value := 0.0
		var lineup_value := 0.0
		for seed in RUNS:
			rng.seed = 40000 + seed
			for id in NationalTeams.select_squad(pool, coach, rng):
				squad_value += NationalTeams.selection_value(index[id], coach) / 25.0 / RUNS
			rng.seed = 50000 + seed
			var lineup := LineupSelector.build(pool, [], coach, {"formation": "2-3-2", "style": "control"}, rng)
			for record in lineup.starters:
				lineup_value += LineupSelector.role_value(MatchRatings.of(record.player), str(record.slot), "control") * float(record.fit) / 8.0 / RUNS
		out.selection[skill] = {"squad_value": squad_value, "lineup_value": lineup_value}
	if not args.is_empty():
		var file := FileAccess.open(args[0], FileAccess.WRITE)
		file.store_string(JSON.stringify(out, "\t"))
	print("NATIONAL BALANCE ", JSON.stringify(out))
	get_tree().quit()
