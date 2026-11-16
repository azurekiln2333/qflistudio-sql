#!/usr/bin/env bash
set -euo pipefail

# Build the host-only Oracle generators shared by OHOS and Android ports.
# Keep target source/build trees separate from this host tree.

SOURCE="${QFLI_MYSQL_HOST_SOURCE:?set QFLI_MYSQL_HOST_SOURCE}"
BUILD="${QFLI_MYSQL_HOST_BUILD:?set QFLI_MYSQL_HOST_BUILD}"
CC="${QFLI_HOST_CLANG:-/usr/bin/clang}"
CXX="${QFLI_HOST_CLANGXX:-/usr/bin/clang++}"
JOBS="${QFLI_BUILD_JOBS:-1}"
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || { echo 'QFLI_BUILD_JOBS must be positive' >&2; exit 64; }

cmake -S "$SOURCE" -B "$BUILD" \
  -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE=-O1 \
  -DCMAKE_CXX_FLAGS_RELEASE=-O1 -DWITH_SSL=system -DWITH_ICU=system \
  -DWITH_TIRPC=system -DWITH_ROUTER=OFF -DWITH_MYSQLX=OFF \
  -DWITH_NDB=OFF -DWITH_NDBCLUSTER_STORAGE_ENGINE=OFF \
  -DWITH_GROUP_REPLICATION=OFF -DWITH_UNIT_TESTS=OFF \
  -DWITH_AUTHENTICATION_CLIENT_PLUGINS=OFF -DWITH_AUTHENTICATION_LDAP=OFF \
  -DWITH_AUTHENTICATION_KERBEROS=OFF -DWITH_AUTHENTICATION_WEBAUTHN=OFF \
  -DWITH_NUMA=OFF -DWITH_SYSTEMD=OFF -DUSE_BISON_RESULTS_FROM_MAKE_DIST=ON
cmake --build "$BUILD" --target \
  comp_err comp_client_err comp_sql uca9dump gen_lex_token \
  gen_keyword_list gen_lex_hash protoc --parallel "$JOBS"

for tool in comp_err comp_client_err comp_sql uca9dump gen_lex_token \
  gen_keyword_list gen_lex_hash protoc; do
  test -x "$BUILD/runtime_output_directory/$tool"
done
echo "$BUILD/runtime_output_directory"
