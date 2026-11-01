LIB=/root/qfli-mysql-port/ohos-build/qfli-runtime/lib/libqfli_mysql_server_proto.so
echo "=== NEEDED ==="
llvm-readelf-18 -d "$LIB" | grep NEEDED
echo "=== defined dynamic symbols (expect entries + proto) ==="
llvm-nm-18 -D --defined-only "$LIB"
echo "=== are exit/pthread_create/pthread_atfork still EXTERNAL imports? (expect none if interposed) ==="
llvm-nm-18 -D -u "$LIB" | grep -wE "exit|pthread_create|pthread_atfork" || echo "  none - interposers bind internally"
echo "=== local interposer definitions ==="
llvm-nm-18 "$LIB" 2>/dev/null | grep -E " T (exit|pthread_create|pthread_atfork)$| t (exit|pthread_create|pthread_atfork)$"
echo "=== dynamic relocations calling exit/pthread_create via PLT (expect none) ==="
llvm-readelf-18 -r "$LIB" | grep "R_AARCH64_JUMP_SLOT" | grep -wE "exit|pthread_create|pthread_atfork" || echo "  none"
