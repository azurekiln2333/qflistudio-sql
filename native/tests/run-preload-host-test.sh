#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d /tmp/qfli-preload-host.XXXXXX)
clang++ -std=c++17 -Wall -Wextra -Werror -fPIC -shared \
  "$REPO/native/tests/qfli_mysql_preload_host_stub.cpp" -o "$WORK/closure.so"
clang++ -std=c++17 -Wall -Wextra -Werror \
  -I"$REPO/native/mysql" -I"$REPO/ohos/entry/src/main/cpp" \
  "$REPO/native/mysql/qfli_mysql_host.cpp" \
  "$REPO/ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp" \
  "$REPO/native/tests/qfli_mysql_preload_host_test.cpp" \
  -Wl,--wrap=pthread_create -ldl -lpthread -o "$WORK/preload_host_test"
"$WORK/preload_host_test" "$WORK/closure.so"
