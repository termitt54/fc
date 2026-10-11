extends Node
## Stable desktop window: no exclusive fullscreen (flicker),
## no manual screen-size hacks (mouse offset).


func _ready() -> void:
	var win := get_window()
	win.content_scale_factor = 1.0
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.msaa_2d = Viewport.MSAA_4X
	win.borderless = false
	# Maximized over the desktop — correct mouse hit-testing, no FS flicker.
	if win.mode != Window.MODE_MAXIMIZED:
		win.mode = Window.MODE_MAXIMIZED

	# Ensure typewriter face is the engine fallback even if a Control skips the Theme.
	var app_font := load(WeTokens.FONT_PATH) as Font
	if app_font != null:
		ThemeDB.fallback_font = app_font
