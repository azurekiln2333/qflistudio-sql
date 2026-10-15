"""Dump each lesson's explain + data + expected for manual prose/data audit.

Run:  python tool/sql_curriculum/review_dump.py > research/prose-review.txt
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

from build_content import load_lessons  # noqa: E402


def main() -> int:
    lessons = sorted(load_lessons(), key=lambda lesson: lesson.number)
    for lesson in lessons:
        print("=" * 78)
        print(f"#{lesson.number} [{lesson.track}/{lesson.level}/{lesson.dialect_label()}] {lesson.title}")
        print(f"objective: {lesson.objective}")
        print("-- setup --")
        print(lesson.setup)
        print("-- query --")
        print(lesson.query)
        print("-- expected --")
        print(lesson.expected)
        print("-- explain --")
        print(lesson.explain)
        print("-- pitfalls --")
        for item in lesson.pitfalls:
            print(f"  * {item}")
        print("-- exercises --")
        for index, ex in enumerate(lesson.exercises, start=1):
            print(f"  ({index}) {ex.prompt} | hint={ex.hint}")
            print(f"      answer: {ex.answer}")
            print(f"      expected: {ex.expected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
