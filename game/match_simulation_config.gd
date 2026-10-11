class_name MatchSimulationConfig
extends RefCounted
## Live match-engine knobs. Defaults live in MatchTypes; this file is the
## runtime overlay saved to user://config/match_simulation.json.


const MatchTypesScript := preload("res://game/match_types.gd")

const DEFAULT_CONFIG_PATH := "user://config/match_simulation.json"
const CONFIG_VERSION := 3

const GROUP_SCORING := "scoring"
const GROUP_BALANCE := "balance"
const GROUP_DISCIPLINE := "discipline"
const GROUP_FITNESS := "fitness"
const GROUP_RECOVERY := "recovery"
const GROUP_LINEUP := "lineup"

const GROUPS := [
	{
		"id": GROUP_SCORING,
		"title": "Голы и удары",
		"hint": "Это частота, когда соперники в эпизоде равны. Дальше удар решает бьющий против защитника и вратаря.",
	},
	{
		"id": GROUP_BALANCE,
		"title": "Баланс сил",
		"hint": "Разницу в составе и план тренера превращает в удары. Карточка ослабляет команду до конца матча.",
	},
	{
		"id": GROUP_DISCIPLINE,
		"title": "Карточки и травмы",
		"hint": "Базовые частоты до строгости судьи юнита и дисциплины тренера.",
	},
	{
		"id": GROUP_FITNESS,
		"title": "Усталость в матче",
		"hint": "Три точки по Выносливости (1 / 10 / 20). Между ними считается линейно. Ниже значение — сильнее выдыхается.",
	},
	{
		"id": GROUP_RECOVERY,
		"title": "Восстановление между турами",
		"hint": "Три точки по Восстановлению (1 / 10 / 20). Игрок закрывает долю недобора до 100, а не прыгает к полной шкале.",
	},
	{
		"id": GROUP_LINEUP,
		"title": "Заявка на матч",
		"hint": "Усталость должна сажать игрока, а не только снижать его силу. Ниже ползунки — тренер охотнее ставит свежего запасного.",
	},
]

static var config_path := DEFAULT_CONFIG_PATH
static var _loaded := false
static var _values: Dictionary = {}
static var _schema_by_key: Dictionary = {}


static func schema() -> Array:
	return [
		{
			"key": "chances_per_phase",
			"group": GROUP_SCORING,
			"label": "Шансы за фазу",
			"hint": "Сколько атак в среднем разыгрывается за 5 минут. Больше — живее и результативнее.",
			"default": MatchTypesScript.CHANCES_PER_PHASE,
			"min": 0.40,
			"max": 2.40,
			"step": 0.02,
			"decimals": 2,
			"percent": false,
			"suffix": "",
		},
		{
			"key": "chance_create_base",
			"group": GROUP_SCORING,
			"label": "Шанс создать удар",
			"hint": "Доля атак, которые становятся ударом, когда создающий и защитник равны.",
			"default": MatchTypesScript.CHANCE_CREATE_BASE,
			"min": 0.40,
			"max": 0.95,
			"step": 0.01,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "shot_on_target_base",
			"group": GROUP_SCORING,
			"label": "Удар в створ",
			"hint": "Доля ударов в створ, когда бьющий средний. Сильный удар поднимает долю, слабый роняет.",
			"default": MatchTypesScript.SHOT_ON_TARGET_BASE,
			"min": 0.35,
			"max": 0.85,
			"step": 0.01,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "shot_conversion_base",
			"group": GROUP_SCORING,
			"label": "Реализация удара в створ",
			"hint": "Доля голов с удара в створ, когда бьющий и вратарь равны. Разрыв в их характеристиках решает эпизод.",
			"default": MatchTypesScript.SHOT_CONVERSION_BASE,
			"min": 0.10,
			"max": 0.55,
			"step": 0.01,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "set_piece_share",
			"group": GROUP_SCORING,
			"label": "Доля стандартов",
			"hint": "Какая часть шансов разыгрывается со стандартов (угловые, штрафные, навесы).",
			"default": MatchTypesScript.SET_PIECE_SHARE,
			"min": 0.00,
			"max": 0.50,
			"step": 0.01,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "penalty_per_phase",
			"group": GROUP_SCORING,
			"label": "Пенальти за фазу",
			"hint": "Ожидаемое число пенальти за 5 минут. 0.013 ≈ одно пенальти примерно в 8 матчах.",
			"default": MatchTypesScript.PENALTY_PER_PHASE,
			"min": 0.000,
			"max": 0.050,
			"step": 0.001,
			"decimals": 3,
			"percent": false,
			"suffix": "",
		},
		{
			"key": "penalty_conversion_base",
			"group": GROUP_SCORING,
			"label": "Реализация пенальти",
			"hint": "Базовая вероятность гола с точки, до навыка бьющего и вратаря.",
			"default": MatchTypesScript.PENALTY_CONVERSION_BASE,
			"min": 0.50,
			"max": 0.95,
			"step": 0.01,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "home_advantage",
			"group": GROUP_BALANCE,
			"label": "Домашнее преимущество",
			"hint": "Надбавка к ожидаемым шансам хозяев на своём поле.",
			"default": MatchTypesScript.HOME_ADVANTAGE,
			"min": 0.00,
			"max": 0.25,
			"step": 0.005,
			"decimals": 3,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "home_reputation_bonus",
			"group": GROUP_BALANCE,
			"label": "Бонус репутации хозяев",
			"hint": "Дополнительная надбавка от репутации клуба (0 при нуле, максимум при 1000).",
			"default": MatchTypesScript.HOME_REPUTATION_BONUS,
			"min": 0.00,
			"max": 0.12,
			"step": 0.005,
			"decimals": 3,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "team_form_spread",
			"group": GROUP_BALANCE,
			"label": "Разброс формы дня",
			"hint": "Насколько стабильность игрока качает один эпизод. Состав и тренера это не перебивает.",
			"default": MatchTypesScript.TEAM_FORM_SPREAD,
			"min": 0.00,
			"max": 0.30,
			"step": 0.01,
			"decimals": 2,
			"percent": false,
			"suffix": "",
		},
		{
			"key": "quality_exponent",
			"group": GROUP_BALANCE,
			"label": "Экспонента качества",
			"hint": "Как резко разница состава превращается в удары. Выше — сильный состав давит слабый.",
			"default": MatchTypesScript.QUALITY_EXPONENT,
			"min": 0.20,
			"max": 1.20,
			"step": 0.05,
			"decimals": 2,
			"percent": false,
			"suffix": "",
		},
		{
			"key": "man_down_penalty",
			"group": GROUP_BALANCE,
			"label": "Штраф в меньшинстве",
			"hint": "На сколько слабее команда после каждого удаления.",
			"default": MatchTypesScript.MAN_DOWN_PENALTY,
			"min": 0.00,
			"max": 0.40,
			"step": 0.02,
			"decimals": 2,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "yellow_per_phase",
			"group": GROUP_DISCIPLINE,
			"label": "Жёлтые за фазу",
			"hint": "Базовая частота карточек за 5 минут, до строгости судьи и дисциплины тренера.",
			"default": MatchTypesScript.YELLOW_PER_PHASE,
			"min": 0.000,
			"max": 0.400,
			"step": 0.002,
			"decimals": 3,
			"percent": false,
			"suffix": "",
		},
		{
			"key": "red_direct_share",
			"group": GROUP_DISCIPLINE,
			"label": "Доля прямых красных",
			"hint": "Какая часть карточек сразу становится удалением, а не жёлтой.",
			"default": MatchTypesScript.RED_DIRECT_SHARE,
			"min": 0.00,
			"max": 0.15,
			"step": 0.002,
			"decimals": 3,
			"percent": true,
			"suffix": "",
		},
		{
			"key": "injury_per_phase",
			"group": GROUP_DISCIPLINE,
			"label": "Травмы за фазу",
			"hint": "Базовая частота травм за 5 минут. Растёт к концу матча и в доп. время.",
			"default": MatchTypesScript.INJURY_PER_PHASE,
			"min": 0.000,
			"max": 0.080,
			"step": 0.001,
			"decimals": 3,
			"percent": false,
			"suffix": "",
		},
		_knob(
			"condition_after_stamina_1",
			GROUP_FITNESS,
			"Кондиция после матча · вын. 1",
			"Сколько кондиции останется после полных 50 минут, если Выносливость = 1. Старт матча — 100.",
			MatchTypesScript.CONDITION_AFTER_STAMINA_1,
			0.0,
			80.0,
			1.0,
			0,
			false
		),
		_knob(
			"condition_after_stamina_10",
			GROUP_FITNESS,
			"Кондиция после матча · вын. 10",
			"То же при Выносливости 10. Обычный игрок.",
			MatchTypesScript.CONDITION_AFTER_STAMINA_10,
			0.0,
			90.0,
			1.0,
			0,
			false
		),
		_knob(
			"condition_after_stamina_20",
			GROUP_FITNESS,
			"Кондиция после матча · вын. 20",
			"То же при Выносливости 20. Должно быть выше, чем у 10.",
			MatchTypesScript.CONDITION_AFTER_STAMINA_20,
			10.0,
			95.0,
			1.0,
			0,
			false
		),
		_knob(
			"fresh_after_stamina_1",
			GROUP_FITNESS,
			"Свежесть к концу матча · вын. 1",
			"Какая доля сил на поле останется к 50-й минуте при Выносливости 1. 100% = не устал.",
			MatchTypesScript.FRESH_AFTER_STAMINA_1,
			0.10,
			1.00,
			0.01,
			2,
			true
		),
		_knob(
			"fresh_after_stamina_10",
			GROUP_FITNESS,
			"Свежесть к концу матча · вын. 10",
			"То же при Выносливости 10.",
			MatchTypesScript.FRESH_AFTER_STAMINA_10,
			0.20,
			1.00,
			0.01,
			2,
			true
		),
		_knob(
			"fresh_after_stamina_20",
			GROUP_FITNESS,
			"Свежесть к концу матча · вын. 20",
			"То же при Выносливости 20. Должно быть выше, чем у 10.",
			MatchTypesScript.FRESH_AFTER_STAMINA_20,
			0.30,
			1.00,
			0.01,
			2,
			true
		),
		_knob(
			"condition_play_floor",
			GROUP_FITNESS,
			"Сила при кондиции 0",
			"Во сколько раз слабее играет игрок с пустой батарейкой. 100% = кондиция не влияет. Ниже — усталость бьёт сильнее.",
			MatchTypesScript.CONDITION_FIT_FLOOR,
			0.30,
			1.00,
			0.01,
			2,
			true
		),
		_knob(
			"recovery_share_1",
			GROUP_RECOVERY,
			"Доля восстановления · восст. 1",
			"Какую часть недобора до 100 закрывает за один тур игрок с Восстановлением 1.",
			MatchTypesScript.RECOVERY_SHARE_1,
			0.05,
			0.60,
			0.01,
			2,
			true
		),
		_knob(
			"recovery_share_10",
			GROUP_RECOVERY,
			"Доля восстановления · восст. 10",
			"То же при Восстановлении 10.",
			MatchTypesScript.RECOVERY_SHARE_10,
			0.10,
			0.80,
			0.01,
			2,
			true
		),
		_knob(
			"recovery_share_20",
			GROUP_RECOVERY,
			"Доля восстановления · восст. 20",
			"То же при Восстановлении 20. Даже 20 не обязан возвращать к 100 за один тур.",
			MatchTypesScript.RECOVERY_SHARE_20,
			0.15,
			0.95,
			0.01,
			2,
			true
		),
		_knob(
			"recovery_floor",
			GROUP_RECOVERY,
			"Минимум восстановления за тур",
			"Сколько пунктов кондиции дают всегда, плюс доля недобора. Держит совсем пустых чуть живыми.",
			MatchTypesScript.CONDITION_RECOVERY_FLOOR,
			0.0,
			10.0,
			1.0,
			0,
			false
		),
		_knob(
			"recovery_idle_factor",
			GROUP_RECOVERY,
			"Бонус, если не играл",
			"Во сколько раз быстрее восстанавливается тот, кто в этом туре сидел.",
			MatchTypesScript.CONDITION_IDLE_FACTOR,
			1.00,
			2.00,
			0.05,
			2,
			false
		),
		_knob(
			"condition_select_floor",
			GROUP_LINEUP,
			"Вес уставшего в заявке",
			"Насколько слабым тренер считает игрока с кондицией 0, когда выбирает старт. Ниже — звёзды чаще садятся.",
			MatchTypesScript.CONDITION_SELECT_FLOOR,
			0.10,
			0.90,
			0.01,
			2,
			true
		),
		_knob(
			"lineup_rest_below",
			GROUP_LINEUP,
			"Порог отдыха",
			"Ниже этой кондиции тренер дополнительно штрафует игрока и ставит свежего, если он близко по силе.",
			MatchTypesScript.LINEUP_REST_BELOW,
			50.0,
			95.0,
			1.0,
			0,
			false
		),
	]


static func knob_by_key(key: String) -> Dictionary:
	_ensure_schema_index()
	var row: Variant = _schema_by_key.get(key, null)
	if typeof(row) == TYPE_DICTIONARY:
		return row
	return {}


static func default_values() -> Dictionary:
	var out := {}
	for knob in schema():
		out[str(knob["key"])] = float(knob["default"])
	return out


static func snapshot() -> Dictionary:
	_ensure_loaded()
	return _values.duplicate()


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
	return lerp_three(attr, get_f(key_1), get_f(key_10), get_f(key_20))


static func condition_play_mult(condition: int) -> float:
	var floor_v := clampf(get_f("condition_play_floor"), 0.0, 1.0)
	var scaled := clampf(
		float(MatchTypesScript.clamp_condition(condition)) / float(MatchTypesScript.CONDITION_MAX),
		0.0,
		1.0
	)
	return floor_v + (1.0 - floor_v) * scaled


## Coaches rest people harder than the on-pitch penalty: a star at 70 condition
## should lose the slot to a decent fresh deputy.
static func condition_select_mult(condition: int) -> float:
	var c := float(MatchTypesScript.clamp_condition(condition))
	var maxv := float(MatchTypesScript.CONDITION_MAX)
	var floor_v := clampf(get_f("condition_select_floor"), 0.0, 1.0)
	var rest := clampf(get_f("lineup_rest_below"), 1.0, maxv)
	var linear := floor_v + (1.0 - floor_v) * (c / maxv)
	if c >= rest:
		return linear
	return linear * (c / rest)


static func editor_values() -> Dictionary:
	return snapshot()


static func apply_values(values: Dictionary, persist: bool) -> Dictionary:
	var next := default_values()
	for key in next.keys():
		if values.has(key):
			next[key] = _clamp_knob(knob_by_key(str(key)), float(values[key]))
	_values = next
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
	_loaded = false
	_values = {}


static func format_value(knob: Dictionary, value: float) -> String:
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
