extends Node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var settings := preload("res://scenes/settings/settings.tscn").instantiate()
	add_child(settings)
	settings.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tab: Variant = settings.get_node("%GlobalPa")
	tab._show_all.button_pressed = true
	for i in 8:
		await get_tree().process_frame
	var scroll: ScrollContainer = tab.get_node("%TableScroll")
	scroll.scroll_vertical = roundi(tab._rows.get_child(80).position.y)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var args := OS.get_cmdline_user_args()
	assert(get_viewport().get_texture().get_image().save_png(args[0]) == OK)
	scroll.scroll_horizontal = roundi(scroll.get_h_scroll_bar().max_value - scroll.get_h_scroll_bar().page)
	for i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	assert(get_viewport().get_texture().get_image().save_png(args[0].get_basename() + "-scrolled.png") == OK)
	print("Youth summary editor preview saved")
	get_tree().quit()
