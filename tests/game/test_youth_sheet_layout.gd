extends Node
const Config = preload("res://game/youth_generation_config.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func frames() -> void:
	for i in 5:
		await get_tree().process_frame

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	get_window().size = Vector2i(1280, 900)
	await frames()
	var tab := preload("res://scenes/settings/tabs/global_pa_tab.tscn").instantiate()
	add_child(tab)
	tab.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tab._show_all.button_pressed = true
	await frames()
	check(tab._frozen_rows.get_child_count() == 101, "Frozen identifiers exist for every talent")
	check(tab.get_node("%TableFrame").get_global_rect().end.x <= get_viewport().get_visible_rect().end.x + 1, "Wide table stays inside viewport")
	if tab.get_node("%TableFrame").get_global_rect().end.x > get_viewport().get_visible_rect().end.x + 1:
		for path in [".", "%Body", "%TableFrame", "%TableWidth", "%Header", "%TableScroll"]:
			var node: Control = tab if path == "." else tab.get_node(path)
			print("LAYOUT ", path, " rect=", node.get_global_rect(), " minimum=", node.get_combined_minimum_size())
	var main: ScrollContainer = tab._table_scroll
	var frozen: ScrollContainer = tab._frozen_scroll
	var head: ScrollContainer = tab._header_scroll
	for talent in [0, 50, 85, 100]:
		check(absf(tab._rows.get_child(talent).size.y - tab._frozen_rows.get_child(talent).size.y) < 1, "Main and frozen rows have equal heights")
	main.scroll_vertical = roundi(tab._rows.get_child(86).position.y + 7)
	await frames()
	check(main.scroll_vertical == frozen.scroll_vertical, "Vertical scrolling synchronizes frozen column")
	check(absf(tab._rows.get_child(86).global_position.y - tab._frozen_rows.get_child(86).global_position.y) < 1, "Frozen identifier aligns with its data")
	var frozen_x: float = tab._frozen_rows.global_position.x
	main.scroll_horizontal = roundi(main.get_h_scroll_bar().max_value - main.get_h_scroll_bar().page)
	await frames()
	check(main.scroll_horizontal == head.scroll_horizontal, "Horizontal header scrolling matches body")
	check(tab._frozen_rows.global_position.x == frozen_x, "Talent column does not move horizontally")
	var headers: HBoxContainer = tab._header.get_child(0).get_child(1)
	check(absf(headers.get_child(0).global_position.x - tab._cells[86][0].global_position.x) < 1, "Probability headers stay above cells")
	check(absf(headers.get_child(headers.get_child_count() - 1).global_position.x - tab._sums[86].global_position.x) < 1, "Final header aligns at far right")
	main.scroll_vertical = roundi(main.get_v_scroll_bar().max_value - main.get_v_scroll_bar().page)
	await frames()
	check(absf(tab._rows.get_child(100).global_position.y - tab._frozen_rows.get_child(100).global_position.y) < 1, "Last row remains aligned with horizontal scrollbar present")
	frozen.scroll_vertical = 400
	await frames()
	check(main.scroll_vertical == frozen.scroll_vertical, "Wheel over frozen column can scroll main rows")
	tab._show_all.button_pressed = false
	await frames()
	var visible := 0
	for i in 101:
		check(tab._rows.get_child(i).visible == tab._frozen_rows.get_child(i).visible, "Filtering keeps both row halves together")
		visible += int(tab._rows.get_child(i).visible)
	check(visible == 2, "Focused mode shows selected and comparison rows")
	tab._show_all.button_pressed = true
	tab._frozen_buttons[85].pressed.emit()
	await frames()
	check(int(tab._talent.value) == 85 and not tab._dirty, "Selecting a frozen identifier does not change data")
	var selector: HBoxContainer = tab._talent.get_parent()
	selector.get_child(2).pressed.emit()
	check(int(tab._talent.value) == 86, "Custom selector plus chooses next talent")
	selector.get_child(0).pressed.emit()
	check(int(tab._talent.value) == 85 and not tab._dirty, "Custom selector minus restores selection without editing probabilities")
	main.scroll_horizontal = 0
	var edit: LineEdit = tab._cells[85][6]
	edit.grab_focus()
	await frames()
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	edit.gui_input.emit(down)
	await frames()
	check(get_viewport().gui_get_focus_owner() == tab._cells[86][6], "Arrow down moves to same band in next row")
	var focused_rect: Rect2 = tab._cells[86][6].get_global_rect()
	check(focused_rect.position.y >= main.global_position.y and focused_rect.end.y <= main.get_global_rect().end.y, "Focused keyboard cell remains visible")
	if focused_rect.position.y < main.global_position.y or focused_rect.end.y > main.get_global_rect().end.y:
		print("FOCUS rect=", focused_rect, " viewport=", main.get_global_rect(), " scroll=", main.scroll_vertical)
	edit = tab._cells[86][6]
	var original: Array = tab._selected_row(86).duplicate()
	edit.text = "12.345"
	edit.text_changed.emit(edit.text)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	edit.gui_input.emit(escape)
	check(tab._selected_row(86) == original, "Escape restores uncommitted probability")
	edit.grab_focus()
	await frames()
	edit.text = "18.123456"
	edit.text_changed.emit(edit.text)
	edit.text_submitted.emit(edit.text)
	edit.release_focus()
	check(tab._selected_row(86)[6] == 18123456, "Enter then focus exit preserves precise band value")
	check(tab._undo_button.visible, "Undo is available outside advanced tools")
	tab.queue_free()
	await frames()
	print("Youth sheet layout: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
