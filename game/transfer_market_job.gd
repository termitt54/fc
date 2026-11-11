extends RefCounted
const TargetSort := preload("res://game/target_sort_work.gd")
const Planner := preload("res://game/transfer_planner.gd")
const OfferRound := preload("res://game/agent_offer_round.gd")
## Resumable market orchestration. Each step handles one club/player/signing;
## all scoring and deal validation remain in TransferMarket.
var market: Script
var session: Node
var rng: RandomNumberGenerator
var clubs: Dictionary
var phase := -1
var cursor := 0
var order: Array = []
var targets: Array = []
var moved := {}
var protected := {}
var squad_cache := {}
var buyer_cache := {}
var buyers := {}
var agent_index := {}
var free_groups := {}
var world_top_reputation := 0
var progressed := false
var tried := 0
var quota := 0
var paid_budget := 0
var sales_budget := 0
var sales_completed := 0
var sales_preparation := -1
var club_ids: Array = []
var sort_work: RefCounted = null
var phase_started: int
var planner: RefCounted
var offer_round: RefCounted
var profile := {}
var result := {"repaired": 0, "signed": 0, "bought": 0, "listed": 0, "unsold": 0, "upgrades": 0, "bids": 0}

func _init(lib: Script, owner: Node, random: RandomNumberGenerator) -> void:
	market = lib
	session = owner
	rng = random
	clubs = session._collect_session_clubs()
	world_top_reputation = PlayerOffer.world_top_reputation(clubs)
	free_groups = market._free_position_groups(session.free_agents)
	order = clubs.keys()
	club_ids = order.duplicate()
	phase_started = Time.get_ticks_usec()

func _next(key: String) -> void:
	profile[key] = float(Time.get_ticks_usec() - phase_started) / 1000.0
	phase += 1
	cursor = 0
	phase_started = Time.get_ticks_usec()

func label() -> String:
	if phase < 0:
		return "Восстановление составов"
	if phase == 1 and sales_preparation >= 0:
		return "Подготовка трансферов"
	return ["Списки на продажу", "Усиление составов", "Трансферы между клубами",
		"Освобождение игроков", "Подписание игроков", "Подписание игроков", "Рынок завершён"][mini(phase, 6)]

func step() -> bool:
	if clubs.is_empty() or not session.is_market_day(session.season_day):
		return true
	match phase:
		-1:
			if cursor < order.size():
				result["repaired"] += market._repair_full_squads(session, clubs, rng, int(order[cursor]), free_groups)
				cursor += 1
			else:
				_next("repair_ms")
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
				free_groups = market._free_position_groups(session.free_agents)
				quota = maxi(1, int(ceili(float(clubs.size()) / 2.0)))
				paid_budget = market.paid_allowance(session, clubs)
				planner=Planner.new(market,session,clubs,rng)
		1:
			if sales_preparation >= 0:
				if sales_preparation < club_ids.size():
					var id: int = int(club_ids[sales_preparation])
					if session.get_club_players(id).size() < market.SQUAD_SIZE:
						buyers[id] = true
						buyer_cache[id] = market._buyer_info(session, id, clubs[id], session.get_club_players(id), world_top_reputation)
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
					sales_budget = market.paid_allowance(session, clubs)
					cursor = 0
					moved = {}
			elif not planner.step():
				return false
			else:
				result["bought"]+=int(planner.result.bought)
				result["upgrades"]+=int(planner.result.upgrades)
				result["bids"]+=int(planner.result.bids)
				result["core_upgrades"]=int(planner.result.core_upgrades)
				result["succession"]=int(planner.result.succession)
				protected=planner.protected
				profile["planner"]=planner.metrics
				planner=null
				profile["upgrade_wave_ms"] = float(Time.get_ticks_usec() - phase_started) / 1000.0
				phase_started = Time.get_ticks_usec()
				sales_preparation = 0
		2:
			if cursor < targets.size() and sales_completed < sales_budget:
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
				agent_index = market._build_agent_index(session.free_agents, world_top_reputation)
		4, 5:
			if offer_round==null:offer_round=OfferRound.new(market,session,clubs,rng,agent_index,phase==5)
			if not offer_round.step():return false
			var arrivals := int(offer_round.signed)
			result["signed"]+=arrivals
			offer_round=null
			if arrivals>0:return false
			market._compact_agents(session,agent_index)
			if phase==4 and session.season_day==session.MARKET_LAST_DAY:
				phase=5;agent_index=market._build_agent_index(session.free_agents,world_top_reputation)
			else:
				phase=6;cursor=0
				profile["free_agent_fill_ms"]=float(Time.get_ticks_usec()-phase_started)/1000.0
				result["profile"]=profile

		6:
			if session.season_day == session.MARKET_LAST_DAY and cursor < order.size():
				market._promote_internal_cover(session,int(order[cursor]))
				cursor += 1
			else:
				if session.season_day==session.MARKET_LAST_DAY:session.market_planner_cache.clear()
				return true
	return false

func _sale(player: Dictionary) -> void:
	var pid := int(player.get("id", 0))
	var seller_id := int(player.get("club_id", 0))
	if moved.has(pid) or seller_id < 1 \
		or not market.is_buyable(player, int(session.season_number)):
		return
	var deal: Dictionary = market._pick_buyer_for_player(session, clubs, player, seller_id, buyers, rng, buyer_cache)
	if not deal.is_empty() and market._execute_club_sale(session, clubs, player, seller_id, deal, rng):
		result["bought"] += 1
		sales_completed += 1
		moved[pid] = true
		var buyer_id := int(deal.get("club_id", 0))
		buyer_cache.erase(buyer_id)
		buyer_cache.erase(seller_id)
		if session.get_club_players(buyer_id).size() >= market.SQUAD_SIZE:
			buyers.erase(buyer_id)
