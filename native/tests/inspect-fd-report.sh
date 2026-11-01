d=$(ls -dt /tmp/qfli_mysql_host_* | head -1)
echo "dir=$d"
cat "$d/blocked.log"
