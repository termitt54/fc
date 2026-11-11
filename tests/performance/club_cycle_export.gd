extends Node
const History = preload("res://game/history_store.gd")
func _ready() -> void: call_deferred("run")
func run() -> void:
	assert(OS.get_user_data_dir().ends_with("fc-load-benchmark"))
	var folder := OS.get_cmdline_user_args()[0]
	assert(folder.contains("/.benchmark-runtime/user-") and folder.ends_with("-snapshot"))
	SaveStore.database_path_override=folder.path_join("games.db")
	var store := SaveStore.new()
	var loaded := store.load_slot("autosave")
	assert(loaded.success)
	var head := int(loaded.data.history_head)
	var from_season := int(loaded.data.season_number)-30
	assert(store._open())
	var stats := FileAccess.open(folder.path_join("club-season-players.jsonl"),FileAccess.WRITE)
	assert(store._db.query_with_bindings(History.ANCESTORS+"SELECT rowid AS rid FROM save_history_tournaments WHERE history_id IN (SELECT id FROM ancestry) AND season>=? ORDER BY season,unit_id;",[head,head,from_season]))
	var editions: Array=store._db.query_result.duplicate(true)
	var seen := {}
	for edition in editions:
		assert(store._db.query_with_bindings("SELECT body FROM save_history_tournaments WHERE rowid=?;",[edition.rid]))
		var decoded := store._decode_tournament_body(store._db.query_result[0].body)
		assert(decoded.success)
		var unit: Dictionary=decoded.data
		if bool(unit.get("national",false)):continue
		var key := "%s:%s" % [unit.id,unit.season]
		assert(not seen.has(key));seen[key]=true
		stats.store_line(JSON.stringify({"unit_id":unit.id,"season":unit.season,"players":unit.get("season_player_stats",{})}))
	stats.close()
	var careers := FileAccess.open(folder.path_join("club-cycle-careers.jsonl"),FileAccess.WRITE)
	var cursor := 0
	var count := 0
	while true:
		assert(store._db.query_with_bindings(History.ANCESTORS+"SELECT rowid AS rid,body FROM save_history_players WHERE rowid>? AND history_id IN (SELECT id FROM ancestry) AND matches>0 AND retired_season>=? ORDER BY rowid LIMIT 256;",[head,head,cursor,from_season]))
		var batch: Array=store._db.query_result
		if batch.is_empty():break
		for row in batch:
			cursor=int(row.rid)
			var record: Dictionary=bytes_to_var(row.body)
			var player: Dictionary=record.get("player",{})
			var compact: Dictionary=record.identity.duplicate(true)
			for field in ["development_history","joined_season","wage","reputation"]:
				if player.has(field):compact[field]=player[field]
			compact["career_stats"]=record.get("seasons",[])
			careers.store_line(JSON.stringify(compact))
			count+=1
		if count%2048==0:print("CAREERS ",count)
	careers.close()
	store._close()
	print("CLUB CYCLE EXPORT editions=",seen.size()," played careers=",count," from=",from_season)
	get_tree().quit()
