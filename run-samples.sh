#!/usr/bin/env bash
# Builds, then runs the example programs on the files in examples/ and checks their results.
#   ./run-samples.sh [fpc]        Output: build/fpc-<platform>/samples
# RunHttpFile talks to a small local server (python3) through libcurl.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/scripts/env.sh"
cd "$ROOT"

bash "$ROOT/build.sh"

OUT="$ROOT/build/fpc-$PLATFORM/samples"
PORT=8099
mkdir -p "$OUT"
step() { printf '\n-- %s\n' "$*"; }
fail() { printf 'FAILED: %s\n' "$*" >&2; exit 1; }
echo "==== samples: fpc $PLATFORM"

step "DumpHttpFile, features.http with the demo host"
"$BIN/DumpHttpFile" examples/features.http --demo | tee "$OUT/dump.txt"
grep -q 'Bearer at-456' "$OUT/dump.txt" || fail "the response references were not resolved"

step "ConvertHttpFile, curl and curl-bat and postman"
for format in curl curl-bat postman; do
  "$BIN/ConvertHttpFile" examples/features.http "$format" "$OUT/generated"
done
for file in features.sh features.bat features.postman_collection.json features.postman_environment.json; do
  test -s "$OUT/generated/$file" || fail "$file was not generated"
done

step "LintHttpFile"
"$BIN/LintHttpFile" examples/local.http
"$BIN/LintHttpFile" examples/features.http | tee "$OUT/lint.txt" || true
grep -q 'lint-unresolved-placeholder' "$OUT/lint.txt" || fail "the linter did not report the placeholders"

step "FormatHttpFile, formatting twice must not change the text"
"$BIN/FormatHttpFile" examples/features.http > "$OUT/formatted1.http"
"$BIN/FormatHttpFile" "$OUT/formatted1.http" > "$OUT/formatted2.http"
diff "$OUT/formatted1.http" "$OUT/formatted2.http" || fail "formatting is not stable"

step "RunHttpFile against a local server"
if ! command -v python3 >/dev/null 2>&1; then
  echo "skipped: python3 was not found"
else
  python3 build/test_server.py "$PORT" 2> "$OUT/server.log" &
  SERVER_PID=$!
  trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
  for _ in $(seq 1 50); do
    (echo > "/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break
    sleep 0.1
  done
  "$BIN/RunHttpFile" examples/local.http | tee "$OUT/run.txt"
  grep -q 'login -> HTTP/1.1 200' "$OUT/run.txt" || fail "login did not return 200"
  grep -q 'getUser -> HTTP/1.1 200' "$OUT/run.txt" || fail "getUser did not return 200"
  grep -q 'Bearer tok-123' "$OUT/run.txt" || fail "the login header was not chained into getUser"
  grep -q '"user":7' "$OUT/run.txt" || fail "the login body id was not chained into the getUser URL"
fi

printf '\nALL SAMPLES PASSED\n'
