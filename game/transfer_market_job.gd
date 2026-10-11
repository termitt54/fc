extends RefCounted
const TargetSort := preload("res://game/target_sort_work.gd")
## Resumable market orchestration. Each step handles one club/player/signing;
## all scoring and deal validation remain in TransferMarket.
var market: Script
var session: Node
var rng: RandomNumberGenerator
var clubs: Dictionary
var phase := 0
var cursor := 0
var order: Array = []
var targets: Array = []
var moved := {}
var protected := {}
var squad_cache := {}
var buyer_cache := {}
var buyers := {}
var agent_index := {}
var progressed := false
var tried := 0
var quota := 0
var sales_preparation := -1
var club_ids: Array = []
var sort_work: RefCounted = null
var phase_started: int
var profile := {}
var result := {"signed": 0, "bought": 0, "listed": 0, "unsold": 0, "upgrades": 0, "bids": 0}

func _init(lib: Script, owner: Node, random: RandomNumberGenerator) -> void:
	market = lib
	session = owner
	rng = random
	clubs = session._collect_session_clubs()
	order = clubs.keys()
	club_ids = order.duplicate()
	phase_started = Time.get_ticks_usec()

func _next(key: String) -> void:
	profile[key] = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase += 1
	cursor = 0
	phase_started = Time.get_ticks_usec()

func label() -> String:
	if phase == 1 and sales_preparation >= 0:
		return "Подготовка трансферов"
	return ["Списки на продажу", "Усиление составов", "Трансферы между клубами",
		"Освобождение игроков", "Подписание игроков", "Подписание игроков", "Рынок завершён"][mini(phase, 6)]

func step() -> bool:
	if clubs.is_empty() or not session.is_market_day(session.season_day):
		return true
	match phase:
		0:
			if cursor < order.size():
				var id: int = int(order[cursor])
				if session.season_day == session.MARKET_OPEN_DAY:
					result["listed"] += market._list_surplus(session, {id: clubs[id]})
				# Warm one club per step, never rebuild the whole world inside
				# the first buyer's search. Successful deals still invalidate it.
				squad_cache[id] = market._squad_market_info(session, id, session.get_club_players(id))
				cursor += 1
			else:
				_next("list_surplus_ms")
				order = market._club_pick_order(session, clubs, rng)
				quota = maxi(1, int(ceili(float(clubs.size()) / 5.0)))
		1:
			if sales_preparation >= 0:
				if sales_preparation < club_ids.size():
					var id: int = int(club_ids[sales_preparation])
					if session.get_club_players(id).size() < market.SQUAD_SIZE:
						buyers[id] = true
						buyer_cache[id] = market._buyer_info(session, id, clubs[id], session.get_club_players(id))
					for player in session.get_club_players(id):
						if typeof(player) == TYPE_DICTIONARY and market.is_buyable(player, int(session.season_number)):
							targets.append(player)
					sales_preparation += 1
				else:
					if not buyers.is_empty():
						if sort_work == null:
							sort_work = TargetSort.new(targets)
							return false
						if not sort_work.is_ready():
							return false
						var sorted: Array = []
						for i in sort_work.take():
							sorted.append(targets[i])
						targets = sorted
						sort_work = null
					else:
						targets = []
					phase = 2
					cursor = 0
					moved = {}
			elif cursor < order.size() and tried < quota:
				_upgrade(int(order[cursor]))
				cursor += 1
			else:
				profile["upgrade_wave_ms"] = float(Time.get_ticks_usec() - phase_started) / 1000.0
				phase_started = Time.get_ticks_usec()
				sales_preparation = 0
		2:
			if cursor < targets.size():
				_sale(targets[cursor])
				cursor += 1
			else:
				_next("club_sales_ms")
				order = clubs.keys()
		3:
			if session.season_day == session.MARKET_LAST_DAY and cursor < order.size():
				var id: int = int(order[cursor])
				result["unsold"] += market._release_unsold_listed(session, {id: clubs[id]})
				cursor += 1
			else:
				_next("release_unsold_ms")
				order = market._club_pick_order(session, clubs, rng)
				agent_index = market._build_agent_index(session.free_agents)
		4, 5:
			if cursor < order.size():
				var id: int = int(order[cursor])
				var squad: Array = session.get_club_players(id)
				var target: int = market.SQUAD_SIZE if phase == 5 else market._day_target(session.season_day, squad.size())
				if squad.size() < target and market._sign_one(session, rng, id, clubs[id], squad, phase == 5, agent_index):
					result["signed"] += 1
					progressed = true
				cursor += 1
			elif progressed:
				cursor = 0
				progressed = false
			else:
				market._compact_agents(session, agent_index)
				if phase == 4 and session.season_day == session.MARKET_LAST_DAY:
					phase = 5
					cursor = 0
					agent_index = market._build_agent_index(session.free_agents)
				else:
					phase = 6
					profile["free_agent_fill_ms"] = float(Time.get_ticks_usec() - phase_started) / 1000.0
					result["profile"] = profile
		6:
			return true
	return phase == 6

func _upgrade(id: int) -> void:
	var club: Dictionary = clubs[id]
	if int(club.get("upgrade_bid_season", 0)) == int(session.season_number) \
		or session.get_club_players(id).size() != market.SQUAD_SIZE or int(session.get_club_budget(id)) <= 0:
		return
	var squad: Array = session.get_club_players(id)
	var coach: Dictionary = session.get_club_coach(id)
	var outgoing: Dictionary = market._pick_outgoing(session, id, squad, coach)
	if outgoing.is_empty():
		return
	var target: Dictionary = market._find_upgrade_target(session, clubs, id, club, coach, outgoing, moved, rng, squad_cache)
	club["upgrade_bid_season"] = int(session.season_number)
	if target.is_empty():
		return
	tried += 1
	result["bids"] += 1
	var player: Dictionary = target.get("player", {})
	var seller_id: int = int(target.get("seller_id", 0))
	if not bool(target.get("accepted", false)):
		market._log_bid(session, id, club, clubs.get(seller_id, {}), player, str(target.get("reason", "отказ")))
		return
	if market._execute_upgrade(session, clubs, id, seller_id, outgoing, player, rng):
		squad_cache.erase(id)
		squad_cache.erase(seller_id)
		result["bought"] += 1
		result["upgrades"] += 1
		protected[id] = true
		moved[int(player.get("id", 0))] = true
		moved[int(outgoing.get("id", 0))] = true

func _sale(player: Dictionary) -> void:
	var pid := int(player.get("id", 0))
	var seller_id := int(player.get("club_id", 0))
	if moved.has(pid) or seller_id < 1 or buyers.has(seller_id) or protected.has(seller_id) \
		or not market.is_buyable(player, int(session.season_number)):
		return
	var deal: Dictionary = market._pick_buyer_for_player(session, clubs, player, seller_id, buyers, rng, buyer_cache)
	if not deal.is_empty() and market._execute_club_sale(session, clubs, player, seller_id, deal, rng):
		result["bought"] += 1
		moved[pid] = true
		buyers.erase(int(deal.get("club_id", 0)))
