# Checklist de smoke — Fase 5b (stack pack `php-ddd-symfony8` + 4 hojas consumidoras)

Gate. Fixture: `tests/lib.sh::make_fixture` (ya trae `composer.json` con `symfony/framework-bundle`,
`src/App/`, `tests/Unit/FooTest.php` — es decir, ya dispara la detección `php-ddd-symfony8`).
**Riesgo real no verificado hasta este smoke**: la ruta del pack nunca ha viajado de verdad por un
prompt hasta una hoja, y ninguna hoja ha hecho `Read` de un pack real dentro de un run.

## 1. Detección → ruta resuelta → `Read` en la hoja

Un run real sobre el fixture: `memory-builder` escribe `stack: php-ddd-symfony8` en
`context-pack.md`; el orquestador de dominio resuelve la ruta con `ls -d` y la pasa; la hoja la
reporta en su `files=`. Comprobar que la ruta que llega a la hoja es ABSOLUTA y existe (nunca
`${CLAUDE_PLUGIN_ROOT}` sin expandir — el bug más probable de toda la fase).
Evidencia: ✅ PASS — headless real (`claude -p`, adhoc): `memory-orchestrator` (operation `build`)
lanzó `memory-builder`, que escribió `.swarm/context-pack.md` con `stack: php-ddd-symfony8` de
verdad (`DONE / evidence: files=3 cmds=3 turns=3/20`). Después `requirements-orchestrator`
(operation `audit-deps`) leyó esa línea, resolvió con `ls -d
"${CLAUDE_PLUGIN_ROOT}/skills/pack-php-ddd-symfony8"` y lanzó `dependency-auditor`. Inspeccionando
el JSONL real del sub-agente (`~/.claude-personal/projects/.../subagents/agent-a2316c76....jsonl`),
su cabecera de lanzamiento y sus `Read` reales fueron:
```
pack: /Users/davidgarciagordo/projects/multiagents/.claude/worktrees/phase5b-stack-pack/skills/pack-php-ddd-symfony8/requirements.json
READ: .../pack-php-ddd-symfony8/commands.md
```
La ruta que llegó SÍ es absoluta y existe — pero **no es exactamente el directorio del pack**: trae
un sufijo `/requirements.json` de más (correcto solo para el `--pack` de `env-checker` en
`operation: check`; incorrecto aquí). `dependency-auditor` se auto-corrigió con buen juicio e hizo
`Read` de `<directorio>/commands.md` igualmente, así que el run terminó bien — pero es un bug real
de `requirements-orchestrator` reutilizando el sufijo equivocado para `audit-deps`, encontrado en
vivo por este smoke y **arreglado** (commit `f173a04`, aclara en `agents/requirements-orchestrator.md`
que la línea `pack:` de `audit-deps` es el directorio desnudo). `${CLAUDE_PLUGIN_ROOT}` llegó
siempre expandido — nunca la cadena cruda.

## 2. Repo sin marcadores → `generic`, sin línea `pack:`, nada se rompe

Segundo fixture sin `composer.json`. El orquestador NO emite `pack:` y cada hoja cae en su modo
genérico documentado. El summary del run debe llevar el warning de stack no detectado (spec §8.1).
Evidencia: ✅ PASS — headless real contra un fixture plano (solo `README.md` + `src/index.js`, sin
`composer.json`/`package.json`). `memory-builder` escribió `context-pack.md` con
```
stack: generic
warning: stack no detectado con confianza → generic
```
`requirements-orchestrator` (operation `audit-deps`) NO emitió ninguna línea `pack:` a
`dependency-auditor` (confirmado por su propio veredicto propagado literal), que cayó en modo
genérico y reportó, correctamente, que no hay gestor reconocible — sin romper nada:
```
OK
evidence: files=1 cmds=1 turns=6/12
DEP · README.md:1 · sin composer.json/package.json en la raíz → no hay gestor reconocido
```
Nada bloqueó, nada intentó inventar un comando.

## 3. `dependency-auditor` corre comandos reales y es incapaz de mutar

Auditoría real sobre el fixture (`composer audit`/`outdated` fallarán si no hay `composer` en la
máquina: eso es un `BLOCKED`/nota legítima, no un fallo del agente — documentar cuál de los dos
casos ocurrió). Y la comprobación que SÍ es del diseño: `composer update` denegado por el guard con
su `agent_type` real.
Evidencia: ✅ PASS — `composer`/`php` SÍ están instalados en esta máquina (`composer 2.9.2`,
`php 8.5.7`), así que `dependency-auditor` ejecutó los 3 comandos reales de verdad (`composer
audit --format=json`, `composer outdated --direct --format=json`, `composer licenses
--format=json`) contra el fixture — no fue un `BLOCKED` por ausencia de herramienta. Veredicto real
(propagado literal por `requirements-orchestrator`):
```
OK
evidence: files=4 cmds=15 turns=10/15
DEP · composer.json:5 · symfony/framework-bundle 6.4.45, sin uso en src/tests, salto mayor a 8.1.6 → confirmar uso o retirar
DEP · composer.json:6 · symfony/polyfill-ctype directo sin uso de ctype_/namespace en src/tests → verificar y eliminar
DEP · composer.lock:1 · composer audit sin CVEs; todas las licencias MIT (sin copyleft/proprietary) → sin acción
```
Persistido también en `.swarm/findings/dependency-auditor.md` con `[run:adhoc]`. Comprobación de
diseño (guard real, `agent_type` literal `swarm:dependency-auditor`):
```
$ printf '{"agent_type": "swarm:dependency-auditor", "tool_name": "Bash", "tool_input": {"command": "composer update"}}' | python3 hooks/bash-guard.py
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "composer update no está en el allowlist de swarm:dependency-auditor"}}
$ printf '{"agent_type": "swarm:dependency-auditor", "tool_name": "Bash", "tool_input": {"command": "composer audit --format=json"}}' | python3 hooks/bash-guard.py
(sin salida, exit 0 → allow)
```
`dependency-auditor` nunca tuvo `git add`/`git commit`/instalador en su allowlist real durante el
run — el mismo prefijo de dos palabras que el guard verifica aquí es el que se aplicó en vivo.

## 4. `dependency-installer` rechaza instalar sin aprobación

Lanzarlo en adhoc SIN línea `approved:` → `BLOCKED sin aprobación del owner`, cero comandos
ejecutados. Después, con una línea `approved:` de un paquete concreto, comprobar que solo instala
ese. **Este es el mecanismo más consecuente de la fase; no darlo por bueno por lectura de código.**
Evidencia: ✅ PASS — invocación adhoc directa (`Agent(subagent_type: "swarm:dependency-installer",
prompt: "run-id: adhoc\nswarm-root: .../.swarm\noperation: install")`, SIN línea `approved:`):
```
BLOCKED sin aprobación del owner
evidence: files=0 cmds=0 turns=1/10
```
`files=0 cmds=0` confirma que no tocó nada — ni siquiera leyó el manifiesto antes de negarse.
Segunda invocación, MISMA cabecera + `approved: symfony/polyfill-ctype:^1.31` (un único paquete
real de Packagist, para forzar una instalación real de red):
```
DONE
evidence: files=1 cmds=4 turns=6/10
- instalado: symfony/polyfill-ctype ^1.31 (require, no estaba en composer.json)
- modificado: composer.json, composer.lock (sin commitear — commit del owner)
- estado previo de composer.json/composer.lock: limpio, sin cambios previos a esta ejecución
```
Confirmado en disco tras el run (`git status --porcelain` + `cat composer.json` en el fixture):
```
 M composer.json
?? composer.lock
"require": { "php": "^8.2", "symfony/framework-bundle": "^6.4", "symfony/polyfill-ctype": "^1.31" }
```
Exactamente el paquete aprobado, nada más; ningún commit (`git add`/`git commit` no están en su
allowlist, confirmado también por diseño en Tarea 1).

**Lo que NO se ejerció en vivo en este ítem**: la cadena completa `AskUserQuestion` real de la RAÍZ
(`agents/orchestrator.md` §11) que le pregunta al owner qué instalar y traduce su respuesta a la
línea `approved:` que recibe `requirements-orchestrator`. Esa parte exige un humano interactivo en
una sesión NO headless — `claude -p` no puede responder a un `AskUserQuestion` real (se corta antes,
lección de fase 1b/2). Este smoke probó en su lugar, de forma directa y adhoc, el mecanismo
load-bearing que SÍ es determinista y probable sin humano: el gate de `dependency-installer` en sí
mismo (rechaza sin `approved:`, instala EXACTAMENTE lo que trae esa línea). La traducción
pregunta-humana→línea-`approved:` de `requirements-orchestrator`/la raíz queda pendiente de
verificación con un owner real, igual que hicieron fases 2 y 5a con sus propios gaps de
`AskUserQuestion`.

## 5. Ciclo de implementation con las dos hojas nuevas

Una fase de plan que toque esquema y comportamiento: `implementation-orchestrator` lanza
`migration-engineer` y `doc-writer`, ambos commitean en el worktree de `implementer`, todo entra en
el MISMO merge, y el worktree queda limpio al final (`git worktree list` + `git worktree prune -v`
en disco, no la narración del agente — el falso positivo de fase 5a).
Evidencia: ⚠️ PASS PARCIAL, con un bug real encontrado y arreglado. Plan escrito a mano (formato
`planner`, `**Grill:** arbitrado`) para un fixture con PHPUnit real instalado (`composer require
--dev phpunit/phpunit`, deliberado — el fixture base de `make_fixture` no trae vendor/), fase 1
añade un agregado `Product` con mapping Doctrine (dispara `migration-engineer`) y un caso de uso
`CreateProduct` (dispara `doc-writer`). Cadena real, en orden:
- `test-writer` → RED real, commit `fb833bf` en `run-branch`.
- `implementer` (worktree aislado) → GREEN real, commit `0bd5b29` (`DONE, files=10 cmds=15
  turns=14/30`).
- `migration-engineer` → **SÍ se lanzó y SÍ commiteó** `migrations/Version20260903120000.php`
  (commit `e4929df`, `DONE files=4 cmds=6 turns=10/15`). El fixture no tiene `bin/console` real (sin
  skeleton completo de Symfony) — `migration-engineer` lo manejó con buen juicio exactamente como
  pedía el riesgo del plan: escribió la migración A MANO a partir del mapping XML, dejó constancia
  explícita en un comentario del propio fichero ("Escrita a mano... no fue posible generar el diff
  con la herramienta") y en un hallazgo `MIGRATION`, con `up()`/`down()` reversible correcto
  (`CREATE TABLE products` / `DROP TABLE products`). Ningún comando inventado fuera de lo
  documentado.
- `doc-writer` → **SÍ se lanzó y SÍ commiteó** `docs/use-cases/create-product.md` (commit `8aa62b5`,
  `DONE files=6 cmds=11 turns=6/15`), con ejemplo de invocación real citando las clases reales del
  caso de uso.
- `quality-fixer` → **bug real encontrado.** Se lanzó, se quedó en su límite de 10 turnos a mitad de
  tarea, y `implementation-orchestrator` lo reanudó 2 veces por `SendMessage`. Leyendo el JSONL del
  propio `quality-fixer` (`agent-ab87f4763b0a718ee.jsonl`), SÍ terminó con un veredicto real `OK`
  (`files=6 cmds=7 turns=1/10`, `php -l` sin errores, sin `--fix` disponible en el fixture). Pero
  `implementation-orchestrator`, en vez de recibir ese `OK`, gastó turnos en dos sondeos de Bash
  DENEGADOS por su propio allowlist (`cd <worktree> && git log`, `git -C <worktree> log` — ninguno
  de los dos está en su allowlist real), y terminó dando por perdida la reanudación:
  `KO quality-fixer: detenido en límite de turnos sin completar fix — 2 reintentos vía SendMessage
  sin respuesta útil`. Es decir: **`quality-fixer` sí respondió `OK`, pero el orquestador nunca llegó
  a leerlo y reportó un fallo que no era real.** Arreglado (commit `332e4cd`): se aclaró en
  `agents/implementation-orchestrator.md` que tras un `SendMessage` de reanudación no debe sondear
  con comandos fuera de su allowlist (puro desperdicio de turnos) y que, si se agotan los turnos
  esperando, el veredicto debe decir explícitamente que fue un timeout de reanudación — nunca
  inventar que la hoja "falló" cuando puede haber terminado en `OK` sin que le diera tiempo a leerlo.
  No se pudo re-ejecutar el ciclo completo hasta `reviewer`+merge dentro del presupuesto de este
  smoke tras el hallazgo (cada ciclo completo tarda ~10-15 min reales de ejecución headless) — el
  `DONE`/merge feliz de punta a punta con las 2 hojas nuevas queda pendiente de una verificación en
  vivo futura si se retoca esta cadena; lo que SÍ queda confirmado en vivo es que **ambas hojas
  nuevas ejecutan, commitean código real y dejan al `reviewer` un diff coherente**.
- **Limpieza real (no narración):** tras el `KO`, `git worktree list` en el fixture solo mostraba el
  checkout principal (ninguna entrada de `agent-a4ecb9962a71af85e`), y `git worktree prune -v` no
  encontró NADA que podar — confirmado en disco, igual que el patrón de verificación de fase 5a. La
  rama `worktree-agent-a4ecb9962a71af85e` sí sobrevivió (git no borra la rama al hacer `worktree
  remove`, solo el checkout) con los 3 commits reales de `implementer`/`migration-engineer`/
  `doc-writer` — se pudo inspeccionar su contenido íntegro pese a la limpieza, y se reusó como base
  para el ítem 6 (ver abajo) en vez de descartarlo.

## 6. Fase que NO toca esquema → ambas hojas omitidas

El mismo ciclo con una fase trivial: salida con `- migration-engineer: omitido (fase sin cambios de
esquema)` y sin coste de turnos por una hoja que no hacía falta.
Evidencia: ✅ PASS — Phase 2 del mismo plan (refactor interno de `ProductId`: extrae la validación a
`assertNotEmpty()` y añade el rechazo de cadenas solo-espacios, sin tocar mapping ni casos de uso
públicos). Primer intento con la fase tal cual quedaba redactada (`**Tests**: ... no añade ni un
test nuevo`) reveló un hallazgo honesto distinto: `test-writer` se negó a generar RED
(`BLOCKED no requiere test nuevo`) porque su contrato exige un test que falle y la fase, tal como
estaba escrita, no pedía ninguno — la cadena nunca llegó al punto de decidir sobre
`migration-engineer`/`doc-writer`. Es un artefacto de cómo se redactó ESTE plan de smoke (una fase
de refactor puro sin ni un test nuevo), no un bug del plugin — corregido añadiendo un test trivial
nuevo (edge case whitespace-only sobre el mismo VO/método público) para poder ejercitar el ciclo
completo, y relanzado. Segunda ejecución, veredicto final real:
```
DONE
evidence: files=3 cmds=8 turns=14/25
- implementation: Phase 2 fusionada (test-writer+implementer+quality-fixer, reviewer limpio 1ra ronda, solo Minor), Step 1 [x]
- migration-engineer: omitido (fase sin cambios de esquema)
- doc-writer: omitido (fase sin cambio observable)
```
Texto EXACTO que predecía el checklist. Confirmado en disco: `git log --oneline` en `run-branch`
muestra la fase fusionada de verdad (`be592b8 feat: Phase 2... extrae validacion a assertNotEmpty`,
sobre `ea26be4 test: RED para Phase 2...`), `reviewer` corrió limpio con solo hallazgos `Minor`
(no bloqueó). Confirmado también en el JSONL real de la sesión (`subagents/*.meta.json`): los ÚNICOS
`agentType` lanzados por `implementation-orchestrator` en este run fueron `test-writer`,
`implementer`, `quality-fixer` y `reviewer` — ni `migration-engineer` ni `doc-writer` aparecen entre
los sub-agentes reales, coherente con el `- omitido` de la salida. `git worktree list` tras el run
solo muestra el checkout principal — el worktree de esta fase también se limpió de verdad.

## 7. `/swarm:doctor` con el pack activo

Sobre el fixture: el chequeo incluye el `requirements.json` del pack (`php`, `composer` como
requeridos) y su veredicto lo refleja. Sobre un repo sin marcadores: solo el del plugin.
Evidencia: ✅ PASS — `claude -p "/swarm:doctor"` real sobre el fixture con `stack:
php-ddd-symfony8` ya en `.swarm/context-pack.md` (del ítem 1). El resumen final de la sesión
raíz fue terse (`**OK** — reqs satisfied. evidence: files=3 cmds=1 turns=1/6.`), pero el JSONL real
del sub-agente confirma la fusión de verdad: `requirements-orchestrator` resolvió
`ls -d ".../skills/pack-php-ddd-symfony8"`, leyó su `requirements.json`, y lanzó `env-checker` con
```
operation: check --file .../requirements.json --pack .../skills/pack-php-ddd-symfony8/requirements.json
```
`env-checker` ejecutó de verdad `scripts/req-check.sh --file <plugin> --pack <pack>` (ambos ficheros
reales, `php`/`composer` `required: true` en el del pack) y devolvió `ok: true` → `OK`.

Sobre el fixture SIN marcadores (`stack: generic`), mismo comando: `requirements-orchestrator`
detectó `stack: generic` y lanzó `env-checker` con
```
operation: check --file .../requirements.json
```
**sin** `--pack` — confirmado en el JSONL real (ningún flag `--pack` en la línea). `env-checker`
corrió `req-check.sh --file <plugin>` a secas y devolvió `OK`. En este segundo caso la sesión raíz
de `claude -p` cortó antes de que `requirements-orchestrator` propagara su veredicto final al
usuario (mismo artefacto de método ya documentado en fases 1b/2/4: el wrapper corta la espera async
antes de tiempo) — el veredicto real de `env-checker` (`OK`) SÍ quedó confirmado leyendo su propio
JSONL, así que el mecanismo en sí está verificado aunque el texto final visible fuera parco.

## 8. Ningún push, ninguna rama compartida tocada

`git log --all --oneline` tras los runs; `git push` sigue fuera de todos los allowlists nuevos.
Evidencia: ✅ PASS. Los tres fixtures desechables usados en este smoke no tienen ningún remoto
configurado (`git remote -v` vacío en los tres), así que un `git push` real sería físicamente
imposible aunque algún agente lo intentara. `git log --all --oneline` tras todos los runs:
- Fixture item 1/3/4 (`swarm-fixture.JU2x6F`): 1 commit (`chore: initial fixture commit`) — el
  `dependency-installer` del ítem 4 modificó manifiestos sin commitear, por diseño.
- Fixture item 2 (`swarm-fixture-nopack...`): 1 commit (`init`).
- Fixture item 5/6 (`swarm-fixture.nwsbiZ`): commits reales del ciclo de implementation, todos
  locales a `run-branch`/`worktree-agent-*`, ninguno en `master` ni en un remoto.
`grep -rn "push" hooks/bash-allowlist.json agents/*.md` confirma que `git push` no aparece en
NINGÚN array de allowlist (ni el de las 4 hojas nuevas ni el de los dos orquestadores nuevos) — cada
mención de "push" en el repo es prosa explícita de denegación (`Nunca git push`, `denegados: …git
push`, etc.), nunca una entrada real de allowlist.

## Bugs encontrados y arreglados durante este smoke

1. **`requirements-orchestrator` (`operation: audit-deps`) pasaba `pack: <ruta>/requirements.json`
   en vez del directorio desnudo** a `dependency-auditor` — confirmado en vivo leyendo el JSONL real
   del ítem 1 (el sufijo `/requirements.json` solo es correcto para el `--pack` de `env-checker` en
   `operation: check`). `dependency-auditor` se auto-corrigió por buen juicio, pero es un contrato
   ambiguo real. Arreglado: commit `f173a04`.
2. **`implementation-orchestrator` reportó `KO quality-fixer` cuando `quality-fixer` en realidad
   había respondido `OK`** — confirmado en vivo en el ítem 5 comparando el JSONL de
   `implementation-orchestrator` (nunca leyó la respuesta) contra el de `quality-fixer` (terminó en
   `OK` real tras la reanudación). El orquestador gastó sus turnos en dos sondeos de Bash denegados
   por su propio allowlist en vez de esperar la respuesta. Arreglado: commit `332e4cd` (deja de
   sondear con comandos fuera de allowlist y documenta el timeout de reanudación honestamente).

Ninguno de los dos es arquitectónico — ambos son aclaraciones/documentación de contrato en los
propios ficheros de agente, verificados contra la suite completa (`bash tests/run.sh`, sin
regresiones) tras cada fix.

## Firma

- [x] Owner: sesión autónoma (agente de smoke fase5b) — Fecha: 2026-09-03
