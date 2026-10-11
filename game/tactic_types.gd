class_name TacticTypes
extends RefCounted
## 8v8 formations (slots) and playing styles (how the ball moves).
## Style and formation stay in the same camp — no attack/defence mix.
## Mentality (attacking / balanced / defensive) is line height, not the style.


const PlayerTypesScript := preload("res://game/player_types.gd")

const MATCH_OUTFIELD := 7
const MATCH_BENCH := 10
const MATCHDAY_SQUAD := 18

const PICK_PRIMARY := 0.68
const PICK_BACKUP := 0.24
const PICK_OTHER_COMPAT := 0.70

const SOURCE_PRIMARY := "primary"
const SOURCE_BACKUP := "backup"
const SOURCE_OTHER := "other"

const FORM_232 := "2-3-2"
const FORM_322 := "3-2-2"
const FORM_331 := "3-3-1"
const FORM_223 := "2-2-3"
const FORM_241 := "2-4-1"
const FORM_313 := "3-1-3"

const FORMATIONS := [FORM_232, FORM_322, FORM_331, FORM_223, FORM_241, FORM_313]

const FORMATION_META := {
	FORM_232: {
		"name": "Контроль",
		"slots": ["CB", "CB", "WM", "CM", "WM", "WF", "ST"],
		"spine": ["CM", "CB", "WF"],
	},
	FORM_322: {
		"name": "Блок",
		"slots": ["FB", "CB", "FB", "CM", "CM", "ST", "WF"],
		"spine": ["CB", "CM", "FB"],
	},
	FORM_331: {
		"name": "Низкий блок",
		"slots": ["FB", "CB", "FB", "WM", "CM", "WM", "ST"],
		"spine": ["CB", "CM", "FB"],
	},
	FORM_223: {
		"name": "Крылья",
		"slots": ["CB", "CB", "CM", "WM", "WF", "ST", "WF"],
		"spine": ["WF", "CB", "ST"],
	},
	FORM_241: {
		"name": "Перегрузка",
		"slots": ["CB", "CB", "WM", "CM", "CM", "WM", "ST"],
		"spine": ["CM", "WM", "CB"],
	},
	FORM_313: {
		"name": "Прессинг",
		"slots": ["FB", "CB", "FB", "CM", "WF", "ST", "WF"],
		"spine": ["FB", "WF", "ST"],
	},
}

const STYLE_TIKI_TAKA := "tiki_taka"
const STYLE_CONTROL := "control"
const STYLE_VERTICAL := "vertical"
const STYLE_KICK_RUSH := "kick_rush"
const STYLE_PRESSING := "pressing"
const STYLE_PARK_BUS := "park_bus"
const STYLE_COUNTER := "counter"

const STYLES := [
	STYLE_TIKI_TAKA,
	STYLE_CONTROL,
	STYLE_VERTICAL,
	STYLE_KICK_RUSH,
	STYLE_PRESSING,
	STYLE_PARK_BUS,
	STYLE_COUNTER,
]

const STYLE_LABELS := {
	STYLE_TIKI_TAKA: "Тики-така",
	STYLE_CONTROL: "Контроль",
	STYLE_VERTICAL: "Вертикаль",
	STYLE_KICK_RUSH: "Бей-беги",
	STYLE_PRESSING: "Прессинг",
	STYLE_PARK_BUS: "Автобус",
	STYLE_COUNTER: "Контратака",
}

const STYLE_TIPS := {
	STYLE_TIKI_TAKA: "Короткие передачи, высокий процент владения, терпеливый розыгрыш.",
	STYLE_CONTROL: "Темп сам задаёт команда: держит мяч, но бьёт в момент, а не крутит зря.",
	STYLE_VERTICAL: "Быстрый выход вперёд через центр, меньше касаний в своей половине.",
	STYLE_KICK_RUSH: "Длинные передачи за спину, борьба на втором этаже, мало комбинаций.",
	STYLE_PRESSING: "Высокая встреча, отбор сразу после потери, игра на чужой половине.",
	STYLE_PARK_BUS: "Низкий блок, компактные линии, минимум риска у своих ворот.",
	STYLE_COUNTER: "Отдаёт инициативу и бьёт в свободные зоны после отбора.",
}

const STYLE_WEIGHTS := {
	STYLE_TIKI_TAKA: 14,
	STYLE_CONTROL: 20,
	STYLE_VERTICAL: 16,
	STYLE_KICK_RUSH: 10,
	STYLE_PRESSING: 16,
	STYLE_PARK_BUS: 10,
	STYLE_COUNTER: 14,
}

const FORMATION_WEIGHTS := {
	FORM_232: 24,
	FORM_322: 16,
	FORM_331: 12,
	FORM_223: 16,
	FORM_241: 16,
	FORM_313: 16,
}

const CAMP_POSSESSION := "possession"
const CAMP_ATTACK := "attack"
const CAMP_DEFEND := "defend"

const STYLE_CAMP := {
	STYLE_TIKI_TAKA: CAMP_POSSESSION,
	STYLE_CONTROL: CAMP_POSSESSION,
	STYLE_VERTICAL: CAMP_ATTACK,
	STYLE_KICK_RUSH: CAMP_ATTACK,
	STYLE_PRESSING: CAMP_ATTACK,
	STYLE_PARK_BUS: CAMP_DEFEND,
	STYLE_COUNTER: CAMP_DEFEND,
}

const FORMATION_CAMP := {
	FORM_232: CAMP_POSSESSION,
	FORM_241: CAMP_POSSESSION,
	FORM_223: CAMP_ATTACK,
	FORM_313: CAMP_ATTACK,
	FORM_322: CAMP_DEFEND,
	FORM_331: CAMP_DEFEND,
}

## Allow-list only. Attack styles never sit on a low block; the bus never plays 2-2-3.
const STYLE_FORMATIONS := {
	STYLE_TIKI_TAKA: [FORM_232, FORM_241],
	STYLE_CONTROL: [FORM_232, FORM_241],
	STYLE_VERTICAL: [FORM_223, FORM_313, FORM_232],
	STYLE_KICK_RUSH: [FORM_223, FORM_313],
	STYLE_PRESSING: [FORM_313, FORM_241],
	STYLE_PARK_BUS: [FORM_331, FORM_322],
	STYLE_COUNTER: [FORM_322, FORM_331],
}

## Backup style stays in the same family — never possession/attack vs the bus.
const STYLE_RELATIVES := {
	STYLE_TIKI_TAKA: [STYLE_CONTROL],
	STYLE_CONTROL: [STYLE_TIKI_TAKA],
	STYLE_VERTICAL: [STYLE_PRESSING, STYLE_KICK_RUSH],
	STYLE_KICK_RUSH: [STYLE_VERTICAL, STYLE_PRESSING],
	STYLE_PRESSING: [STYLE_VERTICAL, STYLE_KICK_RUSH],
	STYLE_PARK_BUS: [STYLE_COUNTER],
	STYLE_COUNTER: [STYLE_PARK_BUS],
}

const MENTALITY_ATTACKING := "attacking"
const MENTALITY_BALANCED := "balanced"
const MENTALITY_DEFENSIVE := "defensive"

const STYLE_MENTALITY := {
	STYLE_TIKI_TAKA: MENTALITY_ATTACKING,
	STYLE_CONTROL: MENTALITY_BALANCED,
	STYLE_VERTICAL: MENTALITY_ATTACKING,
	STYLE_KICK_RUSH: MENTALITY_ATTACKING,
	STYLE_PRESSING: MENTALITY_ATTACKING,
	STYLE_PARK_BUS: MENTALITY_DEFENSIVE,
	STYLE_COUNTER: MENTALITY_DEFENSIVE,
}

const MENTALITY_STYLES := {
	MENTALITY_ATTACKING: [STYLE_PRESSING, STYLE_VERTICAL, STYLE_TIKI_TAKA],
	MENTALITY_BALANCED: [STYLE_CONTROL, STYLE_TIKI_TAKA],
	MENTALITY_DEFENSIVE: [STYLE_PARK_BUS, STYLE_COUNTER],
}


static func is_style(code: String) -> bool:
	return STYLES.has(code)


static func is_formation(code: String) -> bool:
	return FORMATIONS.has(code)


static func normalize_style(code: String) -> String:
	return code if is_style(code) else ""


static func normalize_formation(code: String) -> String:
	return code if is_formation(code) else ""


static func style_label(code: String) -> String:
	var key := normalize_style(code)
	if key.is_empty():
		return "—"
	return str(STYLE_LABELS.get(key, key))


static func style_tip(code: String) -> String:
	var key := normalize_style(code)
	if key.is_empty():
		return ""
	return str(STYLE_TIPS.get(key, ""))


static func formation_name(code: String) -> String:
	var key := normalize_formation(code)
	if key.is_empty():
		return "—"
	var meta: Dictionary = FORMATION_META.get(key, {})
	return str(meta.get("name", key))


static func formation_label(code: String) -> String:
	var key := normalize_formation(code)
	if key.is_empty():
		return "—"
	return "%s %s" % [key, formation_name(key)]


static func mentality_of_style(style: String) -> String:
	var key := normalize_style(style)
	if key.is_empty():
		return MENTALITY_BALANCED
	return str(STYLE_MENTALITY.get(key, MENTALITY_BALANCED))


static func camp_of_style(style: String) -> String:
	var key := normalize_style(style)
	if key.is_empty():
		return ""
	return str(STYLE_CAMP.get(key, ""))


static func camp_of_formation(formation: String) -> String:
	var key := normalize_formation(formation)
	if key.is_empty():
		return ""
	return str(FORMATION_CAMP.get(key, ""))


static func camps_clash(left: String, right: String) -> bool:
	if left.is_empty() or right.is_empty() or left == right:
		return false
	return left == CAMP_DEFEND or right == CAMP_DEFEND


static func is_compatible(style: String, formation: String) -> bool:
	var style_key := normalize_style(style)
	var form_key := normalize_formation(formation)
	if style_key.is_empty() or form_key.is_empty():
		return false
	if camps_clash(camp_of_style(style_key), camp_of_formation(form_key)):
		return false
	return formations_for_style(style_key).has(form_key)


static func outfield_slots(formation: String) -> Array:
	var key := normalize_formation(formation)
	if key.is_empty():
		return []
	var meta: Dictionary = FORMATION_META.get(key, {})
	return (meta.get("slots", []) as Array).duplicate()


static func starting_xi(formation: String) -> Array:
	var xi: Array = [PlayerTypesScript.POS_GK]
	xi.append_array(outfield_slots(formation))
	return xi


static func spine_slots(formation: String) -> Array:
	var key := normalize_formation(formation)
	if key.is_empty():
		return [PlayerTypesScript.POS_CM, PlayerTypesScript.POS_CB]
	var meta: Dictionary = FORMATION_META.get(key, {})
	return (meta.get("spine", []) as Array).duplicate()


static func bench_slots(formation: String) -> Array:
	var start := outfield_slots(formation)
	var seen: Dictionary = {}
	var covers: Array = []
	for pos in start:
		var code := str(pos)
		if seen.has(code):
			continue
		seen[code] = true
		covers.append(code)
	var bench: Array = [PlayerTypesScript.POS_GK]
	bench.append_array(covers)
	var spine := spine_slots(formation)
	var i := 0
	while bench.size() < MATCH_BENCH:
		if spine.is_empty():
			bench.append(PlayerTypesScript.POS_CM)
			continue
		bench.append(str(spine[i % spine.size()]))
		i += 1
	if bench.size() > MATCH_BENCH:
		bench.resize(MATCH_BENCH)
	return bench


static func formations_for_style(style: String) -> Array:
	var key := normalize_style(style)
	if key.is_empty():
		return FORMATIONS.duplicate()
	return (STYLE_FORMATIONS.get(key, FORMATIONS) as Array).duplicate()


static func relatives_for_style(style: String) -> Array:
	var key := normalize_style(style)
	if key.is_empty():
		return []
	return (STYLE_RELATIVES.get(key, []) as Array).duplicate()


static func primary_style_of(coach: Dictionary) -> String:
	ensure_coach_tactics(coach)
	return normalize_style(str(coach.get("primary_style", "")))


static func backup_style_of(coach: Dictionary) -> String:
	ensure_coach_tactics(coach)
	return normalize_style(str(coach.get("backup_style", "")))


static func primary_formation_of(coach: Dictionary) -> String:
	ensure_coach_tactics(coach)
	return normalize_formation(str(coach.get("primary_formation", "")))


static func backup_formation_of(coach: Dictionary) -> String:
	ensure_coach_tactics(coach)
	return normalize_formation(str(coach.get("backup_formation", "")))


static func roll_coach_identity(rng: RandomNumberGenerator) -> Dictionary:
	var primary_style := _weighted_pick(rng, STYLES, STYLE_WEIGHTS)
	var backup_style := _pick_backup_style(rng, primary_style)
	var primary_formation := _weighted_pick(rng, formations_for_style(primary_style), FORMATION_WEIGHTS)
	var backup_formation := _pick_backup_formation(rng, backup_style, primary_formation)
	return {
		"primary_style": primary_style,
		"backup_style": backup_style,
		"primary_formation": primary_formation,
		"backup_formation": backup_formation,
		"style": mentality_of_style(primary_style),
	}


static func ensure_coach_tactics(coach: Dictionary) -> Dictionary:
	if coach.is_empty() or _tactics_are_valid(coach):
		return coach
	var rng := RandomNumberGenerator.new()
	var seed_id := int(coach.get("id", 0)) * 10007 + int(coach.get("club_id", 0))
	rng.seed = seed_id if seed_id != 0 else 1

	var primary := normalize_style(str(coach.get("primary_style", "")))
	if primary.is_empty():
		primary = _infer_primary_style(str(coach.get("style", "")), rng)
	var backup := normalize_style(str(coach.get("backup_style", "")))
	if backup.is_empty() or backup == primary or camps_clash(camp_of_style(primary), camp_of_style(backup)):
		backup = _pick_backup_style(rng, primary)

	var primary_form := normalize_formation(str(coach.get("primary_formation", "")))
	if primary_form.is_empty() or not is_compatible(primary, primary_form):
		primary_form = _weighted_pick(rng, formations_for_style(primary), FORMATION_WEIGHTS)
	var backup_form := normalize_formation(str(coach.get("backup_formation", "")))
	if backup_form.is_empty() or backup_form == primary_form or not is_compatible(backup, backup_form):
		backup_form = _pick_backup_formation(rng, backup, primary_form)

	coach["primary_style"] = primary
	coach["backup_style"] = backup
	coach["primary_formation"] = primary_form
	coach["backup_formation"] = backup_form
	var mentality := str(coach.get("style", ""))
	if not _is_mentality(mentality) or camps_clash(camp_of_style(primary), _camp_of_mentality(mentality)):
		coach["style"] = mentality_of_style(primary)
	return coach


## Every read of a coach's tactics runs through ensure_coach_tactics, so the
## already-normalised case must not touch the random generator at all.
static func _tactics_are_valid(coach: Dictionary) -> bool:
	var primary := normalize_style(str(coach.get("primary_style", "")))
	if primary.is_empty():
		return false
	var backup := normalize_style(str(coach.get("backup_style", "")))
	if backup.is_empty() or backup == primary:
		return false
	if camps_clash(camp_of_style(primary), camp_of_style(backup)):
		return false
	var primary_form := str(coach.get("primary_formation", ""))
	if not is_compatible(primary, primary_form):
		return false
	var backup_form := str(coach.get("backup_formation", ""))
	if backup_form == primary_form or not is_compatible(backup, backup_form):
		return false
	var mentality := str(coach.get("style", ""))
	if not _is_mentality(mentality):
		return false
	return not camps_clash(camp_of_style(primary), _camp_of_mentality(mentality))


static func pick_match_plan(coach: Dictionary, _rng: RandomNumberGenerator) -> Dictionary:
	ensure_coach_tactics(coach)
	var primary_style := str(coach.get("primary_style", ""))
	if not is_style(primary_style):
		primary_style = STYLE_CONTROL
	var primary_form := str(coach.get("primary_formation", ""))
	if not is_compatible(primary_style, primary_form):
		primary_form = FORM_232
	return {
		"style": primary_style,
		"formation": primary_form,
		"style_source": SOURCE_PRIMARY,
		"formation_source": SOURCE_PRIMARY,
	}


static func _infer_primary_style(legacy: String, rng: RandomNumberGenerator) -> String:
	var as_style := normalize_style(legacy)
	if not as_style.is_empty():
		return as_style
	var pool: Array = MENTALITY_STYLES.get(legacy, MENTALITY_STYLES[MENTALITY_BALANCED])
	return str(pool[rng.randi_range(0, pool.size() - 1)])


static func _pick_backup_style(rng: RandomNumberGenerator, primary: String) -> String:
	var relatives := relatives_for_style(primary)
	var pool: Array = []
	for code in relatives:
		var item := str(code)
		if item != primary and is_style(item) and not camps_clash(camp_of_style(primary), camp_of_style(item)):
			pool.append(item)
	if pool.is_empty():
		for code in STYLES:
			if code != primary and not camps_clash(camp_of_style(primary), camp_of_style(code)):
				pool.append(code)
	if pool.is_empty():
		return primary
	return str(pool[rng.randi_range(0, pool.size() - 1)])


static func _pick_backup_formation(rng: RandomNumberGenerator, style: String, avoid_form: String) -> String:
	var pool: Array = []
	for code in formations_for_style(style):
		if str(code) != avoid_form:
			pool.append(str(code))
	if pool.is_empty():
		pool = formations_for_style(style)
	if pool.is_empty():
		return avoid_form
	return _weighted_pick(rng, pool, FORMATION_WEIGHTS)


static func _styles_for_other_pick(primary: String, backup: String) -> Array:
	var pool: Array = []
	for code in STYLES:
		if code == primary or code == backup:
			continue
		if camps_clash(camp_of_style(primary), camp_of_style(code)):
			continue
		pool.append(code)
	return pool


static func _pick_formation_for_style(rng: RandomNumberGenerator, coach: Dictionary, style: String) -> Dictionary:
	var catalog := formations_for_style(style)
	var primary_form := str(coach.get("primary_formation", ""))
	var backup_form := str(coach.get("backup_formation", ""))
	var preferred := ""
	var alternate := ""
	if is_compatible(style, primary_form):
		preferred = primary_form
	if is_compatible(style, backup_form) and backup_form != preferred:
		if preferred.is_empty():
			preferred = backup_form
		else:
			alternate = backup_form
	if preferred.is_empty() and not catalog.is_empty():
		preferred = _weighted_pick(rng, catalog, FORMATION_WEIGHTS)
	return _pick_from_prefs(rng, preferred, alternate, catalog, catalog)


static func _pick_from_prefs(
	rng: RandomNumberGenerator,
	primary: String,
	backup: String,
	catalog: Array,
	compatible: Array
) -> Dictionary:
	var roll := rng.randf()
	if not primary.is_empty() and roll < PICK_PRIMARY:
		return {"code": primary, "source": SOURCE_PRIMARY}
	if not backup.is_empty() and roll < PICK_PRIMARY + PICK_BACKUP:
		return {"code": backup, "source": SOURCE_BACKUP}
	var pool: Array = []
	for code in catalog:
		var item := str(code)
		if item != primary and item != backup:
			pool.append(item)
	var preferred: Array = []
	for code in pool:
		if compatible.has(code):
			preferred.append(code)
	if not preferred.is_empty() and rng.randf() < PICK_OTHER_COMPAT:
		pool = preferred
	if pool.is_empty():
		if not primary.is_empty():
			return {"code": primary, "source": SOURCE_PRIMARY}
		if not catalog.is_empty():
			return {"code": str(catalog[0]), "source": SOURCE_OTHER}
		return {"code": "", "source": SOURCE_OTHER}
	return {"code": str(pool[rng.randi_range(0, pool.size() - 1)]), "source": SOURCE_OTHER}


static func _weighted_pick(rng: RandomNumberGenerator, items: Array, weights: Dictionary) -> String:
	var total := 0
	var resolved: Array = []
	for item in items:
		var code := str(item)
		if code.is_empty():
			continue
		resolved.append(code)
		total += maxi(1, int(weights.get(code, 1)))
	if resolved.is_empty():
		return ""
	var ticket := rng.randi_range(1, maxi(1, total))
	var acc := 0
	for code in resolved:
		acc += maxi(1, int(weights.get(code, 1)))
		if ticket <= acc:
			return str(code)
	return str(resolved[resolved.size() - 1])


static func _is_mentality(code: String) -> bool:
	return code == MENTALITY_ATTACKING or code == MENTALITY_BALANCED or code == MENTALITY_DEFENSIVE


static func _camp_of_mentality(code: String) -> String:
	if code == MENTALITY_DEFENSIVE:
		return CAMP_DEFEND
	if code == MENTALITY_ATTACKING:
		return CAMP_ATTACK
	if code == MENTALITY_BALANCED:
		return CAMP_POSSESSION
	return ""
