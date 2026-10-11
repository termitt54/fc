class_name PlayoffManager
extends RefCounted
## Seeds / advances DIVISIONS playoff brackets.


static func estimate_days(playoff: Dictionary) -> int:
	if not bool(playoff.get("enabled", false)):
		return 0
	var teams: int = maxi(int(playoff.get("teams", 0)), 0)
	if teams < 2:
		return 0
	var rounds := _rounds_for_teams(teams)
	var per_series := _max_days_per_series(playoff)
	return rounds * per_series


static func regular_complete(unit: Dictionary) -> bool:
	var has_regular := false
	for match_row in unit.get("matches", []):
		if str(match_row.get("stage", "REGULAR")) != "REGULAR":
			continue
		has_regular = true
		if not bool(match_row.get("played", false)):
			return false
	return true if has_regular else (unit.get("matches", []) as Array).is_empty()


static func maybe_start(unit: Dictionary, season_day: int, next_match_id: int) -> Dictionary:
	var playoff: Dictionary = unit.get("playoff", {})
	if not bool(playoff.get("enabled", false)):
		return {"started": false, "next_match_id": next_match_id}
	if bool(playoff.get("started", false)) or bool(playoff.get("finished", false)):
		return {"started": false, "next_match_id": next_match_id}
	if not regular_complete(unit):
		return {"started": false, "next_match_id": next_match_id}

	var qualifiers := _select_qualifiers(unit)
	if qualifiers.size() < 2:
		playoff["started"] = true
		playoff["finished"] = true
		playoff["champion_id"] = int(qualifiers[0]) if not qualifiers.is_empty() else 0
		return {"started": true, "next_match_id": next_match_id}

	var pairs := _seed_pairs(qualifiers, str(playoff.get("seeding", PlayoffRules.SEEDING_OVERALL)), unit)
	playoff["started"] = true
	playoff["finished"] = false
	playoff["current_round"] = 1
	playoff["series"] = []
	playoff["matches"] = []
	playoff["champion_id"] = 0
	unit["playoff"] = playoff

	var match_id := next_match_id
	var start_day := season_day + 1
	for i in pairs.size():
		var pair: Dictionary = pairs[i]
		match_id = _append_series(
			unit, playoff, 1, int(pair.get("slot", i)),
			int(pair.get("home_id", 0)), int(pair.get("away_id", 0)),
			i + 1, start_day, match_id, false
		)

	return {"started": true, "next_match_id": match_id}


static func after_day_simulated(unit: Dictionary, season_day: int, next_match_id: int, season_number: int) -> Dictionary:
	var playoff: Dictionary = unit.get("playoff", {})
	if not bool(playoff.get("enabled", false)) or not bool(playoff.get("started", false)):
		return {"changed": false, "next_match_id": next_match_id}
	if bool(playoff.get("finished", false)):
		return {"changed": false, "next_match_id": next_match_id}

	_sync_series_from_matches(unit)
	var changed := false
	var match_id := next_match_id

	# Resolve completed series before scheduling anything else.
	for series in playoff.get("series", []):
		if bool(series.get("complete", false)):
			continue
		if _series_has_unplayed(playoff, int(series.get("id", 0))):
			continue
		if _is_series_decided(series, playoff):
			_mark_series_winner(series, playoff)
			changed = true

	# Schedule next game only for unfinished, undecided series in current round.
	for series in playoff.get("series", []):
		if bool(series.get("complete", false)):
			continue
		if int(series.get("round", 0)) != int(playoff.get("current_round", 1)):
			continue
		if _series_has_unplayed(playoff, int(series.get("id", 0))):
			continue
		if _is_series_decided(series, playoff):
			_mark_series_winner(series, playoff)
			changed = true
			continue
		var next_game := _next_series_game(series, playoff, season_day + 1, match_id)
		if not next_game.is_empty():
			(playoff["matches"] as Array).append(next_game)
			(unit["matches"] as Array).append(next_game)
			match_id += 1
			changed = true

	if int(playoff.get("champion_id", 0)) > 0 and _all_series_complete(playoff):
		if not bool(playoff.get("finished", false)):
			playoff["finished"] = true
			changed = true

	# Advance while the current round is complete (including auto-bye rounds).
	while int(playoff.get("champion_id", 0)) == 0 and _round_complete(playoff):
		var advanced := _advance_round(unit, season_day, match_id, season_number)
		match_id = int(advanced.get("next_match_id", match_id))
		changed = changed or bool(advanced.get("changed", false))
		if not bool(advanced.get("changed", false)):
			break

	unit["playoff"] = playoff
	capture_season_if_ready(unit, season_number)
	return {"changed": changed, "next_match_id": match_id}


static func is_unit_season_complete(unit: Dictionary) -> bool:
	var playoff: Dictionary = unit.get("playoff", {})
	if bool(playoff.get("enabled", false)):
		return bool(playoff.get("finished", false))
	return regular_complete(unit)


static func _rounds_for_teams(teams: int) -> int:
	var n := maxi(teams, 2)
	var rounds := 0
	while n > 1:
		n = int(ceil(float(n) / 2.0))
		rounds += 1
	return rounds


static func _max_days_per_series(playoff: Dictionary) -> int:
	match PlayoffRules.normalize_format(playoff.get("format", PlayoffRules.FORMAT_DEFAULT)):
		PlayoffRules.FORMAT_BEST_OF:
			var wins := PlayoffRules.normalize_series_wins(playoff.get("series_wins", 3))
			return wins * 2 - 1
		PlayoffRules.FORMAT_TWO_LEGGED:
			return 2
		_:
			return 1


static func _select_qualifiers(unit: Dictionary) -> Array:
	var playoff: Dictionary = unit.get("playoff", {})
	var teams: int = maxi(int(playoff.get("teams", 0)), 0)
	var scope := CompetitionUnitRepository.normalize_scope(
		playoff.get("scope", CompetitionUnitRepository.PLAYOFF_SCOPE_DEFAULT),
		CompetitionUnitRepository.PLAYOFF_SCOPE_DEFAULT
	)
	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))

	if scope == CompetitionUnitRepository.SCOPE_PER_DIVISION:
		var divisions: Array = unit.get("divisions", [])
		var per := CompetitionUnitRepository.per_division_quota(teams, maxi(divisions.size(), 1))
		var ids: Array = []
		for division in divisions:
			var div_index: int = int(division.get("index", 0))
			var rows := _sorted_division_rows(unit, div_index, ranking)
			for i in mini(per, rows.size()):
				ids.append(int(rows[i].get("club_id", 0)))
		return ids

	var overall := _sorted_division_rows(unit, -1, ranking)
	var result: Array = []
	for i in mini(teams, overall.size()):
		result.append(int(overall[i].get("club_id", 0)))
	return result


static func _sorted_division_rows(unit: Dictionary, division: int, ranking: Array) -> Array:
	var rows: Array = []
	for row in unit.get("standings", []):
		if division >= 0 and int(row.get("division", 0)) != division:
			continue
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _compare_standings(a, b, ranking) < 0
	)
	return rows


static func _compare_standings(a: Dictionary, b: Dictionary, ranking: Array) -> int:
	for code in ranking:
		var cmp := 0
		match str(code):
			RankingCriteria.POINTS:
				cmp = int(b.get("points", 0)) - int(a.get("points", 0))
			RankingCriteria.GOAL_DIFF:
				cmp = int(b.get("goal_diff", 0)) - int(a.get("goal_diff", 0))
			RankingCriteria.GOALS_FOR:
				cmp = int(b.get("goals_for", 0)) - int(a.get("goals_for", 0))
			RankingCriteria.WINS:
				cmp = int(b.get("won", 0)) - int(a.get("won", 0))
			_:
				cmp = 0
		if cmp != 0:
			return cmp
	return int(a.get("club_id", 0)) - int(b.get("club_id", 0))


static func _seed_pairs(qualifiers: Array, seeding: String, unit: Dictionary) -> Array:
	var teams: Array = qualifiers.duplicate()
	match PlayoffRules.normalize_seeding(seeding):
		PlayoffRules.SEEDING_CROSS:
			return _with_slots(_cross_seed_pairs(unit, teams))
		PlayoffRules.SEEDING_SAME_PLACE:
			return _with_slots(_same_place_pairs(unit, teams))
		PlayoffRules.SEEDING_DRAW:
			teams.shuffle()
			return _adjacent_pairs(teams)
		_:
			return _seeded_bracket_pairs(teams)


## 1 vs last in a fixed bracket so #1 and #2 sit on opposite halves.
static func _seeded_bracket_pairs(teams: Array) -> Array:
	var count := teams.size()
	if count < 2:
		return []
	var size := 1
	while size < count:
		size *= 2
	var order := _bracket_seed_order(size)
	var pairs: Array = []
	var slot := 0
	var i := 0
	while i + 1 < order.size():
		var a := int(order[i]) - 1
		var b := int(order[i + 1]) - 1
		var home_id := int(teams[a]) if a < count else 0
		var away_id := int(teams[b]) if b < count else 0
		if home_id > 0 or away_id > 0:
			pairs.append({"home_id": home_id, "away_id": away_id, "slot": slot})
			slot += 1
		i += 2
	return pairs


## Seed numbers in visual slot order: (1,n), (n/2, n/2+1), then the other half.
static func _bracket_seed_order(size: int) -> Array:
	var order: Array = [1]
	while order.size() < size:
		var next: Array = []
		var mirror := order.size() * 2 + 1
		for seed in order:
			next.append(int(seed))
			next.append(mirror - int(seed))
		order = next
	return order


static func _adjacent_pairs(teams: Array) -> Array:
	var pairs: Array = []
	var slot := 0
	var i := 0
	while i < teams.size():
		var home_id := int(teams[i])
		var away_id := int(teams[i + 1]) if i + 1 < teams.size() else 0
		pairs.append({"home_id": home_id, "away_id": away_id, "slot": slot})
		slot += 1
		i += 2
	return pairs


static func _with_slots(pairs: Array) -> Array:
	for i in pairs.size():
		var pair: Dictionary = pairs[i]
		if not pair.has("slot"):
			pair["slot"] = i
		pairs[i] = pair
	return pairs


static func _bracket_pairs(teams: Array) -> Array:
	return _adjacent_pairs(teams)


static func _cross_seed_pairs(unit: Dictionary, fallback_teams: Array) -> Array:
	var divisions: Array = unit.get("divisions", [])
	if divisions.size() != 2:
		return _seeded_bracket_pairs(fallback_teams)
	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))
	var take := int(ceil(float(fallback_teams.size()) / 2.0))
	# Only playoff qualifiers from each division — not the full table.
	var a := _sorted_division_rows(unit, 0, ranking).slice(0, take)
	var b := _sorted_division_rows(unit, 1, ranking).slice(0, take)
	if a.is_empty() or b.is_empty():
		return _seeded_bracket_pairs(fallback_teams)
	var pairs: Array = []
	var count := mini(a.size(), b.size())
	for i in count:
		# 1A vs worst qualifier B, 2A vs next-worst B…
		var home := int(a[i].get("club_id", 0))
		var away := int(b[count - 1 - i].get("club_id", 0))
		pairs.append({"home_id": home, "away_id": away})
	return pairs


static func _same_place_pairs(unit: Dictionary, fallback_teams: Array) -> Array:
	var divisions: Array = unit.get("divisions", [])
	if divisions.size() != 2:
		return _seeded_bracket_pairs(fallback_teams)
	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))
	var take := int(ceil(float(fallback_teams.size()) / 2.0))
	var a := _sorted_division_rows(unit, 0, ranking).slice(0, take)
	var b := _sorted_division_rows(unit, 1, ranking).slice(0, take)
	if a.is_empty() or b.is_empty():
		return _seeded_bracket_pairs(fallback_teams)
	var pairs: Array = []
	for i in mini(a.size(), b.size()):
		pairs.append({
			"home_id": int(a[i].get("club_id", 0)),
			"away_id": int(b[i].get("club_id", 0)),
		})
	return pairs


static func _make_playoff_match(
	match_id: int,
	season_day: int,
	series_id: int,
	game_index: int,
	home_id: int,
	away_id: int,
	is_third_place: bool
) -> Dictionary:
	return {
		"id": match_id,
		"matchday": season_day,
		"season_day": season_day,
		"home_id": home_id,
		"away_id": away_id,
		"home_goals": -1,
		"away_goals": -1,
		"played": false,
		"stage": "PLAYOFF",
		"series_id": series_id,
		"game_index": game_index,
		"is_third_place": is_third_place,
	}


static func _series_has_unplayed(playoff: Dictionary, series_id: int) -> bool:
	for match_row in playoff.get("matches", []):
		if int(match_row.get("series_id", 0)) != series_id:
			continue
		if not bool(match_row.get("played", false)):
			return true
	return false


static func _sync_series_from_matches(unit: Dictionary) -> void:
	var playoff: Dictionary = unit.get("playoff", {})
	for series in playoff.get("series", []):
		if bool(series.get("complete", false)):
			continue
		var sid: int = int(series.get("id", 0))
		series["home_wins"] = 0
		series["away_wins"] = 0
		series["home_goals"] = 0
		series["away_goals"] = 0
		series["games_played"] = 0
		for match_row in playoff.get("matches", []):
			if int(match_row.get("series_id", 0)) != sid:
				continue
			if not bool(match_row.get("played", false)):
				continue
			series["games_played"] = int(series.get("games_played", 0)) + 1
			var hg: int = int(match_row.get("home_goals", 0))
			var ag: int = int(match_row.get("away_goals", 0))
			var winner_id := match_winner_club_id(match_row)
			# Goals always counted for series home/away clubs.
			if int(match_row.get("home_id", 0)) == int(series.get("home_id", 0)):
				series["home_goals"] = int(series.get("home_goals", 0)) + hg
				series["away_goals"] = int(series.get("away_goals", 0)) + ag
			else:
				series["home_goals"] = int(series.get("home_goals", 0)) + ag
				series["away_goals"] = int(series.get("away_goals", 0)) + hg
			if winner_id == int(series.get("home_id", 0)):
				series["home_wins"] = int(series.get("home_wins", 0)) + 1
			elif winner_id == int(series.get("away_id", 0)):
				series["away_wins"] = int(series.get("away_wins", 0)) + 1


## Winner of a finished playoff game: open score, then shootout / stored winner.
static func match_winner_club_id(match_row: Dictionary) -> int:
	if not bool(match_row.get("played", false)):
		return 0
	var home_id: int = int(match_row.get("home_id", 0))
	var away_id: int = int(match_row.get("away_id", 0))
	var stored: int = int(match_row.get("winner_id", 0))
	if stored == home_id or stored == away_id:
		return stored
	var hg: int = int(match_row.get("home_goals", 0))
	var ag: int = int(match_row.get("away_goals", 0))
	if hg > ag:
		return home_id
	if ag > hg:
		return away_id
	var shootout: Dictionary = match_row.get("shootout", {})
	if shootout.is_empty():
		var report: Dictionary = match_row.get("report", {})
		if typeof(report) == TYPE_DICTIONARY:
			shootout = report.get("shootout", {})
	if typeof(shootout) != TYPE_DICTIONARY or shootout.is_empty():
		return 0
	var home_pens := int(shootout.get("home", 0))
	var away_pens := int(shootout.get("away", 0))
	if home_pens == away_pens:
		return 0
	return home_id if home_pens > away_pens else away_id


static func _is_series_decided(series: Dictionary, playoff: Dictionary) -> bool:
	var format := PlayoffRules.normalize_format(playoff.get("format", PlayoffRules.FORMAT_DEFAULT))
	var games: int = int(series.get("games_played", 0))
	match format:
		PlayoffRules.FORMAT_BEST_OF:
			var need := PlayoffRules.normalize_series_wins(playoff.get("series_wins", 3))
			return int(series.get("home_wins", 0)) >= need or int(series.get("away_wins", 0)) >= need
		PlayoffRules.FORMAT_TWO_LEGGED:
			if games < 2:
				return false
			return true
		_:
			return games >= 1


static func _mark_series_winner(series: Dictionary, playoff: Dictionary) -> void:
	var format := PlayoffRules.normalize_format(playoff.get("format", PlayoffRules.FORMAT_DEFAULT))
	var home_id: int = int(series.get("home_id", 0))
	var away_id: int = int(series.get("away_id", 0))
	var winner := home_id
	match format:
		PlayoffRules.FORMAT_BEST_OF:
			var home_wins: int = int(series.get("home_wins", 0))
			var away_wins: int = int(series.get("away_wins", 0))
			if home_wins != away_wins:
				winner = home_id if home_wins > away_wins else away_id
			else:
				var hg: int = int(series.get("home_goals", 0))
				var ag: int = int(series.get("away_goals", 0))
				winner = home_id if hg >= ag else away_id
		PlayoffRules.FORMAT_TWO_LEGGED:
			var hg: int = int(series.get("home_goals", 0))
			var ag: int = int(series.get("away_goals", 0))
			if hg == ag:
				winner = home_id if int(series.get("home_wins", 0)) >= int(series.get("away_wins", 0)) else away_id
			else:
				winner = home_id if hg > ag else away_id
		_:
			winner = home_id if int(series.get("home_wins", 0)) >= int(series.get("away_wins", 0)) else away_id
	series["complete"] = true
	series["winner_id"] = winner


static func _next_series_game(series: Dictionary, playoff: Dictionary, day: int, match_id: int) -> Dictionary:
	var format := PlayoffRules.normalize_format(playoff.get("format", PlayoffRules.FORMAT_DEFAULT))
	var games: int = int(series.get("games_played", 0))
	var home_id: int = int(series.get("home_id", 0))
	var away_id: int = int(series.get("away_id", 0))
	match format:
		PlayoffRules.FORMAT_TWO_LEGGED:
			if games >= 2:
				return {}
			# Second leg: swap home/away.
			return _make_playoff_match(
				match_id, day, int(series.get("id", 0)), games + 1,
				away_id, home_id, bool(series.get("is_third_place", false))
			)
		PlayoffRules.FORMAT_BEST_OF:
			var need := PlayoffRules.normalize_series_wins(playoff.get("series_wins", 3))
			var wins := int(series.get("home_wins", 0)) + int(series.get("away_wins", 0))
			if wins >= need * 2 - 1:
				return {}
			if int(series.get("home_wins", 0)) >= need or int(series.get("away_wins", 0)) >= need:
				return {}
			# Alternate venue. Keep scheduling past the theoretical max if a
			# draw slipped through without extra time / penalties.
			if games % 2 == 0:
				return _make_playoff_match(
					match_id, day, int(series.get("id", 0)), games + 1,
					home_id, away_id, bool(series.get("is_third_place", false))
				)
			return _make_playoff_match(
				match_id, day, int(series.get("id", 0)), games + 1,
				away_id, home_id, bool(series.get("is_third_place", false))
			)
		_:
			return {}


static func _round_complete(playoff: Dictionary) -> bool:
	var round_no: int = int(playoff.get("current_round", 1))
	var any := false
	for series in playoff.get("series", []):
		if int(series.get("round", 0)) != round_no:
			continue
		if bool(series.get("is_third_place", false)):
			continue
		any = true
		if not bool(series.get("complete", false)):
			return false
	return any


static func _all_series_complete(playoff: Dictionary) -> bool:
	var series_list: Array = playoff.get("series", [])
	if series_list.is_empty():
		return int(playoff.get("champion_id", 0)) > 0
	for series in series_list:
		if not bool(series.get("complete", false)):
			return false
	return true


static func _advance_round(unit: Dictionary, season_day: int, next_match_id: int, season_number: int) -> Dictionary:
	var playoff: Dictionary = unit.get("playoff", {})
	var round_no: int = int(playoff.get("current_round", 1))
	var round_series := _round_series_by_slot(playoff, round_no)
	var winners: Array = []
	var losers: Array = []
	for series in round_series:
		winners.append(int(series.get("winner_id", 0)))
		losers.append(_series_loser(series))

	if winners.size() <= 1:
		playoff["champion_id"] = int(winners[0]) if not winners.is_empty() else 0
		unit["playoff"] = playoff
		_record_winner(unit, int(playoff.get("champion_id", 0)), season_number)
		if _all_series_complete(playoff):
			playoff["finished"] = true
		return {"changed": true, "next_match_id": next_match_id}

	var next_round := round_no + 1
	playoff["current_round"] = next_round
	var match_id := next_match_id
	var start_day := season_day + 1
	var series_id := (playoff.get("series", []) as Array).size() + 1

	# Optional third place from previous round losers (only entering final).
	if bool(playoff.get("third_place", false)) and winners.size() == 2 and losers.size() >= 2:
		match_id = _append_series(
			unit, playoff, next_round, 0,
			int(losers[0]), int(losers[1]),
			series_id, start_day, match_id, true
		)
		series_id += 1

	var pairs := _adjacent_pairs(winners)
	for pair in pairs:
		match_id = _append_series(
			unit, playoff, next_round, int(pair.get("slot", 0)),
			int(pair.get("home_id", 0)), int(pair.get("away_id", 0)),
			series_id, start_day, match_id, false
		)
		series_id += 1

	unit["playoff"] = playoff
	return {"changed": true, "next_match_id": match_id}


static func _round_series_by_slot(playoff: Dictionary, round_no: int) -> Array:
	var rows: Array = []
	for series in playoff.get("series", []):
		if int(series.get("round", 0)) != round_no:
			continue
		if bool(series.get("is_third_place", false)):
			continue
		rows.append(series)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := int(a.get("slot", int(a.get("id", 0))))
		var sb := int(b.get("slot", int(b.get("id", 0))))
		if sa == sb:
			return int(a.get("id", 0)) < int(b.get("id", 0))
		return sa < sb
	)
	for i in rows.size():
		var series: Dictionary = rows[i]
		if not series.has("slot"):
			series["slot"] = i
	return rows


static func _series_loser(series: Dictionary) -> int:
	var winner_id: int = int(series.get("winner_id", 0))
	var home_id: int = int(series.get("home_id", 0))
	var away_id: int = int(series.get("away_id", 0))
	if winner_id == home_id:
		return away_id
	return home_id


static func _append_series(
	unit: Dictionary,
	playoff: Dictionary,
	round_no: int,
	slot: int,
	home_id: int,
	away_id: int,
	series_id: int,
	start_day: int,
	match_id: int,
	is_third_place: bool
) -> int:
	var is_bye := not is_third_place and (home_id < 1 or away_id < 1)
	var winner := 0
	if is_bye:
		winner = home_id if home_id > 0 else away_id
	(playoff["series"] as Array).append({
		"id": series_id,
		"round": round_no,
		"slot": slot,
		"home_id": home_id,
		"away_id": away_id,
		"home_wins": 0,
		"away_wins": 0,
		"home_goals": 0,
		"away_goals": 0,
		"games_played": 0,
		"complete": is_bye,
		"winner_id": winner,
		"is_third_place": is_third_place,
	})
	if is_bye or home_id < 1 or away_id < 1:
		return match_id
	var first := _make_playoff_match(
		match_id, start_day, series_id, 1, home_id, away_id, is_third_place
	)
	(playoff["matches"] as Array).append(first)
	(unit["matches"] as Array).append(first)
	return match_id + 1


static func capture_season_if_ready(unit: Dictionary, season_number: int) -> void:
	var playoff: Dictionary = unit.get("playoff", {})
	if bool(playoff.get("enabled", false)):
		if int(playoff.get("champion_id", 0)) < 1:
			return
	elif not regular_complete(unit) or (unit.get("matches", []) as Array).is_empty():
		return
	record_season_result(unit, season_number)


## Upserts one season: playoff places 1–4 and the regular-season top three.
## Called again after the third-place match, so 3rd and 4th fill in later.
static func record_season_result(unit: Dictionary, season_number: int) -> void:
	if season_number < 1:
		return
	var playoff_rows := _playoff_places(unit)
	var regular_rows := _regular_places(unit, 3)
	var champion_id := 0
	var champion_name := ""
	if not playoff_rows.is_empty():
		champion_id = int(playoff_rows[0].get("club_id", 0))
		champion_name = str(playoff_rows[0].get("club_name", ""))
	elif not regular_rows.is_empty():
		champion_id = int(regular_rows[0].get("club_id", 0))
		champion_name = str(regular_rows[0].get("club_name", ""))
	if champion_id < 1:
		return
	var entry := {
		"season": season_number,
		"club_id": champion_id,
		"club_name": champion_name,
		"place": 1,
		"playoff": playoff_rows,
		"regular": regular_rows,
	}
	var winners: Array = unit.get("winners", [])
	var replaced := false
	for i in winners.size():
		var existing: Dictionary = winners[i]
		if int(existing.get("season", 0)) != season_number:
			continue
		winners[i] = entry
		replaced = true
		break
	if not replaced:
		winners.append(entry)
	unit["winners"] = winners


static func _record_winner(unit: Dictionary, champion_id: int, season_number: int) -> void:
	if champion_id < 1:
		return
	record_season_result(unit, season_number)


static func _playoff_places(unit: Dictionary) -> Array:
	var playoff: Dictionary = unit.get("playoff", {})
	if not bool(playoff.get("enabled", false)):
		return []
	var ids: Array[int] = [0, 0, 0, 0]
	var final_series := _final_series(playoff)
	if not final_series.is_empty():
		ids[0] = int(final_series.get("winner_id", 0))
		ids[1] = _series_loser(final_series)
	elif int(playoff.get("champion_id", 0)) > 0:
		ids[0] = int(playoff.get("champion_id", 0))
	var third := _third_place_series(playoff)
	if not third.is_empty() and bool(third.get("complete", false)) and int(third.get("winner_id", 0)) > 0:
		ids[2] = int(third.get("winner_id", 0))
		ids[3] = _series_loser(third)
	elif third.is_empty():
		var losers := _order_by_table(unit, _semi_losers(playoff, final_series))
		if losers.size() >= 1:
			ids[2] = int(losers[0])
		if losers.size() >= 2:
			ids[3] = int(losers[1])
	var rows: Array = []
	for i in ids.size():
		if ids[i] < 1:
			continue
		rows.append(_club_place(unit, i + 1, ids[i]))
	return rows


static func _regular_places(unit: Dictionary, count: int) -> Array:
	var ranked := _sorted_standings(unit)
	var rows: Array = []
	for i in mini(count, ranked.size()):
		var standing: Dictionary = ranked[i]
		var club_id := int(standing.get("club_id", 0))
		if club_id < 1:
			continue
		var place := _club_place(unit, rows.size() + 1, club_id)
		place["points"] = int(standing.get("points", 0))
		place["goal_diff"] = int(standing.get("goal_diff", 0))
		rows.append(place)
	return rows


static func _final_series(playoff: Dictionary) -> Dictionary:
	var best_round := -1
	for series in playoff.get("series", []):
		if typeof(series) != TYPE_DICTIONARY or bool(series.get("is_third_place", false)):
			continue
		if not bool(series.get("complete", false)) or int(series.get("winner_id", 0)) < 1:
			continue
		best_round = maxi(best_round, int(series.get("round", 0)))
	if best_round < 1:
		return {}
	var in_round: Array = []
	for series in playoff.get("series", []):
		if typeof(series) != TYPE_DICTIONARY or bool(series.get("is_third_place", false)):
			continue
		if int(series.get("round", 0)) != best_round or not bool(series.get("complete", false)):
			continue
		in_round.append(series)
	if in_round.size() == 1:
		return in_round[0]
	return {}


static func _third_place_series(playoff: Dictionary) -> Dictionary:
	for series in playoff.get("series", []):
		if typeof(series) == TYPE_DICTIONARY and bool(series.get("is_third_place", false)):
			return series
	return {}


static func _semi_losers(playoff: Dictionary, final_series: Dictionary) -> Array:
	if final_series.is_empty():
		return []
	var round_no := int(final_series.get("round", 0)) - 1
	if round_no < 1:
		return []
	var losers: Array = []
	for series in playoff.get("series", []):
		if typeof(series) != TYPE_DICTIONARY or bool(series.get("is_third_place", false)):
			continue
		if int(series.get("round", 0)) != round_no or not bool(series.get("complete", false)):
			continue
		var loser := _series_loser(series)
		if loser > 0:
			losers.append(loser)
	return losers


static func _order_by_table(unit: Dictionary, club_ids: Array) -> Array:
	var rank := {}
	var ranked := _sorted_standings(unit)
	for i in ranked.size():
		rank[int(ranked[i].get("club_id", 0))] = i
	var ordered: Array = club_ids.duplicate()
	ordered.sort_custom(func(a: int, b: int) -> bool:
		return int(rank.get(a, 999)) < int(rank.get(b, 999))
	)
	return ordered


static func _sorted_standings(unit: Dictionary) -> Array:
	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))
	return _sorted_division_rows(unit, -1, ranking)


static func _club_place(unit: Dictionary, place: int, club_id: int) -> Dictionary:
	var club_name := "Клуб #%d" % club_id
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	if clubs.has(club_id):
		var stored := str(clubs[club_id].get("name", "")).strip_edges()
		if not stored.is_empty():
			club_name = stored
	return {"place": place, "club_id": club_id, "club_name": club_name}
