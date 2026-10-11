class_name PlayoffRules
extends RefCounted
## Playoff format / seeding allowlists for DIVISIONS units.


const FORMAT_BEST_OF := "BEST_OF"
const FORMAT_TWO_LEGGED := "TWO_LEGGED"
const FORMAT_SINGLE := "SINGLE"

const SEEDING_OVERALL := "OVERALL_TABLE"
const SEEDING_CROSS := "CROSS_SEED"
const SEEDING_SAME_PLACE := "SAME_PLACE"
const SEEDING_DRAW := "DRAW"

const FORMAT_DEFAULT := FORMAT_BEST_OF
const SERIES_WINS_DEFAULT := 3
const THIRD_PLACE_DEFAULT := false
const SEEDING_DEFAULT := SEEDING_OVERALL

const FORMATS := [
	FORMAT_BEST_OF,
	FORMAT_TWO_LEGGED,
	FORMAT_SINGLE,
]

const SEEDINGS := [
	SEEDING_OVERALL,
	SEEDING_CROSS,
	SEEDING_SAME_PLACE,
	SEEDING_DRAW,
]

const SERIES_WINS_OPTIONS := [2, 3, 4]


static func format_label(code: String) -> String:
	match code:
		FORMAT_BEST_OF:
			return "Серия до N"
		FORMAT_TWO_LEGGED:
			return "Два матча"
		FORMAT_SINGLE:
			return "Один матч"
		_:
			return code


static func format_hint(code: String) -> String:
	match code:
		FORMAT_BEST_OF:
			return "до N побед"
		FORMAT_TWO_LEGGED:
			return "общие голы"
		FORMAT_SINGLE:
			return "на выбывание"
		_:
			return ""


static func seeding_label(code: String) -> String:
	match code:
		SEEDING_OVERALL:
			return "Общ. табл. (посев 1–N)"
		SEEDING_CROSS:
			return "2 див.: перекрёст"
		SEEDING_SAME_PLACE:
			return "2 див.: равные места"
		SEEDING_DRAW:
			return "Жеребьёвка"
		_:
			return code


static func seeding_full_label(code: String) -> String:
	match code:
		SEEDING_OVERALL:
			return "Общая таблица (1 играет с N, половины сетки не пересекаются до финала)"
		SEEDING_CROSS:
			return "Два дивизиона: перекрёстный посев (1А — худший из Б…)"
		SEEDING_SAME_PLACE:
			return "Два дивизиона: одинаковые места (1А — 1Б…)"
		SEEDING_DRAW:
			return "Жеребьёвка среди всех вышедших"
		_:
			return code


static func normalize_format(code: Variant) -> String:
	var value := str(code).strip_edges().to_upper()
	if value in FORMATS:
		return value
	return FORMAT_DEFAULT


static func normalize_seeding(code: Variant) -> String:
	var value := str(code).strip_edges().to_upper()
	if value in SEEDINGS:
		return value
	return SEEDING_DEFAULT


static func normalize_series_wins(value: Variant) -> int:
	var wins := clampi(int(value), 2, 4)
	if wins in SERIES_WINS_OPTIONS:
		return wins
	return SERIES_WINS_DEFAULT


static func format_options() -> Array:
	var items: Array = []
	for code in FORMATS:
		items.append({"id": code, "label": format_label(code)})
	return items


static func seeding_options() -> Array:
	var items: Array = []
	for code in SEEDINGS:
		items.append({"id": code, "label": seeding_full_label(code)})
	return items


static func series_wins_options() -> Array:
	var items: Array = []
	for wins in SERIES_WINS_OPTIONS:
		items.append({"id": wins, "label": "до %d" % wins})
	return items
