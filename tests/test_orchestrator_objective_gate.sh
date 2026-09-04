#!/usr/bin/env bash
# tests/test_orchestrator_objective_gate.sh — §1.0bis: gate condicional de interpretación de
# objetivo (docs/superpowers/specs/2026-09-04-objective-interpretation-gate-design.md).
#
# Estructura implementada (fix wave final — el gate está PARTIDO a propósito):
#   §1.0bis (dentro de §1, antes de §1.1)  → juicio + AskUserQuestion. No escribe NADA:
#                                            memory-orchestrator no existe hasta §2.2.
#   §2.3   (después de §2.2)               → persistencia diferida del camino de confirmación.
#   cancelación                            → el run NUNCA se abre: sin run-id no hay summary/curate
#                                            (§4) y sin memory-orchestrator no hay escritura.
# Idempotencia (spec, restricción dura): el match de "ya cerró" de §5.1 compara contra el campo
# `raw:` —determinista— y NUNCA contra `objective:` (que puede variar entre interpretaciones no
# deterministas del mismo texto crudo); además exige el marcador de cierre de discovery, para no
# auto-encontrar la línea `interpretación resuelta` que §2.3 escribe en ESE MISMO run.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qE -- "$2" && echo 0 || echo 1; }

# Section slices (the gate is deliberately split across §1.0bis / §2.3 / §4 / §5.x)
bis_section="$(echo "$body" | awk '/^### 1\.0bis/{p=1} /^### 1\.1 Tiers/{p=0} p')"
persist_section="$(echo "$body" | awk '/^### 2\.3/{p=1} /^## 3\./{p=0} p')"
close_section="$(echo "$body" | awk '/^## 4\./{p=1} /^## 5\./{p=0} p')"
s51_section="$(echo "$body" | awk '/^### 5\.1/{p=1} /^### 5\.2/{p=0} p')"
s53_section="$(echo "$body" | awk '/^### 5\.3/{p=1} /^### 5\.4/{p=0} p')"
s54_section="$(echo "$body" | awk '/^### 5\.4/{p=1} /^## 6\./{p=0} p')"

# --- §1.0bis exists, runs before §1.1 ---
assert_eq "0" "$(has "$body" '### 1.0bis')" "root has a §1.0bis section"
bis_pos="$(echo "$body" | grep -n '### 1.0bis' | head -1 | cut -d: -f1)"
tiers_pos="$(echo "$body" | grep -n '### 1.1 Tiers' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$bis_pos" ] && [ -n "$tiers_pos" ] && [ "$bis_pos" -lt "$tiers_pos" ] && echo 0 || echo 1)" "§1.0bis appears BEFORE §1.1 Tiers in the file"

# --- direct tier is exempt ---
assert_eq "0" "$(has "$body" 'tier: direct')" "§1.0bis or its surrounding prose documents the direct-tier exemption"

# --- raw: / objective: field convention is documented ---
assert_eq "0" "$(has "$body" 'raw:')" "root documents the raw: field"
assert_eq "0" "$(has "$body" 'raw:.*objective:')" "root documents raw: appearing before objective: in a decision line (same order as the spec's example)"

# --- raw-match reuse path (skip re-interpretation for a raw text already resolved before) ---
assert_eq "0" "$(has "$body" 'raw:.*es igual')" "§1.0bis describes matching a NEW run's sanitized raw argument against a stored raw: field"
assert_eq "0" "$(has "$bis_section" '\[pendiente\]')" "§1.0bis's own raw-match reuse path explicitly handles a [pendiente] prior line as NOT resolved (scoped to §1.0bis, not the whole file — §5.3 also uses this term unrelatedly)"

# --- I4: Paso 1's Read is anchored to the repo root and tolerates a missing decisions.md ---
assert_eq "0" "$(has "$bis_section" 'git rev-parse --show-toplevel')" "§1.0bis anchors to the repo root (same cd as §2.0) BEFORE reading .swarm/decisions.md — otherwise a monorepo subdirectory reads the wrong .swarm/"
assert_eq "0" "$(has "$bis_section" 'fichero no existe')" "§1.0bis Paso 1 treats a missing .swarm/decisions.md as 'no match' and continues, instead of erroring before §2.1's health-gate can diagnose it cleanly"

# --- high-confidence pass-through: zero new output, zero new AskUserQuestion ---
assert_eq "0" "$(has "$body" 'confianza alta')" "§1.0bis documents the high-confidence pass-through path"
assert_eq "0" "$(has "$body" 'sin línea de output nueva')" "§1.0bis explicitly states the high-confidence path emits no new output line (happy path stays free)"

# --- low-confidence branch: ONE AskUserQuestion, same one-batch pattern as discovery ---
assert_eq "0" "$(has "$bis_section" 'AskUserQuestion')" "§1.0bis low-confidence path uses a real AskUserQuestion (scoped to §1.0bis, not the whole file — AskUserQuestion also appears elsewhere, e.g. frontmatter tools list, discovery §5.3)"
assert_eq "0" "$(has "$front" 'AskUserQuestion')" "root's own tools: frontmatter already includes AskUserQuestion (pre-existing, verify not accidentally removed)"
assert_eq "0" "$(has "$body" 'hasta 2 alternativas')" "the question offers up to 2 alternatives, matching the spec"
assert_eq "0" "$(has "$body" 'quiero re-escribirlo yo')" "the question offers a free-rewrite option via Other"

# --- outcomes: confirm / alternative / rewrite all become objective: ---
assert_eq "0" "$(has "$body" 'ESE texto final es el')" "whichever outcome the owner picks becomes the objective: used from here on"

# --- C1: §1.0bis itself NEVER writes — memory-orchestrator does not exist until §2.2 ---
assert_eq "1" "$(has "$bis_section" 'SendMessage\(memory-orchestrator')" "§1.0bis (inside §1, before §2 opens the run) sends NOTHING to memory-orchestrator — that agent is not launched until §2.2"
assert_eq "0" "$(has "$bis_section" '§2\.3')" "§1.0bis defers its confirm-path persistence to §2.3, and says so"

# --- C1: §2.3 is where the deferred write actually happens, after §2.2 launches memory-orchestrator ---
assert_eq "0" "$(has "$body" '### 2.3')" "root has a §2.3 section for the gate's deferred persistence"
p23_pos="$(echo "$body" | grep -n '### 2.3' | head -1 | cut -d: -f1)"
p22_pos="$(echo "$body" | grep -n '### 2.2 Lanzamiento' | head -1 | cut -d: -f1)"
pack_pos="$(echo "$body" | grep -n '^## 3\.' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$p23_pos" ] && [ -n "$p22_pos" ] && [ "$p22_pos" -lt "$p23_pos" ] && echo 0 || echo 1)" "§2.3 comes AFTER §2.2 (memory-orchestrator is alive before any write)"
assert_eq "0" "$([ -n "$p23_pos" ] && [ -n "$pack_pos" ] && [ "$p23_pos" -lt "$pack_pos" ] && echo 0 || echo 1)" "§2.3 still lives inside §2 (before §3), so the write happens before any domain orchestrator is launched"
assert_eq "0" "$(has "$persist_section" 'SendMessage\(memory-orchestrator, "write decision --text')" "§2.3 carries the actual write decision call the gate deferred"
assert_eq "0" "$(has "$persist_section" '\\\"raw: ')" "§2.3's write decision --text starts with raw: (idempotency key first, same order as §5.4)"
assert_eq "0" "$(has "$persist_section" '§1.0bis')" "§2.3 names §1.0bis as the step whose resolution it is persisting"
assert_eq "0" "$(has "$persist_section" 'interpretación resuelta')" "§2.3's line carries the 'interpretación resuelta' marker that keeps §5.1 from mistaking it for a discovery close"

# --- C2: owner cancels → the run NEVER opens, so no summary/curate (§4's own rule) ---
assert_eq "0" "$(has "$body" 'BLOCKED interpretación de objetivo sin confirmar')" "cancelling the gate's question produces this exact BLOCKED verdict"
assert_eq "0" "$(has "$bis_section" 'nunca llegó a abrirse')" "the cancel path routes through §4's existing 'run never opened' branch (no run-id ⇒ no summary/curate), instead of claiming a normal terminal close"
assert_eq "1" "$(has "$close_section" 'interpretación de objetivo cancelada')" "§4's per-terminal-path line list no longer carries a bullet for the gate's cancel path — that path never opens a run, so it has no summary line to write"
assert_eq "0" "$(has "$close_section" '§1.0bis')" "§4's 'run never opened' branch names the gate's cancel path alongside §1.0's guards"

# --- C3: §5.1 matches on raw:, NEVER on objective:, and never on its own run's gate line ---
assert_eq "0" "$(has "$s51_section" 'campo \*\*`raw:`\*\*')" "§5.1's idempotency match targets the raw: field"
assert_eq "1" "$(has "$s51_section" 'campo \*\*`objective:`\*\*')" "§5.1 no longer matches on the objective: field (it may be a non-deterministic LLM interpretation — spec's hard constraint)"
assert_eq "0" "$(has "$s51_section" 'nunca.*contra .objective:')" "§5.1 states explicitly that the match is never against objective:"
assert_eq "0" "$(has "$s51_section" 'discovery <run-id>')" "§5.1 additionally requires the discovery-close marker, so an interpretation line is not mistaken for a closed discovery"
assert_eq "0" "$(has "$s51_section" 'interpretación resuelta')" "§5.1 explicitly ignores the 'interpretación resuelta' line §2.3 writes in the SAME run (otherwise the run skips discovery because of its own side effect)"
assert_eq "0" "$(has "$body" 'ya resuelto por')" "§5.1 clarifies the objective it consumes may already be resolved by §1.0bis, not always the raw argument"

# --- C3: every decision line carries raw: + objective:, whoever writes it (§2.3, §5.3, §5.4) ---
assert_eq "0" "$(has "$s54_section" 'raw: <argumento crudo saneado> · objective: <objetivo literal saneado>')" "§5.4's decision line carries raw: (the run's literal sanitized /swarm:run argument) BEFORE objective:, so §5.1 needs a single parser"
assert_eq "0" "$(has "$s54_section" 'NUNCA el objetivo ya interpretado')" "§5.4 states raw: must hold the pre-gate raw argument, never the post-gate objective (writing the interpreted text there would reopen the idempotency bug)"
assert_eq "0" "$(has "$s53_section" 'raw: <argumento crudo saneado> · objective:')" "§5.3's [pendiente] line carries raw: too, so §5.1 can find it and see it is not closed"

# --- full-file regression: no stale claim anywhere that objective always equals the raw /swarm:run argument ---
stale="$(echo "$body" | grep -n 'argumento crudo de.*swarm:run.*objetivo\|objetivo.*siempre.*argumento crudo' || true)"
assert_eq "0" "$([ -z "$stale" ] && echo 0 || echo 1)" "no stale claim anywhere states the objective always equals the raw /swarm:run argument (§1.0bis can now change it)"

# --- bilingual docs mention the gate ---
usage_en="$(cat "$PLUGIN_ROOT/docs/USAGE.md" 2>/dev/null)"
usage_es="$(cat "$PLUGIN_ROOT/docs/USAGE.es.md" 2>/dev/null)"
assert_eq "0" "$(has "$usage_en" 'objective interpretation')" "USAGE.md mentions the objective interpretation gate"
assert_eq "0" "$(has "$usage_es" 'interpretación del objetivo')" "USAGE.es.md mentions the objective interpretation gate"

readme_en="$(cat "$PLUGIN_ROOT/README.md" 2>/dev/null)"
readme_es="$(cat "$PLUGIN_ROOT/README.es.md" 2>/dev/null)"
assert_eq "0" "$(has "$readme_en" 'ambiguous')" "README.md's /swarm:run diagram/prose mentions the ambiguous-objective case"
assert_eq "0" "$(has "$readme_es" 'ambig')" "README.es.md's /swarm:run diagram/prose mentions the ambiguous-objective case (ambiguo/ambigüedad)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
