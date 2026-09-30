#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_ROOT/../.." && pwd)"
PORT_ROOT="${QFLI_MYSQL_PORT_ROOT:-$REPO_ROOT/build/mysql-port}"
SDK_ROOT="${QFLI_OHOS_SDK:-/mnt/d/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native}"
CLANG="${QFLI_CLANG:-/usr/bin/clang-18}"
ARCHIVE="${QFLI_OPENSSL_ARCHIVE:-$PORT_ROOT/openssl-3.5.3.tar.gz}"
OPENSSL_SHA256=c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf
SOURCE="$PORT_ROOT/openssl-3.5.3"
BUILD="$PORT_ROOT/openssl-build"
PREFIX="$PORT_ROOT/openssl-ohos"
RESOURCE_DIR="$SDK_ROOT/llvm/lib/clang/15.0.4"

test -x "$CLANG"
test -d "$SDK_ROOT/sysroot"
test -d "$RESOURCE_DIR"
printf '%s  %s\n' "$OPENSSL_SHA256" "$ARCHIVE" | sha256sum --check --status
mkdir -p "$PORT_ROOT" "$BUILD"
if [[ ! -d "$SOURCE" ]]; then
  tar --no-same-owner -xzf "$ARCHIVE" -C "$PORT_ROOT"
fi

export CC="$CLANG --target=aarch64-linux-ohos --sysroot=$SDK_ROOT/sysroot -resource-dir=$RESOURCE_DIR -fuse-ld=lld"
export AR=/usr/bin/llvm-ar-18
export RANLIB=/usr/bin/llvm-ranlib-18
export CFLAGS="-O2 -fPIC"
export LDFLAGS="-L$SDK_ROOT/llvm/lib/aarch64-linux-ohos"
cd "$BUILD"
perl "$SOURCE/Configure" linux-aarch64 no-shared no-tests no-docs no-apps \
  --prefix="$PREFIX" --libdir=lib
make -j1 build_libs
make install_dev

"$CLANG" --target=aarch64-linux-ohos --sysroot="$SDK_ROOT/sysroot" \
  -resource-dir="$RESOURCE_DIR" -fuse-ld=lld \
  -L"$SDK_ROOT/llvm/lib/aarch64-linux-ohos" -I"$PREFIX/include" \
  -fPIC -shared -Wl,--no-undefined "$SCRIPT_ROOT/openssl-link-smoke.c" \
  "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" -pthread -ldl \
  -o "$PORT_ROOT/libopenssl_ohos_smoke.so"
readelf -h -d "$PORT_ROOT/libopenssl_ohos_smoke.so"
