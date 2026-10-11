class_name PrizeRules
extends RefCounted
## Per-unit prize table for DIVISIONS: regular-season / division places
## plus each playoff finish (champion, runner-up, 3rd/4th, round exits).


const AMOUNT_MAX := 999_999_999
const AMOUNT_STEP := 10000

const KEY_CHAMPION := "playoff_champion"
const KEY_RUNNER_UP := "playoff_runner_up"
const KEY_THIRD := "playoff_third"
const KEY_FOURTH := "playoff_fourth"


static func regular_key(place: int) -> String:
	return "regular_%d" % maxi(place, 1)


static func out_key(round_no: int) -> String:
	return "playoff_out_%d" % maxi(round_no, 1)


static func clamp_amount(value: Variant) -> int:
	return clampi(int(value), 0, AMOUNT_MAX)


static func playoff_enabled(unit: Dictionary) -> bool:
	return int(unit.get("teams_playoff", 0)) >= 2


static func uses_overall_regular(unit: Dictionary) -> bool:
	if bool(unit.get("regular_season_enabled", false)):
		return true
	return int(unit.get("divisions_count", 1)) <= 1


static func regular_place_count(unit: Dictionary) -> int:
	var per_division: int = maxi(int(unit.get("teams_per_division", 1)), 1)
	if uses_overall_regular(unit):
		return per_division * maxi(int(unit.get("divisions_count", 1)), 1)
	return per_division


static func playoff_round_count(teams: int) -> int:
	var remaining := maxi(teams, 2)
	var rounds := 0
	while remaining > 1:
		remaining = int(ceil(float(remaining) / 2.0))
		rounds += 1
	return rounds


static func playoff_round_label(round_no: int, total_rounds: int) -> String:
	var from_end := total_rounds - round_no
	match from_end:
		0:
			return "Финал"
		1:
			return "1/2 финала"
		2:
			return "1/4 финала"
		3:
			return "1/8 финала"
		4:
			return "1/16 финала"
		_:
			return "Раунд %d" % maxi(round_no, 1)


static func has_third_place(unit: Dictionary) -> bool:
	return playoff_enabled(unit) \
		and bool(unit.get("playoff_third_place", false)) \
		and int(unit.get("teams_playoff", 0)) >= 4


## First-to-last playoff rounds that pay an "eliminated here" prize.
## The final is champion/runner-up. The semi is 3rd/4th when that match is on.
static func playoff_out_rounds(unit: Dictionary) -> Array:
	if not playoff_enabled(unit):
		return []
	var teams: int = int(unit.get("teams_playoff", 0))
	var total := playoff_round_count(teams)
	var last_out := total - 1
	if has_third_place(unit):
		last_out -= 1
	var rounds: Array = []
	for round_no in range(1, last_out + 1):
		rounds.append(round_no)
	return rounds


static func describe_rows(unit: Dictionary) -> Array:
	var rows: Array = []
	var overall := uses_overall_regular(unit)
	var regular_hint := "общ. табл." if overall else "кажд. див."
	var regular_section := "Регулярный сезон" if overall else "Дивизион"
	var places := regular_place_count(unit)
	for place in range(1, places + 1):
		rows.append({
			"key": regular_key(place),
			"section": regular_section,
			"label": "%d-е место" % place,
			"hint": regular_hint,
		})

	if not playoff_enabled(unit):
		return rows

	var teams: int = int(unit.get("teams_playoff", 0))
	var total_rounds := playoff_round_count(teams)
	rows.append({
		"key": KEY_CHAMPION,
		"section": "Плей-офф",
		"label": "Чемпион",
		"hint": playoff_round_label(total_rounds, total_rounds),
	})
	rows.append({
		"key": KEY_RUNNER_UP,
		"section": "Плей-офф",
		"label": "Финалист",
		"hint": playoff_round_label(total_rounds, total_rounds),
	})
	if has_third_place(unit):
		rows.append({
			"key": KEY_THIRD,
			"section": "Плей-офф",
			"label": "3-е место",
			"hint": "матч за бронзу",
		})
		rows.append({
			"key": KEY_FOURTH,
			"section": "Плей-офф",
			"label": "4-е место",
			"hint": "матч за бронзу",
		})
	for round_no in playoff_out_rounds(unit):
		rows.append({
			"key": out_key(round_no),
			"section": "Плей-офф",
			"label": "Вылет: %s" % playoff_round_label(round_no, total_rounds),
			"hint": "проигравшие стадии",
		})
	return rows


static func empty_amounts(unit: Dictionary) -> Dictionary:
	var amounts: Dictionary = {}
	for row in describe_rows(unit):
		amounts[str(row.get("key", ""))] = 0
	return amounts


static func normalize(raw: Variant, unit: Dictionary) -> Dictionary:
	var source: Dictionary = {}
	if raw is Dictionary:
		source = raw
	var amounts := empty_amounts(unit)
	for key in amounts.keys():
		if source.has(key):
			amounts[key] = clamp_amount(source[key])
	return amounts


static func parse_stored(raw: Variant, unit: Dictionary = {}) -> Dictionary:
	if raw == null:
		return normalize({}, unit)
	if raw is Dictionary:
		return normalize(raw, unit)
	var text := str(raw).strip_edges()
	if text.is_empty() or text == "null":
		return normalize({}, unit)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return normalize(parsed, unit)
	return normalize({}, unit)


static func serialize(raw: Variant, unit: Dictionary = {}) -> String:
	return JSON.stringify(normalize(raw, unit))


static func filled_count(raw: Variant, unit: Dictionary = {}) -> int:
	var amounts := parse_stored(raw, unit)
	var count := 0
	for key in amounts.keys():
		if int(amounts[key]) > 0:
			count += 1
	return count


## club_id -> prize total for this unit. Regular place and playoff finish stack.
static func payouts(unit: Dictionary, standings_of: Callable, playoff: Dictionary = {}) -> Dictionary:
	var amounts := parse_stored(unit.get("prize_rules", {}), unit)
	var result: Dictionary = {}
	_add_regular_payouts(result, unit, amounts, standings_of)
	if playoff_enabled(unit):
		_add_playoff_payouts(result, unit, amounts, playoff)
	return result


static func _add_regular_payouts(
	result: Dictionary,
	unit: Dictionary,
	amounts: Dictionary,
	standings_of: Callable
) -> void:
	var places := regular_place_count(unit)
	if uses_overall_regular(unit):
		_pay_table(result, amounts, standings_of.call(-1), places)
		return
	var divisions: int = maxi(int(unit.get("divisions_count", 1)), 1)
	for division in divisions:
		_pay_table(result, amounts, standings_of.call(division), places)


static func _pay_table(result: Dictionary, amounts: Dictionary, rows: Array, places: int) -> void:
	if typeof(rows) != TYPE_ARRAY:
		return
	for i in mini(places, rows.size()):
		var row: Dictionary = rows[i] if typeof(rows[i]) == TYPE_DICTIONARY else {}
		var club_id: int = int(row.get("club_id", 0))
		_add_amount(result, club_id, int(amounts.get(regular_key(i + 1), 0)))


static func _add_playoff_payouts(
	result: Dictionary,
	unit: Dictionary,
	amounts: Dictionary,
	playoff: Dictionary
) -> void:
	var finishes := playoff_finishes(playoff)
	for club_id in finishes.keys():
		var finish: Dictionary = finishes[club_id]
		var key := _finish_amount_key(unit, finish)
		if key.is_empty():
			continue
		_add_amount(result, int(club_id), int(amounts.get(key, 0)))


static func _finish_amount_key(unit: Dictionary, finish: Dictionary) -> String:
	var kind := str(finish.get("kind", ""))
	match kind:
		"champion":
			return KEY_CHAMPION
		"runner_up":
			return KEY_RUNNER_UP
		"third":
			return KEY_THIRD
		"fourth":
			return KEY_FOURTH
		"out":
			var round_no: int = int(finish.get("round", 0))
			if round_no in playoff_out_rounds(unit):
				return out_key(round_no)
			return ""
		_:
			return ""


## club_id -> {kind, round} for a completed playoff. Furthest finish wins.
static func playoff_finishes(playoff: Dictionary) -> Dictionary:
	var finishes: Dictionary = {}
	var series_list: Array = playoff.get("series", [])
	var final_round := 0
	for series in series_list:
		if typeof(series) != TYPE_DICTIONARY:
			continue
		if bool(series.get("is_third_place", false)):
			continue
		final_round = maxi(final_round, int(series.get("round", 0)))

	for series in series_list:
		if typeof(series) != TYPE_DICTIONARY:
			continue
		if not bool(series.get("complete", false)):
			continue
		var home_id: int = int(series.get("home_id", 0))
		var away_id: int = int(series.get("away_id", 0))
		var winner_id: int = int(series.get("winner_id", 0))
		var loser_id: int = away_id if winner_id == home_id else home_id
		var round_no: int = int(series.get("round", 0))
		if bool(series.get("is_third_place", false)):
			_keep_finish(finishes, winner_id, {"kind": "third", "round": round_no, "rank": 3})
			_keep_finish(finishes, loser_id, {"kind": "fourth", "round": round_no, "rank": 4})
			continue
		if round_no == final_round and final_round > 0:
			_keep_finish(finishes, winner_id, {"kind": "champion", "round": round_no, "rank": 1})
			_keep_finish(finishes, loser_id, {"kind": "runner_up", "round": round_no, "rank": 2})
			continue
		_keep_finish(finishes, loser_id, {"kind": "out", "round": round_no, "rank": 50 - round_no})
	return finishes


static func _keep_finish(finishes: Dictionary, club_id: int, finish: Dictionary) -> void:
	if club_id < 1:
		return
	if not finishes.has(club_id):
		finishes[club_id] = finish
		return
	var current: Dictionary = finishes[club_id]
	if int(finish.get("rank", 99)) < int(current.get("rank", 99)):
		finishes[club_id] = finish


static func _add_amount(result: Dictionary, club_id: int, amount: int) -> void:
	if club_id < 1 or amount < 1:
		return
	result[club_id] = int(result.get(club_id, 0)) + amount
