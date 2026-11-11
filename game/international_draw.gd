class_name InternationalDraw
extends RefCounted
## Versioned rules leave room for future draw constraints without changing saves.
const REPUTATION := "REPUTATION_POTS"
const ELO := "ELO_POTS"
const RANDOM := "RANDOM"
const NationalRatingScript = preload("res://game/national_rating.gd")

static func rules(value: Variant) -> Dictionary:
	if value is String:
		value = JSON.parse_string(value)
	var result: Dictionary = value.duplicate(true) if value is Dictionary else {}
	result["version"] = 1
	if str(result.get("mode", REPUTATION)) not in [REPUTATION, ELO, RANDOM]:
		result["mode"] = REPUTATION
	if not result.has("mode"):
		result["mode"] = REPUTATION
	return result

static func options() -> Array:
	return [{"id": REPUTATION, "label": "Корзины по репутации сборных"}, {"id": ELO, "label": "Корзины по Elo сборных"}, {"id": RANDOM, "label": "Случайная жеребьёвка"}]

static func description(mode: String) -> String:
	match mode:
		ELO: return "Перед каждым розыгрышем.\nКорзины — по текущему Elo сборных."
		RANDOM: return "Перед каждым розыгрышем.\nСлучайно, без рейтинговых корзин."
		_: return "Перед каждым розыгрышем.\nКорзины — по текущей репутации сборных."

static func _draw_score(identity: Dictionary, mode: String) -> float:
	if mode == ELO:
		var fallback := NationalRatingScript.initial_elo(identity)
		var score := float(identity.get("elo", fallback))
		return maxf(0.0, score if is_finite(score) else fallback)
	return float(identity.get("reputation", 0))

static func qualifier_count(participants: int, groups: int, requested: int) -> int:
	var limit := mini(participants, maxi(4, requested if requested > 0 else groups * 2))
	var result := 1
	while result * 2 <= limit:
		result *= 2
	return result if participants > 0 else 0

static func normalize(source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["competition_type"] = CompetitionTypes.TYPE_GROUP_AND_PLAYOFF
	result["regular_season_enabled"] = false
	result["teams_promote"] = 0
	result["teams_relegate"] = 0
	result["matches_vs_other"] = 0
	result["matches_vs_own"] = maxi(1, int(result.get("matches_vs_own", 1)))
	result["playoff_third_place"] = true
	if not result.has("playoff_format"):
		result["playoff_format"] = PlayoffRules.FORMAT_SINGLE
	result["group_draw_rules"] = rules(result.get("group_draw_rules", {}))
	return result

static func shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var item: Variant = items[i]
		items[i] = items[j]
		items[j] = item

static func draw(identities: Dictionary, count: int, settings: Variant, rng: RandomNumberGenerator) -> Array:
	var ids: Array = identities.keys()
	ids.sort()
	var groups: Array = []
	var group_count := clampi(count, 1, maxi(1, int(ids.size() / 2)))
	for i in group_count:
		groups.append({"index": i, "club_ids": []})
	# Shuffle ties as well as pots: equal scores must not lock the same seeds.
	shuffle(ids, rng)
	var mode := str(rules(settings)["mode"])
	if mode in [REPUTATION, ELO]:
		ids.sort_custom(func(a, b): return _draw_score(identities[a], mode) > _draw_score(identities[b], mode))
	for offset in range(0, ids.size(), group_count):
		var pot := ids.slice(offset, offset + group_count)
		shuffle(pot, rng)
		var targets: Array = range(group_count)
		shuffle(targets, rng)
		for j in pot.size():
			groups[int(targets[j])]["club_ids"].append(int(pot[j]))
	return groups

static func prepare(unit: Dictionary, season: int, rng: RandomNumberGenerator, next_id: int) -> int:
	# This runs only at a new edition's start, never on load or in an off year.
	var config := normalize(unit.get("rules", {}))
	unit["rules"] = config
	unit["competition_type"] = CompetitionTypes.TYPE_DIVISIONS # shared group table engine
	var groups := draw(unit.get("clubs_by_id", {}), int(config.get("divisions_count", 2)), config["group_draw_rules"], rng)
	var generated := FixtureGenerator.build_regular_season([], groups.size(), 1, int(config["matches_vs_own"]), 0, rng, groups)
	unit["divisions"] = groups
	unit["matches"] = generated["matches"]
	var standings: Array = []
	for group in groups:
		for id in group["club_ids"]:
			standings.append({"club_id": id, "division": group["index"], "played": 0, "won": 0, "drawn": 0, "lost": 0, "goals_for": 0, "goals_against": 0, "goal_diff": 0, "points": 0})
	unit["standings"] = standings
	for match_row in unit["matches"]:
		match_row["id"] = next_id
		next_id += 1
	var playoff: Dictionary = unit.get("playoff", {})
	var participants := (unit.get("clubs_by_id", {}) as Dictionary).size()
	playoff["enabled"] = participants >= 2
	var requested := int(config.get("teams_playoff", 0))
	playoff["teams"] = qualifier_count(participants, groups.size(), requested)
	playoff["scope"] = str(config.get("playoff_scope", CompetitionUnitRepository.SCOPE_PER_DIVISION))
	playoff["third_place"] = true
	unit["playoff"] = playoff
	unit["group_draw"] = {"season": season, "rules": config["group_draw_rules"].duplicate(true), "groups": groups.duplicate(true)}
	return next_id
