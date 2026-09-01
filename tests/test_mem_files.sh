#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_FILES="$PLUGIN_ROOT/scripts/mem-files.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

# health fails without .swarm
"$MEM_FILES" health >/dev/null 2>&1
assert_eq "1" "$?" "health fails when .swarm absent"

mkdir -p "$SWARM_ROOT"
"$MEM_FILES" health >/dev/null 2>&1
assert_eq "0" "$?" "health passes once .swarm exists"

# finding written once
"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 3 \
  --run adhoc --text "clase sin interfaz" --fix "extraer interfaz" >/dev/null
lines="$(wc -l < "$SWARM_ROOT/findings/architecture-auditor.md" | tr -d ' ')"
assert_eq "1" "$lines" "finding written once yields 1 line"
assert_file_contains "$SWARM_ROOT/findings/architecture-auditor.md" "\[status:open\]" "finding has open status"

# duplicate key -> dup, still 1 line
out="$("$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 3 \
  --run adhoc --text "clase sin interfaz" --fix "extraer interfaz")"
assert_eq "dup" "$out" "duplicate finding reports dup"
lines="$(wc -l < "$SWARM_ROOT/findings/architecture-auditor.md" | tr -d ' ')"
assert_eq "1" "$lines" "duplicate finding does not append"

# 20 parallel writers of distinct findings -> exactly 20 lines, no torn lines
for i in $(seq 1 20); do
  "$MEM_FILES" write finding --agent concurrency-test --tag CONC --file src/App/Foo.php --line "$i" \
    --run adhoc --text "hallazgo $i" --fix "fix $i" >/dev/null &
done
wait
concurrent_lines="$(wc -l < "$SWARM_ROOT/findings/concurrency-test.md" | tr -d ' ')"
assert_eq "20" "$concurrent_lines" "20 concurrent writers yield exactly 20 lines"
malformed="$(grep -cv '^- \[key:' "$SWARM_ROOT/findings/concurrency-test.md")"
assert_eq "0" "$malformed" "no torn/interleaved lines among concurrent writes"

# mailbox to not-yet-existing agent creates file
"$MEM_FILES" write mailbox --to late-agent --from orchestrator --run adhoc --text "hola" >/dev/null
assert_eq "0" "$( [ -f "$SWARM_ROOT/run/adhoc/mailbox/late-agent.md" ]; echo $? )" "mailbox file created for late agent"
assert_file_contains "$SWARM_ROOT/run/adhoc/mailbox/late-agent.md" "\[from:orchestrator\]" "mailbox entry has from tag"

# query returns expected match
"$MEM_FILES" write decision --text "usar sonnet para ejecucion" >/dev/null
result="$("$MEM_FILES" query "sonnet" --scope decisions)"
assert_eq "0" "$( echo "$result" | grep -q "sonnet" && echo 0 || echo 1 )" "query finds decision text"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
