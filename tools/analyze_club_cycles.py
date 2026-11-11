"""Read-only club dominance, player continuity and replacement audit."""
import collections as C
import json
import statistics as S
import sys
from pathlib import Path

folder=Path(sys.argv[1]).resolve()
p=json.loads((folder/'payload.json').read_text(encoding='utf8'))
probe=json.loads((folder/'club-cycle-probe.json').read_text(encoding='utf8'))
clubs={int(k):v for u in p['units'] if not u.get('national') for k,v in u['clubs_by_id'].items()}
club_units={int(k):u for u in p['units'] if not u.get('national') for k in u['clubs_by_id']}
observed={int(q['player_id']):q for q in map(json.loads,(folder/'club-cycle-careers.jsonl').open(encoding='utf8'))}
active={}
for key in ['players_by_club','reserve_players_by_club','youth_players_by_club']:
    active.update({q['id']:q for squad in p[key].values() for q in squad})
active.update({q['id']:q for q in p['free_agents']});observed.update(active)
def mean(xs):return round(S.mean(xs),3) if xs else None
def ability(pid,year):
    q=observed.get(pid,{})
    values=[(x['season'],x['ca']) for x in q.get('development_history',[]) if x['season']<=year]
    return max(values)[1] if values else None
def age(pid,year):
    q=observed.get(pid,{})
    return q.get('age',0)-(q.get('retired_season',p['season_number']-1)+1-year) if q else None
def core(rows):
    selected=[]
    for role,n in [('GK',1),('CB',3),('CM',2),('ST',2)]:
        selected+=sorted([r for r in rows if r['position']==role],key=lambda r:r.get('minutes',0),reverse=True)[:n]
    return {r['player_id'] for r in selected}
years=C.defaultdict(list)
for raw in (folder/'club-season-players.jsonl').open(encoding='utf8'):
    e=json.loads(raw)
    for row in e['players'].values():
        if row.get('minutes',0)>0:years[(row['club_id'],e['season'])].append(row)
cores={k:core(v) for k,v in years.items()}
pid_club={(year,row['player_id']):cid for (cid,year),rows in years.items() for row in rows}
editions=[e for e in map(json.loads,(folder/'editions.jsonl').open(encoding='utf8')) if not e.get('national') and not e.get('live')]
finishes=C.defaultdict(list);titles=C.Counter();finals=C.Counter();top_titles=C.Counter();infra=C.defaultdict(list)
for e in editions:
    winner=next((x for x in e.get('winners',[]) if x.get('season')==e['season'] and x.get('place',1)==1),{})
    if e['id']==1 and e['season']>=117:
        if winner:top_titles[winner['club_id']]+=1
    for row in winner.get('playoff',[]):
        if row.get('place')==1:titles[row['club_id']]+=1
        if row.get('place',99)<=2:finals[row['club_id']]+=1
        finishes[row['club_id']].append({'season':e['season'],'league':e['name'],'place':row['place']})
    for raw_id,club in e['clubs_by_id'].items():
        infra[int(raw_id)].append({'season':e['season'],'training':club.get('training_level'),'academy':club.get('youth_academy'),'search':club.get('youth_search'),'reputation':club.get('reputation'),'league':e['name']})
trans=[x for x in p['transfer_log'] if 127<=x.get('season',0)<=136]
byclub=C.defaultdict(list)
for row in trans:byclub[row['club_id']].append(row)
result={'season':p['season_number'],'day':p['season_day'],'career_records_exported':sum(1 for _ in (folder/'club-cycle-careers.jsonl').open()),'historical_core_club_seasons':len(cores),'clubs':[],'last20_top_titles':dict(top_titles)}
probes={x['id']:x for x in probe['clubs']}
for cid,club in clubs.items():
    sq=p['players_by_club'].get(str(cid),[])
    ids=set(probes[cid]['fresh_selected']);starters=[q for q in sq if q['id'] in ids]
    wages=sum(q.get('wage',0) for key in ['players_by_club','reserve_players_by_club','youth_players_by_club'] for q in p[key].get(str(cid),[]))+p['coaches_by_club'][str(cid)].get('wage',0)
    rows=byclub[cid];incoming=[x for x in rows if x.get('direction')=='in'];paid=[x for x in incoming if x.get('fee',0)>0]
    out=[x for x in rows if x.get('direction')=='out']
    money_in=sum(x.get('fee',0) for x in out);money_out=sum(x.get('fee',0) for x in paid)
    retention=[];exits=[];replacement_gaps=[];ca_by_year=[];old_cores=[]
    for year in range(107,137):
        before=cores.get((cid,year),set());after=cores.get((cid,year+1),set())
        values=[ability(i,year) for i in before if ability(i,year) is not None]
        if before:ca_by_year.append({'season':year,'ca':mean(values),'covered':len(values),'core_size':len(before)})
        old_cores += [age(i,year)>=32 for i in before if age(i,year) is not None]
        if not before or not after:continue
        remained_in_club={r['player_id'] for r in years[(cid,year+1)]}
        retention.append({'season':year,'same_core':len(before&after),'core_size':len(before),'still_played_here':len(before&remained_in_club)})
        for pid in before-remained_in_club:
            q=observed.get(pid,{})
            destination=pid_club.get((year+1,pid))
            retired=q.get('retired_season')==year
            exits.append({'season':year,'player':q.get('name',pid),'id':pid,'age':age(pid,year),'ca':ability(pid,year),'retired':retired,'next_club':clubs.get(destination,{}).get('name'),'next_club_id':destination})
        left_values=[ability(i,year) for i in before-after if ability(i,year) is not None]
        new_values=[ability(i,year+1) for i in after-before if ability(i,year+1) is not None]
        if left_values and new_values:replacement_gaps.append(mean(new_values)-mean(left_values))
    pr=probes[cid]['players'];key=[x for x in pr if x['key']]
    transfer_ca=[ability(x['player_id'],x['season']) for x in paid if ability(x['player_id'],x['season']) is not None]
    free_ca=[ability(x['player_id'],x['season']) for x in incoming if x.get('fee',0)==0 and ability(x['player_id'],x['season']) is not None]
    historical=sorted(infra[cid],key=lambda x:x['season'])
    result['clubs'].append({'id':cid,'name':club['name'],'country':club.get('country_name'),'country_id':club['country_id'],'league':club_units[cid]['name'],'reputation':club['reputation'],'elo':club.get('club_elo',{}).get('elo'),'budget':p['club_budgets'][str(cid)],'wages':wages,'cash_wage_years':p['club_budgets'][str(cid)]/max(1,wages),'fresh_core_ca':mean([q['current_ability'] for q in starters]),'core_local_ca':mean([q['current_ability'] for q in starters if q['nationality_country_id']==club['country_id']]),'core_foreign_ca':mean([q['current_ability'] for q in starters if q['nationality_country_id']!=club['country_id']]),'core_foreign':sum(q['nationality_country_id']!=club['country_id'] for q in starters),'core_age':mean([q['age'] for q in starters]),'core32plus':sum(q['age']>=32 for q in starters),'training':club.get('training_level'),'academy':club.get('youth_academy'),'search':club.get('youth_search'),'infrastructure_first':historical[0] if historical else {},'historical_leagues':dict(C.Counter(x['league'] for x in historical)),'titles_all':titles[cid],'finals_all':finals[cid],'top_titles_last20':top_titles[cid],'podiums':finishes[cid],'transfers_last10':{'arrivals':len(incoming),'paid':len(paid),'free':len(incoming)-len(paid),'paid_ca_known':len(transfer_ca),'paid_ca_mean':mean(transfer_ca),'free_ca_known':len(free_ca),'free_ca_mean':mean(free_ca),'paid_spend':money_out,'paid_receipts':money_in,'net_spend':money_out-money_in,'paid_out':sum(x.get('fee',0)>0 for x in out)},'core_retention':retention,'core_retained_mean':mean([x['same_core'] for x in retention]),'core_still_played_here_mean':mean([x['still_played_here'] for x in retention]),'core_exits':exits,'core_exits_retired':sum(x['retired'] for x in exits),'core_exits_other_club':sum(x['next_club_id'] is not None for x in exits),'replacement_ca_gap_mean':mean(replacement_gaps),'core_ca_by_year':ca_by_year,'core32plus_historical_share':mean(old_cores),'key_renew_chance':mean([x['renew_chance'] for x in key]),'key_renew97_count':sum(x['renew_chance']>=.969 for x in key),'key_cannot_sell':sum(not x['can_sell'] for x in key),'key_count':len(key),'extra_wage_if_all_renewed':sum(x['renew_wage']-x['wage'] for x in pr)})
groups={'last20_champions':[x for x in result['clubs'] if x['top_titles_last20']>0],'greek':[x for x in result['clubs'] if x['country_id']==18],'all':result['clubs']}
for club in result['clubs']:
    cid=club['id'];sq=p['players_by_club'][str(cid)];selected=set(probes[cid]['fresh_selected'])
    club['foreign_main']=sum(q['nationality_country_id']!=club['country_id'] for q in sq)
    club['foreign_outside_fresh_core']=sum(q['nationality_country_id']!=club['country_id'] and q['id'] not in selected for q in sq)
    club['core_no_transfer_stamp']=sum(q['id'] in selected and 'joined_season' not in q for q in sq)
    for key in ['ordinary_upgrade_quote','diagnostic_core_upgrade_quote']:
        if key in probes[cid]:club[key]=probes[cid][key]
result['groups']={k:{'clubs':len(v),'core_ca':mean([x['fresh_core_ca'] for x in v]),'cash_wage_years':mean([x['cash_wage_years'] for x in v]),'same_core_next_year':mean([x['core_retained_mean'] for x in v if x['core_retained_mean'] is not None]),'same_club_next_year':mean([x['core_still_played_here_mean'] for x in v if x['core_still_played_here_mean'] is not None]),'key_cannot_sell':sum(x['key_cannot_sell'] for x in v),'key_count':sum(x['key_count'] for x in v),'key_renew_chance':mean([x['key_renew_chance'] for x in v]),'key_renew97_count':sum(x['key_renew97_count'] for x in v)} for k,v in groups.items()}
(folder/'club-cycle-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
fields=['id','name','league','fresh_core_ca','core_local_ca','core_foreign_ca','core_foreign','budget','wages','cash_wage_years','training','academy','search','historical_leagues','top_titles_last20','transfers_last10','core_retained_mean','core_still_played_here_mean','core_exits_retired','core_exits_other_club','replacement_ca_gap_mean','key_renew_chance','key_cannot_sell','key_count']
print(json.dumps({'groups':result['groups'],'selected':[{k:x[k] for k in fields} for x in result['clubs'] if x['id'] in [41,35,127,124,125,126,33,34,49,82]],'coverage':{'core_players':sum(x['core_size'] for c in result['clubs'] for x in c['core_ca_by_year']),'ca_known':sum(x['covered'] for c in result['clubs'] for x in c['core_ca_by_year'])}},ensure_ascii=False,indent=2))
