#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${QFLI_MYSQL_ANDROID_WORK:?Set a separate Android work directory}"
NDK="${QFLI_ANDROID_NDK:?Set Android NDK 27 root}"
ABI="${QFLI_ANDROID_ABI:-x86_64}"
HOST_TOOLS="${QFLI_MYSQL_HOST_TOOLS:?Set matching Oracle host generators}"
ARCHIVE="${QFLI_MYSQL_ARCHIVE:?Set official MySQL 8.4.6 archive}"
printf '%s  %s\n' a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7 "$ARCHIVE" | sha256sum --check --status
mkdir -p "$WORK"
SOURCE="$WORK/mysql-8.4.6"
STAMP="$(sha256sum "$ARCHIVE" "$HERE/../patches/0001-ohos-platform.patch" "$HERE/0001-android-platform.patch" "$HERE/0002-android-types.patch" | sha256sum | cut -d ' ' -f1)"
if [[ -d "$SOURCE" ]]; then
  [[ -f "$SOURCE/.qfli-android-prepared" && $(< "$SOURCE/.qfli-android-prepared") == "$STAMP" ]] || {
    printf 'Source has different preparation inputs; use a fresh Android work directory.\n' >&2; exit 1;
  }
fi
if [[ ! -d "$SOURCE" ]]; then
  tar --no-same-owner -xzf "$ARCHIVE" -C "$WORK"
  patch --directory="$SOURCE" -p1 --batch < "$HERE/../patches/0001-ohos-platform.patch"
  patch --directory="$SOURCE" -p1 --batch < "$HERE/0001-android-platform.patch"
  patch --directory="$SOURCE" -p1 --batch < "$HERE/0002-android-types.patch"
  printf '%s\n' "$STAMP" > "$SOURCE/.qfli-android-prepared"
fi
for tool in comp_err comp_client_err comp_sql uca9dump gen_lex_token gen_keyword_list gen_lex_hash protoc; do test -x "$HOST_TOOLS/$tool"; done
PREFIX="$WORK/openssl-$ABI"
test -f "$PREFIX/lib/libssl.a"
PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$PREBUILT" ]] || PREBUILT="$NDK/toolchains/llvm/prebuilt/windows-x86_64"
case "$ABI" in
  x86_64) TRIPLE=x86_64-linux-android;;
  arm64-v8a) TRIPLE=aarch64-linux-android;;
  *) printf 'Unsupported Oracle ABI\n' >&2; exit 1;;
esac
cmake --fresh -S "$SOURCE" -B "$WORK/android-build-$ABI" \
  -DCMAKE_TOOLCHAIN_FILE="$HERE/android-toolchain.cmake" \
  -DQFLI_ANDROID_NDK="$NDK" -DQFLI_ANDROID_ABI="$ABI" \
  -DQFLI_MYSQL_HOST_TOOLS="$HOST_TOOLS" -DWITH_PROTOC="$HOST_TOOLS/protoc" \
  -DQFLI_MYSQL_PLATFORM_CMAKE="$HERE/android-targets.cmake" \
  -DQFLI_MYSQL_WITHOUT_LINE_EDITING=ON -DQFLI_MYSQL_WITHOUT_ZSTD_DICT_BUILDER=ON \
  -DQFLI_MYSQL_STATIC_ABSEIL=ON -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE='-O1 -DNDEBUG' -DCMAKE_CXX_FLAGS_RELEASE='-O1 -DNDEBUG' \
  -DHAVE_SETNS=FALSE -DHAVE_CLOCK_GETTIME=TRUE -DHAVE_CLOCK_REALTIME=TRUE \
  -DHAVE_FALLOC_PUNCH_HOLE_AND_KEEP_SIZE=FALSE -DHAVE___BUILTIN_FFS=FALSE \
  -DRESOLV_LIBRARY="$PREBUILT/sysroot/usr/lib/$TRIPLE/28/libc.so" \
  -DWITH_SSL=system -DOPENSSL_ROOT_DIR="$PREFIX" -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
  -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
  -DWITH_TIRPC=bundled -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_BUILD_LIBPROTOC=ON \
  -DWITH_ROUTER=OFF -DWITH_MYSQLX=OFF -DWITH_NDB=OFF -DWITH_NDBCLUSTER_STORAGE_ENGINE=OFF \
  -DWITH_GROUP_REPLICATION=OFF -DWITH_UNIT_TESTS=OFF -DWITH_AUTHENTICATION_CLIENT_PLUGINS=OFF \
  -DWITH_AUTHENTICATION_LDAP=OFF -DWITH_AUTHENTICATION_KERBEROS=OFF -DWITH_AUTHENTICATION_WEBAUTHN=OFF \
  -DWITH_NUMA=OFF -DWITH_SYSTEMD=OFF -DWITH_EXT_BACKTRACE=OFF -DWITH_EDITLINE=system \
  -DWITH_SASL=system -DWITH_LDAP=system -DWITH_KERBEROS=none -DWITH_FIDO=none -DWITH_CURL=none \
  -DUSE_BISON_RESULTS_FROM_MAKE_DIST=ON
