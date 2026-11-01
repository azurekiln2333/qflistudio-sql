set -e
SRC=/root/qfli-mysql-port/package
DST=/mnt/d/MyNewProjects/qfli_sql/build/mysql-port/package
rm -rf "$DST"
mkdir -p "$DST"
cp -r "$SRC/libs" "$DST/libs"
cp -r "$SRC/rawfile" "$DST/rawfile"
echo "staged back:"
ls -la "$DST/libs/arm64-v8a/"
