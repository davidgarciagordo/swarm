# Handoff — swarm, 2026-09-02

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` y continúa desde ahí. Modo de trabajo:
> Subagent-Driven Development (superpowers), commit por tarea, review adversarial por tarea +
> review final de rama antes de merge, checklist de smoke ejecutado en vivo (no solo escrito) antes
> de dar una fase por cerrada. David quiere avisos cuando cierre cada fase, no antes.

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún).
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Fase 1 (núcleo)**: completa, mergeada a `master`. 13 tareas + review final de rama + 2 bugs
  Critical reales encontrados y arreglados en vivo (uno en la propia review final, otro ejecutando
  el smoke checklist de verdad): el payload real de `SubagentStop` no es lo que se había asumido
  (`last_assistant_message`, no `output`), y `memory-orchestrator` no tenía el tool `Agent` para
  lanzar a `memory-builder`/`memory-curator` — solo `SendMessage`, que solo alcanza agentes ya
  vivos. Lección aplicada explícitamente en fase 1b.
- **Fase 1b (dominio requirements)**: EN VUELO, rama `phase1b-requirements` (sobre `master`).
  Plan: `docs/superpowers/plans/2026-09-02-swarm-phase1b-requirements.md`.
  Ledger: `.superpowers/sdd/2026-09-02-swarm-phase1b-requirements/progress.md` (gitignored, local).
  **Las 5 tareas del plan están completas y commiteadas** (`requirements.json`, `scripts/req-check.sh`,
  `agents/requirements-orchestrator.md` + `agents/env-checker.md`, `commands/doctor.md`, checklist
  de smoke escrito). 16/16 tests en verde.

## Lo que falta AHORA MISMO (bloqueante para cerrar fase 1b)

**Ejecutar el checklist de smoke en vivo** — `docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`
— NO basta con que exista, hay que correrlo de verdad (`claude -p "/swarm:doctor" --plugin-dir
/Users/davidgarciagordo/projects/multiagents --permission-mode bypassPermissions` contra un repo
fixture). Se empezó y se cortó por límite de cupo EXTERNO de la sesión anterior (no un bug del
plugin) a mitad del ítem 1. Antes del corte se vio, en la traza real del subagente
`requirements-orchestrator`:
- 2 fricciones menores no fatales: `pwd` y `echo "..." ` (dentro de un `||` de Bash) no están en
  el allowlist de `swarm:requirements-orchestrator` — el agente se adaptó solo usando `Read`/`cat`,
  sin bloquear el flujo. Backlog, no urgente: valorar añadir `pwd`/`echo` al `default` de
  `hooks/bash-allowlist.json` si se repite en más agentes.
- Confirmado correcto: lee `requirements.json` del PROPIO plugin (no del repo target) — es lo
  esperado, `/swarm:doctor` comprueba la máquina del operador.
- No llegó a confirmarse si `env-checker` se lanzó de verdad (con `Agent`, nombrado `env-checker`)
  antes del corte.

**Pasos**: reintentar ítem 1 de cero (repo fixture limpio, `/swarm:init` + `/swarm:doctor`),
confirmar `env-checker` se lanza con `Agent` (no `SendMessage`) y veredicto final `OK`; luego
ítems 2 (tool inventado → `BLOCKED` con hint) y 3 (env-checker no reimplementa el chequeo). Rellenar
el checklist con evidencia real (mismo patrón que `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`,
ya relleno como referencia de formato). Si aparece un bug real, arreglarlo, re-test, commit — igual
que se hizo en fase 1 (dos bugs reales de esa clase ya se encontraron así, no antes).

Tras el checklist en verde: **review final de la rama `phase1b-requirements` completa** (modelo más
capaz disponible, mismo patrón que fase 1 — dispatch con `superpowers:requesting-code-review`'s
plantilla, foco en deriva entre T1-T5 que ninguna review individual pudo ver), luego
`superpowers:finishing-a-development-branch` para decidir merge a `master` (David eligió "merge
local" la vez anterior, sin remoto configurado).

## Lo que NO se toca ni se construye todavía

`dependency-auditor` y `dependency-installer` (spec §7) son fase 5, no fase 1b — no existen en
ningún fichero, ni como stub. `requirements-orchestrator` solo dice en prosa que devuelve
`BLOCKED dependency-installer no implementado aún (fase 5)` si alguien pide instalar algo.

## Decisiones del owner pendientes de aplicar más adelante (no bloquean fase 1b)

- `/swarm:status` / `/swarm:findings` (dashboard de consola) son fase 6 — David confirmó explícitamente
  "seguimos el plan", no adelantar.
- Tras fase 1b: fase 2 discovery (`discovery-orchestrator` + 4 hojas), spec §15.

## Memoria persistente relevante

Memorias guardadas en la sesión anterior (buscar con mem-search si están disponibles en esta
sesión): convención de nombres estable (todo agente lanzado = su rol), routing de modelos
(Fable/Opus decide y revisa, Sonnet ejecuta planes cerrados), identidad git personal
(`garcia.gordo.david@gmail.com`, no la de Classlife).
