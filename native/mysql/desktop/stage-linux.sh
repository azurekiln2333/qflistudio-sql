#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESTINATION="${1:-$SCRIPT_ROOT/../../build/mysql/linux}"
SERVER="${QFLI_MYSQL_SYSTEM_SERVER:-/usr/sbin/mysqld}"
SHARE="${QFLI_MYSQL_SYSTEM_SHARE:-/usr/share/mysql}"
PLUGIN="${QFLI_MYSQL_SYSTEM_PLUGIN:-/usr/lib/mysql/plugin}"
VERSION="$($SERVER --no-defaults --version)"
[[ "$VERSION" == *"Ver 8."* && "$VERSION" != *MariaDB* ]] || { printf 'Oracle MySQL 8.x is required.\n' >&2; exit 1; }
[[ ! -e "$DESTINATION" ]] || { printf 'Use a fresh staging directory: %s\n' "$DESTINATION" >&2; exit 1; }
pkg-config --exists mysqlclient
mkdir -p "$DESTINATION/bin" "$DESTINATION/lib" "$DESTINATION/share" "$DESTINATION/licenses"
cp "$SERVER" "$DESTINATION/bin/mysqld"
cp -aL "$SHARE/." "$DESTINATION/share/"
cp -aL "$PLUGIN" "$DESTINATION/lib/plugin"
CLIENT="$(pkg-config --variable=libdir mysqlclient)/libmysqlclient.so"
cmake -DSERVER="$SERVER" -DCLIENT="$CLIENT" -DDESTINATION="$DESTINATION" -P "$SCRIPT_ROOT/stage-linux-dependencies.cmake"
for copyright in /usr/share/doc/mysql-server-*/copyright /usr/share/doc/mysql-client-*/copyright /usr/share/doc/libmysqlclient*/copyright; do
  if [[ -f "$copyright" ]]; then
    package="$(basename "$(dirname "$copyright")")"
    cp "$copyright" "$DESTINATION/licenses/$package.txt"
  fi
done
if [[ -f /usr/share/common-licenses/GPL-2 ]]; then cp /usr/share/common-licenses/GPL-2 "$DESTINATION/LICENSE"; fi
printf '%s\n' "$VERSION" > "$DESTINATION/server-version.txt"
printf 'Staged Oracle server and its native dependencies: %s\n' "$DESTINATION"
