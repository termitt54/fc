class_name SeasonReputation
extends RefCounted
## One reputation tick when a season closes.
## The preview is the expectation. Prestige follows results slowly, with both
## the configured competition level and its participants supplying context.
## Clubs move first. Players then take a small share of that result, scaled by
## minutes, and a personal bump when their rating beats what their ability suggests.
## A player's whole season, including the usual fame drift, stays inside the drift cap.


const CLUB_CAP := 20
const LEVEL_PULL := 4
const LEVEL_RATE := 0.02
const LEVEL_REFERENCE_RATIO := 0.80
const FINISH_SPAN := 120.0
const ACHIEVEMENT_HEADROOM := 200.0
const SURPRISE_SPAN := 8.0
const PLAYER_RESULT_CAP := 15
const FULL_SEASON_MATCHES := 24.0
const PLAYER_SPILL := 0.10


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
		var next_reputation := PlayerTypes.clamp_reputation(current + delta)
		clubs[club_id] = {
			"reputation": next_reputation,
			"delta": next_reputation - current,
		}
	var players := {}
	var before := {}
	for unit in units:
		if typeof(unit) != TYPE_DICTIONARY or not season_ready(unit):
			continue
		var strength := competition_strength(unit)
		var club_minutes := {}
		for match_row in unit.get("matches", []):
			if not bool(match_row.get("played", false)):
				continue
			var duration := MatchTypes.REGULAR_MINUTES + (MatchTypes.ET_MINUTES if bool(match_row.get("extra_time", false)) else 0)
			for id in [int(match_row.get("home_id", 0)), int(match_row.get("away_id", 0))]:
				club_minutes[id] = int(club_minutes.get(id, 0)) + duration
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
			# Old saves lack unit minutes: apportion the player's recorded minutes
			# by appearances in this unit, rather than treating a cameo as a full match.
			var minutes := int(row.get("minutes", -1))
			if minutes < 0:
				var season_stats := PlayerStats.season_of(player) if not player.is_empty() else {}
				minutes = int(round(float(season_stats.get("minutes", 0)) * float(matches) / maxf(float(season_stats.get("matches", matches)), 1.0)))
			var reference := maxi(int(club_minutes.get(played_for, 0)), int(FULL_SEASON_MATCHES * MatchTypes.REGULAR_MINUTES))
			var piece := player_adjustment(strength, club_delta, matches, rating, ability,
				minutes, reference, int(player.get("reputation", 0)))
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


## Omitting participant reputation uses the competition's neutral prestige level.
static func table_delta(strength: int, current: int, predicted: int, actual: int, field: int, participants: float = -1.0) -> int:
	return combine_club(current, [{
		"step": _table_step(strength, current, predicted, actual, field, participants),
		"pull": _level_pull(strength, actual, field, current, participants),
		"strength": strength,
	}])


## A cup or super cup: the title chance is the expectation. Winning as an outsider is worth more.
static func chance_delta(strength: int, current: int, title_chance: float, won: bool) -> int:
	var pull := 0
	if won:
		pull = maxi(0, _level_pull(strength, 1, 2, current))
	return combine_club(current, [{
		"step": _chance_step(strength, title_chance, won) * (_achievement_headroom(strength, current) if won else 1.0),
		"pull": pull,
		"strength": strength,
	}])


static func combine_club(_current: int, parts: Array) -> int:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return int(native.reputation_calc("combine",{"parts":parts}))
	var step := 0.0
	var best_strength := -1
	var best_priority := -1
	var pull := 0
	for part in parts:
		if typeof(part) != TYPE_DICTIONARY:
			continue
		step += float(part.get("step", 0.0))
		var strength := int(part.get("strength", 0))
		# A cup's missing table must not erase the league's prestige adjustment.
		var priority := 1 if bool(part.get("table_anchor", false)) else 0
		if priority > best_priority or (priority == best_priority and strength > best_strength):
			best_priority = priority
			best_strength = strength
			pull = int(part.get("pull", 0))
	return clampi(int(round(step)) + pull, -CLUB_CAP, CLUB_CAP)


static func player_adjustment(
	strength: int,
	club_delta: int,
	matches: int,
	rating: float,
	current_ability: int,
	minutes: int = -1,
	season_minutes: int = 1200,
	current_reputation: int = -1
) -> int:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return int(native.reputation_calc("player",{"strength":strength,"club_delta":club_delta,"matches":matches,"rating":rating,"ability":current_ability,"minutes":minutes,"season_minutes":season_minutes,"reputation":current_reputation}))
	if matches < 1:
		return 0
	var played := minutes if minutes >= 0 else matches * MatchTypes.REGULAR_MINUTES
	var share := clampf(float(played) / maxf(float(season_minutes), 1.0), 0.0, 1.0)
	var expected := 6.15 + float(current_ability - 50) * 0.025
	var gap := clampf(rating - expected, -1.6, 1.6)
	var weight := clampf(float(strength) / 1000.0, 0.0, 1.0)
	var personal := gap / 1.6 * 8.0 * share * weight
	# Ability is a ceiling for sustained recognition, not an automatic annual gift.
	# Actual exposure and performance determine movement, without club-name fame.
	var recognition := clampf(float(current_ability) * 10.0 * (0.45 + 0.55 * weight) + gap * 50.0, 0.0, 1000.0)
	if current_reputation >= 0:
		personal += clampf((recognition - float(current_reputation)) * 0.04, -10.0, 10.0) * share
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
	var participants := float(_average_reputation(unit))
	var preview_ok := _preview_matches(unit, season_number)
	var champion_id := _champion_id(unit, season_number)
	var playoff_places := _playoff_place_map(unit)
	if champion_id > 0 and bool(unit.get("playoff", {}).get("enabled", false)):
		playoff_places[champion_id] = 1
	var has_table: bool = not unit.get("standings", []).is_empty()
	var tables := {}
	var parts: Array = []
	for club_id in _result_club_ids(unit):
		var division := _club_division(unit, club_id)
		var section := _table_section_for(unit, division)
		if has_table:
			var filter := _rank_filter(unit, section) if not section.is_empty() else (-1 if bool(unit.get("rules", {}).get("regular_season_enabled", false)) else division)
			if not tables.has(filter):
				tables[filter] = _ranked(unit, filter)
			var ranked: Array = tables[filter]
			var actual := _index_of(ranked, club_id)
			if actual < 1:
				continue
			var predicted := _predicted_place(section, club_id, actual) if preview_ok else actual
			var current := _reputation_of(unit, club_id)
			var bonus := _achievement_bonus(strength, current, int(playoff_places.get(club_id, 0)), participants)
			var pull := _level_pull(strength, actual, ranked.size(), current, participants)
			var step := _table_step(strength, current, predicted, actual, ranked.size(), participants) + bonus
			# A title can preserve an already prestigious club rather than increase
			# it; poor results in another competition may still lower the total.
			if club_id == champion_id:
				step = maxf(step, float(-pull))
			parts.append({
				"club_id": club_id,
				"step": step,
				"pull": pull,
				"strength": strength,
				"table_anchor": true,
			})
			continue
		if champion_id > 0:
			var knockout := _knockout_section(unit)
			var chance := _title_chance(knockout, club_id) if preview_ok else 0.0
			var current := _reputation_of(unit, club_id)
			var won: bool = club_id == champion_id
			var pull := maxi(0, _level_pull(strength, 1, 2, current, participants)) if won else 0
			var bonus := _achievement_bonus(strength, current, int(playoff_places.get(club_id, 0)), participants)
			parts.append({
				"club_id": club_id,
				"step": _chance_step(strength, chance, won) * (_achievement_headroom(strength, current, participants) if won else 1.0) + bonus,
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


static func _table_step(strength: int, current: int, predicted: int, actual: int, field: int, participants: float = -1.0) -> float:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return float(native.reputation_calc("table_step",{"strength":strength,"current":current,"predicted":predicted,"actual":actual,"field":field,"participants":participants}))
	var surprise := _place_step(strength, predicted, actual, field)
	return surprise * _achievement_headroom(strength, current, participants) if surprise > 0.0 else surprise


static func _chance_step(strength: int, title_chance: float, won: bool) -> float:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return float(native.reputation_calc("chance_step",{"strength":strength,"chance":title_chance,"won":won}))
	var chance := clampf(title_chance / 100.0, 0.0, 1.0)
	var surprise := (1.0 - chance) if won else -chance
	return surprise * SURPRISE_SPAN * clampf(float(strength) / 1000.0, 0.0, 1.0)


static func _prestige_reference(strength: int, participants: float = -1.0) -> float:
	var configured := float(strength) * LEVEL_REFERENCE_RATIO
	if participants < 0.0:
		return configured
	return (configured + clampf(participants, 0.0, 1000.0)) * 0.5


static func _achievement_bonus(strength: int, current: int, place: int, participants: float = -1.0) -> float:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return float(native.reputation_calc("bonus",{"strength":strength,"current":current,"actual":place,"participants":participants}))
	var base := 0.0
	match place:
		1: base = 8.0
		2: base = 4.0
		3: base = 2.0
		4: base = 1.0
	return base * (0.5 + 0.5 * clampf(float(strength) / 1000.0, 0.0, 1.0)) * _achievement_headroom(strength, current, participants)


static func _achievement_headroom(strength: int, current: int, participants: float = -1.0) -> float:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return float(native.reputation_calc("headroom",{"strength":strength,"current":current,"participants":participants}))
	var ceiling := minf(1000.0, _prestige_reference(strength, participants) + ACHIEVEMENT_HEADROOM)
	return clampf((ceiling - float(current)) / 100.0, 0.0, 1.0)


static func _level_pull(strength: int, actual: int, field: int, current: int, participants: float = -1.0) -> int:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return int(native.reputation_calc("pull",{"strength":strength,"current":current,"actual":actual,"field":field,"participants":participants}))
	if field < 2 or actual < 1:
		return 0
	var percentile := 1.0 - float(actual - 1) / float(field - 1)
	var target := clampf(_prestige_reference(strength, participants) + FINISH_SPAN * (2.0 * percentile - 1.0), 0.0, 1000.0)
	# The stored reputation carries past achievements; convergence takes seasons.
	return clampi(int(round((target - float(current)) * LEVEL_RATE)), -LEVEL_PULL, LEVEL_PULL)


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
