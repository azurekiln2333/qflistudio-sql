set -e
# Audit the server image's constructors and startup-relevant imports.
# Resolves each .init_array entry address through the ELF symbol table so the
# actual constructor functions are named (dl_iterate_phdr does not report which
# constructors ran, and musl LD_AUDIT is unestablished; do not rely on either).
LIB=${1:-/root/qfli-mysql-port/package/libs/arm64-v8a/libqfli_mysql_server.so}
echo "=== image: $LIB ==="

echo "=== .init_array section ==="
llvm-readelf-18 -S "$LIB" | grep -i init_array

echo "=== all dynamic defined function symbols (address -> name) ==="
llvm-nm-18 -D --defined-only "$LIB" | awk '$2=="T"||$2=="W"||$2=="t"||$2=="w"{print}' | sort > /tmp/srv_funcs.txt
wc -l < /tmp/srv_funcs.txt

echo "=== .init_array raw pointers ==="
llvm-readelf-18 -x .init_array "$LIB" | grep -E "^  0x" > /tmp/init_array_raw.txt || true
wc -l < /tmp/init_array_raw.txt

echo "=== startup-relevant imports: thread/atfork/env/signal/fd/atexit/once ==="
llvm-nm-18 -D -u "$LIB" | grep -iE "pthread_create|pthread_atfork|pthread_once|call_once|__cxa_atexit|atexit|setenv|putenv|sigaction|signal|sigprocmask|pthread_sigmask|socket|bind|listen|epoll|eventfd|setitimer|timer_create|fork|exec" | sort -u

echo "=== Oracle entry/mysqld symbols that call exit() directly (audit targets) ==="
llvm-nm-18 -D --defined-only "$LIB" | grep -iE "mysqld_exit|my_end|clean_up|_Z.*exit" | head -40
