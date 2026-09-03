# Handoff — swarm, 2026-09-03 (fases 1 + 1b + 2 + 3 + 4 cerradas)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí — toca decidir/empezar la fase 5 (implementation-orchestrator + primer stack
> pack `php-ddd-symfony8`, spec §15). Modo de trabajo: brainstorming corto si hace falta cerrar algo
> del diseño → `writing-plans` → Subagent-Driven Development (superpowers), commit por tarea, review
> adversarial por tarea + review final de rama antes de merge, checklist de smoke ejecutado EN VIVO
> (no solo escrito) antes de dar una fase por cerrada — así se han encontrado y arreglado bugs reales
> en CADA fase (2 en fase 1, 1 en fase 1b, 3 en fase 2, varios en fase 3, 7+ en fase 4) que ninguna
> review individual pilló sola. David quiere avisos cuando cierre cada fase, no antes. Cada task/fix
> termina en commit con SU identidad git personal (`garcia.gordo.david@gmail.com`, no Classlife).
> **Merge siempre local a master** (instrucción permanente del owner, 2026-09-03) — no preguntar cada
> vez, no ofrecer PR salvo que lo pida explícitamente. **Pendiente crítico antes de v1 estable: una
> pasada de documentación de uso completa** (ver sección propia más abajo) — el owner lo pidió
> explícitamente y sigue sin hacerse tras 2 fases.

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún,
  rama `master`, sin ramas de trabajo abiertas — **excepto** `worktree-phase2-discovery`, ver nota
  de limpieza pendiente abajo). `worktree-phase3-analysis` y `worktree-phase4-design` ya se
  mergearon y se limpiaron (worktree borrado, rama borrada) — no quedan pendientes.
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Fase 1 (núcleo) — completa y mergeada.** 13 tareas + review final + smoke en vivo. 2 bugs
  Critical: payload real de `SubagentStop` es `last_assistant_message` (no `output`);
  `memory-orchestrator` sin tool `Agent` para lanzar hojas (solo tenía `SendMessage`).
- **Fase 1b (dominio requirements) — completa y mergeada.** 5 tareas + review final + smoke en
  vivo. 1 bug: `bash-guard.py` no normalizaba rutas absolutas ya resueltas fuera de `mem-*.sh`.
- **Fase 2 (dominio discovery) — completa y mergeada (fast-forward `42d6213..6f25335`).** 7 tareas
  + 3 rondas de fix en T6 + smoke test EN VIVO con el owner (sesión interactiva real, `AskUserQuestion`
  no se simula headless) + review final + fix de 4 hallazgos importantes. 5 bugs reales, entre ellos
  un HIGH de seguridad (worktree huérfano del spike) y un HIGH de pérdida de datos (colisión de
  dedup entre runs). Detalle completo: `git log` de la rama ya mergeada, o memoria persistente.
- **Fase 3 (dominio analysis) — completa y mergeada (fast-forward `e870c54..dfad121`).**
  `analysis-orchestrator` + 6 hojas de juicio, excluyente con discovery en v1. Smoke headless
  completo (analysis no usa `AskUserQuestion`). Review final: 6 Important + 4 Minor, arreglados y
  re-verificados limpios (10/10).
- **Fase 4 (dominio design) — completa y mergeada (2026-09-03, fast-forward `f406955..2a6eb59`).**
  `design-orchestrator` (sonnet) + `planner` (opus, ÚNICA hoja de todo el repo con `Write`/`Edit` —
  escribe planes reales en `docs/superpowers/plans/`) + `pattern-advisor` + `domain-modeler`
  (read-only, como el resto). **Primera vez que el enjambre invoca agentes de OTRO plugin ya
  instalado** (`working-methods:grill-architect/operator/engineer`, 3 lentes adversarias) — el
  grant cruzado `Agent(working-methods:...)` desde el `tools:` de un subagente nunca se había
  probado antes de esta fase; **confirmado funcionando en un run real** (ver smoke). Encadena tras
  discovery SOLO en `tier: full` (decisión: spec §9.1 dice `light` = "un solo dominio", así que
  nunca encadena ahí — mismo criterio ya aplicado a analysis en fase 3).
  - **Smoke EN VIVO, headless, con evidencia real fuerte**: se sembró una decisión ya cerrada en
    `decisions.md` para simular el camino "ya cerró" de discovery, y se corrió un `--tier=full`
    real. La cadena completa funcionó: discovery se saltó correctamente, `design-orchestrator`
    lanzó `pattern-advisor`+`domain-modeler`, `planner` escribió un plan REAL de 154 líneas citando
    el bug de inyección SQL del propio fixture, **los 3 lentes grill corrieron de verdad y
    devolvieron hallazgos P1 sustanciosos** (BOM UTF-8 para Excel, truncado de streaming tras
    headers 200, incoherencia bounded-context), y `design-orchestrator` arbitró correctamente
    relanzando `planner` con `operation: revise`. El run se cortó por el timeout de 600s de la
    propia herramienta de test (`claude -p`), NO por un bug — el plan quedó íntegro en disco, sin
    corromper nada a medio editar. Idempotencia verificada aparte en modo adhoc: `DONE · plan ya
    existe`, sin duplicar el fichero.
  - **Review final (Opus): 0 Critical, 7 Important, varios Minor + 3 preguntas arquitectónicas**
    (marcadas para el owner, resueltas por ruling propio dado que la sesión tenía autonomía
    delegada — ver "Rulings arquitectónicos" abajo). Arreglados en una tanda (commit `9c29873`).
  - **Re-review de esa tanda encontró: 1 fix en el lugar equivocado** (una sección de "documentación
    pendiente" se coló DENTRO de README.md/README.es.md — nota interna de proceso en la portada
    pública del plugin, duplicando lo que ya estaba correctamente en el ledger interno) **+ una
    contradicción nueva entre dos de los propios fixes de esa tanda** (detección de convención de
    repo target vs. la ruta fija que la idempotencia ya grepea) **+ varios Minor saltados sin
    avisar** (assert case-sensitive que forzaba prosa en minúsculas, wording "sin Bash" en un
    agente que sí tiene Bash, sin cap explícito de rondas de `revise`, sin test para la marca
    `**Grill:** pendiente/arbitrado` — el mecanismo más sutil de la fase). Sin segunda ronda de
    agente (regla del proceso para review final): arreglado directamente por el controlador,
    commit `2a6eb59`. Suite final: 30/30.
- Todo en `master`: **30 archivos de test, 30/30 en verde** (`bash tests/run.sh`).
- Agentes vivos: `swarm:orchestrator` (raíz), dominio memory (3 agentes), dominio requirements (2),
  dominio discovery (5), dominio analysis (7), dominio design (`design-orchestrator`/`planner`/
  `pattern-advisor`/`domain-modeler`, 4 — más los 3 lentes grill externos que invoca). Comandos:
  `/swarm:init`, `/swarm:run`, `/swarm:doctor`.

## ⚠️ PENDIENTE CRÍTICO: pasada de documentación de uso completa

David lo pidió EXPLÍCITAMENTE durante la sesión de fase 4 ("recuerda incluir documentación completa
de que es y como se usa") y sigue sin hacerse — la fase 4 solo corrigió la precisión
"construido/planeado" del README (qué dominios existen), NO añadió una guía de uso real. Falta:
- Qué es el plugin, en 2-3 frases claras para alguien que nunca lo ha visto.
- Cómo se instala (`--plugin-dir`, o el mecanismo real de instalación de plugins de Claude Code).
- Cada comando (`/swarm:init`, `/swarm:run`, `/swarm:doctor`) con un ejemplo real de invocación y
  qué esperar como salida — no solo la firma, el flujo completo.
- Cada dominio explicado en términos de usuario (qué hace, cuándo se dispara, qué se recibe) con al
  menos un ejemplo real de objetivo que lo dispare — los ejemplos reales de los smoke checklists de
  fases 2/3/4 son una buena fuente (objetivos reales, salidas reales, ya verificados en vivo).
Hacerlo ANTES de declarar v1 estable — es un requisito explícito del owner, no opcional. Buen
momento: al cierre de fase 5 o 6, cuando el roster esté más completo, pero no más tarde que eso.

## Limpieza pendiente (no urgente, no bloquea fase 5)

El worktree `.claude/worktrees/phase2-discovery` (rama `worktree-phase2-discovery`, ya mergeada
fast-forward a `master`) sigue registrado porque estaba **bloqueado por una sesión Claude viva
corriendo dentro de él** en el momento del merge (no se puede borrar el propio cwd activo). Cuando
esa sesión termine: desde el repo principal,
`git worktree remove .claude/worktrees/phase2-discovery && git branch -d worktree-phase2-discovery`.
Verificar antes con `git worktree list -v` que ya no aparece `locked`.

## Lección aplicada cuatro veces ya (aplícala en cada fase nueva)

Todo orquestador de dominio que lance una hoja que NO preexiste necesita `Agent(<hoja1>,<hoja2>,…)`
en su `tools:` — nunca solo `SendMessage`. Fase 4 lo extendió a un caso nuevo: **también aplica a
agentes de OTRO plugin ya instalado** (`Agent(working-methods:grill-architect,...)`) — confirmado
que el mismo mecanismo funciona igual para nombres cross-plugin, no solo `swarm:*`.

## Otra lección de fase 2, aplícala en cada fase nueva

El hábito por defecto de un modelo es cerrar su turno con una frase de cortesía o narración antes
del veredicto. Ya está resuelto en el contrato compartido (`skills/swarm-protocol/SKILL.md` §4,
"cero preámbulo") — no lo re-arregles por agente.

## Lección de fase 4: contenido largo estructurado NUNCA por argumento de shell

`planner` es el único agente de todo el repo que produce un artefacto de verdad (un plan de varias
KB con código, backticks, `$`). Escribirlo vía `mem-files.sh write --text "..."` habría repetido
(mucho peor, por el volumen) el mismo riesgo de injection que C1/I1 de fases anteriores, y el
saneado por strip lo habría destrozado (arrancaría cada backtick/`$` del propio contenido técnico).
Solución: usar el tool `Write` nativo (no pasa por `bash-guard.py`, cero riesgo de shell). Si una
fase futura necesita que un agente produzca contenido largo y estructurado, replica este patrón —
`Write`/`Edit` directo, nunca un argumento de shell — en vez de reinventar el saneado.

## Lo que NO se toca ni se construye todavía

`dependency-auditor`/`dependency-installer` (spec §7) son fase 5 — cero código, solo prosa en
`agents/requirements-orchestrator.md`. `/swarm:status`/`/swarm:findings` son fase 6.
`implementation-orchestrator` y `delivery-orchestrator` son fases 5-6 (spec §15) —
`agents/orchestrator.md` ya declara honestamente que no existen si el objetivo los necesita.
`design-orchestrator` ya NO está en esta lista: fase 4 lo construyó (ver arriba).

## Backlog no bloqueante (de las reviews finales de fases 1-4 — no urgente, atender cuando toque el
área correspondiente)

- `scripts/req-check.sh` no valida su entrada — inalcanzable hoy, requisito real para fase 5.
- `hooks/bash-guard.py`: no inspecciona `$(...)`/backticks DENTRO de argumentos sin comillas de un
  comando ya permitido (con comillas sí lo cubre el saneado de §4.4) — preexistente de fase 1,
  confirmado en fases 1b/2/3. Hardening dedicado antes de dar más agentes con `Bash` a fases futuras.
- `hooks/bash-allowlist.json`: `pwd`/`echo` no están en ningún allowlist — no bloquea nada hoy.
- `is_mem_script` en `bash-guard.py` sigue haciendo match por basename+carpeta padre, más laxo que
  el match exacto ya viable — candidato a simplificar.
- Ítem 3 del checklist de smoke de fase 4 (exclusión design↔analysis) no se re-ejecutó en vivo —
  verificado solo por code review tras 2 rondas de fix en Task 5. Riesgo bajo (sin ruta de código
  compartida entre los chequeos de §8.1/§9.1), pero repetir si se toca esa lógica.
- `planner.md` apunta al propio plan de fase 4 (`docs/superpowers/plans/2026-09-03-swarm-phase4-design.md`)
  como ejemplo del grano de `- [ ] Step N` a replicar — es dogfooding intencional (v1 asume que el
  plugin corre sobre ESTE repo), documentar si fase 5+ alguna vez distribuye el plugin a otro repo.

## Rulings arquitectónicos de fase 4 (resueltos por ruling propio, sesión con autonomía delegada —
revisar si algo no encaja, aunque ya están implementados)

1. **`design-orchestrator` nunca encadena en `tier: light`** — lectura literal de "light = un solo
   dominio" (spec §9.1), mismo criterio ya aplicado a analysis en fase 3. Coste si está mal: bajo,
   recuperable re-corriendo en `full`.
2. **El dominio hace "plan → grill → revise" en vez de "spec → grill → plan"** (letra literal del
   spec §7) — no hay artefacto "spec" separado en v1, el plan ya es la síntesis. Coste si está mal:
   solo nomenclatura, no arquitectura.
3. **`planner` emite fases con steps `- [ ] Step N` anidados dentro** — ya implementado, no es una
   pregunta abierta: resuelve la incompatibilidad con el futuro `implementer` (fase 5, spec §7:
   "ejecuta UNA tarea cerrada del plan") sin perder la agrupación por fase.

## Siguiente paso: fase 5 — implementación + primer stack pack (spec §15)

`implementation-orchestrator` + 7 agentes (`implementer` con `isolation: worktree`, `test-writer`,
`migration-engineer`, `quality-fixer`, `reviewer`, `doc-writer`) + el stack pack
`php-ddd-symfony8` (`skills/pack-php-ddd-symfony8/`) + `dependency-auditor`/`dependency-installer`
del dominio requirements (diferidos desde fase 1b). Es la fase más grande del roster (7 agentes +
un pack completo) — considerar si conviene partirla en sub-fases (p. ej. 5a: implementer+test-writer
+quality-fixer+reviewer sin pack; 5b: el stack pack; 5c: migration-engineer+doc-writer+dependency-*)
antes de escribir el plan. Aún sin brainstorming/spec detallado más allá de lo que ya recoge
`docs/superpowers/specs/2026-09-01-swarm-design.md` §7/§15. Mismo patrón que 1b-4: (brainstorming
corto si hace falta) → plan → Subagent-Driven Development → smoke checklist en vivo → review final
de rama → merge local a master (sin preguntar, instrucción permanente del owner).

**No olvidar la pasada de documentación de uso pendiente (ver sección propia arriba) antes de v1.**

## Memoria persistente relevante

Buscar con mem-search si está disponible en esta sesión: convención de nombres estable, routing de
modelos (Fable/Opus decide y revisa, Sonnet ejecuta planes cerrados), identidad git personal
(`garcia.gordo.david@gmail.com`), regla de saneado shell compartida (`skills/swarm-protocol/SKILL.md`
§4.4 — quita, nunca escapa, backtick/`$(`/comilla/backslash), y la lección de fase 4: contenido
largo estructurado va por `Write`/`Edit` nativo, nunca por argumento de shell.
