#!/usr/bin/env bash
set -euo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_ROOT/../.." && pwd)"
PORT_ROOT="${QFLI_MYSQL_PORT_ROOT:-$REPO_ROOT/build/mysql-port}"
ARCHIVE="${QFLI_MYSQL_ARCHIVE:-$PORT_ROOT/mysql-8.4.6.tar.gz}"
MYSQL_SHA256=a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7
SOURCE="$PORT_ROOT/mysql-8.4.6"

printf '%s  %s\n' "$MYSQL_SHA256" "$ARCHIVE" | sha256sum --check --status
mkdir -p "$PORT_ROOT"
if [[ ! -d "$SOURCE" ]]; then
  tar --no-same-owner -xzf "$ARCHIVE" -C "$PORT_ROOT"
fi
cd "$SOURCE"
for patch in "$SCRIPT_ROOT"/patches/*.patch; do
  if git apply --check "$patch" 2>/dev/null; then
    git apply "$patch"
  elif ! git apply --reverse --check "$patch"; then
    printf 'MySQL source does not match the pinned patch: %s\n' "$patch" >&2
    exit 1
  fi
done
