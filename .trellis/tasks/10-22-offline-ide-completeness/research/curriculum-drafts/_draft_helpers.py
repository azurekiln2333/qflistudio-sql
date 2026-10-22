"""Unshipped curriculum authoring; promotion requires the existing OHOS gate.

Every result below is authored from the fixture, never captured from execution.
The common helper changes presentation only; it does not derive expectations.
"""
from lessons.helper import E, L


def topic(number, slug, title, track, concepts, explain, setup, query, expected,
          pitfalls, first, second, *, level="advanced"):
    return L(
        number, slug, title, level, track,
        concepts=concepts,
        objective=f"实现{title}，核对业务口径与结果粒度",
        prerequisites=["理解 SELECT、JOIN、GROUP BY 与 CTE", "能区分 NULL 与空字符串"],
        explain=explain,
        setup=setup.strip(), query=query.strip(), expected=expected,
        pitfalls=pitfalls,
        exercises=[E(*first), E(*second)],
    )
