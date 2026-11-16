#!/usr/bin/env bash
set -euo pipefail
PACKAGE="${1:?package directory}"
ABI="${2:?Android ABI}"
RUNTIME="$PACKAGE/mysql"
READELF="${READELF:-llvm-readelf-18}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# Reuse the production Oracle ABI, interpreter, 16 KiB and dependency audit.
pwsh -NoProfile -File "$REPO_ROOT/native/mysql/android/stage.ps1" \
  -Abi "$ABI" -Runtime "$RUNTIME" -ReadElf "$(command -v "$READELF")"
python3 "$REPO_ROOT/tool/ci/package_native.py" check-android-sqlite \
  "$PACKAGE/sqlite/$ABI/libqfli_sqlite.so" "$ABI"
