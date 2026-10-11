extends Control

const MAIN_MENU_PATH := "res://scenes/main_menu/main_menu.tscn"

@onready var _back_button: WeButton = %BackButton
@onready var _world_name_label: Label = %WorldName
@onready var _db_status_label: Label = %DatabaseStatus
@onready var _tab_bar: WeTabBar = %TabBar
@onready var _geography = %Geography
@onready var _teams = %Teams
@onready var _competitions = %Competitions
@onready var _names = %Names


func _ready() -> void:
	_back_button.kind = WeButton.Kind.GHOST
	_back_button.focus_mode = Control.FOCUS_NONE
	_back_button.pressed.connect(_on_back_pressed)
	_tab_bar.set_tabs(PackedStringArray(["География", "Все команды", "Турниры", "База имен"]))
	_tab_bar.tab_selected.connect(_on_tab_selected)
	_tab_bar.select(0, false)
	_refresh_header()


func _on_tab_selected(index: int) -> void:
	_geography.visible = index == 0
	_teams.visible = index == 1
	_competitions.visible = index == 2
	_names.visible = index == 3
	if index == 0:
		_geography.reload_continents()
	elif index == 1:
		_teams.reload()


func _refresh_header() -> void:
	var is_db_ready: bool = WorldDatabase.is_ready()
	if is_db_ready:
		var world_name: String = WorldDatabase.get_world_name()
		_world_name_label.text = world_name if not world_name.is_empty() else "Мир"
		_db_status_label.text = WorldDatabase.get_status_text()
	else:
		_world_name_label.text = "Мир недоступен"
		_db_status_label.text = WorldDatabase.get_status_text()

	_db_status_label.add_theme_color_override(
		"font_color",
		WeTokens.SUCCESS if is_db_ready else WeTokens.DANGER
	)
	var box := WeTokens.polish_style(StyleBoxFlat.new())
	box.set_corner_radius_all(999)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if is_db_ready:
		box.bg_color = WeTokens.SUCCESS_SOFT
		box.border_color = Color(WeTokens.SUCCESS.r, WeTokens.SUCCESS.g, WeTokens.SUCCESS.b, 0.4)
	else:
		box.bg_color = WeTokens.DANGER_SOFT
		box.border_color = Color(WeTokens.DANGER.r, WeTokens.DANGER.g, WeTokens.DANGER.b, 0.4)
	box.set_border_width_all(1)
	_db_status_label.add_theme_stylebox_override("normal", box)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()
