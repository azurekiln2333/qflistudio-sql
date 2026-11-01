LIB=/root/qfli-mysql-port/package/libs/arm64-v8a/libqfli_mysql_server.so
echo "=== readelf -x .init_array (raw, first 12 lines) ==="
llvm-readelf-18 -x .init_array "$LIB" | head -12
echo "=== section headers around init_array ==="
llvm-readelf-18 -S "$LIB" | grep -iE "init_array|rela|dynamic"
echo "=== does the image use RELA for init_array? check .rela.dyn count ==="
llvm-readelf-18 -r "$LIB" | grep -c "R_AARCH64_RELATIVE" || true
