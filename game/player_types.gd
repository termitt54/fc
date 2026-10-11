class_name PlayerTypes
extends RefCounted
## Constants and labels for save-scoped player entities (8×8 squad).


const POS_GK := "GK"
const POS_CB := "CB"
const POS_FB := "FB"
const POS_CM := "CM"
const POS_WM := "WM"
const POS_ST := "ST"
const POS_WF := "WF"

const POSITIONS := [
	POS_GK,
	POS_CB,
	POS_FB,
	POS_CM,
	POS_WM,
	POS_ST,
	POS_WF,
]

const FIELD_POSITIONS := [
	POS_CB,
	POS_FB,
	POS_CM,
	POS_WM,
	POS_ST,
	POS_WF,
]

const DEF_POSITIONS := [POS_CB, POS_FB]
const MID_POSITIONS := [POS_CM, POS_WM]
const ATT_POSITIONS := [POS_ST, POS_WF]

const LINE_GK := "GK"
const LINE_DEF := "DEF"
const LINE_MID := "MID"
const LINE_ATT := "ATT"

const SQUAD_LINES := [
	{"id": LINE_GK, "title": "Вратари"},
	{"id": LINE_DEF, "title": "Защитники"},
	{"id": LINE_MID, "title": "Полузащитники"},
	{"id": LINE_ATT, "title": "Нападающие"},
]

## Mandatory first-team law for every club and coach.
const SQUAD_SIZE := 25
const SQUAD_SLOT_MIN := {
	POS_GK: 2,
	POS_CB: 3,
	POS_FB: 4,
	POS_CM: 3,
	POS_WM: 4,
	POS_ST: 3,
	POS_WF: 4,
}
const SQUAD_SLOT_MAX := {
	POS_GK: 3,
	POS_CB: 4,
	POS_FB: 5,
	POS_CM: 4,
	POS_WM: 5,
	POS_ST: 4,
	POS_WF: 5,
}

## Key career characters — each player gets exactly two (non-opposite).
const CHAR_PROFESSIONAL := "PROFESSIONAL"
const CHAR_AMBITIOUS := "AMBITIOUS"
const CHAR_LOYAL := "LOYAL"
const CHAR_MERCENARY := "MERCENARY"
const CHAR_INDIVIDUALIST := "INDIVIDUALIST"
const CHAR_TEAM_PLAYER := "TEAM_PLAYER"
const CHAR_HOT_HEAD := "HOT_HEAD"
const CHAR_ICE_COLD := "ICE_COLD"
const CHAR_FEARLESS := "FEARLESS"
const CHAR_INCONSISTENT := "INCONSISTENT"

const CHARACTERS_PER_PLAYER := 2

const CHARACTERS := [
	CHAR_PROFESSIONAL,
	CHAR_AMBITIOUS,
	CHAR_LOYAL,
	CHAR_MERCENARY,
	CHAR_INDIVIDUALIST,
	CHAR_TEAM_PLAYER,
	CHAR_HOT_HEAD,
	CHAR_ICE_COLD,
	CHAR_FEARLESS,
	CHAR_INCONSISTENT,
]

## Soft conflicts — second character will not be the opposite of the first.
const CHARACTER_OPPOSITES := {
	CHAR_LOYAL: CHAR_MERCENARY,
	CHAR_MERCENARY: CHAR_LOYAL,
	CHAR_INDIVIDUALIST: CHAR_TEAM_PLAYER,
	CHAR_TEAM_PLAYER: CHAR_INDIVIDUALIST,
	CHAR_HOT_HEAD: CHAR_ICE_COLD,
	CHAR_ICE_COLD: CHAR_HOT_HEAD,
}

const PERSONALITY_KEYS := [
	"ambition",
	"loyalty",
	"temperament",
	"pressure",
	"sportsmanship",
	"professionalism",
	"ego",
	"leadership",
	"aggression",
	"risk",
]

const PERSONALITY_MIN := 1
const PERSONALITY_MAX := 20
const ATTR_MIN := 1
const ATTR_MAX := 20
const ABILITY_MIN := 0
const ABILITY_MAX := 100
const REPUTATION_MIN := 0
const REPUTATION_MAX := 1000

const ATTR_GROUP_TECHNICAL := "technical"
const ATTR_GROUP_MENTAL := "mental"
const ATTR_GROUP_PHYSICAL := "physical"
const ATTR_GROUP_SET_PIECES := "set_pieces"
const ATTR_GROUP_GOALKEEPING := "goalkeeping"

const ATTR_GROUPS_OUTFIELD := [
	ATTR_GROUP_TECHNICAL,
	ATTR_GROUP_MENTAL,
	ATTR_GROUP_PHYSICAL,
	ATTR_GROUP_SET_PIECES,
]

const ATTR_GROUPS_GK := [
	ATTR_GROUP_TECHNICAL,
	ATTR_GROUP_MENTAL,
	ATTR_GROUP_PHYSICAL,
	ATTR_GROUP_SET_PIECES,
	ATTR_GROUP_GOALKEEPING,
]

## Compact 8×8 attribute keys per group (1..20).
const ATTR_TECHNICAL := [
	"finishing",
	"passing",
	"first_touch",
	"dribbling",
	"tackling",
	"marking",
	"technique",
	"crossing",
]

const ATTR_MENTAL := [
	"composure",
	"decisions",
	"anticipation",
	"vision",
	"work_rate",
	"concentration",
	"bravery",
	"off_the_ball",
]

## "recovery" is deliberately absent from every ability_weights() table:
## it must not inflate CA, it only drives condition regain between rounds.
const ATTR_PHYSICAL := [
	"pace",
	"acceleration",
	"stamina",
	"strength",
	"agility",
	"balance",
	"recovery",
]

const ATTR_STAMINA := "stamina"
const ATTR_RECOVERY := "recovery"

const ATTR_SET_PIECES := [
	"corners",
	"free_kicks",
	"penalties",
	"long_shots",
]

const ATTR_GOALKEEPING := [
	"reflexes",
	"handling",
	"positioning",
	"one_on_ones",
	"aerial_reach",
	"throwing",
	"rushing_out",
	"communication",
]


static func normalize_position(code: String) -> String:
	match code:
		"DM", "AM":
			return POS_CM
		"W":
			return POS_WF
		_:
			if code in POSITIONS:
				return code
			return POS_CM


static func position_label(code: String) -> String:
	return normalize_position(code)


static func position_full_label(code: String) -> String:
	match normalize_position(code):
		POS_GK:
			return "Вратарь"
		POS_CB:
			return "Защитник"
		POS_FB:
			return "Фланговый защитник"
		POS_CM:
			return "Полузащитник"
		POS_WM:
			return "Фланговый полузащитник"
		POS_ST:
			return "Нападающий"
		POS_WF:
			return "Фланговый нападающий"
		_:
			return code


static func position_line(code: String) -> String:
	var pos := normalize_position(code)
	if pos == POS_GK:
		return LINE_GK
	if pos in DEF_POSITIONS:
		return LINE_DEF
	if pos in MID_POSITIONS:
		return LINE_MID
	return LINE_ATT


static func character_label(code: String) -> String:
	match code:
		CHAR_PROFESSIONAL:
			return "Профессионал"
		CHAR_AMBITIOUS:
			return "Амбициозный"
		CHAR_LOYAL:
			return "Преданный"
		CHAR_MERCENARY:
			return "Наёмник"
		CHAR_INDIVIDUALIST:
			return "Индивидуалист"
		CHAR_TEAM_PLAYER:
			return "Командный игрок"
		CHAR_HOT_HEAD:
			return "Вспыльчивый"
		CHAR_ICE_COLD:
			return "Хладнокровный"
		CHAR_FEARLESS:
			return "Бесстрашный"
		CHAR_INCONSISTENT:
			return "Непостоянный"
		_:
			return code


static func character_effect(code: String) -> String:
	match code:
		CHAR_PROFESSIONAL:
			return "Лучше реализует потенциал, стабильнее развивается, медленнее деградирует с возрастом"
		CHAR_AMBITIOUS:
			return "Стремится в более сильный клуб, чаще хочет уйти при перерастании уровня команды"
		CHAR_LOYAL:
			return "Реже меняет клуб, охотнее продлевает контракт, может долго оставаться в одной команде"
		CHAR_MERCENARY:
			return "Сильнее ориентируется на зарплату, легче уходит в более богатый клуб"
		CHAR_INDIVIDUALIST:
			return "Чаще берёт игру на себя: больше ударов, обводок и индивидуальных решений"
		CHAR_TEAM_PLAYER:
			return "Чаще выбирает передачу и рациональные командные действия"
		CHAR_HOT_HEAD:
			return "Выше вероятность фолов, жёлтых/красных карточек и дисквалификаций"
		CHAR_ICE_COLD:
			return "Лучше реализует пенальти и решающие моменты, меньше штрафа в важных матчах"
		CHAR_FEARLESS:
			return "Слабее зависит от силы соперника и давления больших матчей"
		CHAR_INCONSISTENT:
			return "Больше разброс качества выступлений от матча к матчу"
		_:
			return ""


static func characters_of(player: Dictionary) -> Array:
	var raw: Variant = player.get("characters", null)
	if typeof(raw) == TYPE_ARRAY:
		var out: Array = []
		for item in raw:
			var code := str(item)
			if is_valid_character(code) and code not in out:
				out.append(code)
		if not out.is_empty():
			return out
	# Legacy single archetype field.
	var legacy := str(player.get("archetype", "")).strip_edges()
	if is_valid_character(legacy):
		return [legacy]
	return []


static func characters_label(player: Dictionary) -> String:
	var labels: PackedStringArray = PackedStringArray()
	for code in characters_of(player):
		labels.append(character_label(code))
	if labels.is_empty():
		return "—"
	return " · ".join(labels)


static func personality_label(key: String) -> String:
	match key:
		"ambition":
			return "Амбиции"
		"loyalty":
			return "Лояльность"
		"temperament":
			return "Темперамент"
		"pressure":
			return "Давление"
		"sportsmanship":
			return "Спортсменство"
		"professionalism":
			return "Профессионализм"
		"ego":
			return "Эго"
		"leadership":
			return "Лидерство"
		"aggression":
			return "Агрессия"
		"risk":
			return "Риск"
		_:
			return key


static func is_valid_position(code: String) -> bool:
	return code in POSITIONS or code in PackedStringArray(["DM", "AM", "W"])


static func squad_slot_min(code: String) -> int:
	return int(SQUAD_SLOT_MIN.get(normalize_position(code), 0))


static func squad_slot_max(code: String) -> int:
	return int(SQUAD_SLOT_MAX.get(normalize_position(code), 0))


static func count_squad_positions(squad: Array) -> Dictionary:
	var counts: Dictionary = {}
	for code in POSITIONS:
		counts[code] = 0
	for player in squad:
		if typeof(player) != TYPE_DICTIONARY:
			continue
		var pos := normalize_position(str(player.get("position", "")))
		counts[pos] = int(counts.get(pos, 0)) + 1
	return counts


static func can_add_squad_position(squad: Array, code: String) -> bool:
	if squad.size() >= SQUAD_SIZE:
		return false
	var pos := normalize_position(code)
	if pos not in POSITIONS:
		return false
	var counts := count_squad_positions(squad)
	return int(counts.get(pos, 0)) < squad_slot_max(pos)


static func missing_required_position(squad: Array) -> String:
	var counts := count_squad_positions(squad)
	for pos in POSITIONS:
		if int(counts.get(pos, 0)) < squad_slot_min(pos):
			return pos
	return ""


static func has_open_squad_slot(squad: Array) -> bool:
	if squad.size() >= SQUAD_SIZE:
		return false
	var counts := count_squad_positions(squad)
	for pos in POSITIONS:
		if int(counts.get(pos, 0)) < squad_slot_max(pos):
			return true
	return false


static func is_squad_shape_legal(squad: Array) -> bool:
	if squad.size() != SQUAD_SIZE:
		return false
	var counts := count_squad_positions(squad)
	for pos in POSITIONS:
		var have := int(counts.get(pos, 0))
		if have < squad_slot_min(pos) or have > squad_slot_max(pos):
			return false
	return true


static func build_squad_positions(rng: RandomNumberGenerator) -> PackedStringArray:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var counts: Dictionary = {}
	var positions := PackedStringArray()
	for pos in POSITIONS:
		var need := squad_slot_min(pos)
		counts[pos] = need
		for _i in need:
			positions.append(pos)
	var extras := SQUAD_SIZE - positions.size()
	for _e in extras:
		var open: Array = []
		for pos in POSITIONS:
			if int(counts.get(pos, 0)) < squad_slot_max(pos):
				open.append(pos)
		if open.is_empty():
			break
		var pick := str(open[rng.randi_range(0, open.size() - 1)])
		counts[pick] = int(counts.get(pick, 0)) + 1
		positions.append(pick)
	for i in range(positions.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := positions[i]
		positions[i] = positions[j]
		positions[j] = tmp
	return positions


static func is_valid_character(code: String) -> bool:
	return code in CHARACTERS


static func clamp_personality(value: int) -> int:
	return clampi(value, PERSONALITY_MIN, PERSONALITY_MAX)


static func clamp_attribute(value: int) -> int:
	return clampi(value, ATTR_MIN, ATTR_MAX)


static func clamp_ability(value: int) -> int:
	return clampi(value, ABILITY_MIN, ABILITY_MAX)


static func clamp_reputation(value: int) -> int:
	return clampi(value, REPUTATION_MIN, REPUTATION_MAX)


static func attr_group_label(group: String) -> String:
	match group:
		ATTR_GROUP_TECHNICAL:
			return "Технические"
		ATTR_GROUP_MENTAL:
			return "Психологические"
		ATTR_GROUP_PHYSICAL:
			return "Физ. форма"
		ATTR_GROUP_SET_PIECES:
			return "Стандарты"
		ATTR_GROUP_GOALKEEPING:
			return "Вратарские"
		_:
			return group


static func attribute_label(key: String) -> String:
	match key:
		"finishing":
			return "Завершение"
		"passing":
			return "Пас"
		"first_touch":
			return "Первый контакт"
		"dribbling":
			return "Дриблинг"
		"tackling":
			return "Отбор"
		"marking":
			return "Опека"
		"technique":
			return "Техника"
		"crossing":
			return "Навесы"
		"composure":
			return "Хладнокровие"
		"decisions":
			return "Решения"
		"anticipation":
			return "Предвидение"
		"vision":
			return "Видение"
		"work_rate":
			return "Работоспособность"
		"concentration":
			return "Концентрация"
		"bravery":
			return "Смелость"
		"off_the_ball":
			return "Без мяча"
		"pace":
			return "Скорость"
		"acceleration":
			return "Ускорение"
		"stamina":
			return "Выносливость"
		"strength":
			return "Сила"
		"agility":
			return "Ловкость"
		"balance":
			return "Баланс"
		"recovery":
			return "Восстановление"
		"corners":
			return "Угловые"
		"free_kicks":
			return "Штрафные"
		"penalties":
			return "Пенальти"
		"long_shots":
			return "Дальние удары"
		"reflexes":
			return "Реакция"
		"handling":
			return "Игра руками"
		"positioning":
			return "Позиция"
		"one_on_ones":
			return "1 на 1"
		"aerial_reach":
			return "Верховые"
		"throwing":
			return "Ввод руками"
		"rushing_out":
			return "Выходы"
		"communication":
			return "Командование"
		_:
			return key


static func attribute_keys_for_group(group: String) -> Array:
	match group:
		ATTR_GROUP_TECHNICAL:
			return ATTR_TECHNICAL.duplicate()
		ATTR_GROUP_MENTAL:
			return ATTR_MENTAL.duplicate()
		ATTR_GROUP_PHYSICAL:
			return ATTR_PHYSICAL.duplicate()
		ATTR_GROUP_SET_PIECES:
			return ATTR_SET_PIECES.duplicate()
		ATTR_GROUP_GOALKEEPING:
			return ATTR_GOALKEEPING.duplicate()
		_:
			return []


static func attribute_groups_for_position(position: String) -> Array:
	if normalize_position(position) == POS_GK:
		return ATTR_GROUPS_GK.duplicate()
	return ATTR_GROUPS_OUTFIELD.duplicate()


## Position weights for CA. Keys are "group.key". Higher = more impact.
static func ability_weights(position: String) -> Dictionary:
	match normalize_position(position):
		POS_GK:
			return {
				"goalkeeping.reflexes": 5.0,
				"goalkeeping.handling": 4.5,
				"goalkeeping.positioning": 4.5,
				"goalkeeping.one_on_ones": 4.0,
				"goalkeeping.aerial_reach": 3.0,
				"goalkeeping.rushing_out": 2.5,
				"goalkeeping.communication": 2.0,
				"goalkeeping.throwing": 1.5,
				"mental.anticipation": 3.0,
				"mental.composure": 3.0,
				"mental.concentration": 3.0,
				"mental.decisions": 2.5,
				"mental.bravery": 2.0,
				"physical.agility": 2.5,
				"physical.strength": 1.5,
				"physical.pace": 1.0,
				"technical.first_touch": 1.0,
				"technical.passing": 1.0,
			}
		POS_CB:
			return {
				"technical.marking": 4.0,
				"technical.tackling": 4.0,
				"technical.passing": 1.5,
				"technical.first_touch": 1.5,
				"mental.anticipation": 3.5,
				"mental.concentration": 3.0,
				"mental.decisions": 3.0,
				"mental.bravery": 2.5,
				"mental.composure": 2.0,
				"physical.strength": 3.5,
				"physical.pace": 2.0,
				"physical.balance": 1.5,
				"physical.stamina": 1.5,
			}
		POS_FB:
			return {
				"technical.tackling": 3.0,
				"technical.marking": 2.5,
				"technical.crossing": 3.5,
				"technical.dribbling": 2.0,
				"technical.passing": 2.0,
				"mental.work_rate": 3.0,
				"mental.anticipation": 2.0,
				"mental.decisions": 2.0,
				"physical.pace": 3.5,
				"physical.acceleration": 3.0,
				"physical.stamina": 3.0,
				"physical.agility": 2.0,
			}
		POS_CM:
			return {
				"technical.passing": 4.0,
				"technical.first_touch": 3.0,
				"technical.technique": 2.5,
				"technical.dribbling": 2.0,
				"technical.tackling": 2.5,
				"mental.vision": 3.5,
				"mental.decisions": 3.5,
				"mental.work_rate": 3.0,
				"mental.composure": 2.0,
				"mental.anticipation": 2.5,
				"physical.stamina": 3.0,
				"physical.pace": 2.0,
				"physical.agility": 1.5,
			}
		POS_WM:
			return {
				"technical.crossing": 4.0,
				"technical.dribbling": 3.5,
				"technical.passing": 3.0,
				"technical.technique": 2.5,
				"technical.first_touch": 2.5,
				"mental.work_rate": 3.5,
				"mental.decisions": 2.5,
				"mental.off_the_ball": 2.0,
				"physical.pace": 3.5,
				"physical.acceleration": 3.5,
				"physical.stamina": 3.0,
				"physical.agility": 2.5,
			}
		POS_ST:
			return {
				"technical.finishing": 5.0,
				"technical.first_touch": 3.0,
				"technical.technique": 2.5,
				"technical.dribbling": 2.0,
				"mental.composure": 4.0,
				"mental.off_the_ball": 4.0,
				"mental.anticipation": 3.5,
				"mental.decisions": 2.0,
				"physical.pace": 2.5,
				"physical.acceleration": 2.5,
				"physical.strength": 2.5,
				"physical.balance": 2.0,
				"set_pieces.penalties": 1.5,
			}
		POS_WF:
			return {
				"technical.dribbling": 4.0,
				"technical.finishing": 3.5,
				"technical.technique": 3.0,
				"technical.first_touch": 2.5,
				"technical.crossing": 2.5,
				"mental.off_the_ball": 3.5,
				"mental.composure": 2.5,
				"mental.decisions": 2.0,
				"physical.pace": 4.0,
				"physical.acceleration": 4.0,
				"physical.agility": 3.0,
				"physical.stamina": 2.0,
			}
		_:
			return {
				"technical.passing": 2.0,
				"technical.technique": 2.0,
				"mental.decisions": 2.0,
				"physical.stamina": 2.0,
			}


## Soft generation bias: which attrs tend to be higher for the position.
static func generation_bias(position: String) -> Dictionary:
	var weights := ability_weights(position)
	var bias := {}
	for path in weights.keys():
		var w := float(weights[path])
		if w >= 3.5:
			bias[path] = 3
		elif w >= 2.5:
			bias[path] = 2
		elif w >= 1.5:
			bias[path] = 1
	return bias


static func get_attribute_value(attributes: Dictionary, group: String, key: String) -> int:
	var group_data: Variant = attributes.get(group, {})
	if typeof(group_data) != TYPE_DICTIONARY:
		return 0
	return clamp_attribute(int(group_data.get(key, ATTR_MIN)))


## Parsed "group.key" weight paths per position. The tables above stay the
## readable source of truth; this keeps CA out of the string-splitting business,
## because the match engine asks for it thousands of times per matchday.
static var _weight_terms: Dictionary = {}


static func ability_terms(position: String) -> Array:
	var pos := normalize_position(position)
	var cached: Variant = _weight_terms.get(pos, null)
	if typeof(cached) == TYPE_ARRAY:
		return cached
	var terms: Array = []
	var weights := ability_weights(pos)
	for path in weights.keys():
		var parts := str(path).split(".")
		if parts.size() != 2:
			continue
		terms.append([str(parts[0]), str(parts[1]), float(weights[path])])
	_weight_terms[pos] = terms
	return terms


## CA 0..100 from attributes for a position. Club reputation must not feed this.
static func calc_current_ability(attributes: Dictionary, position: String) -> int:
	return clamp_ability(int(round(calc_ability_exact(attributes, position))))


## The same value before rounding. A generator that nudges single attributes needs
## the fraction: one step often moves CA by less than a whole point.
static func calc_ability_exact(attributes: Dictionary, position: String) -> float:
	var terms := ability_terms(position)
	if terms.is_empty():
		return 50.0
	var total_w := 0.0
	var total := 0.0
	for term in terms:
		var group_data: Variant = attributes.get(term[0], null)
		var value := ATTR_MIN
		if typeof(group_data) == TYPE_DICTIONARY:
			value = clamp_attribute(int((group_data as Dictionary).get(term[1], ATTR_MIN)))
		var w: float = term[2]
		total += float(value) * w
		total_w += w
	if total_w <= 0.0:
		return 50.0
	# Mean attribute 1..20 → CA 0..100.
	var mean := total / total_w
	return clampf(mean / float(ATTR_MAX) * 100.0, float(ABILITY_MIN), float(ABILITY_MAX))


static func fit_attributes_to_target(
	attributes: Dictionary,
	position: String,
	target_ability: int,
	prefer_group: String = ""
) -> void:
	fit_attributes_to_exact(attributes, position, float(clamp_ability(target_ability)), prefer_group)


## Steps single attributes until the unrounded CA lands on the target. Only the
## weighted attributes of the position can move it, so a walk over the whole
## profile is the only way to hit a specific number.
## prefer_group is consumed first when it is set: ageing spends it on "physical"
## so a technical player keeps more of his CA into his thirties.
static func fit_attributes_to_exact(
	attributes: Dictionary,
	position: String,
	target_ability: float,
	prefer_group: String = ""
) -> void:
	var weights: Dictionary = ability_weights(position)
	var paths: Array = weights.keys()
	if paths.is_empty():
		return
	paths.sort_custom(func(a: Variant, b: Variant) -> bool:
		return float(weights[a]) > float(weights[b])
	)
	var preferred: Array = []
	if not prefer_group.is_empty():
		for path in paths:
			if str(path).begins_with(prefer_group + "."):
				preferred.append(path)

	var goal := clampf(target_ability, float(ABILITY_MIN), float(ABILITY_MAX))
	for step in 96:
		var current := calc_ability_exact(attributes, position)
		var gap := absf(current - goal)
		if gap < 0.45:
			return
		var direction := 1 if current < goal else -1
		# The preferred group is drained before anything else; the rest of the
		# profile starts one place further down on every step, so a long fit
		# spreads out instead of hammering the single heaviest attribute.
		if _try_attribute_steps(attributes, position, preferred, 0, direction, goal, gap):
			continue
		if not _try_attribute_steps(attributes, position, paths, step, direction, goal, gap):
			return


static func _try_attribute_steps(
	attributes: Dictionary,
	position: String,
	paths: Array,
	offset: int,
	direction: int,
	goal: float,
	gap: float
) -> bool:
	var count := paths.size()
	for i in count:
		var path: Variant = paths[(i + offset) % count]
		var parts := str(path).split(".")
		if parts.size() != 2 or not attributes.has(parts[0]):
			continue
		var group_map: Dictionary = attributes[parts[0]]
		if not group_map.has(parts[1]):
			continue
		var previous := int(group_map[parts[1]])
		var next_value := clamp_attribute(previous + direction)
		if next_value == previous:
			continue
		group_map[parts[1]] = next_value
		if absf(calc_ability_exact(attributes, position) - goal) < gap:
			return true
		group_map[parts[1]] = previous
	return false


## Soft bias offsets applied when rolling personality scales for a character.
static func character_personality_bias(character: String) -> Dictionary:
	match character:
		CHAR_PROFESSIONAL:
			return {"professionalism": 5, "temperament": -2, "sportsmanship": 2}
		CHAR_AMBITIOUS:
			return {"ambition": 5, "loyalty": -2, "risk": 2}
		CHAR_LOYAL:
			return {"loyalty": 5, "ambition": -1, "risk": -2}
		CHAR_MERCENARY:
			return {"ambition": 3, "loyalty": -4, "risk": 2, "ego": 1}
		CHAR_INDIVIDUALIST:
			return {"ego": 4, "sportsmanship": -2, "leadership": -1, "ambition": 1}
		CHAR_TEAM_PLAYER:
			return {"sportsmanship": 4, "ego": -3, "loyalty": 2, "leadership": 1}
		CHAR_HOT_HEAD:
			return {"temperament": 5, "aggression": 3, "sportsmanship": -3, "pressure": -1}
		CHAR_ICE_COLD:
			return {"temperament": -4, "pressure": 4, "aggression": -2, "professionalism": 2}
		CHAR_FEARLESS:
			return {"risk": 4, "pressure": 3, "aggression": 2, "temperament": 1}
		CHAR_INCONSISTENT:
			return {"pressure": -2, "temperament": 2, "professionalism": -2, "ego": 1}
		_:
			return {}


static func combined_personality_bias(characters: Array) -> Dictionary:
	var merged := {}
	for code in characters:
		var bias: Dictionary = character_personality_bias(str(code))
		for key in bias.keys():
			merged[key] = int(merged.get(key, 0)) + int(bias[key])
	return merged


static func recovery_of(player: Dictionary) -> int:
	var attributes: Variant = player.get("attributes", null)
	if typeof(attributes) != TYPE_DICTIONARY:
		return 10
	return get_attribute_value(attributes, ATTR_GROUP_PHYSICAL, ATTR_RECOVERY)


static func stamina_of(player: Dictionary) -> int:
	var attributes: Variant = player.get("attributes", null)
	if typeof(attributes) != TYPE_DICTIONARY:
		return 10
	return get_attribute_value(attributes, ATTR_GROUP_PHYSICAL, ATTR_STAMINA)


## Fills attribute keys added after the player was generated (older saves).
static func backfill_attributes(player: Dictionary, rng: RandomNumberGenerator = null) -> bool:
	var attributes: Variant = player.get("attributes", null)
	if typeof(attributes) != TYPE_DICTIONARY:
		return false
	var groups: Dictionary = attributes
	var position := str(player.get("position", ""))
	var changed := false
	for group in attribute_groups_for_position(position):
		var group_map: Variant = groups.get(group, null)
		if typeof(group_map) != TYPE_DICTIONARY:
			continue
		var map: Dictionary = group_map
		var missing: Array = []
		var total := 0
		var count := 0
		for key in attribute_keys_for_group(group):
			if map.has(key):
				total += clamp_attribute(int(map[key]))
				count += 1
			else:
				missing.append(key)
		if missing.is_empty():
			continue
		var mean := int(round(float(total) / float(count))) if count > 0 else 10
		for key in missing:
			var jitter := 0
			if rng != null:
				jitter = rng.randi_range(-2, 2)
			map[key] = clamp_attribute(mean + jitter)
			changed = true
	return changed


static func ability_of(player: Dictionary) -> int:
	var attributes: Variant = player.get("attributes", null)
	if typeof(attributes) == TYPE_DICTIONARY and not (attributes as Dictionary).is_empty():
		return calc_current_ability(attributes, str(player.get("position", "")))
	if player.has("current_ability"):
		return clamp_ability(int(player.get("current_ability", 0)))
	return clamp_ability(int(player.get("overall", 0)))
