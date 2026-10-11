extends Node
## Headless check for formations, styles, and non-locked coach picks.
## Run: godot --headless --path . res://tests/game/test_tactic_types.tscn

const TacticTypesScript := preload("res://game/tactic_types.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Tactic types tests ===")
	_assert_catalog()
	_assert_alignment()
	_assert_identity()
	_assert_match_pick_not_locked()
	_finish()


func _assert_catalog() -> void:
	_assert(TacticTypesScript.FORMATIONS.size() == 6, "six formation templates")
	_assert(TacticTypesScript.STYLES.size() == 7, "seven playing styles")
	for code in TacticTypesScript.FORMATIONS:
		var xi: Array = TacticTypesScript.starting_xi(str(code))
		_assert(xi.size() == 8, "%s XI is 1 GK + 7 outfield (got %d)" % [str(code), xi.size()])
		_assert(str(xi[0]) == PlayerTypesScript.POS_GK, "%s starts with GK" % str(code))
		var outfield: Array = TacticTypesScript.outfield_slots(str(code))
		_assert(outfield.size() == TacticTypesScript.MATCH_OUTFIELD, "%s has 7 outfield slots" % str(code))
		for pos in outfield:
			_assert(PlayerTypesScript.FIELD_POSITIONS.has(str(pos)), "%s slot %s is a field position" % [str(code), str(pos)])
		var bench: Array = TacticTypesScript.bench_slots(str(code))
		_assert(bench.size() == TacticTypesScript.MATCH_BENCH, "%s bench is 10 (got %d)" % [str(code), bench.size()])
		_assert(str(bench[0]) == PlayerTypesScript.POS_GK, "%s bench starts with backup GK" % str(code))
		var seen: Dictionary = {}
		for pos in outfield:
			seen[str(pos)] = true
		for pos in seen.keys():
			_assert(bench.has(str(pos)), "%s bench covers starting %s" % [str(code), str(pos)])
	for style in TacticTypesScript.STYLES:
		var forms: Array = TacticTypesScript.formations_for_style(str(style))
		_assert(not forms.is_empty(), "%s has at least one compatible formation" % str(style))
		_assert(TacticTypesScript.style_label(str(style)) != "—", "%s has a label" % str(style))
		for form in forms:
			_assert(
				TacticTypesScript.is_compatible(str(style), str(form)),
				"%s allows only matching %s" % [str(style), str(form)]
			)
			_assert(
				not TacticTypesScript.camps_clash(
					TacticTypesScript.camp_of_style(str(style)),
					TacticTypesScript.camp_of_formation(str(form))
				),
				"%s / %s do not mix attack and defence" % [str(style), str(form)]
			)


func _assert_alignment() -> void:
	_assert(not TacticTypesScript.is_compatible(TacticTypesScript.STYLE_CONTROL, TacticTypesScript.FORM_331), "control does not sit on a low block")
	_assert(not TacticTypesScript.is_compatible(TacticTypesScript.STYLE_TIKI_TAKA, TacticTypesScript.FORM_322), "tiki-taka does not sit on a block")
	_assert(not TacticTypesScript.is_compatible(TacticTypesScript.STYLE_PARK_BUS, TacticTypesScript.FORM_223), "the bus does not play 2-2-3")
	_assert(not TacticTypesScript.is_compatible(TacticTypesScript.STYLE_PRESSING, TacticTypesScript.FORM_331), "pressing does not sit on a low block")
	_assert(TacticTypesScript.is_compatible(TacticTypesScript.STYLE_CONTROL, TacticTypesScript.FORM_232), "control matches 2-3-2")
	_assert(TacticTypesScript.is_compatible(TacticTypesScript.STYLE_PARK_BUS, TacticTypesScript.FORM_331), "the bus matches a low block")
	for style in TacticTypesScript.STYLES:
		for other in TacticTypesScript.relatives_for_style(str(style)):
			_assert(
				not TacticTypesScript.camps_clash(
					TacticTypesScript.camp_of_style(str(style)),
					TacticTypesScript.camp_of_style(str(other))
				),
				"backup of %s stays in family (%s)" % [str(style), str(other)]
			)
	var broken := {
		"id": 11,
		"club_id": 2,
		"primary_style": TacticTypesScript.STYLE_CONTROL,
		"backup_style": TacticTypesScript.STYLE_PARK_BUS,
		"primary_formation": TacticTypesScript.FORM_331,
		"backup_formation": TacticTypesScript.FORM_223,
		"style": "attacking",
	}
	TacticTypesScript.ensure_coach_tactics(broken)
	_assert(TacticTypesScript.is_compatible(str(broken.get("primary_style", "")), str(broken.get("primary_formation", ""))), "ensure fixes primary pair")
	_assert(TacticTypesScript.is_compatible(str(broken.get("backup_style", "")), str(broken.get("backup_formation", ""))), "ensure fixes backup pair")
	_assert(
		not TacticTypesScript.camps_clash(
			TacticTypesScript.camp_of_style(str(broken.get("primary_style", ""))),
			TacticTypesScript.camp_of_style(str(broken.get("backup_style", "")))
		),
		"ensure does not keep a defence backup on a possession coach"
	)


func _assert_identity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for _i in 40:
		var identity: Dictionary = TacticTypesScript.roll_coach_identity(rng)
		var primary := str(identity.get("primary_style", ""))
		var backup := str(identity.get("backup_style", ""))
		_assert(TacticTypesScript.STYLES.has(primary), "rolled primary style")
		_assert(TacticTypesScript.STYLES.has(backup), "rolled backup style")
		_assert(primary != backup, "rolled backup differs from primary")
		_assert(str(identity.get("primary_formation", "")) != str(identity.get("backup_formation", "")), "rolled backup formation differs")
		_assert(["attacking", "balanced", "defensive"].has(str(identity.get("style", ""))), "mentality derived from primary style")
		_assert(TacticTypesScript.is_compatible(primary, str(identity.get("primary_formation", ""))), "primary pair matches")
		_assert(TacticTypesScript.is_compatible(backup, str(identity.get("backup_formation", ""))), "backup pair matches")
		_assert(
			not TacticTypesScript.camps_clash(TacticTypesScript.camp_of_style(primary), TacticTypesScript.camp_of_style(backup)),
			"primary and backup styles stay in one family"
		)

	var legacy := {"id": 3, "club_id": 8, "style": "defensive"}
	TacticTypesScript.ensure_coach_tactics(legacy)
	_assert(TacticTypesScript.STYLES.has(str(legacy.get("primary_style", ""))), "legacy defensive coach gets a style")
	_assert(str(legacy.get("style", "")) == "defensive", "legacy mentality stays")
	_assert(str(legacy.get("primary_style", "")) != str(legacy.get("backup_style", "")), "legacy backup differs")


func _assert_match_pick_not_locked() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var coach := {
		"id": 1,
		"club_id": 1,
		"primary_style": TacticTypesScript.STYLE_CONTROL,
		"backup_style": TacticTypesScript.STYLE_TIKI_TAKA,
		"primary_formation": TacticTypesScript.FORM_232,
		"backup_formation": TacticTypesScript.FORM_241,
		"style": "balanced",
	}
	var style_counts := {"primary": 0, "backup": 0, "other": 0}
	var form_counts := {"primary": 0, "backup": 0, "other": 0}
	var samples := 2500
	var clashes := 0
	for _i in samples:
		var plan: Dictionary = TacticTypesScript.pick_match_plan(coach, rng)
		style_counts[str(plan.get("style_source", ""))] = int(style_counts.get(str(plan.get("style_source", "")), 0)) + 1
		form_counts[str(plan.get("formation_source", ""))] = int(form_counts.get(str(plan.get("formation_source", "")), 0)) + 1
		if not TacticTypesScript.is_compatible(str(plan.get("style", "")), str(plan.get("formation", ""))):
			clashes += 1
	_assert(clashes == 0, "match plan never mixes attack and defence")
	_assert(int(style_counts["primary"]) == samples, "the coach plays his primary style every match")
	_assert(int(form_counts["primary"]) == samples, "the coach plays his primary formation every match")


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % message)
	else:
		_failed += 1
		print("FAIL: %s" % message)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)
