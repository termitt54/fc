extends Node

var failed := 0
var passed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	var dialog := (load("res://scenes/world_editor/dialogs/competition_unit_prizes_dialog.tscn") as PackedScene).instantiate()
	add_child(dialog)
	var unit := {"id": 99, "name": "League One", "competition_type": "DIVISIONS",
		"divisions_count": 2, "teams_per_division": 12, "regular_season_enabled": true,
		"teams_playoff": 16, "playoff_third_place": true,
		"prize_rules": {"regular_1": 10000000, "regular_2": 8000000, "regular_3": 6000000,
			"playoff_champion": 60000000, "playoff_runner_up": 50000000,
			"playoff_third": 45000000, "playoff_fourth": 40000000,
			"playoff_out_1": 30000000, "playoff_out_2": 35000000}}
	dialog.open_editor(unit)
	await get_tree().process_frame
	check(dialog._fields.size() == 18, "12 division places and 6 playoff outcomes")
	check(not dialog._fields.has("regular_13"), "no combined table prizes")
	check(dialog._fields.regular_1.text == "10 000 000", "amounts use readable thousands")
	check(dialog._total.text == "623 000 000 €", "fund counts both divisions and all eliminated teams")
	dialog._fields.regular_2.text = "12 345 678"
	dialog._commit_field("regular_2")
	check(dialog._amounts.regular_2 == 12345678, "formatted amount can be entered")
	dialog._fields.regular_2.text = "invalid"
	dialog._commit_field("regular_2")
	check(dialog._amounts.regular_2 == 12345678, "invalid input preserves amount")
	dialog._fields.regular_2.text = "-1"
	dialog._commit_field("regular_2")
	check(dialog._amounts.regular_2 == 0, "negative amount clamps to zero")
	dialog._fields.regular_2.text = "9999999999"
	dialog._commit_field("regular_2")
	check(dialog._amounts.regular_2 == PrizeRules.AMOUNT_MAX, "amount cap applied")
	dialog.set_busy(true)
	check(not dialog._fields.regular_2.editable, "busy editor blocks edits")
	dialog.set_busy(false)
	var submitted: Array = []
	dialog.prizes_submitted.connect(func(id, amounts): submitted.append({"id": id, "amounts": amounts}))
	dialog._fields.regular_2.text = "7 500 000"
	dialog._on_confirm()
	check(submitted.size() == 1 and int(submitted[0].amounts.regular_2) == 7500000, "save commits focused field without losing entered amount")
	dialog.open_editor(unit)
	dialog._set_amount("regular_1", 1)
	dialog._on_cancel()
	check(unit.prize_rules.regular_1 == 10000000, "cancel leaves source rules unchanged")
	dialog.open_editor(unit)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		dialog.theme = Theme.new()
		dialog.theme.default_font = load(WeTokens.FONT_PATH)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	dialog.queue_free()
	await get_tree().process_frame
	print("=== Prize editor: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
