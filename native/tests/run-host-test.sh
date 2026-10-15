#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORK=$(mktemp -d /tmp/qfli-host-check.XXXXXX)
cd "$WORK"
clang++ -std=c++17 -Wall -Wextra -Werror -DQFLI_MYSQL_HOST_TEST_HOOKS -I"$REPO/native/mysql" -c "$REPO/native/mysql/qfli_mysql_host.cpp" -o host.o
clang++ -std=c++17 -Wall -Wextra -Werror -c "$REPO/native/mysql/qfli_mysql_launcher.cpp" -o launcher.o
clang++ -std=c++17 -Wall -Wextra -Werror -c "$REPO/native/tests/qfli_mysql_child_stub.cpp" -o stub.o
clang++ -std=c++17 -Wall -Wextra -Werror -I"$REPO/native/mysql" -c "$REPO/native/tests/qfli_mysql_host_test.cpp" -o hosttest.o
clang++ -std=c++17 -fPIC -shared stub.o -o libqfli_mysql_server.so
clang++ -std=c++17 -pie -Wl,-rpath,'$ORIGIN' launcher.o -o qfli_mysql_launcher
ar rcs libqfli_mysql_host_core.a host.o
clang++ -std=c++17 hosttest.o libqfli_mysql_host_core.a -ldl -o qfli_mysql_host_test
printf 'launcher=[%s]\n' "$PWD/qfli_mysql_launcher"
LOG="$WORK/host-tests.log"
./qfli_mysql_host_test "$PWD/qfli_mysql_launcher" 2>&1 | tee "$LOG"
exit "${PIPESTATUS[0]}"
