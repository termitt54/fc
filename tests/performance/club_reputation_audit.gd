extends Node
## Read-only inspection of a preserved benchmark copy; never advances or saves.

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2:
		get_tree().quit(2)
		return
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/").get_base_dir()
	var snapshot := args[0].replace("\\", "/").simplify_path()
	if not snapshot.begins_with(root + "/user-") or not snapshot.ends_with("-snapshot"):
		get_tree().quit(2)
		return
	SaveStore.database_path_override = snapshot.path_join("games.db")
	var store := SaveStore.new()
	var loaded := store.load_slot("autosave")
	assert(loaded["success"])
	var payload: Dictionary = loaded["data"]
	var editions: Array = []
	var projections: Array = []
	for unit in payload["units"]:
		if bool(unit.get("national", false)):
			continue
		for part in SeasonReputation._club_parts(unit, int(payload["season_number"])):
			part["unit_id"] = unit["id"]
			part["current"] = unit["clubs_by_id"][part["club_id"]]["reputation"]
			part["projected_delta"] = SeasonReputation.combine_club(part["current"], [part])
			projections.append(part)
		for winner in unit.get("winners", []):
			var result := store.tournament_season(int(payload["history_head"]), int(unit["id"]), int(winner["season"]))
			assert(result["success"])
			var edition: Dictionary = result["data"]
			if edition.is_empty():
				continue
			editions.append({"id": edition["id"], "season": edition["season"], "clubs_by_id": edition["clubs_by_id"], "standings": edition["standings"], "winners": edition["winners"], "rules": edition["rules"]})
	var calibrated := args.size() == 2 and args[1] == "calibrated"
	var output := "club_reputation_calibrated.json" if calibrated else "club_reputation_editions.json"
	var report := {"editions": editions, "projections": projections}
	if calibrated:
		report["replay"] = _replay(editions)
	var file := FileAccess.open(snapshot.path_join(output), FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report))
	file.close()
	print("CLUB AUDIT editions=", editions.size(), " clubs=", projections.size())
	get_tree().quit()


func _replay(editions: Array) -> Dictionary:
	# Old editions did not retain previews. The observed next-year delta lets us
	# recover round(surprise + title bonus), not the unrounded original surprise.
	# Hold these corrections/results/movements fixed: this is not a world simulation.
	var actual_by_season := {}
	var virtual := {}
	var names := {}
	var last_season := 0
	for edition in editions:
		var season := int(edition["season"])
		last_season = maxi(last_season, season)
		if not actual_by_season.has(season):
			actual_by_season[season] = {}
		for id in edition["clubs_by_id"]:
			actual_by_season[season][id] = int(edition["clubs_by_id"][id]["reputation"])
			names[id] = edition["clubs_by_id"][id]["name"]
	virtual = actual_by_season[1].duplicate()
	var trajectory: Array = [_summary(1, actual_by_season[1], virtual)]
	var out_of_range := 0
	var largest_delta := 0
	for season in range(1, last_season):
		var next := virtual.duplicate()
		for edition in editions:
			if int(edition["season"]) != season:
				continue
			var strength := int(edition["rules"]["division_strength"])
			var peers := 0.0
			for id in edition["clubs_by_id"]:
				peers += float(virtual[id])
			peers /= float(edition["clubs_by_id"].size())
			var places := {}
			for winner in edition["winners"]:
				for row in winner.get("playoff", []):
					places[int(row["club_id"])] = int(row["place"])
			var tables := {}
			for row in edition["standings"]:
				var filter := -1 if bool(edition["rules"].get("regular_season_enabled", false)) else int(row["division"])
				if not tables.has(filter):
					tables[filter] = SeasonReputation._ranked(edition, filter)
				var ranked: Array = tables[filter]
				var id := int(row["club_id"])
				var actual := SeasonReputation._index_of(ranked, id)
				var old_rep := int(actual_by_season[season][id])
				var old_target := float(strength) * (1.0 - 0.55 * float(actual - 1) / float(ranked.size() - 1))
				var old_pull := clampi(int(round((old_target - float(old_rep)) * 0.04)), -8, 8)
				var old_bonus := 8.0 * float(strength) / 1000.0 if int(places.get(id, 0)) == 1 else 0.0
				var old_delta := int(actual_by_season[season + 1][id]) - old_rep
				var surprise := float(old_delta - old_pull) - old_bonus
				if absf(surprise) > 8.0 * float(strength) / 1000.0 + 0.500001:
					out_of_range += 1
				var current := int(virtual[id])
				var pull := SeasonReputation._level_pull(strength, actual, ranked.size(), current, peers)
				var step := surprise * SeasonReputation._achievement_headroom(strength, current, peers) if surprise > 0.0 else surprise
				step += SeasonReputation._achievement_bonus(strength, current, int(places.get(id, 0)), peers)
				if int(places.get(id, 0)) == 1:
					step = maxf(step, float(-pull))
				var delta := SeasonReputation.combine_club(current, [{"step": step, "pull": pull, "strength": strength, "table_anchor": true}])
				next[id] = clampi(current + delta, 0, 1000)
				largest_delta = maxi(largest_delta, absi(int(next[id]) - current))
		virtual = next
		trajectory.append(_summary(season + 1, actual_by_season[season + 1], virtual))
	var clubs: Array = []
	for id in virtual:
		clubs.append({"id": id, "name": names[id], "initial": actual_by_season[1][id], "recorded": actual_by_season[last_season][id], "calibrated": virtual[id]})
	assert(out_of_range == 0)
	assert(largest_delta <= SeasonReputation.CLUB_CAP)
	return {"scope": "Frozen historical results/movements; rounded surprise inferred from recorded deltas; not a new world simulation", "trajectory": trajectory, "clubs": clubs, "out_of_range_surprises": out_of_range, "largest_delta": largest_delta}


func _summary(season: int, actual: Dictionary, virtual: Dictionary) -> Dictionary:
	var recorded_sum := 0
	var calibrated_sum := 0
	var minimum := 1000
	var maximum := 0
	var elite := 0
	for id in virtual:
		recorded_sum += int(actual[id])
		calibrated_sum += int(virtual[id])
		minimum = mini(minimum, int(virtual[id]))
		maximum = maxi(maximum, int(virtual[id]))
		if int(virtual[id]) >= 800:
			elite += 1
	return {"season": season, "recorded_mean": float(recorded_sum) / virtual.size(), "calibrated_mean": float(calibrated_sum) / virtual.size(), "calibrated_min": minimum, "calibrated_max": maximum, "calibrated_800_plus": elite}
