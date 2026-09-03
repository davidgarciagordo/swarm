#!/usr/bin/env bash
# tests/test_pack_wiring.sh — la RUTA del pack viaja por el prompt (spec §3.1, §8.1 "los
# orquestadores pasan la RUTA del pack en el prompt de las hojas que lo necesitan: implementation,
# data-model-auditor, vulnerability-scanner, doc-writer"), nunca por mutación de frontmatter.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
front() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# --- los orquestadores resuelven la ruta con `ls -d` y la pasan ya expandida ---
for o in implementation-orchestrator analysis-orchestrator; do
  b="$(body "$PLUGIN_ROOT/agents/$o.md")"
  assert_eq "0" "$(has "$b" 'ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-')" "$o resolves the pack path with ls -d (ruling 1)"
  assert_eq "0" "$(has "$b" 'pack:')" "$o passes a pack: header line"
  assert_eq "0" "$(has "$b" 'stack:')" "$o reads the stack: line from context-pack.md"
  assert_eq "0" "$(has "$b" 'generic')" "$o documents the generic fallback (no pack: line emitted)"
done

# --- ninguna hoja recibe jamás la variable sin expandir ---
for a in implementer test-writer quality-fixer migration-engineer doc-writer data-model-auditor vulnerability-scanner dependency-auditor; do
  b="$(body "$PLUGIN_ROOT/agents/$a.md")"
  assert_eq "0" "$(has "$b" 'pack:')" "$a documents the pack: header line"
  assert_eq "1" "$(echo "$b" | grep -q 'pack: \${CLAUDE_PLUGIN_ROOT}' && echo 0 || echo 1)" "$a never receives an unexpanded \${CLAUDE_PLUGIN_ROOT} as pack:"
done

# --- implementation-orchestrator: la lección aplicada por séptima vez ---
f_front="$(front "$PLUGIN_ROOT/agents/implementation-orchestrator.md")"
tools="$(echo "$f_front" | grep '^tools:')"
assert_eq "0" "$(has "$tools" 'migration-engineer')" "implementation-orchestrator can spawn migration-engineer (Agent tool)"
assert_eq "0" "$(has "$tools" 'doc-writer')" "implementation-orchestrator can spawn doc-writer (Agent tool)"

b="$(body "$PLUGIN_ROOT/agents/implementation-orchestrator.md")"
assert_eq "0" "$(has "$b" 'operation: migrate')" "implementation-orchestrator launches migration-engineer with operation: migrate"
assert_eq "0" "$(has "$b" 'operation: document')" "implementation-orchestrator launches doc-writer with operation: document"
assert_eq "0" "$(has "$b" 'SOLO si la fase toca el esquema')" "migration-engineer step is explicitly conditional"
assert_eq "0" "$(has "$b" 'presupuesto de turnos')" "doc-writer step documents the turn-budget cut rule"
# la limpieza sigue alcanzando TODOS los caminos terminales tras insertar dos pasos nuevos
assert_eq "0" "$(has "$b" 'Limpieza del worktree')" "cleanup section still exists"
assert_eq "0" "$(has "$b" 'KO migration-engineer')" "a migration-engineer failure is a terminal path that cleans up"
assert_eq "0" "$(has "$b" 'KO doc-writer')" "a doc-writer failure is a terminal path that cleans up"

# --- vulnerability-scanner: la nota de futuro de fase 3 ya no puede seguir en pie ---
b="$(body "$PLUGIN_ROOT/agents/vulnerability-scanner.md")"
assert_eq "1" "$(has "$b" 'ningún `skills/pack-*` existe todavía')" "vulnerability-scanner no longer claims no pack exists"
assert_eq "1" "$(has "$b" 'Nota de futuro')" "vulnerability-scanner future-note is gone (the pack landed)"
assert_eq "0" "$(has "$b" 'composer audit')" "vulnerability-scanner names the real scan command it can now run"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
