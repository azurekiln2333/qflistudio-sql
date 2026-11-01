set -euo pipefail
# Rebuild the server + private proto DSO with the InnoDB memory barrier enabled
# for the cross build, then prove the macro reaches the InnoDB compile units and
# the empty-barrier branch is no longer taken.
BUILD=/root/qfli-mysql-port/ohos-build
REPO_CMAKE=/mnt/d/MyNewProjects/qfli_sql/native/mysql/ohos-targets.cmake
cd "$BUILD"
cmake -DQFLI_MYSQL_PLATFORM_CMAKE="$REPO_CMAKE" -DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=TRUE . \
  > /tmp/reconf-fence.log 2>&1 || { echo RECONFIGURE_FAILED; tail -20 /tmp/reconf-fence.log; exit 1; }

echo "=== macro present in InnoDB build flags? ==="
grep -rl "HAVE_IB_GCC_ATOMIC_THREAD_FENCE" storage/innobase/CMakeFiles/*/flags.make 2>/dev/null | head -3 || \
  grep -r "HAVE_IB_GCC_ATOMIC_THREAD_FENCE" storage/innobase/CMakeFiles/ 2>/dev/null | head -3 || \
  echo "(checking compile commands)"

echo "=== rebuild innobase + server + proto (single job) ==="
cmake --build . --target qfli_mysql_server_proto -j1 > /tmp/bfence1.log 2>&1 || { echo PROTO_FAIL; tail -30 /tmp/bfence1.log; exit 1; }
cmake --build . --target qfli_mysql -j1 > /tmp/bfence2.log 2>&1 || { echo NAPI_FAIL; tail -30 /tmp/bfence2.log; exit 1; }
echo "BUILD_OK"
ls -la qfli-runtime/lib/libqfli_mysql_server_proto.so
