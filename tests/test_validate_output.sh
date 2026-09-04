#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

# missing evidence line -> block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "last_assistant_message": "OK"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "missing evidence line is blocked"

# OK + evidence files=0 -> block (spec smoke test 8)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "last_assistant_message": "OK\nevidence: files=0 cmds=1 turns=2/10"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "OK with files=0 is blocked"

# valid OK+evidence with extra spaces -> NO block (regression: lenient whitespace)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:extra-spacing-agent", "last_assistant_message": "OK\nevidence:  files=2  cmds=1  turns=3/10\nARCH · src/App/Foo.php:3 · sin interfaz → extraer interfaz"}
EOF
)"
assert_eq "" "$out" "lenient whitespace evidence line is accepted (no output)"

# valid minimal -> no output, exit 0
out_file="$fixture/valid-out.txt"
python3 "$HOOK" > "$out_file" 2>&1 <<'EOF'
{"agent_type": "swarm:vulnerability-scanner", "last_assistant_message": "DONE\nevidence: files=1 cmds=3 turns=1/10\nSEC · src/App/Foo.php:1 · secreto en claro → mover a env"}
EOF
rc=$?
assert_eq "0" "$rc" "valid minimal output exits 0"
assert_eq "0" "$(wc -l < "$out_file" | tr -d ' ')" "valid minimal output prints nothing"

# repeat failing input twice -> 2nd time accepted with systemMessage
bad_input='{"agent_type": "swarm:flaky-agent", "last_assistant_message": "OK"}'
first="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$first" | grep -q '"decision": "block"' && echo 0 || echo 1)" "first failure is blocked"
second="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$second" | grep -q 'systemMessage' && echo 0 || echo 1)" "second failure is accepted with systemMessage"
assert_eq "1" "$(echo "$second" | grep -q '"decision": "block"' && echo 0 || echo 1)" "second failure is not a block"

# non-swarm agent_type -> no output
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "some-other-agent", "last_assistant_message": "garbage output with no structure at all"}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type produces no output"

# turns==max -> systemMessage present, decision not block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=3 cmds=2 turns=15/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns==max produces systemMessage"
assert_eq "1" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "turns==max is not a block"

# turns>max (miscounted overflow) -> also treated as maxTurns, not silently passed
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=3 cmds=2 turns=16/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns>max also produces systemMessage"

# stop_hook_active=true -> hook stands down entirely, no output even on garbage
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:flaky-agent", "last_assistant_message": "garbage", "stop_hook_active": true}
EOF
)"
assert_eq "" "$out" "stop_hook_active=true short-circuits before any validation"

# non-string agent_type/last_assistant_message -> no crash, no output (fail-closed, not fail-open)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": ["swarm:weird"], "last_assistant_message": 42}
EOF
)"
rc=$?
assert_eq "0" "$rc" "malformed field types do not crash the hook"
assert_eq "" "$out" "malformed field types produce no output"

# narration smuggled behind a "- " prefix, over the length cap -> still rejected
long_line="- $(python3 -c 'print("x" * 130)')"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:reviewer", "last_assistant_message": "OK\nevidence: files=1 cmds=1 turns=1/10\n$long_line"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "long narration behind a dash prefix is still rejected"

# short "- " lines (discovery-orchestrator's own - Q/- warn/- findings format) still pass
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=9 turns=9/15\n- Q1 [Valor] · pregunta · A) uno · B) dos · rec: A\n- findings: value-critic,options-generator,research-analyst,feasibility-spiker"}
EOF
)"
assert_eq "" "$out" "short dash-prefixed batch lines are accepted (no output)"

# C1 real (review final fase 2, 2026-09-02): una línea -Q de verdad, con pregunta larga y 3
# opciones al límite de 8 palabras, supera los 120 chars con normalidad (184-212 en el run real)
# -- el cap uniforme la rechazaba como narración. Debe seguir aceptándose SOLO por reconocer el
# formato estructural (cabecera + · A) ... · rec: <letra>), no por venir con "- " delante.
long_real_q="- Q1 [Alcance] Que conjunto exporta el boton, cambia arquitectura entera · A) solo pagina visible · B) todo el resultado del filtro con tope · C) todo el historico de facturas · rec: B"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=2 cmds=3 turns=6/15\n$long_real_q"}
EOF
)"
assert_eq "" "$out" "a real 184-char Q line with question+3 options+rec is accepted (C1 fix)"

# Un -Q malformado (sin rec: al final) NO se exime solo por parecerse -- sigue sujeto al cap si
# se pasa de 120, para no reabrir la narración disfrazada de pregunta.
malformed_q="- Q1 sin las opciones ni el rec al final, texto largo relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno relleno"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:discovery-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=1 turns=2/15\n$malformed_q"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "a malformed -Q line (no rec:) over 120 chars is still rejected, not exempted"

# Análisis (fix Task 6, review 2026-09-02; ampliado a 7 hojas con solid-auditor): una línea
# `- lentes: ...` real con las 7 hojas del dominio analysis (agents/analysis-orchestrator.md
# "## Salida") supera con normalidad los 120 chars -- confirmado en vivo por encima de 231 chars.
# Debe seguir aceptándose SOLO por reconocer el vocabulario fijo `- lentes: ...`/`- sin hallazgos:
# ...` (DISCOVERY_OTHER_RE ampliada), no por venir con "- " delante.
long_real_lentes="- lentes: opportunity-analyst, architecture-auditor, security-auditor, vulnerability-scanner, performance-analyst, data-model-auditor, solid-auditor, motivo: objetivo casó con seguridad, rendimiento, arquitectura, datos, oportunidades de negocio y principios de diseño"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:analysis-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=6 turns=8/20\n$long_real_lentes"}
EOF
)"
assert_eq "" "$out" "a real long - lentes: line with all 7 lenses is accepted"

# Una línea "- " cualquiera que NO case con el vocabulario fijo de analysis (ni lentes/sin
# hallazgos/hallazgos adicionales/BLOCKED) NO se exime solo por parecerse -- sigue sujeta al cap,
# para no reabrir narración disfrazada de salida de analysis.
unstructured_analysis_line="- resumen: revisé bastante código de seguridad y rendimiento y encontré varias cosas que convendría mirar con calma en otra pasada más adelante"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:analysis-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=6 turns=8/20\n$unstructured_analysis_line"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "an unstructured long - line from analysis-orchestrator is still rejected, not exempted"

# Las otras dos líneas fijas de analysis (prefijo dinámico) también se aceptan sin más -- cubren
# ANALYSIS_ADDITIONAL_RE y ANALYSIS_LEAF_BLOCKED_RE.
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:analysis-orchestrator", "last_assistant_message": "DONE\nevidence: files=1 cmds=6 turns=8/20\n- 3 hallazgos adicionales en .swarm/findings/architecture-auditor.md\n- vulnerability-scanner BLOCKED: repo demasiado grande para el escaneo en este turno"}
EOF
)"
assert_eq "" "$out" "the two dynamic-prefix analysis lines (N hallazgos adicionales / hoja BLOCKED) are accepted"

# Diseño (fix Important #1, review final de fase 4): una línea `- grill: ...` real con el resumen
# del arbitraje de design-orchestrator (agents/design-orchestrator.md "## Salida"/"## Arbitraje")
# supera con normalidad los 120 chars -- mismo bug de fondo que C1/lentes, confirmado en vivo con
# líneas de 150+ chars (shape del checklist de smoke, docs/superpowers/plans/
# 2026-09-03-phase4-smoke-checklist.md item 1). Debe seguir aceptándose SOLO por reconocer el
# vocabulario fijo `- grill: ...` (DISCOVERY_OTHER_RE ampliada), no por venir con "- " delante.
long_real_grill="- grill: 2 P1 incorporados (BOM UTF-8 para Excel, truncado de StreamedResponse tras headers 200), 3 P2/P3 anotados como riesgo en el plan"
out="$(python3 "$HOOK" <<EOF
{"agent_type": "swarm:design-orchestrator", "last_assistant_message": "DONE\nevidence: files=5 cmds=7 turns=15/20\n$long_real_grill"}
EOF
)"
assert_eq "" "$out" "a real 150+ char - grill: line with arbitration summary is accepted"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
