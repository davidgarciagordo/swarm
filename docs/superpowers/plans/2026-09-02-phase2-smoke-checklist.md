# Checklist de smoke — Fase 2 discovery (`discovery-orchestrator` + 4 hojas + `AskUserQuestion` en la raíz)

Gate manual del owner. Fixture: un repo git temporal con `/swarm:init` hecho (sirve
`tests/lib.sh::make_fixture` + `scripts/swarm-init.sh`). Sesión INTERACTIVA:
`claude --plugin-dir /Users/davidgarciagordo/projects/multiagents --permission-mode bypassPermissions`
(`claude -p` corta antes de que el batch llegue a `AskUserQuestion` — lección de fase 1b).

Cada ítem lleva **Evidencia:** para pegar la salida real — no marcar sin pegarla.

## 1. Run `full` con objetivo de producto → batch → `AskUserQuestion` → decisiones

`/swarm:run "añadir export CSV del listado de facturas" --tier=full`. Se espera, en este orden:
`memory-orchestrator` (`build`) → `OK`/`DONE` → `discovery-orchestrator` lanzado NOMBRADO con
`tier: full` y `objective:` → las 4 hojas en UN mismo mensaje (`Agent` ×4, nombres = rol,
`research-analyst` y `feasibility-spiker` en background) → salida `DONE` con ≤4 líneas `- Q…` →
la raíz llama UNA vez a `AskUserQuestion` (la recomendada primera con `(Recommended)`) → tras
responder, `.swarm/decisions.md` tiene una línea `discovery <run-id> Q<n> …` por pregunta y
`run/<id>/summary.md` tiene las líneas `- Q…` espejadas.
Evidencia: ✅ PASS — ejecutado en vivo por el owner (2026-09-02) contra el repo principal. Batch
real de 4 preguntas presentado, respondidas, `decisions.md` con la línea completa incluido
`objective:` literal y el resumen de las 4 respuestas. Además: el sistema detectó un CONFLICTO
real entre Q2 (histórico completo) y Q4 (endpoint síncrono) — `value-critic` ya lo había avisado
por mailbox a `options-generator` — y quedó una segunda línea `SUPERSEDE`/`CONFLICTO RESUELTO`
tras la decisión del owner de resolverlo (job async en cola). `run/summary.md` no existía tras
el cierre — pendiente de investigar en la review final de rama (posible gap de T6, no bloqueante:
`decisions.md` sí quedó completo).

## 2. `feasibility-spiker` en worktree: repo principal intacto, escritura vía `memory-orchestrator`

En el transcript del ítem 1: `feasibility-spiker` corre en un worktree (cwd distinto), crea
`spike/`, ejecuta desde fichero (`python3 spike/…`), y su finding llega a
`.swarm/findings/feasibility-spiker.md` por `SendMessage(memory-orchestrator, "write finding …")`
— NUNCA por `mem-files.sh` directo. Tras el run: `git status --porcelain` en el repo fixture está
vacío (nada del spike se coló) y `git worktree list` no deja worktrees huérfanos.
Evidencia: ⚠️ FALLÓ EN PRIMER INTENTO → bug real HIGH, encontrado por este mismo ítem, exactamente
para lo que existe. `git worktree list` mostró un worktree huérfano real
(`.claude/worktrees/agent-ae25ffb99d186c453`) con el spike sin commitear dentro
(`check_invoice_domain.py`) tras cerrar el run. Causa: `feasibility-spiker.md` afirmaba "el
worktree se descarta solo" — FALSO, la plataforma solo auto-limpia un worktree SIN cambios, y el
spike siempre escribe. Nadie llamaba a `git worktree remove`. Arreglado: `discovery-orchestrator`
anota el `agentId` del spawn y lo borra (`--force`) tras el `DONE`/`BLOCKED` del spiker (commit
`03d660a`, con test que reproduce el ciclo real add→dirty→remove→verify). Worktree huérfano
existente limpiado a mano. `git status --porcelain` del repo principal: limpio salvo `.swarm/`
sin trackear y `.gitignore` con el bloque `# swarm` (esperado, efecto normal de `/swarm:init`
corriendo ahí — no relacionado con el spike). ✅ PASS tras el fix (verificado con worktree de
prueba real, no solo con el guard).

## 3. Tier `light` → hojas de juicio en sonnet

`/swarm:run "añadir export CSV del listado de facturas" --tier=light`. En el transcript,
`discovery-orchestrator` lanza `value-critic` y `options-generator` con `model: "sonnet"` en la
llamada a `Agent`; `research-analyst`/`feasibility-spiker` sin override.
Evidencia: parcial — NO ejecutado en vivo (el ítem 1 ya se corrió en `full`, y repetirlo en
`light` se dejó pendiente al priorizar los bugs reales encontrados en 2 y 7). Verificado a nivel
de código en la review adversarial de T5 (trazado a mano contra la tabla de spawn de
`discovery-orchestrator.md`: `model: "sonnet"` presente solo para `value-critic`/
`options-generator`, ausente para `research-analyst`/`feasibility-spiker`, condicionado a
`tier: light`). Pendiente confirmación en vivo.

## 4. `direct` y objetivos no-producto no lanzan discovery

`/swarm:run "corrige el typo del README" --tier=direct` → sin run, sin discovery.
`/swarm:run "refactor: extraer InvoiceExporter a servicio" --tier=light` → run abierto, `build`,
y la raíz cierra con `- discovery omitido: objetivo de refactor` — `discovery-orchestrator` NO
aparece en `run/<id>/agents/`.
Evidencia: primera mitad ✅ PASS — ejecutado real vía `claude -p` contra fixture limpio:
`--tier=direct` respondió directo (`BLOCKED`, no había README en el fixture — comportamiento
correcto de fixture, no del sistema), CERO directorio nuevo bajo `.swarm/run/`. Segunda mitad
(`--tier=light` + refactor → discovery omitido) inconclusa: `claude -p` cortó la cadena async
antes de llegar a la decisión de omitir discovery — mismo límite de método que los ítems 1/2/3/5/7
(headless no espera cadenas multi-salto), no un fallo del sistema. La lógica de omisión SÍ se
verificó a nivel de código en la review de T6 (P2-c, ejemplo `DONE`/`OK` separado del `BLOCKED
dominio no implementado`). Pendiente confirmación en vivo de la segunda mitad.

## 5. Ninguna hoja pregunta al owner

`grep -c AskUserQuestion` sobre el transcript del ítem 1: solo la llamada de la raíz (1). Ningún
`AskUserQuestion` desde `discovery-orchestrator` ni desde las hojas (la plataforma lo impediría
por `tools:`, pero la evidencia tiene que ser del transcript real).
Evidencia: ✅ PASS — cero apariciones de `AskUserQuestion` en todo el árbol de artefactos del run
real (`findings/`, `mailbox/`, `agents/*.json`), confirmado con grep directo sobre
`.swarm/run/<id>/`.

## 6. Hoja en adhoc (sin run-id)

`Agent(subagent_type: "swarm:value-critic", name: "value-critic", prompt: "operation: critique\nobjective: añadir export CSV")`
desde la sesión, sin `run-id:`. Se espera `OK` + líneas `VALUE · discovery:<n> · …` y el finding
en `.swarm/findings/value-critic.md` con `[run:adhoc]`; sin `BLOCKED`, sin intentar `open`.
Evidencia: ✅ PASS con matiz honesto — ejecutado real vía `claude -p` contra un fixture SIN pack
construido (solo `/swarm:init`, nunca un `/swarm:run` previo). Verdict real fue
`BLOCKED falta context-pack` (correcto: intentó pedir el pack a `memory-orchestrator`, que no
estaba vivo en este contexto de una sola hoja aislada — comportamiento esperado, no el escenario
limpio con pack ya existente que asumía el ítem). Lo importante SÍ se cumplió: escribió 3
hallazgos bajo `discovery-adhoc:1..3` (aislado por run, confirma que el fix de T5 funciona también
en modo adhoc) con `[run:adhoc]`, y nunca intentó `mem-manifest.sh open`.

## 7. Hook de evidencia en vivo

En el transcript del ítem 1, ninguna salida de `swarm:*` fue rechazada por `validate-output.py`
(buscar `decision": "block`). Si alguna lo fue, el ejemplo de "## Salida" de ese agente miente y
`tests/test_agents_output_examples.sh` tiene un hueco: arreglar ambos.
Evidencia: ⚠️ SÍ hubo rechazos, en LOS SEIS agentes del run, sistemáticamente — hallazgo real, no
un bug de bloqueo (el reintento de 1 vez ya diseñado lo absorbió, ningún run se rompió), pero sí
un coste sistemático de 1 turno extra por agente, siempre. Dos causas, ambas confirmadas leyendo
el transcript real (`Stop hook feedback: …`): 4 agentes por "línea 1 debe ser un veredicto"
(escribían una frase antes del veredicto), 2 por "narración detectada" (prosa suelta tras un
hallazgo). No es que el ejemplo de "## Salida" mienta — es que el hábito por defecto de cerrar un
turno con una frase de cortesía le gana a la instrucción del formato en el primer intento, para
cualquier modelo/agente. Arreglado en el contrato compartido (no por agente): párrafo explícito en
`skills/swarm-protocol/SKILL.md` §4, con esta misma evidencia citada, dejando claro que el ÚLTIMO
mensaje del turno empieza LITERAL en el veredicto, sin preámbulo ni cierre (commit `a3efd7f`).
Pendiente confirmar en una futura ejecución que el ratio de reintentos baja de verdad.

## Firma

- [ ] Owner: ________________  Fecha: ________________
