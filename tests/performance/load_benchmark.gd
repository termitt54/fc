extends Node
## Run through tools/run_load_benchmark.ps1: never inside the working project.
## Actual session methods; synthetic world; no UI/FPS claims from headless data.

const LEAGUE := preload("res://game/fixture_generator.gd")
const GENERATOR := preload("res://game/player_generator.gd")
const COACH := preload("res://game/coach_generator.gd")
const ARCHIVE := preload("res://game/career_archive.gd")
const CONDITION := preload("res://game/player_condition.gd")
const WORK := preload("res://game/simulation_work.gd")

var _options: Dictionary = {"clubs": 100, "seasons": 2, "league-size": 10,
    "players-per-club": 50, "seed": 4242, "max-seconds": 900, "market-days": 5}
var _report: Dictionary = {}
var _samples: Array = []
var _failures: Array = []
var _started: int = 0
var _report_path: String = ""
var _slot: String = ""
var _id_state: Dictionary = {"next_id": 1}
var _coach_ids: Dictionary = {"next_id": 1}
var _rng := RandomNumberGenerator.new()
var _empty_start: bool = false
var _match_only: bool = false
var _market_only: bool = false
var _sliced := false
var _heartbeat_frames := 0
var _heartbeat_last := 0
var _heartbeat_gap_usec := 0

func _process(_delta: float) -> void:
    if GameSession.is_processing:
        var now := Time.get_ticks_usec()
        if _heartbeat_last > 0:
            _heartbeat_gap_usec = maxi(_heartbeat_gap_usec, now - _heartbeat_last)
        _heartbeat_last = now
        _heartbeat_frames += 1

func _reset_heartbeat() -> void:
    _heartbeat_frames = 0
    _heartbeat_last = 0
    _heartbeat_gap_usec = 0

func _sliced_market() -> void:
    _reset_heartbeat()
    GameSession.is_processing = true
    var work: RefCounted = WORK.new(GameSession, 8)
    await work.checkpoint("Рынок", 0, 0, true)
    await GameSession._begin_calendar_day_async(work)
    GameSession.last_work_profile = work.finish()
    GameSession.is_processing = false
var _names: Dictionary = {}
var _archive_probe_id: int = 0
var _archive_probe_digest: String = ""
var _continue_squad_errors: bool = false
var _squad_violations: Array = []


func _ready() -> void:
    # Autoloads already ran, so isolation is enforced by the launcher's project.
    if str(ProjectSettings.get_setting("application/config/name", "")) != "FC Load Benchmark" \
        or not OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"):
        push_error("Use tools/run_load_benchmark.ps1. Refusing userdata: " + OS.get_user_data_dir() + " project=" + str(ProjectSettings.get_setting("application/config/name", "")))
        get_tree().quit(2)
        return
    call_deferred("_run")


func _run() -> void:
    _started = Time.get_ticks_usec()
    for argument in OS.get_cmdline_user_args():
        if argument == "--empty-start":
            _empty_start = true
        elif argument == "--match-only":
            _match_only = true
        elif argument == "--market-only":
            _market_only = true
        elif argument == "--sliced":
            _sliced = true
        elif argument == "--continue-squad-errors":
            _continue_squad_errors = true
        elif argument.begins_with("--report="):
            _report_path = argument.trim_prefix("--report=")
        elif argument.begins_with("--") and argument.contains("="):
            var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
            if not _options.has(parts[0]) or not parts[1].is_valid_int():
                _failures.append("Unknown/invalid argument: " + argument)
            else:
                _options[parts[0]] = int(parts[1])
    if int(_options["clubs"]) < 2 or int(_options["seasons"]) < 1 \
        or int(_options["league-size"]) < 2 or int(_options["players-per-club"]) < 25:
        _failures.append("Invalid scenario dimensions")
    _slot = "bench_%d_%d_%d" % [int(_options["clubs"]), int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]
    if _match_only and (_empty_start or int(_options["seasons"]) != 1):
        _failures.append("MatchOnly requires populated squads and one season")
    if _market_only and (_match_only or int(_options["seasons"]) != 1 or int(_options["market-days"]) < 1 or int(_options["market-days"]) > 5):
        _failures.append("MarketOnly requires one season and 1..5 market days")
    _report = {"options": _options, "empty_start": _empty_start, "match_only": _match_only, "market_only": _market_only, "sliced": _sliced, "engine": Engine.get_version_info(),
        "cpu": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
        "userdata": OS.get_user_data_dir(), "slot": _slot, "samples": _samples, "failures": _failures,
        "continue_squad_errors": _continue_squad_errors, "squad_violations": _squad_violations,
        "status": "running", "completed_seasons": 0,
        "scope": "Headless editor build; actual game session, synthetic small leagues; engine-tracked memory, not total process RSS"}
    if not _failures.is_empty():
        _finish(false)
        return
    _rng.seed = int(_options["seed"])
    print("BENCH BEGIN ", JSON.stringify(_options), " isolated=", OS.get_user_data_dir())
    var start: int = Time.get_ticks_usec()
    var payload: Dictionary = _build_world()
    _record("build_world", start)
    if not _check_result(GameSession.apply_save_payload(payload), "apply fixture"):
        _finish(false)
        return
    payload.clear()
    GameSession.save_slot = _slot
    GameSession._rng.seed = int(_options["seed"]) + 1
    _report["initial_players"] = _player_count()
    _report["initial_matches"] = _match_count()
    if not _validate("initial"):
        _finish(false)
        return
    # apply_save_payload does not run the opening day's market.
    if not _match_only:
        start = Time.get_ticks_usec()
        if _sliced:
            await _sliced_market()
        else:
            GameSession._begin_calendar_day()
        _record("market_open", start, {"profile": GameSession.last_market_profile.duplicate()})
    if _market_only:
        for market_step in range(1, int(_options["market-days"])):
            if _expired():
                _finish(false)
                return
            GameSession.season_day += 1
            start = Time.get_ticks_usec()
            if _sliced:
                await _sliced_market()
            else:
                GameSession._begin_calendar_day()
            _record("market_day", start, {"profile": GameSession.last_market_profile.duplicate()})
            await get_tree().process_frame
        if _expired():
            _finish(false)
            return
        _report["market_state_digest"] = _fingerprint()
        _report["transfer_log_digest"] = _digest(GameSession.transfer_log)
        _report["rng_state"] = str(GameSession._rng.state)
        GameSession._strip_rating_caches()
        _report["market_full_digest"] = _digest([GameSession.players_by_club,
            GameSession.youth_players_by_club, GameSession.reserve_players_by_club,
            GameSession.free_agents, GameSession.coaches_by_club, GameSession.club_budgets,
            GameSession.units, GameSession.transfer_log, GameSession._rng.state])
        if int(_options["market-days"]) == 5:
            GameSession.season_day = 1
        _validate("market_end")
        _finish(_failures.is_empty())
        return
    if _expired():
        _finish(false)
        return
    for cycle in int(_options["seasons"]):
        var step_count: int = 0
        while not GameSession.season_finished:
            if _expired():
                _finish(false)
                return
            var old_day: int = GameSession.season_day
            start = Time.get_ticks_usec()
            var advanced: Dictionary
            if _sliced:
                _reset_heartbeat()
                advanced = await GameSession.advance_day_async()
            else:
                advanced = GameSession.advance_day()
            if not _check_result(advanced, "advance day"):
                _finish(false)
                return
            var label: String = "match_day" if old_day > 0 else ("market_close_and_preview" if old_day == -1 else "market_day")
            _record(label, start, {"profile": GameSession.last_day_profile.duplicate(), "market_profile": GameSession.last_market_profile.duplicate()})
            step_count += 1
            if step_count > 1000:
                _failures.append("Season did not finish within 1000 steps")
                _finish(false)
                return
            await get_tree().process_frame
        if not _validate("season_end"):
            _finish(false)
            return
        _report["completed_seasons"] = cycle + 1
        if cycle == 0 or (cycle + 1) in [10, 50, 100, 200] or cycle + 1 == int(_options["seasons"]):
            start = Time.get_ticks_usec()
            var rows: Array = GameSession.get_all_player_rows()
            _record("directory_build", start, {"rows": rows.size()})
            rows.clear()
            start = Time.get_ticks_usec()
            for i in 100:
                GameSession.get_player(maxi(1, int(GameSession._next_player_id) - 1 - i))
            _record("player_lookup_100", start)
            if not _roundtrip():
                _finish(false)
                return
            var archive: RefCounted = ARCHIVE.new()
            if archive.open(_slot):
                start = Time.get_ticks_usec()
                var retired_count: int = archive.count()
                var leaders: Array = archive.top_scorers(50)
                _record("archive_top_50", start, {"retired": retired_count, "rows": leaders.size()})
                if not leaders.is_empty():
                    if _archive_probe_id == 0:
                        _archive_probe_id = int(leaders[0]["player_id"])
                    var pid: int = _archive_probe_id
                    start = Time.get_ticks_usec()
                    var identity: Dictionary = archive.get_player(pid)
                    var history: Array = archive.seasons_of(pid)
                    _record("archive_player", start, {"player_id": pid, "history_rows": history.size()})
                    if identity.is_empty():
                        _failures.append("Archived player could not be read")
                    var digest: String = _digest([identity, history])
                    if _archive_probe_digest.is_empty():
                        _archive_probe_digest = digest
                    elif digest != _archive_probe_digest:
                        _failures.append("Previously retired player's archive changed")
                    _report["archive_probe_player_id"] = pid
                    _report["archive_probe_checked_at_season"] = cycle + 1
                archive.close()
            else:
                _failures.append("Archive open: " + archive.get_last_error())
            print("BENCH CHECKPOINT season=", cycle + 1, " players=", _player_count())
            _write_report()
        if _match_only:
            _finish(_failures.is_empty())
            return
        # Measure real interseason, including archive/intake and the first market wave.
        start = Time.get_ticks_usec()
        if not _check_result(GameSession.start_new_season(), "new season"):
            _finish(false)
            return
        _record("new_season_including_market_open", start, {"profile": GameSession.last_new_season_profile.duplicate(), "market_profile": GameSession.last_market_profile.duplicate()})
        if not _validate("new_season"):
            _finish(false)
            return
        if _expired():
            _finish(false)
            return
        await get_tree().process_frame
    _finish(_failures.is_empty())


func _build_world() -> Dictionary:
    var first: Dictionary = {}
    var youth: Dictionary = {}
    var reserve: Dictionary = {}
    var agents: Array = []
    var clubs: Dictionary = {}
    var budgets: Dictionary = {}
    for id in range(1, int(_options["clubs"]) + 1):
        var club: Dictionary = {"id": id, "name": "Benchmark Club %04d" % id,
            "country_id": 0, "reputation": 500, "finance_level": 10,
            "training_level": 10, "youth_academy": 10, "youth_talent": 50}
        clubs[id] = club
        budgets[id] = 100000000
        var used: Dictionary = {}
        var squad: Array = []
        for position in GENERATOR.build_position_list(_rng):
            squad.append(_player(id, club, position, false, false, used))
        first[id] = [] if _empty_start else squad
        if _empty_start:
            for player in squad:
                player["club_id"] = 0
                player["contract_status"] = "free_agent"
                agents.append(player)
        var young: Array = []
        var reserves: Array = []
        var extras: int = int(_options["players-per-club"]) - 25
        for j in extras:
            var position: String = PlayerTypes.FIELD_POSITIONS[j % PlayerTypes.FIELD_POSITIONS.size()]
            var is_youth: bool = j < mini(6, extras)
            var is_reserve: bool = j >= 6 and j < 18
            var player: Dictionary = _player(id, club, position, is_youth, is_reserve, used)
            if is_youth:
                young.append(player)
            elif is_reserve:
                reserves.append(player)
            else:
                player["club_id"] = 0
                player["contract_status"] = "free_agent"
                agents.append(player)
        youth[id] = young
        reserve[id] = reserves
    var units: Array = []
    var club_ids: Array = clubs.keys()
    var next_match: int = 1
    for offset in range(0, club_ids.size(), int(_options["league-size"])):
        var ids: Array = club_ids.slice(offset, mini(offset + int(_options["league-size"]), club_ids.size()))
        var generated: Dictionary = LEAGUE.build_regular_season(ids, 1, ids.size(), 1, 0, _rng)
        for match_row in generated["matches"]:
            match_row["id"] = next_match
            next_match += 1
        var league_clubs: Dictionary = {}
        var standings: Array = []
        var prizes: Dictionary = {}
        for id in ids:
            league_clubs[id] = clubs[id]
            standings.append({"club_id": id, "division": 0, "played": 0, "won": 0,
                "drawn": 0, "lost": 0, "goals_for": 0, "goals_against": 0, "goal_diff": 0, "points": 0})
            prizes["regular_%d" % (prizes.size() + 1)] = 5000000
        var rules: Dictionary = {"divisions_count": 1, "teams_per_division": ids.size(),
            "matches_vs_own": 1, "matches_vs_other": 0, "points_win": 3,
            "points_draw": 1, "points_loss": 0, "ranking_order": RankingCriteria.DEFAULT_ORDER,
            "regular_season_enabled": true, "prize_rules": prizes, "division_strength": 800}
        units.append({"id": units.size() + 1, "competition_type": CompetitionTypes.TYPE_DIVISIONS,
            "name": "Benchmark League", "label": "Benchmark League", "rules": rules,
            "foreign_players_limit": -1, "clubs_by_id": league_clubs,
            "divisions": generated["divisions"], "matches": generated["matches"],
            "standings": standings, "playoff": {"enabled": false}, "winners": []})
    var coaches: Dictionary = COACH.generate_for_clubs(clubs, _rng, _names, _coach_ids, 1)
    return {"version": GameSession.SAVE_VERSION, "season_number": 1, "season_day": 1 if _match_only else -5,
        "selected_unit_id": 1, "units": units, "players_by_club": first,
        "youth_players_by_club": youth, "reserve_players_by_club": reserve,
        "free_agents": agents, "coaches_by_club": coaches, "club_budgets": budgets,
        "transfer_log": [], "next_player_id": _id_state["next_id"], "next_coach_id": _coach_ids["next_id"]}


func _player(id: int, club: Dictionary, position: String, young: bool, reserve: bool, used: Dictionary) -> Dictionary:
    var player: Dictionary = GENERATOR.create_player(id, club, _rng, _names, used, _id_state,
        {"position": position, "age": _rng.randi_range(15, 17) if young else (_rng.randi_range(18, 21) if reserve else _rng.randi_range(22, 32)),
        "current_ability": _rng.randi_range(25, 45) if young else _rng.randi_range(45, 65),
        "potential_ability": 80, "is_youth": young})
    player["is_reserve"] = reserve
    CONDITION.ensure_state(player)
    PlayerStats.ensure_state(player, 1)
    return player


func _record(label: String, start: int, extra: Dictionary = {}) -> void:
    var sample: Dictionary = {"operation": label, "ms": float(Time.get_ticks_usec() - start) / 1000.0,
        "season": GameSession.season_number, "day_after": GameSession.season_day,
        "memory_mib": float(OS.get_static_memory_usage()) / 1048576.0,
        "peak_memory_mib": float(OS.get_static_memory_peak_usage()) / 1048576.0}
    sample.merge(extra)
    if _sliced and label in ["market_open", "market_day", "market_close_and_preview", "match_day"]:
        sample["work"] = GameSession.last_work_profile.duplicate()
        sample["heartbeat_frames"] = _heartbeat_frames
        sample["max_frame_gap_ms"] = float(_heartbeat_gap_usec) / 1000.0
    _samples.append(sample)
    print("BENCH ", label, " season=", sample["season"], " ms=", snappedf(sample["ms"], 0.01), " memory_mib=", snappedf(sample["memory_mib"], 0.1))
    _write_report()


func _validate(stage: String) -> bool:
    var seen: Dictionary = {}
    var max_id: int = 0
    for map in [GameSession.players_by_club, GameSession.youth_players_by_club, GameSession.reserve_players_by_club]:
        for id in map:
            for player in map[id]:
                var pid: int = int(player.get("id", 0))
                if pid < 1 or seen.has(pid) or int(player.get("club_id", 0)) != int(id):
                    _failures.append(stage + ": duplicate ID or wrong club: " + str(pid))
                seen[pid] = true
                max_id = maxi(max_id, pid)
    for player in GameSession.free_agents:
        var pid: int = int(player.get("id", 0))
        if pid < 1 or seen.has(pid) or int(player.get("club_id", 0)) != 0:
            _failures.append(stage + ": invalid free agent: " + str(pid))
        seen[pid] = true
        max_id = maxi(max_id, pid)
    if int(GameSession._next_player_id) <= max_id:
        _failures.append(stage + ": next player ID collision")
    for unit in GameSession.units:
        # Regular-season IDs are local to a unit and restart each season.
        var seen_matches: Dictionary = {}
        for match_row in unit.get("matches", []):
            var mid: int = int(match_row.get("id", 0))
            if mid < 1 or seen_matches.has(mid):
                _failures.append(stage + ": duplicate/invalid match ID " + str(mid))
            seen_matches[mid] = true
    if GameSession.season_day > 0:
        for id in GameSession.players_by_club:
            var squad: Array = GameSession.players_by_club[id]
            if squad.size() != 25:
                _squad_issue(stage + ": squad size %d for club %s" % [squad.size(), id])
            var positions: Dictionary = {}
            for player in squad:
                var pos: String = str(player.get("position", ""))
                positions[pos] = int(positions.get(pos, 0)) + 1
            for pos in PlayerTypes.SQUAD_SLOT_MIN:
                var n: int = int(positions.get(pos, 0))
                if n < int(PlayerTypes.SQUAD_SLOT_MIN[pos]) or n > int(PlayerTypes.SQUAD_SLOT_MAX[pos]):
                    _squad_issue(stage + ": club %s position %s has %d, expected %d..%d" % [id, pos, n, PlayerTypes.SQUAD_SLOT_MIN[pos], PlayerTypes.SQUAD_SLOT_MAX[pos]])
    print("BENCH VALIDATE ", stage, " active=", seen.size(), " failures=", _failures.size(), " squad_violations=", _squad_violations.size())
    return _failures.is_empty()


func _squad_issue(message: String) -> void:
    _squad_violations.append({"season": GameSession.season_number, "issue": message})
    if not _continue_squad_errors:
        _failures.append(message)


func _fingerprint() -> String:
    # Scalar rows, sorted by ID; excludes transient rating caches.
    var players: Array = []
    for map in [GameSession.players_by_club, GameSession.youth_players_by_club, GameSession.reserve_players_by_club]:
        for id in map:
            players.append_array(map[id])
    players.append_array(GameSession.free_agents)
    players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
    var rows: Array = [GameSession.season_number, GameSession.season_day, GameSession._rng.state,
        GameSession._next_player_id, GameSession._next_match_id, GameSession.history_head]
    for player in players:
        rows.append([player["id"], player["club_id"], player["age"], player["current_ability"],
            player["potential_ability"], player["contract_years"], player["condition"], player["morale"],
            player.get("season_stats", {}), player.get("career_stats", [])])
    var ids: Array = GameSession.club_budgets.keys()
    ids.sort()
    for id in ids:
        rows.append([id, GameSession.club_budgets[id]])
    for unit in GameSession.units:
        rows.append(unit.get("standings", []))
        rows.append(unit.get("winners", []))
    return _digest(rows)


func _digest(value: Variant) -> String:
    var hash := HashingContext.new()
    hash.start(HashingContext.HASH_SHA256)
    hash.update(var_to_bytes(value))
    return hash.finish().hex_encode()


func _roundtrip() -> bool:
    var before: String = _fingerprint()
    var start: int = Time.get_ticks_usec()
    if not _check_result(GameSession.save_game(_slot), "save"):
        return false
    _record("save", start)
    GameSession.clear()
    start = Time.get_ticks_usec()
    if not _check_result(GameSession.load_game(_slot), "load"):
        return false
    _record("load", start)
    if before != _fingerprint():
        _failures.append("Save/load changed scalar state or RNG")
    return _validate("roundtrip")


func _check_result(result: Dictionary, label: String) -> bool:
    if bool(result.get("success", false)):
        return true
    _failures.append(label + ": " + str(result.get("error", "unknown error")))
    return false


func _player_count() -> int:
    var n: int = GameSession.free_agents.size()
    for map in [GameSession.players_by_club, GameSession.youth_players_by_club, GameSession.reserve_players_by_club]:
        for id in map:
            n += (map[id] as Array).size()
    return n


func _match_count() -> int:
    var n: int = 0
    for unit in GameSession.units:
        n += (unit.get("matches", []) as Array).size()
    return n


func _expired() -> bool:
    if Time.get_ticks_usec() - _started > int(_options["max-seconds"]) * 1000000:
        _failures.append("Time budget reached between operations; run incomplete")
        return true
    return false


func _write_report() -> void:
    if _report_path.is_empty():
        return
    _report["elapsed_seconds"] = float(Time.get_ticks_usec() - _started) / 1000000.0
    var file: FileAccess = FileAccess.open(_report_path, FileAccess.WRITE)
    if file == null:
        push_error("Could not write benchmark report: " + _report_path)
        return
    file.store_string(JSON.stringify(_report, "\t"))
    file.close()


func _finish(success: bool) -> void:
    _report["status"] = "passed" if success else "failed_or_incomplete"
    if success and not _squad_violations.is_empty():
        _report["status"] = "completed_with_squad_violations"
        success = false
    _report["final_players"] = _player_count()
    _report["peak_memory_mib"] = float(OS.get_static_memory_peak_usage()) / 1048576.0
    _write_report()
    print("BENCH END status=", _report["status"], " completed_seasons=", _report.get("completed_seasons", 0), " failures=", JSON.stringify(_failures))
    get_tree().quit(0 if success else 1)
