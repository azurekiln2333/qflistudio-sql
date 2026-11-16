#!/usr/bin/env bash
set -euo pipefail

# Build one real Oracle MySQL Android runtime and the project SQLite library.
# The workflow supplies a fresh work directory and verified source archives.

ABI="${QFLI_ANDROID_ABI:?set QFLI_ANDROID_ABI to arm64-v8a or x86_64}"
WORK="${QFLI_MYSQL_ANDROID_WORK:?set QFLI_MYSQL_ANDROID_WORK}"
NDK="${QFLI_ANDROID_NDK:?set QFLI_ANDROID_NDK}"
MYSQL_ARCHIVE="${QFLI_MYSQL_ARCHIVE:?set QFLI_MYSQL_ARCHIVE}"
OPENSSL_ARCHIVE="${QFLI_OPENSSL_ARCHIVE:?set QFLI_OPENSSL_ARCHIVE}"
JOBS="${QFLI_BUILD_JOBS:-1}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'QFLI_BUILD_JOBS must be positive' >&2; exit 64; }
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "$ABI" in
  arm64-v8a|x86_64) ;;
  *) echo "Unsupported Android ABI: $ABI" >&2; exit 64 ;;
esac

mkdir -p "$WORK"
printf '%s  %s\n' a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7 "$MYSQL_ARCHIVE" | sha256sum --check
printf '%s  %s\n' c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf "$OPENSSL_ARCHIVE" | sha256sum --check

# Build the eight host generators from an unpatched source tree. The Android
# configure script then uses these tools with a separate patched source tree.
HOST_SOURCE="$WORK/mysql-8.4.6-host"
HOST_BUILD="$WORK/mysql-host-build"
if [[ ! -d "$HOST_SOURCE" ]]; then
  tar --no-same-owner -xzf "$MYSQL_ARCHIVE" -C "$WORK"
  mv "$WORK/mysql-8.4.6" "$HOST_SOURCE"
fi
export QFLI_MYSQL_HOST_SOURCE="$HOST_SOURCE"
export QFLI_MYSQL_HOST_BUILD="$HOST_BUILD"
bash "$REPO_ROOT/native/mysql/build-host-tools.sh"

export QFLI_MYSQL_HOST_TOOLS="$HOST_BUILD/runtime_output_directory"
export QFLI_ANDROID_NDK="$NDK"
export QFLI_ANDROID_ABI="$ABI"
export QFLI_MYSQL_ANDROID_WORK="$WORK"
export QFLI_OPENSSL_ARCHIVE="$OPENSSL_ARCHIVE"
export QFLI_MYSQL_ARCHIVE="$MYSQL_ARCHIVE"

bash "$REPO_ROOT/native/mysql/android/build-openssl.sh"
bash "$REPO_ROOT/native/mysql/android/configure.sh"
cmake --build "$WORK/android-build-$ABI" \
  --target qfli_mysql_bridge qfli_mysql_launcher mysqld --parallel "$JOBS"

PACKAGE="$WORK/package"
mkdir -p "$PACKAGE"
RUNTIME="$PACKAGE/mysql"
export QFLI_MYSQL_ANDROID_OUTPUT="$RUNTIME"
bash "$REPO_ROOT/native/mysql/android/export-runtime.sh"

# Build the project SQLite bridge with the same NDK and API contract.
SQLITE_BUILD="$WORK/sqlite-$ABI"
cmake -S "$REPO_ROOT/native/runtime" -B "$SQLITE_BUILD" \
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI="$ABI" -DANDROID_PLATFORM=android-28 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS_RELEASE='-O2 -DNDEBUG' \
  -DCMAKE_SHARED_LINKER_FLAGS='-Wl,-z,max-page-size=16384,-z,common-page-size=16384'
cmake --build "$SQLITE_BUILD" --parallel 2
mkdir -p "$PACKAGE/sqlite/$ABI"
cp "$SQLITE_BUILD/libqfli_sqlite.so" "$PACKAGE/sqlite/$ABI/libqfli_sqlite.so"
cp "$REPO_ROOT/native/src/qfli_sql_bridge.h" "$PACKAGE/sqlite/"
printf 'abi=%s\nmysql_source_sha256=%s\nopenssl_source_sha256=%s\n' \
  "$ABI" \
  a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7 \
  c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf \
  > "$PACKAGE/CI_PROVENANCE.txt"
{
  printf 'commit=%s\n' "${GITHUB_SHA:-local}"
  cat "$NDK/source.properties"
  clang-18 --version
  cmake --version
} >> "$PACKAGE/CI_PROVENANCE.txt"
printf '%s\n' 'SQLite 3.50.0 is in the public domain; see the corresponding source archive.' > "$PACKAGE/sqlite/LICENSE.txt"
echo "$PACKAGE"
