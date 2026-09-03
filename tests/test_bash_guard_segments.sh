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

# ═════════════════════════════════════════════════════════════════════════════════════════════════
# Round 2 de la review adversarial: cinco fallos del PARSER (no de las reglas de push/gh).
#
# Todos se prueban con una carga que NO dispara el gate estructural de formas canónicas
# (`rm -rf /tmp/zzz`, que no está en el allowlist de nadie), justamente para que lo que se verifique
# aquí sea el parser en sí y no la capa de encima. Los mismos ataques en su forma original
# (`git push --force origin master`) están en tests/test_push_guard_canonical.sh.
# ═════════════════════════════════════════════════════════════════════════════════════════════════

PAYLOAD='rm -rf /tmp/zzz'

# ---------- sustitución de PROCESO `<(...)` / `>(...)`: se escanea igual que `$(...)` ----------
# Era el agujero más barato de todo el fichero: el segmento visible empieza por `ls`/`cat`, que está
# en el allowlist de casi todos los agentes del plugin, y el comando real vivía dentro del paréntesis
# sin que nadie lo mirase. `>(...)` además se ejecuta de forma asíncrona.
assert_eq "deny" "$(decision "$(json "$M" "ls <($PAYLOAD)")")" \
  "<(...) process substitution body is checked as its own segment (round 2 — was completely unscanned)"
assert_eq "deny" "$(decision "$(json "$M" "ls > >($PAYLOAD)")")" \
  ">(...) output process substitution body is checked too"
assert_eq "deny" "$(decision "$(json "$M" "cat <(ls) <($PAYLOAD)")")" \
  "a second process substitution is scanned too, not just the first"
assert_eq "allow" "$(decision "$(json "$M" 'cat <(git status)')")" \
  "a process substitution whose body is ALLOWED does not cause a false deny"

# ---------- desincronización del rastreador de comillas (tres bugs distintos, round 2) ----------
# En los tres el shell real está FUERA de comillas donde el rastreador creía estar DENTRO, así que el
# `;` siguiente no se veía como separador y todo lo de detrás quedaba pegado a un primer palabro
# permitido.
out_bs_quote="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "cat \\\" ; rm -rf /tmp/zzz"}}
EOF
)"
assert_eq "0" "$(echo "$out_bs_quote" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "backslash-escaped double quote OUTSIDE quotes does not open a string: the ; after it still splits (round 2 bug 1)"

out_ansi_c="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "cat $'a\\'b' ; rm -rf /tmp/zzz"}}
EOF
)"
assert_eq "0" "$(echo "$out_ansi_c" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "ANSI-C quoting \$'a\\'b': the escaped quote does not close the string, so the ; after it still splits (round 2 bug 2)"

out_esc_in_dq="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "cat \"a\\\"\" ; rm -rf /tmp/zzz"}}
EOF
)"
assert_eq "0" "$(echo "$out_esc_in_dq" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" \
  "escaped quote INSIDE double quotes does not close them early: the ; after the real close still splits (round 2 bug 3)"

# y el contrario: una comilla real sigue protegiendo su contenido (sin falsos positivos)
assert_eq "allow" "$(decision "$(json "$M" 'cat \"a;b\"')")" \
  "a genuinely quoted ; is still not a separator (the state machine did not become over-eager)"
assert_eq "allow" "$(decision "$(json "$M" "cat 'a;b'")")" \
  "a ; inside single quotes is still not a separator"

# ---------- tope de recursión: FALLA CERRADO ----------
# Antes, a partir de la profundidad 9 el generador hacía `return` — dejaba de mirar y el comando
# quedaba PERMITIDO. Diez `$(...)` anidados eran una llave maestra.
deep="$PAYLOAD"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do deep="ls \$($deep)"; done
assert_eq "deny" "$(decision "$(json "$M" "$deep")")" \
  "12 nested \$(...) with a disallowed command at the bottom is DENIED (the depth cap fails closed, not open)"

# ---------- REGRESIÓN de round 1: `&` de redirección no es el `&` de fondo ----------
# El fix de C5 añadió `&` al conjunto de separadores sin excluir las redirecciones, y `2>&1` pasó a
# partirse en `2>` + `1`. Eso denegaba comandos de lectura perfectamente legítimos para TODOS los
# agentes: no era un agujero, pero sí una regresión de comportamiento que no debía llegar a merge.
assert_eq "allow" "$(decision "$(json "$M" 'git status 2>&1')")" \
  "2>&1 is a redirection, not the background & separator (round 1 regression, fixed)"
assert_eq "allow" "$(decision "$(json "$M" 'git log --oneline 2>&1 | head -5')")" \
  "2>&1 combined with a pipe still allows"
assert_eq "allow" "$(decision "$(json "$M" 'git diff &> /dev/null')")" \
  "&> (bash stdout+stderr redirection) is not a separator either"
assert_eq "allow" "$(decision "$(json "$M" 'git status 1>&2')")" \
  "1>&2 allows"
assert_eq "allow" "$(decision "$(json "$M" 'git status 2>/dev/null')")" \
  "2>/dev/null (no & at all) allows"
# …y el `&` de fondo DE VERDAD sigue partiendo, incluso pegado a una redirección
assert_eq "deny" "$(decision "$(json "$M" "git status 1>&2& $PAYLOAD")")" \
  "a real background & immediately after a redirection still splits (the exclusion needs adjacency to < or >)"
assert_eq "deny" "$(decision "$(json "$M" "git status & $PAYLOAD")")" \
  "the plain background & still splits (round 1 fix preserved)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
