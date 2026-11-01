#!/usr/bin/env bash
# Stage the freshly built runtime + prototype DSO from the WSL build tree into
# the repo package so the HAP build picks up the probe-enabled NAPI module.
set -e
SRC=/root/qfli-mysql-port/ohos-build/qfli-runtime/lib
WIN=/mnt/d/MyNewProjects/qfli_sql/build/mysql-port/package/libs/arm64-v8a
mkdir -p "$WIN"
for lib in libqfli_mysql.so libqfli_mysql_server.so libqfli_mysql_launcher.so libqfli_mysql_server_proto.so; do
  cp "$SRC/$lib" "$WIN/$lib"
done
echo "staged:"
ls -la "$WIN/" | grep -E "libqfli_mysql"
