#!/usr/bin/env bash
# tests/test_commands.sh — contrato de frontmatter para TODO commands/*.md + coherencia con
# el manifest del plugin (.claude-plugin/plugin.json declara la lista de comandos).
# Glob dinámico: cubre init.md (Task 9), run.md (Task 12) y cualquier comando futuro.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

for f in "$PLUGIN_ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f")"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^description:' && echo 0 || echo 1)" "$name has description"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^allowed-tools:' && echo 0 || echo 1)" "$name has allowed-tools"
done

# Cada comando declarado en el manifest existe en disco (una referencia colgante rompe el
# plugin en carga, no en test — por eso se comprueba aquí).
for rel in $(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for c in data.get('commands', []):
    print(c.lstrip('./'))
" "$PLUGIN_ROOT/.claude-plugin/plugin.json"); do
  [ -n "$rel" ] || continue
  assert_eq "0" "$([ -f "$PLUGIN_ROOT/$rel" ] && echo 0 || echo 1)" "manifest command $rel exists"
done

# El punto de entrada raíz: /swarm:run debe invocar al agente orchestrator.
assert_eq "0" "$([ -f "$PLUGIN_ROOT/agents/orchestrator.md" ] && echo 0 || echo 1)" "agents/orchestrator.md exists"
assert_file_contains "$PLUGIN_ROOT/commands/run.md" "orchestrator" "run.md invoca al orchestrator"
assert_file_contains "$PLUGIN_ROOT/commands/run.md" '\$ARGUMENTS' "run.md pasa \$ARGUMENTS"

# /swarm:doctor (fase 5b): el chequeo incluye el stack pack activo y nunca instala nada.
assert_file_contains "$PLUGIN_ROOT/commands/doctor.md" "pack" "doctor documents that the check includes the active stack pack"
assert_file_contains "$PLUGIN_ROOT/commands/doctor.md" "nunca instala" "doctor states it never installs"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
