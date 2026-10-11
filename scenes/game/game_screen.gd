extends Control
## New-game hub: tournament select, season clock, table / calendar / stats / preview / playoff / history.


const MAIN_MENU_PATH := "res://scenes/main_menu/main_menu.tscn"
const SaveStoreScript := preload("res://game/save_store.gd")
const WeSelectScene := preload("res://ui/components/we_select_field.tscn")
const WeMessageScene := preload("res://ui/components/we_message_dialog.tscn")
const PlayoffBracketViewScript := preload("res://scenes/game/playoff_bracket_view.gd")
const UnitSeasonStatsScript := preload("res://game/unit_season_stats.gd")

const TAB_TABLE := 0
const TAB_CALENDAR := 1
const TAB_STATS := 2
const TAB_PREVIEW := 3
const TAB_PLAYOFF := 4
const TAB_HISTORY := 5

const TABLE_MODE_DIVISIONS := "divisions"
const TABLE_MODE_OVERALL := "overall"
const LOGO_SIZE := 30
const LOGO_SIZE_CALENDAR := 22
const CALENDAR_COLUMNS := 3

@onready var _menu_button: WeButton = %MenuButton
@onready var _tournament_select: WeSelectField = %TournamentSelect
@onready var _players_link: WeButton = %PlayersLink
@onready var _market_link: WeButton = %MarketLink
@onready var _transfers_link: WeButton = %TransfersLink
@onready var _header_card: PanelContainer = %HeaderCard
@onready var _clock_frame: PanelContainer = %ClockFrame
@onready var _season_label: Label = %SeasonLabel
@onready var _day_label: Label = %DayLabel
@onready var _advance_day_button: WeButton = %AdvanceDayButton
@onready var _sim_button: WeButton = %SimButton
@onready var _total_days_label: Label = %TotalDaysLabel
@onready var _new_season_button: WeButton = %NewSeasonButton
@onready var _tab_bar: WeTabBar = %TabBar
@onready var _body: PanelContainer = %Body
@onready var _scroll: ScrollContainer = %Scroll
@onready var _content: VBoxContainer = %Content
@onready var _empty_state: Label = %EmptyState
@onready var _team_card: TeamCard = %TeamCard
@onready var _national_team_card: NationalTeamCard = %NationalTeamCard
@onready var _player_card: PlayerCard = %PlayerCard
@onready var _coach_card: CoachCard = %CoachCard
@onready var _players_view = %WorldPlayersView
@onready var _transfers_view = %TransfersView

var _current_tab: int = TAB_TABLE
var _suppress_select: bool = false
var _message_dialog: WeMessageDialog
var _table_mode: String = TABLE_MODE_DIVISIONS
var _logo_cache: Dictionary = {}
var _menu_popup: PopupPanel
var _menu_list: VBoxContainer
var _return_to_team_card: bool = false
var _return_from_player_card: bool = false
var _return_to_player_card: bool = false
var _return_from_coach_card: bool = false
var _return_to_coach_card: bool = false
var _directory_mode: String = ""
var _return_to_directory: String = ""
var _open_club_after_player: int = 0
var _open_club_after_coach: int = 0
const SIM_OFF := 0
const SIM_SEASON := 1
const SIM_CONTINUOUS := 2

var _sim_mode: int = SIM_OFF
var _sim_loop_active: bool = false
var _sim_menu: PopupMenu = null
var _playoff_bracket: PlayoffBracketView = null
var _playoff_meta: Label = null
var _work_shield: Control


func _ready() -> void:
	_work_shield = Control.new()
	_work_shield.mouse_filter = Control.MOUSE_FILTER_STOP
	_work_shield.z_index = 100
	_work_shield.visible = false
	_body.add_child(_work_shield)
	_menu_button.kind = WeButton.Kind.GHOST
	_menu_button.pressed.connect(_on_menu_pressed)
	_tournament_select.label = ""
	_tournament_select.compact = true
	if _tournament_select.has_node("%Label"):
		(_tournament_select.get_node("%Label") as CanvasItem).visible = false
	_tournament_select.item_selected.connect(_on_tournament_selected)
	_tournament_select.item_reselected.connect(_on_tournament_reselected)
	_players_link.kind = WeButton.Kind.GHOST
	_players_link.focus_mode = Control.FOCUS_NONE
	_players_link.pressed.connect(_on_players_pressed)
	_market_link.kind = WeButton.Kind.GHOST
	_market_link.focus_mode = Control.FOCUS_NONE
	_market_link.pressed.connect(_on_market_pressed)
	_transfers_link.kind = WeButton.Kind.GHOST
	_transfers_link.focus_mode = Control.FOCUS_NONE
	_transfers_link.pressed.connect(_on_transfers_pressed)
	_tab_bar.tab_selected.connect(_on_tab_selected)
	_advance_day_button.kind = WeButton.Kind.PRIMARY
	_advance_day_button.pressed.connect(_on_advance_day_pressed)
	_sim_button.kind = WeButton.Kind.GHOST
	_sim_button.focus_mode = Control.FOCUS_NONE
	_sim_button.pressed.connect(_on_sim_button_pressed)
	_sim_menu = PopupMenu.new()
	_sim_menu.add_item("До конца сезона", SIM_SEASON)
	_sim_menu.add_item("Беспрерывно", SIM_CONTINUOUS)
	_sim_menu.add_separator()
	_sim_menu.add_item("Остановить", SIM_OFF)
	_sim_menu.id_pressed.connect(_on_sim_menu_pressed)
	_style_sim_menu()
	add_child(_sim_menu)
	_new_season_button.kind = WeButton.Kind.PRIMARY
	_new_season_button.pressed.connect(_on_new_season_pressed)
	_team_card.closed.connect(_on_team_card_closed)
	_team_card.league_requested.connect(_on_team_card_league_requested)
	_team_card.country_requested.connect(_on_team_card_country_requested)
	_team_card.player_requested.connect(_on_team_card_player_requested)
	_team_card.coach_requested.connect(_on_team_card_coach_requested)
	_national_team_card.closed.connect(_on_national_team_card_closed)
	_player_card.closed.connect(_on_player_card_closed)
	_player_card.club_requested.connect(_on_player_card_club_requested)
	_player_card.country_requested.connect(_on_player_card_country_requested)
	_coach_card.closed.connect(_on_coach_card_closed)
	_coach_card.club_requested.connect(_on_coach_card_club_requested)
	_coach_card.country_requested.connect(_on_coach_card_country_requested)
	_players_view.player_requested.connect(_on_players_view_player_requested)
	_players_view.club_requested.connect(_on_players_view_club_requested)
	_players_view.country_requested.connect(_on_players_view_country_requested)
	_players_view.closed.connect(_close_directory)
	_transfers_view.player_requested.connect(_on_players_view_player_requested)
	_transfers_view.club_requested.connect(_on_players_view_club_requested)
	_transfers_view.closed.connect(_close_directory)
	_apply_chrome_styles()
	_setup_menu_popup()
	_setup_message_dialog()
	_show_tournament_view()

	if not GameSession.is_active:
		var started := GameSession.start_new_game()
		if not started["success"]:
			_show_fatal(str(started.get("error", GameSession.last_error)))
			return

	GameSession.session_changed.connect(_on_session_changed)
	GameSession.processing_changed.connect(_refresh_header)
	GameSession.simulation_progress.connect(_on_simulation_progress)
	_refresh_header()
	_refresh_tabs(false)
	_rebuild_content()
	_menu_button.grab_focus()


func _apply_chrome_styles() -> void:
	_header_card.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE_RAISED, WeTokens.BORDER, WeTokens.RADIUS_LG, 0, 12.0)
	)
	_clock_frame.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER_STRONG, WeTokens.RADIUS_MD, 0)
	)
	_body.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_LG, 0)
	)


func _setup_message_dialog() -> void:
	_message_dialog = WeMessageScene.instantiate() as WeMessageDialog
	add_child(_message_dialog)


func _setup_menu_popup() -> void:
	_menu_popup = PopupPanel.new()
	_menu_popup.transparent = true
	_menu_popup.transparent_bg = true
	_menu_popup.unresizable = true
	_menu_popup.borderless = true
	_menu_popup.hide()
	_menu_popup.add_theme_stylebox_override(
		"panel",
		WeTokens.elevated(WeTokens.SURFACE_RAISED, WeTokens.BORDER_STRONG, WeTokens.RADIUS_MD, 6, 16.0)
	)
	add_child(_menu_popup)

	_menu_list = VBoxContainer.new()
	_menu_list.add_theme_constant_override("separation", 2)
	_menu_popup.add_child(_menu_list)

	_menu_list.add_child(_make_menu_item("Сохранить игру", _on_save_game_pressed))
	_menu_list.add_child(_make_menu_item("Выйти в главное меню", _on_exit_to_menu_pressed))


func _make_menu_item(text: String, callback: Callable) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(220, 36)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", WeTokens.fill(Color(0, 0, 0, 0), 8, 12, 8))

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT)
	label.add_theme_font_size_override("font_size", 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)

	row.mouse_entered.connect(func():
		if is_instance_valid(row):
			row.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.ACCENT_SOFT, 8, 12, 8))
			label.add_theme_color_override("font_color", WeTokens.ACCENT)
	)
	row.mouse_exited.connect(func():
		if is_instance_valid(row):
			row.add_theme_stylebox_override("panel", WeTokens.fill(Color(0, 0, 0, 0), 8, 12, 8))
			label.add_theme_color_override("font_color", WeTokens.TEXT)
	)
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				row.accept_event()
				_menu_popup.hide()
				callback.call()
	)
	return row


func _on_menu_pressed() -> void:
	if _menu_popup.visible:
		_menu_popup.hide()
		return
	var rect := _menu_button.get_global_rect()
	_menu_popup.size = Vector2i(230, 88)
	_menu_popup.position = Vector2i(
		int(rect.position.x + rect.size.x - _menu_popup.size.x),
		int(rect.position.y + rect.size.y + 4.0)
	)
	_menu_popup.popup()


func _on_save_game_pressed() -> void:
	var result := GameSession.save_game()
	if _message_dialog == null:
		return
	if result["success"]:
		_message_dialog.open_info(
			"Сохранение",
			"Игра сохранена: %s." % SaveStoreScript.display_name(GameSession.save_slot)
		)
	else:
		_message_dialog.open_info("Сохранение", str(result.get("error", "Не удалось сохранить.")))


func _on_exit_to_menu_pressed() -> void:
	if GameSession.is_processing:
		return
	GameSession.clear()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _unhandled_input(event: InputEvent) -> void:
	if GameSession.is_processing:
		if event.is_action_pressed("ui_cancel") and _sim_mode != SIM_OFF:
			_stop_simulation()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _menu_popup != null and _menu_popup.visible:
			_menu_popup.hide()
			get_viewport().set_input_as_handled()
			return
		if _player_card != null and _player_card.is_open():
			_player_card.close()
			get_viewport().set_input_as_handled()
			return
		if _coach_card != null and _coach_card.is_open():
			_coach_card.close()
			get_viewport().set_input_as_handled()
			return
		if _national_team_card != null and _national_team_card.is_open():
			_national_team_card.close()
			get_viewport().set_input_as_handled()
			return
		if _team_card != null and _team_card.is_open():
			_team_card.close()
			get_viewport().set_input_as_handled()
			return
		if not _directory_mode.is_empty():
			_close_directory()
			get_viewport().set_input_as_handled()
			return
		_on_menu_pressed()
		get_viewport().set_input_as_handled()


func _on_session_changed() -> void:
	_refresh_header()
	if _player_card != null and _player_card.is_open():
		_player_card.refresh()
		return
	if _coach_card != null and _coach_card.is_open():
		_coach_card.refresh()
		return
	if _national_team_card != null and _national_team_card.is_open():
		_national_team_card.refresh()
		return
	if _team_card != null and _team_card.is_open():
		_team_card.refresh()
		return
	if not _directory_mode.is_empty():
		_refresh_open_directory()
		return
	_rebuild_content()


func _on_tournament_selected(_index: int) -> void:
	if _suppress_select:
		return
	var unit_id: Variant = _tournament_select.selected_id
	if unit_id == null:
		return
	_close_overlay_cards()
	_directory_mode = ""
	GameSession.select_unit(int(unit_id))
	_refresh_tabs(true)
	_rebuild_content()


func _on_tournament_reselected(_index: int) -> void:
	if _suppress_select:
		return
	if not _directory_mode.is_empty():
		_close_directory()


func _on_tab_selected(index: int) -> void:
	if GameSession.is_processing:
		_tab_bar.select(_current_tab, false)
		return
	_current_tab = index
	if not _directory_mode.is_empty():
		_directory_mode = ""
		_return_to_directory = ""
		_close_overlay_cards()
		_rebuild_content()
		return
	if (_player_card != null and _player_card.is_open()) \
		or (_coach_card != null and _coach_card.is_open()) \
		or (_national_team_card != null and _national_team_card.is_open()) \
		or (_team_card != null and (_team_card.is_open() or _team_card.get_club_id() > 0)):
		_close_overlay_cards()
		return
	_rebuild_content()


func _on_advance_day_pressed() -> void:
	if _sim_mode != SIM_OFF or GameSession.is_processing:
		return
	var result: Dictionary = await GameSession.advance_day_async()
	if not result.get("success", false):
		_message_dialog.open_info("Симуляция", str(result.get("error", "Не удалось продолжить игру.")))


func _on_simulation_progress(stage: String, done: int, total: int) -> void:
	_day_label.text = stage + (" · %d/%d" % [done, total] if total > 0 else "")


func _on_sim_button_pressed() -> void:
	if _sim_mode != SIM_OFF:
		_stop_simulation()
		return
	_open_sim_menu()


func _open_sim_menu() -> void:
	if _sim_menu == null or _sim_button == null:
		return
	var stop_index := _sim_menu.get_item_index(SIM_OFF)
	if stop_index >= 0:
		_sim_menu.set_item_disabled(stop_index, _sim_mode == SIM_OFF)
	var rect := _sim_button.get_global_rect()
	_sim_menu.position = Vector2i(int(rect.position.x), int(rect.end.y + 4))
	_sim_menu.popup()


func _on_sim_menu_pressed(id: int) -> void:
	if id == SIM_OFF:
		_stop_simulation()
		return
	_start_simulation(id)


func _start_simulation(mode: int) -> void:
	if GameSession.is_processing:
		return
	if mode != SIM_SEASON and mode != SIM_CONTINUOUS:
		return
	if not GameSession.is_active:
		return
	_sim_mode = mode
	_refresh_sim_controls()
	if _sim_loop_active:
		return
	_sim_loop_active = true
	_run_simulation()


func _stop_simulation() -> void:
	_sim_mode = SIM_OFF
	_refresh_sim_controls()


func _run_simulation() -> void:
	while _sim_mode != SIM_OFF and is_inside_tree() and GameSession.is_active:
		if GameSession.season_finished:
			if _sim_mode != SIM_CONTINUOUS:
				break
			var started: Dictionary = GameSession.start_new_season()
			if not bool(started.get("success", false)):
				_message_dialog.open_info("История игроков", str(started.get("error", "Не удалось начать сезон.")))
				break
			_refresh_tabs(true)
		else:
			var step: Dictionary = await GameSession.advance_day_async()
			if not bool(step.get("success", false)):
				_message_dialog.open_info("Симуляция", str(step.get("error", "Не удалось продолжить игру.")))
				break
		await get_tree().process_frame
	_sim_mode = SIM_OFF
	_sim_loop_active = false
	if is_inside_tree():
		_refresh_header()
		if _directory_mode.is_empty():
			_rebuild_content()


func _refresh_sim_controls() -> void:
	if _sim_button == null:
		return
	var running := _sim_mode != SIM_OFF
	_sim_button.visible = GameSession.is_active
	_sim_button.disabled = GameSession.is_processing and not running
	_sim_button.text = "Стоп" if running else "Авто"
	_sim_button.kind = WeButton.Kind.DANGER if running else WeButton.Kind.GHOST
	if _sim_menu != null:
		var stop_index := _sim_menu.get_item_index(SIM_OFF)
		if stop_index >= 0:
			_sim_menu.set_item_disabled(stop_index, not running)


func _style_sim_menu() -> void:
	if _sim_menu == null:
		return
	var panel := StyleBoxFlat.new()
	panel.bg_color = WeTokens.SURFACE
	panel.border_color = WeTokens.BORDER_STRONG
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 4
	panel.content_margin_right = 4
	panel.content_margin_top = 4
	panel.content_margin_bottom = 4
	_sim_menu.add_theme_stylebox_override("panel", panel)
	var hover := StyleBoxFlat.new()
	hover.bg_color = WeTokens.ACCENT_SOFT
	hover.set_corner_radius_all(6)
	_sim_menu.add_theme_stylebox_override("hover", hover)
	_sim_menu.add_theme_color_override("font_color", WeTokens.TEXT)
	_sim_menu.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	_sim_menu.add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
	_sim_menu.add_theme_font_size_override("font_size", 13)


func _on_new_season_pressed() -> void:
	var started: Dictionary = GameSession.start_new_season()
	if not started["success"]:
		_message_dialog.open_info("История игроков", str(started.get("error", "Не удалось начать сезон.")))
	_refresh_tabs(false)


func _refresh_header() -> void:
	var busy := GameSession.is_processing
	_menu_button.disabled = busy
	_players_link.disabled = busy
	_market_link.disabled = busy
	_transfers_link.disabled = busy
	_tournament_select.editable = not busy
	if _work_shield != null:
		_work_shield.visible = busy
	if busy:
		get_viewport().gui_release_focus()
	_season_label.text = "Сезон %d" % GameSession.season_number
	if GameSession.is_market_day():
		_day_label.text = "День %d · рынок" % GameSession.season_day
	else:
		_day_label.text = "День %d" % GameSession.season_day
	_total_days_label.text = "из %d" % GameSession.season_total_days

	var running := _sim_mode != SIM_OFF
	_advance_day_button.visible = not GameSession.season_finished
	_advance_day_button.disabled = GameSession.season_finished or running or GameSession.is_processing
	_new_season_button.visible = GameSession.season_finished
	_new_season_button.disabled = running or GameSession.is_processing
	_refresh_sim_controls()

	_suppress_select = true
	_tournament_select.set_items(GameSession.get_unit_options(), GameSession.selected_unit_id)
	_suppress_select = false


func _refresh_tabs(keep_selection: bool) -> void:
	var unit := GameSession.get_selected_unit()
	var titles := PackedStringArray(["Таблица", "Календарь", "Статистика", "Превью"])
	var playoff_enabled := bool(unit.get("playoff", {}).get("enabled", false))
	if playoff_enabled:
		titles.append("Плей-офф")
	titles.append("История победителей")

	var previous := _current_tab
	_tab_bar.set_tabs(titles)

	if keep_selection:
		var max_index := titles.size() - 1
		if not playoff_enabled and previous >= TAB_PLAYOFF:
			_current_tab = mini(previous - 1, max_index) if previous == TAB_HISTORY else TAB_TABLE
		else:
			_current_tab = clampi(previous, 0, max_index)
	else:
		_current_tab = TAB_TABLE

	_tab_bar.select(_current_tab, false)


func _content_tab_code() -> int:
	var unit := GameSession.get_selected_unit()
	var playoff_enabled := bool(unit.get("playoff", {}).get("enabled", false))
	if playoff_enabled:
		return _current_tab
	if _current_tab <= TAB_PREVIEW:
		return _current_tab
	return TAB_HISTORY


func _show_tournament_view() -> void:
	_directory_mode = ""
	_return_to_directory = ""
	_tab_bar.visible = true
	_scroll.visible = true
	if _team_card != null:
		_team_card.visible = false
	if _national_team_card != null:
		_national_team_card.visible = false
	if _player_card != null:
		_player_card.visible = false
	if _coach_card != null:
		_coach_card.visible = false
	_hide_directory_views()
	_refresh_nav_links()


func _show_team_card_view() -> void:
	_tab_bar.visible = false
	_scroll.visible = false
	if _national_team_card != null:
		_national_team_card.visible = false
	if _player_card != null:
		_player_card.visible = false
	if _coach_card != null:
		_coach_card.visible = false
	_hide_directory_views()
	if _team_card != null:
		_team_card.visible = true
	_refresh_nav_links()


func _show_national_team_card_view() -> void:
	_tab_bar.visible = false
	_scroll.visible = false
	if _team_card != null:
		_team_card.visible = false
	if _player_card != null:
		_player_card.visible = false
	if _coach_card != null:
		_coach_card.visible = false
	_hide_directory_views()
	if _national_team_card != null:
		_national_team_card.visible = true
	_refresh_nav_links()


func _show_player_card_view() -> void:
	_tab_bar.visible = false
	_scroll.visible = false
	if _national_team_card != null:
		_national_team_card.visible = false
	if _team_card != null:
		_team_card.visible = false
	if _coach_card != null:
		_coach_card.visible = false
	_hide_directory_views()
	if _player_card != null:
		_player_card.visible = true
	_refresh_nav_links()


func _show_coach_card_view() -> void:
	_tab_bar.visible = false
	_scroll.visible = false
	if _national_team_card != null:
		_national_team_card.visible = false
	if _team_card != null:
		_team_card.visible = false
	if _player_card != null:
		_player_card.visible = false
	_hide_directory_views()
	if _coach_card != null:
		_coach_card.visible = true
	_refresh_nav_links()


func _show_directory(mode: String) -> void:
	_directory_mode = mode
	_tab_bar.visible = false
	_scroll.visible = false
	if _team_card != null:
		_team_card.visible = false
	if _national_team_card != null:
		_national_team_card.visible = false
	if _player_card != null:
		_player_card.visible = false
	if _coach_card != null:
		_coach_card.visible = false
	_hide_directory_views()
	if mode == "transfers":
		if _transfers_view != null:
			_transfers_view.visible = true
			_transfers_view.refresh()
	elif _players_view != null:
		_players_view.set_mode("market" if mode == "market" else "all")
		_players_view.visible = true
		_players_view.refresh()
	_refresh_nav_links()


func _close_directory() -> void:
	_directory_mode = ""
	_return_to_directory = ""
	_show_tournament_view()
	_rebuild_content()


func _restore_directory() -> void:
	var mode := _return_to_directory
	_return_to_directory = ""
	if mode.is_empty():
		mode = _directory_mode
	if mode.is_empty():
		_show_tournament_view()
		_rebuild_content()
		return
	_show_directory(mode)


func _on_players_pressed() -> void:
	_toggle_directory("players")


func _on_market_pressed() -> void:
	_toggle_directory("market")


func _on_transfers_pressed() -> void:
	_toggle_directory("transfers")


func _toggle_directory(mode: String) -> void:
	if _directory_mode == mode and _directory_view_visible(mode):
		_close_directory()
		return
	_close_overlay_cards()
	_show_directory(mode)


func _directory_view_visible(mode: String) -> bool:
	if mode == "transfers":
		return _transfers_view != null and _transfers_view.visible
	return _players_view != null and _players_view.visible


func _refresh_open_directory() -> void:
	if _directory_mode == "transfers":
		if _transfers_view != null:
			_transfers_view.refresh()
		return
	if _players_view != null:
		_players_view.refresh()


func _hide_directory_views() -> void:
	if _players_view != null:
		_players_view.visible = false
	if _transfers_view != null:
		_transfers_view.visible = false


func _refresh_nav_links() -> void:
	_style_nav_link(_players_link, _directory_mode == "players")
	_style_nav_link(_market_link, _directory_mode == "market")
	_style_nav_link(_transfers_link, _directory_mode == "transfers")


func _style_nav_link(button: WeButton, selected: bool) -> void:
	if button == null:
		return
	var normal := _hub_nav_box(
		WeTokens.ACCENT_SOFT if selected else Color(1, 1, 1, 0.05),
		Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.4) if selected else WeTokens.BORDER_STRONG
	)
	var hover := _hub_nav_box(Color(1, 1, 1, 0.1), WeTokens.BORDER)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", normal)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", WeTokens.ACCENT if selected else WeTokens.TEXT)
	button.add_theme_color_override("font_hover_color", WeTokens.TEXT)
	button.add_theme_font_size_override("font_size", 14)


func _hub_nav_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_border_width_all(1)
	box.border_color = border
	box.set_corner_radius_all(WeTokens.RADIUS_SM)
	box.content_margin_left = 16
	box.content_margin_right = 16
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return WeTokens.polish_style(box)


func _on_team_card_closed() -> void:
	if _national_team_card != null and _national_team_card.is_open():
		return
	if not _return_to_directory.is_empty():
		_restore_directory()
		return
	_show_tournament_view()
	_rebuild_content()


func _on_team_card_league_requested(unit_id: int) -> void:
	if unit_id > 0:
		GameSession.select_unit(unit_id)
	_current_tab = TAB_TABLE
	_refresh_tabs(true)
	_tab_bar.select(_current_tab, false)


func _on_team_card_country_requested(country_id: int) -> void:
	if country_id < 1:
		return
	_return_to_team_card = true
	_team_card.suspend()
	_show_national_team_card_view()
	_national_team_card.open_for(country_id)


func _on_team_card_player_requested(player_id: int) -> void:
	if player_id < 1:
		return
	_return_from_player_card = true
	_team_card.suspend()
	_show_player_card_view()
	_player_card.open_for(player_id)


func _on_team_card_coach_requested(coach_id: int) -> void:
	if coach_id < 1:
		return
	_return_from_coach_card = true
	_team_card.suspend()
	_show_coach_card_view()
	_coach_card.open_for(coach_id)


func _on_player_card_club_requested(club_id: int) -> void:
	if club_id < 1:
		return
	_open_club_after_player = club_id
	_return_from_player_card = false
	_return_to_player_card = false
	_player_card.close()


func _on_player_card_country_requested(country_id: int) -> void:
	if country_id < 1:
		return
	_return_to_player_card = true
	_player_card.suspend()
	_show_national_team_card_view()
	_national_team_card.open_for(country_id)


func _on_player_card_closed() -> void:
	if _open_club_after_player > 0:
		var club_id := _open_club_after_player
		_open_club_after_player = 0
		_return_from_player_card = false
		var unit := _find_unit_for_club(club_id)
		if unit.is_empty():
			if not _return_to_directory.is_empty():
				_restore_directory()
				return
			_show_tournament_view()
			_rebuild_content()
			return
		_open_club_card(unit, club_id)
		return
	if _return_from_player_card and _team_card != null and _team_card.get_club_id() > 0:
		_return_from_player_card = false
		_show_team_card_view()
		_team_card.resume()
		return
	_return_from_player_card = false
	if not _return_to_directory.is_empty():
		_restore_directory()
		return
	_show_tournament_view()
	_rebuild_content()


func _on_coach_card_club_requested(club_id: int) -> void:
	if club_id < 1:
		return
	_open_club_after_coach = club_id
	_return_from_coach_card = false
	_return_to_coach_card = false
	_coach_card.close()


func _on_coach_card_country_requested(country_id: int) -> void:
	if country_id < 1:
		return
	_return_to_coach_card = true
	_coach_card.suspend()
	_show_national_team_card_view()
	_national_team_card.open_for(country_id)


func _on_coach_card_closed() -> void:
	if _open_club_after_coach > 0:
		var club_id := _open_club_after_coach
		_open_club_after_coach = 0
		_return_from_coach_card = false
		var unit := _find_unit_for_club(club_id)
		if unit.is_empty():
			_show_tournament_view()
			_rebuild_content()
			return
		_open_club_card(unit, club_id)
		return
	if _return_from_coach_card and _team_card != null and _team_card.get_club_id() > 0:
		_return_from_coach_card = false
		_show_team_card_view()
		_team_card.resume()
		return
	_return_from_coach_card = false
	_show_tournament_view()
	_rebuild_content()


func _on_national_team_card_closed() -> void:
	if _return_to_player_card and _player_card != null and _player_card.get_player_id() > 0:
		_return_to_player_card = false
		_show_player_card_view()
		_player_card.resume()
		return
	if _return_to_coach_card and _coach_card != null and _coach_card.get_coach_id() > 0:
		_return_to_coach_card = false
		_show_coach_card_view()
		_coach_card.resume()
		return
	if _return_to_team_card and _team_card != null and _team_card.get_club_id() > 0:
		_return_to_team_card = false
		_show_team_card_view()
		_team_card.resume()
		return
	_return_to_team_card = false
	_return_to_player_card = false
	_return_to_coach_card = false
	if not _return_to_directory.is_empty():
		_restore_directory()
		return
	if _team_card != null and _team_card.get_club_id() > 0:
		_team_card.close()
		return
	_show_tournament_view()
	_rebuild_content()


func _find_unit_for_club(club_id: int) -> Dictionary:
	if club_id < 1:
		return {}
	var selected := GameSession.get_selected_unit()
	var selected_clubs: Dictionary = selected.get("clubs_by_id", {})
	if selected_clubs.has(club_id):
		return selected
	for unit in GameSession.units:
		var clubs: Dictionary = unit.get("clubs_by_id", {})
		if clubs.has(club_id):
			return unit
	return {}


func _close_overlay_cards() -> void:
	_return_to_team_card = false
	_return_from_player_card = false
	_return_to_player_card = false
	_return_from_coach_card = false
	_return_to_coach_card = false
	_return_to_directory = ""
	_open_club_after_player = 0
	_open_club_after_coach = 0
	if _player_card != null and (_player_card.is_open() or _player_card.get_player_id() > 0):
		_player_card.close()
	if _coach_card != null and (_coach_card.is_open() or _coach_card.get_coach_id() > 0):
		_coach_card.close()
	if _national_team_card != null and _national_team_card.is_open():
		_national_team_card.close()
	if _team_card != null and _team_card.get_club_id() > 0:
		_team_card.close()


func _on_players_view_player_requested(player_id: int) -> void:
	if player_id < 1:
		return
	_return_to_directory = _directory_mode
	_show_player_card_view()
	_player_card.open_for(player_id)


func _on_players_view_club_requested(club_id: int) -> void:
	if club_id < 1:
		return
	var unit := _find_unit_for_club(club_id)
	if unit.is_empty():
		return
	_return_to_directory = _directory_mode
	_open_club_card(unit, club_id)


func _on_players_view_country_requested(country_id: int) -> void:
	if country_id < 1:
		return
	_return_to_directory = _directory_mode
	_show_national_team_card_view()
	_national_team_card.open_for(country_id)


func _rebuild_content() -> void:
	if _player_card != null and _player_card.is_open():
		_player_card.refresh()
		return
	if _coach_card != null and _coach_card.is_open():
		_coach_card.refresh()
		return
	if _national_team_card != null and _national_team_card.is_open():
		_national_team_card.refresh()
		return
	if _team_card != null and _team_card.is_open():
		_team_card.refresh()
		return
	if not _directory_mode.is_empty():
		_show_directory(_directory_mode)
		return

	_show_tournament_view()
	var unit := GameSession.get_selected_unit()
	if unit.is_empty():
		_set_playoff_page_mode(false)
		_clear_content()
		_empty_state.visible = true
		_empty_state.text = "Нет доступных турниров"
		return

	_empty_state.visible = false
	_refresh_header()
	var tab := _content_tab_code()
	_set_playoff_page_mode(tab == TAB_PLAYOFF)
	if tab == TAB_PLAYOFF and _try_sync_playoff(unit):
		return

	_clear_content()
	match tab:
		TAB_TABLE:
			_build_table_view(unit)
		TAB_CALENDAR:
			_build_calendar_view(unit)
		TAB_STATS:
			_build_stats_view(unit)
		TAB_PREVIEW:
			_build_preview_view(unit)
		TAB_PLAYOFF:
			_build_playoff_view(unit)
		TAB_HISTORY:
			_build_history_view(unit)


func _set_playoff_page_mode(on: bool) -> void:
	if on:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	else:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		_content.size_flags_vertical = 0


func _try_sync_playoff(unit: Dictionary) -> bool:
	if _playoff_bracket == null or not is_instance_valid(_playoff_bracket):
		return false
	if not _playoff_bracket.matches_unit(unit):
		return false
	var playoff: Dictionary = unit.get("playoff", {})
	if not bool(playoff.get("enabled", false)) or not bool(playoff.get("started", false)):
		return false
	_playoff_bracket.sync(unit, playoff)
	if _playoff_meta != null and is_instance_valid(_playoff_meta):
		_playoff_meta.text = _playoff_meta_text(playoff)
	return true


func _clear_content() -> void:
	_playoff_bracket = null
	_playoff_meta = null
	for child in _content.get_children():
		if child == _empty_state:
			continue
		_content.remove_child(child)
		child.queue_free()


func _show_fatal(message: String) -> void:
	_season_label.text = "—"
	_day_label.text = "—"
	_total_days_label.text = ""
	_advance_day_button.visible = false
	_stop_simulation()
	if _sim_button != null:
		_sim_button.visible = false
	_new_season_button.visible = false
	_tournament_select.clear_items()
	_tab_bar.set_tabs(PackedStringArray())
	_clear_content()
	_empty_state.visible = true
	_empty_state.text = message


func _build_table_view(unit: Dictionary) -> void:
	var divisions: Array = unit.get("divisions", [])

	if divisions.is_empty() or (unit.get("standings", []) as Array).is_empty():
		_content.add_child(_hint_label("В турнире пока нет клубов. Добавьте их в редакторе мира."))
		return

	var multi_div := divisions.size() > 1
	if multi_div:
		_content.add_child(_make_table_mode_select())

	if multi_div and _table_mode == TABLE_MODE_DIVISIONS:
		_content.add_child(_divisions_two_columns(unit, divisions))
	elif multi_div and _table_mode == TABLE_MODE_OVERALL:
		_content.add_child(_section_title("Общая таблица"))
		_content.add_child(_standings_table(unit, -1))
	else:
		_content.add_child(_standings_table(unit, 0 if not divisions.is_empty() else -1))


func _make_table_mode_select() -> WeSelectField:
	var select := WeSelectScene.instantiate() as WeSelectField
	select.label = "Вид таблицы"
	select.compact = true
	select.custom_minimum_size = Vector2(240, 0)
	select.set_items([
		{"id": TABLE_MODE_DIVISIONS, "label": "Дивизионы"},
		{"id": TABLE_MODE_OVERALL, "label": "Общая таблица"},
	], _table_mode)
	select.item_selected.connect(func(_index: int):
		var mode: Variant = select.selected_id
		if mode == null:
			return
		_table_mode = str(mode)
		_rebuild_content()
	)
	return select


func _divisions_two_columns(unit: Dictionary, divisions: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0
	left.add_theme_constant_override("separation", 14)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.add_theme_constant_override("separation", 14)

	row.add_child(left)
	row.add_child(right)

	for i in divisions.size():
		var division: Dictionary = divisions[i]
		var div_index: int = int(division.get("index", i))
		var col: VBoxContainer = left if i % 2 == 0 else right
		var block := VBoxContainer.new()
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.add_theme_constant_override("separation", 6)
		block.add_child(_section_title("Дивизион %d" % (div_index + 1)))
		block.add_child(_standings_table(unit, div_index))
		col.add_child(block)

	return row


func _standings_table(unit: Dictionary, division: int) -> PanelContainer:
	var panel := _surface_panel()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	root.add_child(_table_header_row())

	var rows := GameSession.sorted_standings(unit, division)
	if rows.is_empty():
		root.add_child(_hint_label("Пусто"))
		return panel

	for i in rows.size():
		root.add_child(_table_data_row(unit, rows[i], i + 1, i % 2 == 1))
	return panel


func _table_header_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 0, 8, 6))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	row.add_child(cols)
	cols.add_child(_col_label("#", 28, WeTokens.TEXT_DIM))
	cols.add_child(_col_label("", LOGO_SIZE + 4, WeTokens.TEXT_DIM))
	cols.add_child(_col_label("Клуб", 0, WeTokens.TEXT_DIM, true))
	for title in ["И", "В", "Н", "П", "Мячи", "РМ", "О"]:
		cols.add_child(_col_label(title, 40, WeTokens.TEXT_DIM))
	return row


func _table_data_row(unit: Dictionary, standing: Dictionary, place: int, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 8, 6))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	row.add_child(cols)

	var club_id: int = int(standing.get("club_id", 0))
	cols.add_child(_col_label(str(place), 28, WeTokens.TEXT_MUTED))
	cols.add_child(_club_logo_rect(unit, club_id, LOGO_SIZE))
	cols.add_child(_club_link(unit, club_id))
	cols.add_child(_col_label(str(standing.get("played", 0)), 40, WeTokens.TEXT))
	cols.add_child(_col_label(str(standing.get("won", 0)), 40, WeTokens.TEXT))
	cols.add_child(_col_label(str(standing.get("drawn", 0)), 40, WeTokens.TEXT))
	cols.add_child(_col_label(str(standing.get("lost", 0)), 40, WeTokens.TEXT))
	cols.add_child(_col_label("%d:%d" % [
		int(standing.get("goals_for", 0)),
		int(standing.get("goals_against", 0)),
	], 40, WeTokens.TEXT))
	var gd: int = int(standing.get("goal_diff", 0))
	var gd_text := ("+%d" % gd) if gd > 0 else str(gd)
	cols.add_child(_col_label(gd_text, 40, WeTokens.TEXT))
	cols.add_child(_col_label(str(standing.get("points", 0)), 40, WeTokens.ACCENT))
	return row


func _club_link(unit: Dictionary, club_id: int) -> Button:
	var button := Button.new()
	button.text = GameSession.club_name(unit, club_id)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 0
	empty.content_margin_right = 0
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_color_override("font_hover_color", WeTokens.ACCENT)
	button.add_theme_color_override("font_pressed_color", WeTokens.ACCENT_DIM)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_open_club_card.bind(unit, club_id))
	return button


func _club_logo_rect(unit: Dictionary, club_id: int, size: int) -> Control:
	var tex := _club_logo_texture(unit, club_id, size)
	if tex == null:
		var placeholder := ColorRect.new()
		placeholder.custom_minimum_size = Vector2(size, size)
		placeholder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		placeholder.color = Color(1, 1, 1, 0.06)
		return placeholder

	return WeTokens.make_tex_rect(tex, Vector2(size, size))


func _club_logo_texture(unit: Dictionary, club_id: int, _size: int) -> Texture2D:
	var cache_key := str(club_id)
	if _logo_cache.has(cache_key):
		return _logo_cache[cache_key]
	var clubs: Dictionary = unit.get("clubs_by_id", {})
	if not clubs.has(club_id):
		_logo_cache[cache_key] = null
		return null
	var path := str(clubs[club_id].get("logo_path", "")).strip_edges()
	if path.is_empty():
		_logo_cache[cache_key] = null
		return null
	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		_logo_cache[cache_key] = null
		return null
	var texture := WeTokens.texture_from_image(image)
	_logo_cache[cache_key] = texture
	return texture


func _open_club_card(unit: Dictionary, club_id: int) -> void:
	_show_team_card_view()
	_team_card.open_for(unit, club_id)


func _build_stats_view(unit: Dictionary) -> void:
	if not UnitSeasonStatsScript.has_leaders(unit):
		_content.add_child(_hint_label(
			"Матчей ещё не было — бомбардиры и остальные лидеры появятся после первого тура."
		))
		return

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_content.add_child(grid)

	for board in UnitSeasonStatsScript.BOARDS:
		if typeof(board) != TYPE_DICTIONARY:
			continue
		var block := _stats_board(unit, board)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(block)


func _stats_board(unit: Dictionary, board: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 4)
	var field := str(board.get("field", ""))
	var column := str(board.get("column", ""))
	block.add_child(_section_title(str(board.get("title", ""))))

	var panel := _tight_panel()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	block.add_child(panel)

	var rows := UnitSeasonStatsScript.leaders(unit, field)
	root.add_child(_stats_header_row(column))
	if rows.is_empty():
		root.add_child(_hint_label("Пока нет"))
		return block

	for i in rows.size():
		root.add_child(_stats_data_row(unit, rows[i], i + 1, field, i % 2 == 1))
	return block


func _stats_header_row(column: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 0, 4, 2))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	_center_row(cols)
	row.add_child(cols)
	cols.add_child(_dense_label("#", 16, WeTokens.TEXT_DIM))
	cols.add_child(_dense_label("Игрок", 0, WeTokens.TEXT_DIM, true))
	var club := _dense_label("Клуб", 58, WeTokens.TEXT_DIM)
	club.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cols.add_child(club)
	cols.add_child(_dense_metric(column, 36, WeTokens.TEXT_DIM))
	return row


func _stats_data_row(
	unit: Dictionary,
	row: Dictionary,
	place: int,
	field: String,
	zebra: bool
) -> PanelContainer:
	var panel := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 4, 1))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	_center_row(cols)
	panel.add_child(cols)

	var player_id := int(row.get("player_id", 0))
	var player_name := str(row.get("name", "")).strip_edges()
	if player_name.is_empty() and player_id > 0:
		player_name = str(GameSession.get_player(player_id).get("name", "")).strip_edges()
	if player_name.is_empty():
		player_name = "Игрок #%d" % player_id
	var club_id := int(row.get("club_id", 0))

	cols.add_child(_dense_label(str(place), 16, WeTokens.TEXT_MUTED))
	var player := _player_link(player_id, player_name)
	player.add_theme_font_size_override("font_size", 12)
	player.tooltip_text = player_name
	cols.add_child(player)
	cols.add_child(_stats_club_cell(unit, club_id))
	cols.add_child(_dense_metric(
		UnitSeasonStatsScript.format_metric(row, field),
		36,
		WeTokens.ACCENT
	))
	return panel


func _player_link(player_id: int, player_name: String) -> Button:
	var button := Button.new()
	button.text = player_name
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var empty := StyleBoxEmpty.new()
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_color_override("font_color", WeTokens.TEXT)
	button.add_theme_color_override("font_hover_color", WeTokens.ACCENT)
	button.add_theme_color_override("font_pressed_color", WeTokens.ACCENT_DIM)
	button.add_theme_font_size_override("font_size", 13)
	button.pressed.connect(_open_stats_player.bind(player_id))
	return button


func _stats_club_cell(unit: Dictionary, club_id: int) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.custom_minimum_size = Vector2(58, 0)
	box.add_theme_constant_override("separation", 4)
	_center_row(box)
	box.add_child(_club_logo_rect(unit, club_id, 16))
	var short_name := GameSession.club_name(unit, club_id, true)
	var full_name := GameSession.club_name(unit, club_id)
	var label := _dense_label(short_name, 38, WeTokens.TEXT_MUTED)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.tooltip_text = full_name
	box.add_child(label)
	box.tooltip_text = full_name
	return box


func _open_stats_player(player_id: int) -> void:
	if player_id < 1:
		return
	_show_player_card_view()
	_player_card.open_for(player_id)


func _build_calendar_view(unit: Dictionary) -> void:
	var by_day := GameSession.matches_by_day(unit)
	if by_day.is_empty():
		var type_code := str(unit.get("competition_type", ""))
		if type_code != CompetitionTypes.TYPE_DIVISIONS:
			_content.add_child(_hint_label(
				"Календарь для типа «%s» появится на следующем этапе." % CompetitionTypes.type_label(type_code)
			))
		else:
			_content.add_child(_hint_label("Календарь пуст — добавьте клубы и правила матчей в редакторе."))
		return

	for day in by_day.keys():
		var day_num: int = int(day)
		var is_today := day_num == GameSession.season_day
		var title := "День %d" % day_num
		if is_today:
			title += " · сегодня"
		var day_matches: Array = by_day[day]
		var stage := str(day_matches[0].get("stage", "REGULAR")) if not day_matches.is_empty() else "REGULAR"
		var circle := int(day_matches[0].get("circle", 0)) if not day_matches.is_empty() else 0
		if stage == "PLAYOFF":
			title += " · плей-офф"
		elif circle > 0:
			title += " · %d-й круг" % circle
		_content.add_child(_section_title(title))

		var panel := _surface_panel()
		var grid := GridContainer.new()
		grid.columns = CALENDAR_COLUMNS
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_child(grid)

		for i in day_matches.size():
			var cell := _match_row(unit, day_matches[i], i % 2 == 1)
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(cell)
		_content.add_child(panel)


func _match_row(unit: Dictionary, match_row: Dictionary, zebra: bool) -> PanelContainer:
	var row := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.04) if zebra else Color(1, 1, 1, 0.02)
	row.add_theme_stylebox_override("panel", WeTokens.fill(bg, 8, 8, 8))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	row.add_child(cols)

	var home_id: int = int(match_row.get("home_id", 0))
	var away_id: int = int(match_row.get("away_id", 0))

	var home_side := HBoxContainer.new()
	home_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_side.alignment = BoxContainer.ALIGNMENT_END
	home_side.add_theme_constant_override("separation", 4)
	var home_label := _col_label(GameSession.club_name(unit, home_id, false), 0, WeTokens.TEXT, true)
	home_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	home_side.add_child(home_label)
	home_side.add_child(_club_logo_rect(unit, home_id, LOGO_SIZE_CALENDAR))
	cols.add_child(home_side)

	var score := Label.new()
	score.custom_minimum_size = Vector2(64, 0)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if bool(match_row.get("played", false)):
		score.text = _match_score_text(match_row)
		score.add_theme_color_override("font_color", WeTokens.ACCENT)
	else:
		score.text = "—:—"
		score.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	score.add_theme_font_size_override("font_size", 12)
	cols.add_child(score)

	var away_side := HBoxContainer.new()
	away_side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away_side.add_theme_constant_override("separation", 4)
	away_side.add_child(_club_logo_rect(unit, away_id, LOGO_SIZE_CALENDAR))
	away_side.add_child(_col_label(GameSession.club_name(unit, away_id, false), 0, WeTokens.TEXT, true))
	cols.add_child(away_side)
	return row


func _match_score_text(match_row: Dictionary) -> String:
	var text := "%d:%d" % [
		int(match_row.get("home_goals", 0)),
		int(match_row.get("away_goals", 0)),
	]
	var shootout: Dictionary = match_row.get("shootout", {})
	if shootout.is_empty():
		var report: Dictionary = match_row.get("report", {})
		if typeof(report) == TYPE_DICTIONARY:
			shootout = report.get("shootout", {})
	if typeof(shootout) == TYPE_DICTIONARY and not shootout.is_empty():
		return "%s пен" % text
	if bool(match_row.get("extra_time", false)):
		return "%s д.в." % text
	var report: Dictionary = match_row.get("report", {})
	if typeof(report) == TYPE_DICTIONARY and bool(report.get("extra_time", false)):
		return "%s д.в." % text
	return text


func _playoff_meta_text(playoff: Dictionary) -> String:
	var meta_parts: PackedStringArray = PackedStringArray([
		"%d команд" % int(playoff.get("teams", 0)),
		PlayoffRules.format_label(str(playoff.get("format", ""))),
	])
	if str(playoff.get("format", "")) == PlayoffRules.FORMAT_BEST_OF:
		meta_parts.append("до %d побед" % int(playoff.get("series_wins", 3)))
	meta_parts.append(PlayoffRules.seeding_label(str(playoff.get("seeding", ""))))
	if bool(playoff.get("third_place", false)):
		meta_parts.append("матч за 3-е")
	return " · ".join(meta_parts)


func _build_playoff_view(unit: Dictionary) -> void:
	var playoff: Dictionary = unit.get("playoff", {})
	if not bool(playoff.get("enabled", false)):
		_content.add_child(_hint_label("В этом турнире плей-офф не предусмотрен."))
		return

	var meta := Label.new()
	meta.text = _playoff_meta_text(playoff)
	meta.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	meta.add_theme_font_size_override("font_size", 12)
	_content.add_child(meta)
	_playoff_meta = meta

	if not bool(playoff.get("started", false)):
		_content.add_child(_hint_label("Плей-офф ещё не начался — дерево появится после регулярного сезона."))
		return

	_content.add_child(_build_playoff_bracket(unit, playoff))


func _build_playoff_bracket(unit: Dictionary, playoff: Dictionary) -> PanelContainer:
	var panel := _surface_panel()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	panel.add_child(root)

	var bracket = PlayoffBracketViewScript.new()
	bracket.setup(
		unit,
		playoff,
		func(u: Dictionary, p: Dictionary, s: Dictionary, mirrored: bool) -> Control:
			return _playoff_series_card(u, p, s, mirrored),
		func(card: Control, u: Dictionary, p: Dictionary, s: Dictionary) -> void:
			_apply_playoff_card(card, u, p, s)
	)
	root.add_child(bracket)
	_playoff_bracket = bracket
	return panel


func _playoff_series_card(
	unit: Dictionary,
	playoff: Dictionary,
	series: Dictionary,
	mirrored: bool = false
) -> PanelContainer:
	var card := PanelContainer.new()
	card.set_meta("mirrored", mirrored)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	card.add_child(root)

	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(4, 0)
	stripe.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("stripe", stripe)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER

	var home_row := _playoff_team_row_shell(mirrored)
	var away_row := _playoff_team_row_shell(mirrored)
	box.add_child(home_row)
	box.add_child(away_row)
	card.set_meta("home_row", home_row)
	card.set_meta("away_row", away_row)

	if mirrored:
		root.add_child(box)
		root.add_child(stripe)
	else:
		root.add_child(stripe)
		root.add_child(box)

	_apply_playoff_card(card, unit, playoff, series)
	return card


func _playoff_team_row_shell(mirrored: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var logo_host := Control.new()
	logo_host.custom_minimum_size = Vector2(24, 24)
	logo_host.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo_host.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name := Label.new()
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if mirrored else HORIZONTAL_ALIGNMENT_LEFT
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name.add_theme_font_size_override("font_size", 13)

	var chip := PanelContainer.new()
	var score := Label.new()
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.custom_minimum_size = Vector2(22, 0)
	score.add_theme_font_size_override("font_size", 13)
	chip.add_child(score)

	if mirrored:
		row.add_child(chip)
		row.add_child(name)
		row.add_child(logo_host)
	else:
		row.add_child(logo_host)
		row.add_child(name)
		row.add_child(chip)

	row.set_meta("logo_host", logo_host)
	row.set_meta("name", name)
	row.set_meta("chip", chip)
	row.set_meta("score", score)
	return row


func _playoff_total_rounds(playoff: Dictionary) -> int:
	var n := maxi(int(playoff.get("teams", 2)), 2)
	var rounds := 0
	while n > 1:
		n = int(ceil(float(n) / 2.0))
		rounds += 1
	return maxi(rounds, 1)


func _apply_playoff_card(
	card: Control,
	unit: Dictionary,
	playoff: Dictionary,
	series: Dictionary
) -> void:
	var complete := bool(series.get("complete", false))
	var winner_id: int = int(series.get("winner_id", 0))
	var current := not series.is_empty() \
		and int(series.get("round", 0)) == int(playoff.get("current_round", 0)) \
		and not complete
	var is_final := not series.is_empty() \
		and not bool(series.get("is_third_place", false)) \
		and int(series.get("round", 0)) == _playoff_total_rounds(playoff)
	var champion := is_final and complete and winner_id > 0

	var border := Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.12)
	var bg := Color(0.11, 0.15, 0.2, 0.94)
	if champion:
		border = Color(0.98, 0.82, 0.42, 0.7)
		bg = Color(0.18, 0.15, 0.09, 0.96)
	elif complete:
		border = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.42)
		bg = Color(0.12, 0.18, 0.22, 0.96)
	elif current:
		border = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.72)
		bg = Color(0.14, 0.22, 0.26, 0.98)
	elif series.is_empty():
		bg = Color(0.12, 0.16, 0.2, 0.7)
		border = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.08)

	var style := WeTokens.elevated(bg, border, WeTokens.RADIUS_MD, 8, 14.0 if (current or champion) else 8.0)
	style.set_border_width_all(1 if not current and not champion else 2)
	card.add_theme_stylebox_override("panel", style)

	var stripe: ColorRect = card.get_meta("stripe")
	if champion:
		stripe.color = Color(0.98, 0.82, 0.42, 0.95)
	elif complete:
		stripe.color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.85)
	elif current:
		stripe.color = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.7)
	else:
		stripe.color = Color(1, 1, 1, 0.08)

	var format := PlayoffRules.normalize_format(playoff.get("format", PlayoffRules.FORMAT_DEFAULT))
	_apply_playoff_team_row(
		card.get_meta("home_row"), unit, series, true, format, winner_id, complete, current
	)
	_apply_playoff_team_row(
		card.get_meta("away_row"), unit, series, false, format, winner_id, complete, current
	)


func _apply_playoff_team_row(
	row: HBoxContainer,
	unit: Dictionary,
	series: Dictionary,
	is_home: bool,
	format: String,
	winner_id: int,
	complete: bool,
	is_current: bool
) -> void:
	var club_id: int = int(series.get("home_id" if is_home else "away_id", 0))
	var is_winner := complete and winner_id > 0 and winner_id == club_id
	var is_loser := complete and winner_id > 0 and club_id > 0 and winner_id != club_id
	row.modulate = Color(1, 1, 1, 0.42) if is_loser else Color.WHITE

	var name: Label = row.get_meta("name")
	if club_id < 1:
		name.text = "TBD"
		name.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		name.remove_theme_font_override("font")
	else:
		name.text = GameSession.club_name(unit, club_id, false)
		if is_winner:
			var font := WeTokens.font_semibold()
			if font != null:
				name.add_theme_font_override("font", font)
			name.add_theme_color_override("font_color", WeTokens.ACCENT)
		else:
			name.remove_theme_font_override("font")
			name.add_theme_color_override("font_color", WeTokens.TEXT)

	var score_text := "—"
	if club_id > 0:
		if format == PlayoffRules.FORMAT_TWO_LEGGED:
			score_text = str(int(series.get("home_goals" if is_home else "away_goals", 0)))
		else:
			score_text = str(int(series.get("home_wins" if is_home else "away_wins", 0)))

	var score: Label = row.get_meta("score")
	score.text = score_text
	var chip: PanelContainer = row.get_meta("chip")
	var bg := Color(1, 1, 1, 0.05)
	var fg := WeTokens.TEXT_MUTED
	if is_winner:
		bg = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.22)
		fg = WeTokens.ACCENT
		var font := WeTokens.font_semibold()
		if font != null:
			score.add_theme_font_override("font", font)
	else:
		score.remove_theme_font_override("font")
		if is_current and not is_loser and club_id > 0:
			bg = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.1)
			fg = WeTokens.TEXT
	chip.add_theme_stylebox_override("panel", WeTokens.fill(bg, 8, 8, 2))
	score.add_theme_color_override("font_color", fg)

	_set_playoff_logo(row.get_meta("logo_host"), unit, club_id)


func _set_playoff_logo(host: Control, unit: Dictionary, club_id: int) -> void:
	if int(host.get_meta("club_id", -999)) == club_id and host.get_child_count() > 0:
		return
	host.set_meta("club_id", club_id)
	for child in host.get_children():
		host.remove_child(child)
		child.queue_free()
	var logo := _club_logo_rect(unit, club_id, 24)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(logo)


func _build_preview_view(unit: Dictionary) -> void:
	var preview: Dictionary = unit.get("season_preview", {})
	var ready := int(preview.get("season", 0)) == GameSession.season_number \
		and not (preview.get("sections", []) as Array).is_empty()
	if GameSession.is_market_day() or not ready:
		var waiting := "Превью появится после закрытия трансферного окна, перед первым туром."
		if not GameSession.is_market_day() and GameSession.season_day > GameSession.FIRST_MATCH_DAY:
			waiting = "Превью этого сезона не составлялось. Следующее появится перед первым туром."
		_content.add_child(_hint_label(waiting))
		return

	_content.add_child(_dense_hint(
		"Сезон %d, перед первым туром. Состав, репутация клуба и главный тренер." % GameSession.season_number
	))
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 10)
	_content.add_child(columns)
	for section in preview.get("sections", []):
		if typeof(section) != TYPE_DICTIONARY:
			continue
		var block := _preview_section(unit, section)
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		block.size_flags_stretch_ratio = 1.0
		columns.add_child(block)


func _preview_section(unit: Dictionary, section: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 2)
	block.add_child(_section_title(str(section.get("title", "Превью"))))
	var note := str(section.get("note", "")).strip_edges()
	if not note.is_empty():
		block.add_child(_dense_hint(note))

	var kind := str(section.get("kind", "table"))
	var panel := _tight_panel()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	panel.add_child(list)
	block.add_child(panel)
	list.add_child(_preview_header(kind))
	var rows: Array = section.get("rows", [])
	if rows.is_empty():
		list.add_child(_hint_label("Некого оценивать"))
		return block
	for i in rows.size():
		var row: Dictionary = rows[i]
		list.add_child(_preview_row(unit, row, kind, i % 2 == 1))
	return block


func _preview_header(kind: String) -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 0, 4, 2))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	_center_row(cols)
	row.add_child(cols)
	cols.add_child(_dense_label("#", 16, WeTokens.TEXT_DIM))
	var logo_slot := Control.new()
	logo_slot.custom_minimum_size = Vector2(16, 0)
	cols.add_child(logo_slot)
	cols.add_child(_dense_label("Клуб", 0, WeTokens.TEXT_DIM, true))
	if kind == "knockout":
		var stage_title := _dense_label("Стадия", 72, WeTokens.TEXT_DIM)
		stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cols.add_child(stage_title)
	if kind == "playoff" or kind == "qualify":
		cols.add_child(_dense_metric("Выход", 44, WeTokens.TEXT_DIM))
	if kind != "qualify":
		cols.add_child(_dense_metric("Титул", 44, WeTokens.TEXT_DIM))
	return row


func _preview_row(unit: Dictionary, row: Dictionary, kind: String, zebra: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var place := int(row.get("place", 0))
	var bg := Color(1, 1, 1, 0.03) if zebra else Color(0, 0, 0, 0)
	if place == 1:
		bg = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.1)
	panel.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 4, 1))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 4)
	_center_row(cols)
	panel.add_child(cols)
	var club_id := int(row.get("club_id", 0))
	cols.add_child(_dense_label(str(place), 16, _history_place_color(place)))
	cols.add_child(_club_logo_rect(unit, club_id, 16))
	var link := _club_link(unit, club_id)
	link.add_theme_font_size_override("font_size", 12)
	var stored := str(row.get("club_name", "")).strip_edges()
	if not stored.is_empty() and link.text.begins_with("Клуб #"):
		link.text = stored
	link.tooltip_text = link.text
	cols.add_child(link)
	if kind == "knockout":
		var stage := _dense_label(str(row.get("stage", "—")), 72, WeTokens.TEXT)
		stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		cols.add_child(stage)
	if kind == "playoff" or kind == "qualify":
		cols.add_child(_dense_metric(_preview_chance_text(float(row.get("qualify_chance", 0.0))), 44, WeTokens.TEXT))
	if kind != "qualify":
		var chance := float(row.get("title_chance", 0.0))
		var color := WeTokens.ACCENT if place == 1 else WeTokens.TEXT
		cols.add_child(_dense_metric(_preview_chance_text(chance), 44, color))
	return panel


func _preview_chance_text(chance: float) -> String:
	if chance < 0.5:
		return "<1%"
	if chance >= 10.0:
		return "%d%%" % int(round(chance))
	return "%.1f%%" % chance


func _build_history_view(unit: Dictionary) -> void:
	var winners: Array = []
	for entry in unit.get("winners", []):
		if typeof(entry) == TYPE_DICTIONARY:
			winners.append(entry)
	if winners.is_empty():
		_content.add_child(_hint_label("История победителей пуста — новый турнир, сезон только начался."))
		return
	winners.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("season", 0)) > int(b.get("season", 0))
	)

	var table := _surface_panel()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	table.add_child(list)
	list.add_child(_history_header())
	for i in winners.size():
		list.add_child(_history_season_row(unit, winners[i], i % 2 == 1))
	_content.add_child(table)


func _history_header() -> PanelContainer:
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", WeTokens.fill(WeTokens.INSET, 0, 12, 10))
	var cols := _history_line()
	row.add_child(cols)
	cols.add_child(_history_title("Сезон", false))
	cols.add_child(_history_title("Плей-офф", true))
	var regular := _history_title("Регулярный сезон", true)
	regular.size_flags_stretch_ratio = 3.0
	cols.add_child(regular)
	return row


func _history_title(text: String, expand: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 11)
	var font := WeTokens.font_semibold()
	if font != null:
		label.add_theme_font_override("font", font)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.size_flags_stretch_ratio = 4.0
	else:
		label.custom_minimum_size = Vector2(96, 0)
	return label


func _history_season_row(unit: Dictionary, entry: Dictionary, zebra: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	var bg := Color(1, 1, 1, 0.035) if zebra else Color(0, 0, 0, 0)
	panel.add_theme_stylebox_override("panel", WeTokens.fill(bg, 0, 8, 8))
	var cols := _history_line()
	panel.add_child(cols)

	var season := Label.new()
	season.text = "Сезон %d" % int(entry.get("season", 0))
	season.custom_minimum_size = Vector2(96, 36)
	season.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	season.add_theme_color_override("font_color", WeTokens.TEXT)
	season.add_theme_font_size_override("font_size", 14)
	var font := WeTokens.font_semibold()
	if font != null:
		season.add_theme_font_override("font", font)
	cols.add_child(season)

	var playoff_rows: Array = entry.get("playoff", []) if typeof(entry.get("playoff")) == TYPE_ARRAY else []
	if playoff_rows.is_empty() and not entry.has("playoff"):
		var champion_id := int(entry.get("club_id", 0))
		if champion_id > 0:
			playoff_rows = [{
				"place": 1,
				"club_id": champion_id,
				"club_name": str(entry.get("club_name", "")),
			}]
	var regular_rows: Array = entry.get("regular", []) if typeof(entry.get("regular")) == TYPE_ARRAY else []
	cols.add_child(_history_place_group(unit, playoff_rows, 4))
	cols.add_child(_history_place_group(unit, regular_rows, 3))
	return panel


func _history_line() -> HBoxContainer:
	var line := HBoxContainer.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_theme_constant_override("separation", 10)
	_center_row(line)
	return line


func _history_place_group(unit: Dictionary, rows: Array, slots: int) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.size_flags_stretch_ratio = float(slots)
	group.add_theme_constant_override("separation", 6)
	_center_row(group)
	if rows.is_empty():
		var empty := _history_club_slot(unit, {}, 0)
		empty.size_flags_stretch_ratio = float(slots)
		group.add_child(empty)
		return group
	var by_place := {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		by_place[int(row.get("place", 0))] = row
	for place in range(1, slots + 1):
		group.add_child(_history_club_slot(unit, by_place.get(place, {}), place))
	return group


func _history_club_slot(unit: Dictionary, row: Dictionary, place: int) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.size_flags_stretch_ratio = 1.0
	var bg := Color(1, 1, 1, 0.045)
	if place == 1 and not row.is_empty():
		bg = Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.14)
	chip.add_theme_stylebox_override("panel", WeTokens.fill(bg, 8, 8, 6))
	if row.is_empty():
		var dash := Label.new()
		dash.text = "—"
		dash.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dash.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		dash.custom_minimum_size = Vector2(0, 28)
		dash.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
		dash.add_theme_font_size_override("font_size", 13)
		chip.add_child(dash)
		return chip

	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_center_row(box)
	chip.add_child(box)

	var mark := Label.new()
	mark.text = str(place)
	mark.custom_minimum_size = Vector2(14, 22)
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", _history_place_color(place))
	mark.add_theme_font_size_override("font_size", 13)
	var font := WeTokens.font_semibold()
	if font != null:
		mark.add_theme_font_override("font", font)
	box.add_child(mark)

	var club_id := int(row.get("club_id", 0))
	box.add_child(_club_logo_rect(unit, club_id, 22))
	var link := _club_link(unit, club_id)
	link.add_theme_font_size_override("font_size", 13)
	var stored_name := str(row.get("club_name", "")).strip_edges()
	if not stored_name.is_empty() and link.text.begins_with("Клуб #"):
		link.text = stored_name
	link.tooltip_text = link.text
	box.add_child(link)
	return chip


func _history_place_color(place: int) -> Color:
	match place:
		1:
			return WeTokens.ACCENT
		2:
			return Color(0.78, 0.84, 0.9, 1.0)
		3:
			return Color(0.82, 0.62, 0.42, 1.0)
		_:
			return WeTokens.TEXT_DIM


func _surface_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, WeTokens.RADIUS_MD, 12)
	)
	return panel


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)
	label.add_theme_font_size_override("font_size", 13)
	return label


func _hint_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	label.add_theme_font_size_override("font_size", 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _info_line(title: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var t := Label.new()
	t.text = title
	t.custom_minimum_size = Vector2(120, 0)
	t.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	t.add_theme_font_size_override("font_size", 13)
	row.add_child(t)
	var v := Label.new()
	v.text = value
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_color_override("font_color", WeTokens.TEXT)
	v.add_theme_font_size_override("font_size", 13)
	row.add_child(v)
	return row


func _col_label(text: String, width: int, color: Color, expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 13)
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.custom_minimum_size.y = 22
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif width > 0:
		label.custom_minimum_size.x = width
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _metric_label(text: String, width: int, color: Color) -> Label:
	var label := _col_label(text, width, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _dense_label(text: String, width: int, color: Color, expand: bool = false) -> Label:
	var label := _col_label(text, width, color, expand)
	label.add_theme_font_size_override("font_size", 12)
	label.custom_minimum_size.y = 16
	return label


func _dense_metric(text: String, width: int, color: Color) -> Label:
	var label := _dense_label(text, width, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _dense_hint(text: String) -> Label:
	var label := _hint_label(text)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _tight_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.SURFACE, WeTokens.BORDER, 8, 6)
	)
	return panel


func _center_row(box: HBoxContainer) -> void:
	box.alignment = BoxContainer.ALIGNMENT_CENTER
