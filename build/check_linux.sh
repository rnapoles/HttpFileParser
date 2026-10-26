#!/usr/bin/env bash
# Builds everything with Free Pascal and checks it end to end (run from anywhere).
#   1. unit tests            2. DumpHttpFile      3. ConvertHttpFile
#   4. RunHttpFile against a local server (libcurl): login -> getUser chaining
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

OUT=build/out
PORT=8099
mkdir -p "$OUT"
FPCOPTS=(-Mdelphi -Fusrc -Fusrc/jsonpath -Fusrc/libcurl "-FU$OUT" "-FE$OUT")

step() { printf '\n==== %s\n' "$*"; }
fail() { printf 'CHECK FAILED: %s\n' "$*" >&2; exit 1; }

step "fpc version"
fpc -iV

step "1/4 unit tests"
fpc "${FPCOPTS[@]}" -Futests tests/HttpFileTests.dpr
( cd "$OUT" && ./HttpFileTests )

step "2/4 DumpHttpFile (features.http with the demo host)"
fpc "${FPCOPTS[@]}" examples/DumpHttpFile.dpr
"$OUT/DumpHttpFile" examples/features.http --demo | tee "$OUT/dump.log"
grep -q 'Bearer at-456' "$OUT/dump.log" || fail "response references were not resolved"

step "3/4 ConvertHttpFile (curl, curl-bat, postman)"
fpc "${FPCOPTS[@]}" examples/ConvertHttpFile.dpr
for format in curl curl-bat postman; do
  "$OUT/ConvertHttpFile" examples/features.http "$format" "$OUT/generated"
done
ls "$OUT/generated"
test -s "$OUT/generated/features.sh" || fail "features.sh was not generated"
test -s "$OUT/generated/features.bat" || fail "features.bat was not generated"
test -s "$OUT/generated/features.postman_collection.json" || fail "Postman collection was not generated"
test -s "$OUT/generated/features.postman_environment.json" || fail "Postman environment was not generated"

step "4/4 RunHttpFile against a local server"
fpc "${FPCOPTS[@]}" examples/RunHttpFile.dpr
python3 build/test_server.py "$PORT" 2> "$OUT/server.log" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for _ in $(seq 1 50); do
  (echo > "/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
  sleep 0.1
done
"$OUT/RunHttpFile" examples/local.http | tee "$OUT/run.log"
grep -q 'login -> HTTP/1.1 200' "$OUT/run.log" || fail "login did not return 200"
grep -q 'getUser -> HTTP/1.1 200' "$OUT/run.log" || fail "getUser did not return 200"
grep -q 'Bearer tok-123' "$OUT/run.log" || fail "the login header was not chained into getUser"
grep -q '"user":7' "$OUT/run.log" || fail "the login body id was not chained into the getUser URL"

printf '\nALL CHECKS PASSED\n'
