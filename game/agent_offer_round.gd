extends RefCounted
## Every interested club bids before any free agent chooses his destination.
var market: Script
var session: Node
var clubs: Dictionary
var rng: RandomNumberGenerator
var index: Dictionary
var ids: Array
var cursor := 0
var settling := false
var books := {}
var keys: Array=[]
var signed := 0
var relaxed := false

func _init(lib: Script,owner: Node,identities: Dictionary,random: RandomNumberGenerator,agent_index: Dictionary,last: bool) -> void:
	market=lib;session=owner;clubs=identities;rng=random;index=agent_index;relaxed=last
	ids=clubs.keys();ids.sort()

func step() -> bool:
	if not settling:
		if cursor<ids.size():
			var id := int(ids[cursor]);cursor+=1
			var squad: Array=session.get_club_players(id)
			var target: int=market.SQUAD_SIZE if relaxed else market._day_target(session.season_day,squad.size())
			if squad.size()>=target:return false
			var choice := {"probe":true}
			if market._try_sign(session,rng,id,clubs[id],squad,market.POS_FLEX,relaxed,false,index,choice):
				var i := int(choice.index)
				var player: Dictionary=session.free_agents[i]
				var coach: Dictionary=session.get_club_coach(id)
				var context: Dictionary=market._offer_context(squad,0,int(index.get("world_top_reputation",0)))
				if session.season_number==1 and session.season_day<1:context.squad_ability=-1.0
				var pos := PlayerTypes.normalize_position(str(player.position))
				var peers: Array=[]
				for p in squad:
					if PlayerTypes.normalize_position(str(p.position))==pos:peers.append(PlayerMarket.ability_of(p))
				peers.sort();peers.reverse()
				var n := YouthGraduation.starter_count("3-2-2",pos)
				var first_team := peers.size()<n or PlayerMarket.ability_of(player)>int(peers[n-1])
				var wage := PlayerMarket.wage_for_move(player,clubs[id],true)
				context.merge({"role":"first_team" if first_team else "rotation","offer_wage":wage,"free_agent":true},true)
				var willingness := PlayerOffer.evaluate(player,clubs[id],coach,context)
				if bool(willingness.accepted):
					if not books.has(i):books[i]=[]
					books[i].append({"id":id,"score":float(willingness.score)+float(wage)/maxf(1,player.get("wage",wage))*5.0,"tie":rng.randf()})
			return false
		keys=books.keys();keys.sort();cursor=0;settling=true
	if cursor<keys.size():
		var i := int(keys[cursor]);cursor+=1
		var offers: Array=books[i]
		offers.sort_custom(func(a,b):return float(a.score)>float(b.score) if a.score!=b.score else float(a.tie)>float(b.tie))
		for offer in offers:
			if market._accept_agent(session,rng,int(offer.id),clubs[int(offer.id)],i,index):signed+=1;break
		return false
	return true
