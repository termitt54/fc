class_name ReputationStars
extends Control
## Classic filled star rating (solid asset).
## 0..900 fills gold; 900..1000 paints red (20 pts per star).


const STAR_PATH := "res://assets/icons/reputation_star.png"
const STAR_COUNT := 5
const GOLD_CAP := 900
const RED_PER_STAR := 20
const MAX_REPUTATION := 1000

const EMPTY := Color(0.30, 0.34, 0.40, 0.95)
const GOLD := Color(0.95, 0.78, 0.32, 1.0)
const RED := Color(0.92, 0.38, 0.34, 1.0)

var reputation: int = 0:
	set(value):
		reputation = clampi(value, 0, MAX_REPUTATION)
		_sync_tip_text()
		queue_redraw()

var star_size: float = 16.0:
	set(value):
		star_size = value
		_refresh_min_size()
		queue_redraw()

var star_gap: float = 3.0:
	set(value):
		star_gap = value
		_refresh_min_size()
		queue_redraw()

var _star_tex: Texture2D
var _tip: PanelContainer
var _tip_label: Label
var _tip_visible: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	texture_filter = WeTokens.UI_TEX_FILTER
	_ensure_star_tex()
	_refresh_min_size()
	_build_tip()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _ensure_star_tex() -> void:
	if _star_tex != null:
		return
	# Prefer raw image so asset swaps apply even if an old import is cached.
	var img := Image.new()
	if img.load(STAR_PATH) == OK:
		img.generate_mipmaps()
		_star_tex = ImageTexture.create_from_image(img)
		return
	if ResourceLoader.exists(STAR_PATH):
		var loaded := load(STAR_PATH)
		if loaded is Texture2D:
			_star_tex = loaded


func _refresh_min_size() -> void:
	custom_minimum_size = Vector2(
		STAR_COUNT * star_size + (STAR_COUNT - 1) * star_gap,
		star_size
	)


func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.top_level = true
	_tip.z_index = 40
	var box := WeTokens.panel(WeTokens.SURFACE_RAISED, WeTokens.BORDER_STRONG, WeTokens.RADIUS_SM, 0)
	box.shadow_color = Color(0.02, 0.04, 0.08, 0.35)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 2)
	_tip.add_theme_stylebox_override("panel", box)
	add_child(_tip)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 7)
	pad.add_theme_constant_override("margin_right", 7)
	pad.add_theme_constant_override("margin_top", 3)
	pad.add_theme_constant_override("margin_bottom", 3)
	_tip.add_child(pad)

	_tip_label = Label.new()
	_tip_label.add_theme_color_override("font_color", WeTokens.TEXT)
	_tip_label.add_theme_font_size_override("font_size", 11)
	pad.add_child(_tip_label)
	_sync_tip_text()


func _sync_tip_text() -> void:
	if _tip_label == null:
		return
	_tip_label.text = "%d / 1000" % reputation


func _on_mouse_entered() -> void:
	_tip_visible = true
	_sync_tip_text()
	_tip.visible = true
	_tip.modulate.a = 0.0
	_place_tip()
	var tween := create_tween()
	tween.tween_property(_tip, "modulate:a", 1.0, 0.1)


func _on_mouse_exited() -> void:
	_tip_visible = false
	var tween := create_tween()
	tween.tween_property(_tip, "modulate:a", 0.0, 0.08)
	tween.finished.connect(func():
		if not _tip_visible and is_instance_valid(_tip):
			_tip.visible = false
	)


func _place_tip() -> void:
	if _tip == null:
		return
	_tip.reset_size()
	var tip_size := _tip.get_combined_minimum_size()
	_tip.size = tip_size
	var global_center := get_global_transform_with_canvas().origin + Vector2(size.x * 0.5, 0.0)
	_tip.global_position = global_center - Vector2(tip_size.x * 0.5, tip_size.y + 6.0)


func _draw() -> void:
	_ensure_star_tex()
	if _star_tex == null:
		return

	var gold_fill := clampf(float(mini(reputation, GOLD_CAP)) / float(GOLD_CAP) * float(STAR_COUNT), 0.0, float(STAR_COUNT))
	var red_fill := 0.0
	if reputation > GOLD_CAP:
		red_fill = clampf(float(reputation - GOLD_CAP) / float(RED_PER_STAR), 0.0, float(STAR_COUNT))

	for i in STAR_COUNT:
		var origin := Vector2(float(i) * (star_size + star_gap), 0.0)
		var gold_part := 1.0 if reputation >= GOLD_CAP else clampf(gold_fill - float(i), 0.0, 1.0)
		var red_part := clampf(red_fill - float(i), 0.0, 1.0)
		_draw_star(origin, gold_part, red_part)


func _draw_star(origin: Vector2, gold_part: float, red_part: float) -> void:
	var dest := Rect2(origin, Vector2(star_size, star_size))
	draw_texture_rect(_star_tex, dest, false, EMPTY)

	if gold_part > 0.001:
		_draw_star_partial(origin, gold_part, GOLD)
	if red_part > 0.001:
		_draw_star_partial(origin, red_part, RED)


func _draw_star_partial(origin: Vector2, fill_ratio: float, color: Color) -> void:
	var ratio := clampf(fill_ratio, 0.0, 1.0)
	if ratio <= 0.0:
		return
	var tex_w := float(_star_tex.get_width())
	var tex_h := float(_star_tex.get_height())
	var src_w := tex_w * ratio
	var dst_w := star_size * ratio
	draw_texture_rect_region(
		_star_tex,
		Rect2(origin, Vector2(dst_w, star_size)),
		Rect2(0.0, 0.0, src_w, tex_h),
		color
	)
