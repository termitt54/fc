class_name WeEntityRow
extends PanelContainer
## Custom selectable row with optional flag/icon and compact distribution chips.


signal pressed(entity_id: int)

const TIER_COLORS := [
	Color(0.98, 0.82, 0.38, 1.0),
	Color(0.72, 0.9, 0.55, 1.0),
	Color(0.38, 0.86, 0.74, 1.0),
	Color(0.4, 0.74, 0.88, 1.0),
	Color(0.55, 0.68, 0.9, 1.0),
	Color(0.62, 0.66, 0.78, 1.0),
	Color(0.52, 0.56, 0.64, 1.0),
]

const TIER_LABELS := [
	"90–100",
	"89–85",
	"84–80",
	"79–70",
	"69–60",
	"59–50",
	"49–40",
]

const FLAG_SIZE := Vector2(36, 24)
const LOGO_SIZE := Vector2(56, 56)

var entity_id: int = -1
var _selected: bool = false
var _hovered: bool = false
var _active: bool = true
var _show_flag: bool = false

@onready var _accent: ColorRect = %Accent
@onready var _flag: TextureRect = %Flag
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _meta: Label = %Meta
@onready var _dist_row: HBoxContainer = %DistRow


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func():
		_hovered = true
		_refresh()
	)
	mouse_exited.connect(func():
		_hovered = false
		_refresh()
	)
	gui_input.connect(_on_gui_input)
	_flag.visible = false
	_dist_row.visible = false
	_refresh()


func setup(
	id: int,
	title: String,
	subtitle: String,
	meta: String,
	active: bool = true,
	icon_path: String = "",
	show_icon: bool = false,
	distribution: Array = [],
	stat_chips: Array = [],
	large_icon: bool = false
) -> void:
	entity_id = id
	_active = active
	if _title == null:
		await ready
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_meta.text = meta
	_meta.visible = not meta.is_empty()
	_set_flag(icon_path, show_icon or not icon_path.is_empty(), large_icon)
	if not stat_chips.is_empty():
		_set_stat_chips(stat_chips)
	else:
		_set_distribution(distribution)
	_refresh()


func set_selected(value: bool) -> void:
	_selected = value
	_refresh()


func is_selected() -> bool:
	return _selected


func _set_flag(path: String, visible_slot: bool, large_icon: bool = false) -> void:
	_show_flag = visible_slot
	_flag.custom_minimum_size = LOGO_SIZE if large_icon else FLAG_SIZE
	if not _show_flag or path.is_empty():
		_flag.texture = null
		_flag.visible = _show_flag and not path.is_empty()
		return

	var abs_path := path
	if path.begins_with("user://") or path.begins_with("res://"):
		abs_path = ProjectSettings.globalize_path(path)
	var image := Image.new()
	if image.load(abs_path) != OK:
		_flag.texture = null
		_flag.visible = false
		return
	_flag.texture = WeTokens.texture_from_image(image)
	_flag.texture_filter = WeTokens.UI_TEX_FILTER
	_flag.visible = true


func _set_distribution(weights: Array) -> void:
	_clear_dist_row()
	if weights.is_empty():
		_dist_row.visible = false
		custom_minimum_size.y = 56
		return

	_dist_row.visible = true
	custom_minimum_size.y = 64 if not _subtitle.visible else 72

	for i in weights.size():
		var value := snappedf(float(weights[i]), 0.01)
		var color: Color = TIER_COLORS[i % TIER_COLORS.size()]
		var tip: String = TIER_LABELS[i] if i < TIER_LABELS.size() else ""
		var tip_text := ("%s: %.2f%%" % [tip, value]) if not tip.is_empty() else ("%.2f%%" % value)
		_dist_row.add_child(_make_chip("%.2f" % value, color, tip_text))


func _set_stat_chips(chips: Array) -> void:
	_clear_dist_row()
	if chips.is_empty():
		_dist_row.visible = false
		custom_minimum_size.y = 56
		return

	_dist_row.visible = true
	custom_minimum_size.y = 64 if not _subtitle.visible else 72

	for i in chips.size():
		var chip: Dictionary = chips[i] as Dictionary
		var value: int = int(chip.get("value", 0))
		var short_label: String = str(chip.get("short", ""))
		var tip: String = str(chip.get("tip", ""))
		var color: Color = TIER_COLORS[i % TIER_COLORS.size()]
		var text := ("%s %d" % [short_label, value]) if not short_label.is_empty() else str(value)
		var tip_text := ("%s: %d" % [tip, value]) if not tip.is_empty() else text
		_dist_row.add_child(_make_chip(text, color, tip_text))


func _clear_dist_row() -> void:
	while _dist_row.get_child_count() > 0:
		var child := _dist_row.get_child(0)
		_dist_row.remove_child(child)
		child.free()


func _make_chip(text: String, color: Color, tip: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chip.tooltip_text = tip
	var bg := Color(color.r, color.g, color.b, 0.16)
	var border := Color(color.r, color.g, color.b, 0.35)
	chip.add_theme_stylebox_override("panel", WeTokens.panel(bg, border, 6, 0))

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color.lightened(0.15))
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit(entity_id)
			accept_event()


func _refresh() -> void:
	var pad_v := 8 if _dist_row.visible else 9
	var box: StyleBoxFlat
	if _selected:
		box = WeTokens.panel(WeTokens.ACCENT_SOFT_STRONG, Color(WeTokens.ACCENT.r, WeTokens.ACCENT.g, WeTokens.ACCENT.b, 0.35), WeTokens.RADIUS_SM, 0)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = pad_v
		box.content_margin_bottom = pad_v
	elif _hovered:
		box = WeTokens.panel(Color(1, 1, 1, 0.06), WeTokens.BORDER, WeTokens.RADIUS_SM, 0)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = pad_v
		box.content_margin_bottom = pad_v
	else:
		box = WeTokens.fill(Color(1, 1, 1, 0.02), WeTokens.RADIUS_SM, 10, pad_v)

	add_theme_stylebox_override("panel", box)

	_accent.color = WeTokens.ACCENT if _selected else Color(0, 0, 0, 0)
	_title.add_theme_color_override("font_color", WeTokens.TEXT if _active else WeTokens.TEXT_DIM)
	_subtitle.add_theme_color_override(
		"font_color",
		WeTokens.ACCENT if _selected else (WeTokens.TEXT_MUTED if _active else WeTokens.TEXT_DIM)
	)
	_meta.add_theme_color_override("font_color", WeTokens.TEXT_MUTED if _selected else WeTokens.TEXT_DIM)
