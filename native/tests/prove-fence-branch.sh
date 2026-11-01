set -euo pipefail
SRC=/root/qfli-mysql-port/mysql-8.4.6
BUILD=/root/qfli-mysql-port/ohos-build
FLAGS=$(grep -o '\-DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=1' "$BUILD/storage/innobase/CMakeFiles/innobase.dir/flags.make" | head -1)
echo "=== innobase flags.make fence macro: $FLAGS ==="
echo "=== all TUs that reference IB_MEMORY_BARRIER_STARTUP_MSG ==="
grep -rln "IB_MEMORY_BARRIER_STARTUP_MSG" "$SRC/storage/innobase/" 2>/dev/null
echo "=== preprocess os0atomic.h with the REAL innobase include/flags and show the barrier branch ==="
# Extract the real include dirs + defines from flags.make.
INCS=$(grep '^CXX_INCLUDES' "$BUILD/storage/innobase/CMakeFiles/innobase.dir/flags.make" | sed 's/^CXX_INCLUDES = //')
DEFS=$(grep '^CXX_DEFINES' "$BUILD/storage/innobase/CMakeFiles/innobase.dir/flags.make" | sed 's/^CXX_DEFINES = //')
cat > /tmp/fence_check.cc <<'EOF'
#include "os0atomic.h"
const char *qfli_probe_msg() { return IB_MEMORY_BARRIER_STARTUP_MSG; }
void qfli_probe_barrier() { os_rmb; os_wmb; }
EOF
/usr/bin/clang++-18 --target=aarch64-linux-ohos \
  --sysroot=/root/qfli-mysql-port/ohos-sdk/sysroot \
  -resource-dir=/root/qfli-mysql-port/ohos-sdk/llvm/lib/clang/15.0.4 \
  $DEFS $INCS -E /tmp/fence_check.cc 2>/dev/null | grep -A2 "qfli_probe_barrier" | tail -5
echo "=== the macro string compiled into the emitting TU ==="
/usr/bin/clang++-18 --target=aarch64-linux-ohos \
  --sysroot=/root/qfli-mysql-port/ohos-sdk/sysroot \
  -resource-dir=/root/qfli-mysql-port/ohos-sdk/llvm/lib/clang/15.0.4 \
  $DEFS $INCS -E /tmp/fence_check.cc 2>/dev/null | grep -o 'GCC builtin __atomic_thread_fence() is used for memory barrier' | head -1
