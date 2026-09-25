#!/usr/bin/env bash
# tests/test_orchestrator_delivery.sh — la raíz integra el dominio delivery (fase 6): la ÚNICA vía
# legítima de autorizar un push real (AskUserQuestion de la raíz, spec §3.2 regla 7), la aprobación
# que NOMBRA remoto/rama/base, y el checkpoint humano que impide encadenar la entrega.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" '## 12. Delivery')" "root has a dedicated §12 section"
assert_eq "0" "$(has "$body" 'subagent_type: "swarm:delivery-orchestrator"')" "root launches delivery-orchestrator by type"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "root documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "root documents phase B"
assert_eq "0" "$(has "$body" 'NEVER chain this automatically')" "delivery never auto-chains (same checkpoint as §10)"
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "root builds the approval line with its exact shape"
assert_eq "0" "$(has "$body" 'approved-push: remote=origin branch=feature/export-csv base=master url=')" "the constructed header carries the fourth field, url=, pinning the remote's URL between preview and approval"
assert_eq "0" "$(has "$body" 'The four fields')" "root names four fields when building the header, not three"
assert_eq "0" "$(has "$body" 'AskUserQuestion')" "root uses AskUserQuestion for the approval"
assert_eq "0" "$(has "$body" 'never from a generic yes')" "a bare yes is not an approval"
assert_eq "0" "$(has "$body" 'green NOT verified')" "the unverified-green warning must reach the question text (ruling 4)"
assert_eq "0" "$(has "$body" 'FRESH `Agent` call')" "phase B is a fresh Agent launch, not a SendMessage resume (ruling 11)"

# el bootstrap de remoto (ruling 3): el ÚNICO BLOCKED que abre una pregunta en vez de cerrar el run
assert_eq "0" "$(has "$body" '### 12.2bis')" "root has the no-remote decision point as its own section"
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "root documents the remote-bootstrap operation"
assert_eq "0" "$(has "$body" 'approved-remote: action=create name=')" "root builds the create approval with its exact shape"
assert_eq "0" "$(has "$body" 'approved-remote: action=use url=')" "…and the use-an-existing-remote one too"
assert_eq "0" "$(has "$body" 'proposed remote')" "the preview reaches the question text before the owner decides"
assert_eq "0" "$(has "$body" 'you don'"'"'t chain the delivery')" "creating the remote never chains straight into the push (ruling 3)"
assert_eq "0" "$(has "$body" 'BLOCKED malformed remote url')" "a hostile or malformed pasted URL closes the run, it is not sanitised"
# y la frase que la versión anterior tenía y ahora sería FALSA
assert_eq "1" "$(has "$body" 'There is no question to ask about a publication that cannot be prepared.')" "the old 'no question to ask' blanket rule is gone (it is false for the no-remote case)"

# la lección 4 del handoff: el párrafo de exención de saneado, LITERAL, una vez por sección de reenvío
assert_eq "0" "$(has "$body" 'That exemption does NOT cover the closing `summary --line`.')" "the sanitisation exemption paragraph is present verbatim"
occurrences="$(grep -cF 'That exemption does NOT cover the closing `summary --line`.' "$F")"
assert_eq "5" "$occurrences" "the paragraph appears once per forwarding section (§8.3, §9.3, §10.3, §11.3, §12.3)"

# la raíz ya no puede seguir diciendo que el dominio delivery no existe. Dos sitios reales,
# verificados en disco el 2026-09-03: el párrafo "Alcance actual" (línea ~22) y el ejemplo de salida
# de §7 (línea ~563). Lección 8: un fix en uno de los dos no está completo.
assert_eq "1" "$(has "$body" 'DOES NOT EXIST YET')" "root no longer says the delivery domain does not exist"
assert_eq "1" "$(has "$body" 'BLOCKED domain not implemented (delivery-orchestrator, phase 6)')" "the stale §7 output example is gone too"
assert_eq "0" "$(has "$body" 'delivery-orchestrator` (phase 6')" "the scope paragraph now lists delivery as an available domain"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
