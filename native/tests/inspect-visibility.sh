cd /root/qfli-mysql-port/package/libs/arm64-v8a
echo "=== dynamic flags (client) ==="
llvm-readelf-18 -d libqfli_mysql.so | grep -iE "FLAGS|BIND_NOW|SYMBOLIC"
echo "=== dynamic flags (server) ==="
llvm-readelf-18 -d libqfli_mysql_server.so | grep -iE "FLAGS|BIND_NOW|SYMBOLIC"
echo "=== server: symbol visibility distribution of exported defined ==="
llvm-nm-18 -D --defined-only libqfli_mysql_server.so | awk '{print $2}' | sort | uniq -c
echo "=== server defined symbols with hidden/local (should dominate if versioned/hidden) ==="
llvm-nm-18 libqfli_mysql_server.so | awk '{print $2}' | sort | uniq -c
