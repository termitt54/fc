class_name CupCompetition
extends RefCounted
## Independent cup pipeline. Source divisions are read-only. All state is JSON-saveable.

static func enabled(unit: Dictionary) -> bool:
	return not (unit.get("cup_config", {}) as Dictionary).get("stages", []).is_empty()

static func validate(config: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var stages: Variant = config.get("stages", [])
	if not stages is Array or stages.is_empty():
		errors.append("Добавьте хотя бы один этап.")
		return errors
	var sources := {}
	for i in stages.size():
		if not stages[i] is Dictionary:
			errors.append("Некорректный этап %d." % (i + 1))
			continue
		var s: Dictionary = stages[i]
		var title := "Этап %d" % (i + 1)
		if str(s.get("name", "")).strip_edges().is_empty():
			errors.append(title + ": укажите название.")
		if str(s.get("kind", "")) not in ["KNOCKOUT", "GROUPS"]:
			errors.append(title + ": выберите формат.")
		if str(s.get("draw", "RANDOM")) not in ["RANDOM", "ELO", "REPUTATION", "DIVISION"]:
			errors.append(title + ": некорректная жеребьёвка.")
		if int(s.get("legs", 1)) not in [1, 2]:
			errors.append(title + ": допустим один или два матча / круга.")
		if int(s.get("groups", 1)) < 1 or int(s.get("qualify", 1)) < 1 or int(s.get("advance", 1)) < 1:
			errors.append(title + ": количество групп и проходящих команд должно быть положительным.")
		if int(s.get("gap", 2)) < 1 or int(s.get("start_day", 1)) < 1:
			errors.append(title + ": дни и интервалы должны быть положительными.")
		for id in source_ids(s):
			sources[int(id)] = true
		if s.has("slots"): continue
		var mode := selection_mode(s)
		if mode not in ["ALL", "REMAINING", "TOP", "BOTTOM", "RANGE", "MANUAL"]:
			errors.append(title + ": некорректное правило отбора.")
		if int(s.get("place_from", 1)) < 1 or int(s.get("place_to", 1)) < int(s.get("place_from", 1)) or int(s.get("place_count", 1)) < 1:
			errors.append(title + ": проверьте диапазон мест и число команд.")
	if sources.is_empty():
		errors.append("Выберите дивизионы, из которых входят участники.")
	return errors

static func selection_mode(stage: Dictionary) -> String:
	return str(stage.get("selection_mode", "MANUAL" if bool(stage.get("selected_only", false)) else "ALL"))

static func source_ids(stage: Dictionary) -> Array:
	if not stage.has("slots"): return stage.get("source_units", [])
	var ids: Array = []
	for slot in stage["slots"]:
		var id := int(slot.get("unit_id", 0))
		if id > 0 and id not in ids: ids.append(id)
	return ids

static func output_count(stage: Dictionary) -> int:
	return int(stage.get("groups", 1)) * int(stage.get("qualify", 1)) if str(stage.get("kind", "")) == "GROUPS" else int(stage.get("advance", 1))

static func participants(stage: Dictionary, cup: Dictionary, units: Array) -> Dictionary:
	if stage.has("slots"):
		var resolved := {"ids": [], "clubs": {}, "origins": {}}
		for slot in stage["slots"]:
			var rule := {"source_units": [int(slot.get("unit_id", 0))], "selection_mode": "RANGE", "place_from": int(slot.get("place", 0)), "place_to": int(slot.get("place", 0))}
			if int(rule["place_from"]) < 1: continue
			var found := participants(rule, cup, units)
			resolved["ids"].append_array(found["ids"])
			resolved["clubs"].merge(found["clubs"], true)
			resolved["origins"].merge(found["origins"], true)
		return resolved
	var ids: Array = []
	var clubs := {}
	var origins := {}
	for source in units:
		if int(source.get("competition_id", 0)) != int(cup.get("competition_id", 0)) or str(source.get("unit_kind", "")) != "DIVISION":
			continue
		if int(source.get("id", 0)) not in stage.get("source_units", []):
			continue
		var ranked: Array = []
		var eligible := {}
		for division in source.get("divisions", []):
			for id in division.get("club_ids", []): eligible[int(id)] = true
		var standings := GameSession.sorted_standings(source)
		for row in standings:
			if eligible.has(int(row["club_id"])): ranked.append(int(row["club_id"]))
		for division in source.get("divisions", []):
			for raw in division.get("club_ids", []):
				if int(raw) not in ranked: ranked.append(int(raw))
		var mode := selection_mode(stage)
		var chosen: Array = ranked
		match mode:
			"TOP": chosen = ranked.slice(0, int(stage.get("place_count", 1)))
			"BOTTOM": chosen = ranked.slice(maxi(0, ranked.size() - int(stage.get("place_count", 1))))
			"RANGE": chosen = ranked.slice(int(stage.get("place_from", 1)) - 1, int(stage.get("place_to", 1)))
		for raw in chosen:
				var id := int(raw)
				if mode == "MANUAL" and id not in stage.get("club_ids", []):
					continue
				if id not in ids:
					ids.append(id)
					clubs[id] = source.get("clubs_by_id", {}).get(id, source.get("clubs_by_id", {}).get(str(id), {}))
					origins[id] = int(source.get("id", 0))
	return {"ids": ids, "clubs": clubs, "origins": origins}

static func validate_world(cup: Dictionary, units: Array) -> PackedStringArray:
	var config: Dictionary = cup.get("cup_config", {})
	var errors := validate(config)
	if not errors.is_empty():
		return errors
	var count := 0
	var seen := {}
	var slot_keys := {}
	for i in config["stages"].size():
		var s: Dictionary = config["stages"][i]
		var title := str(s["name"])
		if s.has("slots"):
			if int(s.get("team_count", 0)) < 2 or s["slots"].size() + count != int(s.get("team_count", 0)):
				errors.append(title + ": число слотов с учётом предыдущего этапа не совпадает с числом команд.")
			for slot in s["slots"]:
				var key := "%d:%d" % [int(slot.get("unit_id", 0)), int(slot.get("place", 0))]
				if int(slot.get("unit_id", 0)) < 1 or int(slot.get("place", 0)) < 1:
					errors.append(title + ": заполните все слоты.")
				if slot_keys.has(key): errors.append(title + ": одно место дивизиона выбрано повторно.")
				slot_keys[key] = true
		for source_id in source_ids(s):
			var exists := false
			for source in units:
				if int(source.get("id", 0)) == int(source_id) and int(source.get("competition_id", 0)) == int(cup.get("competition_id", 0)) and str(source.get("unit_kind", "")) == "DIVISION":
					exists = true
			if not exists:
				errors.append(title + ": исходный дивизион отсутствует в турнире.")
		var p := participants(s, cup, units)
		if s.has("slots") and p["ids"].size() != s["slots"].size():
			errors.append(title + ": указанного места нет в исходном дивизионе.")
		var new_count := 0
		for id in p["ids"]:
			if seen.has(id):
				if s.has("slots"): errors.append(title + ": клуб уже участвовал на предыдущем этапе.")
				continue
			seen[id] = true
			new_count += 1
		count += new_count
		if count < 2:
			errors.append(title + ": необходимо хотя бы две команды.")
		if str(s["kind"]) == "GROUPS":
			var groups := int(s.get("groups", 1))
			var qualify := int(s.get("qualify", 1))
			if count < groups * 2 or qualify >= int(count / groups):
				errors.append(title + ": в каждой группе нужны минимум две команды и хотя бы одна выбывающая.")
			count = groups * qualify
		else:
			var advance := int(s.get("advance", 1))
			if advance >= count:
				errors.append(title + ": число проходящих должно быть меньше числа участников.")
			count = advance
	if count != 1:
		errors.append("Последний этап должен определять одного победителя.")
	return errors

static func initialize_all(units: Array, season: int, world_seed: int = 0) -> PackedStringArray:
	var errors := PackedStringArray()
	for cup in units:
		if not enabled(cup):
			continue
		var checked := validate_world(cup, units)
		if not checked.is_empty():
			for message in checked:
				errors.append(str(cup.get("name", "Кубок")) + ": " + message)
	if not errors.is_empty():
		return errors
	var next_id := 1
	for u in units:
		for m in u.get("matches", []):
			next_id = maxi(next_id, int(m.get("id", 0)) + 1)
	for cup in units:
		if not enabled(cup):
			continue
		cup["matches"] = []
		cup["divisions"] = []
		cup["standings"] = []
		cup["playoff"] = {"enabled": false}
		cup["cup_state"] = {"index": -1, "finished": false, "outputs": [], "entered": [], "stages": [], "season": season, "rng_state": 0}
		if not NationalTeams.due(cup, season):
			cup["cup_state"]["finished"] = true
			cup["cup_state"]["skipped"] = true
		cup["clubs_by_id"] = {}
		var origins := {}
		var levels := {}
		for source in units:
			levels[int(source.get("id", 0))] = int(source.get("rules", {}).get("level", source.get("level", 1)))
		for s in cup["cup_config"]["stages"]:
			var all_sources: Dictionary = s.merged({"selection_mode": "ALL", "selected_only": false}, true)
			all_sources["source_units"] = source_ids(s)
			all_sources.erase("slots")
			var p := participants(all_sources, cup, units)
			cup["clubs_by_id"].merge(p["clubs"], true)
			origins.merge(p["origins"], true)
		cup["cup_origins"] = origins
		cup["cup_levels"] = levels
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("cup:%s:%s:%s" % [cup.get("id", 0), season, world_seed])
		cup["cup_state"]["rng_state"] = rng.state
		# Start after league calendars, leaving their match days and player load untouched.
		var start := 1
		for u in units:
			if not enabled(u) and not NationalTeams.is_unit(u):
				for m in u.get("matches", []):
					start = maxi(start, int(m.get("season_day", 0)) + 2)
		cup["cup_state"]["earliest_day"] = start
	return errors

static func after_day(cup: Dictionary, units: Array, day: int, next_id: int) -> int:
	var state: Dictionary = cup["cup_state"]
	if bool(state["finished"]):
		return next_id
	if int(state["index"]) < 0:
		for other in units:
			if not enabled(other) and not NationalTeams.is_unit(other) and not PlayoffManager.is_unit_season_complete(other):
				return next_id
		return _start_stage(cup, units, maxi(day + 2, int(state.get("earliest_day", 1))), next_id)
	var current: Dictionary = state["stages"].back()
	var all_played := true
	var by_id := {}
	for played in cup["matches"]:
		by_id[int(played["id"])] = played
	for m in current["matches"]:
		# Match rows may no longer share references after loading a save.
		var played: Dictionary = by_id.get(int(m["id"]), {})
		for field in ["played", "home_goals", "away_goals", "winner_id", "shootout", "extra_time"]:
			if played.has(field): m[field] = played[field]
		if not bool(m.get("played", false)):
			all_played = false
	if not all_played:
		return next_id
	var spec: Dictionary = cup["cup_config"]["stages"][int(state["index"])]
	var output: Array = []
	if str(spec["kind"]) == "GROUPS":
		var tables := group_tables(current)
		for table in tables:
			for row in table.slice(0, int(spec.get("qualify", 1))):
				output.append(int(row["club_id"]))
	else:
		output = current.get("byes", []).duplicate()
		for pair in current.get("pairs", []):
			var hg := 0
			var ag := 0
			var winner := 0
			for m in current["matches"]:
				if int(m.get("cup_pair", -1)) != int(pair["index"]):
					continue
				var home_first := int(m["home_id"]) == int(pair["home"])
				hg += int(m.get("home_goals", 0)) if home_first else int(m.get("away_goals", 0))
				ag += int(m.get("away_goals", 0)) if home_first else int(m.get("home_goals", 0))
				winner = int(m.get("winner_id", 0))
			output.append(int(pair["home"]) if hg > ag else (int(pair["away"]) if ag > hg else winner))
	current["outputs"] = output
	current["complete"] = true
	state["outputs"] = output
	if str(spec["kind"]) == "KNOCKOUT" and output.size() > int(spec.get("advance", 1)):
		return _schedule(cup, units, spec, output, day + int(spec.get("gap", 2)), next_id)
	if int(state["index"]) + 1 < cup["cup_config"]["stages"].size():
		return _start_stage(cup, units, day + int(spec.get("gap", 2)), next_id)
	state["finished"] = true
	state["champion_id"] = int(output[0]) if not output.is_empty() else 0
	var champion := int(state["champion_id"])
	var clubs: Dictionary = cup.get("clubs_by_id", {})
	var identity: Dictionary = clubs.get(champion, clubs.get(str(champion), {}))
	var entry := {"season": int(state["season"]), "club_id": champion, "club_name": str(identity.get("name", "")), "place": 1, "playoff": [{"club_id": champion, "club_name": str(identity.get("name", "")), "place": 1}], "regular": []}
	var history: Array = cup.get("winners", [])
	history.append(entry)
	cup["winners"] = history
	return next_id

static func _start_stage(cup: Dictionary, units: Array, day: int, next_id: int) -> int:
	var state: Dictionary = cup["cup_state"]
	state["index"] = int(state["index"]) + 1
	var spec: Dictionary = cup["cup_config"]["stages"][int(state["index"])]
	var entrants: Array = state["outputs"].duplicate()
	for id in participants(spec, cup, units)["ids"]:
		if id not in state["entered"]:
			entrants.append(id)
			state["entered"].append(id)
	return _schedule(cup, units, spec, entrants, maxi(day, int(spec.get("start_day", 1))), next_id)

static func _schedule(cup: Dictionary, units: Array, spec: Dictionary, entrants: Array, day: int, next_id: int) -> int:
	var state: Dictionary = cup["cup_state"]
	var rng := RandomNumberGenerator.new()
	rng.state = int(state["rng_state"])
	var ordered := entrants.duplicate()
	for i in range(ordered.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: Variant = ordered[i]
		ordered[i] = ordered[j]
		ordered[j] = swap
	var draw := str(spec.get("draw", "RANDOM"))
	if draw != "RANDOM":
		ordered.sort_custom(func(a, b): return _score(cup, int(a), draw) > _score(cup, int(b), draw))
	state["rng_state"] = rng.state
	var current := {"name": spec["name"], "kind": spec["kind"], "index": state["index"], "entrants": entrants.duplicate(), "matches": [], "pairs": [], "byes": [], "groups": [], "complete": false}
	state["stages"].append(current)
	var gap := int(spec.get("gap", 2))
	if str(spec["kind"]) == "GROUPS":
		var count := int(spec.get("groups", 1))
		for i in count:
			current["groups"].append({"index": i, "club_ids": []})
		for i in ordered.size():
			var pot := int(i / count)
			var slot := i % count if pot % 2 == 0 else count - 1 - i % count
			current["groups"][slot]["club_ids"].append(ordered[i])
		var generated := FixtureGenerator.build_regular_season(ordered, count, ceili(float(ordered.size()) / count), int(spec.get("legs", 1)), 0, rng, current["groups"])
		for m in generated["matches"]:
			m["id"] = next_id
			next_id += 1
			m["stage"] = "CUP_GROUP"
			m["cup_stage"] = spec["name"]
			m["season_day"] = _free_day(units, int(m["home_id"]), int(m["away_id"]), day + (int(m.get("season_day", 1)) - 1) * gap, gap)
			m["neutral"] = bool(spec.get("neutral", false))
			current["matches"].append(m.duplicate(true))
			cup["matches"].append(m)
	else:
		var target := int(spec.get("advance", 1))
		var pair_count := mini(int(ordered.size() / 2), ordered.size() - target)
		var bye_count := ordered.size() - pair_count * 2
		current["byes"] = ordered.slice(0, bye_count)
		var active := ordered.slice(bye_count)
		for i in pair_count:
			var home := int(active[i])
			var away := int(active[active.size() - 1 - i])
			current["pairs"].append({"index": i, "home": home, "away": away})
			var first_day := day
			for leg in int(spec.get("legs", 1)):
				var h := home if leg == 0 else away
				var a := away if leg == 0 else home
				var match_day := _free_day(units, h, a, first_day if leg == 0 else first_day + gap, gap)
				if leg == 0:
					first_day = match_day
				var m := {"id": next_id, "home_id": h, "away_id": a, "season_day": match_day, "stage": "CUP_KNOCKOUT", "cup_stage": spec["name"], "cup_pair": i, "cup_leg": leg, "cup_legs": int(spec.get("legs", 1)), "cup_round": state["stages"].size(), "played": false, "neutral": bool(spec.get("neutral", false)), "division": 0}
				next_id += 1
				current["matches"].append(m.duplicate(true))
				cup["matches"].append(m)
	return next_id

static func _score(cup: Dictionary, id: int, mode: String) -> float:
	var clubs: Dictionary = cup.get("clubs_by_id", {})
	var club: Dictionary = clubs.get(id, clubs.get(str(id), {}))
	if mode == "DIVISION":
		var origin: Dictionary = cup.get("cup_origins", {})
		var source := int(origin.get(id, origin.get(str(id), 0)))
		var levels: Dictionary = cup.get("cup_levels", {})
		return -float(levels.get(source, levels.get(str(source), 1)))
	if mode == "REPUTATION":
		return float(club.get("reputation", 0))
	return float(club.get("club_elo", {}).get("elo", club.get("elo", 500)))

static func _free_day(units: Array, home: int, away: int, earliest: int, gap: int) -> int:
	var day := earliest
	while true:
		var conflict := false
		for unit in units:
			for m in unit.get("matches", []):
				if absi(int(m.get("season_day", 0)) - day) >= gap:
					continue
				if int(m.get("home_id", 0)) in [home, away] or int(m.get("away_id", 0)) in [home, away]:
					conflict = true
		if not conflict:
			return day
		day += 1
	return day

static func group_tables(current: Dictionary) -> Array:
	var tables: Array = []
	for group in current.get("groups", []):
		var rows := {}
		for id in group["club_ids"]:
			rows[int(id)] = {"club_id": int(id), "played": 0, "points": 0, "goals_for": 0, "goals_against": 0, "goal_diff": 0}
		for m in current["matches"]:
			if not bool(m.get("played", false)) or not rows.has(int(m["home_id"])):
				continue
			for side in ["home", "away"]:
				var other := "away" if side == "home" else "home"
				var row: Dictionary = rows[int(m[side + "_id"])]
				var gf := int(m.get(side + "_goals", 0))
				var ga := int(m.get(other + "_goals", 0))
				row["played"] += 1
				row["goals_for"] += gf
				row["goals_against"] += ga
				row["goal_diff"] += gf - ga
				row["points"] += 3 if gf > ga else (1 if gf == ga else 0)
		var table: Array = rows.values()
		table.sort_custom(func(a, b):
			for key in ["points", "goal_diff", "goals_for"]:
				if int(a[key]) != int(b[key]):
					return int(a[key]) > int(b[key])
			return int(a["club_id"]) < int(b["club_id"])
		)
		tables.append(table)
	return tables
