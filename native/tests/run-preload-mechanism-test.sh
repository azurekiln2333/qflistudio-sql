set -euo pipefail
REPO=/mnt/d/MyNewProjects/qfli_sql
WORK=$(mktemp -d /tmp/qfli-preload-mech.XXXXXX)
cd "$WORK"
# Closure with a constructor that calls pthread_create/atfork.
clang++ -std=c++17 -Wall -Wextra -Werror -fPIC -shared \
  "$REPO/native/tests/qfli_mysql_preload_closure_stub.cpp" -lpthread -o closure.so
# Test binary exports the wrappers so the RTLD_LOCAL closure resolves to them.
clang++ -std=c++17 -Wall -Wextra -Werror -rdynamic \
  "$REPO/native/tests/qfli_mysql_preload_mechanism_test.cpp" -ldl -lpthread \
  -o mechanism_test
./mechanism_test "$WORK/closure.so"
