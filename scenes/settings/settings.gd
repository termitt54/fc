extends Control

const MAIN_MENU_PATH := "res://scenes/main_menu/main_menu.tscn"

@onready var _back_button: WeButton = %BackButton
@onready var _tab_bar: WeTabBar = %TabBar
@onready var _global_pa: Control = %GlobalPa
@onready var _match_sim: Control = %MatchSim


func _ready() -> void:
	_back_button.kind = WeButton.Kind.GHOST
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.pressed.connect(_on_back_pressed)
	_tab_bar.set_tabs(PackedStringArray(["Талант стран", "Симуляция матчей"]))
	_tab_bar.tab_selected.connect(_on_tab_selected)
	_tab_bar.select(0, false)
	_on_tab_selected(0)


func _on_tab_selected(index: int) -> void:
	_global_pa.visible = index == 0
	_match_sim.visible = index == 1


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
