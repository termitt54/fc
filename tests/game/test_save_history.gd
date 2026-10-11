extends Node
## Scratch databases only. Branch isolation, rollback, retries and legacy import.

const STORE := preload("res://game/save_store.gd")
const ARCHIVE := preload("res://game/career_archive.gd")
const PATH := "user://tests/save_history/games.db"
const A := "zz_history_a"
const B := "zz_history_b"
const C := "zz_history_c"
const D := "zz_history_d"
const E := "zz_history_e"
const LEGACY := "zz_history_legacy"
var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	STORE.database_path_override = PATH
	_wipe()
	_test_branches()
	_test_write_failures()
	_test_actual_interseason()
	_test_rejected_load()
	_test_legacy_import()
	GameSession.clear()
	STORE.database_path_override = ""
	_wipe()
	for suffix in ["", "-wal", "-shm"]:
		_remove(ARCHIVE.path_for(LEGACY) + suffix)
	print("=== History: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _fixture(season: int = 20) -> Dictionary:
	return {"version": GameSession.SAVE_VERSION, "season_number": season, "season_day": 1,
		"season_finished": true, "units": [], "players_by_club": {},
		"youth_players_by_club": {}, "reserve_players_by_club": {}, "free_agents": [],
		"coaches_by_club": {}, "club_budgets": {}, "transfer_log": [], "next_player_id": 1000}


func _player(id: int, goals: int = 5) -> Dictionary:
	var player := {"id": id, "name": "History Player %d" % id, "position": "ST", "club_id": 0,
		"nationality_country_id": 0, "age": 100, "retirement_age": 35,
		"current_ability": 30, "potential_ability": 50,
		"attributes": {"technical": {"finishing": 12}, "mental": {}, "physical": {}, "set_pieces": {}},
		"characters": ["LOYAL", "TEAM_PLAYER"], "career_stats": [],
		"development_factor": 0.9, "contract_years": 0, "contract_status": "free_agent"}
	player["_match_ratings"] = {"stamp": 999}
	PlayerStats.ensure_state(player, 20)
	player["season_stats"]["matches"] = 4
	player["season_stats"]["goals"] = goals
	return player


func _fresh() -> void:
	GameSession.clear()
	_ok(GameSession.apply_save_payload(_fixture()), "fresh session")


func _test_branches() -> void:
	_fresh()
	_ok(GameSession.save_game(A), "save before retirement")
	_ok(GameSession._archive_retired([_player(1)], 20), "append unsaved retirement")
	_check(_count(A) == 0, "unsaved future invisible from old save")
	var live: RefCounted = ARCHIVE.new()
	_check(live.open_head(GameSession.history_head), "open live history")
	_check(live.count() == 1, "live branch sees retirement")
	live.close()
	GameSession.season_number = 21
	_ok(GameSession.save_game(B), "save as carries history")
	_check(_identity(B, 1).get("goals", 0) == 5, "new slot keeps career totals")
	_check(_identity(B, 1).get("snapshot", {}).get("attributes", {}).get("technical", {}).get("finishing", 0) == 12, "full player snapshot retained")
	_check(not _identity(B, 1).get("snapshot", {}).has("_match_ratings"), "transient rating cache excluded from archive")
	_ok(GameSession._archive_retired([_player(2, 7)], 21), "append later retirement")
	GameSession.season_number = 22
	_ok(GameSession.save_game(C), "save future")
	_ok(GameSession.load_game(B), "load old point")
	_check(_count(B) == 1, "old point excludes future player")
	_ok(GameSession._archive_retired([_player(2, 99)], 21), "replay same ID on separate branch")
	_ok(GameSession.save_game(D), "save alternate branch")
	_check(_identity(C, 2).get("goals", 0) == 7, "future branch unchanged by replay")
	_check(_identity(D, 2).get("goals", 0) == 99, "alternate branch has its own stats")
	_ok(GameSession.load_game(C), "load future branch")
	_ok(GameSession.save_game(E), "copy save shares history")
	_ok(GameSession.delete_save(C), "delete source slot")
	_check(_count(E) == 2, "deleting source preserves other slot history")
	_fresh()
	_ok(GameSession.save_game(B), "new game overwrites existing slot")
	_check(_count(B) == 0, "new game does not inherit prior archive")
	_check(_count(D) == 2, "other world branch unaffected")
	var invalid: RefCounted = ARCHIVE.new()
	_check(not invalid.open("../history"), "reject path-like archive slot")
	invalid.close()


func _test_write_failures() -> void:
	_fresh()
	_ok(GameSession.save_game(A), "save baseline for write failures")
	var nodes_before: int = _nodes()
	_sql("CREATE TRIGGER history_insert_fault BEFORE INSERT ON save_history_players WHEN NEW.player_id = 11 BEGIN SELECT RAISE(ABORT, 'forced history failure'); END;")
	var first: Dictionary = _player(10)
	var failed: Dictionary = GameSession._archive_retired([first, _player(11)], 20)
	_check(not failed["success"], "report batch failure")
	_check(str(failed.get("error", "")).contains("forced history failure"), "injected insert failure returned")
	_check(GameSession.history_head == 0 and _nodes() == nodes_before, "batch and new history node rolled back together")
	_check(GameSession._pending_history.size() == 2, "keep entire failed batch for retry")
	first["name"] = "Changed after failure"
	_check(not GameSession.save_game(A)["success"], "cannot save session with missing archive")
	_check(_count(A) == 0, "failed save preserves previous snapshot")
	_sql("DROP TRIGGER history_insert_fault;")
	_ok(GameSession.save_game(B), "retry saves pending history")
	_check(GameSession._pending_history.is_empty() and _count(B) == 2, "retry archives all pending players once")
	_check(_identity(B, 10).get("name", "") == "History Player 10", "pending snapshot immune to later mutation")
	var head_before: int = GameSession.history_head
	nodes_before = _nodes()
	_sql("CREATE TABLE deferred_fault (parent INTEGER REFERENCES save_history_nodes(id) DEFERRABLE INITIALLY DEFERRED);")
	_sql("CREATE TRIGGER history_commit_fault AFTER INSERT ON save_history_players WHEN NEW.player_id = 12 BEGIN INSERT INTO deferred_fault(parent) VALUES (-999); END;")
	var commit_failed: Dictionary = GameSession._archive_retired([_player(12)], 20)
	_check(not commit_failed["success"] and str(commit_failed.get("error", "")).contains("FOREIGN KEY"), "detect injected COMMIT failure")
	_check(GameSession.history_head == head_before and _nodes() == nodes_before, "failed COMMIT rolls back history")
	_sql("DROP TRIGGER history_commit_fault;")
	_sql("DROP TABLE deferred_fault;")
	_ok(GameSession.save_game(B), "retry after failed COMMIT")
	_sql("CREATE TRIGGER save_insert_fault BEFORE INSERT ON save_sections WHEN NEW.slot = 'zz_history_a' BEGIN SELECT RAISE(ABORT, 'forced save failure'); END;")
	_check(not GameSession.save_game(A)["success"], "save transaction failure returned")
	_check(GameSession.save_slot == B and _count(A) == 0, "failed save-as preserves source and target")
	_sql("DROP TRIGGER save_insert_fault;")
	_ok(GameSession.load_game(A), "reload old save after failed write")
	_check(GameSession.history_head == 0 and GameSession._pending_history.is_empty(), "old load resets live branch state")
	_check(_count(B) == 3, "saved history remains intact")


func _test_actual_interseason() -> void:
	_fresh()
	GameSession.free_agents.append(_player(50))
	_ok(GameSession.save_game(A), "save active old player")
	_ok(GameSession.start_new_season(), "real interseason retires player")
	_check(GameSession.get_player(50).is_empty(), "retired player leaves active pool")
	_check(_count(A) == 0, "real interseason does not mutate saved past")
	_ok(GameSession.save_game(B), "save after real interseason")
	_check(_identity(B, 50).get("retired_season", 0) == 20, "retirement season belongs to closed season")
	_ok(GameSession.load_game(A), "restore before real retirement")
	_check(not GameSession.get_player(50).is_empty(), "old save restores active player")
	_ok(GameSession.start_new_season(), "replay real interseason")
	_ok(GameSession.save_game(D), "save replay")
	_check(_count(D) == 1 and _count(B) == 1, "replay does not duplicate retired player")


func _test_rejected_load() -> void:
	var original_head: int = GameSession.history_head
	var future: Dictionary = _fixture()
	future["version"] = GameSession.SAVE_VERSION + 1
	_check(not GameSession.apply_save_payload(future)["success"], "reject future save version")
	_check(GameSession.history_head == original_head and GameSession.is_active, "rejected payload leaves current history intact")
	_sql("UPDATE save_slots SET history_head = 999999999 WHERE slot = 'zz_history_a';")
	_check(not GameSession.load_game(A)["success"], "reject missing archive head")
	_check(GameSession.history_head == original_head, "failed load does not replace session")


func _test_legacy_import() -> void:
	_fresh()
	GameSession.free_agents.append(_player(99))
	_ok(GameSession.save_game(LEGACY), "prepare old-format slot")
	_sql("UPDATE save_slots SET version = 10 WHERE slot = 'zz_history_legacy';")
	var old_db: Variant = ClassDB.instantiate("SQLite")
	old_db.path = ARCHIVE.path_for(LEGACY)
	old_db.verbosity_level = 0
	_check(old_db.open_db(), "create scratch legacy archive")
	_check(old_db.query("CREATE TABLE retired_players(player_id INTEGER PRIMARY KEY, name TEXT, position TEXT, goals INTEGER, assists INTEGER, matches INTEGER, retired_season INTEGER);"), "legacy summary schema")
	_check(old_db.query("CREATE TABLE retired_seasons(player_id INTEGER, season INTEGER, club_id INTEGER, goals INTEGER);"), "legacy season schema")
	for row in [[70, 19], [71, 20], [99, 18]]:
		old_db.query_with_bindings("INSERT INTO retired_players VALUES (?, 'Legacy', 'ST', 5, 2, 10, ?);", row)
		old_db.query_with_bindings("INSERT INTO retired_seasons VALUES (?, 18, 3, 5);", [row[0]])
	old_db.close_db()
	_ok(GameSession.load_game(LEGACY), "load old save with archive")
	_ok(GameSession.save_game(E), "migrate legacy history into another slot")
	_check(_count(E) == 1, "exclude future retirements and active-ID collisions")
	_check(not _identity(E, 70).is_empty(), "valid old history retained")
	var view: RefCounted = ARCHIVE.new()
	view.open(E)
	_check(view.seasons_of(70).size() == 1, "old season rows retained")
	view.close()
	_check(FileAccess.file_exists(ARCHIVE.path_for(LEGACY)), "legacy file preserved")
	_ok(GameSession.load_game(E), "load converted slot without reimport")
	_ok(GameSession.save_game(E), "resave converted slot")
	_check(_count(E) == 1, "legacy import not duplicated")


func _count(slot: String) -> int:
	var view: RefCounted = ARCHIVE.new()
	if not view.open(slot):
		_check(false, "open archive: " + view.get_last_error())
		return -1
	var count: int = view.count()
	view.close()
	return count


func _identity(slot: String, id: int) -> Dictionary:
	var view: RefCounted = ARCHIVE.new()
	if not view.open(slot):
		_check(false, "open archive: " + view.get_last_error())
		return {}
	var player: Dictionary = view.get_player(id)
	view.close()
	return player


func _nodes() -> int:
	var db: Variant = ClassDB.instantiate("SQLite")
	db.path = PATH
	db.verbosity_level = 0
	db.open_db()
	db.query("SELECT COUNT(*) AS c FROM save_history_nodes;")
	var count: int = int(db.query_result[0]["c"])
	db.close_db()
	return count


func _sql(sql: String) -> void:
	var db: Variant = ClassDB.instantiate("SQLite")
	db.path = PATH
	db.verbosity_level = 0
	_check(db.open_db(), "open fault-injection connection")
	_check(db.query(sql), "test SQL: " + sql)
	db.close_db()


func _ok(result: Dictionary, message: String) -> void:
	_check(bool(result.get("success", false)), message + " " + str(result.get("error", "")))


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS ", message)
	else:
		_failed += 1
		print("FAIL ", message)


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _wipe() -> void:
	for suffix in ["", "-wal", "-shm"]:
		_remove(PATH + suffix)
