extends Node
## Cohort audit of the actual birth roll, without match simulation or storing players.
const Config := preload("res://game/youth_generation_config.gd")
const REPLICATES := 20
const SEASONS := 100
const LEGACY_BANDS := [[40, 49], [50, 59], [60, 69], [70, 79], [80, 89], [90, 100]]

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		get_tree().quit(1)
		return
	var input: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	Config.birth_config_path = "user://nonexistent_rarity_audit_config.json"
	Config.reset_birth_to_defaults(false)
	var actual: Array = input.club_talents
	var mixed: Array = []
	var elite: Array = []
	for i in 1000:
		mixed.append(actual[i % actual.size()])
		elite.append(100)
	var report := {"replicates": REPLICATES, "seasons": SEASONS, "scenarios": {}}
	for name in ["user_101", "mixed_1000", "elite_1000"]:
		var talents: Array = actual if name == "user_101" else mixed if name == "mixed_1000" else elite
		var summary := {"clubs": talents.size(), "expected_PA100_per_100_seasons": 0.0, "runs": []}
		for talent in talents:
			summary.expected_PA100_per_100_seasons += 6.0 * SEASONS * Config.potential_probability(int(talent), 100)
		for rep in REPLICATES:
			var rng := RandomNumberGenerator.new()
			rng.seed = 170000 + rep
			var before := RandomNumberGenerator.new()
			before.seed = 170000 + rep
			var row := {"births": 0, "PA80+": 0, "PA90+": 0, "PA95+": 0, "PA99+": 0, "PA100": 0,
				"old_PA100": 0, "peak_25_cohorts_PA100": 0, "old_peak_25_cohorts_PA100": 0}
			var cohorts: Array = []
			var active := 0
			var old_active := 0
			for season in SEASONS:
				var current := 0
				var old_current := 0
				for talent in talents:
					var slots := rng.randi_range(Config.YOUTH_SLOTS_MIN, Config.YOUTH_SLOTS_MAX)
					var old_slots := before.randi_range(Config.YOUTH_SLOTS_MIN, Config.YOUTH_SLOTS_MAX)
					for i in slots:
						var pa := Config.roll_birth_potential(int(talent), rng)
						row.births += 1
						for threshold in [80, 90, 95, 99]:
							if pa >= threshold:
								row["PA%d+" % threshold] += 1
						if pa == 100:
							current += 1
					for i in old_slots:
						if old_roll(int(talent), before, input.before_rows) == 100:
							old_current += 1
				row.PA100 += current
				row.old_PA100 += old_current
				active += current
				old_active += old_current
				cohorts.append([current, old_current])
				if cohorts.size() > 25:
					var removed: Array = cohorts.pop_front()
					active -= int(removed[0])
					old_active -= int(removed[1])
				row.peak_25_cohorts_PA100 = maxi(int(row.peak_25_cohorts_PA100), active)
				row.old_peak_25_cohorts_PA100 = maxi(int(row.old_peak_25_cohorts_PA100), old_active)
				if season % 20 == 0:
					await get_tree().process_frame
			summary.runs.append(row)
		report.scenarios[name] = summary
		print("RARITY SCENARIO ", name, " expected100=", summary.expected_PA100_per_100_seasons)
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("RARITY AUDIT complete")
	get_tree().quit()

func old_roll(talent: int, rng: RandomNumberGenerator, rows: Array) -> int:
	var roll := rng.randi_range(1, 1000)
	var sum := 0
	for band in 6:
		sum += int(rows[talent][band])
		if roll <= sum:
			return rng.randi_range(int(LEGACY_BANDS[band][0]), int(LEGACY_BANDS[band][1]))
	return 40
