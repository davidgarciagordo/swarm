#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
COST="$PLUGIN_ROOT/scripts/swarm-cost.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/swarm-cost.XXXXXX")"
repo="/w/my repo"
proj="$tmp/-w-my-repo"
mkdir -p "$proj/s-1/subagents"
row() { printf '{"type":"assistant","timestamp":"%s","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":%s},"content":[{"type":"tool_use","name":"Bash","input":{}}]}}\n' "$@"; }
{ row 2026-01-01T10:00:00Z m1 model-a 1 10 100 5; echo 'not json'; } > "$proj/s-1.jsonl"
# the same API response on two rows counts once
{ row 2026-01-01T10:01:00Z a1 model-b 2 20 200 7; row 2026-01-01T10:01:00Z a1 model-b 2 20 200 7; row 2026-01-01T10:02:00Z a2 model-b 3 30 300 9; } > "$proj/s-1/subagents/agent-x.jsonl"
printf '{"agentType":"swarm:planner"}' > "$proj/s-1/subagents/agent-x.meta.json"

out="$("$COST" --projects "$tmp" --repo "$repo" --session s-1)"
assert_eq "0" "$?" "cost of a known session exits 0"
assert_eq "0" "$(echo "$out" | grep -q '^swarm:planner  *model-b  *2  *3  *5  *50  *500  *16$' && echo 0 || echo 1)" "subagent row sums each response once"
assert_eq "0" "$(echo "$out" | grep -q '^agents: 1 ' && echo 0 || echo 1)" "agent count excludes the main session"
assert_eq "0" "$(echo "$out" | grep -q '^total: in=6 cwrite=60 cread=600 out=21$' && echo 0 || echo 1)" "totals add main session and subagents"
assert_eq "0" "$("$COST" --projects "$tmp" --repo "$repo" | grep -q '^session: s-1$' && echo 0 || echo 1)" "the newest session with subagents is the default"
"$COST" --projects "$tmp" --repo /w/other >/dev/null 2>&1
assert_eq "1" "$?" "no transcripts exits 1"
"$COST" --session 'a/../b' >/dev/null 2>&1
assert_eq "64" "$?" "a session id with path characters is refused"

rm -rf "$tmp"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
