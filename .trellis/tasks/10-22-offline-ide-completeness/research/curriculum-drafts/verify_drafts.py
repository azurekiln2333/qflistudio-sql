"""Isolated draft-only validator. Does not import drafts into product assets.

Expected output always comes from authored module fields. Mismatches are
reported, never written back into any expectation. Run from any directory.
"""
from __future__ import annotations

import hashlib
import argparse
import ctypes
import importlib.util
import json
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
sys.path.insert(0, str(ROOT / "tool" / "sql_curriculum"))
sys.path.insert(0, str(HERE))
from build_content import audit, load_lessons, render_example
import schema

SQLITE = Path(r"D:\ProgramFiles\platform-tools\sqlite3.exe")
NATIVE_SQLITE = ROOT / "native" / "build" / "windows" / "qfli_sqlite.dll"


class NativeSqlite:
    """Execute using the project's actual C engine, one isolated DB per case."""
    def __init__(self, path):
        self.path = path
        self.lib = ctypes.CDLL(str(path))
        self.lib.sqlite3_libversion.restype = ctypes.c_char_p
        self.lib.sqlite3_open.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        self.callback_type = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_int,
                                             ctypes.POINTER(ctypes.c_char_p), ctypes.POINTER(ctypes.c_char_p))
        self.lib.sqlite3_exec.argtypes = [ctypes.c_void_p, ctypes.c_char_p, self.callback_type,
                                         ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
        self.lib.sqlite3_close.argtypes = [ctypes.c_void_p]
        self.lib.sqlite3_free.argtypes = [ctypes.c_void_p]

    @property
    def version(self):
        return self.lib.sqlite3_libversion().decode("utf-8")

    def run(self, sql):
        db = ctypes.c_void_p()
        rc = self.lib.sqlite3_open(b":memory:", ctypes.byref(db))
        if rc:
            if db:
                self.lib.sqlite3_close(db)
            return rc, "", "sqlite3_open failed"
        rows = []

        @self.callback_type
        def result(_context, count, values, _names):
            rows.append("|".join(values[index].decode("utf-8") if values[index] is not None else ""
                                 for index in range(count)))
            return 0

        error = ctypes.c_char_p()
        try:
            rc = self.lib.sqlite3_exec(db, sql.encode("utf-8"), result, None, ctypes.byref(error))
            message = error.value.decode("utf-8") if error.value else ""
            return rc, "\n".join(rows), message
        finally:
            if error:
                self.lib.sqlite3_free(error)
            self.lib.sqlite3_close(db)


def normalized(value):
    return "\n".join(line.rstrip() for line in value.strip().splitlines() if line.strip())


def fingerprint(sql):
    sql = re.sub(r"'([^']|'')*'", "'?'", sql)
    sql = re.sub(r"\b\d+(?:\.\d+)?\b", "?", sql)
    return re.sub(r"\s+", " ", sql).strip().lower()


def main():
    # Windows console code pages must not hide a Unicode-containing failure.
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", choices=("cli", "bundled"), default="cli")
    parser.add_argument("--report", type=Path, help="Write case hashes and outcomes under the draft directory")
    args = parser.parse_args()
    native = NativeSqlite(NATIVE_SQLITE) if args.engine == "bundled" else None
    before = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in [schema.TUTORIAL_ASSET, schema.EXAMPLE_ASSET]}
    drafts = []
    for path in sorted(HERE.glob("track_*.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        drafts.extend(module.LESSONS)
    baseline = load_lessons()
    audit(baseline + drafts)
    failures = []
    outcomes = []
    if sorted(lesson.number for lesson in drafts) != list(range(127, 307)):
        failures.append("draft IDs must cover exactly 127 through 306")
    for lesson in drafts:
        if len(lesson.exercises) != 2 or len(lesson.pitfalls) < 2:
            failures.append(f"{lesson.tid}: needs two authored exercises and at least two pitfalls")
    # Including the baseline makes accidental reuse visible before promotion.
    for attr in ("title", "explain", "code"):
        counts = Counter(getattr(lesson, attr).strip() for lesson in baseline + drafts)
        for text, count in counts.items():
            if count > 1:
                failures.append(f"duplicate {attr}: {text[:100]!r}")
    patterns = Counter(fingerprint(lesson.query) for lesson in baseline + drafts)
    new_patterns = {fingerprint(lesson.query) for lesson in drafts}
    baseline_patterns_repeated = []
    for pattern, count in patterns.items():
        if count > 1 and pattern in new_patterns:
            failures.append(f"repeated normalized teaching query across baseline and drafts ({count}): {pattern}")
        elif count > 1:
            baseline_patterns_repeated.append({"pattern": pattern, "count": count})
    examples = 0
    exercises = 0
    with tempfile.TemporaryDirectory(prefix="qfli_sql_curriculum_drafts_") as temp:
        for lesson in drafts:
            if lesson.engine != "sqlite":
                failures.append(f"unexpected draft engine: {lesson.tid}")
                continue
            cases = [("example", lesson.code, lesson.expected)]
            cases += [(f"exercise-{index}", lesson.setup + "\n" + ex.answer, ex.expected)
                      for index, ex in enumerate(lesson.exercises, 1)]
            for label, sql, expected in cases:
                db = Path(temp) / f"{lesson.tid}-{label}.db"
                if native:
                    rc, stdout, stderr = native.run(sql)
                else:
                    proc = subprocess.run([str(SQLITE), str(db)], input=sql,
                                          capture_output=True, text=True, encoding="utf-8")
                    rc, stdout, stderr = proc.returncode, proc.stdout, proc.stderr
                target = "" if expected == "(no rows)" else normalized(expected)
                actual = normalized(stdout)
                outcomes.append({
                    "lessonId": lesson.tid,
                    "case": label,
                    "engine": "sqlite",
                    "exitCode": rc,
                    "matched": rc == 0 and actual == target,
                    "sqlSha256": hashlib.sha256(sql.encode("utf-8")).hexdigest(),
                    "authoredExpectedSha256": hashlib.sha256(target.encode("utf-8")).hexdigest(),
                    "actualSha256": hashlib.sha256(actual.encode("utf-8")).hexdigest(),
                })
                if rc or actual != target:
                    failures.append(f"{lesson.tid} {label}: rc={rc} "
                                    f"expected={target!r} actual={actual!r} error={stderr.strip()}")
                elif label == "example":
                    examples += 1
                else:
                    exercises += 1
            # Fixture and code remain exact through the existing JSON renderer.
            rendered = json.loads(schema.dumps(render_example(lesson)))
            if rendered["code"] != lesson.code:
                failures.append(f"{lesson.tid}: rendered code drift")
            if json.loads(rendered["inputFixtures"]["exerciseExpectedOutputs"]) != [e.expected for e in lesson.exercises]:
                failures.append(f"{lesson.tid}: rendered exercise expectation drift")
    after = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in [schema.TUTORIAL_ASSET, schema.EXAMPLE_ASSET]}
    if before != after:
        failures.append("product assets changed during draft verification")
    print(f"drafts={len(drafts)} examples={examples}/{len(drafts)} exercises={exercises}/{sum(len(x.exercises) for x in drafts)}")
    print("draft tracks: " + ", ".join(f"{k}={v}" for k, v in sorted(Counter(x.track for x in drafts).items())))
    print("product assets untouched: " + str(before == after))
    if native:
        print(f"bundled SQLite: {native.version}")
        print(f"library SHA256: {hashlib.sha256(NATIVE_SQLITE.read_bytes()).hexdigest()}")
    else:
        print("SQLite CLI: " + subprocess.check_output([str(SQLITE), ":memory:", "SELECT sqlite_version();"], text=True).strip())
    if args.report:
        report_path = args.report.resolve()
        if not report_path.is_relative_to(HERE):
            raise SystemExit("draft reports must remain inside the draft directory")
        engine_path = NATIVE_SQLITE if native else SQLITE
        report = {
            "createdAtUtc": datetime.now(timezone.utc).isoformat(),
            "status": "failed" if failures else "passed",
            "scope": "unshipped curriculum drafts; host only; not OHOS acceptance",
            "engineBackend": args.engine,
            "enginePath": str(engine_path),
            "engineSha256": hashlib.sha256(engine_path.read_bytes()).hexdigest(),
            "engineVersion": native.version if native else subprocess.check_output([str(SQLITE), ":memory:", "SELECT sqlite_version();"], text=True).strip(),
            "draftSourceSha256": {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in sorted(HERE.glob("*.py"))},
            "preExistingBaselineNormalizedQueryDuplicates": baseline_patterns_repeated,
            "productAssetsBefore": before,
            "productAssetsAfter": after,
            "examplesPassed": examples,
            "exercisesPassed": exercises,
            "failures": failures,
            "cases": outcomes,
        }
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        print("report: " + str(report_path))
    for failure in failures:
        print("FAIL " + failure)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
