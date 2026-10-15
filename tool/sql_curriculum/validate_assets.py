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
import re
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


def split_setup_and_query(code: str) -> tuple[str, str]:
    """Split a full script into (setup, final query), as the app imports it.

    The authoring model guarantees ``code == setup + query`` where ``setup`` is
    the last statement boundary. Everything up to and including the final
    non-query statement is the setup; the trailing query is the teaching query.
    We split on the last top-level ``;`` that precedes a query-only tail.
    """
    statements = [s.strip() for s in code.split(";")]
    # Drop a possible trailing empty fragment after the final ';'.
    statements = [s for s in statements if s]
    # The last statement is the query; everything before is setup.
    setup = ";\n".join(statements[:-1])
    query = statements[-1]
    if setup:
        setup += ";\n"
    return setup, query


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

    workdir = Path(tempfile.mkdtemp(prefix="qfli_sql_assets_"))
    try:
        for entry in tutorials["entries"]:
            fixtures = entry.get("inputFixtures", {})
            engine = (
                fixtures.get("engine")
                or entry.get("runtime", {}).get("engine", "sqlite")
            )
            engine = str(engine).lower()
            dialect = entry.get("runtime", {}).get("engine", "")
            if "mysql" in engine or "mysql" in dialect.lower():
                not_executed.append(f"{entry['id']} ({dialect}): requires MySQL")
                continue
            for lesson in entry["lessons"]:
                code = lesson["code"]
                tid = entry["id"]
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

                setup, _query = split_setup_and_query(code)
                for index, exercise in enumerate(lesson.get("exercises", []), 1):
                    answer = exercise.get("answer", "")
                    if not answer.strip():
                        failed.append(f"{tid} exercise {index}: empty answer")
                        continue
                    exercise_total += 1
                    ex_db = workdir / f"{tid}_ex{index}.db"
                    rc_ex, out_ex, err_ex = run_sqlite(
                        ex_db, f"{setup}{answer}"
                    )
                    if rc_ex != 0:
                        failed.append(
                            f"{tid} exercise {index}: exit {rc_ex}: "
                            f"{err_ex.strip()}"
                        )
                        continue
                    # The packaged JSON does not carry an authored expectation
                    # for exercise answers (only the answer SQL). We assert the
                    # answer executes cleanly and returns rows/no-rows, which is
                    # the drift guard; the authored-expectation comparison runs
                    # in validate_content.py against the source modules.
                    exercise_passed += 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print(f"packaged-JSON sqlite examples passed: {passed}")
    print(f"packaged-JSON exercise answers executed cleanly: {exercise_passed}/{exercise_total}")
    print(f"mysql not executed: {len(not_executed)}")
    for item in not_executed:
        print(f"  SKIP {item}")
    if failed:
        print(f"FAILURES ({len(failed)}):")
        for item in failed:
            print(f"  FAIL {item}")
        return 1
    print("all packaged-JSON script executions matched the authored lesson output")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
