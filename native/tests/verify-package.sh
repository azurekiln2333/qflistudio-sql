set -e
cd /root/qfli-mysql-port/package/libs/arm64-v8a
echo "=== staged files ==="
ls -la
echo "=== launcher type ==="
file libqfli_mysql_launcher.so
echo "=== server exported entries ==="
llvm-nm-18 -D libqfli_mysql_server.so | grep -E "qfli_mysql_child_main|QfliMysqlMain|qfli_mysql_record_exit"
echo "=== launcher exported/needed ==="
llvm-nm-18 -D libqfli_mysql_launcher.so | grep -E " main$" || true
llvm-readobj-18 --needed-libs --elf-output-style=JSON libqfli_mysql_launcher.so
