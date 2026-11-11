extends Node
## Club directory: squad strength, filters, and the hub navigation.
## Run: godot --headless --path . res://tests/game/test_teams_view.tscn

const View := preload("res://scenes/game/teams_view.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Teams directory ===")
	_test_squad_and_filters()
	_test_session_rows()
	await _test_hub()
	GameSession.clear()
	print("=== Teams directory: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _test_squad_and_filters() -> void:
	var totals: Dictionary = View.squad_totals([
		{"current_ability": 80},
		{"current_ability": 60},
		"skip",
		{"overall": 40},
	])
	_assert(int(totals["total"]) == 180 and int(totals["count"]) == 3, "strength sums every player rating")
	_assert(is_equal_approx(float(totals["average"]), 60.0), "average is the mean rating")
	_assert(View.parse_bound("1 500 000") == 1500000.0, "a spaced budget is a number")
	_assert(View.parse_bound("70,5") == 70.5, "a comma is a decimal")
	_assert(View.parse_bound("") == null, "an empty bound is not a filter")
	_assert(View.money_short(2_500_000) == "2.5M €", "millions stay readable")
	_assert(View.money_full(-1200) == "-1 200 €", "the full budget keeps the sign and groups")
	_assert(View.clubs_phrase(1) == "1 клуб" and View.clubs_phrase(3) == "3 клуба" and View.clubs_phrase(11) == "11 клубов", "club counts decline")

	var rows: Array = [
		{"id": 1, "name": "Alpha United Football Club", "country_id": 4, "country_name": "Испания", "reputation": 820, "strength_total": 1800, "strength_avg": 72.5, "budget": 2_000_000},
		{"id": 2, "name": "Beta Town", "country_id": 8, "country_name": "Норвегия", "reputation": 410, "strength_total": 900, "strength_avg": 48.0, "budget": -50_000},
	]
	var rich := View.filtered(rows, "", 0, {"reputation": 800, "budget": 1_000_000})
	_assert(rich.size() == 1 and str(rich[0]["name"]) == "Alpha United Football Club", "reputation and budget filters keep the full name")
	var spain := View.filtered(rows, "испан", 0, {})
	_assert(spain.size() == 1 and int(spain[0]["id"]) == 1, "search matches the country")
	var norway := View.filtered(rows, "beta", 8, {"strength_avg": 40, "strength_total": 100})
	_assert(norway.size() == 1 and int(norway[0]["id"]) == 2, "name, country and strength filters combine")
	var ordered := View.sorted_rows(rows, "strength_total", true)
	_assert(int(ordered[0]["id"]) == 2, "ascending strength puts the smaller squad first")
	var by_name := View.sorted_rows(rows, "name", true)
	_assert(str(by_name[0]["name"]).begins_with("Alpha"), "names sort alphabetically")


func _test_session_rows() -> void:
	GameSession.clear()
	GameSession.units = [{
		"id": 1,
		"name": "League",
		"clubs_by_id": {
			1: {
				"id": 1,
				"name": "Alpha United Football Club",
				"short_name": "AFC",
				"country_id": 4,
				"reputation": 820,
				"logo_path": "",
			},
			2: {"id": 2, "name": "Beta Town", "country_id": 8, "reputation": 410},
		},
	}]
	GameSession.players_by_club = {1: [{"current_ability": 80}, {"current_ability": 70}]}
	GameSession.reserve_players_by_club = {1: [{"current_ability": 50}]}
	GameSession.youth_players_by_club = {1: [{"overall": 20}], 2: [{"current_ability": 40}]}
	GameSession.club_budgets = {1: 2_500_000, 2: -1000}
	var rows: Array = GameSession.get_club_rows()
	var by_id := {}
	for row in rows:
		by_id[int(row["id"])] = row
	_assert(by_id.has(1) and by_id.has(2), "each club is one row")
	var alpha: Dictionary = by_id[1]
	_assert(str(alpha["name"]) == "Alpha United Football Club", "the directory uses the full club name")
	_assert(int(alpha["strength_total"]) == 220 and int(alpha["player_count"]) == 4, "senior, reserve and youth ratings are added")
	_assert(is_equal_approx(float(alpha["strength_avg"]), 55.0), "the average covers every club player")
	_assert(int(alpha["reputation"]) == 820 and int(alpha["budget"]) == 2_500_000, "reputation and budget come from the club")
	_assert(int(by_id[2]["strength_total"]) == 40 and int(by_id[2]["budget"]) == -1000, "a youth-only club and a debt stay visible")


func _test_hub() -> void:
	GameSession.is_active = true
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	await get_tree().process_frame
	var select_h: float = screen.get_node("%TournamentSelect").get_node("%Chrome").custom_minimum_size.y
	var track_h: float = screen.get_node("%NavTrack").custom_minimum_size.y
	_assert(is_equal_approx(select_h, track_h) and select_h >= 36.0, "the league select and the nav share one height")
	var link_h := -1.0
	for node_name in ["TeamsLink", "PlayersLink", "MarketLink", "TransfersLink", "CoachesLink"]:
		var button: Control = screen.get_node("%" + node_name)
		if link_h < 0.0:
			link_h = button.custom_minimum_size.y
		_assert(is_equal_approx(button.custom_minimum_size.y, link_h), node_name + " matches the other nav buttons")
	_assert(str(screen.get_node("%TeamsLink").text) == "Команды", "teams is a nav button")
	screen._toggle_directory("teams")
	await get_tree().process_frame
	_assert(screen._teams_view.visible and screen._directory_mode == "teams", "the teams page opens")
	var found_name := false
	for label in _labels(screen._teams_view):
		if label.text == "Alpha United Football Club":
			found_name = true
			_assert(label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING, "the club name is not ellipsized")
	_assert(found_name, "the open page shows the full club name")
	var reputation_header := _button_starting(screen._teams_view, "Репутация")
	_assert(reputation_header != null, "the reputation column is sortable")
	reputation_header.pressed.emit()
	var sorted_names := _club_names(screen._teams_view)
	_assert(sorted_names == ["Beta Town", "Alpha United Football Club"], "a second click sorts reputation upward")
	var resorted := _button_starting(screen._teams_view, "Репутация")
	_assert(resorted != null and str(resorted.text).ends_with("▲"), "the column shows the new direction")
	var reputation_filter: LineEdit = screen._teams_view._bound_inputs["reputation"]
	reputation_filter.text = "800"
	reputation_filter.text_changed.emit("800")
	await get_tree().process_frame
	var visible_names: Array = []
	for label in _labels(screen._teams_view):
		if label.text == "Alpha United Football Club" or label.text == "Beta Town":
			visible_names.append(label.text)
	_assert(visible_names == ["Alpha United Football Club"], "the reputation filter hides the weaker club")
	GameSession.national_teams = {4: {"country": {"id": 4, "name": "National directory test", "reputation": 800, "youth_talent": 85}, "coach": {"name": "Test coach"}}}
	screen.get_node("%NationalRatingLink").pressed.emit()
	await get_tree().process_frame
	_assert(screen._teams_view.visible and screen._teams_view._elo_mode and not screen._teams_view._national, "header opens club Elo tab")
	_assert(screen._teams_view._rows.size() == 2 and screen._teams_view._rows[0].has("elo"), "club Elo tab shows club data")
	screen._teams_view._tabs.tab_selected.emit(1)
	_assert(screen._teams_view._national and screen._teams_view._rows.size() == 1, "rating tabs switch to national teams")
	screen.get_node("%TeamsLink").pressed.emit()
	_assert(not screen._teams_view._national, "teams header returns to clubs")
	screen._teams_view.set_national(true)
	_assert(screen._directory_mode == "teams" and not screen._teams_view._elo_mode and screen._teams_view._sort_key == "reputation", "national directory is separate from Elo")
	_assert(_button_starting(screen._teams_view, "Репутация") != null and _button_starting(screen._teams_view, "Elo") == null, "national directory shows reputation columns only")
	screen.get_node("%NationalRatingLink").pressed.emit()
	_assert(screen._directory_mode == "ratings" and screen._teams_view._elo_mode, "Elo has its own navigation route")
	screen.queue_free()
	await get_tree().process_frame


func _club_names(node: Node) -> Array:
	var names: Array = []
	for label in _labels(node):
		if label.text == "Alpha United Football Club" or label.text == "Beta Town":
			names.append(label.text)
	return names


func _button_starting(node: Node, prefix: String) -> Button:
	if node is Button and str(node.text).begins_with(prefix):
		return node
	for child in node.get_children():
		var found := _button_starting(child, prefix)
		if found != null:
			return found
	return null


func _labels(node: Node) -> Array:
	var found: Array = []
	if node is Label:
		found.append(node)
	for child in node.get_children():
		found.append_array(_labels(child))
	return found


func _assert(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error(message)
		print("FAIL: " + message)
