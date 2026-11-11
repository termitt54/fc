class_name CoachTypes
extends RefCounted
## Labels and keys for head-coach entities.


const ATTR_TRANSFERS := "transfers"
const ATTR_NEGOTIATIONS := "negotiations"
const ATTR_TACTICS := "tactics"
const ATTR_MOTIVATION := "motivation"
const ATTR_DEVELOPMENT := "development"
const ATTR_DISCIPLINE := "discipline"

const ATTR_PROFESSIONALISM := "professionalism"

const ATTR_KEYS := [
	ATTR_PROFESSIONALISM,
	ATTR_TRANSFERS,
	ATTR_NEGOTIATIONS,
	ATTR_TACTICS,
	ATTR_MOTIVATION,
	ATTR_DEVELOPMENT,
	ATTR_DISCIPLINE,
]

const ATTR_LABELS := {
	ATTR_PROFESSIONALISM: "Профессионализм",
	ATTR_TRANSFERS: "Трансферы",
	ATTR_NEGOTIATIONS: "Переговоры",
	ATTR_TACTICS: "Организация игры",
	ATTR_MOTIVATION: "Мотивация",
	ATTR_DEVELOPMENT: "Развитие",
	ATTR_DISCIPLINE: "Дисциплина",
}

const ATTR_TIPS := {
	ATTR_PROFESSIONALISM: "Точность оценки игроков, их формы и выбора состава сборной.",
	ATTR_TRANSFERS: "Работа на рынке: оценка игроков и сбор состава.",
	ATTR_NEGOTIATIONS: "Удержание своих: продление контрактов и согласие игрока остаться.",
	ATTR_TACTICS: "Организация опеки, подготовка к матчу и выбор продолжения атаки.",
	ATTR_MOTIVATION: "Раздевалка и умение выжать максимум из текущего состава.",
	ATTR_DEVELOPMENT: "Рост футболистов на тренировках и работа с молодёжью.",
	ATTR_DISCIPLINE: "Порядок в команде, требования и контроль атмосферы.",
}

const STYLE_ATTACKING := "attacking"
const STYLE_BALANCED := STYLE_ATTACKING # Legacy constant; there is no third mentality.
const STYLE_DEFENSIVE := "defensive"

const STYLES := [STYLE_ATTACKING, STYLE_DEFENSIVE]

const STYLE_LABELS := {
	STYLE_ATTACKING: "Атакующий",
	STYLE_DEFENSIVE: "Оборонительный",
}

const ROLE_HEAD_COACH := "HEAD_COACH"
const ATTR_MAX := 20
const AGE_MIN := 36
const AGE_MAX := 68

const TacticTypesScript := preload("res://game/tactic_types.gd")


static func attr_label(key: String) -> String:
	return str(ATTR_LABELS.get(key, key))


static func attr_tip(key: String) -> String:
	return str(ATTR_TIPS.get(key, ""))


static func style_label(code: String) -> String:
	return TacticTypesScript.style_label(code)


static func ensure_tactics(coach: Dictionary) -> Dictionary:
	return TacticTypesScript.ensure_coach_tactics(coach)


static func primary_style_of(coach: Dictionary) -> String:
	return TacticTypesScript.primary_style_of(coach)


static func backup_style_of(coach: Dictionary) -> String:
	return TacticTypesScript.backup_style_of(coach)


static func primary_formation_of(coach: Dictionary) -> String:
	return TacticTypesScript.primary_formation_of(coach)


static func backup_formation_of(coach: Dictionary) -> String:
	return TacticTypesScript.backup_formation_of(coach)


static func clamp_attr(value: int) -> int:
	return clampi(value, 1, ATTR_MAX)


static func transfers_of(coach: Dictionary) -> int:
	var attributes: Dictionary = coach.get("attributes", {})
	if attributes.has(ATTR_TRANSFERS):
		return clamp_attr(int(attributes.get(ATTR_TRANSFERS, 1)))
	return clamp_attr(int(coach.get("transfers", 1)))


static func negotiations_of(coach: Dictionary) -> int:
	var attributes: Dictionary = coach.get("attributes", {})
	if attributes.has(ATTR_NEGOTIATIONS):
		return clamp_attr(int(attributes.get(ATTR_NEGOTIATIONS, 1)))
	return transfers_of(coach)


## How much the coach adds to a player's season of training.
static func development_of(coach: Dictionary) -> int:
	var attributes: Dictionary = coach.get("attributes", {})
	if attributes.has(ATTR_DEVELOPMENT):
		return clamp_attr(int(attributes.get(ATTR_DEVELOPMENT, 1)))
	if coach.has(ATTR_DEVELOPMENT):
		return clamp_attr(int(coach.get(ATTR_DEVELOPMENT, 1)))
	return transfers_of(coach)


static func calc_current_ability(attributes: Dictionary) -> int:
	if attributes.is_empty():
		return 1
	var total := 0
	var count := 0
	for key in ATTR_KEYS:
		if key == ATTR_PROFESSIONALISM or not attributes.has(key):
			continue
		total += clamp_attr(int(attributes.get(key, 1)))
		count += 1
	if count < 1:
		return 1
	return PlayerTypes.clamp_ability(int(round(float(total) / float(count) * 5.0)))


static func professionalism_of(coach: Dictionary) -> int:
	var attributes: Dictionary = coach.get("attributes", {})
	return clamp_attr(int(attributes.get(ATTR_PROFESSIONALISM, 10)))

## Squared falloff: competent coaches only confuse close candidates.
static func selection_uncertainty(coach: Dictionary) -> float:
	var weakness := float(20 - professionalism_of(coach)) / 19.0
	return weakness * weakness

static func ensure_professionalism(coach: Dictionary) -> void:
	if not coach.has("attributes"):
		coach["attributes"] = {}
	if not coach["attributes"].has(ATTR_PROFESSIONALISM):
		# Stable migration independent of the match RNG.
		coach["attributes"][ATTR_PROFESSIONALISM] = 6 + absi(int(coach.get("id", 0)) * 7919) % 15
