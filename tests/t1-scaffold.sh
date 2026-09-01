#!/usr/bin/env bash
# T1 — Scaffold: plugin.json existe con keys correctas y dirs base creados.
set -euo pipefail
ROOT="$1"
source "$ROOT/tests/lib.sh"

P="$ROOT/.claude-plugin/plugin.json"
assert_file_not_exists "$P.out.placeholder"
assert_file_contains "$P" '"name": "swarm"'
assert_file_contains "$P" '"version": "0.1.0"'
grep -q '"skills": "./skills/"' "$P" || { echo "FAIL: skills key"; exit 1; }
grep -q '"commands"' "$P" || { echo "FAIL: commands key"; exit 1; }
for d in agents commands skills scripts hooks tests; do
  [ -d "$ROOT/$d" ] || { echo "FAIL: missing dir $d"; exit 1; }
done
echo "T1 OK"
