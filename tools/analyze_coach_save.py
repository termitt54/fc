"""Summarize a read-only save export and its season/player-offer audit."""
import argparse
import collections as co
import json
import statistics as st
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("snapshot", type=Path)
parser.add_argument("season_audit", type=Path)
parser.add_argument("offer_audit", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
p = json.loads((args.snapshot / "payload.json").read_text(encoding="utf-8"))
r = json.loads(args.season_audit.read_text(encoding="utf-8"))
offers = json.loads(args.offer_audit.read_text(encoding="utf-8"))
clubs = {int(k): v for u in p["units"] for k, v in u["clubs_by_id"].items()}
market = p["coach_market"]
events = market["events"]
employed = list(p["coaches_by_club"].values())
coaches = employed + market["free"] + market["retired"]
fired = co.Counter((e["club_id"], e["season"]) for e in events if e["reason"] == "dismissed")

def distribution(values):
    return {"min": min(values), "median": st.median(values), "max": max(values)} if values else {}

report = {
    "saved_at": p["saved_at"], "season": p["season_number"], "day": p["season_day"],
    "clubs": len(clubs), "employed": len(employed), "free": len(market["free"]),
    "retired": len(market["retired"]), "unique_coaches": len({q["id"] for q in coaches}),
    "duplicate_coach_ids": len(coaches) - len({q["id"] for q in coaches}),
    "clubs_without_coach": [k for k in clubs if str(k) not in p["coaches_by_club"]],
    "invalid_employed_club_ids": [q["id"] for cid, q in p["coaches_by_club"].items() if q["club_id"] != int(cid)],
    "unknown_event_coach_ids": sorted({e["coach_id"] for e in events} - {q["id"] for q in coaches}),
    "event_counts": dict(co.Counter(e["reason"] for e in events)),
    "dismissals_by_day": dict(sorted(co.Counter(e["day"] for e in events if e["reason"] == "dismissed").items())),
    "dismissals_per_club_season": dict(sorted(co.Counter(fired.values()).items())),
    "extreme_churn": [{"club": clubs[cid]["name"], "season": year, "dismissals": n}
                      for (cid, year), n in fired.items() if n >= 4],
    "employed_distributions": {key: distribution([q[key] for q in employed])
                               for key in ("age", "current_ability", "reputation", "contract_years", "wage")},
    "position_violations": [{"club": q["name"], "positions": q["position_violations"]}
                            for q in r["club_details"] if q["position_violations"]],
    "foreign_counts": dict(co.Counter(sum(q["nationality_country_id"] != clubs[int(cid)]["country_id"] for q in squad)
                                      for cid, squad in p["players_by_club"].items())),
    "free_elite": [{"id": q["id"], "name": q["name"], "ca": q["ca"], "age": q["age"],
                    "accepted_clubs": [o["club"] for o in q["options"] if o["accepted"]],
                    "refusal_reasons": dict(co.Counter(o["reason"] for o in q["options"] if not o["accepted"]))}
                   for q in offers["free_elite"]],
    "load_ms": offers["load_ms"], "units": [],
    "scope": "No original slots changed, no seasons advanced. Historical full tables and transfer-time reputations are not stored; CA is not complete match strength. Offer checks are hypothetical and do not bypass budgets, squad slots or foreign limits."
}
for u in r["units"]:
    history = u["history"]
    transitions = [t for t in r["champion_transitions"] if t["unit"] == u["id"]]
    drops = [t["after_ca"] - t["before_ca"] for t in transitions if t["after_ca"] is not None and t["before_ca"] is not None]
    report["units"].append({
        "name": u["name"], "completed_seasons": len(history),
        "regular_champions": len(u["regular_titles"]), "overall_champions": len(u["overall_titles"]),
        "regular_and_overall_same": u["regular_and_overall_same"],
        "repeat_regular": u["repeat_regular"], "repeat_overall": u["repeat_overall"],
        "last10_regular_champions": dict(co.Counter(h["regular"][0]["club_name"] for h in history[-10:])),
        "last10_overall_champions": dict(co.Counter(h["club_name"] for h in history[-10:])),
        "champion_next_regular_top3": sum(t["next_regular_top3"] for t in transitions),
        "champion_transitions": len(transitions), "largest_weighted_ca_drop": min(drops) if drops else None,
    })
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
