class_name CompetitionTypes
extends RefCounted
## Labels and allowlists for competition card fields.


const TYPE_LEAGUE := "LEAGUE"
const TYPE_CUP := "CUP"
const TYPE_SUPER_CUP := "SUPER_CUP"
const TYPE_GROUP_AND_PLAYOFF := "GROUP_AND_PLAYOFF"
const TYPE_KNOCKOUT := "KNOCKOUT"
const TYPE_DIVISIONS := "DIVISIONS"

const SCOPE_DOMESTIC := "DOMESTIC"
const SCOPE_CONTINENTAL := "CONTINENTAL"
const SCOPE_INTERNATIONAL := "INTERNATIONAL"
const SCOPE_INTERCONTINENTAL_CLUB := "INTERCONTINENTAL_CLUB"

const PERIOD_ANNUAL := "ANNUAL"
const PERIOD_BIENNIAL := "BIENNIAL"
const PERIOD_QUADRENNIAL := "QUADRENNIAL"
const PERIOD_ONCE := "ONCE"

const AGE_SENIOR := "SENIOR"
const AGE_U21 := "U21"
const AGE_U18 := "U18"

const UNIT_DIVISION := "DIVISION"
const UNIT_CUP := "CUP"
const UNIT_SUPER_CUP := "SUPER_CUP"

const TYPES := [
	TYPE_LEAGUE,
	TYPE_CUP,
	TYPE_SUPER_CUP,
	TYPE_GROUP_AND_PLAYOFF,
	TYPE_KNOCKOUT,
	TYPE_DIVISIONS,
]

const SCOPES := [
	SCOPE_DOMESTIC,
	SCOPE_CONTINENTAL,
	SCOPE_INTERNATIONAL,
	SCOPE_INTERCONTINENTAL_CLUB,
]

const PERIODS := [
	PERIOD_ANNUAL,
	PERIOD_BIENNIAL,
	PERIOD_QUADRENNIAL,
	PERIOD_ONCE,
]

const AGE_GROUPS := [
	AGE_SENIOR,
	AGE_U21,
	AGE_U18,
]

const UNIT_KINDS := [
	UNIT_DIVISION,
	UNIT_CUP,
	UNIT_SUPER_CUP,
]


static func type_label(type_code: String) -> String:
	match type_code:
		TYPE_LEAGUE:
			return "Лига"
		TYPE_CUP:
			return "Кубок"
		TYPE_SUPER_CUP:
			return "Супер-кубок"
		TYPE_GROUP_AND_PLAYOFF:
			return "Группы + плей-офф"
		TYPE_KNOCKOUT:
			return "Плей-офф"
		TYPE_DIVISIONS:
			return "Дивизионы"
		_:
			return type_code


static func scope_label(scope_code: String) -> String:
	match scope_code:
		SCOPE_DOMESTIC:
			return "Национальный"
		SCOPE_CONTINENTAL:
			return "Континентальный"
		SCOPE_INTERNATIONAL:
			return "Международный"
		SCOPE_INTERCONTINENTAL_CLUB:
			return "Межконтинентальный клубный"
		_:
			return scope_code


static func period_label(period_code: String) -> String:
	match period_code:
		PERIOD_ANNUAL:
			return "Ежегодно"
		PERIOD_BIENNIAL:
			return "Раз в 2 года"
		PERIOD_QUADRENNIAL:
			return "Раз в 4 года"
		PERIOD_ONCE:
			return "Разовый"
		_:
			return period_code


static func age_group_label(age_code: String) -> String:
	match age_code:
		AGE_SENIOR:
			return "Основная"
		AGE_U21:
			return "U21"
		AGE_U18:
			return "U18"
		_:
			return age_code


static func unit_kind_label(kind_code: String) -> String:
	match kind_code:
		UNIT_DIVISION:
			return "Дивизион"
		UNIT_CUP:
			return "Кубок"
		UNIT_SUPER_CUP:
			return "Суперкубок"
		_:
			return kind_code


static func default_type_for_unit(unit_kind: String) -> String:
	match unit_kind:
		UNIT_CUP:
			return TYPE_CUP
		UNIT_SUPER_CUP:
			return TYPE_SUPER_CUP
		_:
			return TYPE_LEAGUE


static func default_name_for_unit(unit_kind: String, index: int) -> String:
	return "%s %d" % [unit_kind_label(unit_kind), index]


static func is_valid_type(type_code: String) -> bool:
	return type_code in TYPES


static func is_valid_unit_kind(kind_code: String) -> bool:
	return kind_code in UNIT_KINDS


static func is_valid_scope(scope_code: String) -> bool:
	return scope_code in SCOPES


static func is_valid_period(period_code: String) -> bool:
	return period_code in PERIODS


static func is_valid_age_group(age_code: String) -> bool:
	return age_code in AGE_GROUPS


static func type_options() -> Array:
	var items: Array = []
	for code in TYPES:
		items.append({"id": code, "label": type_label(code)})
	return items


static func scope_options() -> Array:
	var items: Array = []
	for code in SCOPES:
		items.append({"id": code, "label": scope_label(code)})
	return items


static func period_options() -> Array:
	var items: Array = []
	for code in PERIODS:
		items.append({"id": code, "label": period_label(code)})
	return items


static func age_group_options() -> Array:
	var items: Array = []
	for code in AGE_GROUPS:
		items.append({"id": code, "label": age_group_label(code)})
	return items
