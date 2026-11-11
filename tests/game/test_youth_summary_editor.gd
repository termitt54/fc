extends Node
const Config = preload("res://game/youth_generation_config.gd")
const Tools = preload("res://game/youth_talent_tools.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var defaults := Config.default_birth_weights()
	for talent in 101:
		var source: Array = defaults[talent]
		for metric in ["mean", "pa70", "pa80", "pa90", "pa100"]:
			var current := Config.row_mean_potential(source) if metric == "mean" else Config.row_probability(source, int(metric.trim_prefix("pa"))) * 100
			var step := 0.1 if metric == "mean" else (0.01 if metric == "pa90" else (maxf(0.000001, current * 0.05) if metric == "pa100" else 0.5))
			for direction in [-1, 1]:
				var target: float = current + direction * step
				var result := Tools.adjust_summary(source, metric, target)
				check(result.ok, "Valid summary adjustment")
				check(result.row.reduce(func(a, b): return a + b, 0) == Config.BIRTH_WEIGHT_TOTAL, "Exact integer total remains 100 percent")
				check(result.row.slice(8) == source.slice(8) if metric in ["mean", "pa70", "pa80"] else (result.row[10] == source[10] if metric == "pa90" else true), "Protected rare weights unchanged")
				check(result.row.all(func(v): return int(v) >= 0), "No negative probability")
				check(absf(float(result.actual) - clampf(target, result.min, result.max)) < 0.00005, "Actual generation expectation matches adjusted target")
		check(source == Config.default_birth_weights()[talent], "Input source not mutated")
	check(not Tools.adjust_summary(defaults[85], "mean", NAN).ok, "NaN rejected")
	var bad: Array = defaults[85].duplicate()
	bad[0] += 1
	check(not Tools.adjust_summary(bad, "mean", 75).ok, "Invalid sum is not silently repaired")
	var empty := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, Config.BIRTH_WEIGHT_TOTAL]
	check(Tools.adjust_summary(empty, "mean", 60).row == empty, "All-genius row stays fixed with locked rare tail")
	var zero_high := [Config.BIRTH_WEIGHT_TOTAL, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	var fallback := Tools.adjust_summary(zero_high, "pa80", 20)
	check(absf(Config.row_probability(fallback.row, 80) * 100 - 20) < 0.000001, "Absent high bands can receive probability")
	var original_path := Config.birth_config_path
	Config.birth_config_path = "user://tests/youth-summary-editor.json"
	Config.reset_birth_to_defaults(false)
	var runtime := Config.editor_birth_weights()
	var tab := preload("res://scenes/settings/tabs/global_pa_tab.tscn").instantiate()
	add_child(tab)
	tab._show_all.button_pressed = true
	check(tab._rows.get_child_count() == 101 and tab._summary_controls.size() == 101, "Every talent has direct summary controls")
	var mean_before := Config.row_mean_potential(tab._selected_row(73))
	tab._summary_controls[73].mean.plus.pressed.emit()
	check(absf(Config.row_mean_potential(tab._selected_row(73)) - mean_before - 0.1) < 0.00005, "Plus changes clicked row by 0.1 PA")
	check(tab._selected_row(85) == defaults[85], "Clicking another row does not edit inspector's selected talent")
	var high_before := Config.row_probability(tab._selected_row(73), 80) * 100
	tab._summary_controls[73].pa80.minus.pressed.emit()
	check(absf(Config.row_probability(tab._selected_row(73), 80) * 100 - high_before + 0.5) < 0.00001, "Minus changes PA80 share by 0.5 percentage points")
	check(tab._selected_row(73).slice(8) == defaults[73].slice(8), "UI preserves rare tail")
	var edit: LineEdit = tab._summary_controls[85].mean.edit
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "78,2"
	edit.text_submitted.emit(edit.text)
	check(absf(Config.row_mean_potential(tab._selected_row(85)) - 78.2) < 0.00005, "Manual comma input commits on Enter")
	var after_enter: Array = tab._selected_row(85).duplicate()
	edit.release_focus()
	check(tab._selected_row(85) == after_enter, "Enter then focus exit does not edit twice")
	edit = tab._summary_controls[85].pa80.edit
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "55,25%"
	edit.release_focus()
	check(absf(Config.row_probability(tab._selected_row(85), 80) * 100 - 55.25) < 0.00001, "Percentage input commits on focus exit")
	check(Config.editor_birth_weights() == runtime, "Unsaved edits cannot change player generation")
	edit = tab._summary_controls[85].mean.edit
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "80,0"
	tab._summary_controls[85].mean.plus.pressed.emit()
	check(absf(Config.row_mean_potential(tab._selected_row(85)) - 80.1) < 0.00005, "Plus after manual typing commits the entered value before adding the step")
	edit = tab._summary_controls[85].pa80.edit
	var before_focus: Array = tab._selected_row(85).duplicate()
	edit.grab_focus()
	await get_tree().process_frame
	edit.release_focus()
	check(tab._selected_row(85) == before_focus, "Focus without editing preserves exact probabilities")
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "wrong"
	check(not tab._commit_summary(85, "pa80") and tab._selected_row(85) == before_focus, "Invalid input preserves row")
	edit.release_focus()
	tab._summary_controls[85].mean.plus.pressed.emit()
	tab._undo_tool()
	check(tab._selected_row(85) == before_focus, "Undo restores direct summary edit")
	edit = tab._summary_controls[85].mean.edit
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "79,3"
	tab._on_save_pressed()
	Config.unload_birth()
	check(absf(Config.row_mean_potential(Config.birth_weights(85)) - 79.3) < 0.00005, "Save commits focused manual input and persists target")
	check(Config.birth_weights(75) == defaults[75] and Config.birth_weights(85).slice(8) == defaults[85].slice(8), "Saving preserves other countries and rare tail")
	check(tab._summary_controls[85].size() == 5, "All five derived metrics have direct editing")
	for metric in ["pa70", "pa90", "pa100"]:
		edit = tab._summary_controls[85][metric].edit
		edit.grab_focus()
		await get_tree().process_frame
		var target := {"pa70": "90,5%", "pa90": "1,25%", "pa100": "0,0005%"}[metric] as String
		edit.text = target
		edit.text_submitted.emit(target)
		edit.release_focus()
		var actual := Config.row_probability(tab._selected_row(85), int(metric.trim_prefix("pa"))) * 100
		check(absf(actual - float(target.replace("%", "").replace(",", "."))) < 0.000005, "Manual input for " + metric)
	var chance := Config.row_probability(tab._selected_row(85), 100) * 100
	tab._summary_controls[85].pa100.plus.pressed.emit()
	check(absf(Config.row_probability(tab._selected_row(85), 100) * 100 - chance - tab._metric_step("pa100", chance)) < 0.000001, "PA100 plus increases chance rather than denominator")
	check(tab._status.text.contains("Талант 85") and tab._metric_explanation("pa80").contains("50 из 100"), "Selected row and percentage meaning are explicit")
	var edited_row: Array = tab._selected_row(85).duplicate()
	tab._on_save_pressed()
	Config.unload_birth()
	check(Config.birth_weights(85) == edited_row, "All five summary adjustments survive configuration save and reload")
	var shares: Array = [70, 80, 90, 100].map(func(threshold): return Config.row_probability(edited_row, threshold))
	check(shares[0] >= shares[1] and shares[1] >= shares[2] and shares[2] >= shares[3], "Nested shares remain consistent after explicit rare-talent editing")
	var before_undo: Array = tab._selected_row(85).duplicate()
	tab._summary_controls[85].mean.plus.pressed.emit()
	edit = tab._summary_controls[85].mean.edit
	edit.grab_focus()
	await get_tree().process_frame
	edit.text = "70"
	tab._undo_tool()
	check(tab._selected_row(85) == before_undo, "Undo while a field is focused cancels its draft and restores the previous row")
	tab.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(Config.birth_config_path)
	Config.birth_config_path = original_path
	Config.unload_birth()
	print("Youth summary editor: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
