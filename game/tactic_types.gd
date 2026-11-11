class_name TacticTypes
extends RefCounted
## Fixed 8v8 shape. style is a legacy field name for the two team mentalities.
const MATCH_OUTFIELD := 7
const MATCH_BENCH := 12
const MATCHDAY_SQUAD := 20
const FORM_322 := "3-2-2"
const FORM_232 := FORM_322 # Legacy API alias, not another available scheme.
const FORM_331 := FORM_322
const FORM_223 := FORM_322
const FORM_241 := FORM_322
const FORM_313 := FORM_322
const FORMATIONS := [FORM_322]
const FORMATION_META := {FORM_322:{"name":"3-2-2","slots":["CB","CB","CB","CM","CM","ST","ST"],"spine":["CB","CM","ST"]}}
const MENTALITY_ATTACKING := "attacking"
const MENTALITY_DEFENSIVE := "defensive"
const MENTALITY_BALANCED := MENTALITY_ATTACKING # Old callers migrate to one of the two values.
const STYLES := [MENTALITY_ATTACKING, MENTALITY_DEFENSIVE]
const STYLE_CONTROL := MENTALITY_ATTACKING
const SOURCE_PRIMARY := "fixed"
const SOURCE_BACKUP := "fixed"
const SOURCE_OTHER := "fixed"
static func is_style(code: String) -> bool: return code in STYLES
static func is_formation(code: String) -> bool: return code==FORM_322
static func normalize_style(code: String) -> String:
	return MENTALITY_DEFENSIVE if code in ["defensive","park_bus","counter"] else MENTALITY_ATTACKING
static func normalize_formation(_code: String) -> String: return FORM_322
static func style_label(code: String) -> String:
	return "Оборонительный" if normalize_style(code)==MENTALITY_DEFENSIVE else "Атакующий"
static func style_tip(code: String) -> String:
	return "Осторожные подключения и больше игроков за мячом." if normalize_style(code)==MENTALITY_DEFENSIVE else "Больше подключений и риска в развитии атаки."
static func formation_name(_code: String) -> String: return FORM_322
static func formation_label(_code: String) -> String: return FORM_322
static func mentality_of_style(code: String) -> String: return normalize_style(code)
static func is_compatible(style: String, formation: String) -> bool: return is_style(style) and is_formation(formation)
static func outfield_slots(_formation: String) -> Array: return ["CB","CB","CB","CM","CM","ST","ST"]
static func starting_xi(_formation: String) -> Array: return ["GK","CB","CB","CB","CM","CM","ST","ST"]
static func spine_slots(_formation: String) -> Array: return ["CB","CM","ST"]
static func bench_slots(_formation: String) -> Array: return ["GK","GK","CB","CB","CB","CB","CM","CM","CM","ST","ST","ST"]
static func formations_for_style(_style: String) -> Array: return FORMATIONS.duplicate()
static func primary_style_of(coach: Dictionary) -> String:
	ensure_coach_tactics(coach)
	return str(coach.get("style",MENTALITY_ATTACKING))
static func backup_style_of(coach: Dictionary) -> String: return primary_style_of(coach)
static func primary_formation_of(_coach: Dictionary) -> String: return FORM_322
static func backup_formation_of(_coach: Dictionary) -> String: return FORM_322
static func roll_coach_identity(rng: RandomNumberGenerator) -> Dictionary:
	return {"style":STYLES[rng.randi_range(0,1)]}
static func ensure_coach_tactics(coach: Dictionary) -> Dictionary:
	if coach.is_empty(): return coach
	var legacy := str(coach.get("style",coach.get("primary_style","attacking")))
	if legacy=="balanced":
		legacy="defensive" if int(coach.get("id",0))%2 else "attacking"
	coach.style=normalize_style(legacy)
	for key in ["primary_style","backup_style","primary_formation","backup_formation"]: coach.erase(key)
	return coach
static func _tactics_are_valid(coach: Dictionary) -> bool:
	return coach.is_empty() or (is_style(str(coach.get("style",""))) and not coach.has("primary_style") and not coach.has("primary_formation"))
static func pick_match_plan(coach: Dictionary,_rng: RandomNumberGenerator) -> Dictionary:
	return {"style":primary_style_of(coach),"formation":FORM_322,"style_source":"fixed","formation_source":"fixed"}
