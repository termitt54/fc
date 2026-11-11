"""Analyze an exported copied save, including national talent and retired careers."""
import collections as co
import json
import sqlite3
import statistics as st
import sys
from pathlib import Path

folder = Path(sys.argv[1]).resolve()
p = json.loads((folder / "payload.json").read_text(encoding="utf-8"))
archive = json.loads((folder / "archive.json").read_text(encoding="utf-8"))
inspection = json.loads((folder / "inspection.json").read_text(encoding="utf-8"))
db = sqlite3.connect((folder / "world.db").as_uri() + "?mode=ro", uri=True)
db.row_factory = sqlite3.Row
countries = {r["id"]: dict(r) for r in db.execute("SELECT id,name,reputation,youth_talent FROM countries")}
db.close()
club_units = [u for u in p["units"] if not u.get("national", False)]
clubs = {int(cid): c for u in club_units for cid, c in u["clubs_by_id"].items()}
active = [q for k in ("players_by_club", "reserve_players_by_club", "youth_players_by_club") for squad in p[k].values() for q in squad] + p["free_agents"]
players = {r["identity"]["player_id"]: r.get("player", {}) for r in archive}
players.update({q["id"]: q for q in active})

def mean(values):
    return round(st.mean(values), 2) if values else None

def distribution(values):
    return {"count": len(values), "min": min(values), "median": st.median(values), "mean": mean(values), "max": max(values)} if values else {}

report = {"season": p["season_number"], "day": p["season_day"], "saved_at": p["saved_at"],
          "clubs": len(clubs), "active_players": len(active), "retired_players": len(archive),
          "duplicate_active_ids": len(active)-len({q["id"] for q in active}), "load_ms": inspection["load_ms"],
          "country_talent_range": distribution([c["youth_talent"] for c in countries.values()]),
          "clubs_reputation": distribution([c["reputation"] for c in clubs.values()]),
          "negative_budgets": sum(v < 0 for v in p["club_budgets"].values()),
          "free_agents": len(p["free_agents"]), "free_ca80_plus": [], "countries": [], "competitions": []}
for q in p["free_agents"]:
    if q.get("current_ability", 0) >= 80:
        report["free_ca80_plus"].append({k: q.get(k) for k in ("id", "name", "age", "current_ability", "reputation", "nationality_country_id", "free_agent_seasons")})
for cid, country in countries.items():
    qs = [q for q in active if q.get("nationality_country_id") == cid]
    seniors = sorted([q["current_ability"] for q in qs if not q.get("is_youth", False)], reverse=True)
    potential = [q["potential_ability"] for q in players.values() if q.get("nationality_country_id") == cid]
    youth = [q["potential_ability"] for q in qs if q.get("age", 100) <= 17]
    report["countries"].append({"id": cid, "name": country["name"], "talent": country["youth_talent"],
        "clubs": sum(c["country_id"] == cid for c in clubs.values()), "players": len(qs),
        "top8_ca": seniors[:8], "top8_mean": mean(seniors[:8]), "top25_mean": mean(seniors[:25]),
        "all_generated_pa": distribution(potential), "pa80_plus_pct": round(100*sum(v>=80 for v in potential)/len(potential), 2) if potential else None,
        "youth_pa": distribution(youth)})
for u in p["units"]:
    history = sorted(u.get("winners", []), key=lambda h: h["season"])
    regular = [h.get("regular", [{}])[0].get("club_name", "?") for h in history if h.get("regular")]
    playoff = [h.get("club_name", "?") for h in history]
    def leaders(values):
        return co.Counter(values).most_common()
    report["competitions"].append({"name": u["name"], "national": u.get("national", False),
        "seasons": len(history), "regular_titles": leaders(regular), "playoff_titles": leaders(playoff),
        "regular_unique": len(set(regular)), "playoff_unique": len(set(playoff)),
        "last10_regular": leaders(regular[-10:]), "last10_playoff": leaders(playoff[-10:]),
        "repeat_regular": sum(a==b for a,b in zip(regular,regular[1:])),
        "repeat_playoff": sum(a==b for a,b in zip(playoff,playoff[1:]))})
profile = inspection["profile"]
report["player10098"] = {k: profile.get(k) for k in ("id", "name", "age", "retired_season", "current_ability", "potential_ability")}
career = profile.get("career_stats", []) + [profile.get("season_stats", {})]
report["player10098"]["matches"] = sum(s.get("matches",0) for s in career)
report["player10098"]["goals"] = sum(s.get("goals",0) for s in career)
report["player10098"]["career_clubs"] = sorted({s.get("club_id") for s in career if s.get("matches",0)>0})
report["historical_logos_outside_current_league"] = sum(not q["local"] for q in inspection["logos"])
report["historical_logos_without_identity_path"] = sum(not q["path"] for q in inspection["logos"])
employed = list(p["coaches_by_club"].values()) + [t["coach"] for t in p.get("national_teams", {}).values()]
market = p.get("coach_market", {})
coaches = employed + market.get("free", []) + market.get("retired", [])
report["duplicate_coach_ids"] = len(coaches)-len({c["id"] for c in coaches})
report["coaches_employed"] = len(employed)
report["country_club_double_jobs"] = sum(c.get("club_id",0)>0 and c.get("national_team_id",0)>0 for c in coaches)
report["position_violations"] = []
bounds = {"GK": (2,3), "CB": (3,4), "FB": (4,5), "CM": (3,4), "WM": (4,5), "ST": (3,4), "WF": (4,5)}
for cid, club in clubs.items():
    squad = p["players_by_club"].get(str(cid), [])
    counts = co.Counter(q["position"] for q in squad)
    violations = {pos: counts[pos] for pos,(lo,hi) in bounds.items() if not lo<=counts[pos]<=hi}
    if violations:
        report["position_violations"].append({"club": club["name"], "size": len(squad), "positions": violations})
stats = co.defaultdict(list)
for player in players.values():
    development = {r["season"]: r["ca"] for r in player.get("development_history", [])}
    for row in player.get("career_stats", []) + [player.get("season_stats", {})]:
        if row.get("minutes", 0)>0 and row.get("season") in development:
            stats[(row["club_id"], row["season"])].append((row["minutes"],development[row["season"]]))
def strength(cid, season):
    rows = stats[(cid,season)]
    return sum(m*ca for m,ca in rows)/sum(m for m,_ in rows) if rows else None
report["champion_transitions"] = []
for u in club_units:
    history = sorted(u.get("winners", []), key=lambda h:h["season"])
    for before,after in zip(history,history[1:]):
        cid = before["club_id"]
        first = strength(cid,before["season"])
        second = strength(cid,after["season"])
        report["champion_transitions"].append({"league":u["name"], "season":before["season"], "club_id":cid,
            "name":before.get("club_name"), "before_ca":first, "after_ca":second,
            "change": round(second-first,2) if first is not None and second is not None else None,
            "next_top3":any(q["club_id"]==cid for q in after.get("regular",[]))})
report["dismissals_per_club_season"] = dict(co.Counter(co.Counter((e["club_id"],e["season"]) for e in market.get("events",[]) if e.get("reason")=="dismissed" and e.get("club_id",0)>0).values()))
report["pool_counts"] = {k:len(p[k]) if k=="free_agents" else sum(len(s) for s in p[k].values()) for k in ["players_by_club","reserve_players_by_club","youth_players_by_club","free_agents"]}
report["scope"] = "Country talent is the current editor value, not its historical value. National top8/top25 are raw available CA, not role-balanced match strength. Same-country club count sets intake volume. Original database unchanged."
(folder / "national-audit.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(report, ensure_ascii=False, indent=2))
