"""Rebuild world.db (countries, clubs, competition, unit, unit clubs) from a
session autosave, after the database was lost.

The session save embeds the full club rows and the unit's rule block, so almost
everything comes back exactly as it was. What the save never carried and cannot
be recovered: country names/abbreviations/reputation/youth_talent, club colours,
the competition card details, and the unit's discipline settings. Those fall
back to the values passed in below or to schema defaults, and must be checked
in the world editor afterwards.

Usage:
    python tools/recover_world_from_autosave.py <userdata_root> [--apply]

Without --apply it only reports what it would write.
"""
import json
import os
import shutil
import sqlite3
import sys
from datetime import datetime

# country_id -> (name, abbreviation). Derived from the club names in the save;
# reputation and youth_talent are genuinely lost and fall back to the default.
COUNTRIES = {
    1: ("Россия", "RUS"),
    2: ("Испания", "ESP"),
    3: ("Германия", "GER"),
    4: ("Англия", "ENG"),
}
CONTINENT_ID = 1  # Europe, the only continent these countries belong to.

# The competition card itself was not stored in the save.
COMPETITION_CODE = "ESL"
COMPETITION_SCOPE = "CONTINENTAL"
COMPETITION_PERIODICITY = "ANNUAL"
COMPETITION_START_SEASON = 1
COMPETITION_REPUTATION = 50

UNIT_COLUMNS = [
    "unit_kind", "name", "level", "competition_type", "sort_order",
    "foreign_players_limit", "logo_path", "divisions_count", "teams_per_division",
    "matches_vs_own", "matches_vs_other", "points_win", "points_draw", "points_loss",
    "teams_promote", "teams_relegate", "teams_playoff", "ranking_order",
    "regular_season_enabled", "movement_scope", "playoff_scope", "playoff_format",
    "playoff_series_wins", "playoff_third_place", "playoff_seeding",
]
CLUB_COLUMNS = [
    "country_id", "name", "short_name", "code", "logo_path", "reputation",
    "finance_level", "youth_academy", "training_level", "scouting_level",
    "youth_search", "stadium_capacity", "primary_color", "secondary_color",
    "is_active",
]


def now():
    return datetime.now().isoformat(timespec="seconds")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    root = sys.argv[1]
    apply_changes = "--apply" in sys.argv

    db_path = os.path.join(root, "database", "world.db")
    save_path = os.path.join(root, "saves", "autosave.json")
    for path in (db_path, save_path):
        if not os.path.exists(path):
            raise SystemExit("missing: %s" % path)

    save = json.load(open(save_path, encoding="utf-8"))
    units = save.get("units", [])
    if not units:
        raise SystemExit("the save carries no units")
    unit = units[0]
    clubs = unit["clubs_by_id"]
    rules = unit.get("rules", {})

    con = sqlite3.connect(db_path)
    con.execute("PRAGMA foreign_keys = ON;")
    for table in ("countries", "clubs", "competitions", "competition_units",
                  "competition_unit_clubs"):
        n = con.execute('select count(*) from "%s"' % table).fetchone()[0]
        if n:
            raise SystemExit(
                "%s already holds %d rows — refusing to touch a non-empty world"
                % (table, n))

    country_ids = sorted({int(c["country_id"]) for c in clubs.values()})
    print("will restore:")
    print("  countries  %d  %s" % (len(country_ids), country_ids))
    print("  clubs      %d" % len(clubs))
    print("  competition 1  %r" % unit.get("competition_name"))
    print("  unit        1  %r (%s)" % (unit.get("name"), unit.get("unit_kind")))
    print("  unit clubs %d" % len(clubs))
    if not apply_changes:
        print()
        print("dry run — pass --apply to write")
        return

    backup = db_path + ".before-recovery.bak"
    shutil.copy2(db_path, backup)
    print("backup written: %s" % backup)

    stamp = now()

    for cid in country_ids:
        name, abbr = COUNTRIES.get(cid, ("Страна %d" % cid, "C%02d" % cid))
        flag = "user://database/flags/country_%d.png" % cid
        if not os.path.exists(os.path.join(root, "database", "flags",
                                           "country_%d.png" % cid)):
            flag = None
        con.execute(
            "insert into countries (id, continent_id, name, abbreviation,"
            " flag_path, created_at, updated_at) values (?,?,?,?,?,?,?)",
            (cid, CONTINENT_ID, name, abbr, flag, stamp, stamp))

    for key in sorted(clubs, key=lambda k: int(k)):
        club = clubs[key]
        values = [club.get(col) for col in CLUB_COLUMNS]
        values[CLUB_COLUMNS.index("is_active")] = 1 if club.get("is_active", True) else 0
        con.execute(
            "insert into clubs (id, %s, created_at, updated_at) values (%s)"
            % (", ".join(CLUB_COLUMNS), ",".join("?" * (len(CLUB_COLUMNS) + 3))),
            [int(club["id"])] + values
            + [club.get("created_at") or stamp, club.get("updated_at") or stamp])

    con.execute(
        "insert into competitions (id, name, short_name, code, competition_type,"
        " scope_type, continent_id, periodicity, start_season, level, reputation,"
        " is_active, created_at, updated_at)"
        " values (?,?,?,?,?,?,?,?,?,?,?,1,?,?)",
        (int(unit.get("competition_id", 1)),
         unit.get("competition_name") or "Соревнование",
         unit.get("competition_short_name") or None,
         COMPETITION_CODE,
         unit.get("competition_type") or "DIVISIONS",
         COMPETITION_SCOPE, CONTINENT_ID, COMPETITION_PERIODICITY,
         COMPETITION_START_SEASON, int(rules.get("level", 1)),
         COMPETITION_REPUTATION, stamp, stamp))

    unit_values = []
    for col in UNIT_COLUMNS:
        value = rules.get(col)
        if col == "ranking_order" and isinstance(value, list):
            value = json.dumps(value)
        elif col in ("regular_season_enabled", "playoff_third_place"):
            value = 1 if value else 0
        unit_values.append(value)
    con.execute(
        "insert into competition_units (id, competition_id, %s, created_at,"
        " updated_at) values (%s)"
        % (", ".join(UNIT_COLUMNS), ",".join("?" * (len(UNIT_COLUMNS) + 4))),
        [int(unit["id"]), int(unit.get("competition_id", 1))] + unit_values
        + [rules.get("created_at") or stamp, rules.get("updated_at") or stamp])

    for key in sorted(clubs, key=lambda k: int(k)):
        con.execute(
            "insert into competition_unit_clubs (unit_id, club_id, created_at)"
            " values (?,?,?)", (int(unit["id"]), int(clubs[key]["id"]), stamp))

    con.commit()
    print()
    print("restored:")
    for table in ("countries", "clubs", "competitions", "competition_units",
                  "competition_unit_clubs"):
        print("  %-24s %d" % (table,
              con.execute('select count(*) from "%s"' % table).fetchone()[0]))
    print()
    print("check in the world editor — these could not be recovered:")
    print("  countries: reputation, youth_talent (reset to 500), names/abbreviations")
    print("  competition card: code, scope, periodicity, start season, reputation")
    print("  unit: discipline settings (cards, bans) fell back to defaults")


if __name__ == "__main__":
    main()
