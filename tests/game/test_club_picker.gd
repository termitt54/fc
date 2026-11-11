extends Node
## Club picker hides clubs already placed in another division of the same tournament.
## Run: godot --headless --path . res://tests/game/test_club_picker.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_predicate()
	await _test_dialog()
	print("=== Club picker: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _test_predicate() -> void:
	var dialog_script: Script = load("res://scenes/world_editor/dialogs/competition_unit_clubs_dialog.gd")
	_check(dialog_script.is_listed(1, {1: true}, {1: true}), "a club selected here stays visible")
	_check(not dialog_script.is_listed(2, {}, {2: true}), "a club in another division is hidden")
	_check(dialog_script.is_listed(3, {}, {}), "a free club stays in the list")


func _test_dialog() -> void:
	var dialog := (load("res://scenes/world_editor/dialogs/competition_unit_clubs_dialog.tscn") as PackedScene).instantiate()
	add_child(dialog)
	var clubs: Array = [
		{"id": 1, "name": "Alpha", "country_name": "Spain", "reputation": 900},
		{"id": 2, "name": "Beta", "country_name": "Russia", "reputation": 800},
		{"id": 3, "name": "Gamma", "country_name": "Norway", "reputation": 700},
	]
	dialog.open_picker(4, "League One", clubs, [1], false, [1, 2])
	_check(dialog._rows.has(1) and dialog._rows.has(3) and not dialog._rows.has(2), "hides a club already in another division")
	_check(dialog._hidden_label.text == "Скрыто 1 — уже в других дивизионах", "notes how many clubs are hidden")
	_check(dialog._clear_button.disabled == false, "clear is available while clubs are selected")
	dialog._clear_button.pressed.emit()
	await get_tree().process_frame
	_check(dialog._selected.is_empty(), "clear removes every selected club")
	_check(dialog._rows.has(3) and not dialog._rows.has(1) and not dialog._rows.has(2), "cleared clubs from other divisions leave the list")
	_check(dialog._clear_button.disabled, "clear is unavailable when nothing is selected")
	dialog.open_picker(8, "Cup", clubs, [2], false, [])
	_check(dialog._rows.has(1) and dialog._rows.has(2) and dialog._rows.has(3), "a cup shows clubs that also play in divisions")
	_check(dialog._hidden_label.text.is_empty(), "a cup does not mention hidden clubs")
	dialog.queue_free()


func _check(ok: bool, label: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)
