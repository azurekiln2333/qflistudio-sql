"""Render the local SQL content assets from the structured lesson definitions.

Run:  python tool/sql_curriculum/build_content.py

The output assets match the shared ``ContentCatalog.fromJson`` contract. The
build is deterministic (sorted by lesson number) and fails loudly on schema
problems so a broken asset never reaches the app.
"""

from __future__ import annotations

import importlib
import json
import pkgutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import schema  # noqa: E402

LESSONS_DIR = HERE / "lessons"

REQUIRED_LESSON_TEXT = (
    "objective",
    "explain",
    "code",
    "expected",
)
REQUIRED_ENTRY_TEXT = (
    "id",
    "language",
    "type",
    "level",
    "title",
    "summary",
    "source",
    "license",
    "updatedAt",
)


def load_lessons() -> list[schema.Lesson]:
    """Import every module under ``lessons/`` and collect Lesson objects.

    Each module exposes ``LESSONS: list[schema.Lesson]``.
    """
    lessons: list[schema.Lesson] = []
    for info in sorted(pkgutil.iter_modules([str(LESSONS_DIR)]), key=lambda i: i.name):
        if info.name.startswith("_") or info.name == "helper":
            continue
        module = importlib.import_module(f"lessons.{info.name}")
        module_lessons = getattr(module, "LESSONS", None)
        if module_lessons is None:
            raise SystemExit(f"lessons/{info.name}.py must define LESSONS")
        lessons.extend(module_lessons)
    return lessons


def audit(lessons: list[schema.Lesson]) -> None:
    numbers = [lesson.number for lesson in lessons]
    if len(numbers) != len(set(numbers)):
        duplicates = sorted({n for n in numbers if numbers.count(n) > 1})
        raise SystemExit(f"duplicate lesson numbers: {duplicates}")

    ids = [lesson.tid for lesson in lessons]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate tutorial ids")

    for lesson in lessons:
        for attr in REQUIRED_LESSON_TEXT:
            value = getattr(lesson, attr)
            if not str(value).strip():
                raise SystemExit(f"{lesson.tid}: empty {attr}")
        if not lesson.exercises:
            raise SystemExit(f"{lesson.tid}: no exercises")
        for ex in lesson.exercises:
            if not ex.prompt.strip() or not ex.answer.strip():
                raise SystemExit(f"{lesson.tid}: incomplete exercise")
            if not ex.expected.strip():
                raise SystemExit(
                    f"{lesson.tid}: missing authored exercise expectation "
                    "(use '(no rows)' for an empty result)"
                )
        joined = " ".join(
            [
                lesson.title,
                lesson.objective,
                lesson.explain,
                lesson.code,
                lesson.expected,
                *lesson.pitfalls,
                *[ex.prompt + ex.hint + ex.answer for ex in lesson.exercises],
            ]
        )
        for pattern in schema.PLACEHOLDER_PATTERNS:
            if pattern.search(joined):
                raise SystemExit(
                    f"{lesson.tid}: placeholder pattern {pattern.pattern!r} found"
                )

    for entry in (lesson.tutorial_entry() for lesson in lessons):
        for field in REQUIRED_ENTRY_TEXT:
            if not str(entry.get(field, "")).strip():
                raise SystemExit(f"{entry.get('id')}: empty entry field {field}")
    for entry in (lesson.example_entry() for lesson in lessons):
        for field in REQUIRED_ENTRY_TEXT:
            if not str(entry.get(field, "")).strip():
                raise SystemExit(f"{entry.get('id')}: empty entry field {field}")


def render_example(lesson: schema.Lesson) -> dict:
    entry = lesson.example_entry()
    # Shared ContentCatalog preserves only string fixture values. Keep the
    # authored exercise outputs as JSON text rather than losing a nested list.
    entry["inputFixtures"].update(
        exerciseSetup=lesson.setup,
        exerciseExpectedOutputs=json.dumps(
            [exercise.expected for exercise in lesson.exercises],
            ensure_ascii=False,
        ),
    )
    return entry


def main() -> int:
    lessons = sorted(load_lessons(), key=lambda lesson: lesson.number)
    audit(lessons)

    tutorials = {
        "schemaVersion": schema.SCHEMA_VERSION,
        "language": "sql",
        "type": "sql",
        "locale": schema.LOCALE,
        "updatedAt": schema.UPDATED_AT,
        "entries": [lesson.tutorial_entry() for lesson in lessons],
    }
    examples = {
        "schemaVersion": schema.SCHEMA_VERSION,
        "language": "sql",
        "type": "sql",
        "locale": schema.LOCALE,
        "updatedAt": schema.UPDATED_AT,
        "entries": [render_example(lesson) for lesson in lessons],
    }

    schema.ASSET_DIR.mkdir(parents=True, exist_ok=True)
    schema.TUTORIAL_ASSET.write_text(schema.dumps(tutorials), encoding="utf-8")
    schema.EXAMPLE_ASSET.write_text(schema.dumps(examples), encoding="utf-8")

    sqlite_count = sum(1 for lesson in lessons if lesson.engine == "sqlite")
    mysql_count = len(lessons) - sqlite_count
    print(f"lessons={len(lessons)} sqlite={sqlite_count} mysql={mysql_count}")
    print(f"wrote {schema.TUTORIAL_ASSET.relative_to(schema.REPO_ROOT)}")
    print(f"wrote {schema.EXAMPLE_ASSET.relative_to(schema.REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
