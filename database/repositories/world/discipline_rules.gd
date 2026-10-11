class_name DisciplineRules
extends RefCounted
## Per-unit discipline settings: cards, bans and how yellows accumulate.


const ENABLED_DEFAULT := true
const STRICTNESS_DEFAULT := 100
const STRICTNESS_MIN := 25
const STRICTNESS_MAX := 250
const YELLOW_THRESHOLD_DEFAULT := 5
const YELLOW_THRESHOLD_MAX := 20
const YELLOW_BAN_DEFAULT := 1
const YELLOW_BAN_MAX := 5
const RED_BAN_DEFAULT := 2
const RED_BAN_MAX := 10
const DOUBLE_YELLOW_RED_DEFAULT := true

const RESET_SEASON := "SEASON"
const RESET_PLAYOFF := "PLAYOFF"
const RESET_NEVER := "NEVER"
const RESET_DEFAULT := RESET_SEASON

const RESETS := [RESET_SEASON, RESET_PLAYOFF, RESET_NEVER]


static func reset_label(code: String) -> String:
	match code:
		RESET_SEASON:
			return "Каждый сезон"
		RESET_PLAYOFF:
			return "Перед плей-офф"
		RESET_NEVER:
			return "Никогда"
		_:
			return code


static func normalize_reset(code: Variant) -> String:
	var value := str(code).strip_edges().to_upper()
	if value in RESETS:
		return value
	return RESET_DEFAULT


static func reset_options() -> Array:
	var items: Array = []
	for code in RESETS:
		items.append({"id": code, "label": reset_label(code)})
	return items


static func normalize_strictness(value: Variant) -> int:
	return clampi(int(value), STRICTNESS_MIN, STRICTNESS_MAX)


static func normalize_yellow_threshold(value: Variant) -> int:
	return clampi(int(value), 0, YELLOW_THRESHOLD_MAX)


static func normalize_yellow_ban(value: Variant) -> int:
	return clampi(int(value), 1, YELLOW_BAN_MAX)


static func normalize_red_ban(value: Variant) -> int:
	return clampi(int(value), 1, RED_BAN_MAX)


## Compact, already-validated view used by the match engine.
static func from_rules(rules: Variant) -> Dictionary:
	var source: Dictionary = rules if typeof(rules) == TYPE_DICTIONARY else {}
	return {
		"enabled": bool(source.get("discipline_enabled", ENABLED_DEFAULT)),
		"strictness": float(normalize_strictness(source.get("card_strictness", STRICTNESS_DEFAULT))) / 100.0,
		"yellow_threshold": normalize_yellow_threshold(
			source.get("yellow_ban_threshold", YELLOW_THRESHOLD_DEFAULT)
		),
		"yellow_ban": normalize_yellow_ban(source.get("yellow_ban_matches", YELLOW_BAN_DEFAULT)),
		"red_ban": normalize_red_ban(source.get("red_ban_matches", RED_BAN_DEFAULT)),
		"double_yellow_red": bool(source.get("double_yellow_red", DOUBLE_YELLOW_RED_DEFAULT)),
		"reset": normalize_reset(source.get("yellow_reset", RESET_DEFAULT)),
	}


static func defaults() -> Dictionary:
	return from_rules({})
