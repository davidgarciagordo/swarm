#!/usr/bin/env bash
# tests/test_orchestrator_design.sh — la raíz integra el dominio design (spec §15 fase 4): lo
# encadena tras discovery SOLO en tier full (spec §9.1: light = un solo dominio).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" 'subagent_type: "swarm:design-orchestrator"')" "root launches design-orchestrator by type"
assert_eq "0" "$(has "$body" 'name: "design-orchestrator"')" "root names it exactly design-orchestrator"
assert_eq "0" "$(has "$body" 'operation: design')" "root passes operation: design"
assert_eq "0" "$(has "$body" 'Only `tier: full`')" "root documents design chains ONLY in tier full"
assert_eq "1" "$(has "$body" 'aún no existe (fase 4)')" "root no longer says design-orchestrator is unimplemented"
assert_eq "0" "$(has "$body" '## 9. Design')" "root has a dedicated §9 Diseño section"

# §4 cierre: nuevas líneas de camino terminal para design
assert_eq "0" "$(has "$body" 'design completed')" "root's close section documents the design terminal path"

# tier: light must never chain to design — both termination clauses that make this airtight
assert_eq "0" "$(has "$body" 'If `tier: light`, the run ends here')" "§5.4 explicitly terminates the run in tier light instead of chaining to design"
assert_eq "0" "$(has "$body" 'Only `tier: full`')" "§9.1 gates the whole design domain on tier full"

# --- refactor/migración sustancial: discovery still skips, but design NOW chains (tier full) ---

# stale bundling must be fully gone: refactor no longer lumped with pure bugfix/docs/infra as a
# single skip-both category ANYWHERE in the file (project's own regression lesson: grep the WHOLE
# file for the enumerated-list pattern, don't assume one site is the whole bug). Pattern-based, not
# a single fixed string — a fixed string only catches ONE spelling (e.g. the slash-joined variant)
# and missed the comma-joined "(bugfix, refactor puro, docs, infra)" variant at old §8.1. Flatten to
# one line (word-wrap must not hide a same-sentence enumeration) and match the ENUMERATION shape —
# "bugfix" directly adjacent to "refactor" via a slash or a comma, either order — not mere
# co-occurrence in the same paragraph (this file legitimately CONTRASTS the two categories in prose
# now, e.g. "bugfix/docs/tests/infra puro — o refactor/migración en tier light", which must NOT
# false-positive: there's real prose between the two words, not a direct enumeration joiner).
flat_body="$(echo "$body" | tr '\n' ' ')"
bundled="$(echo "$flat_body" | grep -oE 'bugfix[,/] *refactor|refactor[,/] *bugfix' || true)"
assert_eq "" "$bundled" "no bugfix<->refactor enumeration-joined bundling remains anywhere in the file (regression sweep, catches slash- and comma-joined variants, and any future variant)"

# §5.1 documents the new keyword-driven sub-classification for refactor/migración
assert_eq "0" "$(has "$body" 'Substantial design refactor/migration')" "§5.1 introduces the refactor/migración sustancial sub-classification"
assert_eq "0" "$(has "$body" 'restructuring,')" "§5.1 lists the refactor/migración keyword table"
assert_eq "0" "$(has "$body" 'design is NOT).')" "§5.1 states discovery skips but design does not, for the refactor path"

# §9.1 documents the two independent chaining paths (product decisions vs refactor/migración)
assert_eq "0" "$(has "$body" 'three independent paths')" "§9.1 documents design now runs via three independent paths (product, refactor, infra-change), not one chained condition"
assert_eq "0" "$(has "$body" 'Substantial refactor/migration path')" "§9.1 has its own refactor/migración path to design"
assert_eq "0" "$(has "$body" "they're no longer the same chained condition")" "§9.1 clarifies discovery-skip and design-skip are independently justified now"

# §9.4 keeps 'design completed' generic to both paths (product decisions and refactor)
assert_eq "0" "$(has "$body" 'via product decisions OR via refactor/migration')" "§9.4 documents both paths close with the same DONE line"

# §4's combined-omission line no longer implies refactor is always bundled with pure bugfix/docs/infra
assert_eq "0" "$(has "$body" 'pure bugfix/docs/tests/infra')" "§4/§5.1/§9.4 use the narrowed bugfix/docs/tests/infra puro category"
assert_eq "0" "$(has "$body" 'in `tier: full` refactor/migration NO LONGER falls here')" "§4 states refactor/migración no longer falls into the combined-omission line in tier full"

# §7 output example: a refactor objective in tier full shows discovery omitted but design chained
assert_eq "0" "$(has "$body" 'substantial refactor/migration objective, no product decision to ask about')" "§7 has a worked example of the refactor path chaining to design"

# --- Opus review round: P1 stale "encadenado tras discovery"-only claims outside §5.1/§9.1/§4/§9.4 ---
assert_eq "0" "$(has "$(echo "$front" | grep '^description:')" 'chains design directly for a refactor/migration objective')" "frontmatter description documents the second (refactor) path to design"
assert_eq "0" "$(has "$body" 'or directly after a substantial refactor/migration objective')" "§1's 'Alcance actual' documents design's second path, not just 'encadenado tras discovery'"
assert_eq "0" "$(has "$body" '## 9. Design (phase 4 — only `tier: full`; chained after discovery OR after a substantial')" "§9 heading documents both paths, not just 'encadenado tras discovery'"

# --- P1: §8.1's comma-joined stale phrase (the one the old fixed-string sweep missed) ---
assert_eq "1" "$(has "$body" 'bugfix, refactor pure, docs, infra')" "§8.1 no longer uses the comma-joined bundled phrase (refactor puro collided with the new bugfix/docs/tests/infra puro vocabulary)"
assert_eq "0" "$(has "$body" 'pure bugfix, docs, tests, infra')" "§8.1 uses the narrowed, non-colliding category"

# --- P2: tier light + refactor is self-contradictory no longer — has its own closing-line clause ---
assert_eq "0" "$(has "$body" 'substantial refactor/migration in `tier: light`')" "§4/§9.4 have a dedicated clause for the tier-light + refactor case"
assert_eq "0" "$(has "$body" 'design is skipped for a DIFFERENT reason')" "§4 states discovery-skip and design-skip can be DISTINCT reasons, not always 'el mismo motivo'"

# --- P2: §9.1 vs §9.4 direct contradiction (§9.1 said design gets its own line, §9.4 said it doesn't) ---
assert_eq "1" "$(has "$body" 'Say so in a line `- design omitted: <shared reason with')" "§9.1 no longer instructs an own diseño-omitido line that contradicts §9.4's folding rule"

# --- P2: keyword list is illustrative, has a bugfix tie-break, and covers the reviewer's false negatives ---
assert_eq "0" "$(has "$body" 'illustrative list, NOT')" "§5.1 states the refactor/migración keyword list is illustrative, not exhaustive"
assert_eq "0" "$(has "$body" 'Tie-break with bugfix')" "§5.1 has a bugfix-wins tie-break rule for objectives that only mention a refactor keyword in passing"
assert_eq "0" "$(has "$body" 'reorganize, rewrite, modernize')" "§5.1's keyword list covers reorganiza/reescribe/moderniza (reviewer false negatives)"

# --- Untested interaction: objective matches BOTH analysis and refactor/migración keywords ---
assert_eq "0" "$(has "$body" 'Precedence over a substantial refactor/migration')" "§8.1 has an explicit precedence rule for objectives matching both analysis and refactor keywords"
assert_eq "0" "$(has "$body" 'analysis wins')" "§8.1 states analysis wins precedence over the refactor/migración-to-design path"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
