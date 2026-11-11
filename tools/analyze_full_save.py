"""Read-only, branch-aware audit of an exported Godot save."""
import json, collections as C, statistics as S, sqlite3, math, sys, re
from pathlib import Path
F=Path(sys.argv[1]).resolve(); p=json.loads((F/'payload.json').read_text(encoding='utf8'))
def mean(a): return round(S.mean(a),3) if a else None
def dist(a):
 a=sorted(a); return {'n':len(a),'min':a[0],'p10':a[int((len(a)-1)*.1)],'median':S.median(a),'mean':mean(a),'p90':a[int((len(a)-1)*.9)],'max':a[-1]} if a else {'n':0}
def ro(db): return sqlite3.connect(db.as_uri()+'?mode=ro',uri=True)
def counter(a): return dict(C.Counter(a).most_common())
def rows(path):
 with path.open(encoding='utf8') as f:
  for line in f:
   if line.strip(): yield json.loads(line)
world=ro(F/'world.db');world.row_factory=sqlite3.Row
countries={r['id']:dict(r) for r in world.execute('select * from countries')};world.close()
units={int(u['id']):u for u in p['units']};clubunits={i:u for i,u in units.items() if not u.get('national')};clubs={int(i):v for u in clubunits.values() for i,v in u['clubs_by_id'].items()};club_unit={int(i):u for u in clubunits.values() for i in u['clubs_by_id']}
name=lambda i: clubs.get(int(i),{}).get('name',countries.get(int(i)-1000000000,{}).get('name',str(i)))
pools={k:p[k] if k=='free_agents' else [q for v in p[k].values() for q in v] for k in ['players_by_club','reserve_players_by_club','youth_players_by_club','free_agents']};active=sum(pools.values(),[]); byid={int(q['id']):q for q in active}
r={'meta':{k:p.get(k) for k in ['version','saved_at','season_number','season_day','season_total_days','history_head']},'pools':{},'integrity':{},'clubs':[],'countries':[],'competitions':[]}
for k,qs in pools.items(): r['pools'][k]={'count':len(qs),'ca':dist([q['current_ability'] for q in qs]),'pa':dist([q['potential_ability'] for q in qs]),'age':dist([q['age'] for q in qs]),'positions':counter(q['position'] for q in qs),'ca70_plus':sum(q['current_ability']>=70 for q in qs),'pa90_plus':sum(q['potential_ability']>=90 for q in qs),'pa100':sum(q['potential_ability']==100 for q in qs)}
r['integrity']={'duplicate_player_ids':len(active)-len(byid),'ca_above_pa':sum(q['current_ability']>q['potential_ability'] for q in active),'invalid_positions':sum(q['position'] not in ['GK','CB','CM','ST'] for q in active),'bad_owner_links':sum(int(cid)!=int(q.get('club_id',0)) for k in ['players_by_club','reserve_players_by_club','youth_players_by_club'] for cid,sq in p[k].items() for q in sq),'free_with_club':sum(int(q.get('club_id',0))!=0 for q in p['free_agents']),'invalid_skill_values':sum(not 1<=v<=20 for q in active for g in q.get('attributes',{}).values() for v in g.values()),'attributes_missing':sum(not q.get('attributes') for q in active)}
mins={'GK':2,'CB':7,'CM':5,'ST':4};maxs={'GK':3,'CB':8,'CM':6,'ST':5}
for cid,club in clubs.items():
 sq=p['players_by_club'].get(str(cid),[]);counts=C.Counter(q['position'] for q in sq);allq=sum([p[k].get(str(cid),[]) for k in ['players_by_club','reserve_players_by_club','youth_players_by_club']],[]);u=club_unit[cid];b=p['club_budgets'].get(str(cid),0); coach=p['coaches_by_club'].get(str(cid),{});foreign=sum(q['nationality_country_id']!=club['country_id'] for q in sq);limit=u.get('rules',{}).get('foreign_players_limit',-1)
 r['clubs'].append({'id':cid,'name':club['name'],'league':u['name'],'country':countries.get(club['country_id'],{}).get('name'),'reputation':club['reputation'],'budget':b,'wages':sum(q.get('wage',0) for q in allq)+coach.get('wage',0),'cash_to_wage_years':round(b/max(1,sum(q.get('wage',0) for q in allq)+coach.get('wage',0)),2),'size':len(sq),'legal':len(sq)==20 and all(mins[k]<=counts[k]<=maxs[k] for k in mins),'counts':dict(counts),'foreign':foreign,'foreign_limit':limit,'foreign_violation':limit>=0 and foreign>limit,'ca_mean':mean([q['current_ability'] for q in sq]),'ca_best8':mean(sorted([q['current_ability'] for q in sq],reverse=True)[:8]),'expired_contracts':sum(q.get('contract_years',0)<=0 for q in sq),'injured':sum(q.get('injury_rounds',0)>0 for q in sq),'coach':{'name':coach.get('name'),'ca':coach.get('current_ability'),'professionalism':coach.get('attributes',{}).get('professionalism'),'style':coach.get('style')}})
r['finance']={'budget':dist([c['budget'] for c in r['clubs']]),'total_budget':sum(c['budget'] for c in r['clubs']),'wages':dist([c['wages'] for c in r['clubs']]),'cash_to_wage_years':dist([c['cash_to_wage_years'] for c in r['clubs']]),'negative':[c for c in r['clubs'] if c['budget']<0],'richest':sorted(r['clubs'],key=lambda c:c['budget'],reverse=True)[:8]}
r['reputations']={'clubs':dist([c['reputation'] for c in r['clubs']]),'clubs_at_1000':sum(c['reputation']>=1000 for c in r['clubs']),'players':dist([q.get('reputation',0) for q in active]),'player_rep_vs_ca_top':[{k:q.get(k) for k in ['id','name','age','position','current_ability','potential_ability','reputation','club_id','nationality_country_id']} for q in sorted(active,key=lambda q:q['current_ability'],reverse=True)[:25]]}
# National pools and currently locked registrations: no inference that they are fresh call-ups.
for cid,c in countries.items():
 qs=[q for q in active if q.get('nationality_country_id')==cid];adults=[q for q in qs if not q.get('is_youth',False)];prime=[q for q in qs if 22<=q['age']<=29];youth=[q for q in qs if q['age']<=17];team=p.get('national_teams',{}).get(str(cid),{});called=[byid[i] for i in team.get('squad_ids',[]) if i in byid];top=[];roledepth={}
 for pos,n in [('GK',1),('CB',3),('CM',2),('ST',2)]:
  sub=sorted([q['current_ability'] for q in adults if q['position']==pos],reverse=True);top+=sub[:n];roledepth[pos]=sub[:8]
 r['countries'].append({'id':cid,'name':c['name'],'talent':c['youth_talent'],'reputation':c['reputation'],'clubs':sum(v['country_id']==cid for v in clubs.values()),'players':len(qs),'adults':len(adults),'pa':dist([q['potential_ability'] for q in qs]),'prime_ca':dist([q['current_ability'] for q in prime]),'youth_pa':dist([q['potential_ability'] for q in youth]),'ca80_plus':sum(q['current_ability']>=80 for q in qs),'pa90_plus':sum(q['potential_ability']>=90 for q in qs),'best_322_ca':mean(top),'best_roles':roledepth,'callup_count':len(team.get('squad_ids',[])),'missing_callup_ids':[i for i in team.get('squad_ids',[]) if i not in byid],'callup_season':team.get('registered_season'),'callup_best8_ca':mean(sorted([q['current_ability'] for q in called],reverse=True)[:8]),'callup_shape':counter(q['position'] for q in called),'coach':team.get('coach',{})})
# Current reports preserve highlights but omit per-player substitutions.
reports=[];events=[]; fingerprints=C.Counter(); current_matches=[]
for u in p['units']:
 for m in u.get('matches',[]):
  if not m.get('played'): continue
  current_matches.append((u,m));rep=m.get('report',{});reports.append(rep);events.extend(rep.get('highlights',[]));fingerprints[(rep.get('settings_version'),rep.get('settings_fingerprint'))]+=1
ge=[e for e in events if e['type'] in ['GOAL','PENALTY_GOAL']]
r['current_matches']={'count':len(current_matches),'goals':sum(m['home_goals']+m['away_goals'] for u,m in current_matches),'report_count':sum(bool(x) for x in reports),'fingerprints':[{'version':k[0],'fingerprint':k[1],'matches':v} for k,v in fingerprints.items()],'highlight_goals':len(ge),'assisted_goals':sum(bool(e.get('assist_ids')) for e in ge),'two_assist_goals':sum(len(e.get('assist_ids',[]))==2 for e in ge),'penalty_goals':sum(e['type']=='PENALTY_GOAL' for e in ge),'invalid_assists':sum(len(e.get('assist_ids',[]))>2 or e.get('player_id') in e.get('assist_ids',[]) or len(set(e.get('assist_ids',[])))!=len(e.get('assist_ids',[])) for e in ge),'formations':counter(x.get(side,{}).get('formation') for x in reports for side in ['home','away']),'styles':counter(x.get(side,{}).get('style') for x in reports for side in ['home','away']),'red_cards':sum(x.get(side,{}).get('red',0) for x in reports for side in ['home','away']),'yellow_cards':sum(x.get(side,{}).get('yellow',0) for x in reports for side in ['home','away']),'substitution_events_preserved':sum(e['type']=='SUB' for e in events),'scorer_positions':counter(byid[e['player_id']]['position'] for e in ge if e.get('player_id') in byid),'shots_per_match':mean([sum(x.get(side,{}).get('shots',0) for side in ['home','away']) for x in reports])}
# Archive health and generation distributions, streamed to avoid duplicating old careers.
retired_ids=set();dups=collisions=never_played=0;retire_years=C.Counter();retire_pa=C.Counter();archived_countries={};archived_cohorts=C.defaultdict(list)
for q in rows(F/'retired.jsonl'):
 i=q['player_id'];dups+=i in retired_ids;retired_ids.add(i);collisions+=i in byid;retire_years[q.get('retired_season')]+=1;retire_pa[q.get('potential_ability')]+=1;games=q.get('matches',0)+sum(v.get('matches',0) for v in q.get('national_stats',[]));never_played+=games==0;cid=q.get('nationality_country_id');archived_countries.setdefault(cid,[]).append(q.get('potential_ability',0));archived_cohorts[cid].append(q.get('current_ability',0))
r['archive']={'current_branch_retired':len(retired_ids),'duplicate_ids':dups,'collisions_with_active':collisions,'zero_club_and_national_appearances':never_played,'retirement_seasons':dict(sorted(retire_years.items())),'pa100':retire_pa[100]}
for c in r['countries']: c['retired_pa']=dist(archived_countries.get(c['id'],[]))
r['free_market']={'seasons_distribution':counter(q.get('free_agent_seasons',0) for q in p['free_agents']),'five_seasons_ca_below70':[q['id'] for q in p['free_agents'] if q.get('free_agent_seasons',0)>=5 and q['current_ability']<70],'ca70_plus':[{k:q.get(k) for k in ['id','name','age','position','current_ability','potential_ability','reputation','free_agent_seasons']} for q in p['free_agents'] if q['current_ability']>=70]}
trans=p.get('transfer_log',[]);latest=[x for x in trans if x.get('season',0)>=p['season_number']-9];incoming=[x for x in latest if x.get('direction')=='in'];r['transfers']={'total_events':len(trans),'last10_events':len(latest),'last10_directions':counter(x.get('direction') for x in latest),'last10_in':len(incoming),'last10_paid':sum(x.get('fee',0)>0 for x in incoming),'last10_free':sum(x.get('fee',0)==0 for x in incoming),'last10_paid_fees':dist([x.get('fee',0) for x in incoming if x.get('fee',0)>0]),'last10_paid_total':sum(x.get('fee',0) for x in incoming),'last10_by_season':dict(sorted(C.Counter(x['season'] for x in incoming).items()))}
allcoaches=list(p['coaches_by_club'].values())+[t['coach'] for t in p.get('national_teams',{}).values()]+p['coach_market'].get('free',[])+p['coach_market'].get('retired',[]);coachids=[x['id'] for x in allcoaches];cev=p['coach_market'].get('events',[]);ce=[x for x in cev if x.get('season',0)>=p['season_number']-9]; stints=[s for q in allcoaches for s in q.get('career',[]) if s.get('season_to',0)>0 and s.get('season_from',0)>=p['season_number']-30]
r['coaches']={'club':len(p['coaches_by_club']),'national':len(p['national_teams']),'free':len(p['coach_market']['free']),'retired':len(p['coach_market']['retired']),'duplicate_ids':len(coachids)-len(set(coachids)),'active_styles':counter(x.get('style') for x in list(p['coaches_by_club'].values())+[t['coach'] for t in p['national_teams'].values()]),'last10_events':counter(x.get('reason') for x in ce),'finished_stint_season_span':dist([s['season_to']-s['season_from'] for s in stints]),'simultaneous_club_national':sum(bool(x.get('club_id')) and bool(x.get('national_team_id')) for x in allcoaches),'active_beyond_retirement':sum(x.get('age',0)>=x.get('retirement_age',100) for x in list(p['coaches_by_club'].values())+[t['coach'] for t in p['national_teams'].values()])}
# Match histories and final tables, processed one edition at a time.
season_maps=C.defaultdict(dict); editions_counts=C.Counter();league_metrics={}; top_examples=[];nat_upsets=[]; all_match_count=0
for e in rows(F/'editions.jsonl'):
 if e.get('live'): continue
 uid=int(e['id']);year=int(e.get('season',0));national=e.get('national',False);u=units.get(uid,{});seen_matches=[m for m in e.get('matches',[]) if m.get('played')];all_match_count+=len(seen_matches);tables=sorted(e.get('standings',[]),key=lambda x:(-x.get('points',0),-x.get('goal_diff',0),-x.get('goals_for',0)));ranks={int(x['club_id']):j+1 for j,x in enumerate(tables)}; identities=e.get('clubs_by_id',{});winners=e.get('winners',[]);winner=next((x.get('club_id') for x in winners if x.get('place',1)==1),None);regular=winners[0].get('regular',[{}])[0].get('club_id') if winners and winners[0].get('regular') else (tables[0]['club_id'] if tables and not e.get('live') and not national else None)
 if not e.get('live'): season_maps[uid][year]={'rank':ranks,'table':tables,'champion':winner,'regular':regular,'clubs':{int(i):v for i,v in identities.items()},'rules':e.get('rules',{}),'divisions':e.get('divisions',[])};editions_counts[uid]+=1
 lm=league_metrics.setdefault(uid,{'name':u.get('name',e.get('name')),'national':national,'eras':{},'bad_table_rows':0,'examples':[],'reversal4':0,'reversal8':0,'exact_8_0_reversal':0,'position_stats':{},'recent_position_stats':{}})
 if not e.get('live'):
  points=e.get('rules',{}); lm['bad_table_rows']+=sum(x.get('played',0)!=x.get('won',0)+x.get('drawn',0)+x.get('lost',0) or x.get('goal_diff',0)!=x.get('goals_for',0)-x.get('goals_against',0) or x.get('points',0)!=x.get('won',0)*points.get('points_win',3)+x.get('drawn',0)*points.get('points_draw',1)+x.get('lost',0)*points.get('points_loss',0) for x in tables)
  for pos,bag in e.get('position_stats',{}).items():
   for target in ['position_stats']+(['recent_position_stats'] if year>=p['season_number']-20 else []):
    q=lm[target].setdefault(pos,{'goals':0,'assists':0,'minutes':0,'matches':0})
    for field in q:q[field]+=bag.get(field,0)
 for m in seen_matches:
  a,b=m['home_goals'],m['away_goals'];era='all' if False else ('last20' if year>=p['season_number']-20 else 'previous');stats=lm['eras'].setdefault(era,{'matches':0,'goals':0,'draws':0,'8plus':0,'margin6plus':0,'home_wins':0,'away_wins':0,'goalless':0,'max_goals':0});stats['matches']+=1;stats['goals']+=a+b;stats['draws']+=a==b;stats['home_wins']+=a>b;stats['away_wins']+=b>a;stats['goalless']+=a+b==0;stats['8plus']+=max(a,b)>=8;stats['margin6plus']+=abs(a-b)>=6;stats['max_goals']=max(stats['max_goals'],a,b)
  if abs(a-b)>=10 and len(lm['examples'])<6: lm['examples'].append({'season':year,'home':name(m['home_id']),'away':name(m['away_id']),'score':[a,b]})
  if national and abs(a-b)>=3:
   win=m['home_id'] if a>b else m['away_id'];lose=m['away_id'] if a>b else m['home_id'];wc=countries.get(win-1000000000,{});lc=countries.get(lose-1000000000,{})
   if wc.get('youth_talent',0)+10<=lc.get('youth_talent',0): nat_upsets.append({'season':year,'stage':m.get('stage'),'winner':name(win),'loser':name(lose),'winner_talent':wc.get('youth_talent'),'loser_talent':lc.get('youth_talent'),'score':[max(a,b),min(a,b)]})
 pairs=C.defaultdict(list)
 for m in seen_matches:
  if m.get('stage')=='PLAYOFF': pairs[tuple(sorted([m['home_id'],m['away_id']]))].append(m)
 for pair,mm in pairs.items():
  mm.sort(key=lambda x:(x.get('season_day',0),x.get('game_index',0)));previous=None
  for m in mm:
   signed=(m['home_goals']-m['away_goals'])*(1 if m['home_id']==pair[0] else -1)
   if previous is not None and abs(previous)>=4 and abs(signed)>=4 and previous*signed<0:lm['reversal4']+=1
   if previous is not None and abs(previous)>=8 and abs(signed)>=8 and previous*signed<0:lm['reversal8']+=1
   previous=signed
# Stable eras and champion collapses; a normal title change is not called a collapse.
def streak(hist,key):
 best=run=0;prev=None
 for y,row in sorted(hist.items()):
  w=row.get(key); run=run+1 if prev==w and w else (1 if w else 0);best=max(best,run);prev=w
 return best
collapse=[]
for uid,lm in league_metrics.items():
 hist=season_maps[uid];seq=[(y,v) for y,v in sorted(hist.items()) if v.get('champion')];last=seq[-20:];lm['editions']=editions_counts[uid];lm['champions']=C.Counter(name(v['champion']) for y,v in seq).most_common();lm['last20_champions']=C.Counter(name(v['champion']) for y,v in last).most_common();lm['repeat_titles']=sum(a[1]['champion']==b[1]['champion'] for a,b in zip(seq,seq[1:]));lm['longest_title_streak']=streak(hist,'champion');lm['regular_playoff_same']=sum(v.get('regular')==v['champion'] for y,v in seq if v.get('regular'));lm['last20_regular_champions']=C.Counter(name(v['regular']) for y,v in last if v.get('regular')).most_common();lm['champion_next_year_bottom_quarter']=0
 for y,v in seq:
  nxt=hist.get(y+1);cid=v['champion']
  if not nxt:continue
  rank=nxt['rank'].get(cid)
  if rank and rank>len(nxt['rank'])*.75:
   lm['champion_next_year_bottom_quarter']+=1;collapse.append({'league':lm['name'],'season':y,'champion':name(cid),'next_rank':rank,'field':len(nxt['rank'])})
 r['competitions'].append(lm)
r['champion_collapses']=collapse;r['national_big_upsets']=nat_upsets;r['total_match_records']=all_match_count
# Actual divisional relegation zones and promotion explain lower-league title churn.
hierarchy=[]
for uid,hist in season_maps.items():
 if units[uid].get('national'): continue
 promoted=stayed=zone_count=0;rank_next=[];changes=[];correlations=[];zone_examples=[]
 for year,entry in sorted(hist.items()):
  nxt=hist.get(year+1)
  if not nxt:continue
  changes.append(len(set(entry['clubs'])-set(nxt['clubs'])))
  shared=set(entry['rank'])&set(nxt['rank'])
  if len(shared)>2:
   xs=[entry['rank'][i] for i in shared];ys=[nxt['rank'][i] for i in shared];mx=S.mean(xs);my=S.mean(ys);den=math.sqrt(sum((x-mx)**2 for x in xs)*sum((y-my)**2 for y in ys));correlations.append(sum((x-mx)*(y-my) for x,y in zip(xs,ys))/den if den else 0)
  champ=entry.get('champion')
  if not champ:continue
  if champ not in nxt['rank']:
   promoted+=1;continue
  stayed+=1;rank_next.append(nxt['rank'][champ]);down=nxt.get('rules',{}).get('teams_relegate',0);zone=set()
  groups=C.defaultdict(list)
  for row in nxt['table']:groups[row.get('division',0)].append(row)
  if down and groups:
   depth=0
   while len(zone)<down:
    candidates=[group[-1-depth]['club_id'] for group in groups.values() if len(group)>depth];candidates.sort(key=lambda i:nxt['rank'][i],reverse=True)
    if not candidates:break
    for i in candidates:
     zone.add(i)
     if len(zone)>=down:break
    depth+=1
  if champ in zone:zone_count+=1;zone_examples.append({'champion_season':year,'club':name(champ),'following_rank':nxt['rank'][champ]})
 hierarchy.append({'unit':uid,'name':units[uid]['name'],'champion_left_next_edition':promoted,'champion_stayed':stayed,'champion_next_relegation_zone':zone_count,'zone_examples':zone_examples,'champion_next_rank':dist(rank_next),'annual_clubs_leaving':dist(changes),'adjacent_rank_correlation':dist(correlations)})
r['hierarchy']=hierarchy
rotation=[]
for cid in clubs:
 qs=[q for q in active if q.get('season_stats',{}).get('season')==p['season_number'] and q.get('season_stats',{}).get('club_id')==cid];matches=next((row['played'] for row in club_unit[cid].get('standings',[]) if row['club_id']==cid),0)
 subs=sum(q['season_stats'].get('matches',0)-q['season_stats'].get('starts',0) for q in qs)
 rotation.append({'club':name(cid),'matches':matches,'sub_appearances':subs,'sub_appearances_per_team_match':subs/max(matches,1),'field_starters':sum(q['position']!='GK' and q['season_stats'].get('starts',0)>0 for q in qs),'field_used':sum(q['position']!='GK' and q['season_stats'].get('minutes',0)>0 for q in qs)})
r['rotation']={'clubs':rotation,'incoming_subs_per_team_match':dist([q['sub_appearances_per_team_match'] for q in rotation]),'distinct_field_starters':dist([q['field_starters'] for q in rotation]),'field_used':dist([q['field_used'] for q in rotation])}
# Storage: only the saved head's ancestry belongs to this run.
db=ro(F/'games.db');head=p['history_head'];ancestry='WITH RECURSIVE a(id) AS (SELECT ? UNION ALL SELECT n.parent_id FROM save_history_nodes n JOIN a ON n.id=a.id WHERE n.parent_id IS NOT NULL) '
size={}
for table in ['save_history_players','save_history_tournaments']:
 total=db.execute('select count(*),sum(length(body)) from '+table).fetchone();branch=db.execute(ancestry+'select count(*),sum(length(body)) from '+table+' where history_id in (select id from a)',(head,)).fetchone();size[table]={'all_records':total[0],'all_body_bytes':total[1],'current_records':branch[0],'current_body_bytes':branch[1],'outside_branch_bytes':total[1]-branch[1]}
size['zero_club_appearances_body']=db.execute(ancestry+'select count(*),sum(length(body)) from save_history_players where history_id in (select id from a) and matches=0',(head,)).fetchone()
size['file_bytes']=(F/'games.db').stat().st_size;size['free_pages']=db.execute('pragma freelist_count').fetchone()[0];size['section_bytes']=dict(db.execute('select section,length(body) from save_sections where slot=?',('autosave',)));db.close();r['storage']=size
if (F/'effective_settings.json').exists():
 cfg=json.loads((F/'effective_settings.json').read_text());r['settings']=cfg;r['settings']['matches_saved_fingerprint']=all(x['fingerprint']==cfg['fingerprint'] for x in r['current_matches']['fingerprints'])
(F/'full-audit.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'meta':r['meta'],'pools':{k:v['count'] for k,v in r['pools'].items()},'integrity':r['integrity'],'total_match_records':all_match_count,'competitions':[{k:x[k] for k in ['name','editions','repeat_titles','longest_title_streak','champion_next_year_bottom_quarter','eras','last20_champions']} for x in r['competitions']],'transfers':r['transfers'],'coaches':r['coaches'],'current_matches':r['current_matches']},ensure_ascii=False,indent=2))
