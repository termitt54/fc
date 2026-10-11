class_name ClubFinance
extends RefCounted
## Session money: club budget and seasonal wage bill.
## Income is prize money from completed units, not a finance-level grant.
## Negative budget is allowed. Wage/value curves still use INCOME_MIN..INCOME_MAX
## as the reference prize scale they were calibrated against.


const FINANCE_MIN := 0
const FINANCE_MAX := 20
const REPUTATION_MAX := 1000

## Reference prize scale for wage/value calibration only. Not paid automatically.
const INCOME_MIN := 100000
const INCOME_MAX := 50000000
const INCOME_EXP := 2.7
const INCOME_FINANCE_WEIGHT := 0.5
const INCOME_REPUTATION_WEIGHT := 0.5

## One signing can eat most of the cash on hand, never the whole pile.
const FEE_BUDGET_SHARE := 0.6


static func clamp_finance_level(value: int) -> int:
	return clampi(value, FINANCE_MIN, FINANCE_MAX)


## 0.0 for a village side, 1.0 for a continental heavyweight.
static func club_rating(finance_level: int, reputation: int = 500) -> float:
	var level := float(clamp_finance_level(finance_level)) / float(FINANCE_MAX)
	var rep := float(clampi(reputation, 0, REPUTATION_MAX)) / float(REPUTATION_MAX)
	return clampf(
		INCOME_FINANCE_WEIGHT * level + INCOME_REPUTATION_WEIGHT * rep, 0.0, 1.0
	)


## Expected prize-scale income for a club of this tier. Used to calibrate wages,
## not credited to the budget.
static func seasonal_income(finance_level: int, reputation: int = 500) -> int:
	var raw := float(INCOME_MAX) * pow(club_rating(finance_level, reputation), INCOME_EXP)
	return _round_money(clampf(raw, float(INCOME_MIN), float(INCOME_MAX)))


static func starting_budget(_finance_level: int = 10, _reputation: int = 500) -> int:
	return 0


static func max_single_fee(budget: int, _finance_level: int = 10, _reputation: int = 500) -> int:
	if budget <= 0:
		return 0
	return _round_money(float(budget) * FEE_BUDGET_SHARE)


static func wage_of(entity: Dictionary) -> int:
	return maxi(0, int(entity.get("wage", 0)))


static func wage_bill(players: Array, youth: Array = [], coach: Dictionary = {}) -> int:
	var total := 0
	for player in players:
		if typeof(player) == TYPE_DICTIONARY:
			total += wage_of(player)
	for player in youth:
		if typeof(player) == TYPE_DICTIONARY:
			total += wage_of(player)
	if not coach.is_empty():
		total += wage_of(coach)
	return total


static func credit(budget: int, amount: int) -> int:
	return budget + maxi(0, amount)


static func debit(budget: int, amount: int) -> int:
	return budget - maxi(0, amount)


static func apply_wages(budget: int, players: Array, youth: Array = [], coach: Dictionary = {}) -> int:
	return debit(budget, wage_bill(players, youth, coach))


static func coerce_budgets(raw: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = raw
	for key in source.keys():
		out[int(key)] = int(source[key])
	return out


static func _round_money(value: float) -> int:
	if value <= 0.0:
		return 0
	return int(round(value / 1000.0)) * 1000
