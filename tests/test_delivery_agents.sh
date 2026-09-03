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

# propiedades permanentes
assert_eq "0" "$(has "$body" 'BLOCKED HEAD en rama protegida')" "never publishes from a protected branch"
assert_eq "0" "$(has "$body" 'BLOCKED sin remoto configurado')" "handles the no-remote repo honestly (ruling 3)"
assert_eq "0" "$(has "$body" '- remoto propuesto:')" "the no-remote BLOCKED carries the preview the root needs to ask the owner (ruling 3)"
assert_eq "0" "$(has "$body" '- cuenta gh:')" "…and names the authenticated gh account, so an identity mismatch is visible before approving (ruling 14)"
assert_eq "0" "$(has "$body" 'sin recortar')" "raw git/gh errors are surfaced verbatim, never trimmed or reworded (ruling 14)"
assert_eq "0" "$(has "$body" 'BLOCKED árbol sucio')" "refuses to publish a dirty tree (ruling 6)"
assert_eq "0" "$(has "$body" 'KO tests en rojo')" "a red suite blocks the preview (ruling 4)"
assert_eq "0" "$(has "$body" 'verde NO verificado')" "an unknown suite is reported as unknown, never as green (ruling 4)"
assert_eq "0" "$(has "$body" 'gh pr merge')" "explicitly names the forbidden auto-merge"
assert_eq "0" "$(has "$body" 'Nunca commiteas')" "states it creates no commits (ruling 5)"

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

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
