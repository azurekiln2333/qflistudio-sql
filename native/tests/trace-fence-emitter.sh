set -uo pipefail
cd /root/qfli-mysql-port/ohos-build
OBJ=storage/innobase/CMakeFiles/innobase.dir/srv/srv0start.cc.o
echo "srv0start.o mtime:"
ls -la "$OBJ" | awk '{print $6, $7, $8}'
echo "=== strings in srv0start.o ==="
strings "$OBJ" | grep -i 'memory barrier' | head
echo "=== innobase archive(s) ==="
find . -name 'libinnobase*.a' | head
for A in $(find . -name 'libinnobase.a' | head -1); do
  echo "archive: $A"
  strings "$A" | grep -i 'memory barrier' | sort -u
done
echo "=== production server .so ==="
strings qfli-runtime/lib/libqfli_mysql_server.so | grep -i 'memory barrier' | sort -u
echo "=== private proto DSO ==="
strings qfli-runtime/lib/libqfli_mysql_server_proto.so | grep -i 'memory barrier' | sort -u
