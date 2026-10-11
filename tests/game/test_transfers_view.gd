extends Node
## The transfer list keeps one row per signing and orders it by fee.
## Run: godot --headless --path . res://tests/game/test_transfers_view.tscn

const View := preload("res://scenes/game/transfers_view.gd")

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Transfer list ===")
	var screen: PackedScene = load("res://scenes/game/game_screen.tscn")
	_assert(screen != null, "game screen scene loads the transfers page")
	_test_one_row_per_signing_dearest_first()
	_test_season_filter()
	_test_page_window()
	_finish()


func _test_one_row_per_signing_dearest_first() -> void:
	var log: Array = [
		_deal("in", 1, "Дешёвый", 500_000),
		_deal("out", 1, "Дешёвый", 500_000),
		_deal("bid", 1, "Ставка", 9_000_000),
		_deal("in", 2, "Дорогой", 4_000_000),
		_deal("in", 1, "Бесплатный", 0),
	]
	var rows := View.deal_rows(log, View.ALL_SEASONS)
	View.sort_deals(rows, "fee", false)
	_assert(rows.size() == 3, "bids and the seller line are not a second transfer")
	_assert(str(rows[0].get("player_name", "")) == "Дорогой", "the dearest signing is first")
	_assert(int(rows[0].get("fee", 0)) == 4_000_000, "fee is kept")
	_assert(str(rows[2].get("player_name", "")) == "Бесплатный", "a free signing stays at the bottom")


func _test_season_filter() -> void:
	var log: Array = [
		_deal("in", 1, "Старый", 2_000_000),
		_deal("in", 3, "Новый", 100_000),
	]
	var season_3 := View.deal_rows(log, 3)
	_assert(season_3.size() == 1 and str(season_3[0].get("player_name", "")) == "Новый", "season filter keeps that season")
	var options := View._season_options(log, 3)
	_assert(str(options[0].get("label", "")) == "Все сезоны", "all seasons is the first filter")
	_assert(options.size() == 3, "both seasons are offered after all seasons")


func _test_page_window() -> void:
	const Page := preload("res://game/list_page.gd")
	const Players := preload("res://scenes/game/world_players_view.gd")
	var sample: Array = []
	for i in 250:
		sample.append({"n": i})
	_assert(Page.slice_of(sample, 0).size() == 100, "first page holds 100")
	_assert(Page.slice_of(sample, 2).size() == 50, "the last page keeps the remainder")
	_assert(Page.label(1, 250) == "101–200 из 250", "the label names the window")
	_assert(Page.count(100) == 1, "exactly 100 rows is one page")
	_assert(Page.count(101) == 2, "the 101st row opens the next page")

	var transfers := View.new()
	add_child(transfers)
	for i in 250:
		transfers._rows.append(_deal("in", 1, "Игрок %d" % i, i))
	transfers._rebuild_list()
	_assert(transfers._list_host.get_child_count() == 100, "transfers draw 100 rows")
	_assert(transfers._pager.visible, "the transfer pager shows past 100")
	transfers._page = 2
	transfers._rebuild_list()
	_assert(transfers._list_host.get_child_count() == 50, "the last transfer page is the remainder")
	_assert(transfers._page_next.disabled, "the last page has no next")
	transfers._rows = transfers._rows.slice(0, 40)
	transfers._page = 4
	transfers._rebuild_list()
	_assert(transfers._list_host.get_child_count() == 40, "a short transfer list stays whole")
	_assert(not transfers._pager.visible, "the transfer pager hides inside one page")

	var players := Players.new()
	add_child(players)
	for i in 180:
		players._rows.append({
			"name": "Игрок %d" % i,
			"position": "ST",
			"age": 20,
			"ca": 70,
			"pa": 80,
			"club_id": 0,
			"country_id": 0,
		})
	players._rebuild_list()
	_assert(players._list_host.get_child_count() == 100, "players draw 100 rows")
	_assert(players._pager.visible, "the player pager shows past 100")
	players.set_mode(players.MODE_MARKET)
	players._page = 1
	players._rebuild_list()
	_assert(players._list_host.get_child_count() == 80, "the market uses the same page size")
	_assert(players._page_prev.disabled == false, "the second page can go back")


func _deal(direction: String, season: int, player_name: String, fee: int) -> Dictionary:
	return {
		"direction": direction,
		"season": season,
		"day": 1,
		"player_id": fee + season,
		"player_name": player_name,
		"position": "ST",
		"club_id": 4,
		"club_name": "Покупатель",
		"other_club": "Продавец",
		"fee": fee,
	}


func _assert(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % label)
	else:
		_failed += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
