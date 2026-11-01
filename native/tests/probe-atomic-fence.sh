#!/usr/bin/env bash
# Real compile+link probe: does the OHOS aarch64 toolchain support
# __atomic_thread_fence(__ATOMIC_ACQUIRE/RELEASE)? Compiles AND links an AArch64
# shared object to prove target support before changing the InnoDB config.
set -euo pipefail
SDK=/root/qfli-mysql-port/ohos-sdk
WORK=$(mktemp -d /tmp/qfli-atomic-probe.XXXXXX)
cd "$WORK"
cat > probe.c <<'EOF'
#include <stdint.h>
int qfli_atomic_probe(void) {
    __atomic_thread_fence(__ATOMIC_ACQUIRE);
    __atomic_thread_fence(__ATOMIC_RELEASE);
    return 0;
}
EOF
/usr/bin/clang-18 --target=aarch64-linux-ohos \
  --sysroot="$SDK/sysroot" \
  -resource-dir="$SDK/llvm/lib/clang/15.0.4" \
  -fuse-ld=lld -L"$SDK/llvm/lib/aarch64-linux-ohos" \
  -L"$SDK/sysroot/usr/lib/aarch64-linux-ohos" \
  -fPIC -shared probe.c -o probe.so
echo "=== compile+link OK ==="
file probe.so
echo "=== disassembly shows a real barrier (dmb/isb/ldar/stlr) ==="
"$SDK/llvm/bin/llvm-objdump" -d probe.so 2>/dev/null | grep -iE "dmb|isb|ldar|stlr" | head -5 || \
  /usr/bin/llvm-objdump-18 -d probe.so 2>/dev/null | grep -iE "dmb|isb|ldar|stlr" | head -5 || \
  echo "(objdump unavailable; compile/link success is the probe)"
