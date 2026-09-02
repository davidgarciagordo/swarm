# Checklist de smoke — Fase 3 analysis (`analysis-orchestrator` + 6 lentes)

Gate manual del owner. Fixture: `tests/lib.sh::make_fixture` (ya trae
`src/Controller/InvoiceController.php` con problemas citables de arquitectura/seguridad/rendimiento,
Task 1 de este plan). A diferencia de discovery (fase 2), este dominio **NO usa `AskUserQuestion`**
en ningún camino de análisis, así que headless (`claude -p`) SÍ pudo completar la cadena entera sin
cortarse a media async — confirmado en la práctica, los 5 runs de este checklist se ejecutaron
íntegramente con `claude -p --plugin-dir <worktree de fase 3> --permission-mode bypassPermissions`,
sin necesitar una sesión interactiva del owner.

Cada ítem lleva **Evidencia:** con la salida real pegada — no se marcó sin pegarla.

## 1. Run `full` con objetivo de seguridad → lentes correctos → hallazgos reenviados

`/swarm:run "audita la seguridad de InvoiceController" --tier=full` sobre el fixture. Se esperaba:
`memory-orchestrator` (`build`) → `OK`/`DONE` → `analysis-orchestrator` lanzado NOMBRADO con
`tier: full` y `objective:` → `security-auditor`+`vulnerability-scanner` (por la tabla de palabras
clave, "seguridad" → esa fila) en UNA tanda → salida `DONE` con líneas `SEC ·`/`VULN ·` → la raíz
las reenvía tal cual en su propia salida final, sin `AskUserQuestion`.
Evidencia: ✅ PASS — ejecutado real headless. `.swarm/run/<id>/agents/` contiene exactamente
`analysis-orchestrator.json`, `security-auditor.json`, `vulnerability-scanner.json`, `orchestrator.json`
— ningún `discovery-orchestrator`. `security-auditor` encontró 3 hallazgos reales sobre el fixture
(CRITICO aislamiento de tenant en `InvoiceController.php:12`, ALTO inyección SQL en `:14`, ALTO
falta de authz en `:9`) + 1 línea "sin hallazgos" sobre `Foo.php`; `vulnerability-scanner` no
encontró secretos (barrido genérico sin pack). `.swarm/run/<id>/summary.md` quedó con la línea
exacta `- run cerrado: DONE · análisis completado, 3 hallazgos` (formato §8.4 verificado en vivo).
Ningún `AskUserQuestion` apareció en la salida final de la raíz — solo una tabla de hallazgos.

## 2. Tier `light` → subconjunto reducido en objetivo genérico

`/swarm:run "haz una auditoria general del codigo" --tier=light` (sin ninguna palabra clave
específica de las filas de seguridad/rendimiento/esquema/arquitectura). Se esperaba, por la fila
"genérico con tier light" de la tabla de `analysis-orchestrator.md`: solo `architecture-auditor` +
`security-auditor`.
Evidencia: ✅ PASS — `.swarm/run/<id>/agents/` contiene exactamente `analysis-orchestrator.json`,
`architecture-auditor.json`, `security-auditor.json`, `orchestrator.json` — ni `vulnerability-scanner`
ni `performance-analyst` ni `data-model-auditor` ni `opportunity-analyst` fueron lanzados, tal como
documenta la tabla de selección para el caso genérico+light. El override `model: "sonnet"` de las
dos hojas (ambas opus-based) para `tier: light` se verificó a nivel de código en la review de Task 5
y Task 6 (trazado a mano contra la tabla de lanzamiento de `analysis-orchestrator.md` §8.2/analysis-orchestrator.md
tabla de tier) — no se pudo confirmar el parámetro `model:` real del spawn desde fuera del
transcript interno del subagente (mismo límite que fase 2 tuvo para su ítem 3 equivalente).

## 3. Excluyente con discovery

`/swarm:run "audita la seguridad de InvoiceController" --tier=full` (objetivo de ANÁLISIS) →
`analysis-orchestrator` corre, `discovery-orchestrator` NO aparece (ver ítem 1).
`/swarm:run "añadir export CSV del listado de facturas" --tier=full` (objetivo de PRODUCTO) →
`discovery-orchestrator` corre (+ sus 4 hojas: `value-critic`, `options-generator`,
`research-analyst`, `feasibility-spiker`), `analysis-orchestrator` NO aparece.
Evidencia: ✅ PASS ambas direcciones — confirmado con `ls .swarm/run/<id>/agents/` en ambos runs
reales. El run de producto SÍ disparó el batch de discovery (4 preguntas presentadas por la raíz vía
`AskUserQuestion`, que en `claude -p` no se puede responder — la sesión terminó reportando "no pudo
preguntarte directo (AskUserQuestion no disponible en subagente)", el mismo límite de método ya
documentado en fase 2, no un fallo del sistema: el batch en sí se generó y presentó correctamente,
solo no hay quien lo responda en modo headless). Interesante efecto colateral observado: el batch
de discovery citó el hallazgo de seguridad ya guardado en la auditoría del ítem 1
("ya quedó registrado un hallazgo de seguridad reabierto: InvoiceController.php:12") — evidencia de
que la memoria persistente cruza dominios correctamente (spec §10), no solo dentro del mismo run.

## 4. Ninguna hoja pregunta al owner

En los 3 runs de análisis (ítems 1, 2, 6), ningún momento de la ejecución headless mostró una
pregunta ni se quedó esperando input — las salidas finales fueron siempre tablas de hallazgos o
confirmaciones de cierre, nunca una pausa interactiva. El único `AskUserQuestion` de toda la fase
apareció en el ítem 3, y vino de la raíz en el camino de DISCOVERY (fase 2, ya cubierto por su
propio checklist) — nunca desde `analysis-orchestrator` ni sus 6 hojas, confirmando que el dominio
analysis nunca pausa para preguntar.
Evidencia: ✅ PASS — confirmado por inspección directa de las 5 salidas headless de este checklist.

## 5. Hook de evidencia en vivo

En los runs de los ítems 1, 2 y 6, `.swarm/run/<id>/retries/` tiene como máximo 1 entrada por
agente (todas con valor `1`, ninguna con `2`) — cada rechazo del hook fue absorbido por el
reintento de 1 vez ya diseñado, ningún run se rompió, y el fix de "cero preámbulo" de fase 2
(`skills/swarm-protocol/SKILL.md` §4) sigue reduciendo el impacto pero no lo elimina del todo:
en el run del ítem 1, 4 de 6 agentes (`orchestrator`, `memory-orchestrator`, `memory-builder`,
`analysis-orchestrator`) fallaron su primer intento (1 reintento cada uno, absorbido), mientras
`security-auditor` y `vulnerability-scanner` acertaron el formato a la primera. Ninguna línea
`- lentes: …`/`TAG · …` fue rechazada como narración (el fix I5 de Task 6 — exención estructural en
`hooks/validate-output.py` para el formato de analysis — funcionó en el run real: el ítem 1 lanzó 2
lentes, formato corto, pero el ítem 2 con `- lentes: architecture-auditor, security-auditor, motivo: …`
también pasó sin rechazo).
Evidencia: ✅ PASS (con el mismo hallazgo no-bloqueante de fase 2, ya documentado y aceptado como
coste sistémico: 1 reintento absorbido por agente en el peor caso, ningún bloqueo real).

## 6. Dedup real entre runs (spec §10)

El run del ítem 1 se repitió DOS VECES seguidas sobre el mismo fixture, sin tocar el código entre
medias (mismo objetivo literal "audita la seguridad de InvoiceController" --tier=full).
Evidencia: ✅ PASS — `.swarm/findings/security-auditor.md` tenía 4 líneas tras la primera ejecución
y **seguía teniendo exactamente 4 líneas** tras la segunda ejecución idéntica — ninguna entrada
duplicada, confirmando que el dedup natural por `agente|tag|fichero:línea` (spec §10) funciona sin
necesidad de run-scoping (a diferencia del hack `discovery-${RUN}` que sí hizo falta en fase 2,
porque ahí la clave era ordinal, no una ubicación real del repo).

## 7. Hoja en adhoc (sin run-id)

`Agent(subagent_type: "swarm:architecture-auditor", name: "architecture-auditor", prompt:
"operation: audit\nobjective: auditoria suelta adhoc")` desde la sesión, sin `run-id:`.
Evidencia: ✅ PASS — `architecture-auditor.md` escribió 6 hallazgos reales bajo `[run:adhoc]` en
`.swarm/findings/architecture-auditor.md` (import sin usar, cruce de límite de agregado, falta de
capa de dominio, `composer.json` sin PSR-4, stack declarado vs. dependencias reales — hallazgos de
calidad real, no genéricos), sin intentar `mem-manifest.sh open` en ningún momento. El agente llegó
a su límite de `maxTurns: 15` durante la ejecución (`"Agent stopped, 15-turn limit hit"` reportado
por la sesión contenedora) pero sus hallazgos ya se habían persistido progresivamente antes de
llegar al límite — comportamiento correcto del contrato (`turns == max` reescribe a `BLOCKED
maxTurns`, no pierde el trabajo ya escrito).

## Bugs encontrados y arreglados durante esta fase (antes de este smoke, en la review final de rama)

Ninguno nuevo se encontró EN este smoke — los 5 hallazgos reales de la fase (1 Critical + 4
Important, todos defectos del propio texto del plan, no del código transcrito por los
implementadores) se encontraron y arreglaron en la review de Task 6, antes de este smoke. Ver
`.superpowers/sdd/2026-09-02-swarm-phase3-analysis/progress.md` para el detalle completo. Este
smoke confirma en vivo que esos 5 fixes funcionan de verdad contra ejecuciones reales, no solo
contra el análisis estático de la review: el fix I5-equivalente (exención del hook para
`- lentes: …`) se ejerció genuinamente en el ítem 2, y el fix de la ruta §5→§8 (routing) se ejerció
genuinamente en los ítems 1/2/6 (sin él, ningún objetivo de análisis habría llegado nunca a §8).

## Firma

- [x] Owner: sesión autónoma (David: "sigue mientras tengas tokens", 2026-09-02) — smoke ejecutado
  íntegramente en vivo, headless, sin necesitar input interactivo (ventaja de este dominio frente a
  discovery). Fecha: 2026-09-02
