extends Node
## Parallel divisions are dealt again each season, not copied forward.
## Run: godot --headless --path . res://tests/game/test_division_sort.tscn

const Generator := preload("res://game/fixture_generator.gd")
const Repo := preload("res://database/repositories/world/competition_unit_repository.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Division sort ===")
	_test_reputation_stripe()
	_test_random_changes_and_stays_balanced()
	_test_explicit_pools_stay()
	_test_new_season_uses_the_rule()
	_test_elo_draw()
	_test_elo_builder_and_new_season()
	_test_elo_editor_storage()
	print("=== Division sort: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


func _test_reputation_stripe() -> void:
	var reps := {1: 900, 2: 850, 3: 800}
	var divisions: Array = Generator.assign_divisions([2, 3, 1], 2, 12, Repo.DIVISION_SORT_REPUTATION, reps)
	_assert(divisions[0]["club_ids"] == [1, 3], "900 and 800 land in the first division")
	_assert(divisions[1]["club_ids"] == [2], "850 lands in the second division")
	var four: Array = Generator.assign_divisions([4, 1, 3, 2], 2, 2, Repo.DIVISION_SORT_REPUTATION, {1: 100, 2: 90, 3: 80, 4: 70})
	_assert(four[0]["club_ids"] == [1, 3] and four[1]["club_ids"] == [2, 4], "the stripe continues down the reputation list")
	var tied: Array = Generator.assign_divisions([9, 2], 2, 1, Repo.DIVISION_SORT_REPUTATION, {9: 500, 2: 500})
	_assert(tied[0]["club_ids"] == [2] and tied[1]["club_ids"] == [9], "equal reputation keeps the lower club id first")


func _test_random_changes_and_stays_balanced() -> void:
	var ids: Array = []
	for i in 24:
		ids.append(i + 1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var first: Array = Generator.assign_divisions(ids, 2, 12, Repo.DIVISION_SORT_RANDOM, {}, rng)
	_assert((first[0]["club_ids"] as Array).size() == 12 and (first[1]["club_ids"] as Array).size() == 12, "a random deal splits the field evenly")
	rng.seed = 11
	var again: Array = Generator.assign_divisions(ids, 2, 12, Repo.DIVISION_SORT_RANDOM, {}, rng)
	_assert(first[0]["club_ids"] == again[0]["club_ids"], "the same seed repeats the draw")
	rng.seed = 99
	var other: Array = Generator.assign_divisions(ids, 2, 12, Repo.DIVISION_SORT_RANDOM, {}, rng)
	_assert(first[0]["club_ids"] != other[0]["club_ids"], "another seed deals a different first division")
	_assert(Repo.normalize_division_sort("") == Repo.DIVISION_SORT_RANDOM, "a missing rule is a random deal")


func _test_explicit_pools_stay() -> void:
	var locked := [{"index": 0, "club_ids": [1, 3]}, {"index": 1, "club_ids": [2]}]
	var generated: Dictionary = Generator.build_regular_season([1, 2, 3], 2, 2, 0, 0, null, locked, Repo.DIVISION_SORT_REPUTATION, {1: 1, 2: 900, 3: 1})
	_assert(generated["divisions"] == locked, "a prepared draw is not dealt again")


func _test_new_season_uses_the_rule() -> void:
	var unit := {
		"competition_type": "DIVISIONS",
		"rules": {
			"divisions_count": 2,
			"teams_per_division": 2,
			"matches_vs_own": 0,
			"matches_vs_other": 0,
			"division_sort": Repo.DIVISION_SORT_REPUTATION,
		},
		"divisions": [{"index": 0, "club_ids": [2, 4]}, {"index": 1, "club_ids": [1, 3]}],
		"clubs_by_id": {
			1: {"reputation": 900},
			2: {"reputation": 850},
			3: {"reputation": 800},
			4: {"reputation": 100},
		},
		"playoff": {},
	}
	var next: Dictionary = GameSession._reset_unit_for_new_season(unit)
	var pools: Array = next["divisions"]
	_assert(pools[0]["club_ids"] == [1, 3], "the new season puts 900 and 800 in division 1")
	_assert(pools[1]["club_ids"] == [2, 4], "the new season puts 850 and 100 in division 2")


func _assert(ok: bool, message: String) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		push_error(message)
		print("FAIL: " + message)


func _test_elo_draw() -> void:
	_assert(Repo.normalize_division_sort(" elo ") == Repo.DIVISION_SORT_ELO, "Elo mode survives normalization")
	_assert(Repo.division_sort_options().any(func(option): return option.id == Repo.DIVISION_SORT_ELO and option.label == "По Elo"), "Editor offers Elo")
	var clubs := {
		1: {"reputation": 1000, "club_elo": {"elo": 100.1}},
		2: {"reputation": 900, "club_elo": {"elo": 100.9}},
		3: {"reputation": 0, "club_elo": {"elo": 2800.0}},
		4: {"reputation": 800, "club_elo": {"elo": 0.0}},
		5: {"reputation": 700, "club_elo": {"elo": 1200.0}},
		6: {"reputation": 600, "club_elo": {"elo": 999.0}},
		7: {"reputation": 500, "club_elo": {"elo": 900.0}},
		8: {"reputation": 400, "club_elo": {"elo": 800.0}},
	}
	var ids := clubs.keys()
	var scores := Generator.division_scores_of(ids, clubs, Repo.DIVISION_SORT_ELO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99101
	var before := rng.state
	var groups := Generator.assign_divisions(ids, 3, 3, Repo.DIVISION_SORT_ELO, scores, rng)
	_assert(groups[0].club_ids == [3, 7, 1] and groups[1].club_ids == [5, 8, 4] and groups[2].club_ids == [6, 2], "Elo is independent of prestige, retains decimals and supports scores above 1000")
	_assert(rng.state == before, "Ranked draw does not consume random numbers")
	_assert(scores[4] == 0.0, "Zero Elo is a real score, not a missing value")
	var fallback := Generator.division_scores_of([1, 2], {"1": {"reputation": 999}, "2": {"club_elo": {"elo": 650.5}}}, Repo.DIVISION_SORT_ELO, 750, {1: 820})
	_assert(fallback[1] == 820 and fallback[2] == 650.5, "Missing Elo uses championship seed, including string dictionary keys")
	var reputation_groups := Generator.assign_divisions(ids, 3, 3, Repo.DIVISION_SORT_REPUTATION, Generator.division_scores_of(ids, clubs, Repo.DIVISION_SORT_REPUTATION), rng)
	_assert(reputation_groups != groups, "Reputation mode keeps using reputation")
	var locked := [{"index": 0, "club_ids": [1, 2]}, {"index": 1, "club_ids": [3, 4]}]
	var calendar := Generator.build_regular_season([1, 2, 3, 4], 2, 2, 1, 0, rng, locked, Repo.DIVISION_SORT_ELO, scores)
	_assert(calendar.divisions == locked, "Explicit group assignments are not overridden by Elo mode")


func _test_elo_builder_and_new_season() -> void:
	var builder := SeasonBuilder.new()
	var competition := {"id": 1, "name": "Elo fixture", "scope_type": CompetitionTypes.SCOPE_INTERCONTINENTAL_CLUB}
	var unit := {"id": 1, "unit_kind": "DIVISION", "competition_type": "DIVISIONS", "division_strength": 800, "divisions_count": 2, "teams_per_division": 2, "division_sort": "ELO", "matches_vs_own": 1, "matches_vs_other": 0}
	var clubs := {1: {"reputation": 1000, "club_elo": {"elo": 100, "seed_version": 2}}, 2: {"reputation": 900, "club_elo": {"elo": 300, "seed_version": 2}}, 3: {"reputation": 100, "club_elo": {"elo": 200, "seed_version": 2}}, 4: {"reputation": 0, "club_elo": {"elo": 400, "seed_version": 2}}}
	var rng := RandomNumberGenerator.new()
	rng.seed = 5314
	var built := builder._build_unit_season(competition, unit, clubs, clubs.keys(), rng)
	_assert(built.rules.division_sort == "ELO" and built.divisions[0].club_ids == [4, 3] and built.divisions[1].club_ids == [2, 1], "New-season builder uses Elo values")
	_assert(built.matches.size() == 2, "Calendar contains the correct number of group games")
	for match_row in built.matches:
		_assert((match_row.home_id in [4, 3] and match_row.away_id in [4, 3]) or (match_row.home_id in [2, 1] and match_row.away_id in [2, 1]), "Calendar follows Elo group membership")
	clubs[1].club_elo.elo = 1000
	var next := GameSession._reset_unit_for_new_season(built)
	_assert(next.divisions[0].club_ids == [1, 2] and next.divisions[1].club_ids == [4, 3], "Next season redraws by updated Elo, ignoring previous divisions")
	var pending := [{"competition": competition, "unit": unit, "clubs_by_id": {1: {}, 2: {}}}, {"competition": competition, "unit": {"id": 2, "unit_kind": "CUP", "competition_type": "CUP", "division_strength": 200}, "clubs_by_id": {1: {}, 3: {}}}]
	var seeds := builder._initial_club_elos(pending)
	_assert(seeds[1] == 800 and seeds[2] == 800 and seeds[3] == 200, "First world seeds prioritize championship over cup strength")
	var missing := builder._build_unit_season(competition, unit, {1: {"reputation": 0}, 2: {"reputation": 1000}, 3: {"reputation": 500}, 4: {"reputation": 800}}, [1, 2, 3, 4], rng)
	_assert(missing.divisions[0].club_ids == [1, 3] and missing.divisions[1].club_ids == [2, 4], "Equal initial Elo uses stable club-id tie break, not prestige")


func _test_elo_editor_storage() -> void:
	assert(OS.get_user_data_dir().replace("\\", "/").ends_with("/fc-load-benchmark"))
	var competition := CompetitionRepository.new().create({"name": "Elo composition integration", "scope_type": CompetitionTypes.SCOPE_INTERCONTINENTAL_CLUB})
	_assert(competition.success, "Competition fixture created")
	if not competition.success: return
	var repo := Repo.new()
	var created := repo.create({"competition_id": competition.data.id, "unit_kind": "DIVISION", "name": "Elo groups", "competition_type": "DIVISIONS", "division_sort": "ELO", "divisions_count": 2, "teams_per_division": 2})
	_assert(created.success and created.data.division_sort == "ELO", "Elo rule persists through SQLite create")
	if created.success:
		var updated := repo.update(int(created.data.id), {"division_sort": "REPUTATION"})
		_assert(updated.success and updated.data.division_sort == "REPUTATION", "Other draw modes can still be selected")
		updated = repo.update(int(created.data.id), {"division_sort": "ELO"})
		_assert(updated.success and repo.get_by_competition(int(competition.data.id)).data[0].division_sort == "ELO", "Elo rule persists through update and read")
		var dialog: Control = preload("res://scenes/world_editor/dialogs/competition_form_dialog.tscn").instantiate()
		add_child(dialog)
		dialog.open_edit(competition.data)
		var selectors := dialog.find_children("*", "VBoxContainer", true, false)
		var found := false
		for selector in selectors:
			if selector is WeSelectField and selector.label == "Состав":
				found = selector.selected_id == "ELO" and selector._ids.has("ELO")
		_assert(found, "Actual composition selector displays the saved Elo option")
		dialog.free()
	CompetitionRepository.new().delete(int(competition.data.id))
