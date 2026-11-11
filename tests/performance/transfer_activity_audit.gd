extends Node
## Isolated market windows with real contract renewals. No matches/aging claimed.
const Builder = preload("res://tests/performance/load_benchmark.gd")
const Market = preload("res://game/transfer_market.gd")
const Job = preload("res://game/transfer_market_job.gd")
var report := {"windows": [], "illegal_squads": 0}

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size() >= 1)
	var first_season := 2
	var windows := 10
	if args.size() > 2:
		var snapshot := args[2].replace("\\", "/").simplify_path()
		assert(snapshot.contains("/.benchmark-runtime/user-") and snapshot.ends_with("-snapshot"))
		SaveStore.database_path_override = snapshot.path_join("games.db")
		var loaded := SaveStore.new().load_slot("autosave")
		assert(loaded.success and GameSession.apply_save_payload(loaded.data).success)
		first_season = GameSession.season_number + 1
		windows = 3
		report["source"] = "Archived user snapshot, season %d; market/contract-only projection" % GameSession.season_number
	else:
		var builder := Builder.new()
		builder._options["clubs"] = 64
		builder._options["league-size"] = 8
		builder._rng.seed = 732154
		assert(GameSession.apply_save_payload(builder._build_world()).success)
		builder.free()
	var sliced := args.size() > 1 and args[1] == "sliced"
	var rng := RandomNumberGenerator.new()
	rng.seed = 141517
	for season in range(first_season, first_season + windows):
		GameSession.season_number = season
		GameSession._rng.seed = 141517 + season
		GameSession._process_contract_renewals()
		var start_index := GameSession.transfer_log.size()
		var started := Time.get_ticks_usec()
		for day in range(-5, 0):
			GameSession.season_day = day
			if sliced:
				var job := Job.new(Market, GameSession, rng)
				while not job.step():
					pass
			else:
				Market.run_day(GameSession, rng)
		var row := {"season": season, "paid": 0, "free": 0, "fees": 0, "ms": (Time.get_ticks_usec() - started) / 1000.0}
		for entry in GameSession.transfer_log.slice(start_index):
			if entry.direction == "in":
				row["paid" if int(entry.fee) > 0 else "free"] += 1
				row.fees += int(entry.fee)
		row["paid_percent"] = 100.0 * row.paid / maxf(1.0, row.paid + row.free)
		report.windows.append(row)
		for squad in GameSession.players_by_club.values():
			if not PlayerTypes.is_squad_shape_legal(squad):
				report.illegal_squads += 1
		# Same income in each comparison, not a new finance policy.
		for id in GameSession.club_budgets:
			GameSession.club_budgets[id] += 5000000
		print("MARKET AUDIT ", JSON.stringify(row))
		await get_tree().process_frame
	report["paid"] = 0
	report["free"] = 0
	for row in report.windows:
		report.paid += row.paid
		report.free += row.free
	report["paid_percent"] = 100.0 * report.paid / maxf(1.0, report.paid + report.free)
	report["sliced"] = sliced
	var file := FileAccess.open(args[0], FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("MARKET TOTAL ", report.paid_percent, " illegal=", report.illegal_squads)
	get_tree().quit(0 if report.illegal_squads == 0 else 1)
