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
assert_eq "0" "$(has "$body" 'sustituye cada backtick')" "root sanitizes backticks before building --text"
assert_eq "0" "$(has "$body" 'borra cada `$`')" "root strips \$ before building --text"
assert_eq "0" "$(has "$body" 'sustituye cada comilla doble')" "root REMOVES double quotes before building --text (never escapes them)"
assert_eq "1" "$(has "$body" 'escapa cada comilla doble')" "root no longer escapes double quotes as \\\" (bash-guard has no backslash handling)"
assert_eq "0" "$(has "$body" 'borra cada barra invertida')" "root strips literal backslashes before building --text"

# N2 — el saneado se aplica también a --line, y se explica por qué se borra en vez de escapar
assert_eq "0" "$(has "$body" '`--text`/`--fix`/`--line`')" "sanitization rule covers --line too"
assert_eq "0" "$(has "$body" 'no tiene NINGÚN tratamiento de la barra invertida')" "root explains the bash-guard quote-state mismatch"

# N1 — §5.1 compara objetivo SANEADO contra objetivo SANEADO
assert_eq "0" "$(has "$body" 'por el **saneado de §5.0**, el mismo que aplicó §5.4')" "skip-check sanitizes the CURRENT objective before comparing"

# N6 — el espejo a buzón es de los SendMessage reenviados, no de toda escritura
assert_eq "1" "$(has "$body" 'aplica a toda escritura')" "root no longer overstates the mailbox mirror scope"
assert_eq "0" "$(has "$body" 'los `SendMessage` peer-to-peer que reenvía')" "root states the real mailbox-mirror scope"

# P1-b — UNA sola escritura de decisión (memory-orchestrator tiene maxTurns: 12)
assert_eq "0" "$(has "$body" 'UNA sola escritura, nunca una por pregunta')" "root batches all answers into ONE write decision"
assert_eq "0" "$(has "$body" 'maxTurns: 12')" "root explains the turn-budget reason for batching"

# P1-c — cancelación del diálogo definida (verdicto + decisión pendiente)
assert_eq "0" "$(has "$body" 'KO batch sin responder')" "root defines the verdict when the owner cancels AskUserQuestion"
assert_eq "0" "$(has "$body" '[pendiente]')" "root records a cancelled batch as a PENDING decision"

# P1-d — objective: en la línea de decisión, y §5.1 matchea contra ese campo
assert_eq "0" "$(has "$body" 'objective: <objetivo literal saneado>')" "decision line carries the literal objective"
assert_eq "0" "$(has "$body" 'nunca** contra el texto de las preguntas')" "skip-check matches objective:, not regenerated question text"

# P2-a — pre-flight del batch antes de llamar a AskUserQuestion
assert_eq "0" "$(has "$body" 'BLOCKED batch malformado de discovery-orchestrator')" "root blocks on a malformed batch instead of losing all questions"

# N3 — el BLOCKED de batch malformado cierra el run (curate), como la cancelación
assert_eq "0" "$(has "$body" 'Antes de devolver ese `BLOCKED`, cierra el run')" "malformed-batch BLOCKED closes the run with curate"

# P2-b — objective: obligatorio al lanzar discovery
assert_eq "0" "$(has "$body" '`objective:` — OBLIGATORIA')" "objective: is mandatory, not optional"
assert_eq "1" "$(has "$body" 'puedes añadir `objective:')" "objective: is no longer documented as optional"

# P2-d — el salto del invariante de tanda (§2.2) queda reconciliado con el espejo a buzón
assert_eq "0" "$(has "$body" 'espejo a buzón')" "root reconciles the roster-snapshot gap with the mailbox mirror"

# P2-c — ejemplo separado de skip legítimo (DONE) vs dominio inexistente (BLOCKED)
assert_eq "0" "$(has "$body" '- discovery omitido: decisions.md ya cerró este objetivo')" "root shows a DONE example for a legitimate discovery skip"
assert_eq "0" "$(has "$body" 'después de su `OK`/`DONE`')" "root launches discovery only AFTER memory-orchestrator finished build"
assert_eq "1" "$(has "$body" 'fase 2, no implementado')" "root no longer says discovery is unimplemented"
assert_eq "0" "$(has "$body" 'bugfix')" "root documents when discovery is skipped (bugfix/refactor/docs)"

# N7 — discovery-orchestrator sanea el texto de sus hojas antes del summary --line
dbody="$(awk '/^---$/{n++; next} n>=2{print}' "$PLUGIN_ROOT/agents/discovery-orchestrator.md")"
assert_eq "0" "$(has "$dbody" 'sustituye cada backtick')" "discovery-orchestrator sanitizes backticks before --line"
assert_eq "0" "$(has "$dbody" 'sustituye cada comilla doble')" "discovery-orchestrator removes double quotes before --line"
assert_eq "0" "$(has "$dbody" 'borra cada barra invertida')" "discovery-orchestrator strips backslashes before --line"
assert_eq "0" "$(has "$dbody" 'el `--line` va saneado por la regla de arriba')" "the summary --line site points at the sanitization rule"

# N5 — falta objective: ⇒ BLOCKED objetivo vacío (lo que la raíz ya prometía)
assert_eq "0" "$(has "$dbody" 'BLOCKED objetivo vacío')" "discovery-orchestrator defines the missing-objective verdict"

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
