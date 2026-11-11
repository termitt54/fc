"""Descriptive comparison of two exports; not a controlled simulation experiment."""
import collections as co
import json
import statistics as st
import sys
from pathlib import Path

def inspect(folder):
    p = json.loads((folder / "payload.json").read_text(encoding="utf-8"))
    archive = json.loads((folder / "archive.json").read_text(encoding="utf-8"))
    clubs = {int(k): v for u in p["units"] if not u.get("national") for k,v in u["clubs_by_id"].items()}
    players = {q["identity"]["player_id"]:q.get("player",{}) for q in archive}
    active = [q for k in ("players_by_club","reserve_players_by_club","youth_players_by_club") for squad in p[k].values() for q in squad] + p["free_agents"]
    players.update({q["id"]:q for q in active})
    foreigners = [sum(q["nationality_country_id"] != clubs[int(k)]["country_id"] for q in squad) for k,squad in p["players_by_club"].items()]
    report = {"season":p["season_number"], "day":p["season_day"], "completed_seasons":p["season_number"]-1,
        "foreign_limit":[u.get("foreign_players_limit") for u in p["units"] if not u.get("national")],
        "foreigners_mean":round(st.mean(foreigners),2), "foreigners_distribution":dict(co.Counter(foreigners)),
        "competitions":[], "transfers":{}}
    for u in p["units"]:
        history = sorted(u.get("winners",[]),key=lambda h:h["season"])[:17]
        regular = [h["regular"][0]["club_name"] for h in history if h.get("regular")]
        champions = [h["club_name"] for h in history]
        report["competitions"].append({"name":u["name"], "national":u.get("national",False),
            "regular_unique":len(set(regular)), "playoff_unique":len(set(champions)),
            "regular_titles":co.Counter(regular).most_common(), "playoff_titles":co.Counter(champions).most_common(),
            "repeat_playoff":sum(a==b for a,b in zip(champions,champions[1:]))})
    incoming = [t for t in p["transfer_log"] if t.get("direction")=="in" and t["season"]<=17]
    known = [t for t in incoming if t["club_id"] in clubs and players.get(t["player_id"],{}).get("nationality_country_id")]
    report["transfers"] = {"incoming_first17":len(incoming), "paid":sum(t.get("fee",0)>0 for t in incoming),
        "known_player_nationality":len(known),
        "foreign_signings":sum(players[t["player_id"]]["nationality_country_id"]!=clubs[t["club_id"]]["country_id"] for t in known),
        "fees":sum(t.get("fee",0) for t in incoming)}
    report["top_clubs"] = sorted([{"name":clubs[int(cid)]["name"], "reputation":clubs[int(cid)]["reputation"],
        "top8_ca":round(st.mean(sorted([q["current_ability"] for q in squad],reverse=True)[:8]),2),
        "foreigners":sum(q["nationality_country_id"]!=clubs[int(cid)]["country_id"] for q in squad)}
        for cid,squad in p["players_by_club"].items() if squad],key=lambda q:q["top8_ca"],reverse=True)[:10]
    return report

old = Path(sys.argv[1]).resolve()
new = Path(sys.argv[2]).resolve()
report = {"previous":inspect(old), "new":inspect(new),
          "scope":"First 17 completed seasons compared. Fresh worlds with different random sequences; causal effect size cannot be isolated. Current roster snapshots are season 43 versus season 18. Top8 CA is not a position-balanced lineup."}
(new / "foreign-limit-comparison.json").write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding="utf-8")
print(json.dumps(report,ensure_ascii=False,indent=2))
