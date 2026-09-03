#!/usr/bin/env bash
# tests/test_orchestrator_requirements.sh — la raíz integra el dominio requirements dentro de un
# run (fase 5b): auditoría de dependencias, y la ÚNICA vía legítima de aprobar una instalación
# (AskUserQuestion de la raíz, spec §3.2 regla 7).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" '## 11. Requisitos e instalación')" "root has a dedicated §11 section"
assert_eq "0" "$(has "$body" 'subagent_type: "swarm:requirements-orchestrator"')" "root launches requirements-orchestrator by type"
assert_eq "0" "$(has "$body" 'operation: audit-deps')" "root can ask for a dependency audit"
assert_eq "0" "$(has "$body" 'operation: install')" "root documents the install operation"
assert_eq "0" "$(has "$body" 'AskUserQuestion')" "root uses AskUserQuestion for the approval"
assert_eq "0" "$(has "$body" 'approved:')" "root builds the approved: line"
assert_eq "0" "$(has "$body" 'nunca autorizas una instalación')" "root never authorises an install on its own judgement"
assert_eq "0" "$(has "$body" 'multi-select')" "root asks with a multi-select, one batch (§5 pattern)"
# el saneado: el §11.3 tiene que llevar el mismo parrafo literal que §8.3/§9.3/§10.3
assert_eq "0" "$(has "$body" 'Esa exención NO cubre el `summary --line` del cierre.')" "the sanitisation exemption paragraph is present verbatim"
occurrences="$(grep -cF 'Esa exención NO cubre el `summary --line` del cierre.' "$F")"
assert_eq "4" "$occurrences" "the paragraph appears once per forwarding section (§8.3, §9.3, §10.3, §11.3)"
# la raiz ya no puede seguir diciendo que requirements solo lo invoca /swarm:doctor
# (fragmento de una sola línea: el original envolvía "tú no lo lanzas en un run" en dos líneas,
# lo que hacía que grep -F -- línea a línea nunca pudiera fallar contra ESTE fragmento concreto)
assert_eq "1" "$(has "$body" 'fase 1b — lo invoca')" "root no longer says it never launches requirements"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
