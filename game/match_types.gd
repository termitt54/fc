class_name MatchTypes
extends RefCounted
## Default calibration for the 8v8 match engine.
## Clock: 2 x 25 minutes cut into 5-minute phases. Playoff adds 2 x 10 minutes.
## Live values are MatchSimulationConfig (Настройки → Симуляция матчей).
## tests/game/test_match_engine.gd guards the default targets.


const PHASE_MINUTES := 5
const HALF_MINUTES := 25
const PHASES_PER_HALF := 5
const REGULAR_PHASES := 10
const REGULAR_MINUTES := 50

const ET_HALF_MINUTES := 10
const ET_PHASES_PER_HALF := 2
const ET_PHASES := 4
const ET_MINUTES := 20

const SUBS_MAX := 5
## Keepers have a different running workload; shared by in-match and daily load.
const GOALKEEPER_WORKLOAD_FACTOR := 0.35
## Coaches keep at least one window in reserve for injuries.
const SUBS_FATIGUE_PHASE_FROM := 6

## Chance funnel. chances -> created (shot) -> on target -> goal.
const CHANCES_PER_PHASE := 2.26
const CHANCE_CREATE_BASE := 0.78
const SHOT_ON_TARGET_BASE := 0.43
## Conditional on a shot reaching the target; player duels still modify this.
const SHOT_CONVERSION_BASE := 0.30
const SET_PIECE_SHARE := 0.22
const PENALTY_PER_PHASE := 0.013
const PENALTY_CONVERSION_BASE := 0.76
const SHOOTOUT_ROUNDS := 5
const SHOOTOUT_MAX_ROUNDS := 24

const HOME_ADVANTAGE := 0.06
const HOME_REPUTATION_BONUS := 0.0
const NEUTRAL_VENUE_KEY := "neutral"

## How far the better side can be pushed by a bad day. Without this every
## mismatch ends the same way and the underdog never steals a game.
const TEAM_FORM_SPREAD := 0.06
const TEAM_FORM_MIN := 0.72
const TEAM_FORM_MAX := 1.28
## How sharply a quality edge turns into chances. Lower means flatter football.
const QUALITY_EXPONENT := 1.20
const QUALITY_RATIO_MIN := 0.62
const QUALITY_RATIO_MAX := 1.45
## Smooth collective edge from the actual on-field ability, after fit and fatigue.
## Reciprocal bounds prevent the favourite/underdog adjustment from running away.
const SQUAD_GAP_LINEAR := 0.05
const SQUAD_GAP_QUADRATIC := 0.0007
const SQUAD_LOG_EDGE_MAX := 1.65

## Discipline base rates per phase, before unit strictness and coach discipline.
const YELLOW_PER_PHASE := 0.090
const SECOND_YELLOW_SHARE := 0.085
const RED_DIRECT_SHARE := 0.018
const MAN_DOWN_PENALTY := 0.16

const INJURY_PER_PHASE := 0.019
const INJURY_GRADE_LIGHT := "LIGHT"
const INJURY_GRADE_MEDIUM := "MEDIUM"
const INJURY_GRADE_HEAVY := "HEAVY"

const INJURY_GRADES := {
	INJURY_GRADE_LIGHT: {"weight": 62, "min": 1, "max": 2, "label": "Лёгкая"},
	INJURY_GRADE_MEDIUM: {"weight": 28, "min": 3, "max": 8, "label": "Средняя"},
	INJURY_GRADE_HEAVY: {"weight": 10, "min": 9, "max": 25, "label": "Тяжёлая"},
}

## Freshness lost per 5-minute phase at intensity 1.0 / average stamina.
## Kept as the implied default behind fresh_after_stamina_10 (0.82 over 10 phases).
const FATIGUE_PER_PHASE := 0.018

const CONDITION_MAX := 100
const CONDITION_MIN := 0
const CONDITION_START := 100
## Legacy average cost; live match drain uses condition_after_stamina_* knobs.
const CONDITION_MATCH_COST := 34.0
## Condition left after 50 minutes at intensity 1.0, starting from 100.
const CONDITION_AFTER_STAMINA_1 := 30.0
const CONDITION_AFTER_STAMINA_10 := 60.0
const CONDITION_AFTER_STAMINA_20 := 82.0
## On-pitch freshness left after 50 minutes at intensity 1.0 / full condition.
const FRESH_AFTER_STAMINA_1 := 0.45
const FRESH_AFTER_STAMINA_10 := 0.72
const FRESH_AFTER_STAMINA_20 := 0.92
## Recovery closes a share of the gap to full fitness, so it never wipes the
## whole cost of a game: an every-round starter settles around 75-80.
const CONDITION_RECOVERY_FLOOR := 3.0
const CONDITION_RECOVERY_RATE := 0.42
const CONDITION_RECOVERY_RATE_SPAN := 0.24
const CONDITION_IDLE_FACTOR := 1.25
const CONDITION_FIT_FLOOR := 0.86
## How much a zero-condition player is worth when the coach picks the XI.
const CONDITION_SELECT_FLOOR := 0.32
## Below this condition a coach would rather start a fresher deputy.
const LINEUP_REST_BELOW := 82.0
const RECOVERY_SHARE_1 := 0.43
const RECOVERY_SHARE_10 := 0.54
const RECOVERY_SHARE_20 := 0.66

const MORALE_MAX := 100
const MORALE_MIN := 0
const MORALE_DEFAULT := 60
const MORALE_EFFECT_SPAN := 0.14
const MORALE_EFFECT_FLOOR := 0.93
const MORALE_DRIFT := 0.12

const RATING_BASE := 6.0
const RATING_MIN := 1.0
const RATING_MAX := 10.0

const EVENT_GOAL := "GOAL"
const EVENT_PENALTY_GOAL := "PENALTY_GOAL"
const EVENT_PENALTY_MISS := "PENALTY_MISS"
const EVENT_YELLOW := "YELLOW"
const EVENT_RED := "RED"
const EVENT_INJURY := "INJURY"
const EVENT_SUB := "SUB"
const EVENT_SHOOTOUT := "SHOOTOUT"

const STAGE_REGULAR := "REGULAR"
const STAGE_PLAYOFF := "PLAYOFF"

## How much a slot feeds attack / possession / defence.
const SLOT_ROLE := {
	"GK":{"att":0.02,"ctrl":0.10,"def":0.30},
	"CB":{"att":0.28,"ctrl":0.45,"def":1.0},
	"CM":{"att":0.75,"ctrl":1.0,"def":0.55},
	"ST":{"att":1.0,"ctrl":0.50,"def":0.20},
}
const STYLE_PROFILE := {
	"attacking":{"tempo":1.0,"ctrl":1.0,"def":1.0,"concede":1.0,"intensity":1.0,"quality":1.0},
	"defensive":{"tempo":0.97,"ctrl":1.0,"def":1.0,"concede":1.0,"intensity":0.97,"quality":1.0},
}

const STYLE_FALLBACK := {
	"tempo": 1.0, "ctrl": 1.0, "def": 1.0, "concede": 1.0, "intensity": 1.0, "quality": 1.0,
}

## Position fit when a player fills a slot he is not native to.
const SLOT_FIT_NATIVE := 1.0
const SLOT_FIT_SAME_LINE := 0.88
const SLOT_FIT_NEIGHBOUR := 0.74
const SLOT_FIT_ALIEN := 0.52
const SLOT_FIT_GK_MISMATCH := 0.30

const NEIGHBOUR_SLOTS := {"CB":["CM"],"CM":["CB","ST"],"ST":["CM"]}


static func style_profile(style: String) -> Dictionary:
	var profile: Variant = STYLE_PROFILE.get(style, null)
	if typeof(profile) == TYPE_DICTIONARY:
		return profile
	return STYLE_FALLBACK


static func slot_role(slot: String) -> Dictionary:
	var role: Variant = SLOT_ROLE.get(slot, null)
	if typeof(role) == TYPE_DICTIONARY:
		return role
	return SLOT_ROLE["CM"]


## There are only a few dozen slot/position pairs, and the selector asks for
## them hundreds of times per lineup, so the answers are memoised.
static var _fit_cache: Dictionary = {}


static func slot_fit(slot: String, position: String) -> float:
	var key := slot + position
	var cached: Variant = _fit_cache.get(key, null)
	if cached != null:
		return float(cached)
	var fit := _compute_slot_fit(slot, position)
	_fit_cache[key] = fit
	return fit


static func _compute_slot_fit(slot: String, position: String) -> float:
	if slot == position:
		return SLOT_FIT_NATIVE
	if slot == "GK" or position == "GK":
		return SLOT_FIT_GK_MISMATCH
	if PlayerTypes.position_line(slot) == PlayerTypes.position_line(position):
		return SLOT_FIT_SAME_LINE
	var neighbours: Array = NEIGHBOUR_SLOTS.get(slot, [])
	if neighbours.has(position):
		return SLOT_FIT_NEIGHBOUR
	return SLOT_FIT_ALIEN


static func injury_grade_label(grade: String) -> String:
	var meta: Variant = INJURY_GRADES.get(grade, null)
	if typeof(meta) == TYPE_DICTIONARY:
		return str((meta as Dictionary).get("label", grade))
	return grade


static func roll_injury_grade(rng: RandomNumberGenerator) -> String:
	var total := 0
	for grade in INJURY_GRADES.keys():
		total += int((INJURY_GRADES[grade] as Dictionary).get("weight", 0))
	var ticket := rng.randi_range(1, maxi(total, 1))
	var acc := 0
	for grade in INJURY_GRADES.keys():
		acc += int((INJURY_GRADES[grade] as Dictionary).get("weight", 0))
		if ticket <= acc:
			return str(grade)
	return INJURY_GRADE_LIGHT


static func roll_injury_rounds(grade: String, rng: RandomNumberGenerator) -> int:
	var meta: Variant = INJURY_GRADES.get(grade, null)
	if typeof(meta) != TYPE_DICTIONARY:
		return 1
	var data: Dictionary = meta
	return rng.randi_range(int(data.get("min", 1)), int(data.get("max", 1)))


static func morale_multiplier(morale: int) -> float:
	var scaled := clampf(float(morale) / float(MORALE_MAX), 0.0, 1.0)
	return MORALE_EFFECT_FLOOR + MORALE_EFFECT_SPAN * scaled


static func condition_multiplier(condition: int) -> float:
	var scaled := clampf(float(condition) / float(CONDITION_MAX), 0.0, 1.0)
	return CONDITION_FIT_FLOOR + (1.0 - CONDITION_FIT_FLOOR) * scaled


static func clamp_condition(value: int) -> int:
	return clampi(value, CONDITION_MIN, CONDITION_MAX)


static func clamp_morale(value: int) -> int:
	return clampi(value, MORALE_MIN, MORALE_MAX)


static func clamp_rating(value: float) -> float:
	return clampf(value, RATING_MIN, RATING_MAX)
