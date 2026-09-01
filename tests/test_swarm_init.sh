#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
INIT_SCRIPT="$PLUGIN_ROOT/scripts/swarm-init.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

"$INIT_SCRIPT" >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "fresh init succeeds"
assert_eq "0" "$( [ -f "$SWARM_ROOT/memory.json" ]; echo $? )" "memory.json created"
assert_eq "0" "$( [ -f "$SWARM_ROOT/decisions.md" ]; echo $? )" "decisions.md created"
assert_file_contains "$fixture/.gitignore" "# swarm" "gitignore has swarm marker"
assert_file_contains "$fixture/.gitignore" ".swarm/run/" "gitignore ignores run/"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
files = [b for b in d['backends'] if b['name'] == 'files'][0]
sys.exit(0 if files['required'] is True else 1)
" "$SWARM_ROOT/memory.json"
assert_eq "0" "$?" "memory.json is valid JSON with files.required == true"

# second run is idempotent
"$INIT_SCRIPT" >/dev/null 2>&1
marker_count="$(grep -c '^# swarm$' "$fixture/.gitignore")"
assert_eq "1" "$marker_count" "gitignore swarm block appears exactly once after 2nd init"
decisions_header_count="$(grep -c '^# Decisiones$' "$SWARM_ROOT/decisions.md")"
assert_eq "1" "$decisions_header_count" "decisions.md not duplicated after 2nd init"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
