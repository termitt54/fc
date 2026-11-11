extends Node
const History = preload("res://game/club_transfer_history.gd")
const Market = preload("res://game/player_market.gd")
const Transfers = preload("res://scenes/game/transfers_view.gd")
const Dialog = preload("res://scenes/game/club_transfers_dialog.gd")
var passed := 0
var failed := 0

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", label)

func entry(direction: String, fee: int, season: int = 3, id: int = 1) -> Dictionary:
	return {"club_id": id, "club_name": "Наш клуб", "other_club": "Гости", "season": season,
		"day": -3, "player_id": 45, "player_name": "Игрок Архивный", "position": "CM", "direction": direction, "fee": fee}

func run() -> void:
	GameSession.clear()
	var log := [entry("in", 2500000), entry("out", 4000000), entry("in", 0),
		entry("bid", 999999999), entry("out", 0, 2), entry("in", 10000000, 3, 2)]
	var rows := History.rows(log, 1)
	check(rows.size() == 5, "only this club's entries, no mirrored double count")
	var stats := History.summary(rows)
	check(stats.incoming == 2 and stats.outgoing == 2 and stats.bids == 1, "directions remain separate")
	check(stats.spent == 2500000 and stats.earned == 4000000 and stats.balance == 1500000, "bids never enter cash totals")
	check(stats.paid_percent == 50 and stats.average_purchase == 2500000, "paid share counts actual arrivals and mean counts paid purchases")
	check(stats.record_purchase == 2500000 and stats.record_sale == 4000000, "records exclude rejected bid")
	check(History.rows(log, 1, {"season": 2}).size() == 1, "season filter")
	check(History.rows(log, 1, {"direction": "out"}).size() == 2, "outgoing filter")
	check(History.rows(log, 1, {"payment": "free"}).size() == 2, "free filter")
	check(History.rows(log, 1, {"position": "CB"}).is_empty(), "position filter")
	check(History.rows(log, 1, {"query": "гОсТи"}).size() == 5, "opponent case-insensitive search")
	check(History.rows(log, 1, {"query": "архивный"}).size() == 5, "archived player's historical name is searchable")
	check(History.rows(log, 1, {"min_fee": 3000000, "max_fee": 5000000}).size() == 1, "fee bounds combine")
	check(History.rows(log, 1, {"season": 3, "direction": "in", "payment": "paid", "position": "CM"}).size() == 1, "combined filters")
	check(rows[1].from == "Наш клуб" and rows[1].to == "Гости" and rows[1].to_club_id == 0, "outgoing does not link destination to seller")
	check(Transfers.deal_rows(log, 0).size() == 3, "global directory still shows arrivals only")
	check(History.summary([]).paid_percent == 0, "empty history safe")
	var player := {"value": 1000000, "asking_price": 1300000, "wage": 12300, "current_ability": 60, "age": 24}
	Market.migrate_value(player)
	check(player.value == 2500000 and player.asking_price == 3250000, "old value and asking price migrate x2.5")
	Market.migrate_value(player)
	check(player.value == 2500000 and player.asking_price == 3250000 and player.wage == 12300, "migration is idempotent and preserves salary")
	check(log[0].fee == 2500000 and log[1].fee == 4000000, "historic deal fees remain unchanged")
	var old_enabled := NativeSimulation.enabled
	for age in [18, 22, 26, 29, 32, 36]:
		for ca in [35, 55, 75, 90]:
			NativeSimulation.enabled = true
			var native_value := Market.value_for(ca, 95, age, 650)
			NativeSimulation.enabled = false
			var reference := Market.value_for(ca, 95, age, 650)
			check(native_value == reference, "C++/GDScript pricing parity")
			var effective: float = float(ca) + (95.0 - float(ca)) * Market._band(Market.POTENTIAL_AGE_BANDS, Market.POTENTIAL_AGE_TAIL, age)
			var old_multiple := Market._band(Market.VALUE_AGE_BANDS, Market.VALUE_AGE_TAIL, age) / 2.5
			var old_value := maxi(3000, Market._round_to(Market.wage_for(effective, 650, age) * old_multiple, 1000))
			check(absf(reference - float(old_value) * 2.5) <= 1750, "new appraisal remains x2.5 within euro rounding")
	NativeSimulation.enabled = old_enabled
	GameSession.transfer_log = log
	var modal := preload("res://ui/components/we_modal.tscn").instantiate()
	modal.set_script(Dialog)
	add_child(modal)
	modal.show_club(1, "Наш клуб")
	var view: Variant = modal.transfer_view
	check(modal.visible and view._rows.size() == 5, "club dialog opens complete history")
	check(view._stats_host.get_child_count() == 2, "summary cards and record line rendered")
	view._filters.direction = "in"
	view._filters.payment = "paid"
	view.refresh()
	check(view._rows.size() == 1, "UI refresh applies selected filters")
	view._filters.direction = "all"
	view._filters.payment = "all"
	for field in view.find_children("*", "LineEdit", true, false):
		if field.placeholder_text == "Сумма от, €":
			field.text_changed.emit("3 000 000")
	check(view._rows.size() == 2, "manual minimum fee is connected to the correct filter")
	for field in view.find_children("*", "LineEdit", true, false):
		if field.placeholder_text == "Сумма до, €":
			field.text_changed.emit("5 000 000")
	check(view._rows.size() == 1 and view._rows[0].direction == "out", "manual maximum fee combines with minimum")
	view._season_filter = 2
	view.refresh()
	for button in view.find_children("*", "Button", true, false):
		if button.text == "Сбросить":
			button.pressed.emit()
			break
	check(view._rows.size() == 5 and int(view._season_select.selected_id) == 0, "reset clears all filters and visible season selector")
	GameSession.transfer_log.append(entry("in", 3000000))
	GameSession.session_changed.emit()
	check(view._rows.size() == 6, "open history refreshes after a completed transfer")
	var old_options := Transfers._season_options(log, 3, 1)
	check(old_options.size() == 3, "season choices include outgoing-only seasons")
	modal.close()
	await get_tree().process_frame
	check(not is_instance_valid(modal), "closing releases modal")
	var club_card := preload("res://scenes/game/team_card.tscn").instantiate()
	add_child(club_card)
	club_card.open_for({"id": 1, "clubs_by_id": {1: {"id": 1, "name": "Наш клуб"}}}, 1)
	for button in club_card.find_children("*", "Button", true, false):
		if button.text == "Все переходы и статистика →":
			button.pressed.emit()
			break
	check(club_card.has_node("ClubTransfersDialog"), "club card opens detailed transfers")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	club_card._side_host.get_child(2).gui_input.emit(click)
	var modal_count := 0
	for child in club_card.get_children():
		if child.name == "ClubTransfersDialog": modal_count += 1
	check(modal_count == 1, "repeated click cannot stack club dialogs")
	club_card.get_node("ClubTransfersDialog").close()
	await get_tree().process_frame
	club_card.queue_free()
	GameSession.clear()
	print("Transfer activity: %d passed, %d failed" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
