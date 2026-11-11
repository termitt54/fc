extends RefCounted
## Pure read model: preserve historical fees, including retired players.

static func rows(log: Array, club_id: int, filters: Dictionary = {}) -> Array:
	var result: Array = []
	var query := str(filters.get("query", "")).strip_edges().to_lower()
	for entry in log:
		if typeof(entry) != TYPE_DICTIONARY or int(entry.get("club_id", 0)) != club_id:
			continue
		var direction := str(entry.get("direction", ""))
		if direction not in ["in", "out", "bid"]:
			continue
		if int(filters.get("season", 0)) > 0 and int(entry.get("season", 0)) != int(filters.season):
			continue
		if str(filters.get("direction", "all")) != "all" and direction != str(filters.direction):
			continue
		var fee := maxi(0, int(entry.get("fee", 0)))
		var payment := str(filters.get("payment", "all"))
		if (payment == "paid" and fee == 0) or (payment == "free" and fee > 0):
			continue
		var position := PlayerTypes.normalize_position(str(entry.get("position", "")))
		if str(filters.get("position", "all")) != "all" and position != str(filters.position):
			continue
		if fee < int(filters.get("min_fee", 0)):
			continue
		if int(filters.get("max_fee", 0)) > 0 and fee > int(filters.max_fee):
			continue
		var other := str(entry.get("other_club", "—"))
		var name := str(entry.get("player_name", "Игрок"))
		if not query.is_empty() and not (name + " " + other).to_lower().contains(query):
			continue
		var own := str(entry.get("club_name", "Клуб"))
		result.append({
			"season": int(entry.get("season", 0)), "day": int(entry.get("day", 0)),
			"player_id": int(entry.get("player_id", 0)), "player_name": name,
			"position": position, "direction": direction, "fee": fee,
			"club_id": club_id, "to_club_id": club_id if direction == "in" else 0,
			"from": other if direction != "out" else own,
			"to": own if direction != "out" else other,
		})
	return result

static func summary(entries: Array) -> Dictionary:
	var result := {"incoming": 0, "outgoing": 0, "bids": 0, "spent": 0,
		"earned": 0, "paid_incoming": 0, "paid_outgoing": 0,
		"record_purchase": 0, "record_sale": 0, "balance": 0, "paid_percent": 0.0,
		"average_purchase": 0.0}
	for entry in entries:
		var fee := maxi(0, int(entry.get("fee", 0)))
		match str(entry.get("direction", "")):
			"in":
				result.incoming += 1
				result.spent += fee
				result.paid_incoming += int(fee > 0)
				result.record_purchase = maxi(result.record_purchase, fee)
			"out":
				result.outgoing += 1
				result.earned += fee
				result.paid_outgoing += int(fee > 0)
				result.record_sale = maxi(result.record_sale, fee)
			"bid": result.bids += 1
	result.balance = result.earned - result.spent
	result.paid_percent = 100.0 * result.paid_incoming / maxf(1.0, result.incoming)
	result.average_purchase = float(result.spent) / maxf(1.0, result.paid_incoming)
	return result
