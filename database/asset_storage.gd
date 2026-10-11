class_name AssetStorage
extends RefCounted
## Copies editor assets into user://database storage.


const FLAGS_DIR := "user://database/flags"
const LOGOS_DIR := "user://database/logos"


static func ensure_flags_dir() -> bool:
	return _ensure_dir(FLAGS_DIR)


static func ensure_logos_dir() -> bool:
	return _ensure_dir(LOGOS_DIR)


static func store_country_flag(source_path: String, country_id: int) -> Dictionary:
	if source_path.is_empty() or country_id < 1:
		return {"success": false, "error": "Не выбран файл флага.", "path": ""}

	var source_abs := _resolve_abs_path(source_path)
	if not FileAccess.file_exists(source_abs):
		return {"success": false, "error": "Файл флага не найден.", "path": ""}

	if not ensure_flags_dir():
		return {"success": false, "error": "Не удалось создать папку для флагов.", "path": ""}

	var ext := _image_extension(source_path)
	if ext.is_empty():
		return {"success": false, "error": "Допустимы только PNG, JPG, WEBP или SVG.", "path": ""}

	var dest_res := "%s/country_%d.%s" % [FLAGS_DIR, country_id, ext]
	_clear_prefixed_files(FLAGS_DIR, "country_%d." % country_id)

	var err := DirAccess.copy_absolute(source_abs, ProjectSettings.globalize_path(dest_res))
	if err != OK:
		return {"success": false, "error": "Не удалось скопировать файл флага.", "path": ""}

	return {"success": true, "error": "", "path": dest_res}


static func delete_country_flag(country_id: int) -> void:
	_clear_prefixed_files(FLAGS_DIR, "country_%d." % country_id)


static func store_club_logo(source_path: String, club_id: int) -> Dictionary:
	if source_path.is_empty() or club_id < 1:
		return {"success": false, "error": "Не выбран файл логотипа.", "path": ""}

	var source_abs := _resolve_abs_path(source_path)
	if not FileAccess.file_exists(source_abs):
		return {"success": false, "error": "Файл логотипа не найден.", "path": ""}

	if not ensure_logos_dir():
		return {"success": false, "error": "Не удалось создать папку для логотипов.", "path": ""}

	var ext := _image_extension(source_path)
	if ext.is_empty():
		return {"success": false, "error": "Допустимы только PNG, JPG, WEBP или SVG.", "path": ""}

	var dest_res := "%s/club_%d.%s" % [LOGOS_DIR, club_id, ext]
	_clear_prefixed_files(LOGOS_DIR, "club_%d." % club_id)

	var err := DirAccess.copy_absolute(source_abs, ProjectSettings.globalize_path(dest_res))
	if err != OK:
		return {"success": false, "error": "Не удалось скопировать файл логотипа.", "path": ""}

	return {"success": true, "error": "", "path": dest_res}


static func delete_club_logo(club_id: int) -> void:
	_clear_prefixed_files(LOGOS_DIR, "club_%d." % club_id)


static func store_unit_logo(source_path: String, unit_id: int) -> Dictionary:
	if source_path.is_empty() or unit_id < 1:
		return {"success": false, "error": "Не выбран файл логотипа.", "path": ""}

	var source_abs := _resolve_abs_path(source_path)
	if not FileAccess.file_exists(source_abs):
		return {"success": false, "error": "Файл логотипа не найден.", "path": ""}

	if not ensure_logos_dir():
		return {"success": false, "error": "Не удалось создать папку для логотипов.", "path": ""}

	var ext := _image_extension(source_path)
	if ext.is_empty():
		return {"success": false, "error": "Допустимы только PNG, JPG, WEBP или SVG.", "path": ""}

	var dest_res := "%s/unit_%d.%s" % [LOGOS_DIR, unit_id, ext]
	_clear_prefixed_files(LOGOS_DIR, "unit_%d." % unit_id)

	var err := DirAccess.copy_absolute(source_abs, ProjectSettings.globalize_path(dest_res))
	if err != OK:
		return {"success": false, "error": "Не удалось скопировать файл логотипа.", "path": ""}

	return {"success": true, "error": "", "path": dest_res}


static func delete_unit_logo(unit_id: int) -> void:
	_clear_prefixed_files(LOGOS_DIR, "unit_%d." % unit_id)


static func _resolve_abs_path(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _image_extension(path: String) -> String:
	var ext := path.get_extension().to_lower()
	if ext.is_empty():
		ext = "png"
	if not ext in ["png", "jpg", "jpeg", "webp", "svg"]:
		return ""
	return ext


static func _ensure_dir(dir_path: String) -> bool:
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	return err == OK or DirAccess.dir_exists_absolute(abs_dir)


static func _clear_prefixed_files(dir_path: String, prefix: String) -> void:
	var abs_dir := ProjectSettings.globalize_path(dir_path)
	if not DirAccess.dir_exists_absolute(abs_dir):
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(prefix):
			dir.remove(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
