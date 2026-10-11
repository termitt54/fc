extends Control

@export var title_text: String = "Заглушка"

const MAIN_MENU_PATH := "res://scenes/main_menu/main_menu.tscn"

@onready var _title: Label = %Title
@onready var _back: WeButton = %Back


func _ready() -> void:
	_title.text = title_text
	_back.kind = WeButton.Kind.GHOST
	_back.pressed.connect(_on_back_pressed)
	_back.grab_focus()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
