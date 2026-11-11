extends Node
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var field = load("res://ui/components/we_slider_field.tscn").instantiate()
	field.configure({"min": 0.0, "max": 1.0, "step": 0.01, "percent": true, "decimals": 2}, 0.25)
	add_child(field)
	check(field.apply_text("50") and is_equal_approx(field.value, 0.5), "50 means fifty percent")
	check(field.apply_text("75%") and is_equal_approx(field.value, 0.75), "percent sign accepted")
	check(field.apply_text("32,0") and is_equal_approx(field.value, 0.32), "decimal comma accepted")
	check(not field.apply_text("wrong") and is_equal_approx(field.value, 0.32), "invalid text preserves value")
	check(field.apply_text("200") and field.value == 1.0, "input clamped to maximum")
	check(field.apply_text("-20") and field.value == 0.0, "input clamped to minimum")
	field.configure({"min": 0.0, "max": 2.0, "step": 0.01, "percent": true, "decimals": 2, "display_scale": 2.0}, 0.5)
	check(field.apply_text("150") and is_equal_approx(field.value, 0.75), "display scale reversed correctly")
	field.configure({"min": 0.0, "max": 20.0, "step": 1.0, "decimals": 0, "suffix": " матчей"}, 10.0)
	check(field.apply_text("15 матчей") and field.value == 15, "integer with suffix accepted")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	field._on_value_input(click)
	check(field._number_edit.visible and not field._value_label.visible, "click opens number editor")
	field._number_edit.text = "17"
	field._number_edit.text_submitted.emit("17")
	check(field.value == 17 and field._value_label.visible, "Enter commits value")
	field._on_value_input(click)
	field._number_edit.text = "19"
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	field._on_edit_input(escape)
	check(field.value == 17 and not field._editing, "Escape cancels edit")
	field._on_value_input(click)
	field._number_edit.text = "18"
	field._finish_edit()
	check(field.value == 18, "focus exit commits value")
	field.queue_free()
	print("Slider manual input: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
