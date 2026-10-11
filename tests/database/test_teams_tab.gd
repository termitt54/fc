extends Node
## Flat country/club directory: both columns list everything, reputation first.
## Run: godot --headless --path . res://tests/database/test_teams_tab.tscn

const TAB_SCENE := preload("res://scenes/world_editor/tabs/teams_tab/teams_tab.tscn")
const EDITOR_SCRIPT := preload("res://scenes/world_editor/world_editor_screen.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Teams directory tab ===")
	_assert(EDITOR_SCRIPT != null, "world editor script parses")
	if not WorldDatabase.is_ready():
		_assert(false, "world database is ready")
		_finish()
		return

	var countries: Dictionary = CountryRepository.new().get_all()
	var clubs: Dictionary = ClubRepository.new().get_all()
	_assert(countries["success"] and clubs["success"], "repositories list countries and clubs")
	var continents: Dictionary = ContinentRepository.new().get_all()
	var clubs_on_cards := 0
	for continent in continents.get("data", []):
		clubs_on_cards += int(continent.get("clubs_count", 0))
	_assert(
		continents["success"] and clubs_on_cards == (clubs["data"] as Array).size(),
		"each continent card counts its clubs (%d)" % clubs_on_cards
	)

	var tab := TAB_SCENE.instantiate()
	add_child(tab)
	var country_count := _row_count(tab, "CountryCol")
	var club_count := _row_count(tab, "ClubCol")
	_assert(country_count == (countries["data"] as Array).size(), "country column lists every country")
	_assert(club_count == (clubs["data"] as Array).size(), "club column lists every club")
	_assert(str(tab.get_node("%CountrySort").selected_id) == "reputation", "countries default to reputation")
	_assert(str(tab.get_node("%ClubSort").selected_id) == "reputation", "clubs default to reputation")
	_assert(not _create_visible(tab, "CountryCol"), "country create stays on the geography tab")
	_assert(not _create_visible(tab, "ClubCol"), "club create stays on the geography tab")

	if country_count > 0:
		var first_id := _first_row_id(tab, "CountryCol")
		var best_id := _best_reputation_id(countries["data"])
		_assert(first_id == best_id, "first country is the highest reputation")
		tab._on_country_selected(first_id)
		_assert(_row_count(tab, "ClubCol") == club_count, "picking a country does not filter clubs")

	tab.get_node("%ClubSort").selected_id = "name"
	tab._render_clubs()
	if club_count > 1:
		var ordered: Array = (clubs["data"] as Array).duplicate()
		tab._sort_rows(ordered, "name")
		_assert(_first_row_id(tab, "ClubCol") == int(ordered[0].get("id", -1)), "club sort follows the chosen field")

	var linked_id := _club_in_tournament(clubs.get("data", []))
	if linked_id > 0:
		var blocked: Dictionary = ClubRepository.new().delete(linked_id)
		_assert(not blocked["success"], "a club inside a tournament is not deleted")
		_assert(
			str(blocked.get("error", "")).find("турнир") >= 0,
			"the refusal names the tournament (%s)" % str(blocked.get("error", ""))
		)
		var still: Dictionary = ClubRepository.new().get_by_id(linked_id)
		_assert(still["success"], "the club is still in the world database")
	else:
		_assert(true, "no club is in a tournament, so nothing is deleted")

	tab.free()

	var editor := (load("res://scenes/world_editor/world_editor_screen.tscn") as PackedScene).instantiate()
	add_child(editor)
	var bar: Node = editor.get_node("%TabBar")
	var teams_button := bar.get_child(1) as Button
	_assert(bar.get_child_count() == 4, "editor has four tabs")
	_assert(teams_button.text == "Все команды", "teams tab sits after geography")
	_assert(not editor.get_node("%Teams").visible, "teams page starts hidden")
	teams_button.pressed.emit()
	_assert(editor.get_node("%Teams").visible, "teams page opens from the tab")
	_assert(not editor.get_node("%Geography").visible, "geography hides when teams is open")
	editor.free()
	_finish()


func _row_count(tab: Node, column_name: String) -> int:
	return _rows(tab, column_name).get_child_count()


func _first_row_id(tab: Node, column_name: String) -> int:
	var rows := _rows(tab, column_name)
	if rows.get_child_count() < 1:
		return -1
	return int(rows.get_child(0).entity_id)


func _rows(tab: Node, column_name: String) -> Node:
	return tab.get_node("%%%s" % column_name).get_node("VBox/EntityList/Stack/Scroll/Rows")


func _create_visible(tab: Node, column_name: String) -> bool:
	var button := tab.get_node("%%%s" % column_name).get_node("VBox/Toolbar/CreateButton")
	return button != null and button.visible


func _best_reputation_id(rows: Array) -> int:
	var best: Dictionary = rows[0]
	for row in rows:
		var reputation := int(row.get("reputation", 0))
		var best_reputation := int(best.get("reputation", 0))
		if reputation > best_reputation:
			best = row
		elif reputation == best_reputation:
			var name_cmp := str(row.get("name", "")).nocasecmp_to(str(best.get("name", "")))
			if name_cmp < 0 or (name_cmp == 0 and int(row.get("id", 0)) < int(best.get("id", 0))):
				best = row
	return int(best.get("id", -1))


func _club_in_tournament(rows: Array) -> int:
	for row in rows:
		var club_id := int(row.get("id", 0))
		if club_id < 1:
			continue
		var links: Array = DatabaseManager.query_rows(
			"SELECT 1 AS hit FROM competition_unit_clubs WHERE club_id = ? LIMIT 1;",
			[club_id]
		)
		if not links.is_empty():
			return club_id
	return -1


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % message)
	else:
		_failed += 1
		print("  FAIL  %s" % message)


func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
