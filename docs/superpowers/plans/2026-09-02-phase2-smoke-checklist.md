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
Evidencia:

## 2. `feasibility-spiker` en worktree: repo principal intacto, escritura vía `memory-orchestrator`

En el transcript del ítem 1: `feasibility-spiker` corre en un worktree (cwd distinto), crea
`spike/`, ejecuta desde fichero (`python3 spike/…`), y su finding llega a
`.swarm/findings/feasibility-spiker.md` por `SendMessage(memory-orchestrator, "write finding …")`
— NUNCA por `mem-files.sh` directo. Tras el run: `git status --porcelain` en el repo fixture está
vacío (nada del spike se coló) y `git worktree list` no deja worktrees huérfanos.
Evidencia:

## 3. Tier `light` → hojas de juicio en sonnet

`/swarm:run "añadir export CSV del listado de facturas" --tier=light`. En el transcript,
`discovery-orchestrator` lanza `value-critic` y `options-generator` con `model: "sonnet"` en la
llamada a `Agent`; `research-analyst`/`feasibility-spiker` sin override.
Evidencia:

## 4. `direct` y objetivos no-producto no lanzan discovery

`/swarm:run "corrige el typo del README" --tier=direct` → sin run, sin discovery.
`/swarm:run "refactor: extraer InvoiceExporter a servicio" --tier=light` → run abierto, `build`,
y la raíz cierra con `- discovery omitido: objetivo de refactor` — `discovery-orchestrator` NO
aparece en `run/<id>/agents/`.
Evidencia:

## 5. Ninguna hoja pregunta al owner

`grep -c AskUserQuestion` sobre el transcript del ítem 1: solo la llamada de la raíz (1). Ningún
`AskUserQuestion` desde `discovery-orchestrator` ni desde las hojas (la plataforma lo impediría
por `tools:`, pero la evidencia tiene que ser del transcript real).
Evidencia:

## 6. Hoja en adhoc (sin run-id)

`Agent(subagent_type: "swarm:value-critic", name: "value-critic", prompt: "operation: critique\nobjective: añadir export CSV")`
desde la sesión, sin `run-id:`. Se espera `OK` + líneas `VALUE · discovery:<n> · …` y el finding
en `.swarm/findings/value-critic.md` con `[run:adhoc]`; sin `BLOCKED`, sin intentar `open`.
Evidencia:

## 7. Hook de evidencia en vivo

En el transcript del ítem 1, ninguna salida de `swarm:*` fue rechazada por `validate-output.py`
(buscar `decision": "block`). Si alguna lo fue, el ejemplo de "## Salida" de ese agente miente y
`tests/test_agents_output_examples.sh` tiene un hueco: arreglar ambos.
Evidencia:

## Firma

- [ ] Owner: ________________  Fecha: ________________
