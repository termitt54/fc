"""Read-only analysis of exported national editions and historical player CA."""
import collections as co
import json
import statistics as st
import sys
from pathlib import Path

root = Path(sys.argv[1])
read = lambda name: json.loads((root / name).read_text(encoding="utf-8"))
p, archives, editions = read("payload.json"), read("archive.json"), read("national_editions.json")
players, retired = {}, {}
for record in archives:
    pid = int(record["identity"]["player_id"])
    players[pid] = record["player"]
    retired[pid] = int(record["identity"]["retired_season"])
for key in ("players_by_club", "reserve_players_by_club", "youth_players_by_club"):
    for pool in p[key].values():
        players.update({int(x["id"]): x for x in pool})
players.update({int(x["id"]): x for x in p["free_agents"]})
hist = {pid: {int(r["season"]): int(r["ca"]) for r in x.get("development_history", [])} for pid, x in players.items()}
by_country = co.defaultdict(list)
for pid, x in players.items():
    by_country[int(x["nationality_country_id"])].append(pid)
coaches = {}
for c in list(p["coaches_by_club"].values()) + [n["coach"] for n in p["national_teams"].values()] + p["coach_market"]["free"] + p["coach_market"]["retired"]:
    if c.get("id") not in coaches or len(c.get("career", [])) > len(coaches[c["id"]].get("career", [])):
        coaches[c["id"]] = c

def ca(pid, season):
    return hist.get(pid, {}).get(season)

def coach_for(cid, season, day):
    for c in coaches.values():
        for job in c.get("career", []):
            if int(job.get("national_team_id", 0)) != cid:
                continue
            start = (int(job["season_from"]), int(job.get("day_from", -5)))
            end = (int(job.get("season_to", 0)), int(job.get("day_to", 999))) if job.get("season_to", 0) else (99999, 99999)
            if start <= (season, day) <= end:
                return {k: c.get(k) for k in ("id", "name", "attributes", "primary_style", "primary_formation", "current_ability")}
    return {}

report = {"season": p["season_number"], "day": p["season_day"], "editions": []}
for u in editions:
    season = int(u["season"])
    first_day = min(m["season_day"] for m in u["matches"])
    teams = {}
    stats = u["season_player_stats"]
    qualifiers = {int(s[k]) for s in u["playoff"]["series"] for k in ("home_id", "away_id") if int(s.get(k, 0)) > 0}
    for tid, identity in u["clubs_by_id"].items():
        tid, cid = int(tid), int(tid) - 1000000000
        eligible = [pid for pid in by_country[cid] if ca(pid, season) is not None and retired.get(pid, 99999) >= season]
        played = [(int(pid), r) for pid, r in stats.items() if int(r["club_id"]) == tid and int(r.get("minutes", 0)) > 0]
        covered = [(pid, r) for pid, r in played if ca(pid, season) is not None]
        minutes = sum(int(r["minutes"]) for pid, r in covered)
        weighted = sum(ca(pid, season) * int(r["minutes"]) for pid, r in covered) / minutes if minutes else None
        keepers = [(pid, r) for pid, r in covered if players[pid]["position"] == "GK"]
        gkmins = sum(r["minutes"] for pid, r in keepers)
        best = sorted([ca(pid, season) for pid in eligible], reverse=True)
        stage = "group"
        if tid in qualifiers:
            deepest = max(int(s["round"]) for s in u["playoff"]["series"] if tid in (s.get("home_id"), s.get("away_id")) and not s.get("is_third_place"))
            stage = "round_%d" % deepest
        medals = u["winners"][0].get("playoff", [])
        for medal in medals:
            if int(medal["club_id"]) == tid:
                stage = "place_%d" % medal["place"]
        standing = next(s for s in u["standings"] if int(s["club_id"]) == tid)
        teams[tid] = {"id": tid, "name": identity["name"], "talent": identity.get("youth_talent"), "stage": stage,
            "points": standing["points"], "gf": standing["goals_for"], "ga": standing["goals_against"], "group": standing["division"],
            "played_ca": round(weighted, 2) if weighted else None, "top8_pool_ca": round(st.mean(best[:8]), 2) if best else None,
            "eligible": len(eligible), "used": len(played), "coverage": len(covered),
            "keeper_ca": round(sum(ca(pid, season) * r["minutes"] for pid, r in keepers) / gkmins, 2) if gkmins else None,
            "coach": coach_for(cid, season, first_day), "players": [{"id": pid, "ca": ca(pid, season), "position": players[pid]["position"], "minutes": r["minutes"]} for pid, r in covered]}
    ranked = sorted(teams.values(), key=lambda x: x["played_ca"] or 0, reverse=True)
    for rank, team in enumerate(ranked, 1):
        team["ca_rank"] = rank
    matches = []
    for m in u["matches"]:
        matches.append({k: m.get(k) for k in ("home_id", "away_id", "home_goals", "away_goals", "winner_id", "shootout", "extra_time", "stage", "season_day")})
    edition = {"season": season, "teams": list(teams.values()), "matches": matches, "champion": u["playoff"]["champion_id"]}
    report["editions"].append(edition)
    champion = teams[int(edition["champion"])]
    print("SEASON", season, "CHAMP", champion["name"], "ca", champion["played_ca"], "rank", champion["ca_rank"], "coach", champion["coach"].get("primary_style"), champion["coach"].get("attributes"))
    print("TOP", [(x["name"], x["played_ca"], x["stage"]) for x in ranked[:6]])
    for cid in [1, 5, 23, 31]:
        team = teams.get(1000000000 + cid)
        if team:
            print("WATCH", team["name"], team["played_ca"], "pool", team["top8_pool_ca"], team["stage"], team["coach"].get("primary_style"))
(root / "national_stability_report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

# Fresh-state diagnostics, not an attempted replay of historical matches.
import copy
import os
last = report["editions"][-1]
fixture = {"season": last["season"], "teams": {}}
for team in last["teams"]:
    if team["name"] not in {"Russia", "Scotland", "Serbia", "Portugal", "Slovakia"}:
        continue
    cid = team["id"] - 1000000000
    squad = []
    for pid in p["national_teams"][str(cid)]["squad_ids"]:
        player = copy.deepcopy(players[int(pid)])
        if ca(int(pid), last["season"]) is None:
            continue
        if max(hist[int(pid)]) == last["season"] + 1:
            for group, changes in player.get("development_deltas", {}).items():
                for key, delta in changes.items():
                    player["attributes"][group][key] -= delta
        player["current_ability"] = ca(int(pid), last["season"])
        player.update(condition=100, morale=50, injury_rounds=0, suspension_matches=0,
                      _national_selection=True, _national_form_bonus=0)
        squad.append(player)
    coach = copy.deepcopy(coaches[int(team["coach"]["id"])])
    coach["national_selection"] = True
    fixture["teams"][team["name"]] = {"club_id": team["id"], "squad": squad, "youth": [], "coach": coach}
config_path = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Новый игровой проект/config/match_simulation.json"
fixture["knobs"] = json.loads(config_path.read_text(encoding="utf-8"))["values"]
(root / "fresh_match_fixture.json").write_text(json.dumps(fixture, ensure_ascii=False), encoding="utf-8")
