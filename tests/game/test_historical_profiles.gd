extends Node
const STORE := preload("res://game/save_store.gd")
const HISTORY := preload("res://game/history_store.gd")
const PATH := "user://tests/historical_profiles/games.db"
var passed := 0
var failed := 0

func check(condition: bool, message: String) -> void:
	if condition:
		passed += 1
	else:
		failed += 1
		push_error(message)

func _ready() -> void:
	if not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
		get_tree().quit(2)
		return
	call_deferred("_run")

func _run() -> void:
	STORE.database_path_override = PATH
	for suffix in ["", "-wal", "-shm"]:
		if FileAccess.file_exists(PATH + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + suffix))
	GameSession.clear()
	var club := {"id": 700001, "name": "Moved Club", "country_id": 0, "logo_path": "res://logos/992.png"}
	var old_league := {"id": 1, "name": "Old league", "clubs_by_id": {}, "divisions": [], "matches": [], "rules": {}, "winners": []}
	var new_league := {"id": 2, "name": "New league", "clubs_by_id": {700001: club}, "divisions": [], "matches": [], "rules": {}, "winners": []}
	GameSession.units = [old_league, new_league]
	GameSession.season_number = 100
	GameSession.is_active = true
	GameSession.selected_unit_id = 1
	var player := {"id": 800001, "name": "Retired Legend", "club_id": 700001, "position": "ST", "age": 35, "nationality_country_id": 0,
		"attributes": {}, "current_ability": 80, "potential_ability": 90, "reputation": 800, "development_history": [], "career_stats": [],
		"national_stats": [{"season": 19, "club_id": 1000000001, "matches": 5, "goals": 4}]}
	PlayerStats.ensure_state(player, 20)
	player["season_stats"]["matches"] = 30
	player["season_stats"]["goals"] = 23
	check(GameSession._archive_retired([player], 20)["success"], "Archive full player")
	check(GameSession.save_game("zz_historical_profiles")["success"], "Save at season 100")
	check(GameSession.load_game("zz_historical_profiles")["success"], "Reload long-running world")
	var screen: Control = load("res://scenes/game/game_screen.tscn").instantiate()
	add_child(screen)
	var texture: Texture2D = screen._club_logo_texture(GameSession.units[0], 700001, 22)
	check(texture != null, "Historical club logo resolves after relegation")
	check(GameSession.club_name(GameSession.units[0], 700001) == "Moved Club", "Historical club name resolves across leagues")
	check(screen._club_logo_texture(GameSession.units[1], 700001, 22) == texture, "Logo shared across leagues")
	GameSession.units[1]["clubs_by_id"][700001]["logo_path"] = ""
	check(screen._club_logo_texture(GameSession.units[0], 700001, 22) == null, "Old cached logo not returned after path change")
	GameSession.units[1]["clubs_by_id"][700001]["logo_path"] = "res://logos/992.png"
	check(screen._club_logo_texture(GameSession.units[0], 700001, 22) != null, "Restored path resolves again")
	screen._directory_mode = "transfers"
	screen._on_players_view_player_requested(800001)
	var card: Control = screen._player_card
	check(card.is_open(), "Transfer click opens retired profile")
	check(card._name_label.text == "Retired Legend", "Archive card shows actual name")
	check(card._player.get("is_retired", false), "Archive card knows career ended")
	check(PlayerStats.career_totals(card._player).get("goals", 0) == 23, "Archive card keeps career goals at season 100")
	check(card._player.get("national_stats", [])[0]["goals"] == 4, "Archive card retains international statistics")
	check(card._resolve_club(700001).get("name", "") == "Moved Club", "Career clubs resolved after movement")
	card.refresh()
	check(card._player.get("retired_season", 0) == 20, "Card refresh retains original retirement season")
	card.close()
	check(screen._directory_mode == "transfers", "Closing player returns to transfers")
	check(GameSession.get_player(800001).is_empty(), "Historical player stays outside simulation")
	screen._on_players_view_player_requested(999999999)
	check(not card.is_open() and screen._directory_mode=="transfers","missing unplayed profile does not open an empty card or leave the transfer directory")
	check(screen._message_dialog.visible,"missing profile explains why its card is not stored")
	screen._message_dialog.close()
	screen.queue_free()
	await get_tree().process_frame
	GameSession.clear()
	STORE.new().delete_slot("zz_historical_profiles")
	STORE.database_path_override = ""
	print("=== Historical profiles: %d passed, %d failed ===" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)
