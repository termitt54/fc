class_name WeTokens
extends RefCounted
## Shared design tokens — deeper surfaces, soft volume, teal accent.


# Atmosphere: cool slate, not pure black.
const BG := Color(0.09, 0.11, 0.145, 1.0)
const BG_DEEP := Color(0.07, 0.085, 0.12, 1.0)
const SURFACE := Color(0.145, 0.17, 0.22, 1.0)
const SURFACE_RAISED := Color(0.18, 0.21, 0.27, 1.0)
const INSET := Color(0.1, 0.125, 0.17, 1.0)

const BORDER := Color(0.55, 0.72, 0.78, 0.14)
const BORDER_STRONG := Color(0.55, 0.72, 0.78, 0.28)
const BORDER_FOCUS := Color(0.35, 0.82, 0.72, 0.55)

const TEXT := Color(0.95, 0.97, 0.98, 1.0)
const TEXT_MUTED := Color(0.72, 0.8, 0.84, 1.0)
const TEXT_DIM := Color(0.52, 0.6, 0.66, 1.0)

# Teal — pitch / freshness, not purple.
const ACCENT := Color(0.32, 0.86, 0.74, 1.0)
const ACCENT_DIM := Color(0.22, 0.62, 0.55, 1.0)
const ACCENT_SOFT := Color(0.28, 0.78, 0.68, 0.18)
const ACCENT_SOFT_STRONG := Color(0.28, 0.78, 0.68, 0.28)

const DANGER := Color(0.95, 0.48, 0.5, 1.0)
const DANGER_SOFT := Color(0.95, 0.42, 0.45, 0.16)
const SUCCESS := Color(0.45, 0.86, 0.62, 1.0)
const SUCCESS_SOFT := Color(0.35, 0.78, 0.55, 0.16)

const RADIUS_SM := 10
const RADIUS_MD := 14
const RADIUS_LG := 18

## Project UI face (Latin + Cyrillic). Prefer project Theme; use for explicit overrides.
const FONT_PATH := "res://assets/fonts/Inter-Regular.otf"
const FONT_SEMIBOLD_PATH := "res://assets/fonts/Inter-SemiBold.otf"

const UI_TEX_FILTER := CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
const UI_TEX_MAX_EDGE := 256


static func font() -> Font:
	return load(FONT_PATH) as Font


static func font_semibold() -> Font:
	return load(FONT_SEMIBOLD_PATH) as Font


static func apply_font(control: Control) -> void:
	var f := font()
	if f == null or control == null:
		return
	control.add_theme_font_override("font", f)


static func polish_style(box: StyleBoxFlat) -> StyleBoxFlat:
	box.anti_aliasing = true
	box.anti_aliasing_size = 1.0
	return box


static func fit_size(source: Vector2i, target_h: int, min_w: int, max_w: int) -> Vector2:
	var height := maxi(target_h, 1)
	var width := int(round(float(source.x) / float(maxi(source.y, 1)) * float(height)))
	return Vector2(clampi(width, min_w, max_w), height)


static func texture_from_image(image: Image, max_edge: int = UI_TEX_MAX_EDGE) -> ImageTexture:
	if image == null or image.is_empty():
		return null
	var width := image.get_width()
	var height := image.get_height()
	var longest := maxi(width, height)
	if longest > max_edge:
		var scale := float(max_edge) / float(longest)
		image.resize(
			maxi(1, int(round(float(width) * scale))),
			maxi(1, int(round(float(height) * scale))),
			Image.INTERPOLATE_LANCZOS
		)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


static func make_tex_rect(tex: Texture2D, display: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = display
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.texture_filter = UI_TEX_FILTER
	return rect


static func panel(bg: Color, border: Color, radius: int, pad: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return polish_style(box)


static func elevated(bg: Color, border: Color, radius: int, pad: int, shadow: float = 10.0) -> StyleBoxFlat:
	var box := panel(bg, border, radius, pad)
	box.shadow_color = Color(0.02, 0.04, 0.08, 0.45)
	box.shadow_size = int(shadow)
	box.shadow_offset = Vector2(0, 4)
	return box


static func fill(bg: Color, radius: int, pad_h: int = 0, pad_v: int = 0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_h
	box.content_margin_right = pad_h
	box.content_margin_top = pad_v
	box.content_margin_bottom = pad_v
	return polish_style(box)
