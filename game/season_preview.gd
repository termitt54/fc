class_name SeasonPreview
extends RefCounted
## One snapshot before round 1, after the window has closed.
##
## A club's chance comes from three things: the squad on the pitch, the club's
## reputation, and the head coach's tactics and motivation. The long league
## trusts the squad. A cup or a playoff gives the coach more say, because one
## tie is noisier than a season.
##
## League-like units get a predicted table and, only when a playoff is configured,
## a separate knockout. Cups, pure knockouts and super cups are a bracket only.
## Groups get a seeded group stage and then a knockout.


const PrizeRulesScript := preload("res://database/repositories/world/prize_rules.gd")
const UnitRepository := preload("res://database/repositories/world/competition_unit_repository.gd")

const SIMS := 400
const TABLE_NOISE := 0.04
const KNOCKOUT_SHARPNESS := 11.0

const XI_SIZE := 11
const DEPTH_SIZE := 6

## Regular season: the squad plays itself into the table.
const REGULAR_SQUAD := 0.62
const REGULAR_REPUTATION := 0.23
const REGULAR_COACH := 0.15

## One tie: preparation and nerve matter more than they do over 30 rounds.
const KNOCKOUT_SQUAD := 0.55
const KNOCKOUT_REPUTATION := 0.20
const KNOCKOUT_COACH := 0.25

const GROUP_SIZE := 4
const GROUP_ADVANCE := 2


static func build(
	unit: Dictionary,
	season: int,
	squads_by_club: Dictionary,
	coaches_by_club: Dictionary
) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(unit.get("id", 1)) * 10007 + maxi(season, 1) * 17
	var clubs := _rate_clubs(unit, squads_by_club, coaches_by_club)
	var type_code := str(unit.get("competition_type", CompetitionTypes.TYPE_LEAGUE))
	var sections: Array = []
	match type_code:
		CompetitionTypes.TYPE_CUP:
			sections = _cup_sections(clubs, rng, "Кубок", "cup")
		CompetitionTypes.TYPE_KNOCKOUT:
			sections = _cup_sections(clubs, rng, "Плей-офф", "knockout")
		CompetitionTypes.TYPE_SUPER_CUP:
			sections = _supercup_sections(clubs, rng)
		CompetitionTypes.TYPE_GROUP_AND_PLAYOFF:
			sections = _group_sections(unit, clubs, rng)
		_:
			sections = _league_sections(unit, clubs, rng)
	return {
		"season": season,
		"competition_type": type_code,
		"sections": sections,
	}


static func _league_sections(unit: Dictionary, clubs: Array, rng: RandomNumberGenerator) -> Array:
	var divisions := _division_pools(unit, clubs)
	var sections: Array = []
	var multi := divisions.size() > 1
	var rules: Dictionary = unit.get("rules", {})
	var unified := bool(rules.get("regular_season_enabled", false)) or not multi
	if multi:
		for pool in divisions:
			var table := _simulate_table(pool.get("clubs", []), rng)
			sections.append(_table_section(
				"division",
				str(pool.get("title", "Дивизион")),
				"Кто возьмёт дивизион",
				table,
				int(pool.get("index", 0))
			))
	if unified:
		var table := _simulate_table(clubs, rng)
		sections.append(_table_section(
			"regular",
			"Регулярный сезон",
			"Кто закончит сезон первым",
			table,
			-1
		))
	var playoff_teams := _playoff_teams(unit)
	if playoff_teams >= 2:
		var field := _simulate_playoff(unit, divisions, clubs, playoff_teams, rng)
		sections.append({
			"id": "playoff",
			"title": "Плей-офф",
			"note": "Кто выйдет с регулярки и кто возьмёт плей-офф",
			"kind": "playoff",
			"rows": field,
		})
	return sections


static func _cup_sections(clubs: Array, rng: RandomNumberGenerator, title: String, section_id: String) -> Array:
	if clubs.is_empty():
		return []
	var result := _simulate_knockout(clubs, rng, false)
	return [{
		"id": section_id,
		"title": title,
		"note": "До жеребьёвки сетка случайная. Стадия — куда клуб доходит хотя бы в половине случаев.",
		"kind": "knockout",
		"rows": result.get("rows", []),
	}]


static func _supercup_sections(clubs: Array, rng: RandomNumberGenerator) -> Array:
	if clubs.size() <= 2:
		var rows := _two_match(clubs)
		return [{
			"id": "super_cup",
			"title": "Суперкубок",
			"note": "Один матч. Шансы из состава, репутации и тренера.",
			"kind": "knockout",
			"rows": rows,
		}]
	return _cup_sections(clubs, rng, "Суперкубок", "super_cup")


static func _group_sections(unit: Dictionary, clubs: Array, rng: RandomNumberGenerator) -> Array:
	if clubs.is_empty():
		return []
	var ranked := clubs.duplicate()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("regular", 0.0)) > float(b.get("regular", 0.0))
	)
	var group_count := maxi(1, int(ceil(float(ranked.size()) / float(GROUP_SIZE))))
	var groups: Array = []
	for _i in group_count:
		groups.append([])
	for i in ranked.size():
		(groups[i % group_count] as Array).append(ranked[i])
	var advance := GROUP_ADVANCE
	var configured := _playoff_teams(unit)
	if configured >= 2:
		advance = clampi(int(round(float(configured) / float(group_count))), 1, GROUP_SIZE - 1)
	var qualify_wins := {}
	var title_wins := {}
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		qualify_wins[club_id] = 0
		title_wins[club_id] = 0
	for _sim in SIMS:
		var qualified: Array = []
		for group in groups:
			var scored: Array = []
			for club in group:
				scored.append({
					"club_id": int(club.get("club_id", 0)),
					"score": float(club.get("regular", 0.0)) + rng.randfn(0.0, TABLE_NOISE),
				})
			scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
			)
			for i in mini(advance, scored.size()):
				var club_id := int(scored[i].get("club_id", 0))
				qualified.append(club_id)
				qualify_wins[club_id] = int(qualify_wins.get(club_id, 0)) + 1
		var winner := _play_seeded(qualified, clubs, rng)
		if winner > 0:
			title_wins[winner] = int(title_wins.get(winner, 0)) + 1
	return [
		{
			"id": "groups",
			"title": "Групповой этап",
			"note": "Группы посеяны по силе, из группы выходят %d. Жеребьёвка ещё впереди." % advance,
			"kind": "qualify",
			"rows": _chance_rows(clubs, qualify_wins, {}, "qualify_chance"),
		},
		{
			"id": "playoff",
			"title": "Плей-офф",
			"note": "Кто из вышедших из группы возьмёт турнир",
			"kind": "playoff",
			"rows": _chance_rows(clubs, qualify_wins, title_wins, "both"),
		},
	]


static func _rate_clubs(
	unit: Dictionary,
	squads_by_club: Dictionary,
	coaches_by_club: Dictionary
) -> Array:
	var rows: Array = []
	for club_id in _competitor_ids(unit):
		var club := _club_record(unit, club_id)
		var squad: Array = squads_by_club.get(club_id, [])
		var coach: Dictionary = coaches_by_club.get(club_id, {})
		var squad_q := _squad_quality(squad)
		var rep_q := clampf(float(int(club.get("reputation", 500))) / 1000.0, 0.0, 1.0)
		var coach_q := _coach_quality(coach)
		rows.append({
			"club_id": club_id,
			"club_name": str(club.get("name", "Клуб #%d" % club_id)),
			"regular": REGULAR_SQUAD * squad_q + REGULAR_REPUTATION * rep_q + REGULAR_COACH * coach_q,
			"knockout": KNOCKOUT_SQUAD * squad_q + KNOCKOUT_REPUTATION * rep_q + KNOCKOUT_COACH * coach_q,
		})
	return rows


static func _competitor_ids(unit: Dictionary) -> Array:
	var ids: Array = []
	var seen := {}
	for division in unit.get("divisions", []):
		if typeof(division) != TYPE_DICTIONARY:
			continue
		for club_id in division.get("club_ids", []):
			var id := int(club_id)
			if id < 1 or seen.has(id):
				continue
			seen[id] = true
			ids.append(id)
	if not ids.is_empty():
		return ids
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	for club_id in clubs.keys():
		var id := int(club_id)
		if id > 0:
			ids.append(id)
	return ids


static func _club_record(unit: Dictionary, club_id: int) -> Dictionary:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	if clubs.has(club_id) and typeof(clubs[club_id]) == TYPE_DICTIONARY:
		return clubs[club_id]
	return {"name": "Клуб #%d" % club_id, "reputation": 500}


static func _division_pools(unit: Dictionary, clubs: Array) -> Array:
	var by_id := {}
	for club in clubs:
		by_id[int(club.get("club_id", 0))] = club
	var divisions: Array = unit.get("divisions", [])
	if divisions.size() <= 1:
		return [{
			"index": 0,
			"title": "Регулярный сезон",
			"clubs": clubs,
		}]
	var pools: Array = []
	for i in divisions.size():
		var division: Dictionary = divisions[i]
		var members: Array = []
		for club_id in division.get("club_ids", []):
			var id := int(club_id)
			if by_id.has(id):
				members.append(by_id[id])
		pools.append({
			"index": int(division.get("index", i)),
			"title": "Дивизион %d" % (int(division.get("index", i)) + 1),
			"clubs": members,
		})
	return pools


static func _playoff_teams(unit: Dictionary) -> int:
	var rules: Dictionary = unit.get("rules", {})
	if rules.has("teams_playoff"):
		return maxi(0, int(rules.get("teams_playoff", 0)))
	return maxi(0, int(unit.get("playoff", {}).get("teams", 0)))


static func _playoff_scope(unit: Dictionary) -> String:
	var rules: Dictionary = unit.get("rules", {})
	var raw: Variant = rules.get("playoff_scope", unit.get("playoff", {}).get("scope", UnitRepository.PLAYOFF_SCOPE_DEFAULT))
	return UnitRepository.normalize_scope(raw, UnitRepository.PLAYOFF_SCOPE_DEFAULT)


static func _simulate_table(clubs: Array, rng: RandomNumberGenerator) -> Array:
	var place_sum := {}
	var titles := {}
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		place_sum[club_id] = 0
		titles[club_id] = 0
	if clubs.is_empty():
		return []
	for _sim in SIMS:
		var scored: Array = []
		for club in clubs:
			scored.append({
				"club_id": int(club.get("club_id", 0)),
				"score": float(club.get("regular", 0.0)) + rng.randfn(0.0, TABLE_NOISE),
			})
		scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
		)
		for i in scored.size():
			var club_id := int(scored[i].get("club_id", 0))
			place_sum[club_id] = int(place_sum.get(club_id, 0)) + i + 1
			if i == 0:
				titles[club_id] = int(titles.get(club_id, 0)) + 1
	var rows: Array = []
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		rows.append({
			"club_id": club_id,
			"club_name": str(club.get("club_name", "")),
			"place_sum": int(place_sum.get(club_id, 0)),
			"title_chance": _percent(int(titles.get(club_id, 0))),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var place := int(a.get("place_sum", 0)) - int(b.get("place_sum", 0))
		if place != 0:
			return place < 0
		return float(a.get("title_chance", 0.0)) > float(b.get("title_chance", 0.0))
	)
	for i in rows.size():
		rows[i]["place"] = i + 1
	return rows


static func _table_section(section_id: String, title: String, note: String, rows: Array, index: int) -> Dictionary:
	return {
		"id": section_id,
		"index": index,
		"title": title,
		"note": note,
		"kind": "table",
		"rows": rows,
	}


static func _simulate_playoff(
	unit: Dictionary,
	divisions: Array,
	clubs: Array,
	playoff_teams: int,
	rng: RandomNumberGenerator
) -> Array:
	var per_division := _playoff_scope(unit) == UnitRepository.SCOPE_PER_DIVISION and divisions.size() > 1
	var quota := UnitRepository.per_division_quota(playoff_teams, maxi(divisions.size(), 1))
	if per_division and quota < 1:
		return []
	var qualify_wins := {}
	var title_wins := {}
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		qualify_wins[club_id] = 0
		title_wins[club_id] = 0
	for _sim in SIMS:
		var qualified: Array = []
		if per_division:
			for pool in divisions:
				var picked := _top_ids(pool.get("clubs", []), quota, rng)
				for club_id in picked:
					qualified.append(club_id)
					qualify_wins[club_id] = int(qualify_wins.get(club_id, 0)) + 1
		else:
			var picked := _top_ids(clubs, playoff_teams, rng)
			for club_id in picked:
				qualified.append(club_id)
				qualify_wins[club_id] = int(qualify_wins.get(club_id, 0)) + 1
		var winner := _play_seeded(qualified, clubs, rng)
		if winner > 0:
			title_wins[winner] = int(title_wins.get(winner, 0)) + 1
	var rows := _chance_rows(clubs, qualify_wins, title_wins, "both")
	var shown: Array = []
	for row in rows:
		if float(row.get("qualify_chance", 0.0)) >= 1.0 or float(row.get("title_chance", 0.0)) >= 0.5:
			shown.append(row)
	return shown


static func _top_ids(clubs: Array, count: int, rng: RandomNumberGenerator) -> Array:
	var scored: Array = []
	for club in clubs:
		scored.append({
			"club_id": int(club.get("club_id", 0)),
			"score": float(club.get("regular", 0.0)) + rng.randfn(0.0, TABLE_NOISE),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var ids: Array = []
	for i in mini(count, scored.size()):
		ids.append(int(scored[i].get("club_id", 0)))
	return ids


static func _simulate_knockout(clubs: Array, rng: RandomNumberGenerator, seeded: bool) -> Dictionary:
	var reached := {}
	var titles := {}
	var total_rounds := PrizeRulesScript.playoff_round_count(maxi(clubs.size(), 2))
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		reached[club_id] = {}
		titles[club_id] = 0
	for _sim in SIMS:
		var outcome: Dictionary = _one_knockout(clubs, rng, seeded)
		var winner := int(outcome.get("winner", 0))
		if winner > 0:
			titles[winner] = int(titles.get(winner, 0)) + 1
		var depth: Dictionary = outcome.get("reached", {})
		for club_id in depth.keys():
			var round_no := int(depth[club_id])
			var hist: Dictionary = reached.get(club_id, {})
			hist[round_no] = int(hist.get(round_no, 0)) + 1
			reached[club_id] = hist
	var rows: Array = []
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		rows.append({
			"club_id": club_id,
			"club_name": str(club.get("club_name", "")),
			"title_chance": _percent(int(titles.get(club_id, 0))),
			"stage": _likely_stage(reached.get(club_id, {}), total_rounds),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("title_chance", 0.0)) > float(b.get("title_chance", 0.0))
	)
	for i in rows.size():
		rows[i]["place"] = i + 1
	return {"rows": rows}


static func _one_knockout(clubs: Array, rng: RandomNumberGenerator, seeded: bool) -> Dictionary:
	var ids: Array = []
	for club in clubs:
		ids.append(int(club.get("club_id", 0)))
	var reached := {}
	if seeded:
		ids = _order_by_knockout(ids, clubs, rng)
		var winner := _play_seeded(ids, clubs, rng)
		return {"winner": winner, "reached": reached}
	var alive := _shuffle(ids, rng)
	var round_no := 1
	for club_id in alive:
		reached[club_id] = round_no
	while alive.size() > 1:
		var nxt: Array = []
		var i := 0
		while i < alive.size():
			if i + 1 >= alive.size():
				nxt.append(int(alive[i]))
				reached[int(alive[i])] = round_no + 1
				break
			var winner := _tie(int(alive[i]), int(alive[i + 1]), clubs, rng)
			nxt.append(winner)
			reached[winner] = round_no + 1
			i += 2
		alive = nxt
		round_no += 1
	var champion := int(alive[0]) if not alive.is_empty() else 0
	return {"winner": champion, "reached": reached}


static func _play_seeded(ids: Array, clubs: Array, rng: RandomNumberGenerator) -> int:
	var ranked := _order_by_knockout(ids, clubs, rng)
	if ranked.is_empty():
		return 0
	if ranked.size() == 1:
		return int(ranked[0])
	var size := 1
	while size < ranked.size():
		size *= 2
	var slots: Array = []
	slots.resize(size)
	for i in size:
		slots[i] = -1
	var positions := _seed_positions(size)
	for i in positions.size():
		var seed := int(positions[i])
		if seed <= ranked.size():
			slots[i] = int(ranked[seed - 1])
	var current := slots
	while current.size() > 1:
		var nxt: Array = []
		for i in range(0, current.size(), 2):
			var away := -1
			if i + 1 < current.size():
				away = int(current[i + 1])
			nxt.append(_tie(int(current[i]), away, clubs, rng))
		current = nxt
	return int(current[0]) if not current.is_empty() else 0


static func _order_by_knockout(ids: Array, clubs: Array, rng: RandomNumberGenerator) -> Array:
	var strength := {}
	for club in clubs:
		strength[int(club.get("club_id", 0))] = float(club.get("knockout", 0.0))
	var scored: Array = []
	for club_id in ids:
		var id := int(club_id)
		if id < 1:
			continue
		scored.append({
			"club_id": id,
			"score": float(strength.get(id, 0.0)) + rng.randfn(0.0, TABLE_NOISE * 0.65),
		})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("score", 0.0)) > float(b.get("score", 0.0))
	)
	var ordered: Array = []
	for row in scored:
		ordered.append(int(row.get("club_id", 0)))
	return ordered


## 1-based seed in bracket slot order: 1 vs last, halves kept apart.
static func _seed_positions(size: int) -> Array:
	var positions: Array = [1]
	var span := 1
	while span < size:
		var nxt: Array = []
		for seed in positions:
			nxt.append(int(seed))
			nxt.append(span * 2 + 1 - int(seed))
		positions = nxt
		span *= 2
	return positions


static func _tie(home_id: int, away_id: int, clubs: Array, rng: RandomNumberGenerator) -> int:
	if home_id < 1:
		return away_id
	if away_id < 1:
		return home_id
	var home := _knockout_of(clubs, home_id)
	var away := _knockout_of(clubs, away_id)
	var diff := home - away
	var chance := 1.0 / (1.0 + exp(-diff * KNOCKOUT_SHARPNESS))
	if rng.randf() < chance:
		return home_id
	return away_id


static func _knockout_of(clubs: Array, club_id: int) -> float:
	for club in clubs:
		if int(club.get("club_id", 0)) == club_id:
			return float(club.get("knockout", 0.0))
	return 0.0


static func _two_match(clubs: Array) -> Array:
	if clubs.is_empty():
		return []
	if clubs.size() == 1:
		var only: Dictionary = clubs[0]
		return [{
			"club_id": int(only.get("club_id", 0)),
			"club_name": str(only.get("club_name", "")),
			"place": 1,
			"title_chance": 100.0,
			"stage": "Титул",
		}]
	var home: Dictionary = clubs[0]
	var away: Dictionary = clubs[1]
	if float(away.get("knockout", 0.0)) > float(home.get("knockout", 0.0)):
		var swap := home
		home = away
		away = swap
	var diff := float(home.get("knockout", 0.0)) - float(away.get("knockout", 0.0))
	var home_chance := 100.0 / (1.0 + exp(-diff * KNOCKOUT_SHARPNESS))
	return [
		{
			"club_id": int(home.get("club_id", 0)),
			"club_name": str(home.get("club_name", "")),
			"place": 1,
			"title_chance": home_chance,
			"stage": "Финал",
		},
		{
			"club_id": int(away.get("club_id", 0)),
			"club_name": str(away.get("club_name", "")),
			"place": 2,
			"title_chance": 100.0 - home_chance,
			"stage": "Финал",
		},
	]


static func _likely_stage(histogram: Dictionary, total_rounds: int) -> String:
	var deepest := 1
	for round_no in range(1, total_rounds + 2):
		var times := 0
		for key in histogram.keys():
			if int(key) >= round_no:
				times += int(histogram[key])
		if float(times) / float(SIMS) >= 0.5:
			deepest = round_no
	if deepest > total_rounds:
		return "Титул"
	return PrizeRulesScript.playoff_round_label(deepest, total_rounds)


static func _chance_rows(clubs: Array, qualify_wins: Dictionary, title_wins: Dictionary, mode: String) -> Array:
	var rows: Array = []
	for club in clubs:
		var club_id := int(club.get("club_id", 0))
		var row := {
			"club_id": club_id,
			"club_name": str(club.get("club_name", "")),
		}
		if mode != "title":
			row["qualify_chance"] = _percent(int(qualify_wins.get(club_id, 0)))
		if mode != "qualify_chance":
			row["title_chance"] = _percent(int(title_wins.get(club_id, 0)))
		rows.append(row)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var title := float(a.get("title_chance", 0.0)) - float(b.get("title_chance", 0.0))
		if absf(title) > 0.01:
			return title > 0.0
		return float(a.get("qualify_chance", 0.0)) > float(b.get("qualify_chance", 0.0))
	)
	for i in rows.size():
		rows[i]["place"] = i + 1
	return rows


static func _percent(wins: int) -> float:
	return float(wins) * 100.0 / float(SIMS)


static func _squad_quality(players: Array) -> float:
	var ratings: Array = []
	for player in players:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		if bool(player.get("is_youth", false)) or bool(player.get("is_reserve", false)):
			continue
		ratings.append(int(player.get("current_ability", player.get("overall", 40))))
	if ratings.is_empty():
		return 0.45
	ratings.sort()
	ratings.reverse()
	var xi_n := mini(XI_SIZE, ratings.size())
	var xi := 0.0
	for i in xi_n:
		xi += float(ratings[i])
	xi /= float(xi_n)
	var depth := xi
	var depth_n := mini(DEPTH_SIZE, ratings.size() - xi_n)
	if depth_n > 0:
		var sum := 0.0
		for i in depth_n:
			sum += float(ratings[xi_n + i])
		depth = sum / float(depth_n)
	return clampf((xi * 0.82 + depth * 0.18) / 100.0, 0.05, 1.0)


static func _coach_quality(coach: Dictionary) -> float:
	if coach.is_empty():
		return 0.5
	var attributes: Dictionary = coach.get("attributes", {})
	var tactics := int(attributes.get("tactics", coach.get("tactics", 10)))
	var motivation := int(attributes.get("motivation", coach.get("motivation", 10)))
	tactics = clampi(tactics, 1, 20)
	motivation = clampi(motivation, 1, 20)
	return float(tactics + motivation) / 40.0


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> Array:
	var copy: Array = items.duplicate()
	for i in range(copy.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = copy[i]
		copy[i] = copy[j]
		copy[j] = tmp
	return copy
