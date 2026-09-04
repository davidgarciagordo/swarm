#!/usr/bin/env bash
# tests/test_zero_friction_ux.sh — zero-friction UX recalibration
# (docs/superpowers/specs/2026-09-04-zero-friction-ux-design.md): single /swarm entry point with
# transparent auto-init, deterministic vocabulary translation, business-impact-framed gates. Prose
# tests only — this repo's agents are LLM-followed Markdown, not executable code.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ===== Task 1: agents/orchestrator.md =====
F="$PLUGIN_ROOT/agents/orchestrator.md"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"

# --- auto-init replaces the hard BLOCKED for the "not found" case ---
assert_eq "0" "$(has "$body" 'SWARM_ROOT not found')" "§2.1 distinguishes the not-found stderr text (auto-init path)"
assert_eq "0" "$(has "$body" 'SWARM_ROOT not writable')" "§2.1 distinguishes the not-writable stderr text (still-block path)"
assert_eq "0" "$(has "$body" 'BLOCKED falta /swarm:init')" "the not-writable case still has a real BLOCKED path (must not vanish entirely)"
not_found_pos="$(echo "$body" | grep -n 'SWARM_ROOT not found' | head -1 | cut -d: -f1)"
autoinit_pos="$(echo "$body" | grep -n 'swarm-init\|scripts/swarm-init' | head -1 | cut -d: -f1)"
assert_eq "0" "$([ -n "$not_found_pos" ] && [ -n "$autoinit_pos" ] && echo 0 || echo 1)" "auto-init actually invokes the real init script (scripts/swarm-init.sh), not a reimplementation"

# --- vocabulary substitution table exists with all 4 verdict words ---
for word in "DONE" "BLOCKED" "KO" "OK"; do
  assert_eq "0" "$(has "$body" "$word")" "vocabulary table covers $word"
done
assert_eq "0" "$(has "$body" 'lenguaje llano')" "orchestrator has a plain-language instruction for its own output"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
