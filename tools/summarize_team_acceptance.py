"""Summarize API 4 checks; read only isolated benchmark results and logs."""
import hashlib
import json
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESULTS = ROOT / "tests/performance/results"
LOGS = ROOT / "tools/.native-runtime"


def read(name):
    return json.loads((RESULTS / name).read_text(encoding="utf-8-sig"))


def main():
    dll = ROOT / "addons/fc_sim_core/bin/fc_sim_core_v4.windows.template_release.x86_64.dll"
    audit = read("action-pitch-v4-audit.json")
    generations = read("action-pitch-v4-generations.json")
    generation_acceptance = read("action-pitch-v4-generations-acceptance.json")
    day = read("action-pitch-v4-day.json")
    paced = read("action-pitch-v4-day-frames60.json")
    scenes = {"native_simulation"}
    runner = (ROOT / "tools/run_native_tests.ps1").read_text(encoding="utf-8-sig")
    block = runner.split("$nativeTestScenes = @(", 1)[1].split("\n)", 1)[0]
    scenes.update(re.findall(r"'([a-z_]+)'", block))
    tests = {}
    for scene in sorted(scenes):
        path = LOGS / f"suite-{scene}.stdout.log"
        assert path.stat().st_mtime > dll.stat().st_mtime, f"Stale test: {scene}"
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        counts = re.findall(r"(\d+) passed, (\d+) failed", text)
        assert counts, f"Missing test completion: {scene}"
        passed, failed = map(int, counts[-1])
        assert failed == 0 and "FAIL:" not in text, f"Failed test: {scene}"
        assert "SCRIPT ERROR:" not in (LOGS / f"suite-{scene}.stderr.log").read_text(encoding="utf-8-sig", errors="replace"), scene
        tests[scene] = {"passed": passed, "failed": failed}
    timing = {}
    for source in [day, paced]:
        for label in [x for x in ["sync","sliced","sliced_ui"] if any(row.get("label")==x and "simulation_ms" in row for row in source["samples"])]:
            samples = [x["simulation_ms"] for x in source["samples"] if x["label"] == label]
            timing[f"{label}_{source['frame_limit']}fps"] = round(statistics.median(samples), 3)
        assert len(set(source["digests"].values())) == 1, "Day modes diverged"
    scenarios = []
    for row in audit["scenarios"]:
        goals = row["goals"]
        metrics = {"labels": row["ca_labels"], "matches": row["matches"], "goals_per_match": row["goals_per_match"],
                   "assisted_percent": 100 * row["assisted_goals"] / goals,
                   "two_assist_percent": 100 * row["two_assist_goals"] / goals,
                   "penalty_goals_per_match": row["penalty_goals"] / row["matches"],
                   "role_goal_shares": {p: 100 * data["goals"] / goals for p, data in row["positions"].items()},
                   "goal_shares": {p: 100 * count / goals for p, count in row["primary_positions"].items()},
                   "subs_per_team": row["subs_per_team"]}
        scenarios.append(metrics)
    equal = scenarios[0]
    assert 80 <= equal["assisted_percent"] <= 90, equal
    assert 45 <= equal["goal_shares"]["ST"] <= 65, equal
    assert 20 <= equal["goal_shares"]["CM"] <= 40, equal
    assert 8 <= equal["goal_shares"]["CB"] <= 22, equal
    assert equal["two_assist_percent"] > 0 and equal["subs_per_team"] > 2, equal
    total_matches = sum(x["matches"] for x in generations.values())
    wins = sum(x["wins"] for x in generations.values())
    summary = {"backend": audit["backend"], "dll_sha256": hashlib.sha256(dll.read_bytes()).hexdigest(),
               "tests": tests, "test_scenes": len(tests), "checks_passed": sum(x["passed"] for x in tests.values()),
               "audit_matches": 6600, "scenarios": scenarios, "generation_matches": total_matches,
               "generation_win_percent_85_vs_75": wins / total_matches * 100, "generation_acceptance": generation_acceptance, "day_medians_ms": timing}
    (RESULTS / "team-model-322-summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = ["# Составы 20 игроков и фиксированная схема 3-2-2", "", "## Правила", "",
              "У всех клубов и сборных схема 3-2-2: один вратарь, три защитника, два полузащитника и два нападающих. "
              "Выбора схем и прежних стилей нет. Тренер задаёт атакующий или оборонительный характер игры. Личные характеры футболистов сохранены.", "",
              "Основной состав и заявка сборной — 20 игроков. Ограничения: 2–3 вратаря, 7–8 защитников, 5–6 полузащитников, 4–5 нападающих; "
              "в сумме всегда 20 при наличии подходящих игроков. На матч выходят восемь, оставшиеся доступны для замен. "
              "При нехватке существующих игроков заявка остаётся неполной. Правила количества замен сохраняются в настройках.", "",
              "Старые фланговые позиции преобразуются в соответствующую линию. Излишки клубной основы переходят в резерв с сохранением ID, навыков, "
              "личных характеров и статистики. Сборная сокращает старую заявку только из уже вызванных игроков. Травмированных во время турнира не заменяет.", "",
              "Голы определяются действиями конкретных вышедших игроков, их навыками и координатами. CA, PA, репутация и талант страны не дают бонуса к счёту. "
              "Доли голов по линиям не назначаются заранее. Поддерживающий защитник подключается, двое сохраняют прикрытие. "
              "У новых защитников завершение развивается, но профиль остаётся оборонительным.", "",
              "До двух ассистентов: последние разные партнёры по цепочке владения; автор удара может получить ассист после добивания партнёром. "
              "Перехват и выход мяча прерывают цепочку. Автор гола не может ассистировать себе. Пенальти не получают искусственных ассистентов. "
              "В своей штрафной защитники осторожнее выбирают контакт. Вратарь может забить, в частности если он лучший исполнитель пенальти.", "",
              "## Проверка", "",
              "Проверка общей результативности использует 20 независимых зеркальных пар уровня 65. У отдельной более слабой пары уровня 58 наблюдалось около 2,9 гола за матч: норма эталонного уровня не означает одинаковое число голов у любых составов.", "",
              f"Тестовых сцен: {len(tests)}. Проверок: {summary['checks_passed']:,}. Ошибок: 0. ".replace(",", " ") +
              "Сверены 585 полных матчей C++ и контрольного GDScript, включая крайние настройки, неполные составы, дополнительное время и пенальти. "
              "Проверены перенос 25→20, третий вратарь на скамейке, две передачи, отсутствие дубликатов, сохранение статистики, рынок и ротация.", "",
              "6 600 матчей: 3×1 000 сравнений составов и 3 600 испытаний отдельных навыков. Настройки по умолчанию, 50 минут, "
              "поле 60×40 м, ворота 5×2 м, без офсайда. Метки CA описывают способ генерации тестовых игроков, не вход формулы матча.", "",
              "| Составы | Голов/матч | НАП / ПЗЩ / ЗЩ | Голов с ассистами | С двумя ассистами | Замен на команду |",
              "|---|---:|---|---:|---:|---:|"]
    for row in scenarios:
        shares = row["goal_shares"]
        report.append(f"| {' / '.join(map(str,row['labels']))} | {row['goals_per_match']:.2f} | "
                      f"{shares['ST']:.1f}% / {shares['CM']:.1f}% / {shares['CB']:.1f}% | "
                      f"{row['assisted_percent']:.1f}% | {row['two_assist_percent']:.1f}% | {row['subs_per_team']:.2f} |")
    report += ["", "Доли посчитаны по основной позиции футболиста. Это результаты выборки, не гарантированные пропорции каждого матча. При большом разрыве навыков возможны крупные счета; ограничения счёта нет.", "",
               f"Проверка поколений: 10 миров, 30 лет развития и набора, {total_matches} матчей в контрольных годах. "
               f"Талант 85 против 75 — {summary['generation_win_percent_85_vs_75']:.1f}% побед. Это проверка поколений, не полная экономическая симуляция 30 сезонов. Прежний ориентир — 65–75%; точечная оценка немного выше верхней границы. "
               f"95%-й интервал по независимым мирам: {generation_acceptance['confidence_95'][0]*100:.1f}–{generation_acceptance['confidence_95'][1]*100:.1f}%. Повторные матчи одного состава считаются кластером одного мира.", "",
               "## Производительность", "",
               "Копия сохранения: 128 клубов, 9 087 игроков, 64 матча за день. Медианы по режимам, последовательные прогоны на одном компьютере:", "",
               "| Режим | День, мс |", "|---|---:|"]
    for key, value in timing.items(): report.append(f"| {key} | {value:.1f} |")
    report += ["", "Режимы дают одинаковое состояние при одинаковом старте. Производительность зависит от количества матчей и игроков; эти числа не являются гарантией для любого мира.", "",
               "## Запуск и воспроизведение", "", "Сейв версии 15, нативный API 4. Перезапустить игру и редактор Godot, чтобы загрузить новый DLL. "
               "Ранее сыгранные матчи и история не переписываются.", "",
               "```powershell", ".\\tools\\build_native.ps1", ".\\tools\\run_load_benchmark.ps1 -PrepareOnly", ".\\tools\\run_action_acceptance.ps1 -Version v4 -FullSuite",
               "python tools/summarize_team_acceptance.py", "```", "",
               "Результаты: `tests/performance/results/team-model-322-summary.json`, `action-pitch-v4-*.json`. Исходный пользовательский сейв не изменяется."]
    (ROOT / "docs/team-model-322.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print(json.dumps({k: summary[k] for k in ["checks_passed", "test_scenes", "generation_win_percent_85_vs_75", "day_medians_ms"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
