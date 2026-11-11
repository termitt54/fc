extends Node
const Fixtures := preload("res://tests/game/squad_fixtures.gd")
var passed := 0
var failed := 0
func _ready() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if ok: passed += 1
	else:
		failed += 1
		print("FAIL: ", message)
func skill_count(player: Dictionary) -> int:
	var n := 0
	for group in player.attributes.values(): n += group.size()
	return n
func run() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 43855
	for i in 20:
		for p in Fixtures.squad(i+1, 30+i*3, rng, 8):
			check(skill_count(p) == (16 if p.position == "GK" else 11), "Exact compact skill count")
			check(not p.has("personality") and p.characters.size() == 1, "One character, no numeric personality")
			check(p.current_ability <= p.potential_ability, "CA remains within PA")
			var attrs: Dictionary = p.attributes.duplicate(true)
			var ratings := MatchRatings.of(p).duplicate(true)
			p.characters = [PlayerTypes.CHAR_PROFESSIONAL]
			MatchRatings.invalidate(p)
			var professional := MatchRatings.of(p)
			for k in MatchRatings.MIX:
				check(professional[k] == ratings[k], "Character does not alter football skills")
			check(p.attributes == attrs, "Character leaves attributes intact")
	# Old saves preserve IDs, PA, stats and one deterministic dominant trait.
	for position in PlayerTypes.POSITIONS:
		var old := {"id": 700, "position":position,"current_ability":73,"potential_ability":87,"overall":73,
			"attributes":{"technical":{"finishing":14,"passing":16,"first_touch":13,"technique":15,"dribbling":12,"tackling":15,"marking":13,"crossing":12},
			"mental":{"composure":19},"physical":{"pace":14,"acceleration":16,"agility":12,"balance":14,"stamina":15,"strength":13,"recovery":17},
			"set_pieces":{"corners":12,"free_kicks":16,"penalties":13,"long_shots":19},
			"goalkeeping":{"reflexes":16,"handling":14,"positioning":15,"one_on_ones":13,"rushing_out":17,"aerial_reach":14,"communication":19,"throwing":20}},
			"personality":{"risk":20},"characters":["LOYAL","PROFESSIONAL"],"career":[{"season":1,"goals":4}]}
		var state := rng.state
		check(PlayerTypes.backfill_attributes(old, rng), "Legacy model is migrated")
		check(rng.state == state, "Migration does not advance RNG")
		check(abs(old.current_ability - 73) <= 1, "Migration preserves CA within integer precision")
		check(old.id == 700 and old.potential_ability == 87 and old.career[0].goals == 4, "Identity, PA and career survive")
		check(old.characters == ["LOYAL"] and not old.has("personality"), "First recorded character retained")
		check(skill_count(old) == (16 if position == "GK" else 11), "Legacy fields removed")
		check(not old.attributes.has("mental"), "Mental group removed")
		var snapshot := old.duplicate(true)
		check(not PlayerTypes.backfill_attributes(old, rng) and old == snapshot, "Migration is idempotent")
	# The fast section-storage path is used by real SQLite saves, not only legacy JSON.
	var stored := {"id":70001,"position":"CM","current_ability":70,"potential_ability":80,
		"characters":["LOYAL","PROFESSIONAL"],"personality":{"risk":20},
		"attributes":{"technical":{"passing":14,"technique":14,"tackling":14,"marking":14},"physical":{"stamina":14}}}
	var payload := {"version":GameSession.SAVE_VERSION,"_native":true,"units":[],"season_number":1,
		"players_by_club":{70:[stored]},"free_agents":[],"transfer_log":[],"rng_seed":234,"rng_state":12345}
	check(GameSession.apply_save_payload(payload).success, "Native save payload loads")
	var migrated: Dictionary = GameSession.players_by_club[70][0]
	check(skill_count(migrated)==11 and migrated.characters==["LOYAL"] and not migrated.has("personality"), "Native storage also migrates old player data")
	check(GameSession._rng.state==12345, "Native storage migration preserves saved RNG")
	GameSession.clear()
	# v2 players: set pieces joined the outfield CA, so only they are raised and CA holds.
	for position in PlayerTypes.POSITIONS:
		var v2 := {"id":701,"position":position,"current_ability":86,"potential_ability":90,"player_model_version":2,
			"attributes":{"technical":{"finishing":19,"passing":17,"technique":18,"dribbling":15,"defending":18},
			"physical":{"pace":17,"stamina":16,"strength":17,"recovery":8},"set_pieces":{"delivery":7,"penalties":8},
			"goalkeeping":{"reflexes":18,"handling":17,"positioning":17,"exits":16,"aerial_reach":15}}}
		if position != "GK":
			v2.attributes.erase("goalkeeping")
		var before: Dictionary = v2.attributes.duplicate(true)
		var state := rng.state
		check(PlayerTypes.backfill_attributes(v2, rng) and rng.state == state, "v2 player is upgraded without RNG")
		check(PlayerTypes.calc_current_ability(v2.attributes, position) == (86 if position != "GK" else PlayerTypes.calc_current_ability(before, position)), "v2 upgrade keeps CA: " + position)
		for group in before:
			if group != "set_pieces":
				check(v2.attributes[group] == before[group], "v2 upgrade leaves non set-piece skills alone")
		check(position == "GK" or v2.attributes.set_pieces.delivery > 7 or v2.attributes.set_pieces.penalties > 8, "v2 outfield set pieces rise")
		var upgraded := v2.duplicate(true)
		check(not PlayerTypes.backfill_attributes(v2, rng) and v2 == upgraded, "v2 upgrade is idempotent")
	# Independent skill effects with an invalidated rating cache.
	var player: Dictionary = Fixtures.squad(90,65,rng,0)[4]
	for spec in [["technical","passing","create"],["technical","finishing","finish"],["technical","dribbling","dribble"],["technical","defending","defend"],["physical","pace","pace"],["physical","strength","aerial"],["physical","stamina","endurance"],["set_pieces","delivery","set_piece"],["set_pieces","penalties","penalty"]]:
		player.attributes[spec[0]][spec[1]] = 1
		MatchRatings.invalidate(player)
		var low: float = MatchRatings.of(player)[spec[2]]
		player.attributes[spec[0]][spec[1]] = 20
		MatchRatings.invalidate(player)
		check(MatchRatings.of(player)[spec[2]] > low, "Skill changes its intended match rating: " + spec[1])
	print("Compact player: ",passed," passed, ",failed," failed")
	get_tree().quit(int(failed > 0))
