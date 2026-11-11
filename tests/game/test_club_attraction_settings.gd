extends Node
const Config = preload("res://game/club_attraction_config.gd")
const Attraction = preload("res://game/club_attraction.gd")
var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void: call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var original_path: String = Config.config_path
	Config.config_path = "user://tests/club-attraction-settings.json"
	Config.apply_values(Config.defaults())
	var club := {"reputation": 600, "club_elo": {"elo": 800, "sporting_reputation": 800, "games": 20}}
	check(Attraction.value(club) == 650, "defaults preserve prior bounded policy")
	Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 50, "elo_weight": 50})
	check(Attraction.value(club) == 700, "50/50 mixes actual reputation and Elo")
	Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 70, "elo_weight": 30, "max_effect": 0, "confidence_matches": 1000})
	check(Attraction.value(club) == 660, "inactive bounded settings do not affect weights")
	Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 0, "elo_weight": 100})
	check(Attraction.value(club) == 800, "pure Elo allowed")
	club.club_elo.elo = 2400
	check(Attraction.value(club) == 2400, "weighted mode does not cap actual Elo")
	club.club_elo.elo = 800
	Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 100, "elo_weight": 0})
	check(Attraction.value(club) == 600, "pure prestige allowed")
	Config.apply_values({"mode": Config.MODE_BOUNDED, "max_effect": 30, "confidence_matches": 40, "reputation_weight": 0, "elo_weight": 100})
	check(Attraction.value(club) == 615, "bounded mode uses limit and observation count, ignores weights")
	Config.apply_values({"mode": Config.MODE_BOUNDED, "max_effect": 30, "confidence_matches": 0})
	check(Attraction.value(club) == 630, "zero matches enables immediate full influence")
	Config.apply_values({"mode": Config.MODE_BOUNDED, "max_effect": 0})
	check(Attraction.value(club) == 600, "zero limit disables Elo correction")
	var normalized := Config.normalized({"reputation_weight": 20, "elo_weight": 20, "max_effect": -1, "confidence_matches": 99999})
	check(normalized.reputation_weight == 50 and normalized.elo_weight == 50, "weights normalized to 100")
	check(normalized.max_effect == 0 and normalized.confidence_matches == 1000, "ranges enforced")
	check(Config.normalized({"elo_weight": "wrong"}).elo_weight == 50, "bad types use defaults")
	check(Config.normalized({"mode": "bad"}).mode == Config.MODE_BOUNDED, "bad mode uses compatible default")
	var before := Config.snapshot()
	var snapshot := Config.snapshot()
	snapshot.max_effect = 999
	check(Config.snapshot() == before, "snapshot cannot mutate runtime settings")
	check(Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 65, "elo_weight": 35, "max_effect": 77, "confidence_matches": 42}, true).ok, "settings persist")
	Config.unload()
	var saved := Config.snapshot()
	check(saved.mode == Config.MODE_WEIGHTS and saved.reputation_weight == 65 and saved.elo_weight == 35 and saved.max_effect == 77 and saved.confidence_matches == 42, "both modes' values survive reload")
	var core: Variant = NativeSimulation.core(false)
	check(core != null and core.has_method("set_attraction_settings"), "native settings support loaded")
	if core != null and core.has_method("set_attraction_settings"):
		for mode in [Config.MODE_WEIGHTS, Config.MODE_BOUNDED]:
			for share in [0, 25, 50, 100]:
				for matches in [0, 10, 40]:
					Config.apply_values({"mode": mode, "reputation_weight": 100 - share, "elo_weight": share, "max_effect": 30, "confidence_matches": matches})
					NativeSimulation.core(false)
					check(is_equal_approx(core.club_attraction(club), Attraction.value(club)), "native sync matches reference in both modes")
		var player := {"age": 24, "reputation": 740, "current_ability": 70, "wage": 100, "characters": []}
		var coach := {"attributes": {"negotiations": 10}}
		Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 100, "elo_weight": 0})
		check(not PlayerOffer.evaluate(player, club, coach).accepted, "prestige-only setting rejects offer")
		Config.apply_values({"mode": Config.MODE_WEIGHTS, "reputation_weight": 0, "elo_weight": 100})
		check(PlayerOffer.evaluate(player, club, coach).accepted, "Elo setting changes real native player decision without reload")
		check(not PlayerOffer.evaluate(player, club, coach, {"squad_ability": 10}).accepted, "weighted Elo does not bypass squad requirements")
		check(not PlayerOffer.evaluate(player, club, coach, {"offer_wage": 1}).accepted, "weighted Elo does not bypass salary requirements")
	Config.apply_values(Config.defaults())
	var settings = load("res://scenes/settings/settings.tscn").instantiate()
	add_child(settings)
	settings._tab_bar.select(2)
	var tab = settings.get_node("%ClubAttraction")
	check(tab.visible and tab._fields.size() == 4, "settings exposes four numeric controls")
	check(not tab._fields.reputation_weight.get_node("%Slider").editable and tab._fields.max_effect.get_node("%Slider").editable, "bounded mode enables only its fields")
	tab._mode.is_on = true
	tab._mode.toggled.emit(true)
	check(tab._fields.reputation_weight.get_node("%Slider").editable and not tab._fields.max_effect.get_node("%Slider").editable, "switch reverses active settings")
	tab._fields.reputation_weight.apply_text("70")
	check(tab._fields.elo_weight.value == 30, "manual reputation edit complements Elo")
	tab._fields.elo_weight.apply_text("60")
	check(tab._fields.reputation_weight.value == 40, "manual Elo edit complements reputation")
	check(Config.snapshot().mode == Config.MODE_BOUNDED, "unsaved UI edits do not change runtime")
	tab._save_settings()
	check(Config.snapshot().mode == Config.MODE_WEIGHTS and Config.snapshot().elo_weight == 60, "save applies selected mode and numbers")
	settings.queue_free()
	Config.config_path = original_path
	Config.unload()
	print("Attraction settings: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
