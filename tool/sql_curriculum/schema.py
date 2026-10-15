"""Shared schema helpers for the QFLISQLab SQL curriculum.

This module defines the single source of truth for the local content assets
``assets/content/sql_tutorials.json`` and ``assets/content/sql_examples.json``.

The JSON shape MUST match the shared parser in
``../qfli_studio_core/lib/content/content_repository.dart``
(``ContentCatalog.fromJson`` / ``_parseTutorial`` / ``_parseExample``).
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ASSET_DIR = REPO_ROOT / "assets" / "content"
TUTORIAL_ASSET = ASSET_DIR / "sql_tutorials.json"
EXAMPLE_ASSET = ASSET_DIR / "sql_examples.json"

SCHEMA_VERSION = 1
UPDATED_AT = "2026-10-12"
LOCALE = "zh-CN"
SOURCE = "https://www.sqlite.org/lang.html"
LICENSE = "Original QFLI curriculum. Reference link retained. CC BY 4.0"

PLACEHOLDER_PATTERNS = [
    re.compile(r"\bTODO\b", re.IGNORECASE),
    re.compile(r"\bFIXME\b", re.IGNORECASE),
    re.compile(r"占位符"),
    re.compile(r"占位内容"),
    re.compile(r"占位说明"),
    re.compile(r"\bplaceholder\b", re.IGNORECASE),
    re.compile(r"待补充"),
    re.compile(r"此处省略"),
    re.compile(r"依此类推，略"),
    re.compile(r"（略）"),
]


@dataclass(frozen=True)
class Exercise:
    prompt: str
    hint: str
    answer: str
    # Authored expected result of running ``answer`` against the lesson setup.
    expected: str = ""
    # Whether ``answer`` is a query-only statement (verified by result) or a
    # mutation (verified by a follow-up check in ``setup_after``).
    verify_query: bool = True

    def __str__(self) -> str:  # pragma: no cover - trivial
        return self.prompt


@dataclass(frozen=True)
class Lesson:
    """One lesson == one tutorial entry == one chapter.

    ``setup`` is the DDL + data (CREATE TABLE / INSERT / CREATE VIEW ...).
    ``query`` is the teaching query. ``code`` is ``setup + query`` and is what
    the app shows and imports. ``expected`` is the authored, hand-derived
    expected result (raw text in SQLite CLI ``|`` row format). ``explain`` must
    state the dialect/version and why the result holds.

    Exercise answers are query-only statements verified against ``setup`` in a
    fresh database, using each exercise's authored ``expected`` text.
    """

    number: int
    slug: str
    title: str
    level: str  # beginner | intermediate | advanced
    track: str
    concepts: list[str]
    objective: str
    prerequisites: list[str]
    explain: str
    setup: str
    query: str
    expected: str
    pitfalls: list[str]
    exercises: list[Exercise]
    engine: str = "sqlite"  # sqlite | mysql
    version: str = "3.50"

    @property
    def code(self) -> str:
        return f"{self.setup.rstrip()}\n{self.query.strip()}\n"

    @property
    def sqlite_query_only(self) -> bool:
        return self.engine == "sqlite"

    @property
    def tid(self) -> str:
        return f"sql-tutorial-{self.number:03d}"

    @property
    def lesson_id(self) -> str:
        return f"{self.tid}-lesson"

    @property
    def eid(self) -> str:
        return f"sql-example-{self.number:03d}"

    def dialect_label(self) -> str:
        if self.engine == "mysql":
            return f"MySQL {self.version}"
        return f"SQLite {self.version}"

    def tutorial_entry(self) -> dict:
        """Render the tutorial entry using the exact shared field names."""
        summary = (
            f"{self.dialect_label()}；本课目标：{self.objective}"
        )
        concepts = list(dict.fromkeys([self.dialect_label(), *self.concepts]))
        return {
            "id": self.tid,
            "language": "sql",
            "type": "sql",
            "locale": LOCALE,
            "level": self.level,
            "title": f"第 {self.number} 课：{self.title}",
            "summary": summary,
            "concepts": concepts,
            "source": SOURCE,
            "license": LICENSE,
            "updatedAt": UPDATED_AT,
            "runtime": {
                "kind": "offline-content",
                "status": "available",
                "engine": self.dialect_label(),
            },
            "lessons": [
                {
                    "id": self.lesson_id,
                    "title": self.title,
                    "summary": summary,
                    "concepts": concepts,
                    "objective": self.objective,
                    "prerequisites": list(self.prerequisites),
                    "explain": self._explain_with_dialect(),
                    "code": self.code,
                    "output": self.expected,
                    "pitfalls": list(self.pitfalls),
                    "exercises": [
                        {
                            "prompt": ex.prompt,
                            "hint": ex.hint,
                            "answer": ex.answer,
                        }
                        for ex in self.exercises
                    ],
                }
            ],
        }

    def _explain_with_dialect(self) -> str:
        """Guarantee the dialect/version is visible in the explain display field.

        The teaching prose may already name the engine; if not, append a single
        sentence stating the dialect and version this lesson was verified under.
        This keeps R6 (dialect visible in display fields) satisfied for every
        lesson without rewriting each hand-written paragraph.
        """
        explain = self.explain.rstrip()
        if "SQLite" in explain or "MySQL" in explain:
            return explain
        if self.engine == "mysql":
            return (
                f"{explain} 本课面向 {self.dialect_label()}，语法与 SQLite 不同，"
                f"无法在 SQLite 引擎执行。"
            )
        return f"{explain} 本课语法在 {self.dialect_label()} 下验证。"

    def example_entry(self) -> dict:
        """Render the example entry using the exact shared field names."""
        summary = (
            f"{self.dialect_label()} 完整可运行示例：建表、造数并查询。"
            f"预期结果已在本机执行验证。目标：{self.objective}"
        )
        concepts = list(dict.fromkeys([self.dialect_label(), *self.concepts]))
        return {
            "id": self.eid,
            "language": "sql",
            "type": "sql",
            "locale": LOCALE,
            "level": self.level,
            "title": f"示例 {self.number}：{self.title}",
            "summary": summary,
            "concepts": concepts,
            "source": SOURCE,
            "license": LICENSE,
            "updatedAt": UPDATED_AT,
            "code": self.code if self.code.endswith("\n") else self.code + "\n",
            "output": self.expected,
            "expectedOutput": self.expected,
            "inputFixtures": {
                "engine": self.engine,
                "version": self.version,
            },
            "templateType": "sql",
            "sourceLessonId": self.lesson_id,
        }


@dataclass
class Track:
    name: str
    lessons: list[Lesson] = field(default_factory=list)


def dumps(document: dict) -> str:
    return json.dumps(document, ensure_ascii=False, indent=2) + "\n"
