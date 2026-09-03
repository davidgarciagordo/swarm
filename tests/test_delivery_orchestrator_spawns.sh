#!/usr/bin/env bash
# tests/test_delivery_orchestrator_spawns.sh — regresión de la clase de bug de fase 1 (aplicada por
# séptima vez): un orquestador de dominio que lanza hojas que NO preexisten necesita Agent(<hojas>)
# en su `tools:`; con solo SendMessage el spawn nace muerto (SendMessage solo llega a agentes vivos).
#
# Y la propiedad específica de fase 6: handoff-writer corre en TODOS los caminos terminales del
# dominio (éxito, KO, BLOCKED, y "el owner no aprobó"), no solo en el feliz — el relevo vale más
# cuando algo se atascó. Se comprueba por conteo de caminos documentados, no por prosa suelta.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/delivery-orchestrator.md"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/delivery-orchestrator.md exists"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/agents/release-manager.md" ] && echo 0 || echo 1)" "agents/release-manager.md exists"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/agents/handoff-writer.md" ] && echo 0 || echo 1)" "agents/handoff-writer.md exists"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
tools_line="$(echo "$front" | grep '^tools:')"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "delivery-orchestrator is haiku (spec §7 and §7.0)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "delivery-orchestrator has maxTurns 10 (spec §7)"
assert_eq "0" "$(has "$tools_line" 'Agent(release-manager')" "tools: declares Agent(release-manager,...) — the spawn is otherwise dead on arrival"
assert_eq "0" "$(has "$tools_line" 'handoff-writer')" "tools: also declares handoff-writer"
assert_eq "0" "$(has "$tools_line" 'SendMessage')" "tools: also includes SendMessage"
assert_eq "1" "$(has "$tools_line" 'AskUserQuestion')" "a domain orchestrator cannot ask the owner (spec §3.2 rule 7)"

assert_eq "0" "$(has "$body" 'No preexiste')" "body documents that the leaves do not preexist"
assert_eq "0" "$(has "$body" 'NUNCA encadenas')" "body states it never auto-chains after implementation"
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "forwards the approval line verbatim, with its exact shape"
assert_eq "0" "$(has "$body" 'nunca construyes')" "states it never builds the approval itself"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "documents phase B"
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "documents the remote-bootstrap operation (ruling 3)"
assert_eq "0" "$(has "$body" 'approved-remote:')" "forwards the remote approval line too, and verbatim"
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere"

# handoff en TODOS los caminos terminales: la sección compartida existe y cada camino la referencia
assert_eq "0" "$(has "$body" '## Handoff — SIEMPRE, en CUALQUIER salida terminal')" "there is ONE shared handoff section"
refs="$(echo "$body" | grep -cF 'ver "## Handoff — SIEMPRE"')"
assert_eq "0" "$([ "$refs" -ge 4 ] && echo 0 || echo 1)" "at least 4 terminal paths point at the shared handoff section (got $refs)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
