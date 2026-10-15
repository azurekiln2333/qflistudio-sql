"""Small helpers to author lessons concisely and readably.

Usage in a track module::

    from helper import L, E

    LESSONS = [
        L(1, "select-basics", "SELECT 基础与列选择", "beginner", "basics",
          concepts=["SELECT", "列", "别名"],
          objective="使用 SELECT 指定列并起别名",
          prerequisites=["了解表与行的概念"],
          explain="...",
          setup=\"\"\"CREATE TABLE ...;\"\"\",
          query="SELECT ...;",
          expected="id|name\\n1|Alice",
          pitfalls=["...", "..."],
          exercises=[
              E("把结果按 name 排序",
                "使用 ORDER BY",
                "SELECT name FROM t ORDER BY name;",
                "Alice\\nBob"),
          ]),
    ]
"""

from __future__ import annotations

from schema import Exercise, Lesson


def L(
    number: int,
    slug: str,
    title: str,
    level: str,
    track: str,
    *,
    concepts: list[str],
    objective: str,
    prerequisites: list[str],
    explain: str,
    setup: str,
    query: str,
    expected: str,
    pitfalls: list[str],
    exercises: list[Exercise],
    engine: str = "sqlite",
    version: str = "3.50",
) -> Lesson:
    return Lesson(
        number=number,
        slug=slug,
        title=title,
        level=level,
        track=track,
        concepts=concepts,
        objective=objective,
        prerequisites=prerequisites,
        explain=explain,
        setup=setup,
        query=query,
        expected=expected,
        pitfalls=pitfalls,
        exercises=exercises,
        engine=engine,
        version=version,
    )


def E(
    prompt: str,
    hint: str,
    answer: str,
    expected: str = "",
    *,
    verify_query: bool = True,
) -> Exercise:
    return Exercise(
        prompt=prompt,
        hint=hint,
        answer=answer,
        expected=expected,
        verify_query=verify_query,
    )
