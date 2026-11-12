class_name CupFormatRepository
extends RefCounted

func get_config(unit_id: int) -> Dictionary:
	var rows: Array = DatabaseManager.query_rows("SELECT config_json FROM cup_formats WHERE unit_id = ?", [unit_id])
	if rows.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(str(rows[0]["config_json"]))
	if not parsed is Dictionary: return {}
	for stage in parsed.get("stages", []):
		if stage.has("team_count"): stage["team_count"] = int(stage["team_count"])
		for slot in stage.get("slots", []):
			slot["unit_id"] = int(slot.get("unit_id", 0))
			slot["place"] = int(slot.get("place", 0))
		for field in ["source_units", "club_ids"]:
			if stage.has(field):
				stage[field] = stage[field].map(func(id): return int(id))
		for field in ["legs", "groups", "qualify", "advance", "gap", "start_day", "place_count", "place_from", "place_to"]:
			if stage.has(field): stage[field] = int(stage[field])
	if parsed.has("version"): parsed["version"] = int(parsed["version"])
	return parsed

func save_config(unit_id: int, config: Dictionary) -> Dictionary:
	var found := CompetitionUnitRepository.new().get_by_id(unit_id)
	if not found["success"]:
		return found
	if str(found["data"].get("unit_kind", "")) != CompetitionTypes.UNIT_CUP:
		return DbResult.fail("Конструктор доступен только для кубка.")
	var checked := CupCompetition.validate(config) if not config.is_empty() else PackedStringArray()
	if not checked.is_empty():
		return DbResult.fail("\n".join(checked))
	if not config.is_empty():
		var source_units := CompetitionUnitRepository.new().get_by_competition(int(found["data"]["competition_id"]))
		if not source_units["success"]:
			return source_units
		var snapshots: Array = []
		for source in source_units["data"]:
			if str(source.get("unit_kind", "")) != "DIVISION": continue
			var members := CompetitionUnitRepository.new().get_club_ids(int(source["id"]))
			if not members["success"]: return members
			source["divisions"] = [{"club_ids": members["data"]}]
			snapshots.append(source)
		var cup: Dictionary = found["data"].duplicate(true)
		cup["cup_config"] = config
		checked = CupCompetition.validate_world(cup, snapshots)
		if not checked.is_empty(): return DbResult.fail("\n".join(checked))
	if not DatabaseManager.execute_with_bindings("INSERT INTO cup_formats(unit_id, config_json) VALUES (?, ?) ON CONFLICT(unit_id) DO UPDATE SET config_json = excluded.config_json", [unit_id, JSON.stringify(config)]):
		return DbResult.fail("Не удалось сохранить этапы кубка.")
	return DbResult.ok(config)
