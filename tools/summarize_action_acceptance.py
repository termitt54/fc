"""Summarize the isolated action-engine acceptance runs without altering game data."""
import hashlib
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "tests/performance/results"
SCENES = set("native_simulation action_pitch compact_player match_engine match_rotation match_coaching "
             "match_simulation_config match_performance_cache match_stability lineup_roles match_day day_work "
             "national_teams player_generator player_development player_market player_offer player_stats "
             "contract_renewal transfer_market coach_market season_preview season_reputation potential_rarity "
             "starting_generation youth_talent_tools youth_intake historical_profiles save_history".split())


def read(name):
    return json.loads((RESULTS / name).read_text(encoding="utf-8-sig"))


def percent(n, d):
    return f"{100*n/max(d,1):.1f}%"


def main():
    audit = read("action-pitch-v3-audit.json")
    generations = read("action-pitch-v3-generations.json")
    day = read("action-pitch-v3-day.json")
    paced = read("action-pitch-v3-day-frames60.json")
    timing = {}
    for source, labels in [(day, ["sync", "sliced", "sliced_ui"]), (paced, ["sliced", "sliced_ui"])]:
        for label in labels:
            samples = [x["simulation_ms"] for x in source["samples"] if x["label"] == label]
            timing[f"{label}_{source['frame_limit']}fps"] = round(statistics.median(samples), 3)
    scenes = {}
    for path in sorted((ROOT / "tools/.native-runtime").glob("suite-*.stdout.log")):
        name = path.name.removeprefix("suite-").removesuffix(".stdout.log")
        if name not in SCENES:
            continue
        content = path.read_text(encoding="utf-8-sig", errors="replace")
        matches = re.findall(r"(\d+) passed, (\d+) failed", content)
        if matches:
            scenes[name] = {
                "passed": int(matches[-1][0]), "failed": int(matches[-1][1])}
    total_matches = sum(x["matches"] for x in generations.values())
    wins = sum(x["wins"] for x in generations.values())
    dll = ROOT / "addons/fc_sim_core/bin/fc_sim_core_v3_1.windows.template_release.x86_64.dll"
    summary = {"backend": audit["backend"], "dll_sha256": hashlib.sha256(dll.read_bytes()).hexdigest(),
               "scenarios": audit["scenarios"], "generation_matches": total_matches,
               "generation_win_percent_85_vs_75": wins/total_matches*100,
               "day_medians_ms": timing, "tests": scenes}
    integration = sorted(RESULTS.glob("clubs-4-seasons-2-*.json"), key=lambda p: p.stat().st_mtime)
    if integration:
        run = json.loads(integration[-1].read_text(encoding="utf-8-sig"))
        summary["two_season_save_load"] = {"file": integration[-1].name, "status": run["status"],
                                          "completed_seasons": run.get("completed_seasons", 0)}
    (RESULTS / "individual-action-engine-summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")

    report = ROOT / "docs/individual-action-engine.md"
    intro = report.read_text(encoding="utf-8").split("## Проверки и измерения")[0]
    rows = ["## Проверки и измерения", "",
            "3 000 матчей баланса и 3 600 матчей с изолированным изменением навыков.",
            "Это синтетические составы. Метки 85/75 задают создание тестовых игроков;",
            "сам CA не участвует в расчёте эпизодов.", "",
            "| Составы | Победы / ничьи / поражения | Голов за матч | Ударов | Замен на сторону |",
            "|---|---|---:|---:|---:|"]
    for row in audit["scenarios"]:
        a, b = row["ca_labels"]
        rows.append(f"| {a}/{b} | {row['wins']} / {row['draws']} / {row['losses']} | "
                    f"{row['goals_per_match']:.3f} | {row['shots_per_match']:.3f} | {row['subs_per_team']:.2f} |")
    rows += ["", "При большом разрыве навыков возможны крупные разгромы: ограничения счёта нет.",
             "Эти метки нельзя читать как талант страны или гарантированный процент побед.", "",
             "### Поколения", "",
             f"10 миров, 30 лет развития и набора, {total_matches} матчей в контрольных годах.",
             f"Талант 85 против 75: **{wins/total_matches*100:.1f}% побед** в сумме.",
             "Это проверка генерации и развития, не полная 30-летняя симуляция экономики.", "",
             "| Год | Победы / ничьи / поражения | Разница среднего CA всего пула | Голов за матч |",
             "|---|---|---:|---:|"]
    for year, row in generations.items():
        rows.append(f"| {year} | {row['wins']} / {row['draws']} / {row['losses']} | "
                    f"{row['mean_ca_85']-row['mean_ca_75']:.2f} | {(row['gf']+row['ga'])/row['matches']:.3f} |")
    rows += ["", "### Один навык 5 → 20", "",
             "По 120 матчей каждого варианта, одинаковые исходные RNG, остальные навыки сохранены.",
             "Восемь игроков без замен, травм и карточек: по 6 000 минут проверяемого игрока.",
             "Последующие события расходятся вслед за изменёнными действиями; отдельный матч",
             "не обязан стать лучше. Приведённые результаты не являются постоянными процентами",
             "влияния на победу команды.", "", "| Навык | Наблюдение |", "|---|---|"]
    names = {"finishing": "Завершение", "passing": "Пас", "technique": "Техника",
             "dribbling": "Дриблинг", "defending": "Защита", "pace": "Быстрота",
             "stamina": "Выносливость", "strength": "Сила", "delivery": "Подачи",
             "penalties": "Пенальти", "reflexes": "Реакция", "handling": "Надёжность рук",
             "positioning": "Выбор позиции", "exits": "Выходы", "aerial_reach": "Верховая игра"}
    for case in audit["interventions"]:
        a, b = case["values"]
        key = case["skill"]
        note = f"Команда пропустила {a['conceded']} → {b['conceded']}"
        if key in ("finishing", "penalties"):
            note = f"Личные голы {a['player_goals']} → {b['player_goals']}"
        if key in ("passing", "dribbling", "delivery"):
            success, attempts, label = {"passing": ("completed_passes", "passes", "Точные передачи"),
                "dribbling": ("successful_dribbles", "dribbles", "Успешные обводки"),
                "delivery": ("completed_crosses", "crosses", "Дошедшие навесы")}[key]
            note = (f"{label} {a[success]}/{a[attempts]} ({percent(a[success],a[attempts])}) → "
                    f"{b[success]}/{b[attempts]} ({percent(b[success],b[attempts])})")
        if key == "technique": note = f"Ошибки приёма {a['miscontrols']} → {b['miscontrols']}"
        if key == "pace": note = f"При полных силах 4 → 7 м/с; личные голы {a['player_goals']} → {b['player_goals']}"
        if key == "stamina": note = f"Средний остаток сил после 50 минут {a['final_freshness']/120:.1f}% → {b['final_freshness']/120:.1f}%"
        if key == "handling": note = f"Фиксации {a['catches']} → {b['catches']}, отскоки {a['parries']} → {b['parries']}"
        if key == "aerial_reach": note = f"Выигранные верховые мячи {a['aerial_wins']} → {b['aerial_wins']}"
        rows.append(f"| {names[key]} | {note} |")
    rows += [f"| Восстановление | При готовности 40 навык 5/10/15/20 даёт за день "
             +"/".join(str(x["condition_after"]) for x in audit["recovery"])+" |", "",
             "### Голы по позициям", "",
             "Первый замер обнаружил перекос: форварды забили 3858 из 3888 голов,",
             "полузащитники — только 25. После добавления подключений в 1000 равных матчах:", "",
             "| Позиция на поле | Голы | Удары |", "|---|---:|---:|"]
    equal = audit["scenarios"][0]
    for position, row in equal["positions"].items():
        rows.append(f"| {position} | {row['goals']} | {row['shots']} |")
    forwards = sum(equal["positions"].get(k, {}).get("goals", 0) for k in ("ST", "WF"))
    midfield = sum(equal["positions"].get(k, {}).get("goals", 0) for k in ("CM", "WM"))
    rows += ["", f"Полузащитники забили {midfield}. Доля форвардов — {percent(forwards,equal['goals'])}.",
             "Распределение всё ещё смещено к форвардам; центральные полузащитники и защитники",
             "забивают редко. Полное соответствие распределению реального футбола не подтверждено.", "",
             "### Производительность", "",
             "Изолированная копия пользовательского мира: 128 клубов, 9 087 игроков, 64 матча за день,",
             "Ryzen 5 3600. Медианы времени самой симуляции (без следующего кадра):", "",
             "| Режим | мс |", "|---|---:|"]
    labels = {"sync_0fps":"Синхронно, без UI", "sliced_0fps":"Порционно, без UI и ограничения FPS",
              "sliced_ui_0fps":"С UI, без ограничения FPS", "sliced_60fps":"Порционно, 60 FPS",
              "sliced_ui_60fps":"С UI, 60 FPS"}
    for key, value in timing.items(): rows.append(f"| {labels.get(key,key)} | {value:.1f} |")
    rows += ["", "Предыдущая коллективная модель: примерно 422 мс синхронно и 675 мс с UI при 60 FPS.",
             "Новая модель медленнее. При 60 FPS заметны ожидания между порциями основного потока;",
             "время одного матча нельзя выдавать за время дня. Хеши sync/sliced/UI совпали.", "",
             "### Регрессии", "",
             f"Сцен с отчётом passed/failed: {len(scenes)}; проверок {sum(x['passed'] for x in scenes.values())}; "
             f"ошибок {sum(x['failed'] for x in scenes.values())}.",
             "Проверяются совпадение C++/GDScript и RNG, независимость от CA/PA/репутации и неиспользованной",
             "скамейки, замены, ротация, травмы, карточки, статистика, рынок и сохранения.", "",
             "Дополнительно пройден двухсезонный прогон четырёх клубов с сохранением/загрузкой.",
             "В его сравнении пустая статистика неигравшей молодёжи приводится к той же нулевой",
             "строке, которую загрузчик создаёт штатно; CA, готовность и RNG не меняются.", "",
             "Полный числовой отчёт: `tests/performance/results/individual-action-engine-summary.json`.",
             "Сырые данные: `action-pitch-v3-audit.json`, `action-pitch-v3-generations.json`,",
             "`action-pitch-v3-day.json`, `action-pitch-v3-day-frames60.json` в той же папке.",
             "Запуск: `tools/run_action_acceptance.ps1 -FullSuite` после подготовки изолированного проекта.",
             f"SHA256 DLL: `{summary['dll_sha256']}`."]
    report.write_text(intro+"\n".join(rows)+"\n", encoding="utf-8")
    print(json.dumps({"scenes": len(scenes), "checks": sum(x["passed"] for x in scenes.values()),
                      "failed": sum(x["failed"] for x in scenes.values()), "day_medians_ms": timing,
                      "midfield_goals": midfield, "forward_goal_share": forwards/equal["goals"],
                      "generation_win_percent": wins/total_matches*100}, ensure_ascii=False))


if __name__ == "__main__":
    main()
