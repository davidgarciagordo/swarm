#!/usr/bin/env bash
# tests/test_delivery_agents.sh — contrato de las hojas del dominio delivery (fase 6, spec §7
# "Entrega"). El foco no es la prosa: son las propiedades de seguridad que este dominio introduce
# por primera vez en el proyecto (push real, PR real) y que ninguna review de lectura garantiza.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

front_of() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body_of()  { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ─────────────────────────── release-manager ───────────────────────────
F="$PLUGIN_ROOT/agents/release-manager.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/release-manager.md exists"
front="$(front_of "$F")"; body="$(body_of "$F")"

assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "release-manager is sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "release-manager has maxTurns 15 (spec §7)"
assert_eq "0" "$(has "$front" 'Write')" "release-manager has Write (release notes go through Write, never shell)"
assert_eq "1" "$(has "$front" 'AskUserQuestion')" "release-manager CANNOT ask the owner (spec §3.2 rule 7)"

# el gate de aprobación: forma literal, exigida, no inferible
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "documents the exact approval line shape"
assert_eq "0" "$(has "$body" 'BLOCKED sin aprobación de push')" "refuses to publish without the approval line"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación de push malformada')" "refuses a malformed approval (not a yes/no)"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación no coincide con el estado real')" "re-verifies the approval against reality before pushing"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "documents phase B"

# backlog fix: approved-push: gains url= — phase B re-verifies the remote's URL, not just its name
assert_eq "0" "$(has "$body" 'approved-push: remote=origin branch=feature/export-csv base=master url=')" "the approval line's literal example carries the fourth field, url="
assert_eq "0" "$(has "$body" 'cuatro campos')" "the gate now names four fields, not three"
assert_eq "0" "$(has "$body" 'discrepancia: url aprobada')" "a URL mismatch surfaces as its own named discrepancy, same shape as remote/branch/base"
assert_eq "1" "$(has "$body" 'candidato de v1.1 si alguna vez importa')" "the old accepted-risk note is gone now that the gap is closed"

# C1 fix-of-a-fix (Opus review): url= must compare the PUSH url, never the fetch url — pushurl can
# diverge from the fetch url and is what git push actually uses.
assert_eq "0" "$(has "$body" 'git remote get-url --push --all origin')" "the re-verification command is explicitly --push --all, not bare get-url or --push alone"
assert_eq "0" "$(has "$body" 'pushurl')" "documents WHY --push matters: remote.<name>.pushurl can diverge from the fetch url"
assert_eq "0" "$(has "$body" 'evil.example.com')" "names the concrete pushurl-hijack scenario the reviewer verified empirically"
assert_eq "0" "$(has "$body" 'nunca uses `git remote get-url <remote>` a secas')" "phase A explicitly forbids the bare (fetch) form when sourcing the url= value"
occurrences_push_all_cmd="$(grep -cF 'git remote get-url --push --all origin' "$F")"
[ "$occurrences_push_all_cmd" -ge 2 ] && push_all_present=0 || push_all_present=1
assert_eq "0" "$push_all_present" "the literal --push --all command appears at least twice (A source, B re-verification) — found $occurrences_push_all_cmd"
# I1: the "tal cual / no reformatees" self-contradiction is gone — get-url --push returns a bare URL
# string with nothing to strip, so there is no reformatting step left to describe.
assert_eq "0" "$(has "$body" 'sin marcador `(push)`/`(fetch)`, sin')" "documents that get-url --push needs no (fetch)/(push) marker stripped (I1 fixed at the source, not by a stripping rule)"
# item 3: the PR host-detection reuses the SAME push url, not an independent fetch-url read
assert_eq "0" "$(has "$body" 'la de PUSH que ya obtuviste en la re-verificación con')" "gh pr create host-detection is explicitly sourced from the push url, consistent with the actual push destination"

# C1' fix-of-a-fix-of-a-fix (2nd Opus review of e4616b8): pushurl/url are MULTI-VALUED in git — a bare
# `--push` (without `--all`) only shows the FIRST destination, so a second pushurl added between phase
# A and phase B was invisible to the previous round's comparison. `git push` pushes to ALL of them.
assert_eq "0" "$(has "$body" 'MULTI-VALUADOS')" "documents that pushurl/url are multi-valued in git, not single-value fields"
assert_eq "0" "$(has "$body" 'BLOCKED remoto con varios destinos de push')" "phase A refuses outright when the remote already has more than one push destination"
assert_eq "0" "$(has "$body" 'real <n> destinos de push')" "phase B's discrepancy line names the destination COUNT rather than trying to encode multiple URLs into a single-value url= field"
assert_eq "0" "$(has "$body" 'no lo intentas comparar línea a línea ni te quedas con la primera')" "explicitly rules out silently narrowing to the first line instead of refusing"

# propiedades permanentes
assert_eq "0" "$(has "$body" 'BLOCKED HEAD en rama protegida')" "never publishes from a protected branch"
assert_eq "0" "$(has "$body" 'BLOCKED sin remoto configurado')" "handles the no-remote repo honestly (ruling 3)"
assert_eq "0" "$(has "$body" '- remoto propuesto:')" "the no-remote BLOCKED carries the preview the root needs to ask the owner (ruling 3)"
assert_eq "0" "$(has "$body" '- cuenta gh:')" "…and names the authenticated gh account, so an identity mismatch is visible before approving (ruling 14)"
assert_eq "0" "$(has "$body" 'sin recortar')" "raw git/gh errors are surfaced verbatim, never trimmed or reworded (ruling 14)"

# backlog fix: additive structured SSH-alias hint (ruling 14 stays honest-raw-stderr, extended not replaced)
assert_eq "0" "$(has "$body" 'cat ~/.ssh/config')" "reads ~/.ssh/config to build the structured hint"
assert_eq "0" "$(has "$body" 'alias candidatos en ~/.ssh/config')" "documents the candidate-alias suggestion line"
assert_eq "0" "$(has "$body" 'Extensión aditiva')" "the SSH hint extension is explicitly additive to the raw-stderr surfacing, never a replacement"
assert_eq "0" "$(has "$body" 'no eliges tú el alias correcto')" "release-manager only names candidates, it never picks or applies one itself"
assert_eq "0" "$(has "$body" 'No ejecuta')" "the never-execute-set-url property still holds unchanged after the extension"
assert_eq "0" "$(has "$body" 'BLOCKED árbol sucio')" "refuses to publish a dirty tree (ruling 6)"
assert_eq "0" "$(has "$body" 'KO tests en rojo')" "a red suite blocks the preview (ruling 4)"
assert_eq "0" "$(has "$body" 'verde NO verificado')" "an unknown suite is reported as unknown, never as green (ruling 4)"
assert_eq "0" "$(has "$body" 'gh pr merge')" "explicitly names the forbidden auto-merge"
assert_eq "0" "$(has "$body" 'Nunca commiteas')" "states it creates no commits (ruling 5)"

# --- operación configure-remote (ruling 3): la SEGUNDA mutación externa, con su propio gate ---
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "documents the remote-bootstrap operation"
assert_eq "0" "$(has "$body" 'approved-remote: action=create name=')" "documents the create approval line, verbatim"
assert_eq "0" "$(has "$body" 'approved-remote: action=use url=')" "documents the use-an-existing-remote approval line"
assert_eq "0" "$(has "$body" 'BLOCKED sin aprobación de remoto')" "refuses to configure a remote without the approval line"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación de remoto malformada')" "refuses a malformed remote approval"
assert_eq "0" "$(has "$body" 'BLOCKED ya hay remoto configurado')" "never clobbers a remote that already exists"
assert_eq "0" "$(has "$body" 'BLOCKED remoto creado pero push rechazado')" "distinguishes 'repo created, push failed' from 'nothing happened' (ruling 14)"
assert_eq "0" "$(has "$body" 'approved-push:` NO vale como aprobación de remoto')" "one approval never stands in for the other (ruling 2e)"
assert_eq "0" "$(has "$body" 'git remote set-url')" "names the command it must NOT run to 'fix' a URL (ruling 14)"

# --- v1.1: mensaje degradado consciente del host, action=create explícitamente GitHub-only ---
assert_eq "0" "$(has "$body" 'github.com')" "checks the remote URL for github.com before trying gh pr create"
assert_eq "0" "$(has "$body" 'abre tu PR/MR a mano')" "documents a host-generic fallback line for non-GitHub remotes"
assert_eq "0" "$(has "$body" 'solo crea en GitHub')" "documents that action=create is GitHub-only, explicitly"
assert_eq "0" "$(has "$body" '- siguiente:')" "closes by telling the owner to re-invoke, never by chaining the push itself (ruling 3)"
assert_eq "1" "$(has "$body" 'gh repo delete')" "never mentions any gh repo subcommand other than create"

# el veredicto DONE nunca lleva sufijo (lección 7 del handoff de fase 5b)
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere (validate-output.py rejects it)"

# Las líneas de preview llevan un COMANDO completo con valores reales y pasan de 120 chars con
# total normalidad — el cap de narración de validate-output.py las rechazaría como prosa suelta.
# La exención es por FORMA (prefijo fijo + comando), igual que DISCOVERY_Q_RE/DISCOVERY_OTHER_RE:
# se comprueba contra el hook REAL, no leyendo el regex.
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"
hook_says() { # hook_says <agent_type> <message-json> -> "accept" | "reject"
  local out root
  root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-delivery-hook.XXXXXX")"
  out="$(SWARM_ROOT="$root/.swarm" python3 "$HOOK" <<PYIN
{"agent_type": "$1", "hook_event_name": "SubagentStop", "last_assistant_message": $2}
PYIN
)"
  rm -rf "$root"
  if echo "$out" | grep -q '"decision": "block"'; then echo reject; else echo accept; fi
}
long_pr='DONE\nevidence: files=2 cmds=6 turns=7/15\n- preview pr: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/1234-5678/release-notes.md'
assert_eq "accept" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$long_pr")")" "a long '- preview pr:' line is accepted (form-based exemption, not the 120-char cap)"
long_cmd='DONE\nevidence: files=2 cmds=9 turns=12/15\n- pr comando: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/1234-5678/release-notes.md'
assert_eq "accept" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$long_cmd")")" "a long '- pr comando:' line is accepted too"
narr='DONE\nevidence: files=2 cmds=6 turns=7/15\n- he terminado de preparar la entrega y creo que lo mejor sería revisar con calma el resultado antes de seguir adelante con el push'
assert_eq "reject" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$narr")")" "plain long prose with a '- ' prefix is STILL rejected (the exemption is by form, not by dash)"

# ─────────────────────────── handoff-writer ───────────────────────────
F="$PLUGIN_ROOT/agents/handoff-writer.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/handoff-writer.md exists"
front="$(front_of "$F")"; body="$(body_of "$F")"

assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "handoff-writer is haiku (spec §7 and §7.0 mechanical leaf)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 8$' && echo 0 || echo 1)" "handoff-writer has maxTurns 8 (spec §7)"
assert_eq "0" "$(has "$front" 'Write')" "handoff-writer writes the MD with Write, never through a shell"
assert_eq "1" "$(has "$front" 'AskUserQuestion')" "handoff-writer cannot ask the owner"

assert_eq "0" "$(has "$body" 'Prompt copy-paste para la sesión nueva')" "the handoff keeps the established section shape"
assert_eq "0" "$(has "$body" 'Dónde está todo')" "the handoff keeps the 'where everything is' section"
assert_eq "0" "$(has "$body" 'Siguiente paso')" "the handoff keeps the 'next step' section"
assert_eq "0" "$(has "$body" 'docs/superpowers/handoffs')" "prefers the repo's existing handoffs directory"
assert_eq "0" "$(has "$body" 'docs/handoffs')" "falls back to docs/handoffs when the superpowers tree is absent"
assert_eq "0" "$(has "$body" 'No commiteas')" "never commits the handoff (ruling 9)"
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
