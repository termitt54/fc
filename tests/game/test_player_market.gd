extends Node
## Headless checks for PlayerMarket: salaries, fees and coach pay must stay
## consistent with the club income anchor (ClubFinance.INCOME_MIN..INCOME_MAX).
## The calibration test is the important one — it is what keeps every club able
## to pay the squad its tier would realistically field.
## Run: godot --headless --path . res://tests/game/test_player_market.tscn

const PlayerMarketScript := preload("res://game/player_market.gd")
const ClubFinanceScript := preload("res://game/club_finance.gd")
const YouthGraduationScript := preload("res://game/youth_graduation.gd")

## label, finance_level, reputation, squad mean CA. A 100k club is
## semi-professional, a 50m club is a continental heavyweight.
const TIERS: Array = [
	["worst", 0, 0, 35],
	["poor", 5, 200, 45],
	["mid", 10, 500, 57],
	["strong", 15, 750, 67],
	["best", 20, 1000, 75],
]
const SQUAD_SIZE := 25
const RESERVE_SIZE := 12
const SQUAD_SPREAD := 12
const SQUAD_AGES: Array = [18, 20, 22, 24, 26, 28, 30, 32, 34]

## Wages leave most of the prize scale free for transfers.
const SHARE_MIN := 0.10
const SHARE_MAX := 0.30

var _failed := 0
var _passed := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	print("=== Player market tests ===")
	_test_wage_rises_with_ability_and_fame()
	_test_wage_peaks_in_the_late_twenties()
	_test_wage_has_a_floor()
	_test_value_rises_with_ability()
	_test_value_collapses_with_age()
	_test_buyers_pay_for_potential()
	_test_potential_premium_fades_with_age()
	_test_fee_is_a_sane_multiple_of_salary()
	_test_every_tier_can_pay_its_squad()
	_test_only_the_rich_buy_the_best()
	_test_coach_pay_scales_with_the_club()
	_test_coach_is_a_small_slice_of_the_bill()
	_test_value_refresh_follows_growth()
	_test_contract_reprice_follows_growth()
	_test_transfer_keeps_the_old_wage()
	_test_reputation_drifts_without_jumping()
	_test_squad_refresh_survives_junk()
	_test_reserve_and_listing_respect_the_floors()
	_finish()


func _test_wage_rises_with_ability_and_fame() -> void:
	var weak := PlayerMarketScript.wage_for(50.0, 500, 27)
	var strong := PlayerMarketScript.wage_for(70.0, 500, 27)
	var elite := PlayerMarketScript.wage_for(90.0, 500, 27)
	_assert(strong > weak * 3, "CA 70 earns multiples of CA 50 (%d vs %d)" % [strong, weak])
	_assert(elite > strong * 3, "CA 90 earns multiples of CA 70 (%d vs %d)" % [elite, strong])
	var obscure := PlayerMarketScript.wage_for(70.0, 200, 27)
	var famous := PlayerMarketScript.wage_for(70.0, 900, 27)
	_assert(famous > obscure * 2, "fame alone more than doubles pay (%d vs %d)" % [famous, obscure])


func _test_wage_peaks_in_the_late_twenties() -> void:
	var teen := PlayerMarketScript.wage_for(70.0, 600, 18)
	var rising := PlayerMarketScript.wage_for(70.0, 600, 23)
	var peak := PlayerMarketScript.wage_for(70.0, 600, 28)
	var veteran := PlayerMarketScript.wage_for(70.0, 600, 36)
	_assert(teen < rising, "a teenager is on rookie terms (%d vs %d)" % [teen, rising])
	_assert(rising < peak, "pay peaks after the rookie years (%d vs %d)" % [rising, peak])
	_assert(veteran < peak, "a veteran takes a pay cut (%d vs %d)" % [veteran, peak])


func _test_wage_has_a_floor() -> void:
	var nobody := PlayerMarketScript.wage_for(8.0, 0, 19)
	_assert(
		nobody == PlayerMarketScript.WAGE_FLOOR,
		"the weakest contract is the floor (%d)" % nobody
	)
	_assert(
		PlayerMarketScript.wage_for(-5.0, -100, 27) >= PlayerMarketScript.WAGE_FLOOR,
		"junk input still returns a payable wage"
	)


func _test_value_rises_with_ability() -> void:
	var filler := PlayerMarketScript.value_for(45, 45, 27, 300)
	var starter := PlayerMarketScript.value_for(70, 70, 27, 600)
	var star := PlayerMarketScript.value_for(90, 90, 27, 850)
	_assert(starter > filler * 10, "a starter costs an order more than a filler (%d vs %d)" % [starter, filler])
	_assert(star > starter * 5, "a star costs multiples of a starter (%d vs %d)" % [star, starter])
	_assert(
		PlayerMarketScript.value_for(10, 10, 38, 0) == PlayerMarketScript.VALUE_FLOOR,
		"a worthless veteran still carries the floor price"
	)


func _test_value_collapses_with_age() -> void:
	var peak := PlayerMarketScript.value_for(80, 80, 26, 700)
	var thirty := PlayerMarketScript.value_for(80, 80, 30, 700)
	var thirty_four := PlayerMarketScript.value_for(80, 80, 34, 700)
	_assert(thirty < peak / 2, "a 30-year-old is worth under half his peak (%d vs %d)" % [thirty, peak])
	_assert(thirty_four < thirty / 4, "a 34-year-old is nearly worthless (%d vs %d)" % [thirty_four, thirty])
	# Past 35 the resale multiple drops below one year's wage.
	_assert(
		PlayerMarketScript.value_for(85, 85, 36, 900)
			< PlayerMarketScript.wage_for(85.0, 900, 36),
		"a veteran past 35 is worth less than a year's wage"
	)


func _test_buyers_pay_for_potential() -> void:
	var wonderkid := PlayerMarketScript.value_for(50, 95, 18, 600)
	var plain := PlayerMarketScript.value_for(50, 50, 18, 600)
	_assert(wonderkid > plain * 5, "potential drives a wonderkid's fee (%d vs %d)" % [wonderkid, plain])
	# He is cheap to employ while still being expensive to buy.
	_assert(
		wonderkid > PlayerMarketScript.wage_for(50.0, 600, 18) * 20,
		"a wonderkid's fee dwarfs his salary"
	)


func _test_potential_premium_fades_with_age() -> void:
	var young_gap := PlayerMarketScript.value_for(60, 90, 19, 600) \
		/ float(PlayerMarketScript.value_for(60, 60, 19, 600))
	var old_gap := PlayerMarketScript.value_for(60, 90, 30, 600) \
		/ float(PlayerMarketScript.value_for(60, 60, 30, 600))
	_assert(young_gap > 2.0, "a 19-year-old's unused potential is priced in (x%.1f)" % young_gap)
	_assert(
		is_equal_approx(old_gap, 1.0),
		"nobody pays for a 30-year-old's unreached potential (x%.2f)" % old_gap
	)


func _test_fee_is_a_sane_multiple_of_salary() -> void:
	for entry in [55, 70, 85]:
		var ca := int(entry)
		var rep := 500 + ca * 3
		var peak_ratio := float(PlayerMarketScript.value_for(ca, ca, 26, rep)) \
			/ float(PlayerMarketScript.wage_for(float(ca), rep, 26))
		_assert(
			peak_ratio > 18.0 and peak_ratio < 54.0,
			"CA %d peak fee is %.1f salaries" % [ca, peak_ratio]
		)


## The anchor test: a squad that fits its club's tier must fit its club's wallet.
func _test_every_tier_can_pay_its_squad() -> void:
	for tier in TIERS:
		var label := str(tier[0])
		var finance := int(tier[1])
		var reputation := int(tier[2])
		var mean_ca := int(tier[3])
		var income := ClubFinanceScript.seasonal_income(finance, reputation)
		var bill := _wage_bill(mean_ca, reputation)
		var share := float(bill) / float(income)
		_assert(
			share > SHARE_MIN and share < SHARE_MAX,
			"%s club spends %.0f%% of its %d income on wages (bill %d)"
				% [label, share * 100.0, income, bill]
		)


func _test_only_the_rich_buy_the_best() -> void:
	var elite := PlayerMarketScript.value_for(85, 85, 27, _player_rep(85, 1000))
	var starter := PlayerMarketScript.value_for(70, 72, 26, _player_rep(70, 500))
	var best_cap := ClubFinanceScript.max_single_fee(ClubFinanceScript.seasonal_income(20, 1000))
	var mid_cap := ClubFinanceScript.max_single_fee(ClubFinanceScript.seasonal_income(10, 500))
	var poor_cap := ClubFinanceScript.max_single_fee(ClubFinanceScript.seasonal_income(5, 200))
	_assert(best_cap >= elite, "the best club can sign an elite player (%d vs %d)" % [best_cap, elite])
	_assert(mid_cap < elite, "a mid club cannot reach an elite (%d vs %d)" % [mid_cap, elite])
	_assert(mid_cap >= starter, "a mid club can still buy a starter (%d vs %d)" % [mid_cap, starter])
	_assert(poor_cap < starter, "a poor club cannot even buy a starter (%d vs %d)" % [poor_cap, starter])


func _test_coach_pay_scales_with_the_club() -> void:
	var poor := PlayerMarketScript.coach_wage_for(30, _coach_rep(30, 0), 50)
	var mid := PlayerMarketScript.coach_wage_for(56, _coach_rep(56, 500), 50)
	var elite := PlayerMarketScript.coach_wage_for(82, _coach_rep(82, 1000), 50)
	_assert(mid > poor * 5, "a mid-club coach earns multiples of a bottom one (%d vs %d)" % [mid, poor])
	_assert(elite > mid * 5, "an elite coach earns multiples of a mid one (%d vs %d)" % [elite, mid])
	_assert(
		PlayerMarketScript.coach_wage_for(70, 700, 65)
			< PlayerMarketScript.coach_wage_for(70, 700, 50),
		"a coach past retirement age takes less"
	)
	_assert(
		PlayerMarketScript.coach_wage_for(1, 0, 40) == PlayerMarketScript.COACH_WAGE_FLOOR,
		"coach pay has a floor too"
	)


func _test_coach_is_a_small_slice_of_the_bill() -> void:
	for tier in TIERS:
		var reputation := int(tier[2])
		var mean_ca := int(tier[3])
		# The generator ties coach ability to club reputation, so mirror it here.
		var coach_ca := int(round(30.0 + float(reputation) * 0.052))
		var coach := PlayerMarketScript.coach_wage_for(coach_ca, _coach_rep(coach_ca, reputation), 50)
		var bill := _wage_bill(mean_ca, reputation)
		var share := float(coach) / float(bill)
		_assert(
			share < 0.25,
			"%s club's coach is %.0f%% of the wage bill (%d of %d)"
				% [str(tier[0]), share * 100.0, coach, bill]
		)


func _test_value_refresh_follows_growth() -> void:
	var player := {
		"current_ability": 60, "potential_ability": 85, "age": 20, "reputation": 500,
		"value": 1,
	}
	var grown := PlayerMarketScript.refresh_value(player)
	_assert(int(player["value"]) == grown, "refresh writes the value back")
	player["current_ability"] = 75
	var after := PlayerMarketScript.refresh_value(player)
	_assert(after > grown, "a season of growth raises the price (%d -> %d)" % [grown, after])
	# A listing must not stay cheaper than the player is now worth.
	player["for_sale"] = true
	player["asking_price"] = 10
	PlayerMarketScript.refresh_value(player)
	_assert(int(player["asking_price"]) == after, "a stale asking price is lifted to the new value")


func _test_contract_reprice_follows_growth() -> void:
	var player := {
		"current_ability": 55, "potential_ability": 80, "age": 24, "reputation": 480,
		"wage": 1,
	}
	var first := PlayerMarketScript.reprice_contract(player)
	_assert(int(player["wage"]) == first, "reprice writes the wage back")
	player["current_ability"] = 72
	player["reputation"] = 620
	_assert(
		PlayerMarketScript.reprice_contract(player) > first,
		"a better player signs a better deal"
	)


func _test_transfer_keeps_the_old_wage() -> void:
	var player := {
		"current_ability": 78,
		"age": 27,
		"reputation": 720,
		"wage": 200_000,
	}
	var small := {"reputation": 180}
	var raw_club := PlayerMarketScript.wage_for(78.0, 180, 27)
	var signed := PlayerMarketScript.wage_for_move(player, small, false)
	_assert(
		signed >= 170_000,
		"a paid move keeps most of a 200k deal (%d)" % signed
	)
	_assert(
		signed > raw_club * 5,
		"the new club's raw reputation does not replace the contract (%d vs %d)" % [signed, raw_club]
	)
	var rich := {"reputation": 950}
	var raised := PlayerMarketScript.wage_for_move(player, rich, false)
	var personal := PlayerMarketScript.expected_wage_of(player)
	_assert(raised >= 200_000, "a richer club does not cut the wage (%d)" % raised)
	_assert(
		raised <= maxi(400_000, personal),
		"one move does not more than double pay unless he was underpaid (%d)" % raised
	)
	var free_wage := PlayerMarketScript.wage_for_move(player, small, true)
	_assert(
		free_wage >= 140_000,
		"a free agent takes a cut, not a reset (%d)" % free_wage
	)
	_assert(free_wage <= signed, "unemployment does not pay more than a transfer")
	PlayerMarketScript.sign_wage(player, small, false)
	_assert(int(player["wage"]) == signed, "signing writes the negotiated wage")


func _test_reputation_drifts_without_jumping() -> void:
	var player := {"current_ability": 90, "reputation": 100, "age": 22}
	var step := PlayerMarketScript.drift_reputation(player, 1000)
	_assert(
		step == 100 + PlayerMarketScript.REPUTATION_DRIFT_MAX,
		"fame climbs by at most one step a season (%d)" % step
	)
	for _i in 40:
		PlayerMarketScript.drift_reputation(player, 1000)
	var target := PlayerMarketScript.target_reputation(90, 1000)
	_assert(
		int(player["reputation"]) == target,
		"fame settles on its target (%d vs %d)" % [int(player["reputation"]), target]
	)
	# Dropping out of the game pulls a reputation back down.
	var faded := {"current_ability": 40, "reputation": 800, "age": 34}
	_assert(
		PlayerMarketScript.drift_reputation(faded, 0) < 800,
		"a forgotten player loses fame"
	)


func _test_squad_refresh_survives_junk() -> void:
	var squad: Array = [
		{"current_ability": 70, "potential_ability": 75, "age": 25, "reputation": 600},
		"not a player",
		{},
	]
	PlayerMarketScript.refresh_squad(squad, 500)
	var first: Dictionary = squad[0]
	_assert(int(first.get("value", 0)) > 0, "a real player gets priced")
	var blank: Dictionary = squad[2]
	_assert(
		int(blank.get("value", 0)) >= PlayerMarketScript.VALUE_FLOOR,
		"an empty record falls back to the floor price"
	)


func _test_reserve_and_listing_respect_the_floors() -> void:
	var player := {"wage": 1, "value": 1, "age": 19, "current_ability": 45}
	YouthGraduationScript.prepare_reserve(player)
	_assert(
		int(player["wage"]) >= PlayerMarketScript.WAGE_FLOOR,
		"a reserve deal never drops below the wage floor (%d)" % int(player["wage"])
	)
	YouthGraduationScript.prepare_listing(player, true)
	_assert(
		int(player["asking_price"]) >= PlayerMarketScript.VALUE_FLOOR,
		"a cut-price listing never drops below the value floor (%d)" % int(player["asking_price"])
	)


## Mirrors PlayerGenerator._roll_player_reputation without the random jitter.
func _player_rep(current_ability: int, club_rep: int) -> int:
	return PlayerMarketScript.target_reputation(current_ability, club_rep)


## Mirrors CoachGenerator._roll_reputation without the random jitter.
func _coach_rep(current_ability: int, club_rep: int) -> int:
	var from_ability := roundf(float(current_ability) / 100.0 * 820.0)
	return clampi(int(roundf(from_ability * 0.65 + float(club_rep) * 0.35)), 0, 1000)


## First team plus a reserve bench that sits below it, priced like the session does.
func _wage_bill(mean_ca: int, club_rep: int) -> int:
	var total := 0
	for entry in _squad(mean_ca, club_rep, SQUAD_SIZE, 0):
		total += int(entry)
	var reserve := 0
	for entry in _squad(mean_ca, club_rep, RESERVE_SIZE, SQUAD_SPREAD + 3):
		reserve += int(entry)
	return total + int(round(float(reserve) * YouthGraduationScript.RESERVE_WAGE_FACTOR))


## Wages for a squad spread evenly around mean_ca, strongest first.
func _squad(mean_ca: int, club_rep: int, count: int, offset: int) -> Array:
	var out: Array = []
	var span := float(SQUAD_SPREAD * 2)
	for i in count:
		var slide := span * float(i) / float(maxi(count - 1, 1))
		var ca := clampi(mean_ca + SQUAD_SPREAD - int(round(slide)) - offset, 15, 100)
		var age := int(SQUAD_AGES[i % SQUAD_AGES.size()])
		out.append(int(PlayerMarketScript.wage_for(float(ca), _player_rep(ca, club_rep), age)))
	return out


func _assert(condition: bool, label: String) -> void:
	if condition:
		_pass(label)
	else:
		_fail(label)


func _pass(label: String) -> void:
	_passed += 1
	print("PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	print("FAIL: %s" % label)


func _finish() -> void:
	print("=== Result: %d passed, %d failed ===" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
