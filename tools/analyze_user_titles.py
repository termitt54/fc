"""Summarize measured title outcomes; does not modify gameplay or save files."""
import json
from collections import Counter
from pathlib import Path
from statistics import mean, median

root = Path(__file__).resolve().parent.parent
results = root / "tests/performance/results"
report = json.loads((results / "user-title-stability.json").read_text(encoding="utf-8-sig"))
names = {c["id"]: c["name"] for c in report["snapshot_clubs"]}

def title_summary(outcomes):
    regular = [r["regular_champion"] for r in outcomes]
    champions = [r["champion"] for r in outcomes]
    return {
        "runs": len(outcomes),
        "regular_titles": {names[k]: v for k, v in Counter(regular).most_common()},
        "playoff_titles": {names[k]: v for k, v in Counter(champions).most_common()},
        "same_winner": sum(a == b for a, b in zip(regular, champions)),
        "regular_repeat": sum(a == b for a, b in zip(regular, regular[1:])),
        "playoff_repeat": sum(a == b for a, b in zip(champions, champions[1:])),
        "gap12_mean": mean(r["table"][0]["points"] - r["table"][1]["points"] for r in outcomes),
        "gap12_median": median(r["table"][0]["points"] - r["table"][1]["points"] for r in outcomes),
    }

def rank_changes(outcomes):
    shifts = []
    for prev, cur in zip(outcomes, outcomes[1:]):
        ranks = {p["club_id"]: i + 1 for i, p in enumerate(prev["table"])}
        shifts += [abs(i + 1 - ranks[p["club_id"]]) for i, p in enumerate(cur["table"])]
    return {"mean_absolute_rank_change": mean(shifts), "max_rank_change": max(shifts)}

summary = {"source": {k: report["source"][k] for k in ("season", "day", "saved_at", "name", "clubs")},
           "frozen": [], "dynamic": [], "errors": report["errors"]}
history = report["source"]["history"]
gaps = [r["regular"][0]["points"] - r["regular"][1]["points"] for r in history]
summary["observed_history"] = {"seasons": len(history), "gap12_mean": mean(gaps),
    "gap12_median": median(gaps), "gap12_at_most_4": sum(x <= 4 for x in gaps)}
for series in report["frozen"]:
    summary["frozen"].append({"playoffs": series["playoffs"], **title_summary(series["outcomes"]),
                               **rank_changes(series["outcomes"])})
if len(report["frozen"]) == 2:
    a, b = [s["outcomes"] for s in report["frozen"]]
    summary["paired_regular_tables_equal"] = all(x["table"] == y["table"] for x, y in zip(a, b))
    summary["paired_runs"] = min(len(a), len(b))
for branch in report["dynamic"]:
    seasons = branch["seasons"]
    row = {"seed": branch["seed"], **title_summary(seasons), "seasons": []}
    shifts = []
    for prev, cur in zip(seasons, seasons[1:]):
        ranks = {p["club_id"]: i + 1 for i, p in enumerate(prev["table"])}
        shifts += [abs(i + 1 - ranks[p["club_id"]]) for i, p in enumerate(cur["table"])]
    retained = [c["retained"] for s in seasons[1:] for c in s["clubs"]]
    row["mean_absolute_rank_change"] = mean(shifts)
    row["max_rank_change"] = max(shifts)
    row["mean_retained_out_of_25"] = mean(retained)
    row["position_violation_records"] = sum(bool(c["positions_outside_limits"]) or c["size"] != 25
                                            for s in seasons for c in s["clubs"])
    initial_coaches = {c["id"]: c["coach"] for c in seasons[0]["clubs"]}
    row["changed_coach_records"] = sum(c["coach"] != initial_coaches[c["id"]] for s in seasons for c in s["clubs"])
    for season in seasons:
        clubs = season["clubs"]
        row["seasons"].append({"season": season["season"], "regular": names[season["regular_champion"]],
            "playoff": names[season["champion"]],
            "ca_min": min(c["primary_xi_ca"] for c in clubs), "ca_max": max(c["primary_xi_ca"] for c in clubs),
            "selection_min": min(c["primary_xi_selection"] for c in clubs),
            "selection_max": max(c["primary_xi_selection"] for c in clubs),
            "negative_budgets": sum(c["budget"] < 0 for c in clubs)})
    summary["dynamic"].append(row)
summary["baseline"] = {"season": report["baseline_season"],
    "ca_min": min(c["primary_xi_ca"] for c in report["baseline_clubs"]),
    "ca_max": max(c["primary_xi_ca"] for c in report["baseline_clubs"]),
    "selection_top": sorted(report["baseline_clubs"], key=lambda c: c["primary_xi_selection"], reverse=True)[:5]}
summary["elapsed_seconds"] = report["elapsed_seconds"]
summary["scope"] = report["scope"]
(results / "user-title-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(summary, ensure_ascii=False, indent=2))
