set -o pipefail
LOG=/mnt/d/MyNewProjects/qfli_sql/build/mysql-port/phone-host-build.log
cd /root/qfli-mysql-port/ohos-build
{
  echo "=== qfli_mysql ==="
  cmake --build . --target qfli_mysql -j1
  echo "=== qfli_mysql_server ==="
  cmake --build . --target qfli_mysql_server -j1
  echo "=== qfli_mysql_launcher ==="
  cmake --build . --target qfli_mysql_launcher -j1
  echo "=== package ==="
  cmake -DQFLI_MYSQL_PORT_ROOT=/root/qfli-mysql-port -P /mnt/d/MyNewProjects/qfli_sql/native/mysql/package-runtime.cmake
} > "$LOG" 2>&1
echo "build+package exit=$?"
tail -3 "$LOG"
