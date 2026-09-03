# Handoff — swarm, 2026-09-03 (fases 1 + 1b + 2 + 3 + 4 + 5a + 5b cerradas, documentación de uso hecha)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí — toca decidir/empezar la **fase 6 (delivery)**: `delivery-orchestrator` +
> `release-manager` + `handoff-writer` (spec §7/§15), primer dominio con `git push` real. Es la
> última fase antes de poder declarar v1 estable. Modo de trabajo: brainstorming corto si hace falta
> cerrar algo del diseño → `writing-plans` → Subagent-Driven Development (superpowers), commit por
> tarea, review adversarial por tarea + review final de rama antes de merge, checklist de smoke
> ejecutado EN VIVO (no solo escrito) antes de dar una fase por cerrada — así se han encontrado y
> arreglado bugs reales en CADA fase (2 en fase 1, 1 en fase 1b, 3 en fase 2, varios en fase 3, 7+ en
> fase 4, 1 Critical + 6 Important en fase 5a, 1 Critical + 5 Important + 2 hallazgos nuevos del
> propio fix + 1 Important residual en fase 5b) que ninguna review individual pilló sola. David
> quiere avisos cuando cierre cada fase, no antes. Cada task/fix termina en commit con SU identidad
> git personal (`garcia.gordo.david@gmail.com`, no Classlife). **Merge siempre local a master**
> (instrucción permanente del owner, 2026-09-03) — no preguntar cada vez, no ofrecer PR salvo que lo
> pida explícitamente. **La pasada de documentación de uso completa ya está hecha**
> (`docs/USAGE.md`/`USAGE.es.md`, commit `21a1e6a`) — mantenerla al día si fase 6 añade
> comandos/dominios nuevos, no repetirla desde cero.

## Dónde está todo

- Repo: `/Users/davidgarciagordo/projects/multiagents` (plugin Claude Code `swarm`, sin remoto aún,
  rama `master`, sin ramas de trabajo propias abiertas — **excepto** `worktree-phase2-discovery`,
  ver nota de limpieza pendiente abajo, sin cambios desde hace 4 handoffs). Todas las demás ramas de
  fase ya se mergearon y limpiaron (worktree borrado, rama borrada).
- **Trabajo concurrente de otra sesión**: durante el cierre de fase 5b, la sesión `multiagents-c9`
  trabajaba en paralelo sobre un pedido en vivo del owner (bucle de estado activo para
  orquestadores, en discusión — investigaron si un subagente orquestador recibe notificación
  automática al terminar una hoja `background: true`, confirmado que SÍ vía plataforma, sin
  mecanismo nuevo necesario) y ya mergeó `fix-discovery-orchestrator-timeout` (commit `17d976c`,
  quita el margen artificial de 2 turnos que `discovery-orchestrator` se daba a sí mismo esperando a
  `research-analyst`/`feasibility-spiker` — innecesario porque la notificación real llega sola).
  Coexiste sin conflicto con fase 5b (verificado, suite 42/42 tras el merge combinado). Si esa
  sesión sigue activa, puede haber más cambios en curso sobre `discovery-orchestrator.md` — revisa
  `git log` antes de asumir el estado de ese fichero.
- Spec: `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — fuente de verdad del diseño.
- **Guía de uso completa: `docs/USAGE.md` / `docs/USAGE.es.md` (commit `21a1e6a`, actualizada en
  fase 5b para el stack pack y las 4 hojas nuevas).** Instalación real, los 3 comandos con ejemplos
  reales, cada dominio construido explicado en términos de usuario. Los README solo apuntan a ella.
- **Fases 1, 1b, 2, 3, 4 — completas y mergeadas.** Detalle completo en `git log` o memoria
  persistente; resumen en handoffs anteriores si hace falta releer motivos.
- **Fase 5a (núcleo del dominio implementation) — completa y mergeada.** `test-writer`/
  `implementer`/`quality-fixer`/`reviewer`/`implementation-orchestrator`. Primera fase que escribe y
  fusiona código real, primer orquestador con `git merge`/`git worktree` de verdad, nunca encadena
  tras discovery/design (checkpoint humano deliberado).
- **Fase 5b (stack pack + 4 hojas consumidoras) — completa y mergeada (merge commit `d9e777d`,
  2026-09-03).** Primer stack pack `skills/pack-php-ddd-symfony8/` (6 ficheros del contrato §8,
  contenido real derivado de un estudio acotado de un proyecto PHP-DDD-Symfony real usado SOLO como
  referencia de patrones, nunca nombrado ni citado en el pack) + 4 hojas nuevas:
  `migration-engineer` (migraciones, condicional a que la fase toque esquema),
  `doc-writer` (docs + changelog, condicional a cambio observable, regla de corte por presupuesto de
  turnos), `dependency-auditor` (auditoría read-only vía comandos del pack), `dependency-installer`
  (primer leaf mutante del dominio requirements — instala solo lo que el owner aprobó explícitamente
  vía `AskUserQuestion` de la raíz, nunca `brew`/`apt`, nunca desinstala, nunca commitea). Wiring del
  pack a través de `implementation-orchestrator`/`analysis-orchestrator` ya construidos, fusión real
  de `requirements.json` (plugin + pack, pack gana en conflicto) en `requirements-orchestrator`
  (antes prosa inerte de fase 1b), integración de raíz (`agents/orchestrator.md` §11 "Requisitos e
  instalación").
  - **Smoke EN VIVO real**: ciclo completo contra fixtures desechables, 2 bugs reales encontrados y
    arreglados EN VIVO durante el propio smoke (no en review): `dependency-auditor` recibía la ruta
    de `requirements.json` en vez del directorio del pack (confusión de convenio con
    `env-checker`); `implementation-orchestrator` quemaba turnos sondeando el worktree de
    `quality-fixer` resumido con comandos denegados por su propio allowlist, y declaraba un `KO`
    fabricado pese a que `quality-fixer` había devuelto `OK`. Honestamente revelado lo no ejercitado:
    la cadena completa `AskUserQuestion` real de la raíz (necesita owner humano interactivo) — se
    verificó en su lugar el mecanismo de carga real de `dependency-installer` (el gate en sí),
    directamente headless.
  - **Review final de rama (Opus, 17 commits): 1 Critical** — verdicto `DONE · <detalle>` de
    `doc-writer`/`implementation-orchestrator` rechazado por `validate-output.py` (mismo patrón que
    `design-orchestrator` ya documentaba desde fase 4 como trampa, no replicado aquí; consecuencia
    real: una fase completada con éxito reportada como `KO` y su worktree destruido). **+ 5
    Important**: mismo bug de sondeo de worktree denegado en un segundo punto (paso 3, el fix de
    fase 5b solo cubrió el paso 5); ruta sin expandir pasada a `env-checker`; fila `scan-secrets` de
    `commands.md` soltada en silencio por el parser de su propio test de cobertura; `composer
    update` bare permitido por el guard para `dependency-installer` (escape de alcance más allá de
    la aprobación itemizada); sin test que valide plantillas de veredicto contra el hook real (el
    hueco sistémico que dejó pasar el Critical).
  - **1 sola ronda de fix + re-review Opus escopeada** (primera corrida de la re-review interrumpida
    por sleep de la máquina — error de API, reintentada limpia) que verificó cada hallazgo
    empíricamente contra los hooks reales, más 2 hallazgos genuinos nuevos que el propio implementer
    encontró al arreglar (línea `evidence:` faltante en un `BLOCKED`; fila de consumidores de
    `precedents.md` con un agente listado por error). La re-review encontró 1 Important residual
    (el backstop `composer update` solo cerraba la forma exacta de 2 palabras, dejaba pasar 8
    variantes solo-con-flags con el mismo radio de alcance) + 1 Minor cosmético — ambos arreglados
    directamente por el controlador sin ronda de agente adicional, verificados contra el guard real.
- Todo en `master`: **42 archivos de test, 42/42 en verde** (`bash tests/run.sh`, verificado tras el
  merge combinado con el fix de la sesión peer).
- Agentes vivos: `swarm:orchestrator` (raíz), memory (3), requirements (5: `requirements-orchestrator`,
  `env-checker`, `dependency-auditor`, `dependency-installer`, más el roster ya existente), discovery
  (5), analysis (7), design (4 + 3 lentes grill externos), implementation (7: `test-writer`,
  `implementer`, `migration-engineer`, `doc-writer`, `quality-fixer`, `reviewer`,
  `implementation-orchestrator` — dominio completo 7/7 del spec §7). Comandos: `/swarm:init`,
  `/swarm:run`, `/swarm:doctor`.

## Limpieza pendiente (no urgente, sin cambios desde hace 4 handoffs)

El worktree `.claude/worktrees/phase2-discovery` (rama `worktree-phase2-discovery`, ya mergeada
fast-forward a `master`) sigue registrado porque estaba **bloqueado por una sesión Claude viva
corriendo dentro de él** en el momento del merge. Cuando esa sesión termine: desde el repo principal,
`git worktree remove .claude/worktrees/phase2-discovery && git branch -d worktree-phase2-discovery`.
Verificar antes con `git worktree list -v` que ya no aparece `locked`.

## Lecciones acumuladas (aplícalas en cada fase nueva — release ya las necesitará todas)

1. **"La lección" (aplicada 6+ veces ya)**: todo orquestador de dominio que lance una hoja que NO
   preexiste necesita `Agent(<hoja1>,<hoja2>,…)` en su `tools:` — nunca solo `SendMessage`. Aplica
   igual a agentes de OTRO plugin ya instalado.
2. **Protocolo compartido, cero preámbulo**: ya resuelto en `skills/swarm-protocol/SKILL.md` §4, no
   repetir por agente.
3. **Contenido largo estructurado → `Write`/`Edit` nativo, nunca argumento de shell.**
4. **La exención de saneado del §4.4 NUNCA cubre el `summary --line` de cierre** — este bug recurrió
   en CUATRO dominios distintos (analysis→design→implementation→requisitos) porque cada autor nuevo
   no copió el párrafo literal del dominio anterior. **Copiar literal, no reescribir de memoria.**
5. **Un allowlist nunca probado contra los comandos reales del propio agente es un allowlist sin
   verificar** — `tests/test_agent_bash_blocks_allowed.sh` extrae y prueba cada bloque ```bash de
   cada agente contra el guard real; EXTENDER su lista (`AGENT_FILES`) en cada fase que añada
   agentes con Bash, nunca confiar en lectura visual del JSON del allowlist.
6. **Limpieza de recursos mutables (worktree, lock) debe cubrir TODOS los caminos de salida** — una
   sección compartida referenciada desde cada camino terminal, más un test que lo compruebe por
   conteo/orden, no solo prosa.
7. **NUEVA (fase 5b): un verdicto documentado con sufijo `· <detalle>` tras `DONE` es rechazado por
   `hooks/validate-output.py`** (`VERDICT_RE` solo admite sufijo tras `KO`/`BLOCKED`, nunca tras
   `DONE`/`OK`). `design-orchestrator` ya lo documentaba como trampa desde fase 4; recurrió en
   `doc-writer`/`implementation-orchestrator` en fase 5b porque nadie lo replicó. **Para cualquier
   agente nuevo: `DONE` siempre solo en la línea 1, cualquier detalle va en una línea de cuerpo
   (`- algo: detalle`), nunca `DONE · algo`.** Se añadió `tests/test_verdict_templates_valid.sh`
   (extrae plantillas de veredicto de los agentes y las prueba contra el hook real) para 7 agentes —
   **extender su lista a cada agente nuevo de fase 6**, sigue siendo el hueco sistémico más barato de
   cerrar por adelantado.
8. **NUEVA (fase 5b): un fix aplicado en un solo punto de un bug que aparece en varios sitios del
   mismo fichero no está completo** — el bug del sondeo de worktree denegado (`implementation-orchestrator`)
   se arregló en el paso 5 durante el propio smoke de fase 5b, pero el paso 3 tenía el MISMO patrón y
   sobrevivió hasta la review final. **Al arreglar un bug de "instrucción pide un comando que el
   allowlist deniega", grepear el fichero entero por el mismo patrón, no confiar en que un solo sitio
   sea todo el bug.**

## Lo que NO se toca ni se construye todavía

`delivery-orchestrator`/`release-manager`/`handoff-writer` (spec §7/§15, fase 6) — cero código, solo
prosa en `agents/orchestrator.md` diciendo honestamente que no existen. `/swarm:status`/
`/swarm:findings` son fase 6 también. Un segundo stack pack está fuera de alcance de v1 (spec §8.1).
Todo lo demás del roster de 30 agentes propios del plugin (spec: "Total 30... — grill×3 es externo")
está construido: memory (3), requirements (5), discovery (5), analysis (7), design (4), implementation
(7 — completo), más la raíz. Fase 6 añade los 3 últimos hasta completar el total.

## Backlog no bloqueante (de las reviews finales de fases 1-5b — no urgente, atender cuando toque el
área correspondiente)

- `hooks/bash-guard.py`: no inspecciona `$(...)`/backticks DENTRO de argumentos sin comillas de un
  comando ya permitido (con comillas sí lo cubre el saneado de §4.4) — preexistente de fase 1,
  confirmado en fases 1b/2/3/5a/5b. Hardening dedicado antes de dar más agentes con `Bash` a fase 6
  — especialmente relevante ahí porque será el primer dominio con `git push` real.
- `hooks/bash-allowlist.json`: `pwd`/`echo` no están en ningún allowlist — no bloquea nada hoy.
- Fase 5a: la guardia anti-`master` de `implementation-orchestrator` es una lista de 2 nombres
  (`master`/`main`) — `develop`/`trunk`/`release/*` no cubiertos. Riesgo bajo (merge siempre local),
  `git rev-parse --abbrev-ref origin/HEAD` lo cubriría. **Relevante para fase 6**: el dominio
  delivery SÍ tocará remoto de verdad — esta guardia necesita revisión/extensión real ahí, no solo
  parcheo cosmético.
- Fase 5a: `git worktree remove` no borra la rama `worktree-agent-<agentId>` — se acumula una rama
  muerta por fase implementada.
- Fase 5b: el chequeo `libs` de `requirements.json` sigue siendo no-bloqueante por diseño (ruling 5,
  split por SRP: `req-check.sh` reporta, `dependency-auditor` verifica de verdad vía comandos del
  pack). Extensiones de PHP (`ext-pdo` etc.) no son expresables en el esquema actual — documentado en
  `conventions.md` del pack, sin consumidor real todavía, no bloquea.
- Fase 5b: piso `php >= 8.2` del pack es conservador (ruling 7) — no verificado contra el floor real
  de Symfony 8 en su momento; cambio de una línea si se confirma un floor más alto.
- Fase 5b: `dependency-installer` acotado a gestores de proyecto, nunca `brew`/`apt` (ruling 2) —
  desviación consciente del spec §7, marcada como revisable.

## Siguiente paso: fase 6 (delivery) — spec §7/§15, última fase antes de v1 estable

`delivery-orchestrator` + `release-manager` + `handoff-writer` — **primer dominio con `git push`
real** (todo lo anterior, incluida la fase 5a/5b con `git merge`, se quedaba estrictamente local).
Diseño de seguridad debe ser AL MENOS tan riguroso como el checkpoint humano de
`implementation-orchestrator` (nunca encadena automáticamente) — probablemente más: publicar código
es la acción más consecuente e irreversible que puede hacer el enjambre. Antes de escribir el plan:
1. Releer spec §7/§15 fase 6 en detalle (rol de cada uno de los 3 agentes, qué activa el dominio).
2. Decidir el mecanismo de aprobación del owner para un push/PR real — mismo patrón que
   `dependency-installer` (fase 5b: `approved:` construido SOLO por la raíz vía `AskUserQuestion`,
   nunca inferido) es el precedente más cercano, pero push/PR tiene mayor radio de alcance que
   instalar una dependencia — puede necesitar algo más estricto.
3. Mismo patrón de ejecución que fases anteriores: (brainstorming corto si hace falta) → plan →
   Subagent-Driven Development → smoke checklist EN VIVO → review final de rama → **fix wave único +
   re-review escopeada** (el patrón que salvó fase 5a y 5b de bugs Critical reales) → merge local a
   master (sin preguntar).
4. Tras fase 6: **v1 estable** — repasar el backlog completo de este handoff, decidir qué se arregla
   antes de declarar v1 y qué queda como backlog post-v1 documentado.

## Memoria persistente relevante

Buscar con mem-search si está disponible: convención de nombres estable, routing de modelos
(Fable/Opus decide y revisa, Sonnet ejecuta planes cerrados), identidad git personal
(`garcia.gordo.david@gmail.com`), regla de saneado shell compartida (`skills/swarm-protocol/SKILL.md`
§4.4), y las 8 lecciones acumuladas arriba (especialmente la 4, 7 y 8 — patrones que ya han recurrido
más de una vez en fases distintas).
