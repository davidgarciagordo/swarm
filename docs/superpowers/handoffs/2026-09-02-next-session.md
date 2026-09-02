# Handoff — swarm, 2026-09-02 (fases 1 + 1b + 2 cerradas)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí — toca decidir/empezar la fase 3 (analysis-orchestrator, spec §15). Modo de
> trabajo: brainstorming corto si hace falta cerrar algo del diseño → `writing-plans` →
> Subagent-Driven Development (superpowers), commit por tarea, review adversarial por tarea + review
> final de rama antes de merge, checklist de smoke ejecutado EN VIVO (no solo escrito) antes de dar
> una fase por cerrada — así se han encontrado y arreglado 6 bugs reales en total (2 en fase 1, 1 en
> fase 1b, 3 en fase 2) que ninguna review individual pilló sola. David quiere avisos cuando cierre
> cada fase, no antes. Cada task/fix termina en commit con SU identidad git personal
> (`garcia.gordo.david@gmail.com`, no Classlife).

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún,
  rama `master`, sin ramas de trabajo abiertas — **excepto** `worktree-phase2-discovery`, ver nota
  de limpieza pendiente abajo).
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Fase 1 (núcleo) — completa y mergeada.** 13 tareas + review final + smoke en vivo. 2 bugs
  Critical: payload real de `SubagentStop` es `last_assistant_message` (no `output`);
  `memory-orchestrator` sin tool `Agent` para lanzar hojas (solo tenía `SendMessage`).
- **Fase 1b (dominio requirements) — completa y mergeada.** 5 tareas + review final + smoke en
  vivo. 1 bug: `bash-guard.py` no normalizaba rutas absolutas ya resueltas fuera de `mem-*.sh`.
- **Fase 2 (dominio discovery) — completa y mergeada (2026-09-02, fast-forward `42d6213..6f25335`).**
  7 tareas + 3 rondas de fix en T6 (root integration) + smoke test EN VIVO con el owner (sesión
  interactiva real, no `claude -p` — necesario porque `AskUserQuestion` no se puede simular headless)
  + review final de rama (Opus) + fix de 4 hallazgos importantes (I1-I4) + verificación acotada de
  esos 3 commits finales antes de mergear. **3 bugs reales encontrados y arreglados en el smoke/review,
  ninguno detectado por las reviews de tarea individuales:**
  1. **HIGH seguridad** — `feasibility-spiker.md` mentía ("el worktree se descarta solo"); la
     plataforma solo auto-limpia un worktree SIN cambios y el spike siempre escribe → fuga real
     confirmada (worktree huérfano con código sin commitear). Fix: `discovery-orchestrator` anota el
     `agentId` del spawn y hace `git worktree remove --force` tras DONE/BLOCKED del spiker, y
     también tras timeout/sin-respuesta (fix I3 de la review final).
  2. **HIGH pérdida de datos** — las 4 hojas escribían con `--file discovery` literal (no
     run-scoped): un segundo run pisaba/perdía en silencio los hallazgos del primero (colisión de
     dedup key entre runs distintos). Fix: `--file "discovery-${RUN:-adhoc}"`.
  3. **Sistémico no bloqueante** — los 6 agentes del primer run real fallaron su primer intento del
     hook de evidencia (4 por escribir una frase antes del veredicto, 2 por narración suelta tras un
     hallazgo) — el reintento diseñado lo absorbió, pero costaba 1 turno extra por agente siempre.
     Fix: párrafo "cero preámbulo" explícito en `skills/swarm-protocol/SKILL.md` §4.
  4. **Casi-bug encontrado tras el smoke, antes de mergear (C1)** — un fix de robustez del hook
     (`4f390d1`, de una sesión paralela) añadió un cap de 120 chars contra narración disfrazada de
     hallazgo, pero eso rechazaba como falso positivo las líneas `-Q` LEGÍTIMAS de
     `discovery-orchestrator` (184-212 chars reales). Fix: exención estructural por regex de forma
     (`DISCOVERY_Q_RE`), no por prefijo `- `.
  5. **I1-I4 de la review final** (saneado shell hoisteado a SKILL.md §4.4 para las 4 hojas +
     ambos orquestadores; `summary` antes de cada `curate` en los 6 caminos terminales de
     `orchestrator.md`; limpieza de worktree también en el camino de timeout; batch vacío `DONE`
     tratado como `BLOCKED` explícito) — verificados limpios por una review acotada independiente
     antes de mergear (sin bugs nuevos, primera vez en toda la rama que una ronda de fix de
     `orchestrator.md` no regresa nada).
- Todo en `master`: **22 archivos de test, 22/22 en verde** (`bash tests/run.sh`), confirmado en
  `PATH` normal y en `PATH=/usr/bin:/bin:$PATH` (entorno grep mínimo).
- Agentes vivos: `swarm:orchestrator` (raíz), `swarm:memory-orchestrator`/`memory-builder`/
  `memory-curator` (dominio memory), `swarm:requirements-orchestrator`/`env-checker` (dominio
  requirements), `swarm:discovery-orchestrator`/`value-critic`/`options-generator`/
  `research-analyst`/`feasibility-spiker` (dominio discovery). Comandos: `/swarm:init`, `/swarm:run`,
  `/swarm:doctor`.

## Limpieza pendiente (no urgente, no bloquea fase 3)

El worktree `.claude/worktrees/phase2-discovery` (rama `worktree-phase2-discovery`, ya mergeada
fast-forward a `master`) sigue registrado porque estaba **bloqueado por una sesión Claude viva
corriendo dentro de él** en el momento del merge (no se puede borrar el propio cwd activo). Cuando
esa sesión termine: desde el repo principal,
`git worktree remove .claude/worktrees/phase2-discovery && git branch -d worktree-phase2-discovery`.
Verificar antes con `git worktree list -v` que ya no aparece `locked`.

## Lección aplicada tres veces ya (aplícala en cada fase nueva)

Todo orquestador de dominio que lance una hoja que NO preexiste necesita `Agent(<hoja1>,<hoja2>,…)`
en su `tools:` — nunca solo `SendMessage`, que solo alcanza agentes ya vivos (roster de hermanos =
snapshot al lanzar). Cada agente nuevo que lance hijos: escribe un test de regresión que haga `grep`
del `tools:` del frontmatter buscando el `Agent(...)` correcto (patrón en
`tests/test_discovery_orchestrator_spawns.sh`).

## Otra lección de fase 2, aplícala en cada fase nueva

El hábito por defecto de un modelo es cerrar su turno con una frase de cortesía o narración antes
del veredicto — le gana a la instrucción de formato en el primer intento, para cualquier
modelo/agente (confirmado: 6/6 agentes fallaron su primer intento en el primer run real). No lo
arregles por agente: el párrafo "cero preámbulo, el ÚLTIMO mensaje empieza literal en el veredicto"
va en el contrato compartido (`skills/swarm-protocol/SKILL.md` §4), preloadeado por todo `swarm:*`.

## Lo que NO se toca ni se construye todavía

`dependency-auditor`/`dependency-installer` (spec §7) son fase 5 — cero código, solo prosa en
`agents/requirements-orchestrator.md`. `/swarm:status`/`/swarm:findings` son fase 6.
`analysis-orchestrator`, `design-orchestrator`, `implementation-orchestrator`, `delivery-orchestrator`
son fases 3-6 (spec §15) — `agents/orchestrator.md` ya declara honestamente que no existen si el
objetivo los necesita.

## Backlog no bloqueante (de las reviews finales de fase 1, 1b y 2 — no urgente, atender cuando toque
el área correspondiente)

- `scripts/req-check.sh` no valida su entrada — inalcanzable hoy, requisito real para fase 5.
- `hooks/bash-guard.py`: no inspecciona `$(...)`/backticks DENTRO de los argumentos de un comando ya
  permitido cuando ese argumento va SIN comillas (con comillas sí lo cubre el saneado de §4.4/I1) —
  preexistente de fase 1, confirmado en fase 1b y 2. Hardening dedicado antes de dar más agentes con
  `Bash` a fases futuras.
- `hooks/bash-allowlist.json`: `pwd`/`echo` no están en ningún allowlist — no bloquea nada hoy.
- `is_mem_script` en `bash-guard.py` sigue haciendo match por basename+carpeta padre, más laxo que
  el match exacto ya viable — candidato a simplificar.
- Ítems 3 y 4-segunda-mitad del checklist de smoke de fase 2 (tier `light` en vivo; `--tier=light`+
  refactor → discovery omitido en vivo) quedaron verificados solo a nivel de código, no en vivo —
  se priorizó el tiempo del owner en los bugs reales de los ítems 2 y 7. Repetir si se toca esa
  lógica en una fase futura.

## Siguiente paso: fase 3 — analysis (spec §15)

Aún sin brainstorming/spec detallado más allá de lo que ya recoge `docs/superpowers/specs/2026-09-01-swarm-design.md`
§15. Empezar confirmando con el owner el alcance exacto de `analysis-orchestrator` y sus hojas antes
de `writing-plans` — mismo patrón que 1b y 2: (brainstorming corto si hace falta) → plan →
Subagent-Driven Development → smoke checklist en vivo → review final de rama → merge.

## Memoria persistente relevante

Buscar con mem-search si está disponible en esta sesión: convención de nombres estable (todo agente
lanzado = su rol), routing de modelos (Fable/Opus decide y revisa, Sonnet ejecuta planes cerrados),
identidad git personal (`garcia.gordo.david@gmail.com`, no la de Classlife), regla de saneado shell
compartida (`skills/swarm-protocol/SKILL.md` §4.4 — quita, nunca escapa, backtick/`$(`/comilla/backslash).
