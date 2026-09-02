#!/usr/bin/env bash
# tests/test_orchestrator_discovery.sh — la raíz integra el dominio discovery (spec §3.2 regla 7,
# §15 fase 2): lanza discovery-orchestrator NOMBRADO con la cabecera + tier:, presenta el batch con
# AskUserQuestion (solo ella lo tiene), y registra cada respuesta como decisión vía
# memory-orchestrator. Además, el README ya no vende discovery como "planned".
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$(echo "$front" | grep '^tools:')" 'AskUserQuestion')" "root keeps AskUserQuestion (the ONLY agent with it)"
assert_eq "0" "$(has "$body" 'subagent_type: "swarm:discovery-orchestrator"')" "root launches discovery-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "discovery-orchestrator"')" "root names it exactly discovery-orchestrator (§2bis)"
assert_eq "0" "$(has "$body" 'operation: discover')" "root passes operation: discover"
assert_eq "0" "$(has "$body" 'tier: ')" "root passes tier: to domain orchestrators"
assert_eq "0" "$(has "$body" 'objective: ')" "root passes objective: literal"
assert_eq "0" "$(has "$body" '(Recommended)')" "root puts the recommended option first with (Recommended)"
assert_eq "0" "$(has "$body" 'multiSelect')" "root documents the multiSelect setting"
assert_eq "0" "$(has "$body" 'write decision')" "root records each answer as a decision via memory-orchestrator"
assert_eq "0" "$(has "$body" 'después de su `OK`/`DONE`')" "root launches discovery only AFTER memory-orchestrator finished build"
assert_eq "1" "$(has "$body" 'fase 2, no implementado')" "root no longer says discovery is unimplemented"
assert_eq "0" "$(has "$body" 'bugfix')" "root documents when discovery is skipped (bugfix/refactor/docs)"

# Solo la raíz tiene AskUserQuestion en todo agents/
for f in "$PLUGIN_ROOT"/agents/*.md; do
  [ "$(basename "$f")" = "orchestrator.md" ] && continue
  t="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f" | grep '^tools:')"
  assert_eq "1" "$(has "$t" 'AskUserQuestion')" "$(basename "$f") has no AskUserQuestion"
done

# README: fase 2 construida, no "planned"
assert_eq "1" "$(grep -q 'Discovery (planned)' "$PLUGIN_ROOT/README.md" && echo 0 || echo 1)" "README.md no longer lists Discovery as planned"
assert_eq "0" "$(grep -q 'Discovery (built)' "$PLUGIN_ROOT/README.md" && echo 0 || echo 1)" "README.md lists Discovery as built"
assert_eq "1" "$(grep -q 'Discovery (planeado)' "$PLUGIN_ROOT/README.es.md" && echo 0 || echo 1)" "README.es.md no longer lists Discovery as planeado"
assert_eq "0" "$(grep -q 'Discovery (construido)' "$PLUGIN_ROOT/README.es.md" && echo 0 || echo 1)" "README.es.md lists Discovery as construido"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
