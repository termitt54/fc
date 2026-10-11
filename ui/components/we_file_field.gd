class_name WeFileField
extends VBoxContainer
## File picker — chrome height matches WeTextField (compact 32 / normal 40).


signal file_changed(path: String)

@export var label: String = "Файл":
	set(value):
		label = value
		if _label != null:
			_label.text = label

@export var compact: bool = false:
	set(value):
		compact = value
		if is_node_ready():
			_apply_density()

@export var filters: PackedStringArray = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.svg;Images"])

var selected_path: String = ""
var _existing_path: String = ""
var _cleared: bool = false
var _disabled: bool = false

@onready var _label: Label = %Label
@onready var _chrome: PanelContainer = %Chrome
@onready var _preview: TextureRect = %Preview
@onready var _path_label: Label = %PathLabel
@onready var _pick_button: Button = %PickButton
@onready var _clear_button: Button = %ClearButton
@onready var _dialog: FileDialog = %FileDialog


func _ready() -> void:
	_label.text = label
	_label.add_theme_color_override("font_color", WeTokens.TEXT_MUTED)

	_chrome.clip_contents = true
	_pick_button.pressed.connect(_on_pick_pressed)
	_clear_button.pressed.connect(_on_clear_pressed)

	if compact:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.use_native_dialog = true
	_dialog.filters = filters
	_dialog.file_selected.connect(_on_file_selected)
	_apply_density()
	_refresh_view()


func _apply_density() -> void:
	if _label == null or _chrome == null:
		return
	add_theme_constant_override("separation", 3 if compact else 6)
	_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	_chrome.custom_minimum_size = Vector2(0, 32 if compact else 40)
	var pad := 8 if compact else 10
	_chrome.add_theme_stylebox_override(
		"panel",
		WeTokens.panel(WeTokens.INSET, WeTokens.BORDER, WeTokens.RADIUS_SM, pad)
	)
	_path_label.add_theme_color_override("font_color", WeTokens.TEXT_DIM)
	_path_label.add_theme_font_size_override("font_size", 12 if compact else 14)
	_preview.custom_minimum_size = Vector2(22, 16) if compact else Vector2(28, 18)
	_style_inline_button(_pick_button, WeTokens.TEXT_MUTED, WeTokens.ACCENT)
	_style_inline_button(_clear_button, WeTokens.TEXT_DIM, WeTokens.DANGER)


func _style_inline_button(button: Button, color: Color, hover: Color) -> void:
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 4
	empty.content_margin_right = 4
	empty.content_margin_top = 0
	empty.content_margin_bottom = 0
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2.ZERO
	button.add_theme_stylebox_override("normal", empty)
	button.add_theme_stylebox_override("hover", empty)
	button.add_theme_stylebox_override("pressed", empty)
	button.add_theme_stylebox_override("focus", empty)
	button.add_theme_stylebox_override("disabled", empty)
	button.add_theme_color_override("font_color", color)
	button.add_theme_color_override("font_hover_color", hover)
	button.add_theme_color_override("font_pressed_color", hover.darkened(0.15))
	button.add_theme_color_override("font_disabled_color", WeTokens.TEXT_DIM)
	button.add_theme_font_size_override("font_size", 11 if compact else 13)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func set_existing_path(path: String) -> void:
	_existing_path = path
	selected_path = ""
	_cleared = false
	_refresh_view()


func clear_selection() -> void:
	selected_path = ""
	_existing_path = ""
	_cleared = false
	_refresh_view()


func was_cleared() -> bool:
	return _cleared


func set_disabled(disabled: bool) -> void:
	_disabled = disabled
	if _pick_button != null:
		_pick_button.disabled = disabled
	if _clear_button != null:
		_clear_button.disabled = disabled


func _on_pick_pressed() -> void:
	if _disabled:
		return
	_dialog.popup_centered_ratio(0.6)


func _on_clear_pressed() -> void:
	if _disabled:
		return
	selected_path = ""
	_cleared = not _existing_path.is_empty()
	if _cleared:
		_existing_path = ""
	_refresh_view()
	file_changed.emit("")


func _on_file_selected(path: String) -> void:
	selected_path = path
	_cleared = false
	_refresh_view()
	file_changed.emit(path)


func _refresh_view() -> void:
	if _path_label == null:
		return
	var path := selected_path if not selected_path.is_empty() else _existing_path
	if path.is_empty():
		_path_label.text = "Не выбран"
		_preview.texture = null
		_clear_button.visible = false
		return

	_path_label.text = path.get_file()
	_clear_button.visible = true
	_preview.texture = _load_preview(path)


func _load_preview(path: String) -> Texture2D:
	var image := Image.new()
	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var err := image.load(abs_path)
	if err != OK:
		return null
	return WeTokens.texture_from_image(image)
