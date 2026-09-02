# Handoff — swarm, 2026-09-02 (fases 1 + 1b cerradas)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí — toca empezar la fase 2 (discovery). Modo de trabajo: brainstorming corto si
> hace falta cerrar algo del diseño → `writing-plans` → Subagent-Driven Development (superpowers),
> commit por tarea, review adversarial por tarea + review final de rama antes de merge, checklist de
> smoke ejecutado EN VIVO (no solo escrito) antes de dar una fase por cerrada — así se han encontrado
> y arreglado 3 bugs reales que ninguna review individual pilló. David quiere avisos cuando cierre
> cada fase, no antes.

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún,
  rama `master`, sin ramas de trabajo abiertas).
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Fase 1 (núcleo) — completa y mergeada.** 13 tareas + review final de rama + checklist de smoke
  en vivo. 2 bugs Critical reales encontrados y arreglados: el payload real de `SubagentStop` no es
  lo que se había asumido (`last_assistant_message`, no `output`), y `memory-orchestrator` no tenía
  el tool `Agent` para lanzar a `memory-builder`/`memory-curator` (solo `SendMessage`, que solo
  alcanza agentes ya vivos).
- **Fase 1b (dominio requirements) — completa y mergeada.** 5 tareas + review final de rama +
  checklist de smoke en vivo. 1 bug real encontrado y arreglado: `hooks/bash-guard.py` normalizaba
  solo la forma `${CLAUDE_PLUGIN_ROOT}/` de ruta, no una ruta absoluta ya resuelta — cualquier
  script fuera de la familia `mem-*.sh` (como el nuevo `req-check.sh`) quedaba denegado al
  invocarse con ruta absoluta. Generalizado para cualquier script futuro.
- Todo en `master`: 16 archivos de test, 16/16 en verde (`bash tests/run.sh`).
- Agentes vivos: `swarm:orchestrator` (raíz), `swarm:memory-orchestrator`/`memory-builder`/
  `memory-curator` (dominio memory), `swarm:requirements-orchestrator`/`env-checker` (dominio
  requirements). Comandos: `/swarm:init`, `/swarm:run`, `/swarm:doctor`.

## Lección aplicada dos veces ya (aplícala en cada fase nueva)

Todo orquestador de dominio que lance una hoja que NO preexiste necesita `Agent(<hoja>)` en su
`tools:` — nunca solo `SendMessage`, que solo alcanza agentes ya vivos. Cada agente nuevo que
lance hijos: escribe un test de regresión que haga `grep` del `tools:` del frontmatter buscando el
`Agent(...)` correcto (patrón ya usado en `tests/test_requirements_orchestrator_spawns.sh`).

## Lo que NO se toca ni se construye todavía

`dependency-auditor`/`dependency-installer` (spec §7) son fase 5 — cero código, solo prosa en
`agents/requirements-orchestrator.md` diciendo `BLOCKED dependency-installer no implementado aún
(fase 5)`. `/swarm:status`/`/swarm:findings` son fase 6.

## Backlog no bloqueante (de las reviews finales de fase 1 y 1b — no urgente, atender cuando toque
el área correspondiente)

- `scripts/req-check.sh` no valida su entrada — un `requirements.json` malformado da un traceback
  crudo con exit 1 (mismo código que "falta un tool requerido", ambiguo). Inalcanzable hoy (nadie
  le pasa un fichero raro todavía); es requisito real para fase 5 cuando los packs traigan su
  propio `requirements.json`. Arreglar: reservar exit 64 para fichero malformado + informe JSON de
  error, antes de que fase 5 empiece a construir sobre esto.
- `hooks/bash-guard.py`: no inspecciona `$(...)`/backticks DENTRO de los argumentos de un comando
  ya permitido (solo la primera palabra del segmento se valida) — preexistente de fase 1, no
  introducido por fase 1b, confirmado en la review final de 1b. Vale la pena una tarea de
  hardening dedicada antes de dar más agentes con `Bash` a fases futuras.
- `hooks/bash-allowlist.json`: `pwd`/`echo` no están en ningún allowlist — agentes se adaptan solos
  usando `Read`/`cat`, no bloquea nada, pero si se repite en más agentes valorar añadirlos al
  `default`.
- `is_mem_script` en `bash-guard.py` sigue haciendo match por basename+carpeta padre (`mem-*.sh`
  bajo cualquier `scripts/`), más laxo que el match exacto que ahora es viable tras el fix de fase
  1b — candidato a simplificar/retirar ese fallback especial.

## Siguiente paso: fase 2 — discovery (spec §15)

`discovery-orchestrator` (sonnet) + 4 hojas: `value-critic` (opus), `research-analyst` (sonnet,
background), `options-generator` (opus), `feasibility-spiker` (sonnet, background). Restricción
clave (spec §3.2 regla 7): ningún subagente puede preguntar al owner directamente — discovery
devuelve UN batch de preguntas+opciones y la RAÍZ lo presenta con `AskUserQuestion`. Empezar con
`superpowers:writing-plans` sobre spec §7 "Discovery" (ya bastante detallado, no debería hacer
falta brainstorming largo) — mismo patrón que 1b: plan → Subagent-Driven Development → smoke
checklist en vivo → review final de rama → merge.

## Memoria persistente relevante

Buscar con mem-search si está disponible en esta sesión: convención de nombres estable (todo
agente lanzado = su rol), routing de modelos (Fable/Opus decide y revisa, Sonnet ejecuta planes
cerrados), identidad git personal (`garcia.gordo.david@gmail.com`, no la de Classlife).
