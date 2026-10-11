extends Control


@onready var _new_game: WeButton = %NewGame
@onready var _load_game: WeButton = %LoadGame
@onready var _world_editor: WeButton = %WorldEditor
@onready var _settings: WeButton = %Settings
@onready var _exit: WeButton = %Exit


func _ready() -> void:
	for button in [_new_game, _load_game, _world_editor, _settings, _exit]:
		button.add_theme_font_size_override("font_size", 18)
		button.custom_minimum_size = Vector2(300, 48)

	_new_game.pressed.connect(_on_new_game_pressed)
	_load_game.pressed.connect(_on_load_game_pressed)
	_world_editor.pressed.connect(_on_world_editor_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_exit.pressed.connect(_on_exit_pressed)
	_new_game.grab_focus()


func _on_new_game_pressed() -> void:
	var started := GameSession.start_new_game()
	if not started["success"]:
		push_warning("[MainMenu] New game failed: %s" % started.get("error", ""))
	get_tree().change_scene_to_file("res://scenes/game/game_screen.tscn")


func _on_load_game_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/load_game/load_game.tscn")


func _on_world_editor_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/world_editor/world_editor_screen.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/settings/settings.tscn")


func _on_exit_pressed() -> void:
	get_tree().quit()
