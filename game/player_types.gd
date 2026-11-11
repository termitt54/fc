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

const POSITIONS := [POS_GK, POS_CB, POS_CM, POS_ST]
const FIELD_POSITIONS := [POS_CB, POS_CM, POS_ST]
const DEF_POSITIONS := [POS_CB]
const MID_POSITIONS := [POS_CM]
const ATT_POSITIONS := [POS_ST]
const LINE_GK := "GK"
const LINE_DEF := "DEF"
const LINE_MID := "MID"
const LINE_ATT := "ATT"
const SQUAD_LINES := [
	{"id": LINE_GK, "title": "Вратари"}, {"id": LINE_DEF, "title": "Защитники"},
	{"id": LINE_MID, "title": "Полузащитники"}, {"id": LINE_ATT, "title": "Нападающие"},
]
const SQUAD_SIZE := 20
const SQUAD_SLOT_MIN := {POS_GK:2, POS_CB:7, POS_CM:5, POS_ST:4}
const SQUAD_SLOT_MAX := {POS_GK:3, POS_CB:8, POS_CM:6, POS_ST:5}

## One dominant career character per player; neutral players use BALANCED.
const CHAR_BALANCED := "BALANCED"
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

const CHARACTERS_PER_PLAYER := 1

const CHARACTERS := [
	CHAR_BALANCED,
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

## Legacy compatibility table; generation now chooses exactly one character.
const CHARACTER_OPPOSITES := {
	CHAR_LOYAL: CHAR_MERCENARY,
	CHAR_MERCENARY: CHAR_LOYAL,
	CHAR_INDIVIDUALIST: CHAR_TEAM_PLAYER,
	CHAR_TEAM_PLAYER: CHAR_INDIVIDUALIST,
	CHAR_HOT_HEAD: CHAR_ICE_COLD,
	CHAR_ICE_COLD: CHAR_HOT_HEAD,
}

const PERSONALITY_KEYS := [] # Removed in compact model v2; kept for legacy API readers.

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
	ATTR_GROUP_PHYSICAL,
	ATTR_GROUP_SET_PIECES,
]

const ATTR_GROUPS_GK := [
	ATTR_GROUP_TECHNICAL,
	ATTR_GROUP_PHYSICAL,
	ATTR_GROUP_SET_PIECES,
	ATTR_GROUP_GOALKEEPING,
]

## Compact 8×8 attribute keys per group (1..20).
const ATTR_TECHNICAL := ["finishing", "passing", "technique", "dribbling", "defending"]

const ATTR_MENTAL := []

## "recovery" is deliberately absent from every ability_weights() table:
## it must not inflate CA, it only drives condition regain between rounds.
const ATTR_PHYSICAL := ["pace", "stamina", "strength", "recovery"]

const ATTR_STAMINA := "stamina"
const ATTR_RECOVERY := "recovery"

const ATTR_SET_PIECES := ["delivery", "penalties"]

const ATTR_GOALKEEPING := ["reflexes", "handling", "positioning", "exits", "aerial_reach"]


static func normalize_position(code: String) -> String:
	match code:
		"CB", "FB", "DF", "DEF": return POS_CB
		"CM", "WM", "DM", "AM", "MF", "MID": return POS_CM
		"ST", "WF", "W", "FW", "ATT": return POS_ST
		"GK": return POS_GK
		_: return POS_CM

static func position_label(code: String) -> String:
	return {POS_GK:"ГК", POS_CB:"ЗЩ", POS_CM:"ПЗЩ", POS_ST:"НАП"}[normalize_position(code)]

static func position_full_label(code: String) -> String:
	return {POS_GK:"Вратарь", POS_CB:"Защитник", POS_CM:"Полузащитник", POS_ST:"Нападающий"}[normalize_position(code)]

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
		CHAR_BALANCED:
			return "Уравновешенный"
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
		CHAR_BALANCED:
			return "Обычное поведение без специальных бонусов и штрафов"
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
			return "Лучше реализует пенальти и моменты в концовке матча"
		CHAR_FEARLESS:
			return "Слабее зависит от силы соперника и давления больших матчей"
		CHAR_INCONSISTENT:
			return "Больше разброс качества отдельных эпизодов"
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
			return [out[0]]
	# Legacy single archetype field.
	var legacy := str(player.get("archetype", "")).strip_edges()
	if is_valid_character(legacy):
		return [legacy]
	return [CHAR_BALANCED]


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
	return code in POSITIONS or code in ["FB","WM","WF","DM","AM","W","DF","MF","FW","DEF","MID","ATT"] or code in PackedStringArray(["DM", "AM", "W"])


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
	if int(counts.get(pos, 0)) >= squad_slot_max(pos):
		return false
	var mandatory_holes := 0
	for required in POSITIONS:
		mandatory_holes += maxi(0, squad_slot_min(required) - int(counts.get(required, 0)))
	# Optional depth cannot occupy the last slots reserved for missing roles.
	return int(counts.get(pos, 0)) < squad_slot_min(pos) or mandatory_holes < SQUAD_SIZE - squad.size()


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
		"defending":
			return "Защита"
		"delivery":
			return "Подачи и стандарты"
		"exits":
			return "Выходы и 1 на 1"
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
			return "Быстрота"
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
			return "Надёжность рук"
		"positioning":
			return "Выбор позиции"
		"one_on_ones":
			return "1 на 1"
		"aerial_reach":
			return "Верховая игра"
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
			return {"goalkeeping.reflexes": 5.0, "goalkeeping.handling": 4.5, "goalkeeping.positioning": 4.5, "goalkeeping.exits": 4.0, "goalkeeping.aerial_reach": 3.0, "technical.passing": 1.0, "technical.technique": 1.0, "physical.pace": 1.0, "physical.strength": 1.5}
		POS_CB:
			return {"technical.finishing": 1.0, "technical.defending": 8.0, "technical.passing": 2.0, "technical.technique": 2.0, "physical.strength": 4.0, "physical.pace": 2.0, "physical.stamina": 2.0, "set_pieces.delivery": 0.75, "set_pieces.penalties": 0.5}
		POS_CM:
			return {"technical.finishing": 4.5, "technical.passing": 8.0, "technical.technique": 6.0, "technical.dribbling": 2.0, "technical.defending": 3.0, "physical.stamina": 4.0, "physical.pace": 2.0, "set_pieces.delivery": 1.5, "set_pieces.penalties": 1.0}
		POS_ST:
			return {"technical.finishing": 9.0, "technical.technique": 5.0, "technical.dribbling": 2.0, "physical.pace": 5.0, "physical.strength": 3.0, "set_pieces.penalties": 2.0, "set_pieces.delivery": 1.0}
		_:
			return {"technical.passing": 2.0, "technical.technique": 2.0, "physical.stamina": 2.0}


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
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		return native.ability_exact(attributes,position)
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


## Personal leaning per attribute ("group.key" → multiplier), rolled once at
## birth and kept in player["aptitudes"]. It scales the attribute's share of
## every growth step and its secondary level: a striker with a low finishing
## aptitude still becomes a finisher, just a pacier, more technical one.
## A missing entry is neutral, which keeps players from older saves unchanged.
const APTITUDES_KEY := "aptitudes"
const APTITUDE_SPREAD := 0.45
const APTITUDE_MIN := 0.4
const APTITUDE_MAX := 2.5

## Every fitting step goes to the attribute whose next point is worth most:
## weight × aptitude × ((FIT_HEADROOM − value) / value)². The profile settles
## where value ≈ 21 / (1 + c / √(weight × aptitude)): proportional to the weight
## for a weak player, squeezed under 20 for a strong one, so a key skill stays
## off the cap until CA is near the top and light skills never drain to 1.
const FIT_HEADROOM := 21.0

## Skills outside the CA formula of a position. The fitter cannot use them, so
## they follow the player's level on their own: level × CA / 5 for a neutral
## aptitude. Recovery stays out: the condition model is calibrated on it.
const SECONDARY_LEVELS := {
	POS_GK: {"technical.finishing": 0.30, "technical.dribbling": 0.35, "technical.defending": 0.35, "physical.stamina": 0.60, "set_pieces.delivery": 0.45, "set_pieces.penalties": 0.40},
	POS_CB: {"technical.dribbling": 0.55},
	POS_CM: {"physical.strength": 0.65},
	POS_ST: {"technical.passing": 0.70, "technical.defending": 0.40, "physical.stamina": 0.72},
}
## Share of the distance to the secondary level covered per growing season.
const SECONDARY_GROWTH_SHARE := 0.4


static func roll_aptitudes(rng: RandomNumberGenerator, position: String) -> Dictionary:
	var out := {}
	for group in attribute_groups_for_position(position):
		for key in attribute_keys_for_group(group):
			if key == ATTR_RECOVERY:
				continue
			var value := exp(rng.randfn(0.0, APTITUDE_SPREAD))
			out["%s.%s" % [group, key]] = snappedf(clampf(value, APTITUDE_MIN, APTITUDE_MAX), 0.01)
	return out


static func aptitudes_of(player: Dictionary) -> Dictionary:
	var raw: Variant = player.get(APTITUDES_KEY, null)
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func aptitude_of(aptitudes: Dictionary, path: String) -> float:
	return clampf(float(aptitudes.get(path, 1.0)), APTITUDE_MIN, APTITUDE_MAX)


static func fit_priority(weight: float, aptitude: float, value: int, direction: int) -> float:
	var level := float(value if direction > 0 else value - 1)
	var ratio := (FIT_HEADROOM - level) / level
	var score := weight * aptitude * ratio * ratio
	return score if direction > 0 else -score


static func secondary_terms(position: String) -> Array:
	var levels: Dictionary = SECONDARY_LEVELS.get(normalize_position(position), {})
	var terms: Array = []
	for path in levels.keys():
		var parts := str(path).split(".")
		terms.append([str(parts[0]), str(parts[1]), float(levels[path])])
	return terms


static func secondary_target(level: float, aptitude: float, ability: float) -> int:
	return clamp_attribute(int(round(ability / 5.0 * level * sqrt(aptitude))))


## Generation: secondary skills start around the level of the new player.
static func settle_secondary(
	attributes: Dictionary,
	position: String,
	ability: float,
	aptitudes: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	for term in secondary_terms(position):
		var group_data: Variant = attributes.get(term[0], null)
		if typeof(group_data) != TYPE_DICTIONARY or not (group_data as Dictionary).has(term[1]):
			continue
		var target := secondary_target(term[2], aptitude_of(aptitudes, term[0] + "." + term[1]), ability)
		(group_data as Dictionary)[term[1]] = clamp_attribute(target + rng.randi_range(-1, 1))


## Development: secondary skills close part of the distance to their level.
## They never fall here; ageing is paid by the CA attributes.
static func grow_secondary(
	attributes: Dictionary,
	position: String,
	ability: float,
	aptitudes: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	for term in secondary_terms(position):
		var group_data: Variant = attributes.get(term[0], null)
		if typeof(group_data) != TYPE_DICTIONARY or not (group_data as Dictionary).has(term[1]):
			continue
		var value := int((group_data as Dictionary)[term[1]])
		var target := secondary_target(term[2], aptitude_of(aptitudes, term[0] + "." + term[1]), ability)
		if value >= target:
			continue
		var step := int(floor(float(target - value) * SECONDARY_GROWTH_SHARE + rng.randf()))
		if step > 0:
			(group_data as Dictionary)[term[1]] = clamp_attribute(mini(value + step, target))


static func fit_attributes_to_target(
	attributes: Dictionary,
	position: String,
	target_ability: int,
	prefer_group: String = "",
	aptitudes: Dictionary = {}
) -> void:
	fit_attributes_to_exact(attributes, position, float(clamp_ability(target_ability)), prefer_group, aptitudes)


## Steps single attributes until the unrounded CA lands on the target. Only the
## weighted attributes of the position can move it, so a walk over the whole
## profile is the only way to hit a specific number.
## prefer_group is consumed first when it is set: ageing spends it on "physical"
## so a technical player keeps more of his CA into his thirties.
static func fit_attributes_to_exact(
	attributes: Dictionary,
	position: String,
	target_ability: float,
	prefer_group: String = "",
	aptitudes: Dictionary = {}
) -> void:
	var native: Variant = NativeSimulation.core(false)
	if native != null:
		native.fit_attributes(attributes,position,target_ability,prefer_group,aptitudes)
		return
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
	for _step in 96:
		var current := calc_ability_exact(attributes, position)
		var gap := absf(current - goal)
		if gap < 0.45:
			return
		var direction := 1 if current < goal else -1
		if _step_best_attribute(attributes, position, preferred, weights, aptitudes, direction, goal, gap):
			continue
		if not _step_best_attribute(attributes, position, paths, weights, aptitudes, direction, goal, gap):
			return


## Tries candidates from the highest fit_priority down; the first step that
## brings CA closer to the goal is kept.
static func _step_best_attribute(
	attributes: Dictionary,
	position: String,
	paths: Array,
	weights: Dictionary,
	aptitudes: Dictionary,
	direction: int,
	goal: float,
	gap: float
) -> bool:
	var tried := {}
	for _attempt in paths.size():
		var best := -1
		var best_score := 0.0
		for i in paths.size():
			if tried.has(i):
				continue
			var parts := str(paths[i]).split(".")
			if parts.size() != 2 or not attributes.has(parts[0]):
				continue
			var group_map: Dictionary = attributes[parts[0]]
			if not group_map.has(parts[1]):
				continue
			var value := int(group_map[parts[1]])
			if clamp_attribute(value + direction) == value:
				continue
			var score := fit_priority(float(weights[paths[i]]), aptitude_of(aptitudes, str(paths[i])), value, direction)
			if best < 0 or score > best_score:
				best = i
				best_score = score
		if best < 0:
			return false
		tried[best] = true
		var chosen := str(paths[best]).split(".")
		var group_map: Dictionary = attributes[chosen[0]]
		var previous := int(group_map[chosen[1]])
		group_map[chosen[1]] = clamp_attribute(previous + direction)
		if absf(calc_ability_exact(attributes, position) - goal) < gap:
			return true
		group_map[chosen[1]] = previous
	return false


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


## Save migration is deterministic and consumes no random numbers.
## v3 put set pieces into the outfield CA formula; older players keep their CA
## because only their set pieces are raised to cover the new weight.
const MODEL_VERSION := 3
static func migrate_compact(player: Dictionary) -> bool:
	var version := int(player.get("player_model_version", 0))
	if version >= MODEL_VERSION:
		return false
	if version == 2:
		_raise_set_pieces_to(player)
		player["player_model_version"] = MODEL_VERSION
		return true
	var old: Dictionary = player.get("attributes", {})
	var compact := old.has("technical") and (old.get("technical", {}) as Dictionary).has("defending")
	var target := mini(int(player.get("current_ability", player.get("overall", 50))), int(player.get("potential_ability", 100)))
	var attrs := {}
	var sources := {
		"technical.finishing": ["technical.finishing"],
		"technical.passing": ["technical.passing"],
		"technical.technique": ["technical.technique", "technical.first_touch"],
		"technical.dribbling": ["technical.dribbling", "physical.agility", "physical.balance"],
		"technical.defending": ["technical.tackling", "technical.marking"],
		"physical.pace": ["physical.pace", "physical.acceleration"],
		"physical.stamina": ["physical.stamina"],
		"physical.strength": ["physical.strength"],
		"physical.recovery": ["physical.recovery"],
		"set_pieces.delivery": ["technical.crossing", "set_pieces.corners", "set_pieces.free_kicks"],
		"set_pieces.penalties": ["set_pieces.penalties"],
		"goalkeeping.exits": ["goalkeeping.one_on_ones", "goalkeeping.rushing_out"],
	}
	for group in attribute_groups_for_position(str(player.get("position", "CM"))):
		var values := {}
		for key in attribute_keys_for_group(group):
			var path: String = group + "." + str(key)
			var paths: Array = [path] if compact else sources.get(path, [path])
			var total := 0.0
			var count := 0
			for source in paths:
				var parts: PackedStringArray = str(source).split(".")
				var prior: Dictionary = old.get(parts[0], {})
				if prior.has(parts[1]):
					total += clamp_attribute(int(prior[parts[1]]))
					count += 1
			values[key] = clamp_attribute(int(round(total / count))) if count else clamp_attribute(int(round(target / 5.0)))
		attrs[group] = values
	player["attributes"] = attrs
	if not old.is_empty():
		fit_attributes_to_target(attrs, str(player.get("position", "CM")), target)
		var actual := calc_current_ability(attrs, str(player.get("position", "CM")))
		if actual > int(player.get("potential_ability", 100)):
			fit_attributes_to_target(attrs, str(player.get("position", "CM")), maxi(target - 1, 1))
		player["current_ability"] = calc_current_ability(attrs, str(player.get("position", "CM")))
		player["overall"] = player["current_ability"]
	player["characters"] = characters_of(player)
	player.erase("personality")
	player.erase("archetype")
	player.erase("_match_ratings")
	player["player_model_version"] = MODEL_VERSION
	return true


static func _raise_set_pieces_to(player: Dictionary) -> void:
	var attributes: Variant = player.get("attributes", null)
	var position := str(player.get("position", ""))
	if typeof(attributes) != TYPE_DICTIONARY or normalize_position(position) == POS_GK:
		return
	var set_pieces: Variant = (attributes as Dictionary).get(ATTR_GROUP_SET_PIECES, null)
	if typeof(set_pieces) != TYPE_DICTIONARY:
		return
	var target := mini(int(player.get("current_ability", 0)), int(player.get("potential_ability", ABILITY_MAX)))
	var weights := ability_weights(position)
	while calc_current_ability(attributes, position) < target:
		var best := ""
		var best_score := 0.0
		for key in ATTR_SET_PIECES:
			var path: String = ATTR_GROUP_SET_PIECES + "." + str(key)
			if not weights.has(path) or not (set_pieces as Dictionary).has(key):
				continue
			var value := int((set_pieces as Dictionary)[key])
			if value >= ATTR_MAX:
				continue
			var score := fit_priority(float(weights[path]), 1.0, value, 1)
			if best.is_empty() or score > best_score:
				best = str(key)
				best_score = score
		if best.is_empty():
			return
		(set_pieces as Dictionary)[best] = int((set_pieces as Dictionary)[best]) + 1

static func backfill_attributes(player: Dictionary, _rng: RandomNumberGenerator = null) -> bool:
	return migrate_compact(player)


static func ability_of(player: Dictionary) -> int:
	var attributes: Variant = player.get("attributes", null)
	if typeof(attributes) == TYPE_DICTIONARY and not (attributes as Dictionary).is_empty():
		return calc_current_ability(attributes, str(player.get("position", "")))
	if player.has("current_ability"):
		return clamp_ability(int(player.get("current_ability", 0)))
	return clamp_ability(int(player.get("overall", 0)))
