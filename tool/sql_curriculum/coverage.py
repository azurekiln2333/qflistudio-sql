"""Static coverage/uniqueness/placeholder checks for the SQL curriculum.

Run:  python tool/sql_curriculum/coverage.py [--min N]

Checks:
- total lesson count >= min (default 110)
- every required field is non-empty
- no placeholder tokens
- no two lessons share an identical ``explain`` or ``code`` body
- per-track coverage counts meet the plan in ``coverage-map.md`` minima table
"""

from __future__ import annotations

import argparse
import sys
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema  # noqa: E402
from build_content import load_lessons  # noqa: E402

# Minimum lesson counts per track, per research/coverage-map.md.
TRACK_MINIMA = {
    "basics": 14,
    "functions": 16,
    "aggregation": 10,
    "joins": 12,
    "subqueries": 10,
    "cte": 8,
    "windows": 12,
    "ddl": 12,
    "dml": 8,
    "transactions": 6,
    "indexes": 8,
    "modeling": 4,
}

# Tracks that are counted but not required to meet a minimum (optional extras).
OPTIONAL_TRACKS = {"mysql"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=int, default=110)
    args = parser.parse_args()

    lessons = sorted(load_lessons(), key=lambda lesson: lesson.number)
    problems: list[str] = []

    if len(lessons) < args.min:
        problems.append(f"lesson count {len(lessons)} < required {args.min}")

    explains = Counter(lesson.explain.strip() for lesson in lessons)
    codes = Counter(lesson.code.strip() for lesson in lessons)
    for text, count in explains.items():
        if count > 1:
            problems.append(f"duplicated explain body used {count} times: {text[:40]!r}")
    for text, count in codes.items():
        if count > 1:
            problems.append(f"duplicated code body used {count} times: {text[:40]!r}")

    for lesson in lessons:
        for attr in ("objective", "explain", "code", "expected"):
            if not str(getattr(lesson, attr)).strip():
                problems.append(f"{lesson.tid}: empty {attr}")
        if not lesson.exercises:
            problems.append(f"{lesson.tid}: no exercises")
        joined = " ".join(
            [lesson.title, lesson.objective, lesson.explain, lesson.code, lesson.expected]
        )
        for pattern in schema.PLACEHOLDER_PATTERNS:
            if pattern.search(joined):
                problems.append(f"{lesson.tid}: placeholder {pattern.pattern!r}")

    by_track = Counter(lesson.track for lesson in lessons)
    for track, minimum in TRACK_MINIMA.items():
        if by_track.get(track, 0) < minimum:
            problems.append(
                f"track {track}: {by_track.get(track, 0)} lessons < planned {minimum}"
            )

    print(f"total lessons: {len(lessons)}")
    for track in sorted(by_track):
        print(f"  {track}: {by_track[track]}")
    sqlite_count = sum(1 for lesson in lessons if lesson.engine == "sqlite")
    print(f"sqlite: {sqlite_count}  mysql: {len(lessons) - sqlite_count}")

    if problems:
        print(f"PROBLEMS ({len(problems)}):")
        for problem in problems:
            print(f"  - {problem}")
        return 1
    print("coverage checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
