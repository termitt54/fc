extends Node

const Config := preload("res://game/youth_generation_config.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	Config.birth_config_path = "user://config/rarity_isolated.json"
	Config.reset_birth_to_defaults(false)
	var monotone := true
	for talent in range(1, 101):
		for threshold in range(20, 101):
			monotone = monotone and Config.potential_probability(talent, threshold) + 1e-12 >= Config.potential_probability(talent - 1, threshold)
	check(monotone, "whole rating distribution improves monotonically at every threshold, including PA100")
	check(Config.potential_probability(35, 100) <= Config.potential_probability(65, 100), "no genius chance disappears between 35 and 65")
	check(is_equal_approx(Config.potential_probability(100, 100), 0.000004), "PA100 capped at 1 in 250000 births even at talent 100")
	check(is_equal_approx(Config.potential_probability(100, 95), 0.0006), "PA95+ remains rarer than PA90+")
	check(Config.potential_probability(70, 80) < Config.potential_probability(85, 80), "country depth still differs")
	check(Config.potential_probability(0, 100) > 0.0, "even the weakest country retains an exceptionally rare prodigy chance")
	check(Config.youth_talent_grade_label(50) == "Слабый" and Config.youth_talent_grade_label(85) == "Элита", "editor grades match the recalibrated country scale")
	var rng := RandomNumberGenerator.new()
	rng.seed = 181724
	var elite_counts := {}
	for i in 100000:
		var pa := Config._roll_elite_rating(9, rng)
		elite_counts[pa] = int(elite_counts.get(pa, 0)) + 1
	check(elite_counts.size() == 5, "every PA95-99 remains possible")
	check(int(elite_counts[95]) > int(elite_counts[99]) * 10, "PA95 is much more common than PA99")
	var rare100 := 0
	var rare95 := 0
	rng.seed = 334491
	for i in 2000000:
		var pa := Config.roll_birth_potential(100, rng)
		if pa == 100:
			rare100 += 1
		if pa >= 95:
			rare95 += 1
	check(rare100 <= 30, "two million full birth rolls do not flood world with PA100")
	check(absi(rare95 - 1200) < 240, "full birth pipeline matches elite-tail frequency")
	var tab := (load("res://scenes/settings/tabs/global_pa_tab.tscn") as PackedScene).instantiate()
	add_child(tab)
	check(tab._collect_rows() == Config.editor_birth_weights(), "compact editor display preserves every exact stored percentage")
	check(tab._genius[70].text == "50000000", "editor explains true PA100 rarity as one birth per population")
	check(tab._genius[100].text == "250000", "editor never rounds a rare positive chance to zero")
	tab._cells[70][10].text = "0.0004"
	tab._refresh_sum(70)
	check(tab._genius[70].text == "250000", "PA100 preview follows edits before saving")
	check(tab._cells[50].size() == 11, "editor exposes all eleven potential bands")
	check(tab._tenths_from_text("0.000001") == 1, "editor preserves a one-in-100-million probability")
	check(tab._format_tenths(1) == "0.000001", "small positive editor value never rounds to zero")
	check(absf(Config.row_mean_potential(Config.birth_weights(50)) - 46.1) < 2.0, "weak countries have a genuinely lower mean potential")
	var custom := Config.editor_birth_weights()
	check(Config.migrate_birth_rows(custom, 4) == custom, "v4 custom tables remain exact")
	check(Config.migrate_birth_rows(Config.LEGACY_V3_BIRTH_WEIGHTS, 3) == Config.default_birth_weights(), "old six-band table migrates to v4 defaults")
	var legacy_text := JSON.stringify({"version": 3, "rows": Config.LEGACY_V3_BIRTH_WEIGHTS})
	var legacy_file := FileAccess.open(Config.birth_config_path, FileAccess.WRITE)
	legacy_file.store_string(legacy_text)
	legacy_file.close()
	Config.unload_birth()
	check(Config.editor_birth_weights() == Config.default_birth_weights(), "v3 disk settings load as calibrated v4 defaults")
	check(FileAccess.get_file_as_string(Config.birth_config_path) == legacy_text, "loading old settings never overwrites the original file")
	DirAccess.remove_absolute(Config.birth_config_path)
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and DisplayServer.get_name() != "headless":
		tab._on_reset_pressed()
		tab.theme = Theme.new()
		tab.theme.default_font = load(WeTokens.FONT_PATH)
		await get_tree().process_frame
		(tab.get_node("%TableScroll") as ScrollContainer).scroll_vertical = 76 * 30
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0])
	tab.queue_free()
	print("RARITY COUNTS elite100=", elite_counts[99], " full100=", rare100, " full95+=", rare95)
	print("=== Potential rarity: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)
