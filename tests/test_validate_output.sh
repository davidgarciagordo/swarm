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
{"agent_type": "swarm:architecture-auditor", "last_assistant_message": "OK"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "missing evidence line is blocked"

# OK + evidence files=0 -> block (spec smoke test 8)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "last_assistant_message": "OK\nevidence: files=0 cmds=1 turns=2/10"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "OK with files=0 is blocked"

# valid OK+evidence with extra spaces -> NO block (regression: lenient whitespace)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:extra-spacing-agent", "last_assistant_message": "OK\nevidence:  files=2  cmds=1  turns=3/10\nARCH · src/App/Foo.php:3 · sin interfaz → extraer interfaz"}
EOF
)"
assert_eq "" "$out" "lenient whitespace evidence line is accepted (no output)"

# valid minimal -> no output, exit 0
out_file="$fixture/valid-out.txt"
python3 "$HOOK" > "$out_file" 2>&1 <<'EOF'
{"agent_type": "swarm:vulnerability-scanner", "last_assistant_message": "DONE\nevidence: files=1 cmds=3 turns=1/10\nSEC · src/App/Foo.php:1 · secreto en claro → mover a env"}
EOF
rc=$?
assert_eq "0" "$rc" "valid minimal output exits 0"
assert_eq "0" "$(wc -l < "$out_file" | tr -d ' ')" "valid minimal output prints nothing"

# repeat failing input twice -> 2nd time accepted with systemMessage
bad_input='{"agent_type": "swarm:flaky-agent", "last_assistant_message": "OK"}'
first="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$first" | grep -q '"decision": "block"' && echo 0 || echo 1)" "first failure is blocked"
second="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$second" | grep -q 'systemMessage' && echo 0 || echo 1)" "second failure is accepted with systemMessage"
assert_eq "1" "$(echo "$second" | grep -q '"decision": "block"' && echo 0 || echo 1)" "second failure is not a block"

# non-swarm agent_type -> no output
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "some-other-agent", "last_assistant_message": "garbage output with no structure at all"}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type produces no output"

# turns==max -> systemMessage present, decision not block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=3 cmds=2 turns=15/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns==max produces systemMessage"
assert_eq "1" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "turns==max is not a block"

# turns>max (miscounted overflow) -> also treated as maxTurns, not silently passed
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=3 cmds=2 turns=16/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns>max also produces systemMessage"

# stop_hook_active=true -> hook stands down entirely, no output even on garbage
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:flaky-agent", "last_assistant_message": "garbage", "stop_hook_active": true}
EOF
)"
assert_eq "" "$out" "stop_hook_active=true short-circuits before any validation"

# non-string agent_type/last_assistant_message -> no crash, no output (fail-closed, not fail-open)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": ["swarm:weird"], "last_assistant_message": 42}
EOF
)"
rc=$?
assert_eq "0" "$rc" "malformed field types do not crash the hook"
assert_eq "" "$out" "malformed field types produce no output"

# narration smuggled behind a "- " prefix, over the length cap -> still rejected
long_line="- $(python3 -c 'print("x" * 130)')"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=1 cmds=1 turns=1/10\n$long_line"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "long narration behind a dash prefix is still rejected"

# short "- " lines (discovery-orchestrator's own - Q/- warn/- findings format) still pass
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=9 turns=9/15\n- Q1 [Valor] · pregunta · A) uno · B) dos · rec: A\n- findings: value-critic,options-generator,research-analyst,feasibility-spiker"}
EOF
)"
assert_eq "" "$out" "short dash-prefixed batch lines are accepted (no output)"

# C1 real (review final fase 2, 2026-09-02): una línea -Q de verdad, con pregunta larga y 3
# opciones al límite de 8 palabras, supera los 120 chars con normalidad (184-212 en el run real)
# -- el cap uniforme la rechazaba como narración. Debe seguir aceptándose SOLO por reconocer el
# formato estructural (cabecera + · A) ... · rec: <letra>), no por venir con "- " delante.
long_real_q="- Q1 [Alcance] Que conjunto exporta el boton, cambia arquitectura entera · A) solo pagina visible · B) todo el resultado del filtro con tope · C) todo el historico de facturas · rec: B"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=2 cmds=3 turns=6/15\n$long_real_q"}
EOF
)"
assert_eq "" "$out" "a real 184-char Q line with question+3 options+rec is accepted (C1 fix)"

# Un -Q malformado (sin rec: al final) NO se exime solo por parecerse -- sigue sujeto al cap si
# se pasa de 120, para no reabrir la narración disfrazada de pregunta.
malformed_q="- Q1 sin las opciones ni el rec al final, texto largo relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=1 turns=2/15\n$malformed_q"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "a malformed -Q line (no rec:) over 120 chars is still rejected, not exempted"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
