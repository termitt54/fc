class_name SeasonReputation
extends RefCounted
## One reputation tick when a season closes.
## The preview is the expectation. Division strength (0–1000) is the level of the
## competition: the same finish moves a club further in a stronger division.
## Clubs move first. Players then take a small share of that result, scaled by
## minutes, and a personal bump when their rating beats what their ability suggests.
## A player's whole season, including the usual fame drift, stays inside the drift cap.


const CLUB_CAP := 20
const LEVEL_PULL := 8
const SURPRISE_SPAN := 32.0
const BAND_SHARE := 0.22
const PLAYER_RESULT_CAP := 15
const FULL_SEASON_MATCHES := 24.0
const PLAYER_SPILL := 0.35


static func plan(units: Array, season_number: int, lookup: Callable) -> Dictionary:
	var parts := {}
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY or not season_ready(unit):
			continue
		for piece in _club_parts(unit, season_number):
			var club_id := int(piece.get("club_id", 0))
			if club_id < 1:
				continue
			if not parts.has(club_id):
				parts[club_id] = []
			(parts[club_id] as Array).append(piece)
	var clubs := {}
	for club_id in parts:
		var current := _club_reputation(units, int(club_id))
		var delta := combine_club(current, parts[club_id])
		clubs[club_id] = {
			"reputation": PlayerTypes.clamp_reputation(current + delta),
			"delta": delta,
		}
	var players := {}
	var before := {}
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY or not season_ready(unit):
			continue
		var strength := competition_strength(unit)
		var bag: Dictionary = UnitSeasonStats.ensure(unit)
		for player_id in bag.keys():
			var row: Dictionary = bag[player_id]
			var matches := int(row.get("matches", 0))
			if matches < 1:
				continue
			var played_for := int(row.get("club_id", 0))
			var club_delta := int(clubs.get(played_for, {}).get("delta", 0))
			var player: Dictionary = lookup.call(int(player_id))
			var ability := int(player.get("current_ability", 50)) if not player.is_empty() else 50
			var rating := float(row.get("rating_sum", 0.0)) / float(matches)
			var piece := player_adjustment(strength, club_delta, matches, rating, ability)
			var key := int(player_id)
			players[key] = clampi(int(players.get(key, 0)) + piece, -PLAYER_RESULT_CAP, PLAYER_RESULT_CAP)
			if not before.has(key) and not player.is_empty():
				before[key] = PlayerTypes.clamp_reputation(int(player.get("reputation", 0)))
	return {"clubs": clubs, "players": players, "before": before}


static func write_clubs(units: Array, clubs: Dictionary) -> void:
	for club_id in clubs:
		var next_reputation := int(clubs[club_id].get("reputation", 0))
		var delta := int(clubs[club_id].get("delta", 0))
		for unit in units:
			if typeof(unit) != TYPE_DICTIONARY:
				continue
			var stored: Dictionary = unit.get("clubs_by_id", {})
			if not stored.has(club_id):
				continue
			var club: Dictionary = stored[club_id]
			club["reputation"] = next_reputation
			club["reputation_delta"] = delta
			stored[club_id] = club
			unit["clubs_by_id"] = stored


static func write_players(deltas: Dictionary, before: Dictionary, lookup: Callable) -> void:
	for player_id in deltas:
		var player: Dictionary = lookup.call(int(player_id))
		if player.is_empty():
			continue
		var start := int(before.get(player_id, player.get("reputation", 0)))
		var drifted := PlayerTypes.clamp_reputation(int(player.get("reputation", start)))
		var next_reputation := settled_player_reputation(start, drifted, int(deltas[player_id]))
		player["reputation"] = next_reputation
		player["reputation_delta"] = next_reputation - drifted
		PlayerMarket.refresh_value(player)


## Surprise against the preview, plus a short pull toward the finish's band around the division strength.
static func table_delta(strength: int, current: int, predicted: int, actual: int, field: int) -> int:
	return combine_club(current, [{
		"step": _place_step(strength, predicted, actual, field),
		"pull": _level_pull(strength, actual, field, current),
		"strength": strength,
	}])


## A cup or super cup: the title chance is the expectation. Winning as an outsider is worth more.
static func chance_delta(strength: int, current: int, title_chance: float, won: bool) -> int:
	var pull := 0
	if won:
		pull = clampi(strength - current, -LEVEL_PULL, LEVEL_PULL)
	return combine_club(current, [{
		"step": _chance_step(strength, title_chance, won),
		"pull": pull,
		"strength": strength,
	}])


static func combine_club(_current: int, parts: Array) -> int:
	var step := 0.0
	var best_strength := -1
	var pull := 0
	for part in parts:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		step += float(part.get("step", 0.0))
		var strength := int(part.get("strength", 0))
		if strength > best_strength:
			best_strength = strength
			pull = int(part.get("pull", 0))
	return clampi(int(round(step)) + pull, -CLUB_CAP, CLUB_CAP)


static func player_adjustment(
	strength: int,
	club_delta: int,
	matches: int,
	rating: float,
	current_ability: int
) -> int:
	if matches < 1:
		return 0
	var share := clampf(float(matches) / FULL_SEASON_MATCHES, 0.0, 1.0)
	var expected := 6.15 + float(current_ability - 50) * 0.025
	var gap := clampf(rating - expected, -1.6, 1.6)
	var weight := clampf(float(strength) / 1000.0, 0.0, 1.0)
	var personal := gap / 1.6 * 12.0 * share * weight
	var spill := float(club_delta) * PLAYER_SPILL * share
	return clampi(int(round(personal + spill)), -PLAYER_RESULT_CAP, PLAYER_RESULT_CAP)


## The result sits on top of the season's fame drift, and the sum cannot leave the drift window.
static func settled_player_reputation(before: int, drifted: int, result_delta: int) -> int:
	var proposed := drifted + result_delta
	var net := clampi(
		proposed - before,
		-PlayerMarket.REPUTATION_DRIFT_MAX,
		PlayerMarket.REPUTATION_DRIFT_MAX
	)
	return PlayerTypes.clamp_reputation(before + net)


static func season_ready(unit: Dictionary) -> bool:
	var playoff: Dictionary = unit.get("playoff", {})
	if bool(playoff.get("enabled", false)):
		return int(playoff.get("champion_id", 0)) > 0
	var matches: Array = unit.get("matches", [])
	return PlayoffManager.regular_complete(unit) and not matches.is_empty()


static func competition_strength(unit: Dictionary) -> int:
	if _is_division(unit):
		var raw: Variant = unit.get("division_strength", null)
		if raw == null:
			raw = unit.get("rules", {}).get("division_strength", null)
		return CompetitionUnitRepository.normalize_division_strength(raw)
	return _average_reputation(unit)


static func _club_parts(unit: Dictionary, season_number: int) -> Array:
	var strength := competition_strength(unit)
	var preview_ok := _preview_matches(unit, season_number)
	var playoff_places := _playoff_place_map(unit)
	var champion_id := _champion_id(unit, season_number)
	var table := _table_section_for(unit, -1)
	var parts: Array = []
	for club_id in _result_club_ids(unit):
		var playoff_place := int(playoff_places.get(club_id, 0))
		if playoff_place > 0:
			var section := _section(unit, "playoff", -1)
			var field := _field_size(section, playoff_places.size())
			var predicted := _predicted_place(section, club_id, playoff_place) if preview_ok else playoff_place
			var current := _reputation_of(unit, club_id)
			parts.append({
				"club_id": club_id,
				"step": _place_step(strength, predicted, playoff_place, field),
				"pull": _level_pull(strength, playoff_place, field, current),
				"strength": strength,
			})
			continue
		var division := _club_division(unit, club_id)
		var section := _table_section_for(unit, division)
		if not section.is_empty():
			var ranked := _ranked(unit, _rank_filter(unit, section))
			var actual := _index_of(ranked, club_id)
			if actual < 1:
				continue
			var predicted := _predicted_place(section, club_id, actual) if preview_ok else actual
			var current := _reputation_of(unit, club_id)
			parts.append({
				"club_id": club_id,
				"step": _place_step(strength, predicted, actual, ranked.size()),
				"pull": _level_pull(strength, actual, ranked.size(), current),
				"strength": strength,
			})
			continue
		if table.is_empty() and champion_id > 0 and preview_ok:
			var knockout := _knockout_section(unit)
			var chance := _title_chance(knockout, club_id) if preview_ok else 0.0
			var current := _reputation_of(unit, club_id)
			var won: bool = club_id == champion_id
			var pull := clampi(strength - current, -LEVEL_PULL, LEVEL_PULL) if won else 0
			parts.append({
				"club_id": club_id,
				"step": _chance_step(strength, chance, won),
				"pull": pull,
				"strength": strength,
			})
	return parts


static func _place_step(strength: int, predicted: int, actual: int, field: int) -> float:
	if field < 2 or actual < 1:
		return 0.0
	var expected := predicted if predicted >= 1 else actual
	var norm := clampf(float(expected - actual) / float(field - 1), -1.0, 1.0)
	return norm * SURPRISE_SPAN * clampf(float(strength) / 1000.0, 0.0, 1.0)


static func _chance_step(strength: int, title_chance: float, won: bool) -> float:
	var chance := clampf(title_chance / 100.0, 0.0, 1.0)
	var surprise := (1.0 - chance) if won else -chance
	return surprise * SURPRISE_SPAN * clampf(float(strength) / 1000.0, 0.0, 1.0)


static func _level_pull(strength: int, actual: int, field: int, current: int) -> int:
	if field < 2 or actual < 1:
		return 0
	var mid := 0.5 - float(actual - 1) / float(field - 1)
	var band := float(strength) + mid * BAND_SHARE * float(strength)
	return clampi(int(round(band)) - current, -LEVEL_PULL, LEVEL_PULL)


static func _preview_matches(unit: Dictionary, season_number: int) -> bool:
	var preview: Variant = unit.get("season_preview", null)
	if typeof(preview) != TYPE_DICTIONARY:
		return false
	return int((preview as Dictionary).get("season", -1)) == season_number


static func _is_division(unit: Dictionary) -> bool:
	var rules: Dictionary = unit.get("rules", {})
	var kind := str(unit.get("unit_kind", rules.get("unit_kind", "")))
	var competition := str(unit.get("competition_type", rules.get("competition_type", "")))
	return kind == CompetitionTypes.UNIT_DIVISION or competition == CompetitionTypes.TYPE_DIVISIONS


static func _average_reputation(unit: Dictionary) -> int:
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	var total := 0
	var count := 0
	for club_id in clubs:
		var club: Variant = clubs[club_id]
		if typeof(club) != TYPE_DICTIONARY:
			continue
		total += PlayerTypes.clamp_reputation(int(club.get("reputation", 0)))
		count += 1
	if count < 1:
		return 500
	return clampi(int(round(float(total) / float(count))), 0, 1000)


static func _club_reputation(units: Array, club_id: int) -> int:
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY:
			continue
		var stored: Dictionary = unit.get("clubs_by_id", {})
		if stored.has(club_id) and typeof(stored[club_id]) == TYPE_DICTIONARY:
			return PlayerTypes.clamp_reputation(int(stored[club_id].get("reputation", 0)))
	return 500


static func _reputation_of(unit: Dictionary, club_id: int) -> int:
	var stored: Dictionary = unit.get("clubs_by_id", {})
	if stored.has(club_id) and typeof(stored[club_id]) == TYPE_DICTIONARY:
		return PlayerTypes.clamp_reputation(int(stored[club_id].get("reputation", 0)))
	return 500


static func _result_club_ids(unit: Dictionary) -> Array:
	var ids: Array = []
	var seen := {}
	for row in unit.get("standings", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var club_id := int(row.get("club_id", 0))
		if club_id < 1 or seen.has(club_id):
			continue
		seen[club_id] = true
		ids.append(club_id)
	if not ids.is_empty():
		return ids
	var preview: Dictionary = unit.get("season_preview", {})
	for section in preview.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY:
			continue
		for row in section.get("rows", []):
			if typeof(row) != TYPE_DICTIONARY:
				continue
			var club_id := int(row.get("club_id", 0))
			if club_id < 1 or seen.has(club_id):
				continue
			seen[club_id] = true
			ids.append(club_id)
	return ids


static func _playoff_place_map(unit: Dictionary) -> Dictionary:
	var places := {}
	for row in PlayoffManager._playoff_places(unit):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var club_id := int(row.get("club_id", 0))
		if club_id > 0:
			places[club_id] = int(row.get("place", 0))
	return places


static func _champion_id(unit: Dictionary, season_number: int) -> int:
	var playoff: Dictionary = unit.get("playoff", {})
	var from_bracket := int(playoff.get("champion_id", 0))
	if from_bracket > 0:
		return from_bracket
	for entry in unit.get("winners", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if int(entry.get("season", 0)) != season_number:
			continue
		return int(entry.get("club_id", 0))
	return 0


static func _table_section_for(unit: Dictionary, division: int) -> Dictionary:
	var rules: Dictionary = unit.get("rules", {})
	if bool(rules.get("regular_season_enabled", false)):
		var regular := _section(unit, "regular", -1)
		if not regular.is_empty():
			return regular
	if division >= 0:
		var own := _section(unit, "division", division)
		if not own.is_empty():
			return own
	return _section(unit, "regular", -1)


static func _rank_filter(unit: Dictionary, section: Dictionary) -> int:
	if str(section.get("id", "")) == "division":
		return int(section.get("index", _club_division(unit, 0)))
	return -1


static func _section(unit: Dictionary, section_id: String, index: int) -> Dictionary:
	var preview: Dictionary = unit.get("season_preview", {})
	for section in preview.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY:
			continue
		if str(section.get("id", "")) != section_id:
			continue
		if index >= 0 and int(section.get("index", -1)) != index:
			continue
		return section
	return {}


static func _knockout_section(unit: Dictionary) -> Dictionary:
	var preview: Dictionary = unit.get("season_preview", {})
	for section in preview.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY:
			continue
		var kind := str(section.get("kind", ""))
		if kind == "knockout" or kind == "playoff":
			return section
	return {}


static func _ranked(unit: Dictionary, division: int) -> Array:
	var ranking: Array = RankingCriteria.parse_stored(unit.get("rules", {}).get("ranking_order", null))
	return PlayoffManager._sorted_division_rows(unit, division, ranking)


static func _index_of(ranked: Array, club_id: int) -> int:
	for i in ranked.size():
		if int(ranked[i].get("club_id", 0)) == club_id:
			return i + 1
	return 0


static func _club_division(unit: Dictionary, club_id: int) -> int:
	for row in unit.get("standings", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("club_id", 0)) == club_id:
			return int(row.get("division", 0))
	return 0


static func _predicted_place(section: Dictionary, club_id: int, fallback: int) -> int:
	for row in section.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("club_id", 0)) == club_id:
			var place := int(row.get("place", 0))
			return place if place >= 1 else fallback
	return fallback


static func _title_chance(section: Dictionary, club_id: int) -> float:
	for row in section.get("rows", []):
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if int(row.get("club_id", 0)) == club_id:
			return float(row.get("title_chance", 0.0))
	return 0.0


static func _field_size(section: Dictionary, fallback: int) -> int:
	var rows: Array = section.get("rows", [])
	return rows.size() if rows.size() >= 2 else maxi(fallback, 2)
