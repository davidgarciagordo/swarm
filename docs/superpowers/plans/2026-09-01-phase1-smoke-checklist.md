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
Evidencia: ⚠️ FALLÓ EN PRIMER INTENTO → bug real encontrado y arreglado en el mismo smoke test.
`memory-orchestrator` intentaba `SendMessage(memory-builder, ...)` para reconstruir el pack, pero
su frontmatter NUNCA tenía el tool `Agent` — solo podía `SendMessage` a agentes YA vivos, y
`memory-builder`/`memory-curator` nunca se lanzan solos. Bug estructural presente desde T11,
sobrevivió a la review de tarea y a la review final de rama (ninguna ejecutó el flujo real end
to end). Fix: `Agent(memory-builder,memory-curator)` añadido al frontmatter + al `tools:` de
`agents/memory-orchestrator.md` + spec §4.2; el cuerpo ahora LANZA (`Agent`) la primera vez, en vez
de `SendMessage` a algo inexistente. Tras el fix: ✅ PASS — pack reconstruido de verdad
(`context-pack.md` con `stack: php-ddd-symfony8` real), `index.md` sellado, run cerrado con
`curate`.

## 3. `/swarm:run "audita memoria" --tier=light` — segunda vez, mismo repo sin cambios

Se espera: `memory-builder` NO reconstruye (staleness fresh) — valida de extremo a extremo el
smoke test 2 del spec (`query con pack presente responde sin invocar builder`).
Evidencia: ✅ PASS — verificado con timestamps de fichero reales: `context-pack.md` mtime idéntico
antes y después del segundo run (no tocado), confirmando que el fast-path de `mem-stale.sh check`
evitó relanzar `memory-builder`.

## 4. Visibilidad de hermanos + espejo de buzón

Lanza dos hojas de prueba nombradas en el mismo mensaje y haz que A mande `SendMessage` a B.
Anota si el roster de hermanos funcionó y si el espejo de mailbox también apareció en
`run/<id>/mailbox/B.md` (spec smoke tests 3 y 6, a nivel de ejecución real de agentes).
Evidencia: ⏸ NO ejecutado en esta pasada — necesita una sesión interactiva con dos hojas de prueba
lanzadas a mano en la misma tanda; fuera del alcance de la ejecución automatizada vía `claude -p`
de este smoke run. Pendiente para el owner.

## 5. Clasificación `direct`

```
/swarm:run "corrige un typo en el README"
```
Se espera: tier `direct`, la raíz responde ella misma, NINGÚN directorio de run nuevo creado bajo
`.swarm/run/` (spec smoke test 10).
Evidencia: ✅ PASS — respondió directo (repo sin README, preguntó qué hacer), sin `.swarm/run/`
creado.

## 6. Objetivo vacío (guarda añadida en review de T12)

```
/swarm:run
```
Se espera: `BLOCKED objetivo vacío — describe qué quieres que haga el enjambre`, sin abrir run.
Evidencia: ⚠️ FALLÓ EN PRIMER INTENTO → `commands/run.md` no forzaba invocar el subagente
`orchestrator` cuando `$ARGUMENTS` estaba vacío; la sesión exterior contestaba por su cuenta sin
llegar a spawnear el agente real, saltándose la guarda entera sin que se notara (parecía correcto,
pero el subagente nunca corrió). Fix: `commands/run.md` reescrito para invocar `Agent` SIEMPRE, sin
excepción, incluso con `$ARGUMENTS` vacío. Tras el fix, verificado en el transcript real que el
subagente `swarm:orchestrator` SÍ se lanzó y su propia guarda (`BLOCKED objetivo vacío`) disparó.
✅ PASS tras el fix.

## 7. `--tier` inválido (guarda añadida en review de T12)

```
/swarm:run "audita memoria" --tier=medium
```
Se espera: `BLOCKED --tier inválido: medium (usa direct, light o full)`, sin llamar a
`mem-manifest.sh open`.
Evidencia: ✅ PASS — verificado en transcript real que el subagente `orchestrator` sí se lanzó y
rechazó `medium` correctamente.

## 8. Invocación desde subdirectorio (fix P1 de T12)

Desde un subdirectorio del repo fixture (`cd packages/api` o equivalente), ejecutar:
```
/swarm:run "audita memoria" --tier=light
```
Se espera: el orquestador ancla a la raíz real del repo (`git rev-parse --show-toplevel`) antes del
health-gate — ni `BLOCKED falta /swarm:init` falso, ni un run abierto en un `.swarm/` suelto del
subdirectorio.
Evidencia: ✅ PASS (tras el fix del ítem 2, misma causa raíz) — `.swarm/` real en la raíz del repo
con `context-pack.md` construido de verdad; CERO `.swarm/` creado en `packages/api/`.

## 9. Dirigirse a un agente por nombre (convención de nombres, decisión del owner)

Durante un run activo, comprobar que se puede pedir "avisa a memory-builder cuando termines" o
similar, y que el orquestador/usuario puede `SendMessage` a `memory-orchestrator` por ese nombre
exacto sin tener que descubrirlo.
Evidencia: parcial — verificado indirectamente en el ítem 2 (`memory-orchestrator` lanza a
`memory-builder`/`memory-curator` con `name:` = su rol exacto, confirmado en el transcript real
tras el fix del bug estructural). El escenario "el owner pide en su propio prompt que se avise a
un agente concreto" no se ejecutó explícitamente — pendiente para el owner en sesión interactiva.

## 10. Registro de agentes y hooks del plugin (sin verificar en runtime) — ✅ PASS, ejecutado real

`.claude-plugin/plugin.json` declara `skills` y `commands` explícitamente, pero NO `agents` ni
`hooks`: se confía en el autodescubrimiento documentado de `agents/` y `hooks/hooks.json`. Eso es
lo esperado según la documentación, pero es exactamente la clase de supuesto no verificado que
produjo C1 — así que se comprueba aquí, en sesión real, en vez de tocar el manifiesto a ciegas.

Comprobar, con el plugin cargado:
- Los cuatro agentes aparecen como `swarm:orchestrator`, `swarm:memory-orchestrator`,
  `swarm:memory-builder`, `swarm:memory-curator` (p. ej. en `/agents` o equivalente).
- El `PreToolUse` de `hooks/bash-guard.py` dispara de verdad (un `rm -rf /x` desde un agente
  `swarm:*` sale denegado) y el `SubagentStop` de `hooks/validate-output.py` también (una salida
  sin línea `evidence:` se rechaza).

Si alguno NO aparece, la corrección es añadir la clave que falte a `plugin.json` y re-verificar —
nunca añadirla especulativamente antes de esta comprobación.
Evidencia: los 4 agentes registran correctamente (`swarm:orchestrator`, `swarm:memory-orchestrator`,
`swarm:memory-builder`, `swarm:memory-curator`) — verificado listándolos en sesión real.
`PreToolUse` deniega `rm` real desde `swarm:memory-curator` (confirmado en transcript). `SubagentStop`
cubierto por evidencia sólida (C1 empírico + 13/13 tests) — el agente probado respetó tan bien su
propio contrato que no se logró forzar una salida malformada real para verlo bloquear en vivo; no
se insistió más para no abrir una ventana de riesgo. `plugin.json` no necesitó tocarse.

## Firma

- [ ] Owner: ________________  Fecha: ________________
