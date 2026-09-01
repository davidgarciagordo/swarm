#!/usr/bin/env bash
# T2 — Lock atómico (mkdir spin) + backend files (scripts/mem-files.sh).
set -euo pipefail
ROOT="$1"
source "$ROOT/tests/lib.sh"

TMP_DIR="/tmp/swarm-t2-$$"
trap 'rm -rf "$TMP_DIR"' EXIT
make_fixture "$TMP_DIR"

SWARM_ROOT="$TMP_DIR/.swarm"
mkdir -p "$SWARM_ROOT/findings"

SCRIPT="$ROOT/scripts/mem-files.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT no ejecutable"; exit 1; }

# 1. Health check
assert_exit "$SCRIPT health '$SWARM_ROOT'" 0

# 2. Escritura de finding con deduplicación por [key:...]
FINDING1="- [key:sec-auditor|AUTH|src/App/Foo.php:20] [sha:a1b2c3d4] [status:open] [run:run-123] AUTH · src/App/Foo.php:20 · falta validación token"
FINDING2="- [key:sec-auditor|AUTH|src/App/Foo.php:20] [sha:a1b2c3d4] [status:open] [run:run-456] AUTH · src/App/Foo.php:20 · falta validación token"
FINDING_DIFF="- [key:sec-auditor|AUTH|src/App/Foo.php:25] [sha:e5f6a7b8] [status:open] [run:run-123] AUTH · src/App/Foo.php:25 · secreto hardcodeado"

"$SCRIPT" write finding sec-auditor "$FINDING1" "$SWARM_ROOT"
"$SCRIPT" write finding sec-auditor "$FINDING2" "$SWARM_ROOT"
"$SCRIPT" write finding sec-auditor "$FINDING_DIFF" "$SWARM_ROOT"

FINDINGS_FILE="$SWARM_ROOT/findings/sec-auditor.md"
[ -f "$FINDINGS_FILE" ] || { echo "FAIL: no existe findings file"; exit 1; }
COUNT=$(wc -l < "$FINDINGS_FILE" | tr -d ' ')
assert_eq "$COUNT" "2"

# 3. Escritura de decision
DECISION="2026-09-01 · PR #42 · Autenticación JWT elegida"
"$SCRIPT" write decision "$DECISION" "$SWARM_ROOT"
assert_file_contains "$SWARM_ROOT/decisions.md" "PR #42"

# 4. Concurrencia con lock atómico (mkdir spin)
for i in $(seq 1 10); do
  "$SCRIPT" write finding load-tester "- [key:perf|N1|src/App/Foo.php:$i] [sha:12345678] [status:open] [run:r] N1 · src/App/Foo.php:$i · n+1 query" "$SWARM_ROOT" &
done
wait

LOAD_COUNT=$(wc -l < "$SWARM_ROOT/findings/load-tester.md" | tr -d ' ')
assert_eq "$LOAD_COUNT" "10"

# 5. Query
QUERY_OUT=$("$SCRIPT" query "JWT" "$SWARM_ROOT")
echo "$QUERY_OUT" | grep -q "Autenticación JWT" || { echo "FAIL: query no encontró decisión"; exit 1; }

echo "T2 OK"
