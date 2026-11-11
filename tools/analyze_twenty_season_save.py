"""Read-only analysis of a Godot export; historical strength is CA, not match strength."""
import argparse
import collections as co
import json
import sqlite3
import statistics as st
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("snapshot", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.snapshot = args.snapshot.resolve()
p = json.loads((args.snapshot / "payload.json").read_text(encoding="utf-8"))
archive = json.loads((args.snapshot / "archive.json").read_text(encoding="utf-8"))
clubs = {int(cid): club for u in p["units"] for cid, club in u["clubs_by_id"].items()}
names = {cid: club["name"] for cid, club in clubs.items()}
pool_names = ("players_by_club", "reserve_players_by_club", "youth_players_by_club")
active = [q for pool in pool_names for squad in p[pool].values() for q in squad] + p["free_agents"]
players = {r["player"]["id"]: r["player"] for r in archive}
players.update({q["id"]: q for q in active})
stats = co.defaultdict(list)
for q in players.values():
    ca_history = {h["season"]: h["ca"] for h in q.get("development_history", [])}
    for s in q.get("career_stats", []) + [q.get("season_stats", {})]:
        if s.get("minutes", 0) > 0:
            stats[(s["club_id"], s["season"])].append((q, s, ca_history.get(s["season"])))

def distribution(xs):
    xs = sorted(xs)
    return {"count": len(xs), "min": min(xs), "median": st.median(xs),
            "mean": st.mean(xs), "max": max(xs)} if xs else {"count": 0}

def historical_strength(cid, season):
    rows = stats[(cid, season)]
    valid = [(q, s, ca) for q, s, ca in rows if ca is not None]
    minutes = sum(s["minutes"] for _, s, _ in rows)
    known = sum(s["minutes"] for _, s, _ in valid)
    top = sorted(rows, key=lambda r: (r[1].get("starts", 0), r[1]["minutes"]), reverse=True)[:8]
    return {"season": season, "players": len(rows), "minutes": minutes, "known_ca_minutes": known,
            "weighted_ca": sum(s["minutes"]*ca for _, s, ca in valid)/known if known else None,
            "top8": [{"id": q["id"], "name": q["name"], "pos": q["position"], "ca": ca,
                       "starts": s.get("starts", 0), "minutes": s["minutes"]} for q, s, ca in top]}

report = {"saved_at": p["saved_at"], "season": p["season_number"], "day": p["season_day"],
          "active_players": len(active), "retired_records": len(archive),
          "unique_retired": len({r["player"]["id"] for r in archive}),
          "duplicate_active_ids": len(active)-len({q["id"] for q in active}),
          "clubs": len(clubs), "pools": {}, "units": [], "champion_transitions": [], "club_details": []}
for pool in (*pool_names, "free_agents"):
    qs = p[pool] if pool == "free_agents" else [q for squad in p[pool].values() for q in squad]
    report["pools"][pool] = {"size": len(qs), "reputation": distribution([q["reputation"] for q in qs]),
        "ca": distribution([q["current_ability"] for q in qs]), "age": distribution([q["age"] for q in qs]),
        "idle_this_season": sum(q.get("season_stats", {}).get("minutes", 0) == 0 for q in qs),
        "ca80_plus": sum(q["current_ability"] >= 80 for q in qs),
        "rep800_plus": sum(q["reputation"] >= 800 for q in qs)}
report["free_agent_years"] = dict(co.Counter(q.get("free_agent_seasons", 0) for q in p["free_agents"]))
report["club_reputation"] = distribution([c["reputation"] for c in clubs.values()])
report["budgets"] = distribution(list(p["club_budgets"].values()))
report["negative_budgets"] = sum(v < 0 for v in p["club_budgets"].values())
report["total_transfer_fee_in"] = sum(t["fee"] for t in p["transfer_log"] if t["direction"] == "in")
report["transfer_years"] = [{"season": year, "incoming": sum(t["season"] == year and t["direction"] == "in" for t in p["transfer_log"]),
    "paid": sum(t["season"] == year and t["direction"] == "in" and t["fee"] > 0 for t in p["transfer_log"]),
    "fees": sum(t["fee"] for t in p["transfer_log"] if t["season"] == year and t["direction"] == "in")}
    for year in range(1, p["season_number"]+1)]

db = sqlite3.connect((args.snapshot / "world.db").as_uri()+"?mode=ro", uri=True)
editor_reps = dict(db.execute("SELECT id,reputation FROM clubs"))
db.close()
for cid, c in clubs.items():
    squad = p["players_by_club"].get(str(cid), [])
    positions = co.Counter(q["position"] for q in squad)
    bounds = {"GK": (2,3), "CB": (3,4), "FB": (4,5), "CM": (3,4), "WM": (4,5), "ST": (3,4), "WF": (4,5)}
    violations = {pos: positions[pos] for pos, (lo,hi) in bounds.items() if not lo <= positions[pos] <= hi}
    coach = p["coaches_by_club"].get(str(cid), {})
    report["club_details"].append({"id": cid, "name": names[cid], "reputation": c["reputation"],
        "editor_reputation": editor_reps.get(cid), "last_reputation_delta": c.get("reputation_delta"),
        "budget": p["club_budgets"].get(str(cid)), "main_size": len(squad), "position_violations": violations,
        "top8_ca": st.mean(sorted([q["current_ability"] for q in squad], reverse=True)[:8]) if squad else None,
        "training_level": c["training_level"], "youth_academy": c["youth_academy"],
        "coach_age": coach.get("age"), "coach_career": coach.get("career", []),
        "coach_contract": coach.get("contract_years"), "history": [historical_strength(cid,s) for s in range(1,p["season_number"]+1)]})

for u in p["units"]:
    history = sorted(u["winners"], key=lambda h: h["season"])
    regular = [h["regular"][0]["club_id"] for h in history if h.get("regular")]
    playoff = [h["club_id"] for h in history]
    table = sorted(u["standings"], key=lambda r: (-r["points"], -r["goal_diff"], -r["goals_for"]))
    detail = {"id": u["id"], "name": u["name"], "strength": u["rules"]["division_strength"],
        "clubs": len(u["clubs_by_id"]), "reputation": distribution([c["reputation"] for c in u["clubs_by_id"].values()]),
        "regular_titles": {names.get(cid, str(cid)): n for cid,n in co.Counter(regular).most_common()},
        "overall_titles": {names.get(cid, str(cid)): n for cid,n in co.Counter(playoff).most_common()},
        "repeat_regular": sum(a == b for a,b in zip(regular,regular[1:])),
        "repeat_overall": sum(a == b for a,b in zip(playoff,playoff[1:])),
        "regular_and_overall_same": sum(h["club_id"] == h["regular"][0]["club_id"] for h in history if h.get("regular")),
        "top3_appearances": {names.get(cid,str(cid)): n for cid,n in co.Counter(r["club_id"] for h in history for r in h.get("regular",[])).most_common()},
        "history": history, "current_table": table, "rules": u["rules"]}
    report["units"].append(detail)
    print(u["name"], "REG", detail["regular_titles"], "TOTAL", detail["overall_titles"], "repeat",detail["repeat_regular"], detail["repeat_overall"])
    for before, after in zip(history,history[1:]):
        if after["season"] != before["season"]+1:
            continue
        cid, season = before["club_id"], before["season"]
        a, b = historical_strength(cid,season), historical_strength(cid,season+1)
        next_ids = {q["id"] for q,_,_ in stats[(cid,season+1)]}
        missing = [r for r in a["top8"] if r["id"] not in next_ids]
        departures = []
        previous_stats = {q["id"]:(q,s,ca) for q,s,ca in stats[(cid,season)]}
        for t in p["transfer_log"]:
            if t["club_id"] == cid and t["season"] == season+1 and t["direction"] == "out":
                q,s,ca = previous_stats.get(t["player_id"], ({},{},None))
                if s.get("starts",0) >= 10:
                    departures.append({**t, "previous_ca": ca, "previous_starts": s["starts"]})
        report["champion_transitions"].append({"unit":u["id"], "club_id":cid, "name":names.get(cid), "season":season,
            "next_regular_top3": any(r["club_id"]==cid for r in after.get("regular",[])),
            "before_ca":a["weighted_ca"], "after_ca":b["weighted_ca"], "missing_previous_top8":missing,
            "meaningful_departures":departures})

report["scope"] = "History records top three regular and top four playoff only; full past tables and transfer-time reputations are absent. Editor reputation is not proof of exact new-game reputation. Historical CA does not recover tactical attributes, morale, fatigue or match strength."
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("POOL",json.dumps(report["pools"],ensure_ascii=False))
print("CLUB REPUTATION",report["club_reputation"],"BUDGET",report["budgets"],"NEG",report["negative_budgets"])
print("TOP3", report["units"][0]["top3_appearances"])
print("CURRENT",[(names[r["club_id"]],r["points"]) for r in report["units"][0]["current_table"]])
