extends Node
## One strength coefficient on the division unit.
## Run: godot --headless --path . res://tests/game/test_division_strength.tscn


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Division strength ===")
	_test_default()
	_test_keeps_the_unit_value()
	_test_old_list_uses_the_first_value()
	var packed: PackedScene = load("res://scenes/world_editor/dialogs/competition_form_dialog.tscn")
	_assert(packed != null, "competition form still parses")
	_finish()


func _test_default() -> void:
	_assert(
		CompetitionUnitRepository.normalize_division_strength("[]") == 800,
		"an empty division starts at 800"
	)
	_assert(
		CompetitionUnitRepository.normalize_division_strength(null) == 800,
		"a missing coefficient starts at 800"
	)


func _test_keeps_the_unit_value() -> void:
	_assert(
		CompetitionUnitRepository.normalize_division_strength(640) == 640,
		"the division keeps its coefficient"
	)
	_assert(
		CompetitionUnitRepository.normalize_division_strength(1400) == 1000,
		"the coefficient stays on the reputation scale"
	)
	var stored := CompetitionUnitRepository.serialize_division_strength(640)
	_assert(
		CompetitionUnitRepository.normalize_division_strength(stored) == 640,
		"the saved coefficient reads back"
	)


func _test_old_list_uses_the_first_value() -> void:
	_assert(
		CompetitionUnitRepository.normalize_division_strength("[900,500]") == 900,
		"a previously stored list keeps the main division"
	)


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)


func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
