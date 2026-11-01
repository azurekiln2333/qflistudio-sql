#!/usr/bin/env bash
# Cold-backup the production MySQL directory via hdc file recv -b (app-bundle
# access) because the shell uid cannot read app-private files. Recursively lists
# the tree with `hdc shell ls -laR`, then re-fetches every regular file it can.
set -uo pipefail
BUNDLE=com.azurekiln.qfli.sqlab
TARGET=192.168.68.207:46551
BASE="/data/app/el2/100/base/$BUNDLE/haps/entry/files/mysql"
DEST="/mnt/d/MyNewProjects/qfli_sql/build/mysql-port/prod-cold-backup-20261009/mysql"
mkdir -p "$DEST"

echo "=== full listing (-laR) saved for manifest ==="
hdc -t "$TARGET" shell "ls -laR $BASE" > "$DEST/../prod-mysql-listing.txt" 2>&1
wc -l "$DEST/../prod-mysql-listing.txt"

echo "=== fetch top-level files ==="
for f in capability.log initialize.exit initialize.log initialized.json my.cnf mysql.log mysql.pid mysql.sock.lock; do
  hdc -t "$TARGET" file recv -b "$BUNDLE" "$BASE/$f" "$DEST/$f" >/dev/null 2>&1 \
    && echo "ok   $f" || echo "skip $f"
done

echo "=== fetch data/ files (non-recursive) ==="
mkdir -p "$DEST/data"
hdc -t "$TARGET" shell "ls $BASE/data" > /tmp/data_list.txt 2>&1
while read -r name; do
  [ -z "$name" ] && continue
  case "$name" in
    *:*) continue ;;
  esac
  hdc -t "$TARGET" file recv -b "$BUNDLE" "$BASE/data/$name" "$DEST/data/$name" >/dev/null 2>&1 \
    && echo "ok   data/$name" || echo "skip data/$name"
done < /tmp/data_list.txt
