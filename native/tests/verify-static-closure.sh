#!/usr/bin/env bash
# Precise static-closure + private-binding gate evidence.
set -e
LIB=${1:-/tmp/libqfli_mysql_server_static.so}

echo "=== NEEDED ==="
llvm-readelf-18 -d "$LIB" | grep -E "NEEDED" || true

echo "=== critical external C++/unwind imports (expect none) ==="
CRIT=$(llvm-nm-18 -D -u "$LIB" | grep -E "__call_once|__cxa_guard|__gxx_personality|_Unwind_|__cxa_throw|__cxa_allocate_exception|_ZSt|_ZNSt" || true)
if [ -z "$CRIT" ]; then echo "PASS: no external C++/unwind/STL imports"; else echo "FOUND:"; echo "$CRIT"; fi

echo "=== libc-provided C++ ABI imports (expected; from libc, not libc++) ==="
llvm-nm-18 -D -u "$LIB" | grep -E "__cxa_atexit|__cxa_thread_atexit" || true

echo "=== my_init_done / my_thread_global_init_done are LOCAL definitions (not exported, not imported) ==="
echo "defined (dynsym) matches:"
llvm-nm-18 -D --defined-only "$LIB" | grep -E "my_init_done|my_thread_global_init_done" || echo "  (not in dynsym - correct, local)"
echo "undefined (dynsym) matches:"
llvm-nm-18 -D -u "$LIB" | grep -E "my_init_done|my_thread_global_init_done" || echo "  (not imported - correct)"
echo "static symbol table matches (should show local b/B definitions):"
llvm-nm-18 "$LIB" 2>/dev/null | grep -E "my_init_done|my_thread_global_init_done" || echo "  (stripped static symtab)"

echo "=== entries exported ==="
llvm-nm-18 -D --defined-only "$LIB"

echo "=== exported defined count (expect 3) ==="
llvm-nm-18 -D --defined-only "$LIB" | wc -l
