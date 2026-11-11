extends Node
## Fresh-state comparisons of reconstructed historical rosters; never writes saves.
const Config := preload("res://game/match_simulation_config.gd")

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
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	Config.apply_values(fixture.knobs, false)
	var engine: Variant = load(str(fixture.get("engine_script", "res://game/match_engine.gd")))
	var out: Array = []
	var count := int(fixture.get("matches", 500))
	for pair in fixture.get("pairs", [["Russia", "Scotland"], ["Russia", "Serbia"], ["Portugal", "Slovakia"]]):
		for same_coach in [false, true]:
			var home: Dictionary = fixture.teams[pair[0]].duplicate(true)
			var away: Dictionary = fixture.teams[pair[1]].duplicate(true)
			if same_coach:
				for spec in [home, away]:
					spec.coach = {"primary_style": "control", "backup_style": "control", "primary_formation": "2-3-2", "backup_formation": "2-3-2", "national_selection": true, "attributes": {"tactics": 10, "motivation": 10, "professionalism": 20}}
			var summary := {"pair": pair, "same_coach": same_coach, "wins": 0, "draws": 0, "losses": 0, "gf": 0, "ga": 0, "home_start": 0.0, "away_start": 0.0}
			for i in count:
				var rng := RandomNumberGenerator.new()
				rng.seed = 21500 + i
				var swap := bool(fixture.get("alternate_sides", false)) and i % 2 == 1
				var result: Dictionary = engine.simulate({"home": away if swap else home, "away": home if swap else away, "neutral": true, "allow_draw": true, "discipline": fixture.get("discipline", DisciplineRules.defaults())}, rng)
				var winner := -int(result.winner) if swap else int(result.winner)
				summary.wins += int(winner > 0)
				summary.draws += int(int(result.winner) == 0)
				summary.losses += int(winner < 0)
				summary.gf += int(result.away_goals if swap else result.home_goals)
				summary.ga += int(result.home_goals if swap else result.away_goals)
				summary.home_start += float(result.away_team.starting_ability if swap else result.home_team.starting_ability) / float(count)
				summary.away_start += float(result.home_team.starting_ability if swap else result.away_team.starting_ability) / float(count)
				if i % 50 == 0:
					await get_tree().process_frame
			out.append(summary)
			print("FRESH PROBE ", JSON.stringify(summary))
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	get_tree().quit()
