#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d /tmp/qfli-stdio-proto.XXXXXX)
cd "$WORK"
clang++ -std=c++17 -Wall -Wextra -Werror -D_GNU_SOURCE -I"$REPO/native/mysql" \
  "$REPO/native/tests/qfli_mysql_stdio_protocol_test.cpp" -lpthread -o stdio_test
./stdio_test
