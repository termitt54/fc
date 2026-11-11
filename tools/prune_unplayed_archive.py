"""Remove exported never-played retirees from one saved branch, with a verified backup.

The folder must contain a consistent snapshot and full_save_export retired.jsonl.
Dry-run is the default. This never deletes active players, tournament history,
transfer rows, saved slots or other history branches.
"""
import argparse
import json
import sqlite3
from pathlib import Path

parser=argparse.ArgumentParser()
parser.add_argument('snapshot',type=Path)
parser.add_argument('--database',type=Path)
parser.add_argument('--apply',action='store_true')
parser.add_argument('--vacuum',action='store_true')
args=parser.parse_args()
folder=args.snapshot.resolve();backup=folder/'games.db'
target=args.database.resolve() if args.database else folder/'games-cleaned.db'
meta=json.loads((folder/'metadata.json').read_text(encoding='utf8'))['slots'][0]
payload=json.loads((folder/'payload.json').read_text(encoding='utf8'))
ids=[]
for raw in (folder/'retired.jsonl').open(encoding='utf8'):
    row=json.loads(raw)
    # Preserve national-only careers and incomplete legacy minutes/statistics.
    fields=['matches','starts','minutes','goals','assists','saves','conceded','clean_sheets','yellow','red','pen_scored','pen_missed','pen_saved','motm','shots','on_target','passes','completed_passes','receipts','miscontrols','dribbles','successful_dribbles','tackles','interceptions','blocks','aerial_wins','crosses','completed_crosses','distance_metres','rating_sum']
    rows=[row]+row.get('national_stats',[])
    if not any(float(r.get(k,0))>0 for r in rows for k in fields):ids.append(int(row['player_id']))
if target==backup:raise RuntimeError('The backup must never be modified')
if not target.exists():
    if not args.apply:raise RuntimeError('For dry-run, pass an existing --database')
    with sqlite3.connect(backup.as_uri()+'?mode=ro',uri=True) as src,sqlite3.connect(target) as dst:src.backup(dst)
with sqlite3.connect(backup.as_uri()+'?mode=ro',uri=True) as src:
    expected=src.execute('select saved_at,history_head from save_slots where slot=?',(meta['slot'],)).fetchone()
    if expected!=(payload['saved_at'],payload['history_head']):raise RuntimeError('Backup/export mismatch')
mode='rw' if args.apply else 'ro'
with sqlite3.connect(target.as_uri()+'?mode='+mode,uri=True,timeout=3) as db:
    current=db.execute('select saved_at,history_head from save_slots where slot=?',(meta['slot'],)).fetchone()
    if current!=expected:raise RuntimeError('Save changed since export; take a fresh snapshot')
    print('Checking candidate careers against the saved branch...',flush=True)
    db.execute('CREATE TEMP TABLE prune_ids(id INTEGER PRIMARY KEY)')
    db.executemany('insert into prune_ids values(?)',[(i,) for i in ids])
    db.execute('CREATE TEMP TABLE prune_ancestry(id INTEGER PRIMARY KEY)')
    db.execute('WITH RECURSIVE a(id) AS (SELECT ? UNION ALL SELECT n.parent_id FROM save_history_nodes n JOIN a ON n.id=a.id WHERE n.parent_id IS NOT NULL) INSERT INTO prune_ancestry SELECT id FROM a',(payload['history_head'],))
    predicate='history_id in (select id from prune_ancestry) and player_id in (select id from prune_ids) and matches=0'
    count,size=db.execute('select count(*),coalesce(sum(length(body)),0) from save_history_players where '+predicate).fetchone()
    before=db.execute('select count(*),sum(matches),sum(goals),sum(assists) from save_history_players').fetchone()
    report={'database':str(target),'backup':str(backup),'slot':meta['slot'],'head':payload['history_head'],'candidates':len(ids),'records_to_remove':count,'body_bytes':size,'applied':False,'file_bytes_before':target.stat().st_size}
    db.commit()
    if args.apply:
        print(f'Removing {count} unplayed careers; played-career aggregates will be verified.',flush=True)
        db.execute('BEGIN IMMEDIATE')
        # Recheck under the write lock to avoid cleaning a newly saved branch.
        if db.execute('select saved_at,history_head from save_slots where slot=?',(meta['slot'],)).fetchone()!=expected:raise RuntimeError('Concurrent save; cleanup aborted')
        db.execute('delete from save_history_players where '+predicate)
        after=db.execute('select count(*),sum(matches),sum(goals),sum(assists) from save_history_players').fetchone()
        if before[0]-after[0]!=count or before[1:]!=after[1:]:raise RuntimeError('Played career aggregates changed; rollback')
        db.commit();report['applied']=True
        if args.vacuum:
            print('Compacting SQLite database...',flush=True)
            db.execute('PRAGMA wal_checkpoint(TRUNCATE)');db.execute('VACUUM');db.execute('PRAGMA wal_checkpoint(TRUNCATE)')
        print('Checking SQLite integrity...',flush=True)
        report['quick_check']=db.execute('PRAGMA quick_check').fetchone()[0]
        if report['quick_check']!='ok':raise RuntimeError('SQLite check failed; restore the verified backup')
    report['file_bytes_after']=target.stat().st_size
print(json.dumps(report,ensure_ascii=False,indent=2))
if args.apply:(folder/('prune-'+('source' if args.database else 'copy')+'-result.json')).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
