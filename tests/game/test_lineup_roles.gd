extends Node

const Selector := preload("res://game/lineup_selector.gd")
const Config := preload("res://game/match_simulation_config.gd")
const RoleFixtures := preload("res://tests/game/role_squad_fixtures.gd")
const Ratings := preload("res://game/match_ratings.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	Config.config_path = "user://config/lineup_roles_test.json"
	Config.reset_to_defaults(false)
	var squad := RoleFixtures.specialised_squad()
	var control := _build(squad, "control")
	var pressing := _build(squad, "pressing")
	_check(_starter(control, "CM") == 1008, "control selects the playmaker")
	_check(_starter(pressing, "CM") == 1009, "pressing selects the ball winner")
	print("ROLE_SELECTION: control CM %d, pressing CM %d" % [_starter(control, "CM"), _starter(pressing, "CM")])
	for index in [7, 8]:
		var ratings := Ratings.of(squad[index])
		print("ROLE_SCORE: id=%d CA=%.1f control=%.2f pressing=%.2f" % [
			squad[index]["id"], float(ratings["ability"]) * 100.0,
			Selector.role_value(ratings, "CM", "control"), Selector.role_value(ratings, "CM", "pressing")])
	for style in ["control", "pressing"]:
		var lineup := _build(squad, style)
		var seen: Dictionary = {}
		for row in lineup["starters"]:
			seen[row["player"]["id"]] = true
		var keeper_count := 0
		for player in lineup["bench"]:
			_check(not seen.has(player["id"]), "bench excludes starters and duplicates")
			seen[player["id"]] = true
			keeper_count += int(player["position"] == "GK")
		_check(keeper_count == 1, "a weak reserve goalkeeper is guaranteed a bench place")
		_check((lineup["bench"] as Array).size() <= 10, "bench stays within matchday limit")
		for slot in ["CB", "WM", "CM", "ST"]:
			var covered := false
			for player in lineup["bench"]:
				covered = covered or player["position"] == slot
			_check(covered, "bench covers %s" % slot)
	squad[7]["condition"] = 20
	_check(_starter(_build(squad, "control"), "CM") != 1008, "tired specialist loses to fresh cover")
	squad[7]["condition"] = 100
	squad[7]["injury_rounds"] = 3
	_check(_starter(_build(squad, "control"), "CM") != 1008, "injured specialist is excluded")
	squad[7]["injury_rounds"] = 0
	squad[7]["suspension_matches"] = 3
	_check(_starter(_build(squad, "control"), "CM") != 1008, "suspended specialist is excluded")
	_check((_build([], "control")["starters"] as Array).is_empty(), "empty pool remains safe")
	Config.config_path = Config.DEFAULT_CONFIG_PATH
	Config.reset_to_defaults(false)
	print("=== Result: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)

func _build(squad: Array, style: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	return Selector.build(squad, [], {}, {"formation": "2-4-1", "style": style}, rng)

func _starter(lineup: Dictionary, slot: String) -> int:
	for row in lineup["starters"]:
		if row["slot"] == slot:
			return int(row["player"]["id"])
	return 0

func _check(ok: bool, label: String) -> void:
	if ok:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

