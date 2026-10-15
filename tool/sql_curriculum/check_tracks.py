"""Ad-hoc check restricted to selected tracks (avoids clashing with a peer's
in-progress tracks). Usage: python tool/sql_curriculum/check_tracks.py t1 t2 ...
"""

from __future__ import annotations

import importlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
if str(HERE / "lessons") not in sys.path:
    sys.path.insert(0, str(HERE / "lessons"))

SQLITE = Path(r"D:\ProgramFiles\platform-tools\sqlite3.exe")
NO_ROWS = "(no rows)"


def normalize(text: str) -> str:
    return "\n".join(
        line.rstrip() for line in text.strip().splitlines() if line.strip() != ""
    )


def expected_of(text: str) -> str:
    return "" if text.strip() == NO_ROWS else normalize(text)


def run(db: Path, script: str) -> tuple[int, str, str]:
    proc = subprocess.run(
        [str(SQLITE), str(db)], input=script, capture_output=True, text=True, encoding="utf-8"
    )
    return proc.returncode, proc.stdout, proc.stderr


def main() -> int:
    mods = sys.argv[1:]
    if not mods:
        print("usage: check_tracks.py track_08_ddl ...")
        return 2
    wd = Path(tempfile.mkdtemp(prefix="qfli_check_"))
    fails = 0
    total = 0
    ex_total = 0
    ex_fail = 0
    try:
        for name in mods:
            mod = importlib.import_module(name)
            for lesson in sorted(mod.LESSONS, key=lambda x: x.number):
                total += 1
                db = wd / f"{lesson.tid}.db"
                rc, out, err = run(db, lesson.code)
                if rc != 0 or normalize(out) != expected_of(lesson.expected):
                    fails += 1
                    print(f"FAIL {lesson.tid}\n  exp {expected_of(lesson.expected)!r}\n  act {normalize(out)!r}\n  err {err.strip()[:120]}")
                for i, ex in enumerate(lesson.exercises, 1):
                    if not ex.verify_query:
                        continue
                    ex_total += 1
                    rc, out, err = run(wd / f"{lesson.tid}_e{i}.db", f"{lesson.setup.rstrip()}\n{ex.answer}")
                    if rc != 0 or normalize(out) != expected_of(ex.expected):
                        ex_fail += 1
                        print(f"FAIL {lesson.tid} ex{i}\n  exp {expected_of(ex.expected)!r}\n  act {normalize(out)!r}\n  err {err.strip()[:120]}")
    finally:
        shutil.rmtree(wd, ignore_errors=True)
    print(f"lessons {total - fails}/{total}, exercises {ex_total - ex_fail}/{ex_total}")
    return 1 if (fails or ex_fail) else 0


if __name__ == "__main__":
    raise SystemExit(main())
