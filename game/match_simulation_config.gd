class_name MatchSimulationConfig
extends RefCounted
## Live match-engine knobs. Defaults live in MatchTypes; this file is the
## runtime overlay saved to user://config/match_simulation.json.


const MatchTypesScript := preload("res://game/match_types.gd")

const DEFAULT_CONFIG_PATH := "user://config/match_simulation.json"
const CONFIG_VERSION := 8

const GROUP_SCORING := "scoring"
const GROUP_BALANCE := "players"
const GROUP_DISCIPLINE := GROUP_SCORING
const GROUP_COACHING := "coaching"
const GROUP_FITNESS := "fitness"
const GROUP_RECOVERY := GROUP_FITNESS
const GROUP_LINEUP := "rotation"

const GROUPS := [
	{"id": GROUP_SCORING, "title": "Симуляция матчей", "short": "Матчи", "hint": "Темп, голы, карточки и травмы. Базовые вероятности затем меняются из-за игроков и ситуации на поле. Больше голов не означает больше преимущества фаворита."},
	{"id": GROUP_BALANCE, "title": "Влияние игроков на матч", "short": "Игроки", "hint": "Каждый футболист действует своими навыками: передаёт, принимает мяч, обыгрывает, отбирает, бьёт или отражает удар. CA и средняя сила команды в расчёте эпизодов не участвуют. Талант страны в расчёт матча не входит."},
	{"id": GROUP_COACHING, "title": "Характер игры и тренер", "short": "Характер и тренер", "hint": "Характер игры определяет подключения в атаке и осторожность. Все команды играют 3-2-2. Характеристики тренера влияют на организацию игры. Даже хороший тренер не заменяет сильных футболистов."},
	{"id": GROUP_FITNESS, "title": "Выносливость и восстановление", "short": "Выносливость", "hint": "Готовность — запас сил между матчами, от 0 до 100. Работоспособность — насколько игрок устаёт в текущем матче. Выносливость снижает расход сил; Восстановление ускоряет отдых."},
	{"id": GROUP_LINEUP, "title": "Ротация и правила замен", "short": "Ротация и замены", "hint": "Ротация меняет стартовый состав между матчами. Замены выпускают запасных во время игры. Тренер учитывает позиции, качество скамейки и ожидаемую пользу до конца матча; травмы требуют отдельного решения."},
]

static var config_path := DEFAULT_CONFIG_PATH
static var _loaded := false
static var _values: Dictionary = {}
static var _schema_by_key: Dictionary = {}
static var _fingerprint := ""
# Derived lookup tables contain no player state and are cleared on every config change.
static var _curve_tables: Dictionary = {}
static var _play_table := PackedFloat64Array()
static var _select_table := PackedFloat64Array()


static func schema() -> Array:
	var knobs := [
		_knob("chances_per_phase", GROUP_SCORING, "Темп принятия решений", "100% — обычный темп решений. Выше — решения принимаются чаще, ниже — игрок дольше выбирает действие. Настройка сокращает время между решениями футболистов. Моменты возникают из действий на поле.", MatchTypesScript.CHANCES_PER_PHASE, 0.4, 2.4, 0.02, 2, false),
		_knob("chance_create_base", GROUP_SCORING, "Склонность к ударам", "100% — обычная склонность бить из зоны удара. Выше — чаще бьёт, ниже — чаще продолжает комбинацию. Защитник может помешать удару.", MatchTypesScript.CHANCE_CREATE_BASE, 0.4, 0.95, 0.01, 2, true),
		_knob("shot_on_target_base", GROUP_SCORING, "Точность ударов", "100% — обычная погрешность прицеливания. Выше — точнее удары. Попадание зависит от завершения и дистанции; значение не равно проценту попаданий.", MatchTypesScript.SHOT_ON_TARGET_BASE, 0.35, 0.85, 0.01, 2, true),
		_knob("shot_conversion_base", GROUP_SCORING, "Скорость мяча при ударе", "100% — обычная скорость мяча. Выше — мяч летит быстрее, вратарю остаётся меньше времени на реакцию. Гол определяется траекторией, положением и действиями вратаря; значение не равно проценту голов.", MatchTypesScript.SHOT_CONVERSION_BASE, 0.1, 0.55, 0.01, 2, true),
		_knob("set_piece_share", GROUP_SCORING, "Частота навесов", "Как часто игрок выбирает верховую передачу на фланге. Навес и розыгрыш штрафного выполняются навыком Стандарты; в воздухе важна борьба за мяч.", MatchTypesScript.SET_PIECE_SHARE, 0, 0.5, 0.01, 2, true),
		_knob("penalty_per_phase", GROUP_SCORING, "Частота пенальти", "Больше — пенальти назначаются чаще. Значение 0.013 — базовая частота на одну команду за 5 минут, примерно одно назначение на 4 матча до игровых поправок.", MatchTypesScript.PENALTY_PER_PHASE, 0, 0.05, 0.001, 3, false),
		_knob("penalty_conversion_base", GROUP_SCORING, "Точность пенальти", "100% — обычная погрешность удара с точки. Выше — меньше погрешность. Фактический результат зависит от навыка Пенальти, траектории удара, реакции и позиции вратаря. Значение не равно проценту реализации.", MatchTypesScript.PENALTY_CONVERSION_BASE, 0.5, 0.95, 0.01, 2, true),
		_knob("yellow_per_phase", GROUP_SCORING, "Частота карточек", "Больше — чаще фиксируются нарушения с карточками. 0.09 — базовая частота на команду за 5 минут; строгость судьи и дисциплина игроков меняют итог.", MatchTypesScript.YELLOW_PER_PHASE, 0, 0.4, 0.002, 3, false),
		_knob("red_direct_share", GROUP_SCORING, "Доля прямых удалений", "Какая часть событий с карточкой сразу становится красной. Больше — больше прямых удалений и неожиданных переломов. Вторая жёлтая считается отдельно.", MatchTypesScript.RED_DIRECT_SHARE, 0, 0.15, 0.002, 3, true),
		_knob("injury_per_phase", GROUP_SCORING, "Частота травм", "Больше — игроки чаще получают травмы по ходу встречи. Уставшие игроки чаще выбираются пострадавшими; в дополнительное время риск выше. Это базовая частота, не доля травмированных игроков.", MatchTypesScript.INJURY_PER_PHASE, 0, 0.08, 0.001, 3, false),
		_knob("duel_skill_influence", GROUP_BALANCE, "Влияние личных навыков в эпизодах", "100% — обычная разница в обводке против защиты, силовой борьбе и попытке пробить под давлением. Выше — преимущество навыка в этих единоборствах сильнее; 0% уравнивает их шансы. Точность передач и ударов, быстрота и реакция продолжают работать напрямую и этим ползунком не отключаются.", 1.0, 0, 2, 0.05, 2, true),
		_knob("tactics_influence", GROUP_COACHING, "Влияние характера игры", "100% — обычная разница между атакующим и оборонительным характером: подключения, передачи и выбор удара. 0% уравнивает эти поправки. Схема всегда 3-2-2.", 1.0, 0, 2, 0.05, 2, true),
		_knob("coach_influence", GROUP_COACHING, "Влияние мастерства тренера в матче", "100% — обычное влияние тренера на выбор адресата передачи, плотность опеки и интенсивность перемещений. Выше — различие сильного и слабого тренера заметнее; 0% уравнивает эти компоненты. Выбор состава и решения о заменах сохраняются.", 1.0, 0, 2, 0.05, 2, true),
		_knob("condition_after_stamina_10", GROUP_FITNESS, "Готовность после полного матча: выносливость 10", "60 означает потерю около 40 пунктов за 50 минут при старте со 100 и обычной нагрузке. Для выносливости 20 по умолчанию остаётся 82: такой игрок тратит более чем вдвое меньше готовности. Минуты, нагрузка и возраст меняют расход.", MatchTypesScript.CONDITION_AFTER_STAMINA_10, 0, 90, 1, 0, false),
		_knob("fresh_after_stamina_10", GROUP_FITNESS, "Работоспособность к концу матча: выносливость 10", "По умолчанию 72% после полных 50 минут при обычной нагрузке; при выносливости 20 — 92%. Усталость снижает скорость и качество действий, а тренер может раньше заменить уставшего игрока. Фактический расход зависит от активности на поле.", MatchTypesScript.FRESH_AFTER_STAMINA_10, 0.2, 1, 0.01, 2, true),
		_knob("recovery_share_10", GROUP_FITNESS, "Восстановление за игровой день: обычный игрок", "54% восполняет чуть больше половины недостающей готовности, плюс фиксированная прибавка ниже. При готовности 60 это около +22 пунктов до прибавки. Больше — меньше потребность в отдыхе.", MatchTypesScript.RECOVERY_SHARE_10, 0.1, 0.8, 0.01, 2, true),
		_knob("recovery_floor", GROUP_FITNESS, "Дополнительное восстановление за день", "Прибавка в пунктах готовности сверх процентного восстановления. 3 означает ещё +3 из 100. Больше — быстрее возвращаются силы, меньше — важнее запасные.", MatchTypesScript.CONDITION_RECOVERY_FLOOR, 0, 10, 1, 0, false),
		_knob("recovery_idle_factor", GROUP_FITNESS, "Бонус отдыха пропустившим матч", "1.25× — процентная часть восстановления на 25% быстрее у тех, кто не играл. Больше — выгоднее дать игроку день отдыха; 1× — этого бонуса нет.", MatchTypesScript.CONDITION_IDLE_FACTOR, 1, 2, 0.05, 2, false),
		_knob("condition_play_floor", GROUP_FITNESS, "Работоспособность при нулевой готовности", "86% — нижний предел влияния готовности на силу в эпизодах до усталости внутри матча. Ниже — измотанный игрок играет слабее. При 100% готовность перестаёт влиять на этот множитель.", MatchTypesScript.CONDITION_FIT_FLOOR, 0.3, 1, 0.01, 2, true),
		_knob("condition_after_stamina_1", GROUP_FITNESS, "Готовность после матча: выносливость 1", "Низкая выносливость. Меньше оставшихся пунктов — тяжелее восстановиться после игры. Для промежуточных характеристик значение рассчитывается между соседними опорными точками.", MatchTypesScript.CONDITION_AFTER_STAMINA_1, 0, 80, 1, 0, false),
		_knob("condition_after_stamina_20", GROUP_FITNESS, "Готовность после матча: выносливость 20", "Высокая выносливость. Значение должно быть не ниже, чем у обычного игрока. Больше — меньше потеря готовности после полной игры.", MatchTypesScript.CONDITION_AFTER_STAMINA_20, 10, 95, 1, 0, false),
		_knob("fresh_after_stamina_1", GROUP_FITNESS, "Работоспособность к концу матча: выносливость 1", "Низкая выносливость. Ниже — сильнее падение силы на поле. Пример: 75% означает примерно четверть потери работоспособности при обычной нагрузке.", MatchTypesScript.FRESH_AFTER_STAMINA_1, 0.1, 1, 0.01, 2, true),
		_knob("fresh_after_stamina_20", GROUP_FITNESS, "Работоспособность к концу матча: выносливость 20", "Высокая выносливость. Выше — дольше играет без сильной усталости. Значение должно быть не ниже, чем у обычного игрока.", MatchTypesScript.FRESH_AFTER_STAMINA_20, 0.3, 1, 0.01, 2, true),
		_knob("recovery_share_1", GROUP_FITNESS, "Восстановление за день: характеристика 1", "Слабое восстановление. Больше — быстрее восполняется недостающая готовность; меньше — дольше нужен отдых.", MatchTypesScript.RECOVERY_SHARE_1, 0.05, 0.6, 0.01, 2, true),
		_knob("recovery_share_20", GROUP_FITNESS, "Восстановление за день: характеристика 20", "Сильное восстановление. Даже высокий показатель не обязан возвращать готовность к 100 за один день. Значение должно быть не ниже, чем у обычного игрока.", MatchTypesScript.RECOVERY_SHARE_20, 0.15, 0.95, 0.01, 2, true),
		_knob("lineup_rest_below", GROUP_LINEUP, "Готовность, ниже которой нужен отдых", "Ниже 82 из 100 тренер сильнее предпочитает свежего конкурента на той же позиции. Больше — чаще меняется стартовый состав, меньше — чаще выходят основные игроки.", MatchTypesScript.LINEUP_REST_BELOW, 50, 95, 1, 0, false),
		_knob("rotation_fatigue_weight", GROUP_LINEUP, "Насколько тренер учитывает усталость при выборе старта", "100% — обычная ротация по готовности и качеству. Больше — чаще стартуют свежие запасные; 0% — готовность не учитывается при выборе, но продолжает влиять на игру.", 1.0, 0, 2.5, 0.05, 2, true),
		_knob("subs_max", GROUP_LINEUP, "Максимум замен на команду", "Предел на весь матч, включая дополнительное время. 5 — до пяти замен. 0 запрещает все замены, в том числе при травме. Это предел, а не обязанность выпустить слабую скамейку.", 5.0, 0, 5, 1, 0, false),
		_knob("subs_first_minute", GROUP_LINEUP, "С какой минуты делать плановые замены", "25 — тренер начинает освежать состав со второго тайма. Меньше — раньше, больше — позже. Проверка идёт раз в 5 минут; травмы и экстренная замена вратаря не ждут этой минуты.", 25.0, 10, 40, 5, 0, false),
		_knob("subs_freshness_threshold", GROUP_LINEUP, "Работоспособность, при которой искать замену", "При 94% тренер рассматривает замену, когда игрок потерял хотя бы 6% работоспособности. Выше — раньше и чаще. Замена произойдёт только при подходящем запасном.", 0.94, 0.7, 1, 0.01, 2, true),
		_knob("subs_min_gain", GROUP_LINEUP, "Минимальная ожидаемая польза замены", "2% — запасной должен быть полезнее минимум на 2% в среднем до конца матча, с учётом дальнейшей усталости. Меньше — охотнее использует скамейку; больше — чаще сохраняет основу.", 0.02, 0, 0.2, 0.01, 2, true),
		_knob("subs_min_quality", GROUP_LINEUP, "Минимальное качество запасного", "85% — запасной должен сохранять хотя бы 85% полезности заменяемого по навыкам и позиции без усталости. Ниже — глубже ротация, но возможнее ослабление команды. Выше — строже отбор.", 0.85, 0.5, 1, 0.01, 2, true),
		_knob("subs_reserve_until", GROUP_LINEUP, "До какой минуты беречь последнюю замену", "40 — до этой минуты тренер сохраняет одну замену на случай травмы. После может потратить её на полезное усиление. Больше — дольше держит резерв.", 40.0, 25, 50, 5, 0, false),
		_knob("condition_select_floor", GROUP_LINEUP, "Оценка игрока при готовности 0", "32% — настолько низко тренер оценивает измотанного игрока при выборе старта, ещё до дополнительного штрафа ниже порога отдыха. Меньше — охотнее даёт отдых. Силу на поле настраивают отдельно.", MatchTypesScript.CONDITION_SELECT_FLOOR, 0.1, 0.9, 0.01, 2, true),
	]
	var advanced := ["set_piece_share", "penalty_per_phase", "penalty_conversion_base", "yellow_per_phase", "red_direct_share", "injury_per_phase", "condition_play_floor", "condition_after_stamina_1", "condition_after_stamina_20", "fresh_after_stamina_1", "fresh_after_stamina_20", "recovery_share_1", "recovery_share_20", "condition_select_floor"]
	for knob in knobs:
		knob["advanced"] = str(knob.key) in advanced
		if knob.key in ["chances_per_phase","chance_create_base","shot_on_target_base","shot_conversion_base","penalty_conversion_base"]:
			knob["display_scale"] = 1.0 / float(knob.default)
			knob["percent"] = true
			knob["decimals"] = 2
		if knob.key in ["subs_first_minute", "subs_reserve_until"]:
			knob["suffix"] = " мин"
		if knob.key == "recovery_idle_factor":
			knob["suffix"] = "×"
	return knobs

static func knob_by_key(key: String) -> Dictionary:
	_ensure_schema_index()
	var row: Variant = _schema_by_key.get(key, null)
	if typeof(row) == TYPE_DICTIONARY:
		return row
	return {}


## Explain contradictory editor values before saving; old files still load intact.
static func validation_error(values: Dictionary) -> String:
	for prefix in ["condition_after_stamina_", "fresh_after_stamina_", "recovery_share_"]:
		if float(values[prefix + "1"]) > float(values[prefix + "10"]) or float(values[prefix + "10"]) > float(values[prefix + "20"]):
			return "Высокая характеристика должна помогать: значения для 1, 10 и 20 должны идти по возрастанию. Проверьте раздел «Выносливость»."
	if float(values.subs_reserve_until) < float(values.subs_first_minute):
		return "Последнюю замену нужно беречь хотя бы до начала плановых замен. Проверьте минуты в разделе «Ротация и замены»."
	return ""


static func default_values() -> Dictionary:
	var out := {}
	for knob in schema():
		out[str(knob["key"])] = float(knob["default"])
	return out


static func snapshot() -> Dictionary:
	_ensure_loaded()
	return _values.duplicate()


## Cached once per configuration change, rather than hashing for every phase.
static func fingerprint() -> String:
	_ensure_loaded()
	if _fingerprint.is_empty():
		_fingerprint = JSON.stringify(_values).sha256_text()
	return _fingerprint


static func get_f(key: String) -> float:
	_ensure_loaded()
	if _values.has(key):
		return float(_values[key])
	var spec := knob_by_key(key)
	if spec.is_empty():
		return 0.0
	return float(spec.get("default", 0.0))


## Linear between attribute 1, 10 and 20. Used by stamina and recovery curves.
static func lerp_three(attr: int, value_1: float, value_10: float, value_20: float) -> float:
	var a := clampf(float(attr), 1.0, 20.0)
	if a <= 10.0:
		return lerpf(value_1, value_10, (a - 1.0) / 9.0)
	return lerpf(value_10, value_20, (a - 10.0) / 10.0)


static func curve_attr(attr: int, key_1: String, key_10: String, key_20: String) -> float:
	_ensure_loaded()
	var key := key_1 + "|" + key_10 + "|" + key_20
	if not _curve_tables.has(key):
		var table := PackedFloat64Array()
		var low := get_f(key_1)
		var middle := get_f(key_10)
		var high := get_f(key_20)
		for value in 21:
			table.append(lerp_three(value, low, middle, high))
		_curve_tables[key] = table
	return float(_curve_tables[key][clampi(attr, 1, 20)])


static func condition_play_mult(condition: int) -> float:
	_ensure_loaded()
	if _play_table.is_empty():
		_build_condition_tables()
	return _play_table[MatchTypesScript.clamp_condition(condition)]


## Exactly the same equations as the editor knobs, evaluated once per 0–100 value.
static func _build_condition_tables() -> void:
	var maxv := float(MatchTypesScript.CONDITION_MAX)
	var play_floor := clampf(get_f("condition_play_floor"), 0.0, 1.0)
	var select_floor := clampf(get_f("condition_select_floor"), 0.0, 1.0)
	var rest := clampf(get_f("lineup_rest_below"), 1.0, maxv)
	var weight := get_f("rotation_fatigue_weight")
	for value in MatchTypesScript.CONDITION_MAX + 1:
		var c := float(value)
		var scaled := clampf(c / maxv, 0.0, 1.0)
		_play_table.append(play_floor + (1.0 - play_floor) * scaled)
		var linear := select_floor + (1.0 - select_floor) * (c / maxv)
		_select_table.append(pow(linear if c >= rest else linear * (c / rest), weight))


static func condition_select_mult(condition: int) -> float:
	_ensure_loaded()
	if _select_table.is_empty():
		_build_condition_tables()
	return _select_table[MatchTypesScript.clamp_condition(condition)]


static func _clear_derived_tables() -> void:
	_curve_tables.clear()
	_play_table = PackedFloat64Array()
	_select_table = PackedFloat64Array()


static func editor_values() -> Dictionary:
	return snapshot()


static func apply_values(values: Dictionary, persist: bool) -> Dictionary:
	var next := default_values()
	for key in next.keys():
		if values.has(key):
			next[key] = _clamp_knob(knob_by_key(str(key)), float(values[key]))
	_values = next
	_clear_derived_tables()
	_fingerprint = ""
	_loaded = true
	if not persist:
		return {"ok": true, "error": ""}
	var err := _save_to_disk()
	if err != OK:
		return {"ok": false, "error": "Не удалось сохранить файл настроек."}
	return {"ok": true, "error": ""}


static func reset_to_defaults(persist: bool = false) -> Dictionary:
	return apply_values(default_values(), persist)


static func unload() -> void:
	_clear_derived_tables()
	_loaded = false
	_values = {}
	_fingerprint = ""


static func format_value(knob: Dictionary, value: float) -> String:
	value *= float(knob.get("display_scale", 1.0))
	if bool(knob.get("percent", false)):
		var shown := maxi(int(knob.get("decimals", 2)) - 2, 0)
		return ("%." + str(shown) + "f%%") % (value * 100.0)
	var decimals := int(knob.get("decimals", 2))
	var text := ("%." + str(decimals) + "f") % value
	var suffix := str(knob.get("suffix", ""))
	if suffix.is_empty():
		return text
	return text + suffix


static func _ensure_schema_index() -> void:
	if not _schema_by_key.is_empty():
		return
	for knob in schema():
		_schema_by_key[str(knob["key"])] = knob


static func _clamp_knob(spec: Dictionary, value: float) -> float:
	if spec.is_empty():
		return value
	var lo := float(spec.get("min", value))
	var hi := float(spec.get("max", value))
	var step := float(spec.get("step", 0.0))
	var clamped := clampf(value, lo, hi)
	if step > 0.0:
		clamped = lo + round((clamped - lo) / step) * step
		clamped = clampf(clamped, lo, hi)
	var decimals := int(spec.get("decimals", 3))
	var snap := pow(10.0, -float(maxi(decimals, 0)))
	return snappedf(clamped, snap)


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _load_from_disk():
		_values = default_values()


static func _load_from_disk() -> bool:
	if not FileAccess.file_exists(config_path):
		return false
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("MatchSimulationConfig: invalid JSON in %s, using defaults" % config_path)
		return false
	var data: Dictionary = parsed
	var raw: Variant = data.get("values", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return false
	_values = default_values()
	for key in _values.keys():
		# One-time stamina rebalance; preserve all unrelated user settings.
		if int(data.get("version", 0)) < 8 and (str(key).begins_with("condition_after_stamina_") or str(key).begins_with("fresh_after_stamina_")):
			continue
		if int(data.get("version", 0)) < 7 and str(key) in ["chances_per_phase", "chance_create_base", "shot_on_target_base", "shot_conversion_base", "duel_skill_influence"]:
			continue
		if (raw as Dictionary).has(key):
			_values[key] = _clamp_knob(knob_by_key(str(key)), float((raw as Dictionary)[key]))
	return true


static func _save_to_disk() -> Error:
	var dir_path := config_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mkdir_err != OK:
			return mkdir_err
	var payload := {"version": CONFIG_VERSION, "values": snapshot()}
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_OPEN
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


static func _knob(
	key: String,
	group: String,
	label: String,
	hint: String,
	default_value: float,
	min_value: float,
	max_value: float,
	step: float,
	decimals: int,
	percent: bool
) -> Dictionary:
	return {
		"key": key,
		"group": group,
		"label": label,
		"hint": hint,
		"default": default_value,
		"min": min_value,
		"max": max_value,
		"step": step,
		"decimals": decimals,
		"percent": percent,
		"suffix": "",
	}
