extends Node
const Coaching := preload("res://game/match_coaching.gd")
var report := {"errors": [], "frozen": [], "dynamic": []}
var source: Dictionary
var unit_id := 0
var started := 0

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-title-diagnostic"):
		push_error("Run only with the copied user world in fc-title-diagnostic")
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	started = Time.get_ticks_msec()
	var loaded: Dictionary = SaveStore.new().load_slot("autosave")
	if not _ok(loaded):
		return
	source = loaded["data"]
	unit_id = int(source["selected_unit_id"])
	if not _ok(GameSession.apply_save_payload(source.duplicate(true))):
		return
	var unit := _unit()
	report["source"] = {"saved_at": source["saved_at"], "season": source["season_number"],
		"day": source["season_day"], "unit_id": unit_id, "name": unit.get("name", ""),
		"rules": unit.get("rules", {}), "playoff": unit.get("playoff", {}).duplicate(true),
		"clubs": unit.get("clubs_by_id", {}).size(), "history": unit.get("winners", []).duplicate(true)}
	report["snapshot_clubs"] = _clubs()
	report["snapshot_outcome"] = _outcome()
	print("USER TITLE SOURCE ", JSON.stringify(report["source"]))
	if OS.get_cmdline_user_args().has("--inspect-only"):
		_finish()
		return
	# Complete the saved partial season, then use real interseason + market
	# to establish a full-season starting point. No reconstruction of seasons 1-19.
	if not await _complete():
		return
	if not _ok(GameSession.start_new_season()):
		return
	while GameSession.season_day < 1:
		if not _ok(GameSession.advance_day()):
			return
	var base := _payload()
	report["baseline_season"] = GameSession.season_number
	report["baseline_clubs"] = _clubs()
	# Twelve independent repeats of the same complete season, with and
	# without playoffs. Regular results must be identical for paired seeds.
	for playoffs in [true, false]:
		var starts := base.duplicate(true)
		if not playoffs:
			for entry in starts["units"]:
				entry["playoff"]["enabled"] = false
		var outcomes: Array = []
		for run in 12:
			if not _ok(GameSession.apply_save_payload(starts.duplicate(true))):
				return
			GameSession._rng.seed = 18000 + run
			if not await _complete():
				return
			outcomes.append(_outcome())
			print("USER TITLE FROZEN playoffs=", playoffs, " run=", run + 1)
		report["frozen"].append({"playoffs": playoffs, "outcomes": outcomes})
	# Two branches of eight seasons from exactly the same full-season base.
	for seed in [18000, 28000]:
		if not _ok(GameSession.apply_save_payload(base.duplicate(true))):
			return
		GameSession._rng.seed = seed
		var rows: Array = []
		var previous := {}
		for cycle in 8:
			var clubs := _clubs(previous)
			previous = _roster_ids()
			var log_start := GameSession.transfer_log.size()
			if not await _complete():
				return
			var outcome := _outcome()
			outcome.merge({"season": GameSession.season_number, "clubs": clubs})
			rows.append(outcome)
			print("USER TITLE DYNAMIC seed=", seed, " season=", GameSession.season_number,
				" regular=", outcome["regular_champion"], " playoff=", outcome["champion"])
			if cycle < 7:
				if not _ok(GameSession.start_new_season()):
					return
				while GameSession.season_day < 1:
					if not _ok(GameSession.advance_day()):
						return
				outcome["following_interseason_log"] = GameSession.transfer_log.slice(log_start).duplicate(true)
			await get_tree().process_frame
		report["dynamic"].append({"seed": seed, "seasons": rows})
	_finish()

func _complete() -> bool:
	var days := 0
	while not GameSession.season_finished:
		if not _ok(GameSession.advance_day()):
			return false
		days += 1
		if days % 5 == 0:
			await get_tree().process_frame
		if days > 500 or Time.get_ticks_msec() - started > 600000:
			report["errors"].append("Diagnostic time/day limit")
			_finish()
			return false
	return true

func _payload() -> Dictionary:
	return {"_native": true, "version": GameSession.SAVE_VERSION, "season_number": GameSession.season_number,
		"season_day": GameSession.season_day, "season_finished": GameSession.season_finished,
		"selected_unit_id": unit_id, "units": GameSession.units.duplicate(true),
		"players_by_club": GameSession.players_by_club.duplicate(true),
		"youth_players_by_club": GameSession.youth_players_by_club.duplicate(true),
		"reserve_players_by_club": GameSession.reserve_players_by_club.duplicate(true),
		"free_agents": GameSession.free_agents.duplicate(true),
		"coaches_by_club": GameSession.coaches_by_club.duplicate(true),
		"club_budgets": GameSession.club_budgets.duplicate(true), "transfer_log": GameSession.transfer_log.duplicate(true),
		"wages_paid_for_season": GameSession.wages_paid_for_season,
		"next_player_id": GameSession._next_player_id, "next_match_id": GameSession._next_match_id,
		"next_coach_id": GameSession._next_coach_id, "history_head": GameSession.history_head,
		"season_total_days": GameSession.season_total_days, "rng_seed": GameSession._rng.seed, "rng_state": GameSession._rng.state}

func _unit() -> Dictionary:
	for unit in GameSession.units:
		if int(unit["id"]) == unit_id:
			return unit
	return {}

func _outcome() -> Dictionary:
	var unit := _unit()
	var table := PlayoffManager._sorted_division_rows(unit, -1,
		RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null)))
	var champion := int(unit.get("playoff", {}).get("champion_id", 0))
	return {"regular_champion": int(table[0]["club_id"]), "champion": champion if champion > 0 else int(table[0]["club_id"]),
		"table": table.duplicate(true)}

func _roster_ids() -> Dictionary:
	var result := {}
	for id in _unit()["clubs_by_id"]:
		result[id] = {}
		for player in GameSession.get_club_players(id):
			result[id][int(player["id"])] = true
	return result

func _clubs(previous: Dictionary = {}) -> Array:
	var rows: Array = []
	var unit := _unit()
	var probe_rng := RandomNumberGenerator.new()
	probe_rng.seed = 999
	for id in unit["clubs_by_id"]:
		var club: Dictionary = unit["clubs_by_id"][id]
		var squad := GameSession.get_club_players(id)
		var counts := {}
		var retained := 0
		var ca := 0.0
		var age := 0.0
		var unavailable := 0
		for player in squad:
			ca += int(player.get("current_ability", 0))
			age += int(player.get("age", 0))
			retained += int(previous.get(id, {}).has(int(player["id"])))
			unavailable += int(not PlayerCondition.is_available(player))
			var pos := str(player["position"])
			counts[pos] = int(counts.get(pos, 0)) + 1
		var violations: Array = []
		for pos in PlayerTypes.SQUAD_SLOT_MIN:
			if int(counts.get(pos, 0)) < PlayerTypes.SQUAD_SLOT_MIN[pos] or int(counts.get(pos, 0)) > PlayerTypes.SQUAD_SLOT_MAX[pos]:
				violations.append(pos)
		# Primary-plan selection as a reference, not actual opponent-specific XI.
		var coach := GameSession.get_club_coach(id)
		var plan := TacticTypes.pick_match_plan(coach, probe_rng)
		var lineup := LineupSelector.build(squad,
			GameSession.get_club_reserve_players(id) + GameSession.get_club_youth_players(id), coach, plan, probe_rng, false)
		var starter_ids: Array = []
		var selection := 0.0
		var starters_ca := 0.0
		for row in lineup["starters"]:
			starter_ids.append(row["player"]["id"])
			selection += float(row["selection_score"])
			starters_ca += int(row["player"].get("current_ability", 0))
		rows.append({"id": id, "name": club.get("name", str(id)), "reputation": club.get("reputation", 0),
			"facilities": {"finance_level": club.get("finance_level", 10), "training_level": club.get("training_level", 10),
				"youth_academy": club.get("youth_academy", 10), "scouting_level": club.get("scouting_level", 10),
				"youth_search": club.get("youth_search", 10)},
			"budget": GameSession.get_club_budget(id), "size": squad.size(), "retained": retained,
			"mean_ca": ca / maxf(1, squad.size()), "mean_age": age / maxf(1, squad.size()),
			"primary_xi_ca": starters_ca / 8.0, "primary_xi_selection": selection / 8.0, "starter_ids": starter_ids,
			"unavailable": unavailable, "positions_outside_limits": violations,
			"coach": {"id": coach.get("id", 0), "age": coach.get("age", 0), "years": coach.get("contract_years", 0),
				"ability": coach.get("current_ability", 0), "attributes": coach.get("attributes", {}).duplicate(true),
				"primary_style": coach.get("primary_style", ""), "backup_style": coach.get("backup_style", "")}})
	return rows

func _ok(result: Dictionary) -> bool:
	if result.get("success", false):
		return true
	report["errors"].append(str(result.get("error", "Unknown error")))
	_finish()
	return false

func _finish() -> void:
	report["elapsed_seconds"] = float(Time.get_ticks_msec() - started) / 1000.0
	report["scope"] = "Copied autosave and world; no writes to original data; frozen repeats start at next full season; primary-plan selection metrics are reference values, not opponent-specific strength"
	var report_name := "user-title-inspect.json" if OS.get_cmdline_user_args().has("--inspect-only") else "user-title-stability.json"
	var file := FileAccess.open("res://tests/performance/results/" + report_name, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("USER TITLE END errors=", report["errors"], " seconds=", report["elapsed_seconds"])
	get_tree().quit(0 if report["errors"].is_empty() else 1)
