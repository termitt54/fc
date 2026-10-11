"""Read-only, consistent SQLite snapshots for the title diagnostic."""
import json
import sqlite3
from pathlib import Path
import os

source = Path(os.environ["APPDATA"]) / "Godot/app_userdata/Новый игровой проект"
destination = Path(__file__).resolve().parent / ".benchmark-runtime/user-snapshot"
destination.mkdir(parents=True, exist_ok=True)
metadata = {}
for relative in ("saves/games.db", "database/world.db", "saves/autosave_history.db"):
    path = source / relative
    if not path.exists():
        continue
    with sqlite3.connect(path.as_uri() + "?mode=ro", uri=True) as original:
        with sqlite3.connect(destination / path.name) as copy:
            original.backup(copy)
    metadata[relative] = {"bytes": (destination / path.name).stat().st_size}
with sqlite3.connect((destination / "games.db").as_uri() + "?mode=ro", uri=True) as db:
    db.row_factory = sqlite3.Row
    metadata["slots"] = [dict(row) for row in db.execute(
        "SELECT slot,version,saved_at,season_number,season_day,selected_unit_id,season_finished,player_count,unit_count FROM save_slots ORDER BY saved_at DESC"
    )]
(destination / "metadata.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps(metadata, ensure_ascii=False, indent=2))
