"""Analyse a diagnostic JSON export, including immutable retired careers."""
import argparse
import collections
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("snapshot", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
p = json.loads((args.snapshot / "payload.json").read_text(encoding="utf-8"))
archive = json.loads((args.snapshot / "archive.json").read_text(encoding="utf-8"))
players = {}
for pool in ("players_by_club", "reserve_players_by_club", "youth_players_by_club"):
    for squad in p[pool].values():
        players.update({q["id"]: q for q in squad})
players.update({q["id"]: q for q in p["free_agents"]})
players.update({r["player"]["id"]: r["player"] for r in archive})
stats = collections.defaultdict(list)
for q in players.values():
    for s in q.get("career_stats", []) + [q.get("season_stats", {})]:
        if s.get("minutes", 0) > 0:
            ca = next((h["ca"] for h in q.get("development_history", []) if h["season"] == s["season"]), None)
            stats[(s["club_id"], s["season"])].append((q, s, ca))
u = p["units"][0]
names = {int(cid): c["name"] for cid, c in u["clubs_by_id"].items()}
report = {"saved_at": p["saved_at"], "season": p["season_number"], "retired": len(archive), "history": u["winners"], "clubs": []}
for cid, name in names.items():
    seasons = []
    for sn in range(1, p["season_number"] + 1):
        arr = stats[(cid, sn)]
        valid = [(q, s, ca) for q, s, ca in arr if ca is not None]
        minutes = sum(s["minutes"] for q, s, ca in valid)
        top = sorted(arr, key=lambda x: x[1].get("starts", 0), reverse=True)[:8]
        seasons.append({"season": sn, "players": len(arr), "minutes": sum(s["minutes"] for q, s, ca in arr),
            "ca_coverage_minutes": minutes,
            "minute_weighted_ca": sum(ca*s["minutes"] for q, s, ca in valid)/max(minutes, 1),
            "top_starters": [{"id": q["id"], "name": q["name"], "position": q["position"], "ca": ca,
                "starts": s.get("starts", 0), "minutes": s["minutes"]} for q, s, ca in top]})
    transitions = []
    for sn in range(2, p["season_number"] + 1):
        prev = {q["id"]: (q, s, ca) for q, s, ca in stats[(cid, sn-1)]}
        departures = []
        for t in p["transfer_log"]:
            if t["club_id"] != cid or t["season"] != sn or t["direction"] != "out":
                continue
            q, s, ca = prev.get(t["player_id"], ({}, {}, None))
            departures.append({**t, "previous_ca": ca, "previous_starts": s.get("starts", 0), "previous_minutes": s.get("minutes", 0)})
        previous_top = {r["id"] for r in seasons[sn-2]["top_starters"]}
        next_players = {q["id"] for q, s, ca in stats[(cid, sn)]}
        transitions.append({"season": sn, "previous_top8_played_again": len(previous_top & next_players), "departures": departures})
    report["clubs"].append({"id": cid, "name": name, "seasons": seasons, "transitions": transitions})
args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
for c in report["clubs"]:
    if c["id"] in (56,64,68,41,33,49,52):
        print(c["name"], [(s["season"], round(s["minute_weighted_ca"],2), s["ca_coverage_minutes"] == s["minutes"]) for s in c["seasons"][-3:]])
        t = c["transitions"][-1]
        print("top8 returned", t["previous_top8_played_again"], "meaningful departures", [(r["player_id"], r["previous_ca"], r["previous_starts"], r["fee"]) for r in t["departures"] if r["previous_starts"] >= 10])
