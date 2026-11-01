REPO=/mnt/d/MyNewProjects/qfli_sql
WORK=$(mktemp -d /tmp/qfli-host-check.XXXXXX)
cd "$WORK"
clang++ -std=c++17 -Wall -Wextra -Werror -I"$REPO/native/mysql" -c "$REPO/native/mysql/qfli_mysql_host.cpp" -o host.o
clang++ -std=c++17 -Wall -Wextra -Werror -c "$REPO/native/mysql/qfli_mysql_launcher.cpp" -o launcher.o
clang++ -std=c++17 -Wall -Wextra -Werror -c "$REPO/native/tests/qfli_mysql_child_stub.cpp" -o stub.o
clang++ -std=c++17 -fPIC -shared stub.o -o libqfli_mysql_server.so
clang++ -std=c++17 -pie -Wl,-rpath,'$ORIGIN' launcher.o -o qfli_mysql_launcher
ar rcs libqfli_mysql_host_core.a host.o
cat > trace.cpp <<'EOF'
#include "qfli_mysql_host.h"
#include <cstdio>
#include <unistd.h>
int main(int argc, char** argv) {
    std::string j = "{\"exitFile\":\"" + std::string(argv[2]) + "\",\"exitCode\":0}";
    int pid = qfli_mysql::start_child(argv[1], j, argv[3]);
    std::printf("pid=%d\n", pid);
    for (int i = 0; i < 50; i++) {
        if (qfli_mysql::poll_child(pid).state == qfli_mysql::ChildState::Exited) break;
        usleep(100*1000);
    }
    return 0;
}
EOF
clang++ -std=c++17 -I"$REPO/native/mysql" trace.cpp libqfli_mysql_host_core.a -ldl -o trace
./trace "$PWD/qfli_mysql_launcher" "$WORK/x.exit" "$WORK/trace.log"
echo "=== trace.log markers ==="
cat "$WORK/trace.log"
