#!/usr/bin/env bash
# tests/test_extending_packs_doc.sh — verifica que docs/EXTENDING-PACKS.md (+ su gemelo .es.md) dice
# la verdad sobre el mecanismo real, no solo que exista prosa plausible. Ancla cada afirmación
# concreta de la guía (el contrato de 6 ficheros, el formato de commands.md, y el ejemplo trabajado
# de allowlist) contra el estado real del repo y contra el guard de verdad.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

EN="$PLUGIN_ROOT/docs/EXTENDING-PACKS.md"
ES="$PLUGIN_ROOT/docs/EXTENDING-PACKS.es.md"

assert_eq "0" "$([ -f "$EN" ] && echo 0 || echo 1)" "docs/EXTENDING-PACKS.md exists"
assert_eq "0" "$([ -f "$ES" ] && echo 0 || echo 1)" "docs/EXTENDING-PACKS.es.md exists"

has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
en="$(cat "$EN" 2>/dev/null)"; es="$(cat "$ES" 2>/dev/null)"

# --- el contrato de 6 ficheros: la guía tiene que nombrar EXACTAMENTE los 6 reales ---
for f in SKILL.md commands.md conventions.md boundaries.md precedents.md requirements.json; do
  assert_eq "0" "$(has "$en" "$f")" "EN names $f as part of the 6-file contract"
  assert_eq "0" "$(has "$es" "$f")" "ES names $f as part of the 6-file contract"
done

# --- el conjunto cerrado de claves de commands.md: la guía tiene que listarlas todas ---
for k in lint fix typecheck test test-one scan-deps outdated licenses scan-secrets sast migrate-diff migrate-status migrate-up; do
  assert_eq "0" "$(has "$en" "$k")" "EN lists key: $k"
done

# --- mermaid diagram present in both (David's explicit ask: add diagrams) ---
assert_eq "0" "$(has "$en" '```mermaid')" "EN has a real mermaid diagram, not just prose"
assert_eq "0" "$(has "$es" '```mermaid')" "ES has a real mermaid diagram, not just prose"

# --- el fichero real de detección que la guía dice editar, existe de verdad ---
assert_eq "0" "$([ -f "$PLUGIN_ROOT/scripts/mem-scan.sh" ] && echo 0 || echo 1)" "scripts/mem-scan.sh (the file the guide says to edit) really exists"
assert_eq "0" "$(has "$en" 'scripts/mem-scan.sh')" "EN names the real detection script"

# --- el test que la guía dice replicar, existe de verdad ---
assert_eq "0" "$([ -f "$PLUGIN_ROOT/tests/test_stack_pack.sh" ] && echo 0 || echo 1)" "tests/test_stack_pack.sh (the file the guide says to mirror) really exists"

# --- EL CHEQUEO QUE IMPORTA: el ejemplo trabajado de la guía dice explícitamente qué tools YA
# están permitidas y cuáles NO — verificado contra el guard real, no contra lo que la guía afirma ---
guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": %s}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# La guía afirma: pytest YA está permitido para test-writer/implementer/quality-fixer, sin cambios.
assert_eq "allow" "$(guard "swarm:test-writer" '"pytest -q"')" "guide's claim holds: pytest already allowed for test-writer"
assert_eq "allow" "$(guard "swarm:implementer" '"pytest -q"')" "guide's claim holds: pytest already allowed for implementer"
assert_eq "allow" "$(guard "swarm:quality-fixer" '"pytest -q"')" "guide's claim holds: pytest already allowed for quality-fixer"

# La guía afirma: ruff/mypy/pip-audit NO están permitidos hoy — el ejemplo insiste en verificar
# antes de confiar, y esto es justo esa verificación. Si algún día alguien los añade sin actualizar
# la guía, este assert falla y avisa de que el ejemplo quedó desactualizado.
assert_eq "deny" "$(guard "swarm:quality-fixer" '"ruff check ."')" "guide's claim holds: ruff NOT allowed for quality-fixer today (the worked example's whole point)"
assert_eq "deny" "$(guard "swarm:quality-fixer" '"mypy ."')" "guide's claim holds: mypy NOT allowed for quality-fixer today"
assert_eq "deny" "$(guard "swarm:dependency-auditor" '"pip-audit --format=json"')" "guide's claim holds: pip-audit NOT allowed for dependency-auditor today"

# --- ambos ficheros apuntan al pack real como referencia, no a sintaxis inventada ---
assert_eq "0" "$(has "$en" 'pack-php-ddd-symfony8')" "EN points at the real shipped pack as reference"
assert_eq "0" "$(has "$es" 'pack-php-ddd-symfony8')" "ES points at the real shipped pack as reference"

# --- cross-link desde USAGE.md/.es.md ---
usage_en="$(cat "$PLUGIN_ROOT/docs/USAGE.md" 2>/dev/null)"
usage_es="$(cat "$PLUGIN_ROOT/docs/USAGE.es.md" 2>/dev/null)"
assert_eq "0" "$(has "$usage_en" 'EXTENDING-PACKS.md')" "USAGE.md links to the new authoring guide"
assert_eq "0" "$(has "$usage_es" 'EXTENDING-PACKS.es.md')" "USAGE.es.md links to the new authoring guide"
assert_eq "0" "$(has "$usage_en" '```mermaid')" "USAGE.md now has at least one diagram (previously had zero)"
assert_eq "0" "$(has "$usage_es" '```mermaid')" "USAGE.es.md now has at least one diagram (previously had zero)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
