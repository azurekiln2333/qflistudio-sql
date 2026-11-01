set -euo pipefail
cd /root/qfli-mysql-port/ohos-build/sql
ERP=/mnt/d/MyNewProjects/qfli_sql/native/mysql
LINK=$(cat CMakeFiles/qfli_mysql_server.dir/link.txt)
# Relink the already-built objects with a private version script + symbolic
# binding, into a scratch file, to measure the exported-symbol and dependency
# effect WITHOUT changing the production target.
RELINK=$(echo "$LINK" | sed 's#-o [^ ]*libqfli_mysql_server.so#-o /tmp/libqfli_mysql_server_private.so#')
RELINK="$RELINK -Wl,--version-script=$ERP/qfli_mysql_server.map -Wl,-Bsymbolic-functions"
eval "$RELINK"

echo "=== private server exported defined symbols ==="
llvm-nm-18 -D --defined-only /tmp/libqfli_mysql_server_private.so | wc -l
echo "=== private server NEEDED ==="
llvm-readelf-18 -d /tmp/libqfli_mysql_server_private.so | grep -iE "NEEDED|SONAME"
echo "=== private server init_array size ==="
llvm-readelf-18 -S /tmp/libqfli_mysql_server_private.so | grep -i init_array
echo "=== entries present ==="
llvm-nm-18 -D --defined-only /tmp/libqfli_mysql_server_private.so | grep -E "qfli_mysql_child_main|QfliMysqlMain|qfli_mysql_record_exit"
