#!/usr/bin/env bash
# Compile-verifies the OHOS SQLite NAPI bridge against a real DevEco SDK and
# includes the production isolated-validation core. Run the independent real
# engine validation tests as a separate gate; this is not device acceptance.
#
# This is a syntax/typing gate only: it does not run a device, install a HAP,
# or produce shared build output. When no SDK is present the script prints
# SKIP and exits 0, because a compile check is not runtime acceptance.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SDK_SOURCE=""

for candidate in \
    "${DEVECO_SDK_HOME:-}/native" \
    "${DEVECO_SDK_HOME:-}/openharmony/native" \
    "${OHOS_NDK_HOME:-}" \
    "/opt/huawei/DevEco Studio/sdk/default/openharmony/native" \
    "$HOME/Applications/DevEco Studio/sdk/default/openharmony/native"; do
    if [ -n "$candidate" ] && [ -x "$candidate/llvm/bin/clang++" ]; then
        SDK_SOURCE=$candidate
        break
    fi
done

if [ -z "$SDK_SOURCE" ]; then
    echo "SKIP: no DevEco/OpenHarmony native SDK found (set DEVECO_SDK_HOME)."
    echo "      A compile check is not runtime acceptance either way."
    exit 0
fi

CLANGXX="$SDK_SOURCE/llvm/bin/clang++.exe"
[ -x "$CLANGXX" ] || CLANGXX="$SDK_SOURCE/llvm/bin/clang++"
SOURCE="$REPO/ohos/entry/src/main/cpp/qfli_sql_napi.cpp"
VALIDATION="$REPO/ohos/entry/src/main/cpp/qfli_sql_validation.cpp"
INCLUDES=(
    "--sysroot=$SDK_SOURCE/sysroot"
    "-I$SDK_SOURCE/sysroot/usr/include"
    "-I$REPO/native/third_party/sqlite"
    "-I$REPO/native/src"
)

status=0
for target in aarch64-linux-ohos x86_64-linux-ohos; do
    if "$CLANGXX" -fsyntax-only -std=c++17 -Wall -Wextra -Werror \
        -target "$target" "${INCLUDES[@]}" "$SOURCE" "$VALIDATION"; then
        echo "PASS: $target -Werror syntax check for NAPI and isolated validation core"
    else
        echo "FAIL: $target syntax check for qfli_sql_napi.cpp"
        status=1
    fi
done

exit "$status"
