class_name NativeSimulation
extends RefCounted
## Calculation boundary. Game entities, UI and save formats remain in Godot.
## Set FC_SIMULATION_BACKEND=gdscript for a reference run without native calculations.

const API_VERSION := 5
const AttractionConfig = preload("res://game/club_attraction_config.gd")
static var _attraction_revision := -1
static var enabled := OS.get_environment("FC_SIMULATION_BACKEND").to_lower() != "gdscript"
static var _instance: RefCounted
static var _fingerprint := ""
static var _checked := false
static var _announced := false

static func core(sync_knobs: bool = true) -> Variant:
	if not enabled:
		return null
	if _instance == null:
		if _checked:
			return null
		_checked = true
		if not ClassDB.class_exists("FCSimCore"):
			return null
		_instance = ClassDB.instantiate("FCSimCore") as RefCounted
		if not _instance.has_method("api_version") or int(_instance.call("api_version")) != API_VERSION:
			push_warning("Native simulation module needs rebuilding with tools/build_native.ps1")
			_instance = null
			return null
		_instance.call("configure", _configuration())
		_attraction_revision = -1
		sync_knobs = true
	var attraction_revision := AttractionConfig.revision()
	if attraction_revision != _attraction_revision and _instance.has_method("set_attraction_settings"):
		_instance.call("set_attraction_settings", AttractionConfig.snapshot())
		_attraction_revision = attraction_revision
	if sync_knobs:
		var config: Script = load("res://game/match_simulation_config.gd")
		var fingerprint: String = config.fingerprint()
		if fingerprint != _fingerprint:
			_instance.call("set_knobs", config.snapshot())
			_fingerprint = fingerprint
	if not _announced:
		_announced = true
		print("[Simulation] C++ / ", _instance.call("version"))
	return _instance

static func _configuration() -> Dictionary:
	# Load these at runtime to avoid preload cycles between the reference modules.
	var ratings: Dictionary = load("res://game/match_ratings.gd").get_script_constant_map()
	var lineup: Dictionary = load("res://game/lineup_selector.gd").get_script_constant_map()
	var types: Script = load("res://game/player_types.gd")
	var type_constants: Dictionary = types.get_script_constant_map()
	var match_types: Script = load("res://game/match_types.gd")
	var tactics: Script = load("res://game/tactic_types.gd")
	var tactic_constants: Dictionary = tactics.get_script_constant_map()
	var youth: Script = load("res://game/youth_generation_config.gd")
	var nationals: Script = load("res://game/national_teams.gd")
	var squad_min := {}
	var squad_max := {}
	var generation := {}
	var terms := {}
	var fits := {}
	for position in type_constants.POSITIONS:
		squad_min[position] = types.squad_slot_min(position)
		squad_max[position] = types.squad_slot_max(position)
		var groups := {}
		for group in types.attribute_groups_for_position(position):
			groups[group] = types.attribute_keys_for_group(group)
		generation[position] = {
			"groups": groups, "bias": types.generation_bias(position),
			"secondary": types.secondary_terms(position),
		}
		terms[position] = types.ability_terms(position)
		fits[position] = {}
		for other_position in type_constants.POSITIONS:
			fits[position][other_position] = match_types.slot_fit(position, other_position)
	var compatible := {}
	for style in tactic_constants.STYLES:
		compatible[style] = {}
		for formation in tactic_constants.FORMATIONS:
			compatible[style][formation] = tactics.is_compatible(style, formation)
	return {
		"discipline_defaults": load("res://database/repositories/world/discipline_rules.gd").defaults(),
		"settings_version": load("res://game/match_simulation_config.gd").CONFIG_VERSION,
		"compatible": compatible,
		"match_constants": match_types.get_script_constant_map(),
		"action_constants": load("res://game/action_rules.gd").get_script_constant_map(),
		"tactic_constants": tactic_constants,
		"fits": fits,
		"national_quotas": nationals.QUOTAS,
		"national_maxima": PlayerTypes.SQUAD_SLOT_MAX,
		"national_squad_size": nationals.SQUAD_SIZE,
		"reputation_constants": load("res://game/season_reputation.gd").get_script_constant_map(),
		"preview_constants": load("res://game/season_preview.gd").get_script_constant_map(),
		"transfer_flex": load("res://game/transfer_market.gd").POS_FLEX,
		"training_floor": youth.TRAINING_GROWTH_FLOOR,
		"training_span": youth.TRAINING_GROWTH_SPAN,
		"general_profile_ca": load("res://game/player_generator.gd").GENERAL_PROFILE_CA,
		"development_constants": load("res://game/player_development.gd").get_script_constant_map(),
		"market_constants": load("res://game/player_market.gd").get_script_constant_map(),
		"birth_bands": youth.BIRTH_BANDS,
		"elite_weights": youth.ELITE_RATING_WEIGHTS,
		"generation": generation,
		"squad_min": squad_min,
		"squad_max": squad_max,
		"stat_fields": load("res://game/player_stats.gd").FIELDS,
		"mix": ratings.MIX,
		"gk_mix": ratings.GK_MIX,
		"role_weights": lineup.ROLE_WEIGHTS,
		"style_weights": lineup.STYLE_WEIGHTS,
		"ability_terms": terms,
		"attribute_profile": {
			"fit_headroom": type_constants.FIT_HEADROOM,
			"aptitude_min": type_constants.APTITUDE_MIN,
			"aptitude_max": type_constants.APTITUDE_MAX,
			"secondary_share": type_constants.SECONDARY_GROWTH_SHARE,
			"aptitudes_key": type_constants.APTITUDES_KEY,
		},
		"characters": type_constants.CHARACTERS,
		"character_flags": {
			"hot_head": "HOT_HEAD", "ice_cold": "ICE_COLD", "fearless": "FEARLESS",
			"inconsistent": "INCONSISTENT", "individualist": "INDIVIDUALIST",
			"team_player": "TEAM_PLAYER", "professional": "PROFESSIONAL", "ambitious": "AMBITIOUS",
		},
	}

static func backend() -> String:
	var instance: Variant = core()
	return "C++ / " + str(instance.version()) if instance != null else "GDScript (native module unavailable or disabled)"

static func supports_match(config: Dictionary) -> bool:
	# Legacy tactic migration stays on the reference path for its first match.
	var tactics: Script = load("res://game/tactic_types.gd")
	for side in ["home", "away"]:
		var coach: Dictionary = (config.get(side, {}) as Dictionary).get("coach", {})
		if not coach.is_empty() and not tactics._tactics_are_valid(coach):
			return false
	return true
