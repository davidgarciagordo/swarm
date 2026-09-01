#!/usr/bin/env bash
# Runner de smoke tests: ejecuta tests/t*-*.sh en orden.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/tests/lib.sh"

fail=0
for t in "$ROOT"/tests/t[0-9]*-*.sh; do
  [ -e "$t" ] || continue
  echo "== $(basename "$t")"
  if bash "$t" "$ROOT" >/tmp/swarm-test.out 2>&1; then
    echo "   ok"
  else
    echo "   FAIL"
    cat /tmp/swarm-test.out
    fail=1
  fi
done

[ "$fail" -eq 0 ] && echo "ALL PASS"
exit "$fail"
