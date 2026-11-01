cd /root/qfli-mysql-port/package/libs/arm64-v8a
echo "=== exported defined symbol counts ==="
llvm-nm-18 -D --defined-only libqfli_mysql.so | wc -l
llvm-nm-18 -D --defined-only libqfli_mysql_server.so | wc -l
echo "=== overlapping exported defined symbols (candidate interposition) ==="
llvm-nm-18 -D --defined-only libqfli_mysql.so | awk '{print $3}' | sort > /tmp/cli.syms
llvm-nm-18 -D --defined-only libqfli_mysql_server.so | awk '{print $3}' | sort > /tmp/srv.syms
comm -12 /tmp/cli.syms /tmp/srv.syms > /tmp/common.syms
wc -l < /tmp/common.syms
echo "=== notable overlapping symbols ==="
grep -E "my_init|my_thread|my_end|OpenSSL|SSL_|EVP_|CRYPTO_|_ZN2my|sql_alloc|thr_lock" /tmp/common.syms | head -40
echo "=== INIT_ARRAY size (server) ==="
llvm-readelf-18 -S libqfli_mysql_server.so | grep -i init_array
echo "=== INIT_ARRAY size (client) ==="
llvm-readelf-18 -S libqfli_mysql.so | grep -i init_array
echo "=== server: any GLOBAL thread/once/openssl-version data exported ==="
llvm-nm-18 -D --defined-only libqfli_mysql_server.so | grep -iE " my_init_done|OpenSSL_version|once|pthread" | head -30
