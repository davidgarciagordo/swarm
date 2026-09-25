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
assert_eq "0" "$(has "$body" 'write decision')" "root records the answers as a decision via memory-orchestrator"

# P1-a — saneado de texto ajeno antes de interpolarlo en un --text (el guard no protege dentro de comillas)
assert_eq "0" "$(has "$body" 'replace each backtick')" "root sanitizes backticks before building --text"
assert_eq "0" "$(has "$body" 'delete each `$`')" "root strips \$ before building --text"
assert_eq "0" "$(has "$body" 'replace each double quote')" "root REMOVES double quotes before building --text (never escapes them)"
assert_eq "1" "$(has "$body" 'escapes each double quote')" "root no longer escapes double quotes as \\\" (bash-guard has no backslash handling)"
assert_eq "0" "$(has "$body" 'delete each backslash')" "root strips literal backslashes before building --text"

# N2 — el saneado se aplica también a --line, y se explica por qué se borra en vez de escapar
assert_eq "0" "$(has "$body" '`--text`/`--fix`/`--line`')" "sanitization rule covers --line too"
assert_eq "0" "$(has "$body" 'has NO handling of the backslash')" "root explains the bash-guard quote-state mismatch"

# N1 — §5.1 compara texto SANEADO contra texto SANEADO (hoy el campo raw:, ver el gate de §1.0bis)
assert_eq "0" "$(has "$body" 'the **sanitization in §5.0**, the same one §5.3/§5.4 applied')" "skip-check sanitizes the CURRENT run's raw argument before comparing"

# N6 — el espejo a buzón es de los SendMessage reenviados, no de toda escritura
assert_eq "1" "$(has "$body" 'applies to every write')" "root no longer overstates the mailbox mirror scope"
assert_eq "0" "$(has "$body" 'peer-to-peer `SendMessage`s it forwards')" "root states the real mailbox-mirror scope"

# P1-b — UNA sola escritura de decisión (memory-orchestrator tiene maxTurns: 12)
assert_eq "0" "$(has "$body" 'ONE single write, never one per question')" "root batches all answers into ONE write decision"
assert_eq "0" "$(has "$body" 'maxTurns: 12')" "root explains the turn-budget reason for batching"

# P1-c — cancelación del diálogo definida (verdicto + decisión pendiente)
assert_eq "0" "$(has "$body" 'KO batch left unanswered')" "root defines the verdict when the owner cancels AskUserQuestion"
assert_eq "0" "$(has "$body" '[pending]')" "root records a cancelled batch as a PENDING decision"

# P1-d — objective: sigue en la línea de decisión (§5.4); el match de §5.1 va contra raw:
assert_eq "0" "$(has "$body" 'objective: <sanitized literal objective>')" "decision line carries the literal objective"
assert_eq "0" "$(has "$body" '**never** against the question text')" "skip-check matches a stored field, never the regenerated question text"

# P2-a — pre-flight del batch antes de llamar a AskUserQuestion
assert_eq "0" "$(has "$body" 'BLOCKED malformed batch from discovery-orchestrator')" "root blocks on a malformed batch instead of losing all questions"

# N3 — el BLOCKED de batch malformado cierra el run (curate), como la cancelación
assert_eq "0" "$(has "$body" 'Before returning that `BLOCKED`, close the run')" "malformed-batch BLOCKED closes the run with curate"

# P2-b — objective: obligatorio al lanzar discovery
assert_eq "0" "$(has "$body" '`objective:` — MANDATORY')" "objective: is mandatory, not optional"
assert_eq "1" "$(has "$body" 'you can optionally add `objective:')" "objective: is no longer documented as optional"

# P2-d — el salto del invariante de tanda (§2.2) queda reconciliado con el espejo a buzón
assert_eq "0" "$(has "$body" 'mailbox mirror')" "root reconciles the roster-snapshot gap with the mailbox mirror"

# P2-c — ejemplo separado de skip legítimo (DONE) vs dominio inexistente (BLOCKED)
assert_eq "0" "$(has "$body" '- discovery omitted: decisions.md already closed this objective')" "root shows a DONE example for a legitimate discovery skip"
assert_eq "0" "$(has "$body" '**after** the `OK`/`DONE` from `memory-orchestrator`')" "root launches discovery only AFTER memory-orchestrator finished build"
assert_eq "1" "$(has "$body" 'phase 2, not implemented')" "root no longer says discovery is unimplemented"
assert_eq "0" "$(has "$body" 'bugfix')" "root documents when discovery is skipped (bugfix/refactor/docs)"

# N7 — discovery-orchestrator sanea el texto de sus hojas antes del summary --line
dbody="$(awk '/^---$/{n++; next} n>=2{print}' "$PLUGIN_ROOT/agents/discovery-orchestrator.md")"
assert_eq "0" "$(has "$dbody" 'replace every backtick')" "discovery-orchestrator sanitizes backticks before --line"
assert_eq "0" "$(has "$dbody" 'replace every double quote')" "discovery-orchestrator removes double quotes before --line"
assert_eq "0" "$(has "$dbody" 'delete every backslash')" "discovery-orchestrator strips backslashes before --line"
assert_eq "0" "$(has "$dbody" 'the `--line` is sanitized by the rule above')" "the summary --line site points at the sanitization rule"

# N5 — falta objective: ⇒ BLOCKED objetivo vacío (lo que la raíz ya prometía)
assert_eq "0" "$(has "$dbody" 'BLOCKED empty objective')" "discovery-orchestrator defines the missing-objective verdict"

# I2 — todo camino terminal escribe run/<id>/summary.md ANTES del curate (spec §11)
assert_eq "0" "$(has "$body" 'mem-manifest.sh" summary --run')" "root writes run/<id>/summary.md before closing (spec §11)"
assert_eq "0" "$(has "$body" 'Every run writes `run/<id>/summary.md` at close.')" "root states the spec §11 summary obligation"
assert_eq "0" "$(has "$body" '- run closed: BLOCKED malformed batch')" "malformed-batch path has its own summary line"
assert_eq "0" "$(has "$body" '- run closed: KO batch left unanswered')" "cancelled-dialog path has its own summary line"
assert_eq "0" "$(has "$body" 'close with `summary`+`curate` (§4)')" "normal close and cancellation close with summary + curate"

# I4 — DONE/OK con CERO líneas `- Q` está definido (batch vacío = bug del productor, visto en el smoke)
assert_eq "0" "$(has "$body" 'BLOCKED empty batch from discovery-orchestrator')" "root defines the empty-batch verdict"
assert_eq "0" "$(has "$body" 'ZERO `- Q` lines (empty batch)')" "root treats DONE/OK with zero questions as a producer bug, not an OK run"
assert_eq "0" "$(has "$body" 'ONE confirmation')" "root knows the legitimate zero-value-questions case still yields one Q"

# I1 — el saneado es UNA regla compartida del skill y las CUATRO hojas la aplican
hasi() { echo "$1" | grep -qiF -- "$2" && echo 0 || echo 1; }
SKILL="$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md"
assert_eq "0" "$(grep -qF 'Mandatory sanitization of all third-party text' "$SKILL" && echo 0 || echo 1)" "the sanitization rule is hoisted into the shared skill (SKILL.md §4.4)"
assert_eq "0" "$(has "$body" 'skills/swarm-protocol/SKILL.md` §4.4')" "root points its local copy at the shared rule"
for leaf in research-analyst value-critic options-generator feasibility-spiker; do
  lb="$(awk '/^---$/{n++; next} n>=2{print}' "$PLUGIN_ROOT/agents/$leaf.md")"
  assert_eq "0" "$(hasi "$lb" 'mandatory sanitization')" "$leaf sanitizes untrusted text before interpolating it into a shell argument"
  assert_eq "0" "$(hasi "$lb" 'skills/swarm-protocol/SKILL.md` §4.4')" "$leaf points at the shared sanitization rule"
done

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

# P2-e — el diagrama de flujo de /swarm:run ya no termina en el OK de memory-orchestrator
for r in README.md README.es.md; do
  assert_eq "0" "$(grep -q 'participant DO as discovery-orchestrator' "$PLUGIN_ROOT/$r" && echo 0 || echo 1)" "$r: /swarm:run diagram includes discovery-orchestrator"
  assert_eq "0" "$(grep -q 'AskUserQuestion (UNA llamada\|AskUserQuestion (ONE call' "$PLUGIN_ROOT/$r" && echo 0 || echo 1)" "$r: /swarm:run diagram shows the questions batch"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
