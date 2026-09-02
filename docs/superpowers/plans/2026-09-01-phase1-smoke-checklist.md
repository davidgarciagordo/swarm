# Checklist de smoke — Fase 1 núcleo (`swarm`)

Gate manual del owner. Ejecutar contra un repo fixture con:
`claude --plugin-dir /Users/davidgarciagordo/projects/multiagents`

Cada ítem lleva un campo **Evidencia:** para pegar la salida real — no marcar sin pegarla.

## 1. `/swarm:init`

```
/swarm:init
```
Se espera: `.swarm/` creado, `memory.json` con backend `files` requerido, `decisions.md` con
cabecera, bloque `.gitignore` marcado `# swarm`, health-gate en verde.
Evidencia:

## 2. `/swarm:run "audita memoria" --tier=light` — primera vez

Se espera: directorio de run creado bajo `.swarm/run/<uuid>/`, `context-pack.md` construido,
`summary.md` presente al cierre, `memory-orchestrator` lanzado NOMBRADO exactamente
`memory-orchestrator` (spec §4.5).
Evidencia:

## 3. `/swarm:run "audita memoria" --tier=light` — segunda vez, mismo repo sin cambios

Se espera: `memory-builder` NO reconstruye (staleness fresh) — valida de extremo a extremo el
smoke test 2 del spec (`query con pack presente responde sin invocar builder`).
Evidencia:

## 4. Visibilidad de hermanos + espejo de buzón

Lanza dos hojas de prueba nombradas en el mismo mensaje y haz que A mande `SendMessage` a B.
Anota si el roster de hermanos funcionó y si el espejo de mailbox también apareció en
`run/<id>/mailbox/B.md` (spec smoke tests 3 y 6, a nivel de ejecución real de agentes).
Evidencia:

## 5. Clasificación `direct`

```
/swarm:run "corrige un typo en el README"
```
Se espera: tier `direct`, la raíz responde ella misma, NINGÚN directorio de run nuevo creado bajo
`.swarm/run/` (spec smoke test 10).
Evidencia:

## 6. Objetivo vacío (guarda añadida en review de T12)

```
/swarm:run
```
Se espera: `BLOCKED objetivo vacío — describe qué quieres que haga el enjambre`, sin abrir run.
Evidencia:

## 7. `--tier` inválido (guarda añadida en review de T12)

```
/swarm:run "audita memoria" --tier=medium
```
Se espera: `BLOCKED --tier inválido: medium (usa direct, light o full)`, sin llamar a
`mem-manifest.sh open`.
Evidencia:

## 8. Invocación desde subdirectorio (fix P1 de T12)

Desde un subdirectorio del repo fixture (`cd packages/api` o equivalente), ejecutar:
```
/swarm:run "audita memoria" --tier=light
```
Se espera: el orquestador ancla a la raíz real del repo (`git rev-parse --show-toplevel`) antes del
health-gate — ni `BLOCKED falta /swarm:init` falso, ni un run abierto en un `.swarm/` suelto del
subdirectorio.
Evidencia:

## 9. Dirigirse a un agente por nombre (convención de nombres, decisión del owner)

Durante un run activo, comprobar que se puede pedir "avisa a memory-builder cuando termines" o
similar, y que el orquestador/usuario puede `SendMessage` a `memory-orchestrator` por ese nombre
exacto sin tener que descubrirlo.
Evidencia:

## Firma

- [ ] Owner: ________________  Fecha: ________________
