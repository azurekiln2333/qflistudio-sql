"""Validate the PACKAGED JSON assets directly (asset-drift guard).

`validate_content.py` executes the Python authoring modules
(`build_content.load_lessons()`), so it validates the *source* the assets were
built from. This script instead reads the shipped JSON files
(`assets/content/sql_tutorials.json` / `sql_examples.json`) — exactly what the
app loads through `SqlContentRepository` — and re-executes every SQLite lesson
and exercise answer in an isolated throwaway database.

If `build_content.py` is deterministic and the assets are in sync, this script
and `validate_content.py` agree. If the assets drift from the authoring source,
this script catches it.

Run:  python tool/sql_curriculum/validate_assets.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema  # noqa: E402

SQLITE = Path(r"D:\ProgramFiles\platform-tools\sqlite3.exe")
NO_ROWS = "(no rows)"


def run_sqlite(db: Path, script: str) -> tuple[int, str, str]:
    proc = subprocess.run(
        [str(SQLITE), str(db)],
        input=script,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    return proc.returncode, proc.stdout, proc.stderr


def normalize(text: str) -> str:
    return "\n".join(
        line.rstrip() for line in text.strip().splitlines() if line.strip() != ""
    )


def normalize_expected(text: str) -> str:
    return "" if text.strip() == NO_ROWS else normalize(text)


def main() -> int:
    if not SQLITE.exists():
        print(f"sqlite3 CLI not found at {SQLITE}", file=sys.stderr)
        return 2

    tutorials = json.loads(schema.TUTORIAL_ASSET.read_text(encoding="utf-8"))
    examples = json.loads(schema.EXAMPLE_ASSET.read_text(encoding="utf-8"))

    passed = 0
    exercise_passed = 0
    exercise_total = 0
    failed: list[str] = []
    not_executed: list[str] = []
    example_by_lesson: dict[str, dict] = {}
    for example in examples["entries"]:
        lesson_id = example["sourceLessonId"]
        if lesson_id in example_by_lesson:
            failed.append(f"duplicate example for {lesson_id}")
        example_by_lesson[lesson_id] = example

    workdir = Path(tempfile.mkdtemp(prefix="qfli_sql_assets_"))
    try:
        for entry in tutorials["entries"]:
            for lesson in entry["lessons"]:
                code = lesson["code"]
                tid = entry["id"]
                example = example_by_lesson.pop(lesson["id"], None)
                if example is None:
                    failed.append(f"{tid}: missing matching packaged example")
                    continue
                if example["code"] != code or example["expectedOutput"] != lesson["output"]:
                    failed.append(f"{tid}: tutorial/example code or expectation drift")
                fixtures = example.get("inputFixtures", {})
                setup = fixtures.get("exerciseSetup")
                try:
                    expected_outputs = json.loads(fixtures["exerciseExpectedOutputs"])
                except (KeyError, TypeError, ValueError):
                    failed.append(f"{tid}: invalid packaged exercise expectations")
                    continue
                exercises = lesson.get("exercises", [])
                if (not isinstance(setup, str)
                    or not isinstance(expected_outputs, list)
                    or len(expected_outputs) != len(exercises)
                    or any(not isinstance(value, str) or not value.strip()
                           for value in expected_outputs)):
                    failed.append(f"{tid}: incomplete packaged exercise fixtures")
                    continue
                engine = fixtures.get("engine")
                if engine == "mysql":
                    not_executed.append(f"{tid}: requires native MySQL execution")
                    continue
                if engine != "sqlite":
                    failed.append(f"{tid}: unknown packaged engine {engine!r}")
                    continue
                db = workdir / f"{tid}.db"
                rc, out, err = run_sqlite(db, code)
                if rc != 0:
                    failed.append(f"{tid}: exit {rc}: {err.strip()}")
                else:
                    actual = normalize(out)
                    expected = normalize_expected(lesson["output"])
                    if actual != expected:
                        failed.append(
                            f"{tid}: mismatch\n  expected: {expected!r}\n"
                            f"  actual:   {actual!r}"
                        )
                    else:
                        passed += 1

                for index, exercise in enumerate(exercises, 1):
                    answer = exercise.get("answer", "")
                    if not answer.strip():
                        failed.append(f"{tid} exercise {index}: empty answer")
                        continue
                    exercise_total += 1
                    ex_db = workdir / f"{tid}_ex{index}.db"
                    rc_ex, out_ex, err_ex = run_sqlite(
                        ex_db, f"{setup.rstrip()}\n{answer}"
                    )
                    if rc_ex != 0:
                        failed.append(
                            f"{tid} exercise {index}: exit {rc_ex}: "
                            f"{err_ex.strip()}"
                        )
                        continue
                    actual_ex = normalize(out_ex)
                    expected_ex = normalize_expected(expected_outputs[index - 1])
                    if actual_ex != expected_ex:
                        failed.append(
                            f"{tid} exercise {index}: mismatch\n"
                            f"  expected: {expected_ex!r}\n  actual:   {actual_ex!r}"
                        )
                    else:
                        exercise_passed += 1
        for lesson_id in example_by_lesson:
            failed.append(f"{lesson_id}: example has no matching tutorial lesson")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print(f"packaged-JSON sqlite examples passed: {passed}")
    print(f"packaged-JSON exercise expectations matched: {exercise_passed}/{exercise_total}")
    print(f"mysql not executed: {len(not_executed)}")
    for item in not_executed:
        print(f"  SKIP {item}")
    if failed:
        print(f"FAILURES ({len(failed)}):")
        for item in failed:
            print(f"  FAIL {item}")
        return 1
    print("all packaged-JSON executions matched authored lesson and exercise outputs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
