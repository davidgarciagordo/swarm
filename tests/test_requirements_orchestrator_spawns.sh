#!/usr/bin/env bash
# tests/test_requirements_orchestrator_spawns.sh — regresion para la clase exacta de bug real
# encontrada en fase 1: memory-orchestrator se envio sin `Agent` en su frontmatter, dejando
# memory-builder/memory-curator estructuralmente inalcanzables (SendMessage solo llega a agentes
# YA vivos). requirements-orchestrator lanza env-checker, que TAMPOCO preexiste: su frontmatter
# tiene que declarar Agent(env-checker...) o el spawn nace muerto.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
AGENT_FILE="$PLUGIN_ROOT/agents/requirements-orchestrator.md"
ENV_CHECKER_FILE="$PLUGIN_ROOT/agents/env-checker.md"

assert_eq "0" "$([ -f "$AGENT_FILE" ] && echo 0 || echo 1)" "agents/requirements-orchestrator.md exists"
assert_eq "0" "$([ -f "$ENV_CHECKER_FILE" ] && echo 0 || echo 1)" "agents/env-checker.md exists"

frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$AGENT_FILE")"
tools_line="$(echo "$frontmatter" | grep '^tools:')"

assert_eq "0" "$(echo "$tools_line" | grep -qF 'Agent(env-checker' && echo 0 || echo 1)" "tools: declares Agent(env-checker...) -- the spawn is otherwise dead on arrival (phase 1 bug class)"
assert_eq "0" "$(echo "$tools_line" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: also includes SendMessage"

# La leccion tiene que estar TAMBIEN en la prosa del cuerpo, no solo en el frontmatter -- quien
# edite este fichero a mano despues no debe poder quitar el Agent sin verlo documentado ahi mismo.
body="$(awk '/^---$/{n++; next} n>=2{print}' "$AGENT_FILE")"
assert_eq "0" "$(echo "$body" | grep -qF 'no preexiste' && echo 0 || echo 1)" "body explicitly documents that env-checker does not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'Agent' && echo 0 || echo 1)" "body prose mentions the Agent tool explicitly, not just the frontmatter"

# Regresion de allowlist: hooks/bash-guard.py matchea entradas NO prefijadas por "scripts/mem" por
# IGUALDAD EXACTA de la primera palabra del segmento (ver hooks/bash-guard.py:97-121) -- una
# entrada suelta "scripts/req-" nunca matchearia. Confirma que las entradas reales anadidas usan
# el nombre de fichero literal "scripts/req-check.sh" y que ambos agentes pueden invocarlo.
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:env-checker", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh --file /x/requirements.json"}}
EOF
)"
assert_eq "" "$out" "env-checker can run scripts/req-check.sh via CLAUDE_PLUGIN_ROOT prefix"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:requirements-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh --file /x/requirements.json"}}
EOF
)"
assert_eq "" "$out" "requirements-orchestrator can run scripts/req-check.sh via CLAUDE_PLUGIN_ROOT prefix"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:env-checker", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '\"permissionDecision\": \"deny\"' && echo 0 || echo 1)" "env-checker cannot run rm -rf / (not in its allowlist)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
