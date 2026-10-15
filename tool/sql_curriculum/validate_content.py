"""Execute every SQLite example and exercise answer and verify the authored
expectation in an isolated fresh database.

Run:  python tool/sql_curriculum/validate_content.py

Design notes (per main-control requirement):
- Expected results are AUTHORED per lesson (hand-derived from the taught
  semantics), then asserted against execution. We never "run once and paste the
  output as the expectation" — the comparison target comes from the lesson data.
- Every SQLite example runs in its own throwaway database file so nothing
  touches a real user database.
- MySQL-only lessons cannot run here; they are listed as NOT EXECUTED with a
  reason and never counted as passing.

For exercises, each answer is executed as a query-only statement against a fresh
copy of the lesson's schema+data (the setup is the lesson ``code`` minus its
final query, or the explicit ``exercise_setup`` when provided). The exercise
expectation is authored separately in the lesson data (``Exercise.answer`` is the
SQL; the expected output is authored alongside in the track module). To keep the
schema simple, exercises declare their expected result text; see ``checks``.
"""

from __future__ import annotations

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
from build_content import load_lessons  # noqa: E402

SQLITE = Path(r"D:\ProgramFiles\platform-tools\sqlite3.exe")


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
    lines = [line.rstrip() for line in text.strip().splitlines()]
    # Drop the trailing prompt-only artefact lines if any.
    return "\n".join(line for line in lines if line.strip() != "")


NO_ROWS = "(no rows)"


def normalize_expected(text: str) -> str:
    """Resolve the authored expectation sentinel for an empty result set."""
    return "" if text.strip() == NO_ROWS else normalize(text)


def main() -> int:
    if not SQLITE.exists():
        print(f"sqlite3 CLI not found at {SQLITE}", file=sys.stderr)
        return 2

    lessons = sorted(load_lessons(), key=lambda lesson: lesson.number)
    passed = 0
    exercise_passed = 0
    exercise_total = 0
    failed: list[str] = []
    not_executed: list[str] = []

    workdir = Path(tempfile.mkdtemp(prefix="qfli_sql_validate_"))
    try:
        for lesson in lessons:
            if lesson.engine != "sqlite":
                not_executed.append(
                    f"{lesson.tid} ({lesson.dialect_label()}): requires MySQL"
                )
                continue

            # 1) Verify the lesson example (setup + query vs authored expected).
            db = workdir / f"{lesson.tid}.db"
            rc, out, err = run_sqlite(db, lesson.code)
            if rc != 0:
                failed.append(f"{lesson.tid}: exit {rc}: {err.strip()}")
            else:
                actual = normalize(out)
                expected = normalize_expected(lesson.expected)
                if actual != expected:
                    failed.append(
                        f"{lesson.tid}: mismatch\n  expected: {expected!r}\n  actual:   {actual!r}"
                    )
                else:
                    passed += 1

            # 2) Verify each exercise answer against a fresh setup DB.
            for index, exercise in enumerate(lesson.exercises, start=1):
                if not exercise.verify_query:
                    continue
                if not exercise.expected.strip():
                    failed.append(
                        f"{lesson.tid} exercise {index}: missing authored expectation "
                        f"(use '{NO_ROWS}' for an empty result)"
                    )
                    continue
                exercise_total += 1
                ex_db = workdir / f"{lesson.tid}_ex{index}.db"
                # Run setup and the answer in one session so TEMP tables and
                # session state created by the setup are visible to the answer.
                rc_ex, out_ex, err_ex = run_sqlite(
                    ex_db, f"{lesson.setup.rstrip()}\n{exercise.answer}"
                )
                if rc_ex != 0:
                    failed.append(
                        f"{lesson.tid} exercise {index}: exit {rc_ex}: {err_ex.strip()}"
                    )
                    continue
                actual_ex = normalize(out_ex)
                expected_ex = normalize_expected(exercise.expected)
                if actual_ex != expected_ex:
                    failed.append(
                        f"{lesson.tid} exercise {index}: mismatch\n"
                        f"  expected: {expected_ex!r}\n  actual:   {actual_ex!r}"
                    )
                else:
                    exercise_passed += 1
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    total_sqlite = sum(1 for lesson in lessons if lesson.engine == "sqlite")
    print(f"sqlite examples passed: {passed}/{total_sqlite}")
    print(f"exercise answers passed: {exercise_passed}/{exercise_total}")
    print(f"mysql not executed: {len(not_executed)}")
    for item in not_executed:
        print(f"  SKIP {item}")
    if failed:
        print(f"FAILURES ({len(failed)}):")
        for item in failed:
            print(f"  FAIL {item}")
        return 1
    print("all authored expectations matched execution")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
