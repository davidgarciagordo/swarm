# Handoff — swarm, 2026-09-03 (fases 1 + 1b + 2 + 3 + 4 + 5a cerradas, documentación de uso hecha)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí — toca decidir/empezar la fase 5b (stack pack `php-ddd-symfony8`) o 5c
> (`migration-engineer`/`doc-writer`/`dependency-auditor`/`dependency-installer`), spec §15. Modo de
> trabajo: brainstorming corto si hace falta cerrar algo del diseño → `writing-plans` → Subagent-Driven
> Development (superpowers), commit por tarea, review adversarial por tarea + review final de rama
> antes de merge, checklist de smoke ejecutado EN VIVO (no solo escrito) antes de dar una fase por
> cerrada — así se han encontrado y arreglado bugs reales en CADA fase (2 en fase 1, 1 en fase 1b, 3
> en fase 2, varios en fase 3, 7+ en fase 4, 1 Critical + 6 Important en la review final de fase 5a)
> que ninguna review individual pilló sola. David quiere avisos cuando cierre cada fase, no antes.
> Cada task/fix termina en commit con SU identidad git personal (`garcia.gordo.david@gmail.com`, no
> Classlife). **Merge siempre local a master** (instrucción permanente del owner, 2026-09-03) — no
> preguntar cada vez, no ofrecer PR salvo que lo pida explícitamente. **La pasada de documentación de
> uso completa que David pidió explícitamente ya está hecha** (`docs/USAGE.md`/`USAGE.es.md`,
> commit `21a1e6a`) — no hace falta repetirla, solo mantenerla al día si se añaden dominios/comandos
> nuevos.

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún,
  rama `master`, sin ramas de trabajo abiertas — **excepto** `worktree-phase2-discovery`, ver nota
  de limpieza pendiente abajo, sin cambiar desde hace 3 handoffs). `worktree-phase3-analysis`,
  `worktree-phase4-design` y `worktree-phase5a-implementation` ya se mergearon y se limpiaron
  (worktree borrado, rama borrada) — no quedan pendientes.
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Guía de uso completa: `docs/USAGE.md` / `docs/USAGE.es.md` (commit `21a1e6a`).** Instalación
  real, los 3 comandos con ejemplos reales sacados de los smoke checklists, cada dominio construido
  explicado en términos de usuario con ejemplo real, el contrato de veredicto universal explicado
  una vez. Los README solo apuntan a ella (una línea cada uno), no la duplican.
- **Fase 1 (núcleo) — completa y mergeada.** 13 tareas + review final + smoke en vivo. 2 bugs
  Critical: payload real de `SubagentStop` es `last_assistant_message` (no `output`);
  `memory-orchestrator` sin tool `Agent` para lanzar hojas (solo tenía `SendMessage`).
- **Fase 1b (dominio requirements) — completa y mergeada.** 5 tareas + review final + smoke en
  vivo. 1 bug: `bash-guard.py` no normalizaba rutas absolutas ya resueltas fuera de `mem-*.sh`.
- **Fase 2 (dominio discovery) — completa y mergeada (fast-forward `42d6213..6f25335`).** 7 tareas
  + 3 rondas de fix en T6 + smoke test EN VIVO con el owner (sesión interactiva real, `AskUserQuestion`
  no se simula headless) + review final + fix de 4 hallazgos importantes. 5 bugs reales, entre ellos
  un HIGH de seguridad (worktree huérfano del spike) y un HIGH de pérdida de datos (colisión de
  dedup entre runs).
- **Fase 3 (dominio analysis) — completa y mergeada (fast-forward `e870c54..dfad121`).**
  `analysis-orchestrator` + 6 hojas de juicio, excluyente con discovery en v1. Smoke headless
  completo. Review final: 6 Important + 4 Minor, arreglados y re-verificados limpios.
- **Fase 4 (dominio design) — completa y mergeada (fast-forward `f406955..2a6eb59`).**
  `design-orchestrator` (sonnet) + `planner` (opus, escribe planes reales con `Write`/`Edit`) +
  `pattern-advisor` + `domain-modeler`. Primera vez que el enjambre invoca agentes de OTRO plugin ya
  instalado (`working-methods:grill-architect/operator/engineer`), confirmado funcionando en un run
  real. Encadena tras discovery SOLO en `tier: full`.
- **Fase 5a (núcleo del dominio implementation) — completa y mergeada (merge commit `666fc4d`,
  2026-09-03).** Primera fase que escribe y fusiona código real. 4 hojas nuevas (`test-writer`,
  `implementer` con `isolation: worktree`, `quality-fixer`, `reviewer`) + `implementation-orchestrator`
  (primer orquestador del repo con `git merge`/`git worktree` de verdad). Ciclo TDD real:
  test-writer (RED, commit directo a la rama del run) → implementer (worktree aislado, GREEN, commit
  propio, marca `- [x] Step N` del plan) → quality-fixer (`--fix`) → reviewer (gate ANTES del merge,
  read-only puro) → `implementation-orchestrator` fusiona LOCAL (nunca a master/remoto, guardia real
  `git rev-parse --abbrev-ref HEAD` antes del `git merge`, nunca prosa sola) → limpieza del worktree
  en TODOS los caminos de salida (no solo el feliz). Decisión de seguridad explícita: **nunca
  encadena tras discovery/design, ni en `tier: full`** — checkpoint humano obligatorio antes de que
  el enjambre escriba/fusione código.
  - **Spike real ANTES de escribir el plan**: `isolation: worktree` NO auto-commitea (queda `??`
    hasta que el propio agente hace `git add`+`commit`), la rama es `worktree-agent-<agentId>`,
    mergeable con `git merge` normal desde el checkout principal — verificado con un
    `feasibility-spiker` adhoc real contra un fixture desechable, no adivinado.
  - **Smoke EN VIVO real**: ciclo completo de 5 agentes contra un VO `Money`, merge real confirmado
    (`git log --all`), limpieza de worktree confirmada en disco (`git worktree prune -v`, no solo
    confiando en la narración del propio agente coordinador, que dio un falso "sigue existiendo").
    2 mecanismos (gate Critical con fix-loop, guardia anti-master) verificados solo por trazado de
    código, no disparados en vivo — riesgo bajo, documentado honestamente en el checklist.
  - **Review final de rama (Opus, 13 commits): 1 Critical NUEVO** que ninguna review de tarea pilló
    — `cd` ausente del allowlist de `quality-fixer`/`reviewer`, sus propios comandos documentados
    (incluido `vendor/bin/php-cs-fixer`, tampoco allowlisted por nombre completo) eran `deny` en
    runtime, neutralizando en silencio el paso de calidad y degradando el gate pre-merge (falla
    cerrado, no es hueco de seguridad, pero sí regresión funcional real). + 6 Important: sin test
    para la guardia anti-master ni la limpieza de `implementation-orchestrator`; la raíz sin regla de
    enrutado que alcance §10 (un objetivo "implementa el plan de X" caía en cierre omitido); ruta de
    worktree documentada como absoluta pero escrita relativa, sin ancla de repo-root; sin manejo de
    `git merge` con conflicto real; sin cut-rule si `implementer` nunca responde; READMEs/SKILL.md
    seguían afirmando que implementation no existe (regresión real del propio merge de la fase).
  - **1 sola ronda de fix** (regla "no second fix wave") + **re-review Opus escopeada al diff del
    fix**, que verificó CADA hallazgo empíricamente (guard.py contra formas reales de comando, repo
    desechable con worktree real para C1/I4, mutation-testing de los 2 tests nuevos contra 11
    reversiones — 10/11 capturadas), con foco especial en confirmar que la nueva regla de enrutado
    (I2) NO abre ninguna vía implícita a §10 — la propiedad "nunca encadena" quedó intacta y
    reforzada. 3 Minor nuevos del propio fix, corregidos directamente sin agente (commit `fdc7061`).
- Todo en `master`: **36 archivos de test, 36/36 en verde** (`bash tests/run.sh`, verificado tras el
  merge, no solo antes).
- Agentes vivos: `swarm:orchestrator` (raíz), dominio memory (3), requirements (2), discovery (5),
  analysis (7), design (4 + 3 lentes grill externos), implementation (5: `test-writer`, `implementer`,
  `quality-fixer`, `reviewer`, `implementation-orchestrator`). Comandos: `/swarm:init`, `/swarm:run`,
  `/swarm:doctor`.

## Limpieza pendiente (no urgente, sin cambios desde hace 3 handoffs)

El worktree `.claude/worktrees/phase2-discovery` (rama `worktree-phase2-discovery`, ya mergeada
fast-forward a `master`) sigue registrado porque estaba **bloqueado por una sesión Claude viva
corriendo dentro de él** en el momento del merge (no se puede borrar el propio cwd activo). Cuando
esa sesión termine: desde el repo principal,
`git worktree remove .claude/worktrees/phase2-discovery && git branch -d worktree-phase2-discovery`.
Verificar antes con `git worktree list -v` que ya no aparece `locked`.

## Lección aplicada cinco veces ya (aplícala en cada fase nueva)

Todo orquestador de dominio que lance una hoja que NO preexiste necesita `Agent(<hoja1>,<hoja2>,…)`
en su `tools:` — nunca solo `SendMessage`. Fase 4 lo extendió a agentes de OTRO plugin ya instalado,
confirmado que el mismo mecanismo funciona igual para nombres cross-plugin.

## Lección de fase 2 (protocolo compartido, no repetir por agente)

El hábito por defecto de un modelo es cerrar su turno con una frase de cortesía o narración antes
del veredicto. Ya está resuelto en `skills/swarm-protocol/SKILL.md` §4 ("cero preámbulo").

## Lección de fase 4: contenido largo estructurado NUNCA por argumento de shell

`planner` e `implementer` son los únicos agentes del repo con `Write`/`Edit` — escriben directo, sin
pasar por `bash-guard.py`, cero riesgo de injection en contenido largo/con backticks/`$`.

## Lección de fase 5a, aplicada TRES veces ya en fases distintas (8.3→9.3→10.3): réplica manual de
## una exención de saneado se olvida si no se copia literal

La exención de saneado del §4.4 (turn-output) NUNCA cubre el `summary --line` que propaga un
veredicto BLOCKED/KO — cada dominio orquestador nuevo (analysis §8.3, design §9.3, implementation
§10.3) reintrodujo este mismo bug porque el párrafo de exención no se copió literal del dominio
anterior. **Para cualquier fase futura con orquestador nuevo: copiar literal el párrafo "Esa exención
NO cubre el `summary --line` del cierre" de la sección equivalente más reciente (§10.3 ahora mismo),
no reescribirlo de memoria.**

## Lección de fase 5a: un allowlist nunca probado contra los comandos reales del propio agente es
## un allowlist sin verificar

El bug Critical de la review final de fase 5a (`cd` denegado para `quality-fixer`/`reviewer`) existió
porque ninguna review de tarea ejecutó los comandos ```bash literales del cuerpo del agente contra
`hooks/bash-guard.py` — solo se leyó el allowlist y se asumió coherente. Fase 5a añadió
`tests/test_agent_bash_blocks_allowed.sh`, que extrae y prueba cada bloque ```bash de los 5 agentes
de implementation contra el guard real. **Para cualquier fase futura que añada agentes con Bash:
extender ese test (o su patrón) a los agentes nuevos — no confiar en lectura visual del allowlist.**

## Lección de fase 5a: limpieza de recursos mutables debe cubrir TODOS los caminos de salida, no solo
## el feliz — y necesita test dedicado, no solo prosa

El primer fix de Task 6 (worktree leak) y el patrón general: cualquier orquestador que cree un
recurso que hay que liberar (worktree, lock, proceso) necesita una sección de limpieza compartida
referenciada desde CADA camino terminal documentado, más un test que compruebe eso por conteo/orden
(mirar `tests/test_implementation_worktree_cleanup.sh` como plantilla) — no basta con prosa
afirmando "siempre limpio".

## Lo que NO se toca ni se construye todavía

`dependency-auditor`/`dependency-installer` (spec §7) — cero código, solo prosa en
`agents/requirements-orchestrator.md`, diferidos a fase 5c. `/swarm:status`/`/swarm:findings` son
fase 6. `migration-engineer`/`doc-writer` (dominio implementation, spec §7) y el stack pack
`php-ddd-symfony8` son fase 5b/5c. `delivery-orchestrator`/`release-manager`/`handoff-writer` (fase
6, el primer dominio con `git push` real) — `agents/orchestrator.md` ya declara honestamente que no
existen si el objetivo los necesita.

## Backlog no bloqueante (de las reviews finales de fases 1-5a — no urgente, atender cuando toque el
área correspondiente)

- `scripts/req-check.sh` no valida su entrada — inalcanzable hoy, requisito real para fase 5b/5c.
- `hooks/bash-guard.py`: no inspecciona `$(...)`/backticks DENTRO de argumentos sin comillas de un
  comando ya permitido (con comillas sí lo cubre el saneado de §4.4) — preexistente de fase 1,
  confirmado en fases 1b/2/3/5a. Hardening dedicado antes de dar más agentes con `Bash` a fases futuras.
- `hooks/bash-allowlist.json`: `pwd`/`echo` no están en ningún allowlist — no bloquea nada hoy.
- `is_mem_script` en `bash-guard.py` sigue haciendo match por basename+carpeta padre, más laxo que
  el match exacto ya viable — candidato a simplificar.
- Ítem 3 del checklist de smoke de fase 4 (exclusión design↔analysis) no se re-ejecutó en vivo —
  verificado solo por code review. Riesgo bajo, repetir si se toca esa lógica.
- Fase 5a: la guardia anti-`master` es una lista de 2 nombres (`master`/`main`) — `develop`/`trunk`/
  `release/*` no están cubiertos. Riesgo bajo (merge siempre local), `git rev-parse --abbrev-ref
  origin/HEAD` cubriría la rama por defecto real del repo con un comando más. Parcheable cuando se
  toque esa lógica de nuevo.
- Fase 5a: `git worktree remove` no borra la rama `worktree-agent-<agentId>` — se acumula una rama
  muerta por fase implementada. Candidato a un `git branch -d` tras merge exitoso, o documentar como
  intencional.
- `planner.md` apunta a un plan real de este mismo repo como ejemplo del grano de `- [ ] Step N` a
  replicar — dogfooding intencional (v1 asume que el plugin corre sobre ESTE repo), documentar si
  fase 5+ alguna vez distribuye el plugin a otro repo.

## Rulings arquitectónicos de fase 5a (resueltos por ruling propio, sesión con autonomía delegada —
revisar si algo no encaja, aunque ya están implementados)

1. **`implementation-orchestrator` nunca encadena, ni en `tier: full`** — a diferencia de analysis/
   design (que sí encadenan en `full`), este dominio SIEMPRE requiere invocación explícita del owner.
   Coste si está mal: ninguno operativo (más seguro que el spec exige), solo fricción de un paso
   manual extra por fase.
2. **`quality-fixer`/`reviewer` apuntan al worktree de `implementer` por ruta absoluta en el prompt,
   sin `isolation:` propia** — evita el coste de un segundo worktree por leaf cuando ya existe uno
   compartible. Coste si está mal: bajo, mismo patrón ya usado por los lentes grill de fase 4.
3. **El merge lo hace `implementation-orchestrator`, nunca `implementer`** — separa "quien escribe
   código" de "quien tiene poder de fusión", con la hoja de código en un worktree aislado sin
   `Agent` tool (jerarquía de 2 niveles, spec §3.2 regla 8). Coste si está mal: ninguno, es más
   restrictivo que el mínimo del spec.

## Siguiente paso: fase 5b o 5c (spec §7/§15)

Fase 5 se partió en sub-fases por tamaño (ruling de sesión anterior): **5a (hecha)** = núcleo TDD +
merge. Quedan:
- **5b: stack pack `php-ddd-symfony8`** (`skills/pack-php-ddd-symfony8/`) — convenciones/plantillas
  específicas de stack que `implementer`/`test-writer` consumen.
- **5c: `migration-engineer` + `doc-writer` + `dependency-auditor`/`dependency-installer`** (estos
  dos últimos diferidos desde fase 1b, dominio requirements).
Decidir el orden (5b antes de 5c, o viceversa) al empezar — ninguno depende estrictamente del otro,
pero `dependency-auditor`/`dependency-installer` llevan más tiempo esperando (desde fase 1b). Aún
sin brainstorming/spec detallado más allá de lo que ya recoge
`docs/superpowers/specs/2026-09-01-swarm-design.md` §7/§15. Mismo patrón que fases anteriores:
(brainstorming corto si hace falta) → plan → Subagent-Driven Development → smoke checklist en vivo
→ review final de rama → **fix wave único si hay hallazgos + re-review escopeada** (patrón que
salvó fase 5a de un bug Critical real) → merge local a master (sin preguntar, instrucción permanente
del owner).

Después de 5b/5c: **fase 6 (delivery)** — `delivery-orchestrator`/`release-manager`/`handoff-writer`,
primer dominio con `git push` real, diseño de seguridad aún más alto que el de implementation (esa
fase fusiona local; delivery publica). Esa es la última fase antes de poder declarar v1 estable.

## Memoria persistente relevante

Buscar con mem-search si está disponible en esta sesión: convención de nombres estable, routing de
modelos (Fable/Opus decide y revisa, Sonnet ejecuta planes cerrados), identidad git personal
(`garcia.gordo.david@gmail.com`), regla de saneado shell compartida (`skills/swarm-protocol/SKILL.md`
§4.4), la lección de fase 4 (contenido largo → `Write`/`Edit` nativo), y las 3 lecciones nuevas de
fase 5a arriba (réplica manual de exención de saneado, allowlist sin probar contra comandos reales,
limpieza de recursos en todos los caminos de salida).
