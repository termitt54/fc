"""Long-run save health, leader eras, economics and archive footprint."""
import collections as co
import json
import sqlite3
import statistics as st
import sys
from pathlib import Path

folder = Path(sys.argv[1]).resolve()
p = json.loads((folder / "payload.json").read_text(encoding="utf-8"))
a = json.loads((folder / "archive.json").read_text(encoding="utf-8"))
clubs = {int(k):v for u in p["units"] if not u.get("national") for k,v in u["clubs_by_id"].items()}
report = {"season":p["season_number"], "day":p["season_day"], "clubs":len(clubs), "units":[], "pools":{}, "finance":{}, "archive":{}}
def streaks(rows, field):
    result = []
    current = None
    for h in rows:
        name = h.get("regular",[{}])[0].get("club_name") if field=="regular" else h.get("club_name")
        if current and current["club"]==name and current["season_to"]+1==h["season"]:
            current["season_to"] = h["season"]
            current["length"] += 1
        else:
            current = {"club":name,"season_from":h["season"],"season_to":h["season"],"length":1}
            result.append(current)
    return sorted(result,key=lambda x:x["length"],reverse=True)
for u in p["units"]:
    history = sorted(u.get("winners",[]),key=lambda h:h["season"])
    detail = {"name":u["name"],"national":u.get("national",False),"foreign_limit":u.get("foreign_players_limit"),"eras":[],
        "regular_streaks":streaks(history,"regular")[:5],"playoff_streaks":streaks(history,"playoff")[:5]}
    for lo,hi in [(1,25),(26,50),(51,75),(76,103)]:
        rows = [h for h in history if lo<=h["season"]<=hi]
        detail["eras"].append({"from":lo,"to":hi,"regular":co.Counter(h["regular"][0]["club_name"] for h in rows if h.get("regular")).most_common(),
                            "playoff":co.Counter(h["club_name"] for h in rows).most_common()})
    report["units"].append(detail)
for key in ["players_by_club","reserve_players_by_club","youth_players_by_club","free_agents"]:
    qs = p[key] if key=="free_agents" else [q for squad in p[key].values() for q in squad]
    report["pools"][key] = {"count":len(qs),"ca_mean":round(st.mean(q["current_ability"] for q in qs),2),"ca_max":max(q["current_ability"] for q in qs),
        "pa_mean":round(st.mean(q["potential_ability"] for q in qs),2),"rep_mean":round(st.mean(q["reputation"] for q in qs),2),"rep_max":max(q["reputation"] for q in qs)}
report["invalid_club_player_links"] = sum(int(cid)!=q.get("club_id") for key in ["players_by_club","reserve_players_by_club","youth_players_by_club"] for cid,squad in p[key].items() for q in squad)
report["invalid_contracts_main"] = sum(q.get("contract_years",0)<=0 for sq in p["players_by_club"].values() for q in sq)
foreign = [sum(q["nationality_country_id"]!=clubs[int(cid)]["country_id"] for q in sq) for cid,sq in p["players_by_club"].items()]
report["foreigners"] = {"distribution":dict(co.Counter(foreign)),"mean":round(st.mean(foreign),2),"violations":sum(x>12 for x in foreign)}
budgets = sorted([{"club":clubs[int(cid)]["name"],"budget":value,
    "wages":sum(q.get("wage",0) for key in ["players_by_club","reserve_players_by_club","youth_players_by_club"] for q in p[key].get(cid,[]))+p["coaches_by_club"].get(cid,{}).get("wage",0)} for cid,value in p["club_budgets"].items()],key=lambda r:r["budget"])
report["finance"] = {"negative":sum(q["budget"]<0 for q in budgets),"median":st.median(q["budget"] for q in budgets),"total":sum(q["budget"] for q in budgets),"bottom":budgets[:8],"top":list(reversed(budgets[-8:]))}
ids = [q["identity"]["player_id"] for q in a]
active_ids = {q["id"] for key in ["players_by_club","reserve_players_by_club","youth_players_by_club"] for sq in p[key].values() for q in sq} | {q["id"] for q in p["free_agents"]}
report["archive"] = {"current_records":len(ids),"duplicate_ids":len(ids)-len(set(ids)),"collisions_with_active":len(set(ids)&active_ids),
    "missing_full_snapshot":sum(not q.get("player") for q in a),"retirement_years":dict(sorted(co.Counter(q["identity"]["retired_season"] for q in a).items()))}
db = sqlite3.connect((folder / "games.db").as_uri()+"?mode=ro",uri=True)
report["archive"]["all_branches_records"],report["archive"]["all_branches_body_bytes"] = db.execute("select count(*),sum(length(body)) from save_history_players").fetchone()
report["archive"]["current_body_bytes"] = sum(len(row[0]) for row in db.execute("WITH RECURSIVE a(id) AS (SELECT ? UNION ALL SELECT n.parent_id FROM save_history_nodes n JOIN a ON n.id=a.id WHERE n.parent_id IS NOT NULL) SELECT body FROM save_history_players WHERE history_id in (select id from a)",(p["history_head"],)))
report["section_bytes"] = dict(db.execute("select section,length(body) from save_sections where slot='autosave'"))
report["db_bytes"] = (folder/"games.db").stat().st_size
db.close()
previous = json.loads((folder.parent/"user-foreign12-snapshot/payload.json").read_text(encoding="utf-8"))
report["same_history_as_previous_run"] = all(sorted(u["winners"],key=lambda h:h["season"])[:17]==sorted(v["winners"],key=lambda h:h["season"]) for u,v in zip(p["units"],previous["units"]))
(folder/"longrun-audit.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(report,ensure_ascii=False,indent=2))
