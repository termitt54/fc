extends Node

const STORE := preload("res://game/save_store.gd")
const PATH := "user://tests/tournament_history/games.db"
var passed := 0
var failed := 0

func check(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	if not ProjectSettings.globalize_path("user://").contains("fc-load-benchmark"):
		get_tree().quit(1)
		return
	STORE.database_path_override = PATH
	cleanup()
	var unit := fixture()
	check(GameSession.apply_save_payload(payload(unit, 1))["success"], "Completed season loads")
	check(GameSession._flush_history()["success"], "Completed tournament archives")
	var head := int(GameSession.history_head)
	var record := STORE.new().tournament_season(head, 91, 1)
	check(record["success"] and not record["data"].is_empty(), "Edition loads by indexed key and history branch")
	if not record["success"] or record["data"].is_empty():
		get_tree().quit(1)
		return
	var saved: Dictionary = record["data"]
	check(saved["matches"].size() == 6 and saved["standings"].size() == 4, "Archive retains regular games, standings and all playoff games")
	check(saved["playoff"]["series"].size() == 4 and saved["winners"][0]["playoff"].size() == 4, "Archive retains bracket, bronze and final places")
	check(not saved["matches"][0].has("report"), "Heavy match reports are excluded")
	check(UnitSeasonStats.leaders(saved, "goals")[0]["name"] == "Historic Striker", "Historical scorers own their names")
	GameSession.units[0]["standings"][0]["points"] = 999
	GameSession.units[0][UnitSeasonStats.KEY][700]["name"] = "Changed now"
	check(STORE.new().tournament_season(head, 91, 1)["data"]["standings"][0]["points"] != 999, "Archive is immutable when live tables change")
	check(GameSession._flush_history()["success"] and int(GameSession.history_head) == head, "Edition archives only once")
	var next := GameSession._reset_unit_for_new_season(unit)
	var state := payload(next, 2)
	state["history_head"] = head
	check(GameSession.apply_save_payload(state)["success"], "Next season reads same archive head")
	check(GameSession.save_game("zz_tournament_a")["success"], "Branch A saves")
	check(GameSession.get_tournament_season(91, 1)["data"]["season"] == 1, "Past edition reads after current season resets")
	var second := fixture()
	second[UnitSeasonStats.KEY][700]["goals"] = 19
	state = payload(second, 2)
	state["history_head"] = head
	GameSession.apply_save_payload(state)
	check(GameSession._flush_history()["success"], "Branch B adds second season")
	var head_b := int(GameSession.history_head)
	check(GameSession.save_game("zz_tournament_b")["success"], "Branch B saves")
	check(GameSession.load_game("zz_tournament_a")["success"], "Older branch reloads")
	check(GameSession.get_tournament_season(91, 2)["data"].get("season", 0) == 2, "Current unsimulated season is an independent live snapshot")
	check(STORE.new().tournament_season(int(GameSession.history_head), 91, 2)["data"].is_empty(), "Old branch cannot see future archived edition")
	second = fixture()
	second[UnitSeasonStats.KEY][700]["goals"] = 31
	state = payload(second, 2)
	state["history_head"] = head
	GameSession.apply_save_payload(state)
	check(GameSession._flush_history()["success"], "Branch C writes alternate second season")
	var head_c := int(GameSession.history_head)
	check(STORE.new().tournament_season(head_b, 91, 2)["data"][UnitSeasonStats.KEY][700]["goals"] == 19, "Branch B keeps original scorer total")
	check(STORE.new().tournament_season(head_c, 91, 2)["data"][UnitSeasonStats.KEY][700]["goals"] == 31, "Branch C sees its own scorer total")
	check(GameSession.start_new_season()["success"], "Actual new-season transition succeeds")
	check(GameSession.get_tournament_season(91, 2)["data"]["matches"].size() == 6, "Actual new-season transition retains closed edition")
	var career: Dictionary = GameSession.career_player_stats(GameSession.units[0])
	var career_goals := 0
	if career.get("ok", false):
		career_goals = int(career.get("bag", {}).get(700, {}).get("goals", 0))
	check(career.get("ok", false) and career_goals == 37, "All-time scoring adds the closed seasons without counting the new empty season")
	test_rollback(head_c)
	await test_ui(saved)
	test_long_archive()
	GameSession.clear()
	STORE.database_path_override = ""
	cleanup()
	print("Tournament history: %d passed, %d failed" % [passed, failed])
	get_tree().quit(1 if failed else 0)

func cleanup() -> void:
	for suffix in ["", "-wal", "-shm"]:
		var path := ProjectSettings.globalize_path(PATH + suffix)
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)

func payload(unit: Dictionary, season: int) -> Dictionary:
	return {"version": GameSession.SAVE_VERSION, "season_number": season, "season_day": 8, "season_finished": PlayoffManager.is_unit_season_complete(unit), "units": [unit.duplicate(true)], "players_by_club": {}}

func fixture() -> Dictionary:
	var unit := {"id": 91, "label": "Archive test", "competition_type": "DIVISIONS", "rules": {"divisions_count": 2, "teams_per_division": 2, "matches_vs_own": 1, "teams_promote": 0, "teams_relegate": 0}, "clubs_by_id": {}, "divisions": [{"index": 0, "club_ids": [1, 2]}, {"index": 1, "club_ids": [3, 4]}], "standings": [], "matches": [], "playoff": {"enabled": true, "teams": 4, "format": "SINGLE", "scope": "PER_DIVISION", "third_place": true, "seeding": "OVERALL_TABLE"}, "winners": []}
	for id in range(1, 5):
		unit["clubs_by_id"][id] = {"id": id, "name": "Historic club %d" % id, "reputation": 500}
		unit["standings"].append({"club_id": id, "division": int((id - 1) / 2), "played": 1, "won": 1 if id % 2 else 0, "drawn": 0, "lost": 0 if id % 2 else 1, "goals_for": 2 if id % 2 else 0, "goals_against": 0 if id % 2 else 2, "goal_diff": 2 if id % 2 else -2, "points": 3 if id % 2 else 0})
	for i in 2:
		unit["matches"].append({"id": i + 1, "season_day": 1, "home_id": i * 2 + 1, "away_id": i * 2 + 2, "home_goals": 2, "away_goals": 0, "played": true, "stage": "REGULAR", "report": {"heavy": "unused"}})
	var started := PlayoffManager.maybe_start(unit, 1, 10)
	var next_id: int = started["next_match_id"]
	for day in range(2, 5):
		for row in unit["matches"]:
			if not row["played"]:
				row["played"] = true
				row["home_goals"] = 3
				row["away_goals"] = 1
		var result := PlayoffManager.after_day_simulated(unit, day, next_id, 1)
		next_id = result["next_match_id"]
	unit[UnitSeasonStats.KEY] = {700: {"player_id": 700, "club_id": 1, "name": "Historic Striker", "position": "ST", "goals": 6, "assists": 2, "matches": 3, "rating_sum": 24.0}}
	return unit

func test_rollback(head: int) -> void:
	var db = ClassDB.instantiate("SQLite")
	db.path = ProjectSettings.globalize_path(PATH)
	db.verbosity_level = 0
	check(db.open_db(), "Fault-injection connection opens")
	check(db.query("CREATE TRIGGER fail_tournament BEFORE INSERT ON save_history_tournaments BEGIN SELECT RAISE(FAIL, 'forced tournament failure'); END;"), "Archive failure trigger created")
	var state := payload(fixture(), 3)
	state["history_head"] = head
	GameSession.apply_save_payload(state)
	check(not GameSession._flush_history()["success"], "Archive insert failure is reported")
	check(int(GameSession.history_head) == head and not GameSession._pending_history.is_empty(), "Failed archive keeps old head and pending snapshot")
	check(STORE.new().tournament_season(head, 91, 3)["data"].is_empty(), "Failed archive leaves no visible partial edition")
	check(db.query("DROP TRIGGER fail_tournament;"), "Failure trigger removed")
	db.close_db()
	check(GameSession._flush_history()["success"], "Pending archive retries successfully")
	check(not STORE.new().tournament_season(int(GameSession.history_head), 91, 3)["data"].is_empty(), "Retried archive is readable")

func test_ui(unit: Dictionary) -> void:
	GameSession.is_active = true
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var series: Dictionary = unit["playoff"]["series"][0]
	var card: Control = screen._playoff_series_card(unit, unit["playoff"], series, false)
	add_child(card)
	check(card.get_meta("home_row").get_meta("score").text == "3" and card.get_meta("away_row").get_meta("score").text == "1", "Single-game card displays match score 3:1, not series wins 1:0")
	var scheduled := series.duplicate(true)
	scheduled["games_played"] = 0
	scheduled["complete"] = false
	screen._apply_playoff_card(card, unit, unit["playoff"], scheduled)
	check(card.get_meta("home_row").get_meta("score").text == "—", "Unplayed single game has no invented 0:0 score")
	var playoff: Dictionary = unit["playoff"].duplicate(true)
	playoff["format"] = "BEST_OF"
	screen._apply_playoff_card(card, unit, playoff, series)
	check(card.get_meta("home_row").get_meta("score").text == "1", "Best-of series keeps win count")
	playoff["format"] = "TWO_LEGGED"
	screen._apply_playoff_card(card, unit, playoff, series)
	check(card.get_meta("home_row").get_meta("score").text == "3", "Two-legged tie keeps aggregate goals")
	screen._apply_playoff_card(card, unit, unit["playoff"], series)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	card.gui_input.emit(click)
	await get_tree().process_frame
	var dialog: Control = screen.get_node_or_null("SeasonHistoryDialog")
	check(dialog != null and dialog.visible, "Clicking a tie opens match results")
	if dialog != null:
		var rows: Array = dialog.get("_calendar_rows")
		check(rows.size() == 1 and TournamentHistory.score(rows[0]) == "3 : 1", "Match-results window shows actual match score")
		dialog.free()
	var multi := unit.duplicate(true)
	var return_leg: Dictionary = TournamentHistory.series_matches(unit, series)[0].duplicate(true)
	return_leg["id"] = 900
	return_leg["game_index"] = 2
	return_leg["home_id"] = series["away_id"]
	return_leg["away_id"] = series["home_id"]
	return_leg["home_goals"] = 2
	return_leg["away_goals"] = 5
	multi["matches"].append(return_leg)
	screen._show_series_results(multi, series)
	dialog = screen.get_node_or_null("SeasonHistoryDialog")
	check(dialog != null and dialog.get("_calendar_rows").size() == 2, "Series results include every match")
	if dialog != null:
		check(dialog.get("_calendar_rows")[1]["home_id"] == series["away_id"] and TournamentHistory.score(dialog.get("_calendar_rows")[1]) == "2 : 5", "Return match keeps its own home/away score orientation")
		dialog.free()
	card.free()
	screen._clear_content()
	screen._history_tab = 1
	screen._build_history_view(unit)
	var season_labels := screen.get_node("%Content").find_children("*", "Label", true, false).filter(func(label): return label.text == "Сезон 1")
	check(not season_labels.is_empty(), "Season labels remain in history table")
	if not season_labels.is_empty():
		season_labels[0].gui_input.emit(click)
	await get_tree().process_frame
	dialog = screen.get_node_or_null("SeasonHistoryDialog")
	check(dialog != null and dialog.get("_tabs").get_tab_count() == 4, "Season opens four history tabs")
	if dialog != null:
		for i in range(1, 4):
			dialog.get("_tabs").current_tab = i
			await get_tree().process_frame
		check(dialog.find_children("*", "Control", true, false).filter(func(node): return node.has_meta("history_board")).size() >= 8, "Historical tables, statistic boards and match calendar build")
		check(dialog.find_children("*", "Tree", true, false).is_empty() and not dialog.get("_tabs").tabs_visible, "History uses shared project tables and custom tabs, not native table chrome")
		check(dialog.find_children("*", "PlayoffBracketView", true, false).size() == 1, "Archived bracket builds without switching live tournament")
		dialog.free()
	var penalties := {"played": true, "home_goals": 2, "away_goals": 2, "shootout": {"home": 4, "away": 5}, "extra_time": true}
	check(TournamentHistory.score(penalties) == "2 : 2 (пен. 4 : 5)", "Penalties stay separate from match goals")
	screen._open_history_season({"id": 91, "label": "Legacy", "winners": [{"season": 19, "club_id": 2, "club_name": "Old winner"}]}, 19)
	await get_tree().process_frame
	dialog = screen.get_node_or_null("SeasonHistoryDialog")
	check(dialog != null and dialog.get("_unit").get("archive_missing", false), "Legacy season opens honest incomplete-history view")
	if dialog != null:
		var labels := dialog.find_children("*", "Label", true, false)
		check(labels.any(func(label): return label.text == "Old winner"), "Old champion-only record remains visible")
		dialog.free()
	screen.free()

func test_long_archive() -> void:
	var base := TournamentHistory.snapshot(fixture(), 1)
	var head := 0
	var start := Time.get_ticks_usec()
	for season in range(1, 102):
		var batch: Array = []
		for unit_id in range(201, 211):
			var unit: Dictionary = base.duplicate(true)
			unit["id"] = unit_id
			unit["season"] = season
			batch.append({"kind": "tournament_season", "unit_id": unit_id, "season": season, "unit": unit})
		var result := STORE.new().append_history(head, batch)
		if not result["success"]:
			check(false, "101-season archive writes")
			return
		head = int(result["data"]["history_head"])
	var write_ms := float(Time.get_ticks_usec() - start) / 1000.0
	start = Time.get_ticks_usec()
	var oldest := STORE.new().tournament_season(head, 201, 1)
	var read_ms := float(Time.get_ticks_usec() - start) / 1000.0
	check(oldest["success"] and oldest["data"].get("season", 0) == 1, "Season 1 remains readable after 101 seasons across ten tournaments")
	check(oldest["data"]["matches"].size() == 6 and UnitSeasonStats.leaders(oldest["data"], "goals")[0]["name"] == "Historic Striker", "Long archive retains complete season data and scorers")
	check(GameSession.units.size() == 1 and not GameSession.units[0].has("season_archive"), "Archive growth does not populate active simulation with old seasons")
	print("Archive benchmark: 1010 editions, write %.1f ms, one oldest edition read %.2f ms" % [write_ms, read_ms])
