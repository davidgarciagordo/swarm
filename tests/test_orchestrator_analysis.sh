#!/usr/bin/env bash
# tests/test_orchestrator_analysis.sh — la raíz integra el dominio analysis (spec §7 "Análisis",
# §15 fase 3): lanza analysis-orchestrator NOMBRADO con la cabecera + tier:, reenvía sus líneas de
# hallazgo DIRECTAMENTE (sin AskUserQuestion, a diferencia de discovery), y es EXCLUYENTE con
# discovery en v1 (decisión del owner, 2026-09-02).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:analysis-orchestrator"')" "root launches analysis-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "analysis-orchestrator"')" "root names it exactly analysis-orchestrator (§2bis)"
assert_eq "0" "$(has "$body" 'operation: audit')" "root passes operation: audit"
assert_eq "0" "$(has "$body" 'excluyente')" "root documents analysis is mutually exclusive with discovery in v1"

# analysis no tiene AskUserQuestion propio: la raíz reenvía sus líneas directamente
assert_eq "0" "$(has "$body" 'DIRECTAMENTE como tus propias líneas de salida')" "root documents it forwards analysis-orchestrator findings directly (no AskUserQuestion)"

# §4 cierre: nuevas líneas de camino terminal para analysis
assert_eq "0" "$(has "$body" 'análisis completado')" "root's close section documents the analysis terminal path"

# §1.0/§7: analysis-orchestrator ya no es "no implementado" — dominio ya no dice fase 3 pendiente para sí mismo
n_pending="$(echo "$body" | grep -cF 'analysis-orchestrator, fase 3')"
assert_eq "0" "$([ "$n_pending" -eq 0 ] && echo 0 || echo 1)" "root no longer lists analysis-orchestrator as unimplemented (fase 3 done)"

# design/implementation/delivery siguen honestamente no implementados
assert_eq "0" "$(has "$body" 'design-orchestrator')" "root still names design-orchestrator among not-yet-built domains"
assert_eq "0" "$(has "$body" 'implementation-orchestrator')" "root still names implementation-orchestrator among not-yet-built domains"

# saneado ya cubre las líneas que la raíz reenvía de analysis-orchestrator (reusa §5.0, no lo duplica)
assert_eq "0" "$(has "$body" '## 8. Análisis')" "root has a dedicated §8 Análisis section"

# CRITICAL de la review final: la propagación BLOCKED/KO de analysis SÍ pasa por el saneado de §5.0
# antes de construir el `summary --line` (§8.3) — la exención de arriba es SOLO para la salida de
# turno, nunca para el --line del cierre.
assert_eq "0" "$(has "$body" 'pasa por el saneado de §5.0')" "root's §8.3 states the BLOCKED/KO-propagation summary --line goes through §5.0 sanitization"

# README: fase 3 (análisis) construida, no "planned"/"planeado"
assert_eq "1" "$(grep -q 'Analysis (planned)' "$PLUGIN_ROOT/README.md" && echo 0 || echo 1)" "README.md no longer lists Analysis as planned"
assert_eq "0" "$(grep -q 'Analysis (built)' "$PLUGIN_ROOT/README.md" && echo 0 || echo 1)" "README.md lists Analysis as built"
assert_eq "1" "$(grep -q 'Análisis (planeado)' "$PLUGIN_ROOT/README.es.md" && echo 0 || echo 1)" "README.es.md no longer lists Análisis as planeado"
assert_eq "0" "$(grep -q 'Análisis (construido)' "$PLUGIN_ROOT/README.es.md" && echo 0 || echo 1)" "README.es.md lists Análisis as construido"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
