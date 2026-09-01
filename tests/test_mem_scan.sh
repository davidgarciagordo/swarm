#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_SCAN="$PLUGIN_ROOT/scripts/mem-scan.sh"

fixture="$(make_fixture)"
out="$("$MEM_SCAN" --root "$fixture")"
assert_eq "0" "$(echo "$out" | grep -q '^stack: php-ddd-symfony8$' && echo 0 || echo 1)" "symfony fixture detects php-ddd-symfony8"
assert_eq "0" "$(echo "$out" | grep -q '^## Markers$' && echo 0 || echo 1)" "has Markers section"

generic_fixture="$(mktemp -d "${TMPDIR:-/tmp}/swarm-generic.XXXXXX")"
mkdir -p "$generic_fixture/src"
out2="$("$MEM_SCAN" --root "$generic_fixture")"
assert_eq "0" "$(echo "$out2" | grep -q '^stack: generic$' && echo 0 || echo 1)" "no composer.json falls back to generic"
assert_eq "0" "$(echo "$out2" | grep -q 'warning: stack no detectado' && echo 0 || echo 1)" "generic fallback includes warning line"

rm -rf "$fixture" "$generic_fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
