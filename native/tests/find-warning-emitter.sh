set -uo pipefail
SRC=/root/qfli-mysql-port/mysql-8.4.6
BUILD=/root/qfli-mysql-port/ohos-build
echo "=== source files containing the exact warning text ==="
grep -rln "might allow a mutex/rw_lock violation" "$SRC/" 2>/dev/null
echo "=== which objects in the link contain it ==="
cd "$BUILD"
for obj in $(find storage/innobase -name '*.o' 2>/dev/null); do
  if strings "$obj" 2>/dev/null | grep -q "might allow a mutex/rw_lock violation"; then
    echo "$obj"
  fi
done
echo "=== also check sql/ objects ==="
for obj in $(find sql -name '*.o' 2>/dev/null); do
  if strings "$obj" 2>/dev/null | grep -q "might allow a mutex/rw_lock violation"; then
    echo "$obj"
  fi
done
