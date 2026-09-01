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

# Finding 1 regression: the fixture lives under mktemp's default dir, which on
# macOS is /var/folders/... — a bare `*/var/*` find exclusion would wrongly
# match this ancestor segment and silently empty out the Tree section. Assert
# the Tree is non-empty and lists the fixture's own top-level dirs.
tree_section="$(echo "$out" | awk '/^## Tree$/{f=1;next} /^## Entrypoints$/{f=0} f')"
assert_eq "0" "$([ -n "$(echo "$tree_section" | tr -d '[:space:]')" ] && echo 0 || echo 1)" "Tree section is non-empty"
assert_eq "0" "$(echo "$tree_section" | grep -qF "$fixture/src" && echo 0 || echo 1)" "Tree lists fixture's own src dir"
assert_eq "0" "$(echo "$tree_section" | grep -qF "$fixture/src/App" && echo 0 || echo 1)" "Tree lists fixture's own src/App dir"

# Finding 2 regression: --root with no following value must exit non-zero
# with a clean error, not crash on an unbound $2 under set -u.
"$MEM_SCAN" --root >/dev/null 2>&1; root_exit=$?
assert_eq "0" "$([ "$root_exit" -ne 0 ] && echo 0 || echo 1)" "--root with no value exits non-zero"

generic_fixture="$(mktemp -d "${TMPDIR:-/tmp}/swarm-generic.XXXXXX")"
mkdir -p "$generic_fixture/src"
out2="$("$MEM_SCAN" --root "$generic_fixture")"
assert_eq "0" "$(echo "$out2" | grep -q '^stack: generic$' && echo 0 || echo 1)" "no composer.json falls back to generic"
assert_eq "0" "$(echo "$out2" | grep -q 'warning: stack no detectado' && echo 0 || echo 1)" "generic fallback includes warning line"

rm -rf "$fixture" "$generic_fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
