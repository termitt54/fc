extends Node

const NationalRatingScript = preload("res://game/national_rating.gd")

var passed := 0
var failed := 0

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void:
	call_deferred("run")

func team(id: int, talent: int = 80) -> Dictionary:
	return {"country": {"id": id, "name": "Country %d" % id, "reputation": 800,
		"youth_talent": talent}, "coach": {"name": "Coach"}, "squad_ids": []}

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	check(is_equal_approx(NationalRatingScript.expected(1600, 1600), 0.5), "equal teams")
	check(is_equal_approx(NationalRatingScript.expected(1600, 1000), 10.0 / 11.0), "FIFA divisor 600")
	check(absf(NationalRatingScript.adjustment(1300, 1500, 1, 25, false) - 17.074649) < 0.0001, "official FIFA example")
	check(NationalRatingScript.adjustment(1800, 1200, 0, 60, true) == 0, "no negative knockout points")
	GameSession.clear()
	GameSession.season_number = 1
	GameSession.national_teams = {1: team(1), 2: team(2)}
	var a := NationalTeams.team_id(1)
	var b := NationalTeams.team_id(2)
	var unit := {"id": 90, "national": true, "international_started": true,
		"clubs_by_id": {a: NationalTeams.identity(GameSession.national_teams[1].country), b: NationalTeams.identity(GameSession.national_teams[2].country)},
		"matches": [], "playoff": {"enabled": true, "finished": false, "teams": 16, "series": [{"id": 1, "round": 1}, {"id": 2, "round": 2}]}}
	GameSession.units = [unit]
	NationalRatingScript.ensure(GameSession)
	var row := {"id": 1, "home_id": a, "away_id": b, "home_goals": 3, "away_goals": 1, "played": true}
	NationalRatingScript.record(GameSession, unit, row)
	check(is_equal_approx(GameSession.national_teams[1].rating.elo, 1785.0), "win adds 25")
	check(is_equal_approx(GameSession.national_teams[2].rating.elo, 1735.0), "group loss subtracts 25")
	NationalRatingScript.record(GameSession, unit, row)
	check(GameSession.national_teams[1].rating.games == 1, "same match counted once")
	check(GameSession.national_teams[1].country.reputation > 800, "reputation follows results")
	var reputation_row: Dictionary = NationalRatingScript.rows(GameSession).filter(func(r): return int(r.country_id) == 1)[0]
	check(int(reputation_row.reputation_change) == int(reputation_row.reputation) - 800 and float(reputation_row.change) == 25.0, "reputation delta is tracked separately from Elo delta")
	check(float(unit.clubs_by_id[a].elo) == float(GameSession.national_teams[1].rating.elo), "draw identity synced")
	check(NationalRatingScript.importance(unit, {"stage": "PLAYOFF", "series_id": 1}) == 50, "round of 16 importance")
	check(NationalRatingScript.importance(unit, {"stage": "PLAYOFF", "series_id": 2}) == 60, "quarterfinal importance")
	GameSession.national_teams[1].rating.elo = 1600.0
	GameSession.national_teams[2].rating.elo = 1600.0
	var shootout := {"id": 2, "stage": "PLAYOFF", "series_id": 2, "home_id": a, "away_id": b,
		"home_goals": 2, "away_goals": 2, "played": true, "winner_id": a, "shootout": {"home": 4, "away": 3}}
	NationalRatingScript.record(GameSession, unit, shootout)
	check(GameSession.national_teams[1].rating.elo == 1615, "shootout winner earns half-win")
	check(GameSession.national_teams[2].rating.elo == 1600, "shootout loser draw points")
	check(is_equal_approx(float(GameSession.national_teams[1].rating.talent_elo)+float(GameSession.national_teams[2].rating.talent_elo),3520.0), "talent reference stays zero-sum despite knockout point inflation")
	check(float(GameSession.national_teams[1].rating.talent_elo)<1776.0, "shootout draw lowers overestimated favourite in talent reference")
	var before_prestige := int(GameSession.national_teams[1].country.reputation)
	NationalRatingScript.sync_identity(GameSession, a)
	before_prestige = int(GameSession.national_teams[1].country.reputation)
	for t in GameSession.national_teams.values(): t.rating.elo += 100.0
	NationalRatingScript.sync_identity(GameSession, a)
	check(int(GameSession.national_teams[1].country.reputation) == before_prestige, "common Elo inflation does not inflate prestige")
	for t in GameSession.national_teams.values(): t.rating.elo -= 100.0
	var draw_rng := RandomNumberGenerator.new()
	draw_rng.seed = 51
	var groups := InternationalDraw.draw({1: {"elo": 2000, "reputation": 100}, 2: {"elo": 1900, "reputation": 100}, 3: {"elo": 1000, "reputation": 900}, 4: {"elo": 900, "reputation": 900}}, 2, {"mode": InternationalDraw.REPUTATION}, draw_rng)
	check(groups.all(func(g): return (g.club_ids as Array).filter(func(id): return id in [1, 2]).size() == 1), "pots use Elo rather than old prestige")
	var snapshots := var_to_bytes(GameSession.national_teams)
	var restored: Dictionary = bytes_to_var(snapshots)
	check(restored[1].rating.history.size() == 2 and restored[1].rating.games == 2, "rating survives binary save codec")
	# SaveStore itself must retain nested rating data without new database columns.
	SaveStore.database_path_override = "user://national-rating-test.db"
	var sections := {}
	for key in SaveStore.SECTIONS: sections[key] = [] if key in ["units", "free_agents", "transfer_log"] else {}
	sections.national_teams = restored
	check(SaveStore.new().write_slot("rating_test", {"version": 15}, sections).success, "SQLite rating save")
	var loaded := SaveStore.new().load_slot("rating_test")
	check(loaded.success and loaded.data.national_teams[1].rating.elo == 1615, "SQLite rating load")
	SaveStore.database_path_override = ""
	# Legacy data is migrated without rerolling or replaying old results.
	unit.erase("national_rating")
	unit.matches = [row]
	row.erase("elo_counted")
	NationalRatingScript.ensure(GameSession)
	check(row.elo_counted, "legacy played match excluded")
	var history_size: int = restored[1].rating.history.size()
	NationalRatingScript.ensure(GameSession)
	check(restored[1].rating.history.size() == history_size, "migration repeat safe")
	var extraordinary := {"youth_talent": 85}
	var rating := {"trend": 0.0}
	for edition in 25: NationalRatingScript.advance_talent(extraordinary, rating, 2.5, (edition + 1) * 2)
	var gain := int(extraordinary.youth_talent) - 85
	check(gain >= 5 and gain <= 7, "exceptional +5..7 in 50 seasons")
	print("Exceptional 50-season talent gain: ", gain)
	var annual := {"youth_talent": 85}
	var annual_state := {"trend": 0.0, "last_talent_evaluation": 0}
	for edition in 50: NationalRatingScript.advance_talent(annual, annual_state, 2.5, edition + 1)
	check(int(annual.youth_talent) - 85 >= 5 and int(annual.youth_talent) - 85 <= 7, "annual cups do not double talent growth")
	print("Annual exceptional 50-season talent gain: ", int(annual.youth_talent) - 85)
	var rise := {"youth_talent": 70}
	var rise_state := {"trend": 0.0}
	var fall := {"youth_talent": 85}
	var fall_state := {"trend": 0.0}
	var stable := {"youth_talent": 75}
	var stable_state := {"trend": 0.0}
	for edition in 500:
		NationalRatingScript.advance_talent(rise, rise_state, 2.5, edition * 2)
		NationalRatingScript.advance_talent(fall, fall_state, -0.6, edition * 2)
		NationalRatingScript.advance_talent(stable, stable_state, 0.0, edition * 2)
	check(rise.youth_talent == 100, "70 can reach 100 without baseline cap")
	check(fall.youth_talent <= 60, "85 can fall below 60")
	check(stable.youth_talent == 75, "no automatic seasonal drift")
	check(rise_state.talent_history.size() <= 128, "bounded talent history")
	# 500 independent fair-result trajectories, 25 editions each. No forced
	# growth: inspect stochastic drift over the same 50-season horizon.
	var rng := RandomNumberGenerator.new()
	rng.seed = 51009
	var deltas: Array = []
	for sample in 500:
		var c := {"youth_talent": 80}
		var r := {"trend": 0.0}
		for edition in 25:
			var residual := 0.0
			for match_index in 6: residual += (1.0 if rng.randf() < 0.5 else 0.0) - 0.5
			NationalRatingScript.advance_talent(c, r, residual / sqrt(6.0) * 2.0, edition * 2)
		deltas.append(int(c.youth_talent) - 80)
	check(deltas.max() < 5 and deltas.min() > -5, "ordinary random results do not mimic exceptional +5..7 path")
	print("Fair 50-season trajectories: min=", deltas.min(), " max=", deltas.max())
	var once := {"youth_talent": 80}
	NationalRatingScript.advance_talent(once, {"trend": 0.0}, 2.5, 1)
	check(once.youth_talent == 80, "one miracle does not change talent")
	# Completion is applied once, and fewer than three tracked matches are skipped.
	NationalRatingScript.begin_edition(GameSession, unit)
	unit.national_rating.participants[a].games = 3
	unit.national_rating.participants[a].residual = 2.0
	unit.national_rating.participants[b].games = 8
	unit.national_rating.participants[b].residual = -2.0
	GameSession.national_teams[1].rating.trend=0.0
	GameSession.national_teams[2].rating.trend=0.0
	unit.playoff.finished = true
	NationalRatingScript.close_completed(GameSession)
	check(is_zero_approx(float(GameSession.national_teams[1].rating.trend)+float(GameSession.national_teams[2].rating.trend)),"different knockout path lengths do not bias mirrored evidence")
	var trend: float = GameSession.national_teams[1].rating.trend
	NationalRatingScript.close_completed(GameSession)
	check(is_equal_approx(trend, GameSession.national_teams[1].rating.trend), "edition evaluated once")
	var rows := NationalRatingScript.rows(GameSession)
	check(rows.size() == 2 and rows[0].has("rank") and rows[0].has("talent"), "national directory data")
	var view = load("res://scenes/game/teams_view.tscn").instantiate()
	add_child(view)
	view.set_national(true)
	check(view._rows.size() == 2 and view._sort_key == "reputation" and not view._elo_mode, "national teams tab shows reputation")
	check(view._rows[0].has("reputation_change"), "reputation change available")
	view.set_national(true, true)
	check(view._sort_key == "elo" and view._tabs.visible, "rating page exposes clubs and national tabs")
	view.set_national(false)
	check(view._sort_key == "reputation", "club tab restored")
	view.queue_free()
	GameSession.clear()
	print("National rating: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
