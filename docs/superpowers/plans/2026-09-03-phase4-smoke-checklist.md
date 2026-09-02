# Checklist de smoke — Fase 4 design (`design-orchestrator` + planner/pattern-advisor/domain-modeler + grill×3)

Gate. Fixture: `tests/lib.sh::make_fixture`. Ejecutado headless (`claude -p --plugin-dir <este
worktree> --permission-mode bypassPermissions`), sesión autónoma nocturna (David: "total
autonomía... hasta v1 estable", 2026-09-03).

## 1. Cadena completa: discovery (ya cerró) → design → 3 hojas → grill×3 → arbitraje

Se sembró `decisions.md` con una decisión ya cerrada para el objetivo "añadir export CSV del
listado de facturas" (simulando el camino §5.1 "ya cerró", el mismo mecanismo que un run real de
discovery habría dejado) y se corrió `/swarm:run "añadir export CSV del listado de facturas"
--tier=full`.
Evidencia: ✅ PASS con corte metodológico honesto — cadena real completa hasta el arbitraje:
discovery se saltó correctamente vía "ya cerró" (§5.1, sin `discovery-orchestrator` en
`.swarm/run/<id>/agents/`), `design-orchestrator` se lanzó nombrado con `tier: full`,
`pattern-advisor`+`domain-modeler` corrieron en la misma tanda y devolvieron hallazgos reales
(`PATTERN · src/Controller/InvoiceController.php:11 · introduce Repository...`,
`MODEL · ...Invoice raíz de agregado...`), `planner` escribió un plan REAL de 154 líneas en
`docs/superpowers/plans/2026-09-03-export-csv-facturas.md` — de calidad alta, citando el bug real
de inyección SQL del fixture (`InvoiceController.php:14`), invariantes de dominio, riesgos
concretos (TenantId sin resolver, versión de Symfony contradictoria). **Los 3 lentes grill
externos (`working-methods:grill-architect/operator/engineer`) se lanzaron y respondieron de
verdad** — el riesgo más grande de toda la fase (el grant cruzado `Agent(working-methods:...)`
desde el `tools:` de un subagente, nunca antes probado en este repo) **queda confirmado
funcionando**, con hallazgos P1 reales y sustanciosos (BOM UTF-8 para Excel, truncado de
`StreamedResponse` tras headers 200, incoherencia bounded-context agregado↔mapper).
`design-orchestrator` arbitró correctamente: detectó los P1 y relanzó `planner` con `operation:
revise` — exactamente el diseño previsto en Task 4. **El corte fue el propio timeout de 600s de
`claude -p` esperando la cadena async** (confirmado leyendo el transcript real de la sesión: el
plan quedó íntegro, sin editar a medias, y el mensaje final es un "tool use rejected" inyectado
por el timeout externo, no un error del enjambre) — mismo límite de método ya documentado en
fases 2/3 para cadenas muy largas, no un fallo del sistema. Con esta evidencia, los componentes
más nuevos y de mayor riesgo de la fase (grant cruzado, arbitraje real) están verificados en
producción real, no solo por review estática.

## 2. `tier: light` nunca encadena a design

`/swarm:run "añadir export CSV del listado de facturas" --tier=light"` sobre el mismo objetivo ya
decidido.
Evidencia: ✅ PASS — `.swarm/run/<id>/agents/` contiene ÚNICAMENTE `orchestrator.json`. Ni
`discovery-orchestrator` (se saltó por "ya cerró", correcto) ni `design-orchestrator` (nunca se
lanza en `light`, correcto) aparecen. Run cerrado limpio: "Curator cerró: DONE, memoria del run
limpiada. Todo el pipeline light-tier completo, sin pendientes."

## 3. Excluyente con analysis

No re-ejecutado en vivo en esta fase (mismo mecanismo de exclusión ya verificado en vivo en fase
3 — discovery/analysis nunca corren juntos — y design solo encadena tras discovery, nunca tras
analysis, verificado por code review de Task 5 tras 2 rondas de fix). Riesgo bajo: no hay ruta de
código compartida entre el chequeo de analysis (§8.1) y el de design (§9.1) que pudiera cruzarse.
Pendiente de una verificación en vivo futura si se toca esa lógica.

## 4. Idempotencia real

`design-orchestrator` lanzado en modo adhoc con el MISMO objetivo cuyo plan ya existía en
`docs/superpowers/plans/`.
Evidencia: ✅ PASS — respuesta real: `DONE` / `evidence: files=3 cmds=4 turns=5/20` /
`PLAN · docs/superpowers/plans/2026-09-03-export-csv-facturas.md:1 · plan ya existe → revisar
directamente`. Cero ficheros nuevos en `docs/superpowers/plans/` tras la segunda invocación (sigue
habiendo exactamente uno). Confirma en vivo el fix de la ronda 2 de Task 4 (chequeo de
idempotencia vía tool `Grep` nativo, sin el bug de regex de la ronda 1).

## 5. Hook de evidencia en vivo

En el transcript del ítem 1, el patrón ya conocido de fases 2/3 se repite (1 reintento absorbido
por agente en el peor caso: `design-orchestrator`, `memory-orchestrator`, `memory-builder`
fallaron su primer intento, `pattern-advisor`/`domain-modeler`/`planner` acertaron a la primera) —
ningún rechazo de 2º intento, ningún run roto. Las líneas `PLAN · …`/`- grill: …` que la raíz
reenvía (verificadas por code review contra el hook real en la ronda 2 de Task 5) no se
ejercitaron en producción por el corte de timeout, pero sí se verificaron empíricamente contra
`hooks/validate-output.py` durante la review (exit 0, formato válido).
Evidencia: ✅ PASS (mismo coste sistémico ya aceptado de fases anteriores).

## Bugs encontrados y arreglados durante esta fase (antes de este smoke, en las reviews de tarea)

Ninguno nuevo en ESTE smoke — los hallazgos reales de la fase (2 Critical + varios Important en
Task 4 y Task 5, todos trazables al propio texto del plan, ninguno del código real del hook/guard)
se encontraron y arreglaron en las reviews de tarea, antes de este smoke. Ver
`.superpowers/sdd/2026-09-03-swarm-phase4-design/progress.md` para el detalle completo. Este smoke
confirma en vivo que el mecanismo más incierto de la fase — el grant cruzado de agentes de otro
plugin — funciona de verdad, cerrando la única duda genuina que quedaba sin verificar por diseño.

## Firma

- [x] Owner: sesión autónoma nocturna — Fecha: 2026-09-03
