#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${QFLI_MYSQL_ANDROID_WORK:?Set a separate Android work directory}"
NDK="${QFLI_ANDROID_NDK:?Set Android NDK 27 root}"
ABI="${QFLI_ANDROID_ABI:-x86_64}"
API=28
case "$ABI" in
  x86_64) TRIPLE=x86_64-linux-android; CONFIG=linux-x86_64;;
  arm64-v8a) TRIPLE=aarch64-linux-android; CONFIG=linux-aarch64;;
  *) printf 'Unsupported Oracle ABI: %s\n' "$ABI" >&2; exit 1;;
esac
ARCHIVE="${QFLI_OPENSSL_ARCHIVE:?Set the verified OpenSSL 3.5.3 archive}"
printf '%s  %s\n' c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf "$ARCHIVE" | sha256sum --check --status
PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$PREBUILT" ]] || PREBUILT="$NDK/toolchains/llvm/prebuilt/windows-x86_64"
SOURCE="$WORK/openssl-3.5.3"
BUILD="$WORK/openssl-build-$ABI"
PREFIX="$WORK/openssl-$ABI"
mkdir -p "$WORK" "$BUILD"
if [[ ! -d "$SOURCE" ]]; then tar --no-same-owner -xzf "$ARCHIVE" -C "$WORK"; fi
export CC="/usr/bin/clang-18 --target=$TRIPLE$API --sysroot=$PREBUILT/sysroot -resource-dir=$PREBUILT/lib/clang/18 -fuse-ld=lld"
export AR=/usr/bin/llvm-ar-18 RANLIB=/usr/bin/llvm-ranlib-18
export CFLAGS='-O1 -fPIC'
export LDFLAGS='-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384'
cd "$BUILD"
perl "$SOURCE/Configure" "$CONFIG" no-shared no-tests no-docs no-apps no-asm --prefix="$PREFIX" --libdir=lib
make -j1 build_libs
make install_dev
