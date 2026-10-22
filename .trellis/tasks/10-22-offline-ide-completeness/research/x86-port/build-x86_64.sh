#!/usr/bin/env bash
set -euo pipefail
TASK_SCRIPTS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$TASK_SCRIPTS/../../../../.." && pwd)
PORT_ROOT=/root/qfli-mysql-ohos-x64-1022
ORIGINAL=/root/qfli-mysql-port
INSTALLED_SDK=/mnt/d/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native
SDK_ROOT=$PORT_ROOT/ohos-sdk
SOURCE=$PORT_ROOT/mysql-8.4.6
PREFIX=$PORT_ROOT/openssl-ohos
TARGET_BUILD=$PORT_ROOT/ohos-build
HOST_TOOLS=$ORIGINAL/host-tools
JOBS=3

test -f "$REPO/native/mysql/ohos-targets.cmake"
test "$(realpath -m "$PORT_ROOT")" = /root/qfli-mysql-ohos-x64-1022
test -d "$ORIGINAL/mysql-8.4.6"
for tool in comp_err comp_client_err comp_sql uca9dump gen_lex_token gen_keyword_list gen_lex_hash protoc; do
  test -x "$HOST_TOOLS/$tool"
done
mkdir -p "$PORT_ROOT"
printf 'Isolated build log: %s\n' "$PORT_ROOT/build.log"
exec >> "$PORT_ROOT/build.log" 2>&1
trap 'status=$?; printf "TERMINAL status=%s at %s\n" "$status" "$(date --iso-8601=seconds)"' EXIT
printf 'START isolated x86_64 port %s\n' "$(date --iso-8601=seconds)"
sha256sum "$REPO/native/mysql/ohos-targets.cmake" "$REPO/native/mysql/package-runtime.cmake"
if [[ ! -f "$PORT_ROOT/source-copy-verified" ]]; then
  mkdir -p "$SOURCE"
  cp -a --reflink=never --sparse=never "$ORIGINAL/mysql-8.4.6/." "$SOURCE/"
  diff -qr "$ORIGINAL/mysql-8.4.6" "$SOURCE"
  touch "$PORT_ROOT/source-copy-verified"
fi
if [[ ! -f "$PORT_ROOT/sdk-copy-verified" ]]; then
  mkdir -p "$SDK_ROOT"
  cp -a --reflink=never --sparse=never "$ORIGINAL/ohos-sdk/." "$SDK_ROOT/"
  diff -qr --exclude=x86_64-linux-ohos "$ORIGINAL/ohos-sdk" "$SDK_ROOT"
  diff -qr "$ORIGINAL/ohos-sdk/sysroot/usr/lib/x86_64-linux-ohos" "$SDK_ROOT/sysroot/usr/lib/x86_64-linux-ohos"
  touch "$PORT_ROOT/sdk-copy-verified"
fi
if [[ ! -d "$SDK_ROOT/llvm/lib/x86_64-linux-ohos" ]]; then
  cp -a --reflink=never "$INSTALLED_SDK/llvm/lib/x86_64-linux-ohos" "$SDK_ROOT/llvm/lib/"
fi
diff -qr "$INSTALLED_SDK/llvm/lib/x86_64-linux-ohos" "$SDK_ROOT/llvm/lib/x86_64-linux-ohos"
test -f "$SDK_ROOT/llvm/lib/x86_64-linux-ohos/c++/libc++_static.a"
test -f "$SDK_ROOT/llvm/lib/x86_64-linux-ohos/libunwind.a"
test -f "$SDK_ROOT/sysroot/usr/lib/x86_64-linux-ohos/libace_napi.z.so"

ARCHIVE=$REPO/build/mysql-port/openssl-3.5.3.tar.gz
printf '%s  %s\n' c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf "$ARCHIVE" | sha256sum --check --status
if [[ ! -d "$PORT_ROOT/openssl-3.5.3" ]]; then
  tar --no-same-owner -xzf "$ARCHIVE" -C "$PORT_ROOT"
fi
if [[ ! -f "$PREFIX/lib/libssl.a" || ! -f "$PREFIX/lib/libcrypto.a" ]]; then
  mkdir -p "$PORT_ROOT/openssl-build"
  (
    cd "$PORT_ROOT/openssl-build"
    export CC="/usr/bin/clang-18 --target=x86_64-linux-ohos --sysroot=$SDK_ROOT/sysroot -resource-dir=$SDK_ROOT/llvm/lib/clang/15.0.4 -fuse-ld=lld"
    export AR=/usr/bin/llvm-ar-18 RANLIB=/usr/bin/llvm-ranlib-18
    export CFLAGS='-O2 -fPIC' LDFLAGS="-L$SDK_ROOT/llvm/lib/x86_64-linux-ohos"
    if [[ ! -f Makefile ]]; then
      perl "$PORT_ROOT/openssl-3.5.3/Configure" linux-x86_64 no-shared no-tests no-docs no-apps --prefix="$PREFIX" --libdir=lib
    fi
    make -j"$JOBS" build_libs
    make install_dev
  )
fi
/usr/bin/clang-18 --target=x86_64-linux-ohos --sysroot="$SDK_ROOT/sysroot" \
  -resource-dir="$SDK_ROOT/llvm/lib/clang/15.0.4" -fuse-ld=lld \
  -L"$SDK_ROOT/llvm/lib/x86_64-linux-ohos" -I"$PREFIX/include" \
  -fPIC -shared -Wl,--no-undefined "$REPO/native/mysql/openssl-link-smoke.c" \
  "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" -pthread -ldl \
  -o "$PORT_ROOT/libopenssl_ohos_smoke.so"
readelf -h -d "$PORT_ROOT/libopenssl_ohos_smoke.so"

cmake -S "$SOURCE" -B "$TARGET_BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$TASK_SCRIPTS/ohos-toolchain-x86_64.cmake" \
  -DQFLI_SQL_REPO="$REPO" -DQFLI_OHOS_SDK="$SDK_ROOT" \
  -DQFLI_CLANG=/usr/bin/clang-18 -DQFLI_CLANGXX=/usr/bin/clang++-18 \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DQFLI_MYSQL_HOST_TOOLS="$HOST_TOOLS" -DWITH_PROTOC="$HOST_TOOLS/protoc" \
  -DQFLI_MYSQL_WITHOUT_LINE_EDITING=ON -DQFLI_MYSQL_WITHOUT_ZSTD_DICT_BUILDER=ON \
  -DQFLI_MYSQL_STATIC_ABSEIL=ON \
  -DQFLI_MYSQL_PLATFORM_CMAKE="$TASK_SCRIPTS/ohos-targets-x86_64.cmake" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE='-O1 -DNDEBUG' \
  -DCMAKE_CXX_FLAGS_RELEASE='-O1 -DNDEBUG' \
  -DHAVE_SETNS=FALSE -DHAVE_CLOCK_GETTIME=FALSE -DHAVE_CLOCK_REALTIME=FALSE \
  -DHAVE_FALLOC_PUNCH_HOLE_AND_KEEP_SIZE=FALSE -DHAVE___BUILTIN_FFS=FALSE \
  -DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=TRUE \
  -DWITH_SSL=system -DOPENSSL_ROOT_DIR="$PREFIX" -DWITH_TIRPC=bundled \
  -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_BUILD_LIBPROTOC=ON \
  -DOPENSSL_INCLUDE_DIR="$PREFIX/include" -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
  -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
  -DWITH_ROUTER=OFF -DWITH_MYSQLX=OFF -DWITH_NDB=OFF -DWITH_NDBCLUSTER_STORAGE_ENGINE=OFF \
  -DWITH_GROUP_REPLICATION=OFF -DWITH_UNIT_TESTS=OFF \
  -DWITH_AUTHENTICATION_CLIENT_PLUGINS=OFF -DWITH_AUTHENTICATION_LDAP=OFF \
  -DWITH_AUTHENTICATION_KERBEROS=OFF -DWITH_AUTHENTICATION_WEBAUTHN=OFF \
  -DWITH_NUMA=OFF -DWITH_SASL=system -DWITH_LDAP=system -DWITH_KERBEROS=none \
  -DWITH_FIDO=none -DWITH_CURL=none -DWITH_EDITLINE=system -DWITH_SYSTEMD=OFF \
  -DWITH_EXT_BACKTRACE=OFF -DUSE_BISON_RESULTS_FROM_MAKE_DIST=ON

cmake --build "$TARGET_BUILD" --target qfli_mysql qfli_mysql_server qfli_mysql_launcher qfli_mysql_server_proto -j"$JOBS"
cmake -DQFLI_SQL_REPO="$REPO" -DQFLI_MYSQL_PORT_ROOT="$PORT_ROOT" -P "$TASK_SCRIPTS/package-runtime-x86_64.cmake"
printf 'COMPLETE isolated x86_64 port %s\n' "$(date --iso-8601=seconds)"
