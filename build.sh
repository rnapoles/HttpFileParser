#!/usr/bin/env bash
# Builds the unit tests and the example programs with Free Pascal (native platform only).
#   ./build.sh [fpc]
# Output: build/fpc-<platform>/bin   (units in build/fpc-<platform>/obj)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/env.sh"
cd "$ROOT"

mkdir -p "$BIN" "$OBJ"
echo "==== fpc $PLATFORM -> build/fpc-$PLATFORM/bin"
for program in "${PROGRAMS[@]}"; do
  echo "    $(basename "$program").dpr"
  fpc -Mdelphi -vew -Fusrc -Fusrc/jsonpath -Fusrc/libcurl -Futests \
      -FU"$OBJ" -FE"$BIN" "$program.dpr"
done
echo "Build OK"
