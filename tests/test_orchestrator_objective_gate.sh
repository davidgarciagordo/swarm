#!/usr/bin/env bash
# tests/test_orchestrator_objective_gate.sh — §1.0bis: gate condicional de interpretación de
# objetivo (docs/superpowers/specs/2026-09-04-objective-interpretation-gate-design.md). Corre
# ANTES de clasificar tier (§1.1) porque una interpretación mejor también mejora esa clasificación.
# Idempotencia (spec, restricción dura): el match de "ya cerró" en §5.1 sigue siendo determinista
# porque compara SIEMPRE contra el campo raw:, nunca contra objective: (que puede variar entre
# interpretaciones no deterministas del mismo texto crudo).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qE -- "$2" && echo 0 || echo 1; }

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
bis_section="$(echo "$body" | awk '/^### 1\.0bis/{p=1} /^### 1\.1 Tiers/{p=0} p')"
assert_eq "0" "$(has "$bis_section" '\[pendiente\]')" "§1.0bis's own raw-match reuse path explicitly handles a [pendiente] prior line as NOT resolved (scoped to §1.0bis, not the whole file — §5.3 also uses this term unrelatedly)"

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

# --- decision line written BEFORE tier classification, with raw: + objective: fields ---
assert_eq "0" "$(has "$bis_section" 'write decision --text')" "§1.0bis writes a decision line via the same write decision --text mechanism as discovery (scoped to §1.0bis — the same call shape also appears in discovery §5.3, unrelated to this task)"
assert_eq "0" "$(has "$body" '\\\"raw: ')" "the write decision call's --text starts with raw: (mirrors discovery's objective:-first convention, adapted for this gate)"

# --- owner cancels: BLOCKED, [pendiente], mirrors discovery §5.3's cancel handling exactly ---
assert_eq "0" "$(has "$body" 'BLOCKED interpretación de objetivo sin confirmar')" "cancelling the gate's question produces this exact BLOCKED verdict"

# --- §5.1's own idempotency-match prose now clarifies it runs on the POST-GATE objective ---
assert_eq "0" "$(has "$body" 'ya resuelto por')" "§5.1 clarifies the objective it matches may already be resolved by §1.0bis, not always the raw argument"

# --- full-file regression: no stale claim anywhere that objective always equals the raw /swarm:run argument ---
stale="$(echo "$body" | grep -n 'argumento crudo de.*swarm:run.*objetivo\|objetivo.*siempre.*argumento crudo' || true)"
assert_eq "0" "$([ -z "$stale" ] && echo 0 || echo 1)" "no stale claim anywhere states the objective always equals the raw /swarm:run argument (§1.0bis can now change it)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
