#!/usr/bin/env bash
# Gate 3 source audit: do the flagged process-wide-call functions appear in the
# static-initializer (constructor) paths, and via which TUs? Focus on the
# reviewer's finite set, not all 870.
SRC=/root/qfli-mysql-port/mysql-8.4.6
echo "=== definitions of the flagged functions ==="
grep -rn --include=*.cc --include=*.h -E "getauxval|Rpl_filter::Rpl_filter|Udf_load_service|aggregated_stats_buffer|Persisted_variables_cache::Persisted_variables_cache" "$SRC/sql" 2>/dev/null | head -20

echo "=== Rpl_filter ctor body ==="
grep -rn "Rpl_filter::Rpl_filter" "$SRC/sql" 2>/dev/null | head
sed -n '/Rpl_filter::Rpl_filter/,/^}/p' "$SRC/sql/rpl_filter.cc" 2>/dev/null | head -30

echo "=== Persisted_variables_cache ctor ==="
grep -rn "Persisted_variables_cache::Persisted_variables_cache" "$SRC/sql" 2>/dev/null | head
sed -n '/Persisted_variables_cache::Persisted_variables_cache/,/^}/p' "$SRC/sql/persisted_variable.cc" 2>/dev/null | head -30

echo "=== aggregated_stats_buffer definition/ctor ==="
grep -rn "aggregated_stats_buffer" "$SRC/sql" 2>/dev/null | head

echo "=== any constructor calling pthread_create directly? ==="
grep -rn --include=*.cc -E "_GLOBAL__sub_I|MY_ATTRIBUTE\(\(constructor" "$SRC/sql" 2>/dev/null | head
