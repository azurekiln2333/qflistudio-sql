# Existing curriculum baseline, 2026-10-22

Both validators were executed before any expansion. These are HOST SQLite CLI results, not OHOS acceptance.

## Authoring source

```
sqlite examples passed: 120/120
exercise answers passed: 240/240
mysql not executed: 6
  SKIP sql-tutorial-121 (MySQL 8.0): requires MySQL
  SKIP sql-tutorial-122 (MySQL 8.0): requires MySQL
  SKIP sql-tutorial-123 (MySQL 8.0): requires MySQL
  SKIP sql-tutorial-124 (MySQL 8.0): requires MySQL
  SKIP sql-tutorial-125 (MySQL 8.0): requires MySQL
  SKIP sql-tutorial-126 (MySQL 8.0): requires MySQL
all authored expectations matched execution
```

## Packaged JSON

```
packaged-JSON sqlite examples passed: 120
packaged-JSON exercise expectations matched: 240/240
mysql not executed: 6
  SKIP sql-tutorial-121: requires native MySQL execution
  SKIP sql-tutorial-122: requires native MySQL execution
  SKIP sql-tutorial-123: requires native MySQL execution
  SKIP sql-tutorial-124: requires native MySQL execution
  SKIP sql-tutorial-125: requires native MySQL execution
  SKIP sql-tutorial-126: requires native MySQL execution
all packaged-JSON executions matched authored lesson and exercise outputs
```

All six MySQL entries remain unexecuted in this host check. New native coverage derives the denominator from the actual catalog and executes each engine separately. OHOS structured SQLite script dispatch is being fixed; SQL signing is absent and live emulator x86_64 lacks real Oracle runtime.
