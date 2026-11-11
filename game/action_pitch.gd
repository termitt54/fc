class_name ActionPitch
extends RefCounted
## Reference spatial possession model. No CA, PA, reputation or team-strength inputs.
const Rules := preload("res://game/action_rules.gd")
const FINISH:=0
const PASS:=1
const TECH:=2
const DRIBBLE:=3
const DEFEND:=4
const PACE:=5
const STAMINA:=6
const STRENGTH:=7
const RECOVERY:=8
const DELIVERY:=9
const PENALTY:=10
const REFLEX:=11
const HANDS:=12
const POSITION:=13
const EXITS:=14
const AIR:=15
const STAT_NAMES := ["passes","completed_passes","receipts","miscontrols","dribbles","successful_dribbles","tackles","interceptions","blocks","crosses","completed_crosses","aerial_wins","catches","parries"]
var teams: Array
var actors: Array = []
var rng: RandomNumberGenerator
var ctx: Dictionary
var engine: Script
var owner := -1
var trace := false
var second_assist := 0
var length := Rules.PITCH_LENGTH
var width := Rules.PITCH_WIDTH
var goal_width := Rules.GOAL_WIDTH
var goal_height := Rules.GOAL_HEIGHT

static func play(home: Dictionary, away: Dictionary, context: Dictionary, start: int, extra: bool) -> void:
	var pitch := ActionPitch.new()
	pitch.teams = [home,away]
	pitch.ctx = context
	pitch.rng = context.rng
	pitch.trace = bool(context.get("trace_actions",false))
	pitch.engine = load("res://game/match_engine.gd")
	pitch.build_actors(extra)
	pitch.run_phase(start)

func knob(key: String, fallback: float) -> float:
	return float(ctx.knobs.get(key,fallback))
func inc(d: Dictionary, key: String, amount: int = 1) -> void:
	d[key] = int(d.get(key,0))+amount
func distance(x: float,y: float,xx: float,yy: float) -> float:
	return sqrt((x-xx)*(x-xx)+(y-yy)*(y-yy))
func skill(a: Dictionary,k: int) -> float:
	return float(a.skill[k])*(0.55+0.45*float(a.fresh))
func progress(a: Dictionary) -> float:
	return float(a.x) if a.side==0 else length-float(a.x)
func goal_x(side: int) -> float:
	return length if side==0 else 0.0
func nearest(side: int,x: float,y: float,keeper_only: bool = false,snapshot: Array = []) -> int:
	var pool: Array = actors if snapshot.is_empty() else snapshot
	var best := -1
	var value := 1e100
	for j in pool.size():
		var a: Dictionary = pool[j]
		if not a.active or a.side!=side or (keeper_only and a.slot!="GK"): continue
		var dx: float = float(a.x)-x
		var dy: float = float(a.y)-y
		var d := dx*dx+dy*dy
		if d<value:
			value=d
			best=j
	return best
func event(type: String,a: Dictionary,second: float,x: float,y: float,other: int = 0,success: bool = true) -> void:
	if not trace: return
	var e: Dictionary = engine._log(ctx,int(second/60.0),type,teams[a.side],a.entry)
	e.second=snappedf(second,0.01)
	e.x=snappedf(x,0.01)
	e.y=snappedf(y,0.01)
	e.other_player_id=other
	e.success=success
func build_actors(extra: bool) -> void:
	var groups := ["technical","technical","technical","technical","technical","physical","physical","physical","physical","set_pieces","set_pieces","goalkeeping","goalkeeping","goalkeeping","goalkeeping","goalkeeping"]
	var keys := ["finishing","passing","technique","dribbling","defending","pace","stamina","strength","recovery","delivery","penalties","reflexes","handling","positioning","exits","aerial_reach"]
	for side in 2:
		var field: Array = teams[side].on_field
		var counts := {}
		var seen := {}
		var emergency := not field.is_empty()
		for unit in field:
			if unit.slot=="GK": emergency=false
		for j in field.size():
			var field_slot: String="GK" if emergency and j==0 else str(field[j].slot)
			counts[field_slot]=int(counts.get(field_slot,0))+1
		for j in field.size():
			var u: Dictionary = field[j]
			u.phase_fouls=0
			var p: Dictionary = u.player
			var slot: String = "GK" if emergency and j==0 else str(u.slot)
			var r: Dictionary = u.ratings
			var skills: Array = []
			for k in 16:
				skills.append(clampf(float(p.get("attributes",{}).get(groups[k],{}).get(keys[k],1 if k>=REFLEX and not bool(r.get("is_gk",false)) else 10)),1.0,20.0))
			var depth := 0.05 if slot=="GK" else 0.28 if slot=="CB" else 0.48 if slot=="CM" else 0.72
			var count: int = counts[slot]
			var number := int(seen.get(slot,0))
			seen[slot]=number+1
			var lane := 0.5 if count==1 else 0.20+0.60*number/float(count-1)
			var ax := depth*length if side==0 else (1-depth)*length
			var ay := lane*width
			actors.append({"unit":u,"entry":u.entry,"id":int(p.id),"side":side,"slot":slot,"skill":skills,
				"ax":ax,"ay":ay,"x":float(u.get("pitch_x",ax)),"y":float(u.get("pitch_y",ay)),
				"fresh":float(u.fresh),"drain":float(u.drain)*(1.35 if extra else 1.0),"metres":0.0,"delay":0.0,
				"active":true,"mark":-1,"individual":bool(r.get("individualist",false)),"team_player":bool(r.get("team_player",false)),
				"hot":bool(r.get("hot_head",false)),"ice":bool(r.get("ice_cold",false)),"stats":[0,0,0,0,0,0,0,0,0,0,0,0,0,0]})
	# Keep a distinct assignment for every defender until the next tactical review.
	for side in 2:
		var markers: Array=[]
		var targets: Array=[]
		for j in actors.size():
			if actors[j].slot=="GK": continue
			if actors[j].side==side: markers.append(j)
			else: targets.append(j)
		var weights: Array=[]
		for marker in markers:
			var row := PackedFloat64Array()
			row.resize(maxi(markers.size(),targets.size()))
			for j in targets.size():
				var m: Dictionary=actors[marker]
				var target: Dictionary=actors[targets[j]]
				var role := 12.0 if m.slot=="CB" and target.slot=="ST" else 0.0
				if m.slot==target.slot: role+=5
				row[j]=100-distance(m.ax,m.ay,target.x,target.y)+role
			weights.append(row)
		var assignments: PackedInt32Array=load("res://game/lineup_assignment.gd").solve(weights)
		for j in markers.size():
			if assignments[j]>=0 and assignments[j]<targets.size(): actors[markers[j]].mark=targets[assignments[j]]

func move(dt: float,held: int = -1) -> void:
	if owner<0: return
	var before: Array = []
	for actor in actors: before.append(actor.duplicate())
	var side: int = actors[owner].side
	var bx: float = actors[owner].x
	var by: float = actors[owner].y
	var pressing_actor := nearest(1-side,bx,by,false,before)
	for j in actors.size():
		var u: Dictionary = actors[j]
		if not u.active: continue
		var tx: float = u.ax
		var ty: float = u.ay
		var style: String = teams[u.side].style
		var tactical := knob("tactics_influence",1)
		var coach := clampf(10+(int(teams[u.side].get("tactics",10))-10)*float(teams[u.side].get("coach_influence",1)),1,20)
		if u.slot=="GK":
			var own_goal := goal_x(1-int(u.side))
			var ball_distance := maxf(absf(bx-own_goal),0.5)
			tx=own_goal+(1.0 if u.side==0 else -1.0)*length*0.035
			if u.side!=side and ball_distance<12: tx=own_goal+(1.0 if u.side==0 else -1.0)*minf(ball_distance*0.50,1.0+skill(u,EXITS)*0.12)
			ty=width/2+(by-width/2)*absf(tx-own_goal)/ball_distance
			ty+=(21.0-float(u.skill[POSITION]))*0.04*(1.0 if int(u.id)%2==0 else -1.0)
		elif u.side==side:
			var advance := (bx if u.side==0 else length-bx)-length*0.45
			var penetration := clampf(advance/(length*0.40),0.0,1.0)
			var attacking := style=="attacking"
			var depth := 0.72+0.17*penetration
			var inward := 0.50
			if u.slot=="CM":
				depth=Rules.MIDFIELD_ATTACK_DEPTH_BASE+Rules.MIDFIELD_ATTACK_DEPTH_SPAN*penetration
				inward=0.65
			elif u.slot=="CB":
				var runner: bool = (u.ay<width*0.30 and by<width/2) or (u.ay>width*0.70 and by>=width/2)
				depth=0.28+(Rules.DEFENDER_ATTACK_RUN_SPAN*pow(penetration,0.70) if runner else 0.12*penetration)
				inward=0.80 if runner else 0.0
			depth+=(0.01 if attacking else -0.025)*penetration*tactical
			tx=length*(depth if u.side==0 else 1-depth)
			ty+=(width/2-ty)*inward*penetration
		else:
			if j==pressing_actor:
				tx=bx
				ty=by
			else:
				var mark: int = u.mark
				if mark>=0:
					var defending := skill(u,DEFEND)
					tx=float(before[mark].x)+(-1.0 if u.side==0 else 1.0)*(1.55+0.04*(10-defending)+0.012*(10-coach))
					ty=float(before[mark].y)+((21-defending)*0.035+(10-coach)*0.008)*(1.0 if int(u.id)%2==0 else -1.0)
		tx=clampf(tx,1,length-1)
		ty=clampf(ty,1,width-1)
		var d := distance(u.x,u.y,tx,ty)
		var moved := 0.0
		if j!=owner and j!=held and u.delay<=0 and d>0.0001:
			var running_effort := clampf(0.80+0.005*(float(teams[u.side].get("motivation",10))-10)*float(teams[u.side].get("coach_influence",1)),0.65,0.90)
			moved=minf(d,Rules.running_speed(u.skill[PACE],u.fresh)*dt*running_effort)
			u.x+=(tx-float(u.x))*moved/d
			u.y+=(ty-float(u.y))*moved/d
			u.metres+=moved
		u.delay=maxf(0.0,float(u.delay)-dt)
		var effort := 0.55+(moved/maxf(dt,0.001))/maxf(Rules.running_speed(u.skill[PACE],u.fresh),1.0)
		u.fresh=maxf(0.25,float(u.fresh)-float(u.drain)*(dt/300.0)*effort)
func restart(side: int,kickoff: bool = false) -> void:
	if kickoff:
		for u in actors:
			u.x=u.ax
			u.y=u.ay
		owner=nearest(side,length/2,width/2)
		if owner>=0:
			actors[owner].x=length/2
			actors[owner].y=width/2
	else: owner=nearest(side,goal_x(1-side),width/2,true)
	if owner<0: owner=nearest(side,length/2,width/2)
func shoot(assist: int,second: float,penalty: bool = false) -> bool:
	var u: Dictionary = actors[owner]
	var side: int = u.side
	var team: Dictionary = teams[side]
	var opposition: Dictionary = teams[1-side]
	var gx := goal_x(side)
	var d := distance(u.x,u.y,gx,width/2)
	var ability := skill(u,PENALTY if penalty else (DELIVERY if bool(u.unit.get("free_kick",false)) else FINISH))
	u.unit.free_kick=false
	if penalty and u.ice: ability=minf(20.0,ability+1.0)
	if penalty:
		var goalie := nearest(1-side,gx,width/2,true)
		var outcome := Rules.penalty_trial(ability,skill(actors[goalie],REFLEX) if goalie>=0 else 1.0,skill(actors[goalie],POSITION) if goalie>=0 else 1.0,rng,knob("penalty_conversion_base",MatchTypes.PENALTY_CONVERSION_BASE)/MatchTypes.PENALTY_CONVERSION_BASE,goalie>=0)
		inc(team,"shots")
		inc(u.entry,"shots")
		if outcome>0:
			inc(team,"on_target")
			inc(u.entry,"on_target")
		if outcome==2:
			engine._score_goal(team,opposition,u.unit,{},ctx,int(second/60),"PENALTY_GOAL")
			ctx.events[-1].second=snappedf(second,0.01)
			inc(u.entry,"pen_scored")
			restart(1-side,true)
			return true
		inc(u.entry,"pen_missed")
		if outcome==1 and goalie>=0:
			inc(actors[goalie].entry,"saves")
			inc(actors[goalie].entry,"pen_saved")
		restart(1-side)
		return false
	var aim := (-1.0 if rng.randf()<0.5 else 1.0)*(1.6+0.03*ability)*goal_width/5.0
	var sigma := Rules.shot_sigma(ability,d,penalty)
	sigma*=sqrt(MatchTypes.SHOT_ON_TARGET_BASE/maxf(knob("shot_on_target_base",MatchTypes.SHOT_ON_TARGET_BASE),0.1))
	var target := width/2+aim+rng.randfn(0,sigma)
	var height := (0.25+rng.randf()*1.5)+rng.randfn(0,sigma*0.15)
	inc(team,"shots")
	inc(u.entry,"shots")
	event("SHOT",u,second,u.x,u.y,0,absf(target-width/2)<=goal_width/2 and height>0 and height<goal_height)
	if absf(target-width/2)>goal_width/2 or height<0 or height>goal_height:
		if penalty: inc(u.entry,"pen_missed")
		restart(1-side)
		return false
	if not penalty:
		for j in actors.size():
			var defender: Dictionary = actors[j]
			if not defender.active or defender.side==side or defender.slot=="GK": continue
			var vx: float = gx-float(u.x)
			var vy: float = target-float(u.y)
			var norm := vx*vx+vy*vy
			var f := ((float(defender.x)-float(u.x))*vx+(float(defender.y)-float(u.y))*vy)/norm if norm>0 else 0.0
			if f<0.05 or f>0.90: continue
			var lateral := distance(defender.x,defender.y,float(u.x)+f*vx,float(u.y)+f*vy)
			var flight := d*f/(14+0.4*ability)
			var reach := 0.30+0.035*skill(defender,DEFEND)+Rules.running_speed(defender.skill[PACE],defender.fresh)*maxf(0.0,flight-(0.9-0.035*skill(defender,DEFEND)))
			if lateral<reach:
				defender.stats[8]+=1
				owner=j
				event("BLOCK",defender,second,defender.x,defender.y,u.id)
				return false
	inc(team,"on_target")
	inc(u.entry,"on_target")
	var keeper := nearest(1-side,gx,width/2,true)
	if keeper>=0:
		var g: Dictionary = actors[keeper]
		var plane := maxf(0.5,absf(float(g.x)-float(u.x)))
		var speed := (14+0.4*ability)*sqrt(knob("shot_conversion_base",MatchTypes.SHOT_CONVERSION_BASE)/MatchTypes.SHOT_CONVERSION_BASE)
		var flight := plane/maxf(speed,1.0)
		var available := maxf(0.0,flight+(0.0 if penalty else 0.08)-Rules.reaction_delay(skill(g,REFLEX)))
		var at_keeper: float = float(u.y)+(target-float(u.y))*clampf(plane/maxf(absf(gx-float(u.x)),0.5),0,1)
		var reach := 0.85+4.8*available
		var gy: float = g.y
		if penalty:
			gy=width/2+(-1.2 if rng.randf()<0.5 else 1.2)
			reach=0.45+4.0*available
		if absf(at_keeper-gy)<=reach and height<=(1.2 if penalty else 1.35)+1.8*available:
			inc(g.entry,"saves")
			event("SAVE",g,second,g.x,g.y,u.id)
			if penalty:
				inc(u.entry,"pen_missed")
				inc(g.entry,"pen_saved")
			if rng.randf()<clampf(0.25+0.035*skill(g,HANDS),0.25,0.95) or penalty:
				g.stats[12]+=1
				owner=keeper
			else:
				g.stats[13]+=1
				var rx := clampf(gx+(-3.0 if side==0 else 3.0),1,length-1)
				var ry := clampf(target+rng.randf_range(-2,2),1,width-1)
				var near := -1
				var time := 1e100
				for j in actors.size():
					var a: Dictionary = actors[j]
					if not a.active: continue
					var t := distance(a.x,a.y,rx,ry)/Rules.running_speed(a.skill[PACE],a.fresh)
					if t<time:
						time=t
						near=j
				owner=near
			return false
	var helper := {}
	var helper2: Dictionary = {}
	for a in actors:
		if a.id==assist and a.side==side and a.id!=u.id: helper=a.unit
		if a.id==second_assist and a.side==side and a.id!=u.id and a.id!=assist: helper2=a.unit
	engine._score_goal(team,opposition,u.unit,helper,ctx,int(second/60),"PENALTY_GOAL" if penalty else "GOAL",helper2)
	ctx.events[-1].second=snappedf(second,0.01)
	if penalty: inc(u.entry,"pen_scored")
	restart(1-side,true)
	return true
func run_phase(start: int) -> void:
	if actors.is_empty(): return
	var ball: Dictionary = teams[0].get("pitch_ball",{})
	var assist := int(ball.get("assist",0))
	second_assist=int(ball.get("second_assist",0))
	for j in actors.size():
		if actors[j].id==int(ball.get("owner",0)) and int(actors[j].side)==int(ball.get("side",0)): owner=j
	if start in [0,25,50,60]:
		restart(1 if start in [25,60] else 0,true)
		assist=0
		second_assist=0
	elif owner<0: restart(0 if start%10==0 else 1,true)
	var elapsed := 0.0
	var home_time := 0.0
	var away_time := 0.0
	while elapsed<300.0 and owner>=0:
		var current := owner
		var u: Dictionary = actors[current]
		var side: int = u.side
		var team: Dictionary = teams[side]
		var second := start*60.0+elapsed
		var decision := clampf(1.4/maxf(float(team.profile.get("tempo",1)),0.4)*MatchTypes.CHANCES_PER_PHASE/maxf(knob("chances_per_phase",MatchTypes.CHANCES_PER_PHASE),0.1),0.4,8.0)
		move(decision)
		elapsed+=decision
		if side==0: home_time+=decision
		else: away_time+=decision
		var defender := nearest(1-side,u.x,u.y)
		var close := 1e6 if defender<0 else distance(u.x,u.y,actors[defender].x,actors[defender].y)
		var d := distance(u.x,u.y,goal_x(side),width/2)
		var in_box := d<9.0 and absf(float(u.y)-width/2)<8.0
		var contact_caution := 0.40 if in_box else 1.0
		if defender>=0 and u.slot!="GK" and close<1.5 and rng.randf()<contact_caution*(0.004+0.002*(21-skill(actors[defender],DEFEND)))*(1.6 if actors[defender].hot else 1.0):
			var offender: Dictionary = actors[defender]
			inc(teams[offender.side],"fouls")
			inc(offender.unit,"phase_fouls")
			inc(offender.entry,"fouls")
			event("FOUL",offender,second,offender.x,offender.y,u.id)
			if in_box and rng.randf()<minf(1.0,knob("penalty_per_phase",MatchTypes.PENALTY_PER_PHASE)/maxf(MatchTypes.PENALTY_PER_PHASE,0.001)):
				var taker := current
				for j in actors.size():
					if actors[j].active and actors[j].side==side and skill(actors[j],PENALTY)>skill(actors[taker],PENALTY): taker=j
				owner=taker
				actors[taker].x=goal_x(side)+(-Rules.PENALTY_DISTANCE if side==0 else Rules.PENALTY_DISTANCE)
				actors[taker].y=width/2
				event("PENALTY",actors[taker],second,actors[taker].x,actors[taker].y)
				shoot(0,second,true)
				assist=0
				second_assist=0
				elapsed+=25
			else:
				u.unit.free_kick=true
				elapsed+=8
			continue
		var shot_preference := maxf(0.05,1+(float(Rules.STYLE_SHOT_PREFERENCE.get(str(team.style),1))-1)*knob("tactics_influence",1))
		# After winning possession, prefer a combination over a rushed distance shot.
		# A clear chance close to goal remains available without an earlier pass.
		var combination := 1.0 if assist>0 or d<3.5 else 0.01
		if (u.slot!="GK" or progress(u)>length*0.15) and d<length*0.32 and rng.randf()<clampf((0.07+(length*0.32-d)*0.025)*shot_preference*combination*knob("chance_create_base",MatchTypes.CHANCE_CREATE_BASE)/MatchTypes.CHANCE_CREATE_BASE,0.001,0.45):
			if defender>=0 and close<2.2:
				var blocking: Dictionary = actors[defender]
				var defence := skill(blocking,EXITS if blocking.slot=="GK" else DEFEND)
				if rng.randf()>Rules.duel(skill(u,FINISH),defence,knob("duel_skill_influence",1)):
					blocking.stats[6 if blocking.slot=="GK" else 8]+=1
					event("BLOCK",blocking,second,blocking.x,blocking.y,u.id)
					owner=defender
					assist=0
					second_assist=0
					elapsed+=2
					continue
			var scored := shoot(assist,second)
			if scored or owner<0 or actors[owner].side!=side:
				assist=0
				second_assist=0
			elif int(actors[owner].id)!=int(u.id):
				second_assist=assist
				assist=int(u.id)
			elapsed+=32.0 if scored else 12.0
			continue
		if (u.slot!="GK" or progress(u)>length*0.15) and close<1.3 and rng.randf()<0.25:
			var opponent: Dictionary = actors[defender]
			var held := rng.randf()<Rules.duel(skill(u,STRENGTH),skill(opponent,STRENGTH),knob("duel_skill_influence",1))
			if not held:
				opponent.stats[6]+=1
				owner=defender
				assist=0
				second_assist=0
			event("CONTACT",u,second,u.x,u.y,opponent.id,held)
			if not held: continue
		var dribble: bool = (u.slot!="GK" or progress(u)>length*0.15) and close<5.0 and rng.randf()<(0.35+(0.16 if u.individual else 0.0)-(0.09 if u.team_player else 0.0))
		if dribble:
			u.stats[4]+=1
			var opponent: Dictionary = actors[defender]
			var won := rng.randf()<Rules.duel(skill(u,DRIBBLE),skill(opponent,EXITS if opponent.slot=="GK" else DEFEND),knob("duel_skill_influence",1))
			if won:
				u.stats[5]+=1
				var step := Rules.running_speed(u.skill[PACE],u.fresh)*0.65
				u.x=clampf(float(u.x)+(step if side==0 else -step),1,length-1)
				u.metres+=step
				opponent.delay=1.6
			else:
				opponent.stats[6]+=1
				owner=defender
				assist=0
				second_assist=0
			event("DRIBBLE",u,second,u.x,u.y,opponent.id,won)
			move(1.0)
			elapsed+=1.0
			continue
		var target := -1
		var best := -1e100
		var style: String = team.style
		var forward := 0.30 if style=="attacking" else 0.24
		for j in actors.size():
			var a: Dictionary = actors[j]
			if j==owner or not a.active or a.side!=side or a.slot=="GK": continue
			var dist := distance(u.x,u.y,a.x,a.y)
			var marker := nearest(1-side,a.x,a.y)
			var space := 10.0 if marker<0 else distance(a.x,a.y,actors[marker].x,actors[marker].y)
			var score := (progress(a)-progress(u))*forward+minf(space,10.0)*0.7-dist*0.06
			var route_risk := 0.0
			var vx: float = float(actors[j].x)-float(u.x)
			var vy: float = float(actors[j].y)-float(u.y)
			var norm := vx*vx+vy*vy
			for marker_actor in actors:
				if not marker_actor.active or marker_actor.side==side or marker_actor.slot=="GK": continue
				var along := ((float(marker_actor.x)-float(u.x))*vx+(float(marker_actor.y)-float(u.y))*vy)/norm if norm>0 else 0.0
				if along<0.08 or along>0.95: continue
				var lateral := distance(marker_actor.x,marker_actor.y,float(u.x)+along*vx,float(u.y)+along*vy)
				var flight := dist*along/(8+0.35*skill(u,PASS))
				var reach := 0.35+0.04*skill(marker_actor,DEFEND)+Rules.running_speed(marker_actor.skill[PACE],marker_actor.fresh)*maxf(0.0,flight-(0.9-0.035*skill(marker_actor,DEFEND)))
				route_risk+=maxf(0.0,reach+0.5-lateral)
			var knowledge := clampf(10+(int(team.get("tactics",10))-10)*float(team.get("coach_influence",1)),1,20)
			score-=route_risk*(1.5+knowledge*0.10)
			score+=rng.randf_range(-1,1)*(21-knowledge)*0.15
			if score>best:
				best=score
				target=j
		if target<0 or (best<1.5 and close>3.0 and u.slot!="GK"):
			var step := minf(maxf(0.2,close-1.5),Rules.running_speed(u.skill[PACE],u.fresh)*0.75)
			u.x=clampf(float(u.x)+(step if side==0 else -step),1,length-1)
			u.metres+=step
			event("CARRY",u,second,u.x,u.y)
			move(1.0)
			elapsed+=1.0
			continue
		var cross: bool = bool(u.unit.get("free_kick",false))
		u.unit.free_kick=false
		if not cross: cross=u.slot!="GK" and progress(u)>length*0.48 and absf(float(u.y)-width/2)>width*0.20 and rng.randf()<knob("set_piece_share",MatchTypes.SET_PIECE_SHARE)
		u.stats[9 if cross else 0]+=1
		var receive_x: float = goal_x(side)+(-5.0 if side==0 else 5.0) if cross else float(actors[target].x)
		var receive_y: float = clampf(float(actors[target].y),width/2-4,width/2+4) if cross else float(actors[target].y)
		d=distance(u.x,u.y,receive_x,receive_y)
		var ability := skill(u,DELIVERY if cross else PASS)
		var error := (21-ability)*0.055*maxf(0.5,d/10.0)
		var tx: float = receive_x+rng.randfn(0,error)
		var ty: float = receive_y+rng.randfn(0,error)
		var vx: float = tx-float(u.x)
		var vy: float = ty-float(u.y)
		var norm := vx*vx+vy*vy
		var flight := d/(8+0.35*ability)+(0.7 if cross else 0.0)
		var interceptor := -1
		var first := 1e100
		for j in actors.size():
			var a: Dictionary = actors[j]
			if not a.active or a.side==side or (not cross and a.slot=="GK"): continue
			var f := ((float(a.x)-float(u.x))*vx+(float(a.y)-float(u.y))*vy)/norm if norm>0 else 0.0
			if f<0.05 or f>1.08: continue
			var lateral := distance(a.x,a.y,float(u.x)+f*vx,float(u.y)+f*vy)
			var defence := skill(a,AIR if a.slot=="GK" else (STRENGTH if cross else DEFEND))
			var available := maxf(0.0,flight*f-(0.9-0.035*defence))
			var reach := 0.35+0.04*defence+Rules.running_speed(a.skill[PACE],a.fresh)*available
			if cross and a.slot!="GK" and f<0.75: continue
			if cross and a.slot=="GK": reach=minf(reach,2.0+0.15*skill(a,EXITS))
			if lateral<reach and f<first:
				interceptor=j
				first=f
		if cross and interceptor>=0 and distance(actors[target].x,actors[target].y,receive_x,receive_y)<=Rules.running_speed(actors[target].skill[PACE],actors[target].fresh)*flight*0.8+1.2:
			var contest: Dictionary = actors[interceptor]
			if rng.randf()>=Rules.duel(skill(contest,AIR if contest.slot=="GK" else STRENGTH),skill(actors[target],STRENGTH),knob("duel_skill_influence",1)):
				actors[target].stats[11]+=1
				event("AERIAL_DUEL",actors[target],second,actors[target].x,actors[target].y,contest.id)
				interceptor=-1
		if tx<0 or tx>length or ty<0 or ty>width:
			event("OUT",u,second,clampf(tx,0,length),clampf(ty,0,width))
			owner=nearest(1-side,clampf(tx,1,length-1),clampf(ty,1,width-1))
			if owner>=0:
				actors[owner].x=clampf(tx,1,length-1)
				actors[owner].y=clampf(ty,1,width-1)
			assist=0
			second_assist=0
			elapsed+=flight+8
			continue
		move(flight,target)
		elapsed+=flight
		if cross:
			var receiver: Dictionary = actors[target]
			var travel := distance(receiver.x,receiver.y,receive_x,receive_y)
			var run := minf(travel,Rules.running_speed(receiver.skill[PACE],receiver.fresh)*flight*0.8)
			if travel>0.0001:
				receiver.x+=(receive_x-float(receiver.x))*run/travel
				receiver.y+=(receive_y-float(receiver.y))*run/travel
				receiver.metres+=run
		if side==0: home_time+=flight
		else: away_time+=flight
		if interceptor>=0:
			actors[interceptor].stats[11 if cross else 7]+=1
			event("INTERCEPTION",actors[interceptor],second,actors[interceptor].x,actors[interceptor].y,u.id)
			owner=interceptor
			assist=0
			second_assist=0
			continue
		var catch_radius := 0.7+0.06*skill(actors[target],TECH)
		var received := distance(actors[target].x,actors[target].y,tx,ty)<=catch_radius
		if received:
			u.stats[10 if cross else 1]+=1
			actors[target].stats[2]+=1
			owner=target
			second_assist=assist
			assist=u.id
			move(Rules.trap_time(skill(actors[target],TECH)))
			elapsed+=Rules.trap_time(skill(actors[target],TECH))
		else:
			actors[target].stats[3]+=1
			owner=nearest(1-side,tx,ty)
			assist=0
			second_assist=0
		event("CROSS" if cross else "PASS",u,second,tx,ty,actors[target].id,received)
	for a in actors:
		a.unit.pitch_x=a.x
		a.unit.pitch_y=a.y
		a.unit.fresh=a.fresh
		a.entry.final_freshness=int(round(float(a.fresh)*100))
		inc(a.entry,"distance_metres",int(round(a.metres)))
		for k in 14: inc(a.entry,STAT_NAMES[k],a.stats[k])
		a.entry.intensity_minutes=float(a.entry.intensity_minutes)+5*float(teams[a.side].intensity)
	if owner>=0:
		ball.owner=actors[owner].id
		ball.side=actors[owner].side
		ball.assist=assist
		ball.second_assist=second_assist
		teams[0].pitch_ball=ball
	var total := maxf(home_time+away_time,0.001)
	teams[0].possession_sum=float(teams[0].possession_sum)+home_time/total
	teams[1].possession_sum=float(teams[1].possession_sum)+away_time/total

