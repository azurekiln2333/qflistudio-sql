#!/usr/bin/env bash
set -euo pipefail
ROOT="${1:?OHOS package root}"
for path in \
  libs/arm64-v8a/libqfli_mysql.so \
  libs/arm64-v8a/libqfli_mysql_server.so \
  libs/arm64-v8a/libqfli_mysql_launcher.so \
  libs/arm64-v8a/libqfli_mysql_server_proto.so \
  libs/arm64-v8a/libqfli_sql.so \
  rawfile/mysql/runtime.json rawfile/mysql/share/english/errmsg.sys; do
  test -f "$ROOT/$path" || { echo "Missing OHOS native file: $path" >&2; exit 1; }
done
llvm-nm-18 --dynamic --defined-only "$ROOT/libs/arm64-v8a/libqfli_sql.so" > /tmp/qfli-sql-ohos-exports.txt
grep -q ' register_qfli_sql_module$' /tmp/qfli-sql-ohos-exports.txt
grep -q ' qfli_sql_version$' /tmp/qfli-sql-ohos-exports.txt
READELF="${READELF:-llvm-readelf-18}"
for path in "$ROOT"/libs/arm64-v8a/*.so; do
  "$READELF" -h "$path" | grep -q 'Class:[[:space:]]*ELF64' || exit 1
  "$READELF" -h "$path" | grep -Eq 'Machine:[[:space:]]*AArch64' || exit 1
done
