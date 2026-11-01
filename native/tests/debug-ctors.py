#!/usr/bin/env python3
import re, subprocess, bisect, sys
lib = "/root/qfli-mysql-port/package/libs/arm64-v8a/libqfli_mysql_server.so"
sec = subprocess.run(["llvm-readelf-18","-S",lib],capture_output=True,text=True).stdout
init_addr=init_size=None
for line in sec.splitlines():
    if ".init_array" in line:
        p=line.split(); i=p.index("INIT_ARRAY"); init_addr=int(p[i+1],16); init_size=int(p[i+3],16)
rel = subprocess.run(["llvm-readelf-18","-r",lib],capture_output=True,text=True).stdout
pat = re.compile(r"^([0-9a-f]{16})\s+([0-9a-f]{16})\s+R_AARCH64_RELATIVE\s+([0-9a-f]+)")
addends=[]
for line in rel.splitlines():
    m=pat.match(line.strip())
    if not m: continue
    off=int(m.group(1),16); add=int(m.group(3),16)
    if init_addr<=off<init_addr+init_size: addends.append(add)
print("count", len(addends))
print("first 10 addends:", [hex(a) for a in addends[:10]])
# Does llvm-nm show anything near these addends?
nm=subprocess.run(["llvm-nm-18",lib],capture_output=True,text=True).stdout
lines=[]
for l in nm.splitlines():
    p=l.split()
    if len(p)>=3:
        try: lines.append((int(p[0],16),p[2]))
        except: pass
lines.sort()
print("nm symbol count", len(lines), "min", hex(lines[0][0]), "max", hex(lines[-1][0]))
# nearest symbol for first addend
a=addends[0]
i=bisect.bisect_right([x[0] for x in lines],a)-1
print("nearest to", hex(a), ":", hex(lines[i][0]), lines[i][1])
