#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SKILL_FILE="$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md"

assert_eq "0" "$( [ -f "$SKILL_FILE" ]; echo $? )" "SKILL.md exists"
assert_file_contains "$SKILL_FILE" "evidence: files=" "mentions evidence contract format"
assert_file_contains "$SKILL_FILE" "run/adhoc" "mentions adhoc run mode"
assert_file_contains "$SKILL_FILE" "mailbox" "mentions mailbox"
assert_file_contains "$SKILL_FILE" "SWARM_ROOT" "mentions SWARM_ROOT"
assert_file_contains "$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md" '^tier: ' "SKILL.md §2 documents the optional tier: header line (fase 2)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
