"""Supplement a branch-aware exported save audit with rating and generation data."""
import collections as C
import json
import math
import statistics as S
import sys
from pathlib import Path

folder = Path(sys.argv[1]).resolve()
p = json.loads((folder / 'payload.json').read_text(encoding='utf8'))
active = []
for key in ['players_by_club', 'reserve_players_by_club', 'youth_players_by_club']:
    active.extend(q for squad in p[key].values() for q in squad)
active.extend(p['free_agents'])
byid = {q['id']: q for q in active}
clubs = {int(k): v for u in p['units'] if not u.get('national') for k, v in u['clubs_by_id'].items()}
teams = {int(k): v for k, v in p['national_teams'].items()}
def mean(xs): return round(S.mean(xs), 3) if xs else None
def corr(xs, ys):
    if len(xs) < 3: return None
    a, b = S.mean(xs), S.mean(ys)
    d = math.sqrt(sum((x-a)**2 for x in xs)*sum((y-b)**2 for y in ys))
    return round(sum((x-a)*(y-b) for x,y in zip(xs,ys))/d, 4) if d else None
def country_name(cid): return teams.get(cid, {}).get('country', {}).get('name', str(cid))
r = {'national': [], 'club_ratings': [], 'national_editions': [], 'economic_flow': []}
settings = json.loads((folder/'config/club_attraction.json').read_text())['values']
for cid, club in clubs.items():
    rating = club.get('club_elo', {})
    rep, elo = club['reputation'], rating.get('elo', club['reputation'])
    attract = rep*settings['reputation_weight']/100 + elo*settings['elo_weight']/100 if settings['mode']=='WEIGHTS' else rep+max(-settings['max_effect'], min(settings['max_effect'], (rating.get('sporting_reputation',rep)-rep)*.25))
    r['club_ratings'].append({'id':cid,'name':club['name'],'reputation':rep,'elo':elo,'initial_elo':rating.get('initial_elo'), 'games':rating.get('games'), 'attractiveness':attract})
for cid, t in teams.items():
    c, rating = t['country'], t.get('rating', {})
    qs = [q for q in active if q['nationality_country_id']==cid]
    best = []
    for role,n in [('GK',1),('CB',3),('CM',2),('ST',2)]:
        best += sorted((q['current_ability'] for q in qs if q['position']==role and not q.get('is_youth',False)), reverse=True)[:n]
    r['national'].append({'id':cid,'name':c['name'],'talent':c['youth_talent'],'initial_talent':c.get('initial_youth_talent'), 'reputation':c['reputation'],'initial_reputation':rating.get('initial_reputation'),'elo':rating.get('elo'), 'initial_elo':rating.get('initial_elo'),'games':rating.get('games'), 'talent_changes':rating.get('talent_history',[]),'trend':rating.get('trend'),'pool':len(qs),'ca80':sum(q['current_ability']>=80 for q in qs),'pa90':sum(q['potential_ability']>=90 for q in qs),'best322_ca':mean(best),'current_youth_pa':mean([q['potential_ability'] for q in qs if q['age']<=17]),'registration_season':t.get('registered_season'),'callup_missing':sum(i not in byid for i in t.get('squad_ids',[]))})
r['correlations'] = {'talent_to_best322_ca':corr([x['talent'] for x in r['national']],[x['best322_ca'] for x in r['national']]),'talent_to_youth_pa':corr([x['talent'] for x in r['national'] if x['current_youth_pa'] is not None],[x['current_youth_pa'] for x in r['national'] if x['current_youth_pa'] is not None])}
rep_hist, elo_hist = C.defaultdict(list), C.defaultdict(list)
current_year = p['season_number']
pair_buckets = C.defaultdict(C.Counter)
cross = {'table_rows_checked':0,'bad_table_rows':0,'bad_table_examples':[],'club_elo_games_mismatches':[], 'national_elo_games_mismatches':[]}
counted_club_games, counted_national_games = C.Counter(), C.Counter()
for raw in (folder/'editions.jsonl').open(encoding='utf8'):
    e=json.loads(raw)
    recomputed=C.defaultdict(C.Counter)
    for m in e.get('matches',[]):
        if not m.get('played'): continue
        counts=counted_national_games if e.get('national') else counted_club_games
        counts[m['home_id']]+=1;counts[m['away_id']]+=1
        if m.get('stage','REGULAR')!='REGULAR': continue
        for cid,gf,ga in [(m['home_id'],m['home_goals'],m['away_goals']),(m['away_id'],m['away_goals'],m['home_goals'])]:
            row=recomputed[cid];row['played']+=1;row['goals_for']+=gf;row['goals_against']+=ga;row['goal_diff']+=gf-ga
            outcome='won' if gf>ga else 'drawn' if gf==ga else 'lost';row[outcome]+=1
            row['points']+=e.get('rules',{}).get({'won':'points_win','drawn':'points_draw','lost':'points_loss'}[outcome],3 if gf>ga else 1 if gf==ga else 0)
    for row in e.get('standings',[]):
        cross['table_rows_checked']+=1
        if any(row.get(k,0)!=recomputed[row['club_id']][k] for k in ['played','goals_for','goals_against','goal_diff','won','drawn','lost','points']):
            cross['bad_table_rows']+=1
            if len(cross['bad_table_examples'])<5:cross['bad_table_examples'].append({'unit':e['id'],'season':e['season'],'club':row['club_id']})
    if not e.get('national') or e.get('live'): continue
    year=e['season']; identities=e['clubs_by_id']
    for raw_id, c in identities.items():
        rep_hist[int(raw_id)].append((year,c.get('reputation')))
        if 'elo' in c: elo_hist[int(raw_id)].append((year,c['elo']))
    wins=e.get('winners',[])
    winner=next((w for w in wins if w.get('season')==year and w.get('place',1)==1),wins[0] if wins else {})
    r['national_editions'].append({'season':year,'winner':winner.get('club_name'),'podium':winner.get('playoff',[]),'draw_mode':e.get('group_draw',{}).get('rules',{}).get('mode')})
    if year < current_year-20: continue
    for m in e['matches']:
        if not m.get('played'): continue
        a,b=identities.get(str(m['home_id']),{}),identities.get(str(m['away_id']),{})
        if 'youth_talent' not in a or 'youth_talent' not in b: continue
        gap=abs(a['youth_talent']-b['youth_talent'])
        bucket='0-4' if gap<5 else '5-9' if gap<10 else '10-14' if gap<15 else '15-24' if gap<25 else '25+'
        if gap==0: continue
        hg,ag=m['home_goals'],m['away_goals'];sg,wg=(hg,ag) if a['youth_talent']>b['youth_talent'] else (ag,hg)
        z=pair_buckets[bucket];z['matches']+=1;z['wins' if sg>wg else 'draws' if sg==wg else 'losses']+=1;z['goals_for']+=sg;z['goals_against']+=wg
r['recent_national_results_by_talent_gap'] = dict(pair_buckets)
for cid,club in clubs.items():
    saved=club.get('club_elo',{}).get('games',0)
    if saved!=counted_club_games[cid]:cross['club_elo_games_mismatches'].append({'id':cid,'saved':saved,'matches':counted_club_games[cid]})
for cid,team in teams.items():
    saved=team.get('rating',{}).get('games',0)
    if saved!=counted_national_games[cid+1000000000]:cross['national_elo_games_mismatches'].append({'id':cid,'saved':saved,'matches':counted_national_games[cid+1000000000]})
r['cross_checks']=cross
r['national_reputation_history']={country_name(i-1000000000): {'first':min(v),'last':max(v),'min':min(x[1] for x in v),'max':max(x[1] for x in v),'distinct':len(set(x[1] for x in v))} for i,v in rep_hist.items()}
r['national_editions'].sort(key=lambda x:x['season'])
for u in p['units']:
    if u.get('national'): continue
    rule=u['rules'];pr=rule.get('prize_rules',{});n=rule.get('teams_playoff',0)
    reg=sum(pr.get('regular_'+str(i),0) for i in range(1,rule['teams_per_division']+1))*rule['divisions_count']
    po=sum(pr.get(k,0) for k in ['playoff_champion','playoff_runner_up','playoff_third','playoff_fourth']) if n>=4 else 0
    for rd in range(1,max(1,math.ceil(math.log2(n)) if n>0 else 0)-1): po+=(n//2**rd)*pr.get('playoff_out_'+str(rd),0)
    wages=sum(sum(q.get('wage',0) for key in ['players_by_club','reserve_players_by_club','youth_players_by_club'] for q in p[key].get(cid,[]))+p['coaches_by_club'].get(cid,{}).get('wage',0) for cid in u['clubs_by_id'])
    r['economic_flow'].append({'name':u['name'],'clubs':len(u['clubs_by_id']),'prizes_regular':reg,'prizes_playoff':po,'prizes_total':reg+po,'current_annual_wages':wages,'division_prize_values':{k:v for k,v in pr.items() if k.startswith('regular_')}})
r['match_settings']=json.loads((folder/'effective_settings.json').read_text())
r['attraction_settings']=settings
arrivals=[x for x in p.get('transfer_log',[]) if x.get('direction')=='in' and current_year-10<=x.get('season',0)<current_year]
fees=[x['fee'] for x in arrivals if x.get('fee',0)>0]
r['completed_last10_transfers']={'from':current_year-10,'through':current_year-1,'arrivals':len(arrivals),'paid':len(fees),'paid_percent':100*len(fees)/max(1,len(arrivals)),'median_fee':S.median(fees) if fees else None,'max_fee':max(fees,default=0),'total_fees':sum(fees)}
(folder/'dynamics-audit.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'correlations':r['correlations'],'recent_national_results_by_talent_gap':r['recent_national_results_by_talent_gap'],'economic_flow':r['economic_flow'],'national_top':sorted(r['national'],key=lambda q:q['elo'],reverse=True)[:10],'last10_editions':r['national_editions'][-10:],'club_elo_range':[min(q['elo'] for q in r['club_ratings']),max(q['elo'] for q in r['club_ratings'])]},ensure_ascii=False,indent=2))
