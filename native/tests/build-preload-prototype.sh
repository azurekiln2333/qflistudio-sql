set -euo pipefail
# Build the option-B prototype DSO + probe-enabled NAPI against the checked-in
# repo CMake, then assert the rebuilt arm64 ELF properties before any staging.
# pipefail ensures a failed compiler/linker cannot be masked by `tail`.
BUILD=/root/qfli-mysql-port/ohos-build
REPO_CMAKE=/mnt/d/MyNewProjects/qfli_sql/native/mysql/ohos-targets.cmake
cd "$BUILD"

# Pin the platform CMake to the checked-in repo copy.
cmake -DQFLI_MYSQL_PLATFORM_CMAKE="$REPO_CMAKE" -DQFLI_MYSQL_PRELOAD_PROTOTYPE=ON . \
  > /tmp/proto-reconfigure.log 2>&1 || { echo RECONFIGURE_FAILED; tail -20 /tmp/proto-reconfigure.log; exit 1; }

echo "=== production server (clean map) ==="
cmake --build . --target qfli_mysql_server -j1 > /tmp/build-server.log 2>&1 || { echo BUILD_SERVER_FAILED; tail -30 /tmp/build-server.log; exit 1; }
tail -2 /tmp/build-server.log
echo "=== prototype DSO ==="
cmake --build . --target qfli_mysql_server_proto -j1 > /tmp/build-proto.log 2>&1 || { echo BUILD_PROTO_FAILED; tail -30 /tmp/build-proto.log; exit 1; }
tail -2 /tmp/build-proto.log
echo "=== NAPI probe module ==="
cmake --build . --target qfli_mysql -j1 > /tmp/build-napi.log 2>&1 || { echo BUILD_NAPI_FAILED; tail -30 /tmp/build-napi.log; exit 1; }
tail -2 /tmp/build-napi.log

LIBDIR="$BUILD/qfli-runtime/lib"
PROTO="$LIBDIR/libqfli_mysql_server_proto.so"
for f in "$LIBDIR/libqfli_mysql.so" "$LIBDIR/libqfli_mysql_server.so" "$PROTO"; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
done

echo "=== assert prototype ELF properties ==="
# NEEDED must be libc.so only (static private C++ runtime).
if llvm-readelf-18 -d "$PROTO" | grep "NEEDED" | grep -qv "libc.so"; then
  echo "ASSERT_FAIL: prototype NEEDED a library other than libc.so"; llvm-readelf-18 -d "$PROTO" | grep NEEDED; exit 1
fi
echo "  NEEDED libc.so only: ok"
# No external imports for the interposed calls.
if llvm-nm-18 -D -u "$PROTO" | grep -qwE "exit|pthread_create|pthread_atfork"; then
  echo "ASSERT_FAIL: interposed calls still external"; exit 1
fi
echo "  exit/pthread_create/pthread_atfork not external: ok"
# The proto probe entry must be exported.
for sym in qfli_mysql_proto_report qfli_mysql_proto_ready qfli_mysql_proto_enter_child_scope qfli_mysql_proto_child_exit; do
  llvm-nm-18 -D --defined-only "$PROTO" | grep -q "$sym" || { echo "ASSERT_FAIL: missing export $sym"; exit 1; }
done
echo "  prototype exports present: ok"
# The probe NAPI module must contain the protoProbe registration string.
PROTO_STR=$(strings "$LIBDIR/libqfli_mysql.so" | grep -c "protoProbe" || true)
if [ "$PROTO_STR" -lt 1 ]; then
  echo "ASSERT_FAIL: NAPI missing protoProbe"; exit 1
fi
echo "  NAPI protoProbe present: ok ($PROTO_STR)"

echo "=== artifacts ==="
ls -la "$LIBDIR/libqfli_mysql.so" "$LIBDIR/libqfli_mysql_server.so" "$PROTO"
