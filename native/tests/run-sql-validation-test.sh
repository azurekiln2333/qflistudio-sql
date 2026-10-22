#!/usr/bin/env bash
set -euo pipefail
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_DIR=${1:-$(mktemp -d -t qfli-sql-validation-XXXXXXXX)}
cmake -S "$REPO/native/tests/sql_validation" -B "$BUILD_DIR"
cmake --build "$BUILD_DIR" --parallel
ctest --test-dir "$BUILD_DIR" --output-on-failure
echo "PASS: production core real-engine tests; build directory: $BUILD_DIR"
