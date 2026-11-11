extends Node
const HISTORY := preload("res://game/history_store.gd")

func _ready() -> void: call_deferred("run")

func compact_edition(unit: Dictionary) -> Dictionary:
	var result := {}
	for key in ["id","season","name","label","competition_name","national","rules","divisions","standings","clubs_by_id","group_draw","winners"]:
		if unit.has(key): result[key]=unit[key]
	result.matches=[]
	for row in unit.get("matches",[]):
		var match_row := {}
		for key in ["id","season_day","stage","series_id","game_index","is_third_place","home_id","away_id","home_goals","away_goals","played","winner_id","extra_time","shootout"]:
			if row.has(key): match_row[key]=row[key]
		result.matches.append(match_row)
	var bag: Dictionary=unit.get("season_player_stats",{})
	result.player_stats_count=bag.size()
	result.position_stats={}
	for row in bag.values():
		var pos := str(row.get("position","?"))
		if not result.position_stats.has(pos): result.position_stats[pos]={"goals":0,"assists":0,"minutes":0,"matches":0,"yellow":0,"red":0}
		for stat in result.position_stats[pos]: result.position_stats[pos][stat]+=int(row.get(stat,0))
	result.scorers=UnitSeasonStats.leaders_in(bag,"goals",20)
	result.assistants=UnitSeasonStats.leaders_in(bag,"assists",20)
	return result

func run() -> void:
	assert(OS.get_user_data_dir().replace("\\","/").ends_with("/fc-load-benchmark"))
	var args := OS.get_cmdline_user_args()
	assert(args.size()==2)
	var folder := args[0].replace("\\","/").simplify_path()
	assert(folder.contains("/.benchmark-runtime/user-") and folder.ends_with("-snapshot"))
	SaveStore.database_path_override=folder.path_join("games.db")
	var store := SaveStore.new()
	var started := Time.get_ticks_msec()
	var loaded := store.load_slot(args[1])
	assert(loaded.success)
	var payload: Dictionary=loaded.data
	var payload_file := FileAccess.open(folder.path_join("payload.json"),FileAccess.WRITE)
	payload_file.store_string(JSON.stringify(payload))
	payload_file.close()
	print("PAYLOAD EXPORTED season=",payload.season_number," load/export_ms=",Time.get_ticks_msec()-started)
	var head := int(payload.get("history_head",0))
	assert(store._open())
	var editions := FileAccess.open(folder.path_join("editions.jsonl"),FileAccess.WRITE)
	for unit in payload.get("units",[]):
		var live := compact_edition(unit)
		live.season=payload.season_number
		live.live=true
		editions.store_line(JSON.stringify(live))
	assert(store._db.query_with_bindings(HISTORY.ANCESTORS+"SELECT rowid AS rid,unit_id,season FROM save_history_tournaments WHERE history_id IN (SELECT id FROM ancestry) ORDER BY unit_id,season,history_id DESC;",[head,head]))
	var rows: Array=store._db.query_result.duplicate(true)
	var seen := {}
	var count := 0
	for row in rows:
		var key := str(row.unit_id)+":"+str(row.season)
		if seen.has(key): continue
		seen[key]=true
		assert(store._db.query_with_bindings("SELECT body FROM save_history_tournaments WHERE rowid=?;",[int(row.rid)]))
		var decoded := store._decode_tournament_body(store._db.query_result[0].body)
		assert(decoded.success)
		editions.store_line(JSON.stringify(compact_edition(decoded.data)))
		count+=1
		if count%100==0: print("EDITIONS ",count,"/",rows.size())
	editions.close()
	var archive := FileAccess.open(folder.path_join("retired.jsonl"),FileAccess.WRITE)
	var cursor := 0
	var retired_count := 0
	while true:
		assert(store._db.query_with_bindings(HISTORY.ANCESTORS+"SELECT rowid AS rid,body FROM save_history_players WHERE rowid>? AND history_id IN (SELECT id FROM ancestry) ORDER BY rowid LIMIT 256;",[head,head,cursor]))
		var batch: Array=store._db.query_result
		if batch.is_empty(): break
		for row in batch:
			cursor=int(row.rid)
			var record: Dictionary=bytes_to_var(row.body)
			var thin: Dictionary=record.get("identity",{}).duplicate()
			var player: Dictionary=record.get("player",{})
			for key in ["free_agent_seasons","national_stats","condition","reputation"]:
				if player.has(key): thin[key]=player[key]
			archive.store_line(JSON.stringify(thin))
			retired_count+=1
		if retired_count%4096==0: print("RETIRED ",retired_count)
	archive.close()
	store._close()
	print("EXPORT COMPLETE editions=",count," retired=",retired_count," elapsed_ms=",Time.get_ticks_msec()-started)
	get_tree().quit()
