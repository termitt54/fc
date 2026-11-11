"""Controlled tournament null model: fixed real strengths, stochastic football results.

Exercises knockout survival, unequal match counts, protected public SUM Elo and
the new symmetric development reference. This is not the spatial match engine.
"""
import json
import math
import random
import statistics as S
from pathlib import Path

def expected(a,b):return 1/(1+10**((b-a)/600))
def advance(t,trend,evidence,old):
    trend=trend*.98+max(-2.5,min(2.5,evidence))
    up=5+.04*t if old else 8
    down=5+.04*(100-t) if old else 8
    if trend>=up:t+=1;trend-=up
    elif trend<=-down:t-=1;trend+=down
    return t,trend

changes={'old':[],'new':[]};high={'old':[],'new':[]}
for world in range(80):
    rng=random.Random(111126+world)
    initial=[85-(i%16) for i in range(42)]
    true=[1400+20*(t-77) for t in initial]
    public=true.copy();shadow=true.copy()
    talents=[initial.copy(),initial.copy()];trends=[[0.0]*42,[0.0]*42]
    for edition in range(68):
        start=public.copy();evidence=[[0.0]*42,[0.0]*42];games=[0]*42
        def play(a,b,knockout=False):
            e=expected(true[a],true[b]);draw=min(.20,2*min(e,1-e))
            roll=rng.random();score=1.0 if roll<e-draw/2 else .5 if roll<e+draw/2 else 0.0
            winner=a if score==1 or (score==.5 and rng.random()<.5) else b
            evidence[0][a]+=score-expected(start[a],start[b]);evidence[0][b]+=1-score-expected(start[b],start[a])
            surprise=score-expected(shadow[a],shadow[b]);evidence[1][a]+=surprise;evidence[1][b]-=surprise
            shadow[a]+=32*surprise;shadow[b]-=32*surprise
            pa,pb=public[a],public[b]
            ra=.75 if knockout and score==.5 and winner==a else score
            rb=.75 if knockout and score==.5 and winner==b else 1-score
            da=50*(ra-expected(pa,pb));db=50*(rb-expected(pb,pa))
            public[a]+=max(0,da) if knockout else da;public[b]+=max(0,db) if knockout else db
            games[a]+=1;games[b]+=1
            return score,winner
        ids=list(range(42));rng.shuffle(ids);groups=[ids[i:i+7] for i in range(0,42,7)]
        qualified=[];third=[]
        for group in groups:
            points={i:0 for i in group}
            for j,a in enumerate(group):
                for b in group[j+1:]:
                    score,_=play(a,b);points[a]+=score*2;points[b]+=(1-score)*2
            group.sort(key=lambda i:(points[i],rng.random()),reverse=True)
            qualified+=group[:2];third.append((points[group[2]],rng.random(),group[2]))
        qualified += [x[2] for x in sorted(third,reverse=True)[:4]];rng.shuffle(qualified)
        while len(qualified)>1:
            qualified=[play(qualified[j],qualified[j+1],True)[1] for j in range(0,len(qualified),2)]
        for i in range(42):
            for model in range(2):
                scale=games[i] if model==0 else 6
                talents[model][i],trends[model][i]=advance(talents[model][i],trends[model][i],evidence[model][i]/math.sqrt(scale)*2,model==0)
    for model,key in enumerate(['old','new']):
        changes[key]+=[t-start for t,start in zip(talents[model],initial)]
        high[key]+=[t-start for t,start in zip(talents[model],initial) if start>=80]
def summary(xs):return {'mean':S.mean(xs),'up':sum(x>0 for x in xs),'down':sum(x<0 for x in xs),'same':xs.count(0),'min':min(xs),'max':max(xs)}
out={'worlds':80,'countries_per_world':42,'seasons':136,'model':'fixed latent strengths, stochastic group + knockout results; no player generation or spatial simulation','all':{k:summary(v) for k,v in changes.items()},'initial_talent80_plus':{k:summary(v) for k,v in high.items()}}
Path('tests/performance/results/talent-tournament-drift-nov11.json').write_text(json.dumps(out,indent=2),encoding='utf8')
print(json.dumps(out,indent=2))
