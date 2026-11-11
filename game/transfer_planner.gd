extends RefCounted
## One shared, bounded market book. No work is performed outside market days.
const VERSION := 1
const MAX_PURCHASES := 2
const ROUNDS_PER_DAY := 2
var market: Script
var session: Node
var clubs: Dictionary
var rng: RandomNumberGenerator
var ids: Array
var cursor := 0
var phase := 0
var round_number := 0
var pool := {}
var plans := {}
var books := {}
var proposals: Array = []
var settled := {}
var moved := {}
var protected := {}
var result := {"bought":0,"upgrades":0,"bids":0,"core_upgrades":0,"succession":0}
var role_cache := {}
var paid_budget := 0
var free_cursor := 0
var world_top := 0
var reserves := {}
var metrics := {"index_ms":0.0,"search_ms":0.0,"settle_ms":0.0}
var rows_by_id := {}
var shortlist_cache: Dictionary
var daily_attempts := {}
var native_indexes := {}

func _init(lib: Script, owner: Node, identities: Dictionary, random: RandomNumberGenerator) -> void:
	market=lib;session=owner;clubs=identities;rng=random
	ids=clubs.keys();ids.sort()
	paid_budget=market.paid_allowance(session,clubs)
	world_top=PlayerOffer.world_top_reputation(clubs)
	if int(session.market_planner_cache.get("season",0))!=int(session.season_number):
		session.market_planner_cache={"season":session.season_number,"shortlists":{},"qualities":{},"plans":{}}
	shortlist_cache=session.market_planner_cache.shortlists
	role_cache=session.market_planner_cache.qualities
	for pos in PlayerTypes.POSITIONS:pool[pos]=[]

func quality(player: Dictionary) -> float:
	var id := int(player.id)
	if not role_cache.has(id):role_cache[id]=LineupSelector.role_value(MatchRatings.of(player),PlayerTypes.normalize_position(str(player.position)),"attacking")
	return float(role_cache[id])

func state(id: int) -> Dictionary:
	var value: Dictionary=clubs[id].get("transfer_plan",{})
	if int(value.get("version",0))!=VERSION or int(value.get("season",0))!=int(session.season_number):
		value={"version":VERSION,"season":session.season_number,"purchases":0,"attempted":[],"core_upgrades":0}
		clubs[id]["transfer_plan"]=value
	return value

func needs(id: int) -> Array:
	var squad: Array=session.get_club_players(id)
	if squad.size()!=market.SQUAD_SIZE or int(state(id).purchases)>=MAX_PURCHASES:return []
	var positions := {}
	for player in squad:
		var pos := PlayerTypes.normalize_position(str(player.position))
		if not positions.has(pos):positions[pos]=[]
		positions[pos].append(player)
	var result_needs := []
	for pos in positions:
		var peers: Array=positions[pos]
		peers.sort_custom(func(a,b):
			if quality(a)!=quality(b):return quality(a)>quality(b)
			if int(a.current_ability)!=int(b.current_ability):return int(a.current_ability)>int(b.current_ability)
			return int(a.id)<int(b.id))
		var n := YouthGraduation.starter_count("3-2-2",pos)
		if peers.size()<n:continue
		var weakest: Dictionary=peers[n-1]
		var outgoing := {}
		for i in range(peers.size()-1,-1,-1):
			if not market.is_transfer_locked(peers[i],session.season_number):outgoing=peers[i];break
		if outgoing.is_empty():continue
		var succession := int(weakest.age)>=31
		var limit: int = market.foreign_limit_for_club(session,id)
		var remaining: int = market.foreign_count(squad,clubs[id])-int(market.is_foreigner(outgoing,clubs[id]))
		result_needs.append({"position":pos,"baseline":quality(weakest),"minimum":maxf(quality(weakest),quality(outgoing))+2.0,
			"outgoing":outgoing,"core_id":int(weakest.id),"ca":int(weakest.current_ability),"age":int(weakest.age),"succession":succession,
			"priority":100.0-quality(weakest)+(8.0 if succession else 0.0)+(4.0 if int(weakest.get("contract_years",3))<=1 else 0.0),
			"allow_foreign":limit<0 or remaining<limit,"termination":market._termination_cost(session,outgoing)})
	result_needs.sort_custom(func(a,b):return float(a.priority)>float(b.priority) if a.priority!=b.priority else str(a.position)<str(b.position))
	return result_needs

func index_player(player: Dictionary, owner: int) -> void:
	var pos := PlayerTypes.normalize_position(str(player.position))
	if not pool.has(pos):return
	pool[pos].append({"id":int(player.id),"owner":owner,"nation":int(player.get("nationality_country_id",0)),
		"quality":quality(player),"ca":int(player.current_ability),"pa":int(player.get("potential_ability",player.current_ability)),
		"age":int(player.age),"fee":market._upgrade_fee(player) if owner>0 else 0,"player":player})
	rows_by_id[int(player.id)]=pool[pos].back()

static func candidate_noise(id: int,seed_value: int) -> float:
	return float((id*1103515245+seed_value*12345)%2147483647)/2147483647.0*2.0-1.0

static func shortlist_reference(candidates: Array, need: Dictionary, buyer: int, nation: int, cap: int, excluded: Array, skill: int, random: RandomNumberGenerator, limit: int) -> Array:
	var ranked := []
	for i in candidates.size():
		var row: Dictionary=candidates[i]
		if int(row.owner)==buyer or int(row.id) in excluded or int(row.fee)>cap:continue
		if not bool(need.allow_foreign) and int(row.nation)>0 and nation>0 and int(row.nation)!=nation:continue
		var successor := bool(need.succession) and int(row.age)<=26 and float(row.quality)>=maxf(float(need.baseline)-1.0,float(need.get("out_quality",0))+2.0) and int(row.pa)>=int(need.ca)+2
		if float(row.quality)<float(need.minimum) and not successor:continue
		var score := (float(row.quality)-float(need.baseline))*8.0+maxf(0,float(row.pa)-float(need.ca))*0.12-float(row.fee)/maxf(1,cap)*3.0
		if successor:score+=3.0
		score+=candidate_noise(int(row.id),int(need.get("noise_seed",0)))*float(20-skill)*0.4
		ranked.append({"index":i,"score":score,"id":row.id})
	ranked_sort(ranked)
	var result_indices := []
	for row in ranked.slice(0,limit):result_indices.append(int(row.index))
	return result_indices

static func ranked_sort(rows: Array) -> void:
	rows.sort_custom(func(a,b):return float(a.score)>float(b.score) if a.score!=b.score else int(a.id)<int(b.id))

func propose(id: int) -> void:
	if int(daily_attempts.get(id,0))>=2:return
	if int(session.get_club_budget(id))<=0:return
	var status := state(id)
	if int(status.purchases)>=MAX_PURCHASES:return
	if not plans.has(id):
		var signature := []
		for player in session.get_club_players(id):signature.append(int(player.id))
		var plan_key := str(id)+":"+str(signature.hash())
		if not session.market_planner_cache.plans.has(plan_key):session.market_planner_cache.plans[plan_key]=needs(id)
		plans[id]=session.market_planner_cache.plans[plan_key]
	var coach: Dictionary=session.get_club_coach(id)
	var squad: Array=session.get_club_players(id)
	for need in plans[id]:
		var cap := mini(ClubFinance.max_single_fee(session.get_club_budget(id)),session.get_club_budget(id)-int(need.termination))
		if cap<=0:continue
		need["out_quality"]=quality(need.outgoing)
		need["noise_seed"]=absi((str(session.season_number)+":"+str(id)+":"+str(need.position)).hash())
		var candidates: Array=pool[need.position]
		var native: Variant=NativeSimulation.core(false)
		if native_indexes.has(need.position):need["_native_index"]=native_indexes[need.position]
		var indices: Array
		var key := "%d:%s:%d:%.6f:%d" % [id,need.position,int(need.outgoing.id),float(need.minimum),int(cap/100000)]
		if not shortlist_cache.has(key):
			if native!=null and native.has_method("planner_shortlist"):
				indices=native.planner_shortlist(candidates,need,id,int(clubs[id].get("country_id",0)),cap,[],CoachTypes.transfers_of(coach),rng,32)
			else:indices=shortlist_reference(candidates,need,id,int(clubs[id].get("country_id",0)),cap,[],CoachTypes.transfers_of(coach),rng,32)
			var target_ids := []
			for index in indices:target_ids.append(int(candidates[index].id))
			shortlist_cache[key]=target_ids
		for target_id in shortlist_cache[key]:
			if not rows_by_id.has(int(target_id)) or int(target_id) in status.attempted:continue
			var row: Dictionary=rows_by_id[int(target_id)]
			var player: Dictionary=row.player
			var seller := int(player.get("club_id",0))
			if moved.has(int(row.id)) or seller!=int(row.owner):continue
			if seller>0 and result.bought>=paid_budget:continue
			if not market._foreign_ok_after_swap(squad,clubs[id],need.outgoing,player,market.foreign_limit_for_club(session,id)):continue
			var fee := int(row.fee)
			var wage := PlayerMarket.wage_for_move(player,clubs[id],seller==0)
			if fee+int(need.termination)+wage>session.get_club_budget(id):continue
			var context: Dictionary=market._offer_context(squad,0 if seller==0 else int(round(PlayerOffer.Attraction.value(clubs[seller]))),world_top)
			context.merge({"offer_wage":wage,"role":"first_team" if float(row.quality)>=float(need.baseline)+2.0 else "rotation","free_agent":seller==0},true)
			var willingness := PlayerOffer.evaluate(player,clubs[id],coach,context)
			result.bids+=1
			daily_attempts[id]=int(daily_attempts.get(id,0))+1
			status.attempted.append(int(row.id))
			if not bool(willingness.accepted):
				market._log_bid(session,id,clubs[id],clubs.get(seller,{}),player,"игрок отказал")
				if int(daily_attempts[id])>=2:return
				continue
			if seller>0 and not market._seller_accepts_upgrade(player,clubs[seller],fee):continue
			var offer := {"buyer":id,"seller":seller,"row":row,"need":need,"score":float(willingness.score)+float(wage)/maxf(1,player.get("wage",wage))*5.0,"tie":rng.randf()}
			if not books.has(int(row.id)):books[int(row.id)]=[]
			books[int(row.id)].append(offer)
			return

func settle(offers: Array) -> void:
	offers.sort_custom(func(a,b):return float(a.score)>float(b.score) if a.score!=b.score else float(a.tie)>float(b.tie))
	for offer in offers:
		var buyer := int(offer.buyer)
		var row: Dictionary=offer.row
		if settled.has(buyer) or moved.has(int(row.id)):continue
		var player: Dictionary=row.player
		if int(player.get("club_id",0))!=int(row.owner):continue
		var outgoing: Dictionary=offer.need.outgoing
		if int(outgoing.get("club_id",0))!=buyer:continue
		if not market._foreign_ok_after_swap(session.get_club_players(buyer),clubs[buyer],outgoing,player,market.foreign_limit_for_club(session,buyer)):continue
		var fee := int(row.fee)
		var cost := int(offer.need.termination)
		if fee+cost+PlayerMarket.wage_for_move(player,clubs[buyer],int(row.owner)==0)>session.get_club_budget(buyer):continue
		var success := false
		if int(row.owner)>0:
			if result.bought>=paid_budget:continue
			success=market._execute_upgrade(session,clubs,buyer,int(row.owner),outgoing,player,rng)
		else:
			# Optional free upgrades must leave sufficient native supply to fill holes.
			if market._native_reserved(player,int(clubs[buyer].get("country_id",0)),reserves,buyer):continue
			if session.free_agents.find(player)<0:continue
			if not market._remove_from_squad(session,buyer,int(outgoing.id)):continue
			session.free_agents.erase(player)
			market._attach_to_club(session,player,buyer,clubs[buyer],rng,0,"свободный агент")
			market._release_to_agents(session,buyer,str(clubs[buyer].name),outgoing)
			success=true
		if not success:continue
		# Update the shared supply/demand book incrementally after a completed deal.
		for supply_row in [[outgoing,1],[player,-1 if int(row.owner)==0 else 0]]:
			var person: Dictionary=supply_row[0]
			var change := int(supply_row[1])
			var nations := [0]
			if int(person.get("nationality_country_id",0))>0:nations.append(int(person.nationality_country_id))
			for nation in nations:
				if reserves.has(nation):
					var supply: Dictionary=reserves[nation].supply
					var pos := PlayerTypes.normalize_position(str(person.position))
					supply[pos]=maxi(0,int(supply.get(pos,0))+change)
		for nation in reserves:
			market._update_native_reserve(session,buyer,reserves[nation])
			if int(row.owner)>0:market._update_native_reserve(session,int(row.owner),reserves[nation])
		session.adjust_club_budget(buyer,-cost)
		var status := state(buyer);status.purchases=int(status.purchases)+1
		status.core_upgrades=int(status.core_upgrades)+int(float(row.quality)>=float(offer.need.baseline)+2.0)
		result.bought+=int(int(row.owner)>0)
		result.upgrades+=1
		result.core_upgrades+=int(float(row.quality)>=float(offer.need.baseline)+2.0)
		result.succession+=int(bool(offer.need.succession))
		settled[buyer]=true;protected[buyer]=true;moved[int(player.id)]=true;moved[int(outgoing.id)]=true
		plans.erase(buyer);plans.erase(int(row.owner))
		return

func step() -> bool:
	if phase==0:
		if cursor<ids.size():
			var start := Time.get_ticks_usec()
			var id := int(ids[cursor]);cursor+=1
			var squad: Array=session.get_club_players(id)
			var info: Dictionary=market._squad_market_info(session,id,squad)
			for player in session.get_club_players(id):
				if market.is_buyable(player,session.season_number) and market._seller_can_spare_info(info,player):index_player(player,id)
			metrics.index_ms+=float(Time.get_ticks_usec()-start)/1000.0
			return false
		phase=1;cursor=0
	if phase==1:
		var start := Time.get_ticks_usec()
		var end := mini(free_cursor+256,session.free_agents.size())
		for i in range(free_cursor,end):index_player(session.free_agents[i],0)
		free_cursor=end
		metrics.index_ms+=float(Time.get_ticks_usec()-start)/1000.0
		if free_cursor<session.free_agents.size():return false
		reserves=market._build_native_reserves(session)
		var native: Variant=NativeSimulation.core(false)
		if native!=null and native.has_method("planner_index"):
			for pos in pool:native_indexes[pos]=native.planner_index(pool[pos])
		phase=2
	if phase==2:
		if cursor<ids.size():
			var start := Time.get_ticks_usec()
			propose(int(ids[cursor]));cursor+=1
			metrics.search_ms+=float(Time.get_ticks_usec()-start)/1000.0
			return false
		var keys: Array=books.keys();keys.sort()
		for id in keys:proposals.append(books[id])
		phase=3;cursor=0
	if phase==3:
		if cursor<proposals.size():
			var start := Time.get_ticks_usec()
			settle(proposals[cursor]);cursor+=1
			metrics.settle_ms+=float(Time.get_ticks_usec()-start)/1000.0
			return false
		round_number+=1
		if round_number<ROUNDS_PER_DAY:
			phase=2;cursor=0;books={};proposals=[];settled={}
			return false
		return true
	return false
