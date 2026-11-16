#!/usr/bin/env bash
set -euo pipefail

# Build the retained SQLite C bridge for iOS and package device/simulator slices.
# Usage: build-ios-sqlite.sh [output-directory]
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUTPUT="${1:-${QFLI_IOS_SQLITE_OUTPUT:-$ROOT/build/ci-ios-sqlite}}"
DEPLOYMENT_TARGET="${QFLI_IOS_DEPLOYMENT_TARGET:-13.0}"
if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
  echo "Use a fresh output directory: $OUTPUT" >&2
  exit 64
fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
SDK_DEVICE="$(xcrun --sdk iphoneos --show-sdk-path)"
SDK_SIMULATOR="$(xcrun --sdk iphonesimulator --show-sdk-path)"
CLANG="$(xcrun --find clang)"
LIBTOOL="$(xcrun --find libtool)"
LIPO="$(xcrun --find lipo)"

mkdir -p "$OUTPUT/build" "$OUTPUT/headers" "$OUTPUT/package"
cp "$ROOT/native/src/qfli_sql_bridge.h" "$OUTPUT/headers/"
cp "$ROOT/native/third_party/sqlite/sqlite3.h" "$OUTPUT/headers/"
cp "$ROOT/native/third_party/sqlite/sqlite3.c" "$OUTPUT/package/SQLite-LICENSE-source.c"
cp "$ROOT/native/src/qfli_sql_bridge.c" "$OUTPUT/package/SQLite-bridge-source.c"
cp "$ROOT/LICENSE" "$OUTPUT/package/LICENSE"

COMMON=(-std=gnu99 -O2 -fvisibility=default -DSQLITE_THREADSAFE=1
  -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DQS=0 -DSQLITE_OMIT_LOAD_EXTENSION
  -I"$ROOT/native/third_party/sqlite" -I"$ROOT/native/src")

build_slice() {
  local platform="$1" arch="$2" sdk="$3" triple="$4"
  local dir="$OUTPUT/build/$platform-$arch"
  mkdir -p "$dir"
  "$CLANG" "${COMMON[@]}" -isysroot "$sdk" -target "$triple" \
    -c "$ROOT/native/third_party/sqlite/sqlite3.c" -o "$dir/sqlite3.o"
  "$CLANG" "${COMMON[@]}" -isysroot "$sdk" -target "$triple" \
    -c "$ROOT/native/src/qfli_sql_bridge.c" -o "$dir/qfli_sql_bridge.o"
  "$LIBTOOL" -static -no_warning_for_no_symbols -o "$dir/libqfli_sqlite.a" \
    "$dir/sqlite3.o" "$dir/qfli_sql_bridge.o"
  test -s "$dir/libqfli_sqlite.a"
  "$LIPO" "$dir/libqfli_sqlite.a" -verify_arch "$arch"
  xcrun vtool -show-build "$dir/qfli_sql_bridge.o" | tee "$dir/platform.txt"
  if [[ "$platform" == iphoneos ]]; then
    grep -Eq 'platform[[:space:]]+IOS$' "$dir/platform.txt"
  else
    grep -Eq 'platform[[:space:]]+IOSSIMULATOR$' "$dir/platform.txt"
  fi
  printf '%s\n' "$platform/$arch" >> "$OUTPUT/package/slices.txt"
}

build_slice iphoneos arm64 "$SDK_DEVICE" "arm64-apple-ios$DEPLOYMENT_TARGET"
build_slice iphonesimulator arm64 "$SDK_SIMULATOR" "arm64-apple-ios$DEPLOYMENT_TARGET-simulator"
build_slice iphonesimulator x86_64 "$SDK_SIMULATOR" "x86_64-apple-ios$DEPLOYMENT_TARGET-simulator"
mkdir -p "$OUTPUT/build/iphonesimulator"
"$LIPO" -create "$OUTPUT/build/iphonesimulator-arm64/libqfli_sqlite.a" \
  "$OUTPUT/build/iphonesimulator-x86_64/libqfli_sqlite.a" \
  -output "$OUTPUT/build/iphonesimulator/libqfli_sqlite.a"
"$LIPO" "$OUTPUT/build/iphonesimulator/libqfli_sqlite.a" -verify_arch arm64 x86_64

xcodebuild -create-xcframework \
  -library "$OUTPUT/build/iphoneos-arm64/libqfli_sqlite.a" -headers "$OUTPUT/headers" \
  -library "$OUTPUT/build/iphonesimulator/libqfli_sqlite.a" -headers "$OUTPUT/headers" \
  -output "$OUTPUT/package/QfliSqlite.xcframework"

cat > "$OUTPUT/package/PROVENANCE.txt" <<EOF
QFLISQLab retained SQLite 3.50.0 iOS native bridge
Deployment target: $DEPLOYMENT_TARGET
Device SDK: $SDK_DEVICE
Simulator SDK: $SDK_SIMULATOR
Architectures: iphoneos/arm64, iphonesimulator/arm64, iphonesimulator/x86_64
This artifact contains SQLite and the qfli_sql bridge only. It is not a MySQL runtime.
Commit: ${GITHUB_SHA:-$(git -C "$ROOT" rev-parse HEAD)}
EOF
xcodebuild -version >> "$OUTPUT/package/PROVENANCE.txt"
"$CLANG" --version >> "$OUTPUT/package/PROVENANCE.txt"
python3 - "$OUTPUT/package" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import sys
root = Path(sys.argv[1])
info = plistlib.loads((root / 'QfliSqlite.xcframework/Info.plist').read_bytes())
actual = {(item['SupportedPlatform'], item.get('SupportedPlatformVariant', ''),
           tuple(sorted(item['SupportedArchitectures']))) for item in info['AvailableLibraries']}
expected = {('ios', '', ('arm64',)), ('ios', 'simulator', ('arm64', 'x86_64'))}
if actual != expected:
    raise SystemExit(f'Unexpected XCFramework slices: {actual}')
lines = []
for path in sorted(root.rglob('*')):
    if path.is_file():
        lines.append(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(root).as_posix()}\n')
(root / 'SHA256SUMS').write_text(''.join(lines), encoding='utf-8')
PY
tar -C "$OUTPUT/package" -czf "$OUTPUT/native-ios-sqlite.tar.gz" .
printf 'Built iOS SQLite XCFramework: %s\n' "$OUTPUT/package/QfliSqlite.xcframework"
