extends RefCounted
## Local settings; separate from saves and match-generation parameters.
const MODE_WEIGHTS := "WEIGHTS"
const MODE_BOUNDED := "BOUNDED"
static var config_path := "user://config/club_attraction.json"
static var _values: Dictionary = {}
static var _loaded := false
static var _revision := 0

static func defaults() -> Dictionary:
	return {"mode": MODE_BOUNDED, "reputation_weight": 50.0, "elo_weight": 50.0,
		"max_effect": 60.0, "confidence_matches": 20.0}

static func normalized(source: Dictionary) -> Dictionary:
	var result := defaults()
	if str(source.get("mode", "")) in [MODE_WEIGHTS, MODE_BOUNDED]: result.mode = str(source.mode)
	for key in ["reputation_weight", "elo_weight", "max_effect", "confidence_matches"]:
		var raw: Variant = source.get(key, result[key])
		if typeof(raw) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(raw)): continue
		result[key] = clampf(roundf(float(raw)), 0.0, 100.0 if key.ends_with("weight") else 1000.0)
	var total := float(result.reputation_weight) + float(result.elo_weight)
	if total <= 0:
		result.reputation_weight = 50.0
		result.elo_weight = 50.0
	else:
		result.elo_weight = roundf(float(result.elo_weight) * 100.0 / total)
		result.reputation_weight = 100.0 - float(result.elo_weight)
	return result

static func _ensure_loaded() -> void:
	if _loaded: return
	_loaded = true
	_values = defaults()
	if FileAccess.file_exists(config_path):
		var payload: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
		if payload is Dictionary and payload.get("values") is Dictionary:
			_values = normalized(payload["values"])
	_revision += 1

static func snapshot() -> Dictionary:
	_ensure_loaded()
	return _values.duplicate()

static func runtime_values() -> Dictionary:
	_ensure_loaded()
	return _values # Internal read-only view for hot recruitment loops.

static func revision() -> int:
	_ensure_loaded()
	return _revision

static func apply_values(source: Dictionary, persist: bool = false) -> Dictionary:
	var next := normalized(source)
	if persist:
		var err := DirAccess.make_dir_recursive_absolute(config_path.get_base_dir())
		if err != OK: return {"ok": false, "error": "Не удалось создать папку настроек."}
		var file := FileAccess.open(config_path, FileAccess.WRITE)
		if file == null: return {"ok": false, "error": "Не удалось сохранить настройки привлекательности."}
		file.store_string(JSON.stringify({"version": 1, "values": next}, "\t"))
		file.flush()
		if file.get_error() != OK: return {"ok": false, "error": "Ошибка записи настроек привлекательности."}
	_values = next
	_loaded = true
	_revision += 1
	return {"ok": true, "error": ""}

static func unload() -> void:
	_loaded = false
	_values = {}
	_revision += 1
