extends Node
const Rating = preload("res://game/club_rating.gd")
const Attraction = preload("res://game/club_attraction.gd")
const National = preload("res://game/national_rating.gd")
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
	GameSession.clear()
	GameSession.season_number = 5
	var old := {"played": true, "home_id": 1, "away_id": 2, "home_goals": 8, "away_goals": 0}
	var unit := {"id": 1, "division_strength": 1000, "clubs_by_id": {
		1: {"id": 1, "name": "Alpha", "reputation": 600}, 2: {"id": 2, "name": "Beta", "reputation": 900}}, "matches": [old], "playoff": {"teams": 16, "series": [{"id": 1, "round": 2}]}}
	var cup := {"id": 2, "division_strength": 500, "clubs_by_id": {1: {"id": 1, "name": "Alpha", "reputation": 600}}, "matches": []}
	GameSession.units = [unit, cup]
	Rating.ensure(GameSession)
	var a: Dictionary = unit.clubs_by_id[1]
	var b: Dictionary = unit.clubs_by_id[2]
	check(a.club_elo.elo == 1000 and a.reputation == 600, "seed Elo from championship strength without changing prestige")
	check(old.club_elo_counted and a.club_elo.games == 0, "old matches excluded on migration")
	check(a.club_elo.elo == b.club_elo.elo and a.reputation != b.reputation, "same championship gives equal Elo despite different reputation")
	var strengths := Rating.starting_strengths([
		{"id": 0, "unit_kind": "CUP", "competition_type": "KNOCKOUT", "division_strength": 1000, "clubs_by_id": {1: {}}},
		{"id": 5, "unit_kind": "DIVISION", "competition_type": "LEAGUE", "division_strength": 650, "clubs_by_id": {1: {}}},
		{"id": 6, "national": true, "division_strength": 999, "clubs_by_id": {1: {}}}])
	check(strengths[1] == 650, "championship takes precedence over stronger cup and national tournament")
	check(Rating.starting_strengths([{ "id": 1, "division_strength": 0, "clubs_by_id": {1: {}} }])[1] == 0, "zero-strength championship seeds zero Elo")

	check(a.club_elo == cup.clubs_by_id[1].club_elo, "league and cup share one club rating")
	var row := {"played": true, "home_id": 1, "away_id": 2, "home_goals": 2, "away_goals": 1}
	var rng_state: int = GameSession._rng.state
	Rating.record(GameSession, unit, row)
	check(a.club_elo.elo == 1025 and b.club_elo.elo == 975, "equal-club group result exchanges 25 points")
	check(a.reputation == 600 and b.reputation == 900, "Elo leaves reputation untouched")
	check(GameSession._rng.state == rng_state, "rating never consumes match RNG")
	Rating.record(GameSession, unit, row)
	check(a.club_elo.games == 1, "same result counted once")
	check(cup.clubs_by_id[1].club_elo.elo == 1025, "club rating changes in every competition copy")
	check(Rating.importance(unit, row) > Rating.importance(cup, row), "configured strength weights results")
	check(Rating.importance({"division_strength": 0}, row) == 5, "zero strength remains a low-importance match")
	var before := float(b.club_elo.elo)
	var knockout := {"played": true, "stage": "PLAYOFF", "series_id": 1, "home_id": 1, "away_id": 2, "home_goals": 1, "away_goals": 0}
	Rating.record(GameSession, unit, knockout)
	check(b.club_elo.elo == before, "FIFA knockout loser is protected")
	check(a.club_elo.elo > 1025, "FIFA knockout winner receives points")
	var replica: Array = bytes_to_var(var_to_bytes(GameSession.units))
	check(replica[0].clubs_by_id[1].club_elo.elo == a.club_elo.elo, "club Elo survives save codec")
	SaveStore.database_path_override = "user://club-rating-test.db"
	var sections := {}
	for key in SaveStore.SECTIONS: sections[key] = [] if key in ["units", "free_agents", "transfer_log"] else {}
	sections.units = replica
	check(SaveStore.new().write_slot("club_elo", {"version": 15, "season_number": 5}, sections).success, "SQLite saves club Elo")
	var loaded := SaveStore.new().load_slot("club_elo")
	check(loaded.success and loaded.data.units[0].clubs_by_id[1].club_elo.elo == a.club_elo.elo, "SQLite restores club Elo")
	SaveStore.database_path_override = ""
	GameSession.season_number += 1
	var carried := float(a.club_elo.elo)
	Rating.ensure(GameSession)
	check(a.club_elo.elo == carried and a.club_elo.season_delta == 0, "new season retains Elo and resets season delta")
	var base := {"reputation": 600}
	var strong := {"reputation": 600, "club_elo": {"games": 20, "sporting_reputation": 800}}
	var weak := {"reputation": 600, "club_elo": {"games": 20, "sporting_reputation": 400}}
	check(Attraction.value(base) == 600, "unrated club keeps prestige attraction")
	check(Attraction.value(strong) == 650 and Attraction.value(weak) == 550, "Elo raises and lowers attraction")
	var one_match := strong.duplicate(true)
	one_match.club_elo.games = 1
	check(Attraction.value(one_match) == 602.5, "one result has only gradual influence")
	check(Attraction.value({"reputation": 100, "club_elo": {"games": 20, "sporting_reputation": 1000}}) == 160, "maximum Elo effect bounded")
	var player := {"age": 24, "reputation": 740, "current_ability": 70, "wage": 100, "characters": []}
	var coach := {"attributes": {"negotiations": 10}}
	check(PlayerOffer.evaluate(player, strong, coach).accepted, "rising sporting club can attract suitable player")
	check(not PlayerOffer.evaluate(player, base, coach).accepted, "same player rejects equal prestige without sporting success")
	var elite := player.duplicate(true)
	elite.current_ability = 90
	elite.reputation = 900
	check(not PlayerOffer.evaluate(elite, strong, coach).accepted, "Elo cannot bypass elite player's standards")
	var raw: Dictionary = PlayerOffer.profile(player)
	var core: Variant = NativeSimulation.core()
	check(core != null and core.has_method("club_attraction"), "updated native module loaded")
	if core != null and core.has_method("club_attraction"):
		for club in [base, strong, weak, one_match]:
			check(is_equal_approx(core.club_attraction(club), Attraction.value(club)), "native attraction equals reference")
		var enabled := NativeSimulation.enabled
		NativeSimulation.enabled = false
		var expected := PlayerOffer.evaluate_profile(raw, strong, coach)
		var renewal := ContractRenewal.stay_chance(player, strong, coach)
		NativeSimulation.enabled = enabled
		check(PlayerOffer.evaluate_profile(raw, strong, coach) == expected, "native and GDScript offer decisions agree with Elo")
		check(is_equal_approx(ContractRenewal.stay_chance(player, strong, coach), renewal), "native and GDScript renewals agree with Elo")
	var view = load("res://scenes/game/teams_view.tscn").instantiate()
	add_child(view)
	view.set_national(false, true)
	check(view._elo_mode and not view._national and view._rows.size() == 2, "club Elo tab lists clubs")
	check(view._tabs.visible and view._title.text == "Рейтинг", "rating page has both tabs")
	view.set_national(true, true)
	check(view._elo_mode and view._national, "national rating tab stays in rating mode")
	view.set_national(true, false)
	check(view._sort_key == "reputation", "teams directory retains reputation mode")
	view.queue_free()
	var boundary_match := {"played": true, "home_id": 1, "away_id": 2, "home_goals": 1, "away_goals": 0}
	a.club_elo.elo = 5.0
	b.club_elo.elo = 0.0
	Rating.record(GameSession, unit, boundary_match)
	check(b.club_elo.elo == 0 and b.club_elo.last_delta == 0, "loss cannot push Elo below zero and reports actual delta")
	# Existing tracked scores survive a missing/stale copy in another tournament.
	var legacy: Dictionary = a.club_elo.duplicate(true)
	legacy.elo = 2200.0
	legacy.games = 100
	legacy.erase("seed_version")
	a.club_elo = legacy
	Rating.ensure(GameSession)
	check(a.club_elo.elo == 2200 and cup.clubs_by_id[1].club_elo.elo == 2200, "tracked legacy Elo above 1000 survives load and stale cup copy")
	b.club_elo.games = 0
	b.club_elo.elo = 1880.0
	b.club_elo.erase("seed_version")
	Rating.ensure(GameSession)
	check(b.club_elo.elo == 1000 and int(b.club_elo.seed_version) == 2, "unplayed old seed migrates to championship strength")
	unit.division_strength = 400
	GameSession.season_number += 1
	Rating.ensure(GameSession)
	check(b.club_elo.elo == 1000 and a.club_elo.elo == 2200, "changing championship strength or season never reseeds existing Elo")
	b.club_elo.elo = -7.0
	Rating.ensure(GameSession)
	check(b.club_elo.elo == 0, "negative legacy Elo is repaired to zero")
	GameSession.clear()
	print("Club rating: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
