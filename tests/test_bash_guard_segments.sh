#!/usr/bin/env bash
# tests/test_bash_guard_segments.sh — C5 (fase 6, review adversarial de Task 1): `split_segments()`
# es la base de TODO el guard — cada agent_type, cada fase — así que su parsing es una superficie
# de seguridad transversal, no algo propio de push/gh. Antes de este fix, `\n` (salto de línea) y
# un `&` simple (operador de fondo, distinto de `&&`) no eran separadores de segmento, y una
# sustitución de comando ($(...) / backticks) nunca se comprobaba por su cuenta — así que un
# comando benigno delante ocultaba uno peligroso detrás, porque el string entero se analizaba como
# UN solo segmento y el comando peligroso nunca llegaba a `segment_allowed`:
#   git status
#   git push --force origin master
# (dos líneas de UN mismo tool_input.command) colaba porque `git status` (primera "palabra" tras
# trocear por espacio en blanco, incluido `\n`) es un prefijo permitido y `push --force ...` nunca
# se evaluaba como comando aparte.
#
# Este fichero prueba el parsing en sí (split_segments + recursión en sustituciones), NO las
# reglas de push/gh (esas ya las cubre tests/test_push_guard.sh con este mismo fix aplicado).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

_run_hook() { python3 "$HOOK"; }

decision() { # decision <json> -> "allow" | "deny"
  local out
  out="$(printf '%s' "$1" | _run_hook)"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

json() { # json <agent_type> <command-already-JSON-safe> -> JSON payload
  printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2"
}

A=swarm:release-manager
M=swarm:memory-orchestrator

# ---------- newline is a segment separator ----------
assert_eq "deny" "$(decision "$(json "$A" 'git status\ngit push --force origin master')")" \
  "newline-joined benign+dangerous command: the second line is checked as its own segment and denied"
assert_eq "deny" "$(decision "$(json "$A" 'git remote -v\ngit remote set-url origin https://evil')")" \
  "newline-joined git remote -v + set-url: set-url is denied even on its own line"
assert_eq "deny" "$(decision "$(json "$A" 'gh pr view 1\ngh pr merge 1 --squash')")" \
  "newline-joined gh pr view + merge: merge is denied even on its own line"
assert_eq "allow" "$(decision "$(json "$M" 'git status\ngit log --oneline -5')")" \
  "newline-joined two ALLOWED commands still allows (no false positive from the new separator)"

# ---------- single `&` (background operator) is a segment separator, distinct from `&&` ----------
assert_eq "deny" "$(decision "$(json "$A" 'git status & git push --force origin master')")" \
  "single & joining benign+dangerous command: the backgrounded second command is denied"
assert_eq "deny" "$(decision "$(json "$A" 'gh pr view 1 & gh pr merge 1')")" \
  "single & joining gh pr view + merge: merge is denied"
assert_eq "allow" "$(decision "$(json "$M" 'git status && git log --oneline -5')")" \
  "&& (chained, not backgrounded) still works exactly as before — not mistaken for a single &"
assert_eq "deny" "$(decision "$(json "$M" 'git status && rm x')")" \
  "&& with a disallowed second segment still denies (pre-existing behavior unaffected by the & fix)"

# ---------- quoted `&` is NOT treated as a separator (git commit itself is not on the
# allowlist at all — the point here is the deny reason cites the FULL unsplit segment, exactly
# like test_bash_guard.sh's pre-existing quoted-&&-inside-a-string case does for `;`/`|`/`&&`) ----------
out_quoted_amp="$(printf '%s' "$(json "$M" 'git commit -m \"a & b\"')" | _run_hook)"
assert_eq "0" "$(echo "$out_quoted_amp" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "git commit -m \"a & b\" is denied (git commit is not on memory-orchestrator's allowlist)"
assert_eq "0" "$(echo "$out_quoted_amp" | grep -qF 'git commit -m \"a & b\"' && echo 0 || echo 1)" \
  "deny reason cites the FULL unsplit segment — the literal & inside the quoted string was not treated as a separator"

# ---------- $(...) command substitution: the body is checked as its own segment ----------
assert_eq "deny" "$(decision "$(json "$A" 'git status $(git push --force origin master)')")" \
  "\$(...) substitution body containing a --force push is denied even though the outer command (git status) is benign by itself"
assert_eq "deny" "$(decision "$(json "$A" 'git status && git log $(git push --force origin master)')")" \
  "a substitution inside an already-chained segment is still recursed into and denied"
assert_eq "allow" "$(decision "$(json "$M" 'git log $(git status)')")" \
  "a substitution whose body is itself an ALLOWED command does not cause a false deny"

# ---------- backtick command substitution: same recursion as \$(...) ----------
assert_eq "deny" "$(decision "$(json "$A" 'git status `git push --force origin master`')")" \
  "backtick substitution body containing a --force push is denied"

# ---------- legitimate documented usage keeps working: cd \"\$(git rev-parse --show-toplevel)\" ----------
# (agents/orchestrator.md §2.0 — swarm:orchestrator's first Bash command of every run). Recursing
# into the substitution BODY, instead of denying any segment that merely contains \$(...), is what
# preserves this: the body (`git rev-parse --show-toplevel`) is itself on swarm:orchestrator's
# allowlist, so both the outer `cd …` segment and the inner body pass.
out_anchor="$(_run_hook <<'EOF'
{"agent_type": "swarm:orchestrator", "tool_name": "Bash", "tool_input": {"command": "cd \"$(git rev-parse --show-toplevel)\""}}
EOF
)"
assert_eq "" "$out_anchor" "cd \"\$(git rev-parse --show-toplevel)\" (orchestrator's documented anchor command) still allowed"

# ---------- a substitution whose body is itself dangerous, wrapped in the documented anchor shape ----------
out_anchor_evil="$(_run_hook <<'EOF'
{"agent_type": "swarm:release-manager", "tool_name": "Bash", "tool_input": {"command": "cd \"$(git push --force origin master)\""}}
EOF
)"
assert_eq "0" "$(echo "$out_anchor_evil" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "the same anchor SHAPE with a dangerous body (git push --force) is denied — only the body's own legitimacy decides, not the shape"

# ---------- pre-existing behavior (quoted && not split) is unaffected by any of the above ----------
out_quoted_chain="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git commit -m \"a && b\""}}
EOF
)"
assert_eq "0" "$(echo "$out_quoted_chain" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "quoted && inside a string is still not split — same deny-with-full-reason shape as test_bash_guard.sh case 4, re-verified here"
assert_eq "0" "$(echo "$out_quoted_chain" | grep -qF 'git commit -m \"a && b\"' && echo 0 || echo 1)" \
  "deny reason cites the FULL unsplit segment (git commit -m \"a && b\"), confirming the quoted && was not treated as a separator"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
