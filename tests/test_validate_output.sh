#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

# missing evidence line -> block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "output": "OK"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "missing evidence line is blocked"

# OK + evidence files=0 -> block (spec smoke test 8)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "output": "OK\nevidence: files=0 cmds=1 turns=2/10"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "OK with files=0 is blocked"

# valid OK+evidence with extra spaces -> NO block (regression: lenient whitespace)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:extra-spacing-agent", "output": "OK\nevidence:  files=2  cmds=1  turns=3/10\nARCH · src/App/Foo.php:3 · sin interfaz → extraer interfaz"}
EOF
)"
assert_eq "" "$out" "lenient whitespace evidence line is accepted (no output)"

# valid minimal -> no output, exit 0
out_file="$fixture/valid-out.txt"
python3 "$HOOK" > "$out_file" 2>&1 <<'EOF'
{"agent_type": "swarm:vulnerability-scanner", "output": "DONE\nevidence: files=1 cmds=3 turns=1/10\nSEC · src/App/Foo.php:1 · secreto en claro → mover a env"}
EOF
rc=$?
assert_eq "0" "$rc" "valid minimal output exits 0"
assert_eq "0" "$(wc -l < "$out_file" | tr -d ' ')" "valid minimal output prints nothing"

# repeat failing input twice -> 2nd time accepted with systemMessage
bad_input='{"agent_type": "swarm:flaky-agent", "output": "OK"}'
first="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$first" | grep -q '"decision": "block"' && echo 0 || echo 1)" "first failure is blocked"
second="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$second" | grep -q 'systemMessage' && echo 0 || echo 1)" "second failure is accepted with systemMessage"
assert_eq "1" "$(echo "$second" | grep -q '"decision": "block"' && echo 0 || echo 1)" "second failure is not a block"

# non-swarm agent_type -> no output
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "some-other-agent", "output": "garbage output with no structure at all"}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type produces no output"

# turns==max -> systemMessage present, decision not block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "output": "OK\nevidence: files=3 cmds=2 turns=15/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns==max produces systemMessage"
assert_eq "1" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "turns==max is not a block"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
