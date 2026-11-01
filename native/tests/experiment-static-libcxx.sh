set -euo pipefail
# Static-libc++ prototype: relink the built server objects against the OHOS
# static C++ runtime so the private server image does not share libc++_shared
# locks with the parent. Experiment only; no production CMake change.
cd /root/qfli-mysql-port/ohos-build/sql
SDK=/root/qfli-mysql-port/ohos-sdk
ERP=/mnt/d/MyNewProjects/qfli_sql/native/mysql
LINK=$(cat CMakeFiles/qfli_mysql_server.dir/link.txt)

# Replace output path and strip the shared libc++ flags the toolchain injects,
# then append the static archives and the private binding options.
RELINK=$(echo "$LINK" \
  | sed 's#-o [^ ]*libqfli_mysql_server.so#-o /tmp/libqfli_mysql_server_static.so#' \
  | sed 's#-stdlib=libc++#-nostdlib++#' )
STATIC="$SDK/llvm/lib/aarch64-linux-ohos/c++/libc++_static.a"
RELINK="$RELINK -Wl,--whole-archive $STATIC -Wl,--no-whole-archive $SDK/llvm/lib/aarch64-linux-ohos/libunwind.a"
RELINK="$RELINK -Wl,--version-script=$ERP/qfli_mysql_server.map -Wl,-Bsymbolic-functions"

eval "$RELINK" 2>/tmp/static_relink.err || { echo "RELINK_FAILED"; tail -25 /tmp/static_relink.err; exit 1; }

echo "=== static-libc++ server NEEDED ==="
llvm-readelf-18 -d /tmp/libqfli_mysql_server_static.so | grep -iE "NEEDED|SONAME"
echo "=== exported defined symbols (expect 3) ==="
llvm-nm-18 -D --defined-only /tmp/libqfli_mysql_server_static.so | wc -l
echo "=== libc++_shared still a dependency? ==="
llvm-readelf-18 -d /tmp/libqfli_mysql_server_static.so | grep -c "libc++_shared" || echo 0
