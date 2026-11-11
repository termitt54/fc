extends RefCounted
## Simultaneous movement between league units of the same competition.
## Level 1 is above level 2. Groups inside a league are parallel pools.

static func plan(units: Array, standings: Callable) -> Dictionary:
	var pyramids: Dictionary = {}
	for i in units.size():
		var unit: Dictionary = units[i]
		if NationalTeams.is_unit(unit):
			continue
		if str(unit.get("unit_kind", "")) != CompetitionTypes.UNIT_DIVISION:
			continue
		if str(unit.get("competition_type", "")) not in [CompetitionTypes.TYPE_DIVISIONS, CompetitionTypes.TYPE_LEAGUE]:
			continue
		var competition_id := int(unit.get("competition_id", 0))
		if competition_id < 1:
			continue
		if not pyramids.has(competition_id):
			pyramids[competition_id] = []
		(pyramids[competition_id] as Array).append(i)

	var transfers: Array = []
	for indices in pyramids.values():
		indices.sort_custom(func(a: int, b: int) -> bool:
			return _level(units[a]) < _level(units[b])
		)
		var enabled := false
		for i in indices:
			var rules: Dictionary = units[i].get("rules", {})
			enabled = enabled or int(rules.get("teams_promote", 0)) > 0 or int(rules.get("teams_relegate", 0)) > 0
		if not enabled:
			continue
		var seen_levels: Dictionary = {}
		var seen_clubs: Dictionary = {}
		for i in indices:
			var unit: Dictionary = units[i]
			var level := _level(unit)
			if seen_levels.has(level):
				return DbResult.fail("Для повышений и понижений задайте лигам разные уровни «Ур.»: %s (уровень %d)." % [unit.get("name", ""), level])
			seen_levels[level] = true
			for club_id in _club_ids(unit):
				if seen_clubs.has(club_id):
					return DbResult.fail("Клуб %d включён сразу в несколько лиг одного турнира. Исправьте состав участников." % club_id)
				seen_clubs[club_id] = true

		for position in indices.size():
			var source: int = indices[position]
			var unit: Dictionary = units[source]
			var rules: Dictionary = unit.get("rules", {})
			var selected: Dictionary = {}
			for direction in ["teams_promote", "teams_relegate"]:
				var quota := maxi(int(rules.get(direction, 0)), 0)
				if quota == 0:
					continue
				var up: bool = direction == "teams_promote"
				var target_position: int = position - 1 if up else position + 1
				if target_position < 0 or target_position >= indices.size():
					return DbResult.fail("%s: задано %d мест на %s, но в этом турнире нет %s лиги. Добавьте лигу с другим «Ур.» или установите 0." % [unit.get("name", "Лига"), quota, "повышение" if up else "понижение", "вышестоящей" if up else "нижестоящей"])
				var candidates := _candidates(unit, quota, up, selected, standings)
				if candidates.size() != quota:
					return DbResult.fail("%s: недостаточно клубов для заданных повышений и понижений (%d мест)." % [unit.get("name", "Лига"), quota])
				for club_id in candidates:
					selected[club_id] = true
					transfers.append({"club_id": club_id, "from": source, "to": int(indices[target_position]), "direction": "promotion" if up else "relegation"})
	return DbResult.ok(transfers)


static func apply(units: Array, transfers: Array) -> void:
	# Capture club data before removing any participants; a middle league can
	# send teams in both directions and receive teams from both neighbours.
	var club_data: Dictionary = {}
	for transfer in transfers:
		var club_id := int(transfer["club_id"])
		var source: Dictionary = units[int(transfer["from"])]
		club_data[club_id] = source.get("clubs_by_id", {}).get(club_id, {})
	for transfer in transfers:
		var club_id := int(transfer["club_id"])
		var source: Dictionary = units[int(transfer["from"])]
		for division in source.get("divisions", []):
			(division["club_ids"] as Array).erase(club_id)
		(source.get("clubs_by_id", {}) as Dictionary).erase(club_id)
	for transfer in transfers:
		var club_id := int(transfer["club_id"])
		var target: Dictionary = units[int(transfer["to"])]
		var divisions: Array = target.get("divisions", [])
		if divisions.is_empty():
			divisions.append({"index": 0, "club_ids": []})
			target["divisions"] = divisions
		var smallest: Dictionary = divisions[0]
		for division in divisions:
			if (division["club_ids"] as Array).size() < (smallest["club_ids"] as Array).size():
				smallest = division
		(smallest["club_ids"] as Array).append(club_id)
		if not target.has("clubs_by_id"):
			target["clubs_by_id"] = {}
		target["clubs_by_id"][club_id] = club_data[club_id]


static func _level(unit: Dictionary) -> int:
	return int(unit.get("rules", {}).get("level", 1))


static func _club_ids(unit: Dictionary) -> Array:
	var ids: Array = []
	for division in unit.get("divisions", []):
		for club_id in division.get("club_ids", []):
			ids.append(int(club_id))
	return ids


## Clubs the configured quotas currently place in promotion and relegation.
## A missing neighbour league does not hide the places: the table shows the rule.
static func zone_club_ids(unit: Dictionary, standings: Callable) -> Dictionary:
	var rules: Dictionary = unit.get("rules", {})
	var selected: Dictionary = {}
	var promote: Array = []
	var relegate: Array = []
	var up := maxi(int(rules.get("teams_promote", 0)), 0)
	var down := maxi(int(rules.get("teams_relegate", 0)), 0)
	if up > 0:
		promote = _candidates(unit, up, true, selected, standings)
		for club_id in promote:
			selected[int(club_id)] = true
	if down > 0:
		relegate = _candidates(unit, down, false, selected, standings)
	return {"promote": promote, "relegate": relegate}


static func _candidates(unit: Dictionary, quota: int, up: bool, excluded: Dictionary, standings: Callable) -> Array:
	var table: Array = standings.call(unit)
	if not up:
		table.reverse()
	var participants := _club_ids(unit)
	var pools: Dictionary = {}
	var eligible: Array = []
	for row in table:
		var club_id := int(row.get("club_id", 0))
		if excluded.has(club_id) or not participants.has(club_id):
			continue
		eligible.append(club_id)
		var division := int(row.get("division", 0))
		if not pools.has(division):
			pools[division] = []
		(pools[division] as Array).append(club_id)
	var scope := CompetitionUnitRepository.normalize_scope(unit.get("rules", {}).get("movement_scope", CompetitionUnitRepository.MOVEMENT_SCOPE_DEFAULT))
	if scope == CompetitionUnitRepository.SCOPE_OVERALL or pools.size() <= 1:
		return eligible.slice(0, quota)

	# Take equally from each pool. If the total does not divide evenly, the
	# next best (or worst) team from each pool competes for the remaining places.
	var chosen: Array = []
	var depth := 0
	while chosen.size() < quota:
		var round_ids: Array = []
		for pool in pools.values():
			if depth < pool.size():
				round_ids.append(int(pool[depth]))
		if round_ids.is_empty():
			break
		for club_id in eligible:
			if round_ids.has(club_id):
				chosen.append(club_id)
				if chosen.size() == quota:
					break
		depth += 1
	return chosen
