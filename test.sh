#!/usr/bin/env bash
# Builds, then runs the unit tests.   ./test.sh [fpc]
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/env.sh"
cd "$ROOT"

bash "$ROOT/build.sh"

# the tests create and delete small fixture files in the current folder
WORK="$ROOT/build/fpc-$PLATFORM/work"
mkdir -p "$WORK"
echo "==== tests: fpc $PLATFORM"
( cd "$WORK" && "$BIN/HttpFileTests" )
echo "ALL TESTS PASSED"
