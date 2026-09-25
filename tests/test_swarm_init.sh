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
assert_file_contains "$fixture/.gitignore" ".swarm/models.unavailable" "gitignore ignores per-host models.unavailable"
assert_file_contains "$fixture/.gitignore" ".swarm/judgements.jsonl" "gitignore ignores the panel's judgements.jsonl"

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
assert_eq "1" "$(grep -cxF '.swarm/run/' "$fixture/.gitignore")" "no gitignore entry duplicated after 2nd init"
# an older init (block without judgements.jsonl) is upgraded in place, entry by entry
grep -vxF '.swarm/judgements.jsonl' "$fixture/.gitignore" > "$fixture/.gitignore.old" && mv "$fixture/.gitignore.old" "$fixture/.gitignore"
"$INIT_SCRIPT" >/dev/null 2>&1
assert_eq "1" "$(grep -cxF '.swarm/judgements.jsonl' "$fixture/.gitignore")" "re-init adds a missing entry to an existing swarm block"
assert_eq "1" "$(grep -c '^# swarm$' "$fixture/.gitignore")" "and still one marker"
decisions_header_count="$(grep -c '^# Decisiones$' "$SWARM_ROOT/decisions.md")"
assert_eq "1" "$decisions_header_count" "decisions.md not duplicated after 2nd init"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
