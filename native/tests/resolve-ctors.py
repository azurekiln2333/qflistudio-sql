#!/usr/bin/env python3
# Resolve server .init_array constructors through RELA, not the on-disk zeros.
#
# The image's .init_array is zero on disk and filled by R_AARCH64_RELATIVE
# relocations at load. For each relocation whose r_offset lies in the
# .init_array range, the addend is the constructor address; map it to the owning
# symbol. This names the constructors the loader will actually call.
import bisect
import re
import subprocess
import sys

lib = sys.argv[1] if len(sys.argv) > 1 else \
    "/root/qfli-mysql-port/package/libs/arm64-v8a/libqfli_mysql_server.so"

# Section headers: find .init_array address/size and .rela.dyn.
sec = subprocess.run(["llvm-readelf-18", "-S", lib], capture_output=True,
                     text=True, check=True).stdout
init_addr = init_size = None
for line in sec.splitlines():
    if ".init_array" in line:
        # [18] .init_array INIT_ARRAY 0000000003e58770 3e56770 001b30 ...
        parts = line.split()
        idx = parts.index("INIT_ARRAY")
        init_addr = int(parts[idx + 1], 16)
        init_size = int(parts[idx + 3], 16)
print(f".init_array addr=0x{init_addr:x} size=0x{init_size:x}")

# Relocations.
rel = subprocess.run(["llvm-readelf-18", "-r", lib], capture_output=True,
                     text=True, check=True).stdout
# Lines look like: 0000000003e58770 0000000000001234 R_AARCH64_RELATIVE 1234
ctor_addends = []
pattern = re.compile(r"^([0-9a-f]{16})\s+([0-9a-f]{16})\s+R_AARCH64_RELATIVE\s+([0-9a-f]+)")
for line in rel.splitlines():
    m = pattern.match(line.strip())
    if not m:
        continue
    offset = int(m.group(1), 16)
    addend = int(m.group(3), 16)
    if init_addr <= offset < init_addr + init_size:
        ctor_addends.append(addend)
print("constructors in .init_array (RELA-resolved):", len(ctor_addends))

# Symbol table.
nm = subprocess.run(["llvm-nm-18", lib], capture_output=True, text=True,
                    check=True).stdout
syms = []
for line in nm.splitlines():
    parts = line.split()
    if len(parts) >= 3:
        try:
            syms.append((int(parts[0], 16), parts[2]))
        except ValueError:
            continue
syms.sort()
addrs = [a for a, _ in syms]

resolved = {}
unresolved = []
for a in ctor_addends:
    i = bisect.bisect_right(addrs, a) - 1
    if i >= 0 and addrs[i] == a:
        name = syms[i][1]
    else:
        # nearest lower symbol defines the function containing the address
        name = syms[i][1] if i >= 0 else "?"
    resolved[name] = resolved.get(name, 0) + 1

print("distinct constructor owners (top 50):")
for name, count in sorted(resolved.items(), key=lambda kv: -kv[1])[:50]:
    print(f"  {count:4d}  {name}")
