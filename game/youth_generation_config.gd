class_name YouthGenerationConfig
extends RefCounted
## Global youth-generation knobs. Balance here — do not scatter magic numbers.


const YOUTH_TALENT_MIN := 0
const YOUTH_TALENT_MAX := 100
const YOUTH_TALENT_DEFAULT := 50

## Inclusive bands for the country editor slider.
const YOUTH_TALENT_GRADES := [
	{"min": 0, "max": 19, "label": "Слабый", "short": "Слабый"},
	{"min": 20, "max": 39, "label": "Ниже среднего", "short": "Ниже ср."},
	{"min": 40, "max": 59, "label": "Средний", "short": "Средний"},
	{"min": 60, "max": 74, "label": "Сильный", "short": "Сильный"},
	{"min": 75, "max": 89, "label": "Очень сильный", "short": "Оч. сильный"},
	{"min": 90, "max": 100, "label": "Элита", "short": "Элита"},
]

const YOUTH_SLOTS_MIN := 5
const YOUTH_SLOTS_MAX := 7

const MIN_PA := 20
const MAX_PA := 100

const DEFAULT_CONFIG_PATH := "user://config/youth_generation.json"
const CONFIG_VERSION := 1
const WEIGHT_EPS := 0.001

## Default percent weights (sum 100). Runtime copy is loaded/saved via get_pa_buckets().
const PA_BUCKETS := [
	{"bucket_key": "r95_100", "rating_min": 95, "rating_max": 100, "weight_pct": 0.02, "hint": "Мировая звезда"},
	{"bucket_key": "r90_94", "rating_min": 90, "rating_max": 94, "weight_pct": 0.06, "hint": "Элита"},
	{"bucket_key": "r85_89", "rating_min": 85, "rating_max": 89, "weight_pct": 0.60, "hint": "Звезда"},
	{"bucket_key": "r80_84", "rating_min": 80, "rating_max": 84, "weight_pct": 2.20, "hint": "Топ"},
	{"bucket_key": "r70_79", "rating_min": 70, "rating_max": 79, "weight_pct": 22.00, "hint": "Сильный"},
	{"bucket_key": "r60_69", "rating_min": 60, "rating_max": 69, "weight_pct": 44.00, "hint": "Средний+"},
	{"bucket_key": "r20_59", "rating_min": 20, "rating_max": 59, "weight_pct": 31.12, "hint": "Обычный"},
]

## Fixed potential groups. A talent row is the chance of each group.
## Stored in tenths of a percent: 40 means 4%, 5 means 0.5%. Each row sums to 1000.
const BIRTH_BANDS := [
	[40, 49],
	[50, 59],
	[60, 69],
	[70, 79],
	[80, 89],
	[90, 100],
]

## Index is talent 0..100. Talent 0 matches talent 1. Six values, same order as BIRTH_BANDS.
const TALENT_BIRTH_WEIGHTS := [
	[760, 200, 35, 5, 0, 0], # 0
	[760, 200, 35, 5, 0, 0], # 1
	[738, 214, 42, 6, 0, 0], # 2
	[716, 229, 48, 7, 0, 0], # 3
	[694, 243, 55, 8, 0, 0], # 4
	[671, 258, 62, 9, 0, 0], # 5
	[649, 272, 68, 10, 1, 0], # 6
	[626, 287, 75, 11, 1, 0], # 7
	[604, 301, 82, 12, 1, 0], # 8
	[582, 316, 88, 13, 1, 0], # 9
	[560, 330, 95, 14, 1, 0], # 10
	[547, 333, 102, 17, 1, 0], # 11
	[534, 336, 109, 19, 2, 0], # 12
	[521, 339, 116, 22, 2, 0], # 13
	[508, 342, 123, 25, 2, 0], # 14
	[495, 345, 130, 28, 2, 0], # 15
	[482, 348, 137, 30, 3, 0], # 16
	[469, 351, 144, 33, 3, 0], # 17
	[456, 354, 151, 36, 3, 0], # 18
	[443, 357, 158, 38, 4, 0], # 19
	[430, 360, 165, 41, 4, 0], # 20
	[420, 360, 172, 44, 4, 0], # 21
	[410, 360, 178, 47, 5, 0], # 22
	[400, 360, 185, 50, 5, 0], # 23
	[390, 360, 191, 53, 6, 0], # 24
	[380, 360, 198, 56, 6, 0], # 25
	[370, 360, 204, 60, 6, 0], # 26
	[360, 360, 210, 63, 7, 0], # 27
	[350, 360, 217, 66, 7, 0], # 28
	[340, 359, 224, 69, 8, 0], # 29
	[330, 360, 230, 72, 8, 0], # 30
	[322, 359, 235, 75, 9, 0], # 31
	[314, 358, 240, 79, 9, 0], # 32
	[306, 357, 245, 82, 10, 0], # 33
	[298, 356, 250, 86, 10, 0], # 34
	[290, 355, 255, 89, 11, 0], # 35
	[282, 353, 260, 92, 12, 1], # 36
	[274, 353, 265, 95, 12, 1], # 37
	[266, 352, 270, 98, 13, 1], # 38
	[258, 351, 275, 102, 13, 1], # 39
	[250, 350, 280, 105, 14, 1], # 40
	[243, 348, 283, 110, 15, 1], # 41
	[236, 346, 286, 115, 16, 1], # 42
	[229, 344, 289, 120, 16, 2], # 43
	[222, 342, 292, 125, 17, 2], # 44
	[215, 340, 295, 130, 18, 2], # 45
	[208, 338, 298, 135, 19, 2], # 46
	[201, 336, 301, 140, 20, 2], # 47
	[194, 334, 304, 145, 20, 3], # 48
	[187, 332, 307, 150, 21, 3], # 49
	[180, 330, 310, 155, 22, 3], # 50
	[175, 325, 314, 161, 22, 3], # 51
	[170, 320, 318, 166, 23, 3], # 52
	[165, 315, 321, 172, 24, 3], # 53
	[160, 310, 326, 177, 24, 3], # 54
	[155, 305, 330, 183, 24, 3], # 55
	[150, 300, 334, 188, 25, 3], # 56
	[145, 295, 337, 194, 26, 3], # 57
	[140, 290, 342, 199, 26, 3], # 58
	[135, 285, 346, 205, 26, 3], # 59
	[130, 280, 350, 210, 27, 3], # 60
	[126, 275, 353, 216, 27, 3], # 61
	[122, 270, 356, 221, 28, 3], # 62
	[118, 265, 359, 227, 28, 3], # 63
	[114, 260, 362, 233, 28, 3], # 64
	[110, 255, 365, 239, 28, 3], # 65
	[106, 250, 368, 244, 29, 3], # 66
	[102, 245, 371, 250, 29, 3], # 67
	[98, 240, 374, 256, 29, 3], # 68
	[94, 235, 377, 261, 30, 3], # 69
	[90, 230, 380, 267, 30, 3], # 70
	[86, 224, 382, 275, 30, 3], # 71
	[82, 218, 384, 282, 31, 3], # 72
	[78, 212, 386, 290, 31, 3], # 73
	[74, 206, 388, 297, 32, 3], # 74
	[70, 200, 390, 305, 32, 3], # 75
	[66, 194, 392, 313, 32, 3], # 76
	[62, 188, 394, 320, 33, 3], # 77
	[58, 182, 396, 327, 33, 4], # 78
	[54, 176, 397, 335, 34, 4], # 79
	[50, 170, 400, 342, 34, 4], # 80
	[48, 165, 400, 349, 34, 4], # 81
	[46, 160, 400, 355, 35, 4], # 82
	[44, 155, 400, 362, 35, 4], # 83
	[42, 150, 400, 368, 36, 4], # 84
	[40, 145, 400, 375, 36, 4], # 85
	[38, 142, 396, 384, 36, 4], # 86
	[36, 139, 392, 392, 37, 4], # 87
	[34, 136, 388, 401, 37, 4], # 88
	[32, 133, 384, 409, 38, 4], # 89
	[30, 130, 380, 418, 38, 4], # 90
	[29, 127, 378, 424, 38, 4], # 91
	[28, 124, 376, 430, 38, 4], # 92
	[27, 121, 374, 435, 39, 4], # 93
	[26, 118, 372, 441, 39, 4], # 94
	[25, 115, 370, 447, 39, 4], # 95
	[24, 112, 368, 452, 39, 5], # 96
	[23, 109, 366, 458, 39, 5], # 97
	[22, 106, 364, 463, 40, 5], # 98
	[21, 103, 362, 469, 40, 5], # 99
	[20, 100, 360, 475, 40, 5], # 100
]

const YOUTH_AGES := [15, 16, 17]
const YOUTH_AGE_WEIGHTS := [0.25, 0.45, 0.30]

## Inclusive readiness bands before academy / noise. Keys are age.
const AGE_READINESS := {
	15: [0.40, 0.45],
	16: [0.44, 0.50],
	17: [0.48, 0.55],
}

const ACADEMY_CA_WEIGHT := 0.14
const CA_NOISE := 0.03
const CA_READINESS_MIN := 0.28
const CA_READINESS_MAX := 0.72

const DEVELOPMENT_FACTOR_MIN := 0.80
const DEVELOPMENT_FACTOR_MAX := 1.05
const TRAINING_GROWTH_FLOOR := 0.70
const TRAINING_GROWTH_SPAN := 0.60

## Expected rating of the legacy default country table (used to map → 500).
const LEGACY_DEFAULT_EXPECTED_PA := 62.605
const LEGACY_TALENT_SCALE := 20.0

const DEFAULT_BIRTH_CONFIG_PATH := "user://config/youth_talent_birth.json"
const BIRTH_WEIGHT_TOTAL := 1000

static var config_path := DEFAULT_CONFIG_PATH
static var birth_config_path := DEFAULT_BIRTH_CONFIG_PATH
static var _loaded := false
static var _runtime_pa_buckets: Array = []
static var _birth_loaded := false
static var _runtime_birth: Array = []


static func clamp_youth_talent(value: int) -> int:
	return clampi(value, YOUTH_TALENT_MIN, YOUTH_TALENT_MAX)


static func youth_talent_grade(value: int) -> Dictionary:
	var talent := clamp_youth_talent(value)
	var fallback: Dictionary = YOUTH_TALENT_GRADES[YOUTH_TALENT_GRADES.size() - 1]
	for band in YOUTH_TALENT_GRADES:
		if talent >= int(band["min"]) and talent <= int(band["max"]):
			return band
	return fallback


static func youth_talent_grade_label(value: int) -> String:
	return str(youth_talent_grade(value).get("label", ""))


static func birth_weights(youth_talent: int) -> Array:
	_ensure_birth_loaded()
	return _runtime_birth[clamp_youth_talent(youth_talent)]


static func default_birth_weights() -> Array:
	return _copy_birth_rows(TALENT_BIRTH_WEIGHTS)


static func editor_birth_weights() -> Array:
	_ensure_birth_loaded()
	return _copy_birth_rows(_runtime_birth)


static func apply_birth_weights(rows: Array) -> Dictionary:
	var next := _validated_birth_rows(rows)
	if next.is_empty():
		return {"ok": false, "error": "У каждого таланта 0–100 сумма шести процентов должна быть 100%."}
	_runtime_birth = next
	_birth_loaded = true
	var err := _save_birth_to_disk()
	if err != OK:
		return {"ok": false, "error": "Не удалось сохранить таблицу талантов."}
	return {"ok": true, "error": ""}


static func reset_birth_to_defaults(persist: bool = false) -> Dictionary:
	_runtime_birth = default_birth_weights()
	_birth_loaded = true
	if not persist:
		return {"ok": true, "error": ""}
	var err := _save_birth_to_disk()
	if err != OK:
		return {"ok": false, "error": "Не удалось сохранить таблицу талантов."}
	return {"ok": true, "error": ""}


static func unload_birth() -> void:
	_birth_loaded = false
	_runtime_birth = []


static func _ensure_birth_loaded() -> void:
	if _birth_loaded:
		return
	_birth_loaded = true
	if not _load_birth_from_disk():
		_runtime_birth = default_birth_weights()


static func _validated_birth_rows(rows: Array) -> Array:
	if rows.size() != TALENT_BIRTH_WEIGHTS.size():
		return []
	var out: Array = []
	for row in rows:
		if typeof(row) != TYPE_ARRAY or (row as Array).size() != BIRTH_BANDS.size():
			return []
		var copy: Array = []
		var total := 0
		for weight in row:
			var tenths := int(weight)
			if tenths < 0:
				return []
			copy.append(tenths)
			total += tenths
		if total != BIRTH_WEIGHT_TOTAL:
			return []
		out.append(copy)
	return out


static func _copy_birth_rows(rows: Array) -> Array:
	var out: Array = []
	for row in rows:
		var copy: Array = []
		for weight in row:
			copy.append(int(weight))
		out.append(copy)
	return out


static func _load_birth_from_disk() -> bool:
	if not FileAccess.file_exists(birth_config_path):
		return false
	var file := FileAccess.open(birth_config_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = parsed
	var rows: Variant = data.get("rows", [])
	if typeof(rows) != TYPE_ARRAY:
		return false
	var next := _validated_birth_rows(rows)
	if next.is_empty():
		return false
	_runtime_birth = next
	return true


static func _save_birth_to_disk() -> Error:
	var dir_path := birth_config_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mkdir_err != OK:
			return mkdir_err
	var file := FileAccess.open(birth_config_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_OPEN
	file.store_string(JSON.stringify({"version": 1, "rows": _runtime_birth}, "\t"))
	file.close()
	return OK


static func roll_birth_potential(youth_talent: int, rng: RandomNumberGenerator) -> int:
	var weights: Array = birth_weights(youth_talent)
	var total := 0
	for weight in weights:
		total += int(weight)
	if total <= 0:
		return MIN_PA
	var roll := rng.randi_range(1, total)
	var acc := 0
	var index := weights.size() - 1
	for i in weights.size():
		acc += int(weights[i])
		if roll <= acc:
			index = i
			break
	var band: Array = BIRTH_BANDS[index]
	return rng.randi_range(int(band[0]), int(band[1]))


static func pa_tier_index(potential_ability: int) -> int:
	var buckets := get_pa_buckets()
	for i in buckets.size():
		var bucket: Dictionary = buckets[i]
		if potential_ability >= int(bucket["rating_min"]):
			return i
	return buckets.size() - 1


static func pa_bucket_key(bucket: Dictionary) -> String:
	var key := str(bucket.get("bucket_key", ""))
	if not key.is_empty():
		return key
	return "r%d_%d" % [int(bucket.get("rating_min", 0)), int(bucket.get("rating_max", 0))]


static func default_pa_buckets() -> Array:
	var out: Array = []
	for bucket in PA_BUCKETS:
		out.append((bucket as Dictionary).duplicate(true))
	return out


static func get_pa_buckets() -> Array:
	_ensure_loaded()
	return _runtime_pa_buckets


static func editor_pa_buckets() -> Array:
	return _to_editor_buckets(get_pa_buckets())


static func default_editor_pa_buckets() -> Array:
	return _to_editor_buckets(default_pa_buckets())


static func apply_pa_weights(weights: Dictionary) -> Dictionary:
	var next := _merge_weights(default_pa_buckets(), weights)
	var total := _weight_total(next)
	if absf(total - 100.0) >= WEIGHT_EPS:
		return {"ok": false, "error": "Сумма должна быть 100%% (сейчас %.2f%%)." % total}
	_runtime_pa_buckets = next
	_loaded = true
	var err := _save_to_disk()
	if err != OK:
		return {"ok": false, "error": "Не удалось сохранить файл настроек."}
	return {"ok": true, "error": ""}


static func reset_to_defaults(persist: bool = false) -> Dictionary:
	_runtime_pa_buckets = default_pa_buckets()
	_loaded = true
	if not persist:
		return {"ok": true, "error": ""}
	var err := _save_to_disk()
	if err != OK:
		return {"ok": false, "error": "Не удалось сохранить файл настроек."}
	return {"ok": true, "error": ""}


static func unload() -> void:
	_loaded = false
	_runtime_pa_buckets = []


static func _to_editor_buckets(buckets: Array) -> Array:
	var out: Array = []
	for bucket in buckets:
		var row: Dictionary = bucket.duplicate(true)
		var lo := int(row.get("rating_min", MIN_PA))
		var hi := int(row.get("rating_max", MAX_PA))
		row["bucket_key"] = pa_bucket_key(row)
		row["range_label"] = "%d–%d" % [lo, hi]
		out.append(row)
	return out


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not _load_from_disk():
		_runtime_pa_buckets = default_pa_buckets()


static func _load_from_disk() -> bool:
	if not FileAccess.file_exists(config_path):
		return false
	var file := FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("YouthGenerationConfig: invalid JSON in %s, using defaults" % config_path)
		return false
	var data: Dictionary = parsed
	var weights: Variant = data.get("pa_weights", {})
	if typeof(weights) != TYPE_DICTIONARY:
		return false
	var next := _merge_weights(default_pa_buckets(), weights)
	var total := _weight_total(next)
	if absf(total - 100.0) >= WEIGHT_EPS:
		push_warning(
			"YouthGenerationConfig: PA weights in %s sum to %.2f, using defaults" % [config_path, total]
		)
		return false
	_runtime_pa_buckets = next
	return true


static func _save_to_disk() -> Error:
	var dir_path := config_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var mkdir_err := DirAccess.make_dir_recursive_absolute(dir_path)
		if mkdir_err != OK:
			return mkdir_err
	var weights := {}
	for bucket in _runtime_pa_buckets:
		weights[pa_bucket_key(bucket)] = float(bucket.get("weight_pct", 0.0))
	var payload := {"version": CONFIG_VERSION, "pa_weights": weights}
	var file := FileAccess.open(config_path, FileAccess.WRITE)
	if file == null:
		return ERR_CANT_OPEN
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


static func _merge_weights(buckets: Array, weights: Dictionary) -> Array:
	var out: Array = []
	for bucket in buckets:
		var row: Dictionary = (bucket as Dictionary).duplicate(true)
		var key := pa_bucket_key(row)
		if weights.has(key):
			row["weight_pct"] = snappedf(clampf(float(weights[key]), 0.0, 100.0), 0.01)
		out.append(row)
	return out


static func _weight_total(buckets: Array) -> float:
	var total := 0.0
	for bucket in buckets:
		total += float(bucket.get("weight_pct", 0.0))
	return snappedf(total, 0.01)


static func legacy_expected_to_talent(expected_pa: float) -> int:
	var raw := 500.0 + (expected_pa - LEGACY_DEFAULT_EXPECTED_PA) * LEGACY_TALENT_SCALE
	return clampi(int(round(raw)), 0, 1000)


static func talent_from_legacy_buckets(buckets: Array) -> int:
	var total_w := 0.0
	var expected := 0.0
	for bucket in buckets:
		var weight := float(bucket.get("weight_pct", 0.0))
		if weight <= 0.0:
			continue
		var lo := int(bucket.get("rating_min", MIN_PA))
		var hi := int(bucket.get("rating_max", lo))
		expected += weight * (float(lo + hi) * 0.5)
		total_w += weight
	if total_w <= 0.001:
		return YOUTH_TALENT_DEFAULT
	return legacy_expected_to_talent(expected / total_w)
