extends Node
## Club budget, wage bill. Seasonal cash comes from prizes, not a grant.
## Run: godot --headless --path . res://tests/game/test_club_finance.tscn

const ClubFinanceScript := preload("res://game/club_finance.gd")
const PlayerTypesScript := preload("res://game/player_types.gd")


var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Club finance tests ===")
	_test_income_scales()
	_test_income_spans_the_anchor_range()
	_test_starting_budget_is_zero()
	_test_wage_bill()
	_test_debit_allows_negative()
	_test_max_fee()
	_test_session_seeds_and_pays_once()
	_test_legacy_save_seeds_budget()
	_test_new_season_does_not_grant_income()
	GameSession.clear()
	_finish()


func _test_income_scales() -> void:
	var poor := ClubFinanceScript.seasonal_income(0, 200)
	var mid := ClubFinanceScript.seasonal_income(10, 500)
	var rich := ClubFinanceScript.seasonal_income(20, 900)
	_assert(poor > 0, "poor income > 0")
	_assert(mid > poor, "mid income > poor (%d vs %d)" % [mid, poor])
	_assert(rich > mid, "rich income > mid (%d vs %d)" % [rich, mid])
	_assert(
		ClubFinanceScript.seasonal_income(20, 500) > ClubFinanceScript.seasonal_income(10, 500),
		"finance level alone raises income"
	)
	_assert(
		ClubFinanceScript.seasonal_income(10, 900) > ClubFinanceScript.seasonal_income(10, 200),
		"reputation alone raises income"
	)


## The whole price scale is calibrated against these two ends.
func _test_income_spans_the_anchor_range() -> void:
	var worst := ClubFinanceScript.seasonal_income(0, 0)
	var best := ClubFinanceScript.seasonal_income(20, 1000)
	_assert(worst == ClubFinanceScript.INCOME_MIN, "worst club banks the floor (%d)" % worst)
	_assert(best == ClubFinanceScript.INCOME_MAX, "best club banks the ceiling (%d)" % best)
	_assert(
		ClubFinanceScript.seasonal_income(10, 500) < best / 2,
		"an average club earns well under half of the ceiling"
	)


func _test_starting_budget_is_zero() -> void:
	_assert(ClubFinanceScript.starting_budget(0, 0) == 0, "poor clubs open empty")
	_assert(ClubFinanceScript.starting_budget(20, 1000) == 0, "rich clubs also open empty")


func _test_wage_bill() -> void:
	var squad := [
		{"wage": 5000},
		{"wage": 7000},
	]
	var youth := [{"wage": 2000}]
	var coach := {"wage": 8000}
	_assert(
		ClubFinanceScript.wage_bill(squad, youth, coach) == 22000,
		"wage bill sums first team, youth and coach"
	)
	_assert(ClubFinanceScript.wage_bill([]) == 0, "empty bill is 0")
	_assert(ClubFinanceScript.wage_of({"wage": -10}) == 0, "negative wage clamps to 0")


func _test_debit_allows_negative() -> void:
	_assert(ClubFinanceScript.debit(1000, 2500) == -1500, "budget may go negative")
	_assert(ClubFinanceScript.credit(1000, 500) == 1500, "credit adds")
	_assert(ClubFinanceScript.debit(1000, -50) == 1000, "debit ignores negative amount")


func _test_max_fee() -> void:
	_assert(ClubFinanceScript.max_single_fee(-100) == 0, "no fee when broke")
	_assert(ClubFinanceScript.max_single_fee(0) == 0, "no fee with empty cash")
	var cap := ClubFinanceScript.max_single_fee(1_000_000)
	_assert(cap == 600_000, "one signing is 60% of cash (%d)" % cap)
	_assert(cap < 1_000_000, "one signing never spends the whole budget")
	_assert(
		ClubFinanceScript.max_single_fee(2_000_000) > ClubFinanceScript.max_single_fee(1_000_000),
		"more cash raises the fee ceiling"
	)


func _test_session_seeds_and_pays_once() -> void:
	var grant := ClubFinanceScript.starting_budget(10, 500)
	var payload := _session_payload({
		"season_day": GameSession.MARKET_LAST_DAY,
		"club_budgets": {1: grant},
		"wages_paid_for_season": 0,
		"players_by_club": {
			1: [
				_player(1, 4000),
				_player(2, 6000),
			],
		},
		"youth_players_by_club": {1: [_player(3, 1500)]},
		"coaches_by_club": {1: {"id": 1, "club_id": 1, "wage": 2500}},
	})
	var loaded: Dictionary = GameSession.apply_save_payload(payload)
	_assert(bool(loaded.get("success", false)), "finance session loads")
	_assert(GameSession.get_club_budget(1) == grant, "seeded budget kept")
	var bill := GameSession.get_club_wage_bill(1)
	_assert(bill == 14000, "wage bill 4000+6000+1500+2500 (got %d)" % bill)

	var advanced: Dictionary = GameSession.advance_day()
	_assert(bool(advanced.get("success", false)), "advance from last market day")
	_assert(int(GameSession.season_day) == GameSession.FIRST_MATCH_DAY, "calendar moves to match day 1")
	_assert(
		GameSession.get_club_budget(1) == grant - bill,
		"wages deducted once after the window (got %d)" % GameSession.get_club_budget(1)
	)
	var after := GameSession.get_club_budget(1)
	GameSession.advance_day()
	_assert(GameSession.get_club_budget(1) == after, "wages are not deducted twice")
	GameSession.clear()


func _test_legacy_save_seeds_budget() -> void:
	var expected := ClubFinanceScript.starting_budget(8, 400)
	var loaded: Dictionary = GameSession.apply_save_payload({
		"version": 8,
		"season_number": 1,
		"season_day": GameSession.FIRST_MATCH_DAY,
		"units": [{
			"id": 1,
			"clubs_by_id": {
				1: {"id": 1, "name": "Alpha", "finance_level": 8, "reputation": 400},
			},
			"matches": [],
		}],
		"players_by_club": {},
		"coaches_by_club": {},
	})
	_assert(bool(loaded.get("success", false)), "legacy save without budgets loads")
	_assert(GameSession.get_club_budget(1) == expected, "legacy save seeds starting budget")
	_assert(
		GameSession.wages_paid_for_season == 1,
		"mid-season legacy save does not pay wages again"
	)
	GameSession.clear()


func _test_new_season_does_not_grant_income() -> void:
	GameSession.apply_save_payload(_session_payload({
		"season_day": GameSession.FIRST_MATCH_DAY,
		"club_budgets": {1: 25000},
		"wages_paid_for_season": 1,
	}))
	var before := GameSession.get_club_budget(1)
	GameSession._apply_unit_prizes()
	_assert(
		GameSession.get_club_budget(1) == before,
		"no prize table means no seasonal credit"
	)
	GameSession.clear()


func _session_payload(overrides: Dictionary) -> Dictionary:
	var payload := {
		"version": GameSession.SAVE_VERSION,
		"season_number": 1,
		"season_day": GameSession.MARKET_LAST_DAY,
		"season_total_days": 32,
		"selected_unit_id": 1,
		"season_finished": false,
		"units": [{
			"id": 1,
			"clubs_by_id": {
				1: {"id": 1, "name": "Alpha", "finance_level": 10, "reputation": 500},
			},
			"matches": [],
		}],
		"players_by_club": {},
		"youth_players_by_club": {},
		"free_agents": [],
		"coaches_by_club": {},
		"club_budgets": {},
		"wages_paid_for_season": 0,
		"transfer_log": [],
	}
	for key in overrides.keys():
		payload[key] = overrides[key]
	return payload


func _player(id: int, wage: int) -> Dictionary:
	return {
		"id": id,
		"club_id": 1,
		"name": "P%d" % id,
		"position": PlayerTypesScript.POS_CM,
		"age": 24,
		"wage": wage,
		"current_ability": 50,
		"potential_ability": 60,
	}


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  %s" % message)
	else:
		_failed += 1
		print("  FAIL  %s" % message)


func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
