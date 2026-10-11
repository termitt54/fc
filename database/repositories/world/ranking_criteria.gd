class_name RankingCriteria
extends RefCounted
## Standing / group ranking tie-breakers and their default priority.


const POINTS := "POINTS"
const GOAL_DIFF := "GOAL_DIFF"
const GOALS_FOR := "GOALS_FOR"
const H2H_POINTS := "H2H_POINTS"
const H2H_GOAL_DIFF := "H2H_GOAL_DIFF"
const H2H_GOALS := "H2H_GOALS"
const WINS := "WINS"
const AWAY_GOALS := "AWAY_GOALS"

const ALL := [
	POINTS,
	GOAL_DIFF,
	GOALS_FOR,
	H2H_POINTS,
	H2H_GOAL_DIFF,
	H2H_GOALS,
	WINS,
	AWAY_GOALS,
]

const DEFAULT_ORDER := [
	POINTS,
	GOAL_DIFF,
	GOALS_FOR,
	H2H_POINTS,
	H2H_GOAL_DIFF,
	H2H_GOALS,
]


static func label(code: String) -> String:
	match code:
		POINTS:
			return "Очки"
		GOAL_DIFF:
			return "Разница мячей"
		GOALS_FOR:
			return "Забитые мячи"
		H2H_POINTS:
			return "Личные встречи — очки"
		H2H_GOAL_DIFF:
			return "Личные встречи — разница"
		H2H_GOALS:
			return "Личные встречи — голы"
		WINS:
			return "Победы"
		AWAY_GOALS:
			return "Голы на выезде"
		_:
			return code


static func is_valid(code: String) -> bool:
	return code in ALL


static func normalize_order(raw: Array) -> Array:
	var result: Array = []
	var seen: Dictionary = {}
	for item in raw:
		var code := str(item).strip_edges().to_upper()
		if not is_valid(code) or seen.has(code):
			continue
		seen[code] = true
		result.append(code)
	if result.is_empty():
		return DEFAULT_ORDER.duplicate()
	return result


static func parse_stored(raw: Variant) -> Array:
	if raw == null:
		return DEFAULT_ORDER.duplicate()
	if raw is Array:
		return normalize_order(raw)
	var text := str(raw).strip_edges()
	if text.is_empty():
		return DEFAULT_ORDER.duplicate()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Array:
		return normalize_order(parsed)
	return DEFAULT_ORDER.duplicate()


static func serialize(order: Variant) -> String:
	return JSON.stringify(parse_stored(order))


static func unused_codes(order: Array) -> Array:
	var active := normalize_order(order)
	var unused: Array = []
	for code in ALL:
		if not code in active:
			unused.append(code)
	return unused
