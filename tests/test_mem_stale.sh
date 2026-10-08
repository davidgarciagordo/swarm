#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_STALE="$PLUGIN_ROOT/scripts/mem-stale.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

"$MEM_STALE" check >/dev/null 2>&1
assert_eq "2" "$?" "check with no index.md returns 2"

"$MEM_STALE" seal >/dev/null
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "0" "$?" "check after seal is fresh"

echo "// dirty edit" >> "$fixture/src/App/Foo.php"
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "1" "$?" "uncommitted edit to covered file marks stale"

( cd "$fixture" && git add -A && git commit -q -m "chore: dirty edit" )
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "1" "$?" "still stale until reseal, even after commit"

"$MEM_STALE" seal >/dev/null
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "0" "$?" "fresh again after reseal"

# stub: a near-empty repo gets a sealed pack from the script alone; a real repo does not
"$MEM_STALE" stub >/dev/null 2>&1
assert_eq "0" "$?" "stub writes the pack for a near-empty repo"
assert_file_contains "$SWARM_ROOT/context-pack.md" "^# context-pack" "stub pack has the skeleton header"
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "0" "$?" "stub leaves the pack sealed and fresh"
for i in 1 2 3 4 5 6; do echo "x" > "$fixture/src/App/F$i.php"; done
"$MEM_STALE" stub >/dev/null 2>&1
assert_eq "3" "$?" "stub refuses a repo with more than a handful of files"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
