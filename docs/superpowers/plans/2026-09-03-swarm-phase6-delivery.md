# Fase 6 — Dominio delivery (`delivery-orchestrator` + `release-manager` + `handoff-writer`) + `/swarm:status` y `/swarm:findings` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el ÚLTIMO dominio del roster del spec (§7 "Entrega": `delivery-orchestrator`,
`release-manager`, `handoff-writer`) — el primero y único con `git push` real y capacidad de abrir
un PR — más los dos comandos de visibilidad que faltan (`/swarm:status`, `/swarm:findings`, spec
§11/§15 fase 6), cerrando el roster de 30 agentes propios y dejando el plugin en estado v1.

**Architecture:** El dominio delivery es **de dos fases separadas por un checkpoint humano real**, y
esa separación es la propiedad de seguridad central de toda la fase. Fase A (`prepare-release`):
`release-manager` valida el estado del repo, resuelve remoto y rama base, comprueba que la suite del
pack está en VERDE, escribe las notas de release en `.swarm/run/<id>/release-notes.md` y devuelve un
**preview literal** de los comandos que ejecutaría — sin ejecutar ninguno de ellos, sin tocar el
remoto, sin crear un commit. La RAÍZ presenta ese preview al owner con `AskUserQuestion` (único
agente del plugin con esa tool, spec §3.2 regla 7) y traduce un SÍ en una línea de cabecera literal
`approved-push: remote=<r> branch=<b> base=<base>` que NOMBRA el destino exacto. Fase B
(`publish-release`): la raíz relanza el dominio con esa línea; `release-manager` **re-verifica contra
la realidad** (HEAD es esa rama, ese remoto existe con esa URL, la rama no es la base ni una
protegida) y solo entonces hace `git push <remote> <branch>` y `gh pr create`. Nunca fusiona el PR,
nunca hace checkout, nunca commitea, nunca empuja a una rama protegida — y esas cuatro cosas no
dependen solo de la prosa: `hooks/bash-guard.py` gana un backstop determinista nuevo que las deniega
para CUALQUIER agente, presente o futuro.

Hay una **tercera operación**, `configure-remote`, que existe por el caso real de este mismo repo: un
repo sin remoto. `release-manager` sigue devolviendo `BLOCKED sin remoto configurado` (no puede
empujar a un remoto que no existe), pero la RAÍZ trata ESE motivo distinto de cualquier otro
`BLOCKED`: no cierra el run en seco, sino que lo convierte en una pregunta real al owner con
`AskUserQuestion` — crear un repo nuevo en su cuenta de GitHub y usarlo como `origin`, usar un remoto
que ya tiene, o no hacer nada. Si el owner elige mutar, la raíz construye una segunda cabecera de
aprobación con la MISMA forma que la del push, `approved-remote: action=create name=<repo>
visibility=<public|private>` (o `action=use url=<url>`), y `release-manager` —nunca la raíz, que no
ejecuta trabajo de hoja— es quien corre `gh repo create`/`git remote add`. La raíz sigue sin tener
`gh` en su allowlist, a propósito.

`handoff-writer` corre al final de CADA invocación (éxito, bloqueo o rechazo del owner) y escribe un
MD de relevo con la forma ya establecida en `docs/superpowers/handoffs/`. Los dos comandos de
visibilidad tienen como camino PRIMARIO dos scripts deterministas (`scripts/swarm-status.sh`,
`scripts/swarm-findings.sh`) que el comando ejecuta y reporta tal cual, igual que `/swarm:init` con
`swarm-init.sh` (spec principio 4: tool determinista antes que modelo) — cero modelo en el caso
común — más un **fallback acotado, inline en el propio fichero de comando** (sin subagente) para el
residual que el script no puede resolver de forma determinista y señaliza con `exit 2`.

**Tech Stack:** Markdown (frontmatter YAML) para agentes y comandos, Python 3 stdlib
(`hooks/bash-guard.py`), Bash 3.2 (scripts y tests), `git` (≥ 2.x, ya requerido en
`requirements.json`), `gh` CLI (**opcional** — ya declarado `required: false` en
`requirements.json`; sin él, `release-manager` degrada a instrucción manual de PR, nunca falla).

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (**v2.2**, actualizado por una sesión
peer el 2026-09-03 con §14bis) — §7 "Entrega" (las 3 filas con su modelo y `maxTurns`), §7.0 (modelo
por tier: `delivery-orchestrator` haiku en ambos tiers, `handoff-writer` hoja mecánica → haiku), §11
(visibilidad: `/swarm:status`, `/swarm:findings`, `summary.md` por run), §12 (estructura del plugin:
`commands/status.md`, `commands/findings.md`), §15 fase 6, §16 (fuera de alcance v1). **§14bis (gate
de verificación independiente, `swarm:verifier`) NO se construye en este plan** — ver "Alcance".

## Alcance — qué NO entra en esta fase (para que nadie lo busque aquí)

- **Modo Agent Teams.** El spec lo marca literalmente "Opcional: modo Agent Teams tras flag" (§15
  fase 6) y "fuera del diseño base; modo opcional futuro" (§3.1), y §16 lo lista como fuera de
  alcance de v1. **No se construye, no se prepara, no se deja andamiaje.**
- **Un push real a un remoto de red.** Todo el smoke (Task 7) corre contra un **repo bare local
  desechable** (`git init --bare` en un tmp dir, `file://` como URL de remoto). Ningún paso de esta
  fase toca GitHub/GitLab ni ningún host real, ni durante el desarrollo ni durante la verificación.
  **Matiz de `configure-remote` (Task 2b):** su rama `action=use` SÍ se ejercita en el smoke (la URL
  es la del bare `file://`); su rama `action=create` **no se ejercita automáticamente**, porque
  crearía un repositorio real en la cuenta del owner. Lo que sí se verifica sin tocar la red: el
  guard (formas denegadas de `gh repo create`/`git remote add`, Task 1), el gate (`BLOCKED sin
  aprobación de remoto` / `BLOCKED aprobación de remoto malformada` sin ejecutar nada) y el preview.
  La ejecución real de `action=create` es un paso MANUAL y opcional del checklist, que el owner corre
  una vez si quiere (ítem 11 de Task 7) — y de hecho ya se ejercitó a mano en este repo el
  2026-09-03, de donde sale el ruling 14.
- **Auto-merge de un PR.** `release-manager` prepara, empuja y abre el PR; **el merge del PR lo hace
  una persona**, siempre. Esto NO es un diferido a v1.1: es una propiedad permanente del diseño, del
  mismo rango que "`implementation-orchestrator` nunca toca `master`". `gh pr merge` queda denegado
  por el guard determinista, no solo por la prosa (Task 1).
- **Segundo stack pack, multi-stack por ruta, telemetría de coste, CI externo** — spec §16, fuera de
  v1, sin cambios en esta fase.
- **Versionado semántico / tags de release.** `release-manager` no crea tags, no decide números de
  versión y no edita el `CHANGELOG.md` del repo (ruling 7). Genera notas de release para el cuerpo
  del PR; la entrada de changelog por fase ya la escribe `doc-writer` (spec §7, dominio
  implementation) y duplicar esa responsabilidad rompería el principio 1.
- **Backlog de fases anteriores** (hardening de `$(...)` en `bash-guard.py` dentro de argumentos sin
  comillas, rama `worktree-agent-*` huérfana, `worktree-phase2-discovery` bloqueado). Se decide qué
  se arregla al declarar v1, tras esta fase — ver Task 7 Step 5.
- **El agente `swarm:verifier` y el gate de §14bis.** El spec pasó a **v2.2** el 2026-09-03 (commit
  `c637a90`, sesión peer) añadiendo un gate de verificación independiente que la RAÍZ ejecuta tras el
  `DONE`/`OK` de CUALQUIER orquestador de dominio y ANTES de `curate`/cerrar. **No es parte de la
  fase 6** (§15 fase 6 son 3 agentes + 2 comandos; §14bis no tiene fase asignada y lo lleva la sesión
  peer) y este plan **no lo construye ni lo prepara**. Sí está diseñado para **componer** con él: el
  §12.3 de Task 6 cierra el run "igual que en cualquier otro camino terminal (§4)" en vez de
  redescribir la secuencia de cierre, así que si el gate aterriza en §4 antes o después, el dominio
  delivery lo hereda sin tocar nada. **Riesgo de colisión real**: `agents/orchestrator.md` es el
  fichero que ambos trabajos tocan — de ahí el Step 0 de Task 6 y su programación tardía.

## Global Constraints

- **Frontmatter obligatorio** en cada agente nuevo: `name`, `description` ("Use when…"), `model`,
  `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`. Nunca
  `hooks:`/`mcpServers:`/`permissionMode:` (spec §3.1: se IGNORAN en subagentes de plugin), nunca
  sintaxis `Bash(cmd:*)`. `tests/test_agents_frontmatter.sh` lo vigila con glob dinámico — cubre los
  3 agentes nuevos gratis, sin tocar el test.
- **Modelo y `maxTurns` EXACTOS del spec §7**: `delivery-orchestrator` haiku / 10,
  `release-manager` sonnet / 15, `handoff-writer` haiku / 8. Por §7.0, `handoff-writer` es "hoja
  mecánica" (haiku en `full` y en `light`) y `release-manager` no está en la lista de hojas de
  juicio → **ninguno de los tres recibe override de `model` por tier**, ni en `light` ni en `full`.
- Todo agente nuevo lleva `SendMessage` en `tools` (spec §7, nota de cabecera del roster).
- **Ninguna hoja ni orquestador de dominio tiene `AskUserQuestion`** (spec §3.2 regla 7). La
  aprobación del push la obtiene la RAÍZ, único agente del plugin con esa tool.
- **Lección 1 del handoff (aplicada ya 6+ veces): `Agent(<hoja>,…)` en `tools:`.**
  `delivery-orchestrator` lanza dos hojas que NO preexisten → su frontmatter declara
  `Agent(release-manager,handoff-writer)`. Nunca solo `SendMessage` (solo llega a agentes ya vivos).
  `tests/test_delivery_orchestrator_spawns.sh` (Task 4) lo vigila.
- **Lección 2: cero preámbulo** (`skills/swarm-protocol/SKILL.md` §4). El último mensaje de cada
  agente nuevo empieza LITERALMENTE en el veredicto, con `evidence: files=N cmds=M turns=k/max` como
  línea 2 y hallazgos `TAG · fichero:línea · problema → fix` después. Sin frase previa, sin cierre.
- **Lección 3: contenido largo estructurado → `Write`/`Edit` nativo, nunca argumento de shell.**
  Aplica literalmente a `release-manager` (notas de release) y a `handoff-writer` (el MD de relevo):
  ninguno de los dos construye su fichero con `cat >`/`echo` — ambos tienen `Write` en `tools` y
  ninguno tiene `echo`/`cat >` en su allowlist.
- **Lección 4: la exención de saneado del §4.4 NUNCA cubre el `summary --line` de cierre.** Este bug
  recurrió en CUATRO dominios seguidos (analysis → design → implementation → requirements) porque
  cada autor nuevo lo reescribió de memoria. Task 6 **copia LITERAL** el párrafo del §11.3 actual de
  `agents/orchestrator.md` (el que empieza "**Esa exención NO cubre el `summary --line` del
  cierre.**"), sustituyendo únicamente el nombre del orquestador y los números de sección. El test
  cuenta ocurrencias: hoy 4, tras Task 6 deben ser **5**.
- **Lección 5: un allowlist nunca probado contra los comandos reales del propio agente es un
  allowlist sin verificar.** Los 3 agentes nuevos se añaden a `AGENT_FILES` de
  `tests/test_agent_bash_blocks_allowed.sh` (Tasks 2, 3, 4) — cada bloque ```bash documentado en su
  cuerpo pasa por `hooks/bash-guard.py` con su `agent_type` real.
- **Lección 6: limpieza de recursos mutables en TODOS los caminos de salida, con test.** Verificado
  para esta fase: **ningún agente nuevo crea un recurso con ciclo de vida DENTRO del run** (ni
  worktree, ni lock, ni rama nueva, ni commit). La excepción consciente es `configure-remote`
  (Task 2b): el repositorio de GitHub y la entrada `origin` que crea son **permanentes y así lo
  quiere el owner** — no son recursos que el run deba limpiar al salir, sino el resultado que el
  owner aprobó explícitamente. Por eso no entran en la lección 6 (nada que revertir en el camino de
  error: si el `gh repo create` falla, no hay repo; si falla el push posterior, el repo queda creado
  y vacío y el veredicto lo dice literalmente, ver ruling 14).
  `release-manager` publica una rama que YA existía y escribe bajo `.swarm/`
  (gitignorado); `handoff-writer` escribe un fichero de docs que deja sin commitear a propósito
  (ruling 9). Por eso este plan **no añade un test de limpieza nuevo** — pero Task 4 sí exige que
  `delivery-orchestrator` lance `handoff-writer` en TODOS sus caminos terminales (éxito, `KO`,
  `BLOCKED`), y `tests/test_delivery_orchestrator_spawns.sh` lo comprueba por conteo de caminos, no
  por prosa.
- **Lección 7: `DONE · <detalle>` es RECHAZADO por `hooks/validate-output.py`** (su `VERDICT_RE` es
  `^(OK|KO .+|DONE|BLOCKED .+)$`: solo `KO`/`BLOCKED` admiten sufijo). En los 3 agentes nuevos,
  `DONE` va SIEMPRE solo en la línea 1 y cualquier detalle va en una línea de cuerpo
  (`- algo: detalle`). Los 3 se añaden a `AGENT_FILES` de `tests/test_verdict_templates_valid.sh`
  (Tasks 2, 3, 4), que corre cada plantilla documentada contra el hook REAL.
- **Lección 8: un fix en un solo sitio de un bug que aparece en varios sitios del mismo fichero no
  está completo.** Al tocar `hooks/bash-guard.py` (Task 1) y `agents/orchestrator.md` (Task 6), se
  **grepea el fichero entero** por el mismo patrón antes de dar el cambio por hecho; cada Task lo
  pide como step explícito con el comando `grep` concreto.
- **Saneado obligatorio** (`skills/swarm-protocol/SKILL.md` §4.4) para CUALQUIER texto ajeno
  interpolado en un `--text`/`--fix`/`--line` de shell: backtick→`'`, borrar `$`, `"`→`'`, borrar
  `\`, colapsar saltos de línea. En esta fase el texto ajeno más peligroso es **la salida de `git
  log`** (mensajes de commit escritos por cualquiera, con backticks y `$(...)` normales en un mensaje
  técnico) — `release-manager` lo escribe con `Write`, nunca por shell, y `delivery-orchestrator`/la
  raíz lo sanean antes de cualquier `--line`.
- **Contrato universal de evidencia** (spec §6): línea 1 veredicto, línea 2
  `evidence: files=N cmds=M turns=k/max` (la línea TERMINA ahí, sin texto detrás), resto hallazgos.
  `OK`/`DONE` con `files=0` se rechaza siempre.
- **Convención de nombre estable** (`skills/swarm-protocol/SKILL.md` §2bis): cada agente se lanza
  NOMBRADO con su rol exacto (`release-manager`, `handoff-writer`, `delivery-orchestrator`).
- Cada tarea termina en su **propio commit**, con identidad git personal (`git config user.email`
  debe imprimir `garcia.gordo.david@gmail.com` — comprobar ANTES del primer commit de la fase).
- `bash tests/run.sh` en verde al final de CADA tarea. **42 ficheros de test hoy → 49 al cerrar la
  fase**; cada tarea declara su `files: N` esperado.

## Rulings de esta sesión (decisiones tomadas al escribir el plan — el owner puede revertirlas)

> El spec es MÁS ESCUETO en §7 "Entrega" que en cualquier dominio anterior: tres filas de tabla y
> media línea de §15. Casi todo el contrato de este dominio son rulings. Se marcan aquí en bloque
> para que el owner los apruebe o los tumbe ANTES de ejecutar, no después. Los rulings 2, 3, 4 y 5
> son los de mayor radio de alcance de todo el proyecto: son los que gobiernan un `git push` real.

1. **`delivery-orchestrator` NUNCA encadena automáticamente.** Igual que
   `implementation-orchestrator` (§10.1 de `agents/orchestrator.md`), y por la misma razón elevada
   al cuadrado: si "escribir y fusionar código real" merece un checkpoint humano, "publicar ese
   código donde otras personas lo ven y lo mergean" lo merece más. La raíz lanza el dominio **solo**
   con una invocación explícita y separada del owner ("publica la rama X", "abre el PR de Y",
   "prepara la release"). Nunca como continuación de implementation, ni en `tier: full`.
   Coste si el ruling está mal: el owner teclea un `/swarm:run` extra.

2. **La autorización de un push real es MÁS ESTRICTA que la de `dependency-installer`, en tres ejes
   simultáneos.** El precedente (`approved:` construido solo por la raíz vía `AskUserQuestion`, nunca
   inferido, la hoja rechaza sin él) se conserva ENTERO y se le añaden tres capas, porque el radio de
   alcance es mayor y menos reversible (un merge local se deshace; un push a un remoto compartido, o
   un PR que otra persona mergea, no siempre):
   - **(a) La aprobación NOMBRA el destino exacto, no dice "sí".** La línea es
     `approved-push: remote=<remote> branch=<branch> base=<base>` — los tres campos, en ese orden,
     con esa sintaxis literal `clave=valor`. Un `approved-push: sí` / `approved-push: adelante` /
     una línea con dos campos → `BLOCKED aprobación de push malformada`, sin ejecutar nada.
   - **(b) Preview ANTES de la aprobación, dos invocaciones separadas.** Igual que
     `dependency-installer` nunca instala sin que el owner haya visto la lista itemizada de
     paquetes, aquí el owner ve, ANTES de decidir, los comandos LITERALES (`git push …`,
     `gh pr create …`), la URL del remoto, el nombre de la rama base, el número de commits que
     viajan y el estado del verde. Fase A no ejecuta ninguno de esos comandos.
   - **(c) Re-verificación contra la realidad justo antes de empujar.** La hoja no confía en su
     propia cabecera: comprueba `git rev-parse --abbrev-ref HEAD` == `branch`, que `git remote -v`
     contiene `remote` con la MISMA URL que se previsualizó, y que `branch` != `base` y no es una
     rama protegida. Cualquier discrepancia → `BLOCKED aprobación no coincide con el estado real`.
     Esto cierra la ventana entre el preview y el push (el owner pudo cambiar de rama mientras
     decidía).
   - **(d) Y por debajo de todo, un backstop DETERMINISTA en `hooks/bash-guard.py`** (Task 1), no
     prosa: `git push` sin `<remote> <rama>` explícitos, a una rama protegida, con `--force`/
     `--delete`/`--mirror`/`--all`/`--tags`, o con refspec `+`/`:dst` vacío → **denegado para
     cualquier agente**. Mismo patrón que el backstop `composer update` de fase 5b: la prosa dice
     qué hacer, el guard hace imposible lo contrario.
   - **(e) La MISMA forma se reutiliza para la otra mutación externa del dominio** (crear un remoto,
     ruling 3): `approved-remote: action=create name=<repo> visibility=<public|private>` o
     `approved-remote: action=use url=<url>`. No se inventa un mecanismo distinto: mismo sitio donde
     se construye (solo la raíz, tras `AskUserQuestion`), mismo preview literal ANTES de preguntar,
     misma cabecera `clave=valor` que NOMBRA el destino, mismo rechazo (`BLOCKED sin aprobación de
     remoto` / `BLOCKED aprobación de remoto malformada`) cuando falta o está malformada, mismo
     backstop determinista por debajo (Task 1). Dos aprobaciones distintas para dos mutaciones
     distintas: una NUNCA vale por la otra, y `approved-push:` no autoriza a crear nada.

3. **Sin remoto configurado ⇒ `BLOCKED` en la hoja, y una PREGUNTA REAL en la raíz — no el final del
   run.** *(Reescrito el 2026-09-03 tras la revisión del owner: la versión original terminaba el run
   en seco con el `BLOCKED`; el owner pidió literalmente "preguntar al usuario qué quiere hacer, en
   este caso crea un repo nuevo público en mi cuenta y súbelo tú mismo".)* Verificado EN VIVO en este
   repo: `git remote -v` no imprimía nada — el repo del plugin no tenía remoto. El ruling tiene dos
   mitades, y solo la segunda cambia:
   - **En la hoja, nada cambia.** `release-manager` comprueba el remoto en sus primeros comandos,
     antes de escribir notas o de mirar nada más, y si no hay ninguno su veredicto es
     `BLOCKED sin remoto configurado` con la línea de hint literal `- hint: git remote add origin
     <url>` y CERO mutaciones. Sin remoto no puede empujar: eso es un hecho, no una decisión.
     Alternativa considerada y descartada: hacer igualmente el trabajo local (notas, verde) y
     devolver un aviso — descartada porque deja artefactos huérfanos de un flujo que no puede
     terminar, y porque contradice el precedente gate-first de `dependency-installer`.
   - **En la raíz, ese motivo concreto abre un `AskUserQuestion`.** `sin remoto configurado` es el
     ÚNICO `BLOCKED` del dominio que la raíz NO propaga y cierra: es una precondición que el owner
     puede resolver ahora mismo, no un error. La raíz pregunta (§12.2bis): (a) crear un repositorio
     nuevo en GitHub bajo su cuenta y usarlo como `origin`, (b) usar un remoto que ya tiene (URL por
     texto libre en "Other"), (c) nada — se queda `BLOCKED` y el run termina honestamente. Con (a) o
     (b), la raíz construye `approved-remote:` (ruling 2e) y relanza el dominio con
     `operation: configure-remote`; **la raíz NO ejecuta `gh repo create` ella misma** (spec §3.2
     regla 4: la raíz nunca ejecuta trabajo de hoja, y de hecho no tiene `gh` en su allowlist —
     verificado en `hooks/bash-allowlist.json`). Quien muta es `release-manager`, con su gate.
   - **Preview ANTES de preguntar, como en el push.** Quien conoce la cuenta autenticada y el nombre
     del repo es la hoja, no la raíz: por eso el `BLOCKED sin remoto configurado` de fase A trae ya
     las líneas `- cuenta gh:` y `- remoto propuesto: <el comando literal>`. El owner ve el nombre
     exacto, la visibilidad y el comando ANTES de decidir — nunca después.
   - **Tras crear el remoto, el owner RE-INVOCA; no se encadena solo.** Razón fuerte, no
     conservadurismo: una `approved-push:` NOMBRA remoto, rama y base (ruling 2a), y en el momento en
     que el owner aprobó el remoto **la base todavía no existía** en ningún sitio. Encadenar el push
     dentro del mismo run exigiría fabricar una aprobación para un destino que nadie ha visto — que
     es exactamente lo que el ruling 2 prohíbe. Así que `configure-remote` termina en `DONE` con la
     línea `- siguiente: vuelve a lanzar la entrega ahora que <remote> existe`, y el owner teclea un
     `/swarm:run` más. Coste si el ruling está mal: una invocación extra.

4. **"Merge en verde" = la suite local está VERDE antes de empujar. Nunca = auto-mergear el PR.**
   La lectura literal del spec ("rama, PR, changelog, merge en verde") admite dos interpretaciones y
   una de ellas es catastrófica: esperar al CI y mergear el PR solo destruiría el propósito del PR
   (que una persona lo revise) y sería una propiedad de seguridad ESTRICTAMENTE PEOR que todo lo
   construido hasta ahora. Se adopta la otra: **verde local, comprobado por `release-manager` con el
   comando `test` del stack pack activo, como precondición del preview de push.** Tres estados, tres
   comportamientos distintos y honestos:
   - suite existe y pasa → preview normal, `- verde: <comando> OK`;
   - suite existe y **falla** → `KO tests en rojo: <resumen>`, sin preview, sin aprobación posible;
   - **no hay pack, o el pack no declara `test`, o el comando lo deniega el guard** → hay preview,
     pero con la línea `- warn: sin suite ejecutable — verde NO verificado`, y la raíz está obligada
     (Task 6) a reproducir ese warning DENTRO del texto de la opción de `AskUserQuestion`, para que
     el owner apruebe con los ojos abiertos. "Desconocido" nunca se presenta como "verde".

5. **`release-manager` publica la rama en la que YA está; nunca hace checkout, nunca crea commits.**
   No tiene `git checkout`/`git switch`/`git add`/`git commit`/`git merge`/`git tag` en su allowlist,
   a propósito. Consecuencias buscadas: (a) lo que se empuja es EXACTAMENTE lo que el owner ya tiene
   commiteado y pudo revisar — el agente no puede colar un commit propio en la publicación; (b) el
   árbol de trabajo del owner nunca se mueve bajo sus pies; (c) si `HEAD` es `master`/`main`/
   `develop`/`trunk` o coincide con la base, el veredicto es
   `BLOCKED HEAD en rama protegida, nada que publicar` con el hint `git switch -c <rama>` — publicar
   `master` sobre `master` no es un caso de uso, es el accidente que este dominio existe para
   impedir. Lectura del "rama" del spec §7: `release-manager` **valida y nombra** la rama a publicar,
   no la fabrica. Marcado como revisable: si el owner quiere que cree `release/<slug>` desde HEAD, es
   un cambio acotado a la fase A.

6. **El árbol debe estar limpio.** `git status --porcelain` no vacío → `BLOCKED árbol sucio: <n>
   ficheros`. Empujar una rama cuyo árbol local tiene cambios sin commitear publica un estado que no
   se corresponde con lo que el owner ve, y `release-manager` no puede commitearlos (ruling 5).

7. **`release-manager` NO edita el `CHANGELOG.md` del repo.** Escribe **notas de release** en
   `.swarm/run/<run-id>/release-notes.md` (con `Write`, nunca por shell) a partir de
   `git log --no-merges --format=%s <base>..HEAD`, y ese fichero es el `--body-file` del PR. Razones:
   (a) editar un changelog exige una política de numeración de versiones que el plugin no puede
   inferir de un repo cualquiera; (b) la entrada de changelog por fase ya es responsabilidad de
   `doc-writer` (spec §7, dominio implementation) y duplicarla rompe el principio 1 ("un agente, una
   responsabilidad"); (c) `.swarm/` está gitignorado, así que el artefacto no ensucia el diff que se
   publica. Desviación consciente de la palabra "changelog" de la fila del spec, marcada como
   revisable.

8. **`gh` es opcional y su ausencia NUNCA es un fallo.** Ya está declarado `required: false` en
   `requirements.json` (verificado), así que `/swarm:doctor` ya avisa de su ausencia sin bloquear. Si
   `gh auth status` falla o `gh` no está, `release-manager` **igualmente empuja la rama** (que es la
   parte irreversible y valiosa) y devuelve `DONE` con las dos líneas de degradación:
   `- pr manual: <url del remoto> · rama <branch> → base <base>` y
   `- pr comando: gh pr create --base <base> --head <branch> --title "<t>" --body-file <ruta>`.
   No se fabrica una URL de "compare" a partir del remoto: las formas `ssh://`, `git@host:owner/repo`,
   `https://` y `file://` no se parsean igual y una URL inventada que lleva a ningún sitio es peor que
   un comando exacto que el owner puede pegar. `gh pr merge` está denegado por el guard (ruling 2d).

9. **`handoff-writer` escribe el MD y NO lo commitea.** Mismo criterio que `dependency-installer`
   (ruling 3 de fase 5b): un fichero visible y sin commitear es mejor que un commit que nadie revisó,
   y el fichero sobrevive a la sesión igual (no vive en un worktree que se borra). Ruta: reutiliza
   `docs/superpowers/handoffs/` si ese directorio ya existe en el repo (caso de este repo), si no
   `docs/handoffs/`, y si `docs/` no existe, `.swarm/run/<run-id>/handoff.md` como último recurso —
   nunca crea una convención de directorios que el repo no tenga en su raíz.

10. **`handoff-writer` corre en TODOS los caminos terminales del dominio**, incluido
    `BLOCKED sin remoto configurado` y "el owner dijo que no". Cuesta haiku × ≤8 turnos y es
    justamente cuando el estado es confuso cuando un relevo escrito vale más. La forma del documento
    calca la de `docs/superpowers/handoffs/2026-09-02-next-session.md` (secciones "Prompt copy-paste
    para la sesión nueva", "Dónde está todo", "Siguiente paso"), acotada a lo que este run sabe.

11. **La raíz relanza el dominio en fase B con un `Agent` FRESCO, no con `SendMessage` al vivo.**
    Va en contra de la regla general "continuar un agente vivo conserva contexto", y es deliberado:
    la aprobación tiene que viajar en una **cabecera de lanzamiento** que la hoja pueda verificar como
    dato de entrada, y un relanzamiento limpio garantiza que la fase B re-ejecuta TODAS las
    validaciones (ruling 2c) en vez de confiar en un estado que el orquestador creía tener. El coste
    (unos turnos repetidos de validación) se paga a cambio de determinismo en la acción más
    consecuente del enjambre.

12. **`/swarm:status` y `/swarm:findings`: script determinista como camino PRIMARIO, con un fallback
    inline acotado para el residual.** *(Reescrito el 2026-09-03: la versión original era "no llevan
    modelo, punto"; el owner respondió "lo que sea más óptimo, puede ser como subagente con un
    fallback determinista".)* La regla vinculante del proyecto
    (`~/.claude/rules/common/orchestration-and-tokens.md`) es "herramienta determinista = ejecútala,
    NO le pongas modelo delante… un modelo SOLO para el residual que la herramienta no puede
    auto-arreglar, y en el tier más barato que sirva". Así que el orden es ése, no el inverso:
    - **Primario (el 100% del caso común, cero modelo):** los dos scripts deterministas
      (`scripts/swarm-status.sh`, `scripts/swarm-findings.sh`), cuya salida el comando reporta tal
      cual — el patrón ya probado de `/swarm:init` con `swarm-init.sh`. `exit 0` (salida normal),
      `exit 1` (no hay `.swarm/`) y `exit 64` (filtro inválido) son casos que el script ya resuelve
      ÉL, y el comando NO llama a ningún modelo en ninguno de los tres.
    - **Fallback (residual, y solo con `exit` ∉ {0,1,64}):** el script no ha podido interpretar los
      datos de forma determinista y lo dice con `exit 2` (o ha reventado: `python3` ausente → 127,
      un `.swarm/` ilegible → traceback). Entonces —y solo entonces— el comando lee él mismo un
      puñado acotado de ficheros de `.swarm/` y da un resumen best-effort, SIEMPRE precedido de la
      línea `- warn: modo degradado — <script> falló (exit <n>)`. Un resultado degradado jamás se
      presenta como el normal.
    - **El fallback es INLINE en el fichero del comando, no un subagente nuevo.** Justificación
      (Task 5 Step 9): el caso es de dos disparadores conocidos y se resuelve con ≤3 `Read` y ocho
      líneas de salida; un agente nuevo costaría frontmatter, entrada de allowlist, contrato de
      veredicto, cobertura en `test_agents_frontmatter.sh`/`test_verdict_templates_valid.sh` y un
      spawn con registro en el manifest — todo ello para un camino que en operación normal no se
      recorre nunca. Y el ahorro real no es "un modelo barato en cada llamada" sino **cero modelo en
      cada llamada**, que es estrictamente mejor. El precedente de comando que hace `Bash`+`Read` sin
      subagente ya existe (`commands/doctor.md` declara `Agent, Read, Bash, SendMessage`).
    El filtro de `/swarm:findings` se valida
    **en el script** (`[A-Za-z0-9_-]+`, si no `exit 64`), que es la defensa autoritativa: un comando
    de slash NO pasa por `hooks/bash-guard.py` (el guard solo actúa sobre `agent_type` que empieza por
    `swarm:`), así que el argumento del usuario no puede depender de una instrucción en prosa.

13. **`release-manager` recibe los runners de test por prefijo de DOS palabras, nunca `php`/`npm`/
    `composer` a secas.** Es el agente con `git push`: darle además ejecución arbitraria de código
    sería regalar la llave entera. Sus prefijos son un conjunto cerrado de runners
    (`php vendor/bin/phpunit`, `php vendor/bin/paratest`, `composer test`, `npm test`, `make test`,
    `go test`, `cargo test`, `pytest`). Si el comando `test` del pack activo no casa con ninguno, el
    guard lo deniega y el caso cae en el tercer estado del ruling 4 ("verde NO verificado"), nunca en
    un falso verde.

14. **La identidad de `gh` y la de `git` pueden NO coincidir, y `release-manager` NUNCA reinterpreta
    el error: lo devuelve LITERAL.** *(Ruling nuevo, 2026-09-03, de un fallo REAL reproducido en vivo
    en esta misma sesión al crear el repo de este proyecto.)* Lo que pasó: `gh auth status` daba como
    cuenta ACTIVA `davidgarciagordo` (la personal), `gh repo create --push` dejó el remoto como
    `git@github.com:<owner>/<repo>.git`, y el `git push` falló con
    `Permission ... denied to DavidClasslife` — porque el host `github.com` a secas resuelve por el
    `Host github.com` por defecto de `~/.ssh/config`, atado a OTRA clave (la de Classlife), mientras
    la clave personal vive bajo el alias `github-personal-david`. Se arregló a mano con
    `git remote set-url origin git@github-personal-david:<owner>/<repo>.git`. Consecuencias de
    diseño:
    - **Emparejamiento asumido y documentado** en todo este flujo: cuenta personal de GitHub
      (`davidgarciagordo`) + email de git personal (`garcia.gordo.david@gmail.com`), nunca la de
      Classlife (memoria de proyecto "Git identity personal"). `release-manager` lo **reporta**
      (`- cuenta gh: <login> (activa) · git user.email: <email>`) para que una discrepancia sea
      visible ANTES de aprobar; no lo corrige.
    - **`release-manager` NO construye ni reescribe URLs de remoto.** Deja que
      `gh repo create --source=. --remote=origin --push` ponga la URL y luego **verifica** el
      resultado. No tiene `git remote set-url` (denegado por el guard, y sigue denegado): reescribir
      la config de git del owner por su cuenta es justo el "arreglo" silencioso que este proyecto
      prohíbe.
    - **Opción elegida: (b), superficie el error crudo.** Se descartó (a) "detectar y arreglar el
      alias SSH": exigiría parsear `~/.ssh/config` (con `Include`, `Match`, wildcards), adivinar qué
      alias corresponde a qué cuenta, y aun así escribir en la config del owner — mucho esfuerzo,
      poco fiable, y muta algo que no es del run. (b) es barato y honesto: el veredicto lleva **el
      texto literal de `git`/`gh`, sin recortar ni reformular**
      (`BLOCKED remoto creado pero push rechazado: <stderr literal>`) más una línea de hint que
      NOMBRA este modo de fallo, para que el owner lo diagnostique de un vistazo y sea ÉL quien mute
      su config.
    - **Ningún `KO`/`BLOCKED` de este dominio "traduce" un error de `git` o de `gh`.** El recorte a
      ≤60 caracteres vale para el resumen de una suite de tests (ruling 4), no para un error de
      credenciales o de permisos: ahí el valor está exactamente en el texto íntegro. Excepción
      explícita al recorte, documentada en la sección "Errores de `git`/`gh`: literales, nunca
      reinterpretados" de `agents/release-manager.md` (Task 2).

---

### Task 1: Backstop determinista de `git push`/`gh`/`git remote` en `hooks/bash-guard.py` + allowlist de los 3 agentes nuevos

**Files:**
- Modify: `hooks/bash-guard.py`
- Modify: `hooks/bash-allowlist.json`
- Modify: `skills/pack-php-ddd-symfony8/commands.md` (columna `ejecutor` de la fila `test`)
- Create: `tests/test_push_guard.sh`
- Create: `tests/test_bash_allowlist_delivery.sh`

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces:
  - Entradas de allowlist para `swarm:delivery-orchestrator`, `swarm:release-manager`,
    `swarm:handoff-writer`. Las Tasks 2-4 documentan comandos que dependen EXACTAMENTE de estos
    prefijos.
  - Reglas nuevas de `hooks/bash-guard.py`: `PUSH_DENIED_FLAGS`, `PROTECTED_REFS`,
    `SUBCOMMAND_DENIED_ARGS`, `SUBCOMMAND_ALLOWED_ARGS`, `GH_REPO_CREATE_ALLOWED_FLAGS`, funciones
    `_push_dst(ref)`, `push_segment_denied(words)`, `remote_add_segment_denied(words)` y
    `gh_repo_create_denied(words)`. Aquí quedan fijadas las **tres únicas formas mutantes permitidas**
    en todo el plugin:
    - `git push <remote> <rama>` — dos palabras posicionales, sin flags destructivos, destino no
      protegido (Task 2 documenta esa forma literal y no otra);
    - `git remote add <nombre> <url>` — exactamente dos posicionales y **cero flags** (Task 2b);
    - `gh repo create <nombre> [flags de un conjunto cerrado]` (Task 2b).
    Todo lo demás de `git remote` y de `gh repo` sigue denegado para cualquier agente.

- [ ] **Step 1: Escribir el test del guard (falla primero)**

```bash
cat > tests/test_push_guard.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_push_guard.sh — backstop DETERMINISTA de la fase 6: el dominio delivery es el primero
# con `git push` real, y su seguridad no puede depender solo de la prosa de agents/release-manager.md.
#
# Mismo patrón que el backstop `composer update` de fase 5b (BARE_TWO_WORD_DENIED): la prosa dice qué
# hacer, el guard hace imposible lo contrario. Aquí se deniega, para CUALQUIER agent_type:
#   - `git push` sin `<remote> <rama>` explícitos (la forma bare empuja al upstream configurado, que
#     el agente no controla ni ha previsualizado);
#   - push a una rama protegida (master/main/develop/trunk), en cualquiera de sus formas de refspec
#     (`master`, `HEAD:master`, `refs/heads/master`);
#   - flags destructivos (--force/-f/--force-with-lease/--delete/--mirror/--all/--prune/--tags) y sus
#     variantes con `=` y en cluster de flags cortos (`-fu`);
#   - refspec con `+` (force implícito) o con destino vacío (`:rama` = borrado remoto);
#   - `gh pr merge|close|edit|ready|review|reopen|comment|lock|unlock|checkout` (auto-merge de un PR
#     es la propiedad de seguridad que esta fase existe para NO tener), `gh auth login|logout|...`,
#     y los subcomandos DESTRUCTIVOS de `git remote` (set-url/rename/remove/prune/...).
#
# Y las dos únicas formas mutantes que el bootstrap de remoto necesita (ruling 3, Task 2b), cada una
# acotada a su forma exacta para que un flag no la convierta en otra cosa:
#   - `git remote add <nombre> <url>`: exactamente dos posicionales y CERO flags. `git remote add` es
#     aditivo (falla si el nombre ya existe, así que no puede pisar un remoto del owner), pero
#     `--mirror=push` lo convertiría en un remoto que borra ramas en cada push: por eso, cero flags.
#   - `gh repo create <nombre> [flags de un conjunto CERRADO]`: `--public`/`--private`/`--source`/
#     `--remote`/`--push`/`--description`. Cualquier otro flag (`--template`, `--clone`, `--team`…)
#     deniega el segmento entero. `gh repo` sin `create` detrás sigue denegado por completo.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

A=swarm:release-manager

# --- la ÚNICA forma permitida ---
assert_eq "allow" "$(guard $A 'git push origin feature/export-csv')" "the one allowed push form: git push <remote> <branch>"
assert_eq "allow" "$(guard $A 'git push origin release/2026-09')" "a slash in the branch name is fine"
assert_eq "allow" "$(guard $A 'git push -u origin feature/x')" "-u is not destructive, still two positionals"

# --- forma incompleta: nunca ---
assert_eq "deny"  "$(guard $A 'git push')" "bare git push (implicit upstream) is denied"
assert_eq "deny"  "$(guard $A 'git push origin')" "git push <remote> with no refspec is denied"
assert_eq "deny"  "$(guard $A 'git push origin feature/a feature/b')" "two refspecs at once is denied"

# --- ramas protegidas, en todas sus formas de refspec ---
assert_eq "deny"  "$(guard $A 'git push origin master')" "push to master is denied"
assert_eq "deny"  "$(guard $A 'git push origin main')" "push to main is denied"
assert_eq "deny"  "$(guard $A 'git push origin develop')" "push to develop is denied"
assert_eq "deny"  "$(guard $A 'git push origin trunk')" "push to trunk is denied"
assert_eq "deny"  "$(guard $A 'git push origin HEAD:master')" "push HEAD:master is denied (dst is what counts)"
assert_eq "deny"  "$(guard $A 'git push origin refs/heads/main')" "fully qualified protected ref is denied"
assert_eq "deny"  "$(guard $A 'git push origin feature/x:master')" "src:dst onto a protected dst is denied"

# --- refspecs peligrosos ---
assert_eq "deny"  "$(guard $A 'git push origin +feature/x')" "leading + (force refspec) is denied"
assert_eq "deny"  "$(guard $A 'git push origin :feature/x')" "empty src (remote branch deletion) is denied"

# --- flags destructivos y sus variantes ---
assert_eq "deny"  "$(guard $A 'git push --force origin feature/x')" "--force is denied"
assert_eq "deny"  "$(guard $A 'git push -f origin feature/x')" "-f is denied"
assert_eq "deny"  "$(guard $A 'git push -fu origin feature/x')" "-f inside a short-flag cluster is denied"
assert_eq "deny"  "$(guard $A 'git push --force-with-lease origin feature/x')" "--force-with-lease is denied"
assert_eq "deny"  "$(guard $A 'git push --force-with-lease=refs/heads/x origin feature/x')" "--flag=value form is denied too"
assert_eq "deny"  "$(guard $A 'git push --delete origin feature/x')" "--delete is denied"
assert_eq "deny"  "$(guard $A 'git push --mirror origin')" "--mirror is denied"
assert_eq "deny"  "$(guard $A 'git push --all origin')" "--all is denied"
assert_eq "deny"  "$(guard $A 'git push --tags origin feature/x')" "--tags is denied (v1 creates no tags)"

# --- gh: crear/leer sí, mergear/cerrar/mover el árbol NO ---
assert_eq "allow" "$(guard $A 'gh auth status')" "gh auth status is allowed (availability probe)"
assert_eq "allow" "$(guard $A 'gh pr create --base master --head feature/x --title T --body-file /tmp/n.md')" "gh pr create is allowed"
assert_eq "allow" "$(guard $A 'gh pr view 12')" "gh pr view is allowed"
assert_eq "deny"  "$(guard $A 'gh pr merge 12 --squash')" "gh pr merge is DENIED — a human merges the PR (permanent design property)"
assert_eq "deny"  "$(guard $A 'gh pr close 12')" "gh pr close is denied"
assert_eq "deny"  "$(guard $A 'gh pr edit 12 --title x')" "gh pr edit is denied"
assert_eq "deny"  "$(guard $A 'gh pr ready 12')" "gh pr ready is denied"
assert_eq "deny"  "$(guard $A 'gh pr checkout 12')" "gh pr checkout is denied (never moves the working tree)"
assert_eq "deny"  "$(guard $A 'gh auth login')" "gh auth login is denied (interactive, mutates credentials)"

# --- gh repo: SOLO `create`, y solo con su conjunto cerrado de flags (ruling 3, Task 2b) ---
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the one allowed gh repo form: create with closed flags"
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --public --source=. --remote=origin --push')" "--public is in the closed flag set too"
assert_eq "allow" "$(guard $A 'gh repo create owner/repo --public --source . --remote origin --push')" "the space form of a value flag is accepted (its value is consumed, not counted as a positional)"
assert_eq "deny"  "$(guard $A 'gh repo delete owner/repo')" "gh repo delete is denied (only create is reachable)"
assert_eq "deny"  "$(guard $A 'gh repo rename other')" "gh repo rename is denied"
assert_eq "deny"  "$(guard $A 'gh repo edit --visibility public')" "gh repo edit is denied"
assert_eq "deny"  "$(guard $A 'gh repo clone owner/repo')" "gh repo clone is denied (writes a tree the owner did not ask for)"
assert_eq "deny"  "$(guard $A 'gh repo')" "bare gh repo is denied (no third word at all)"
assert_eq "deny"  "$(guard $A 'gh repo create owner/repo --template evil/repo')" "an out-of-set flag denies the whole segment (flag injection)"
assert_eq "deny"  "$(guard $A 'gh repo create owner/repo --clone')" "--clone is not in the closed set"
assert_eq "deny"  "$(guard $A 'gh repo create')" "gh repo create with no repo name is denied"
assert_eq "deny"  "$(guard $A 'gh repo create a b')" "two positionals after create is denied (one name, exactly)"

# --- git remote: leer sí; `add` sí en su forma exacta; el resto de mutantes NO ---
assert_eq "allow" "$(guard $A 'git remote -v')" "git remote -v is allowed"
assert_eq "allow" "$(guard $A 'git remote get-url origin')" "git remote get-url is allowed"
assert_eq "allow" "$(guard $A 'git remote add origin https://example.com/x.git')" "git remote add <name> <url> is allowed (additive: fails if the name exists)"
assert_eq "deny"  "$(guard $A 'git remote add --mirror=push origin https://example.com/x.git')" "--mirror=push would turn every push into a destructive one: denied"
assert_eq "deny"  "$(guard $A 'git remote add -f origin https://example.com/x.git')" "no flags at all on git remote add"
assert_eq "deny"  "$(guard $A 'git remote add origin')" "git remote add with no URL is denied"
assert_eq "deny"  "$(guard $A 'git remote set-url origin https://example.com/x.git')" "git remote set-url is denied (never rewrites the owner's remote — ruling 14)"
assert_eq "deny"  "$(guard $A 'git remote -v set-url origin https://example.com/x.git')" "git remote -v set-url … is denied too (a leading flag does not hide the subcommand)"
assert_eq "deny"  "$(guard $A 'git remote rename origin upstream')" "git remote rename is denied"
assert_eq "deny"  "$(guard $A 'git remote remove origin')" "git remote remove is denied"

# --- el backstop es GLOBAL: ningún otro agente gana push por tener el prefijo en el futuro ---
assert_eq "deny"  "$(guard swarm:implementation-orchestrator 'git push origin feature/x')" "implementation-orchestrator has no push at all"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git push origin feature/x')" "the domain orchestrator does NOT push — only its leaf does"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git push origin feature/x')" "handoff-writer never pushes"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the domain orchestrator creates no repository — only its leaf does"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git remote add origin https://example.com/x.git')" "the domain orchestrator adds no remote"
assert_eq "deny"  "$(guard swarm:orchestrator 'gh repo create owner/repo --private --source=. --remote=origin --push')" "the ROOT never runs leaf work: no gh at all (spec §3.2 rule 4)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_push_guard.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_push_guard.sh`
Expected: FAIL en las tres primeras aserciones `allow` (`swarm:release-manager` aún no existe en el
allowlist, cae al bloque `default` que no tiene `git push` ni `gh`) y FAIL en las de `gh`/`git remote`
que esperan `allow`. Las de `deny` pasarán ya (todo se deniega por defecto) — eso es esperado y no
demuestra nada todavía: solo el paso 4, con el allowlist ya puesto, convierte esos `deny` en la
prueba real del backstop.

- [ ] **Step 3: Añadir las reglas deterministas a `hooks/bash-guard.py`**

Justo DESPUÉS del bloque de constantes `BARE_TWO_WORD_DENIED` (que termina con el `}` de su dict),
inserta:

```python
# ── Delivery (fase 6): `git push` es la acción más consecuente e IRREVERSIBLE del enjambre ──
# Un merge local se deshace; un push a un remoto compartido, o un PR que otra persona mergea, no
# siempre. La prosa de agents/release-manager.md dice qué forma usar; esto hace imposible el resto,
# para CUALQUIER agent_type (presente o futuro), igual que BARE_TWO_WORD_DENIED con `composer update`.
PUSH_DENIED_FLAGS = (
    '--force', '-f', '--force-with-lease', '--force-if-includes',
    '--delete', '-d', '--mirror', '--all', '--prune', '--tags', '--follow-tags',
)

# Ramas cuyo destino NUNCA se empuja desde el enjambre. Extiende la guarda de 2 nombres que
# implementation-orchestrator aplica en local (backlog de fase 5a: `develop`/`trunk` no cubiertos).
PROTECTED_REFS = ('master', 'main', 'develop', 'trunk')

# Tercera palabra denegada para un prefijo de dos palabras ya permitido. Un prefijo de DOS palabras
# ("gh pr") no puede expresar "todo menos merge" — esto lo expresa. `gh pr merge` es la línea roja
# permanente del diseño (el PR lo mergea una persona); los mutantes DESTRUCTIVOS de `git remote` y
# `gh auth` cambian configuración del owner fuera del alcance de un run.
#
# `add` NO está en la lista de `git remote`: es la única forma que el bootstrap de remoto necesita
# (ruling 3) y es ADITIVA — `git remote add` falla si el nombre ya existe, así que no puede pisar un
# remoto del owner. Su forma exacta la fija `remote_add_segment_denied`. `set-url` SÍ sigue denegado:
# reescribir la URL de un remoto existente es justo lo que el ruling 14 prohíbe hacer en silencio.
SUBCOMMAND_DENIED_ARGS = {
    ('git', 'remote'): ('remove', 'rm', 'set-url', 'rename', 'set-head', 'prune', 'update'),
    ('gh', 'pr'): ('merge', 'close', 'edit', 'ready', 'review', 'reopen', 'comment', 'lock', 'unlock', 'checkout'),
    ('gh', 'auth'): ('login', 'logout', 'refresh', 'setup-git', 'token'),
}

# Inverso de SUBCOMMAND_DENIED_ARGS: para estos prefijos de dos palabras SOLO se permite un conjunto
# CERRADO de terceras palabras, y cualquier otra (incluida la ausencia de tercera palabra) se
# deniega. Denylist y allowlist no son intercambiables: `gh repo` tiene decenas de subcomandos y `gh`
# añade más en cada versión, así que enumerar lo prohibido envejece mal y falla ABIERTO. Aquí sólo
# `create` es alcanzable, y su forma la acota además `gh_repo_create_denied`.
SUBCOMMAND_ALLOWED_ARGS = {
    ('gh', 'repo'): ('create',),
}

# Conjunto CERRADO de flags de `gh repo create`. Lo que se protege aquí es la inyección de flags: el
# nombre del repo y la visibilidad los decide el owner (ruling 2e), pero un `--template`, un
# `--clone` o un `--team` convertirían "crea mi repo vacío" en otra cosa distinta. Lo que no está en
# esta tupla deniega el segmento entero.
GH_REPO_CREATE_ALLOWED_FLAGS = (
    '--public', '--private', '--source', '--remote', '--push', '--description',
)

# De los anteriores, los que llevan valor: hay que consumirlo para no contarlo como el nombre del
# repo cuando vienen en su forma con espacio (`--source .`).
GH_REPO_CREATE_VALUE_FLAGS = ('--source', '--remote', '--description')
```

Y justo ANTES de `def segment_allowed(...)`, las dos funciones:

```python
def _push_dst(ref):
    """Destino REAL de un refspec de push: el `dst` de `src:dst`, o el propio ref.

    `master`, `HEAD:master` y `refs/heads/master` son el mismo destino; comprobar solo la
    palabra literal dejaría pasar las dos últimas formas.
    """
    ref = ref[1:] if ref.startswith('+') else ref
    if ':' in ref:
        ref = ref.split(':', 1)[1]
    if ref.startswith('refs/heads/'):
        ref = ref[len('refs/heads/'):]
    return ref


def push_segment_denied(words):
    """True si este `git push` cae fuera de la ÚNICA forma permitida.

    Forma permitida: `git push <remote> <rama>` — exactamente dos palabras posicionales tras
    `git push`, sin flag destructivo, sin `+` de force, y con destino que no sea rama protegida.
    """
    for word in words[2:]:
        if word.split('=', 1)[0] in PUSH_DENIED_FLAGS:
            return True
        # cluster de flags cortos: `-fu` lleva `-f` dentro (mismo bug-class que INTERP_DENIED_FLAGS)
        if re.match(r'^-[A-Za-z]+$', word) and not word.startswith('--'):
            if any(len(f) == 2 and f[1] in word[1:] for f in PUSH_DENIED_FLAGS):
                return True
    positional = [w for w in words[2:] if not w.startswith('-')]
    if len(positional) != 2:
        return True
    ref = positional[1]
    if ref.startswith('+'):
        return True
    dst = _push_dst(ref)
    if not dst or dst in PROTECTED_REFS:
        return True
    return False


def subcommand_and_rest(words):
    """(subcomando, resto) de un segmento `<cmd> <grupo> …`.

    El subcomando es el PRIMER no-flag tras el grupo, no `words[2]` a secas: con `words[2]` fijo,
    `git remote -v set-url origin <url>` colaría por delante de SUBCOMMAND_DENIED_ARGS (el tercer
    palabro sería `-v`) y `git remote -v` legítimo dejaría de funcionar si se denegara todo flag.
    El `resto` lleva TODO lo demás —incluidos los flags que iban ANTES del subcomando—, para que
    los verificadores de forma no puedan saltarse un flag por su posición.
    """
    sub = None
    rest = []
    for word in words[2:]:
        if sub is None and not word.startswith('-'):
            sub = word
        else:
            rest.append(word)
    return sub, rest


def remote_add_segment_denied(rest):
    """True si este `git remote add` cae fuera de la ÚNICA forma permitida.

    Forma permitida: `git remote add <nombre> <url>` — exactamente dos palabras posicionales y CERO
    flags. `--mirror=push` convertiría el remoto en uno que BORRA ramas en cada push, y `-f`
    dispararía un fetch que nadie pidió: por eso no se permite ningún flag, no una lista de flags
    malos (fallar cerrado, igual que GH_REPO_CREATE_ALLOWED_FLAGS).
    """
    if any(w.startswith('-') for w in rest):
        return True
    return len(rest) != 2


def gh_repo_create_denied(rest):
    """True si este `gh repo create` cae fuera de la forma permitida.

    Forma permitida: exactamente UN posicional (el nombre `owner/repo` o `repo`) y flags
    únicamente del conjunto cerrado GH_REPO_CREATE_ALLOWED_FLAGS, en su forma `--flag`,
    `--flag=valor` o `--flag valor`. Se cuenta el posicional tras consumir el valor de los flags que
    lo llevan: sin eso, `--source .` metería `.` en la cuenta y la forma legítima se denegaría.
    """
    positional = []
    i = 0
    while i < len(rest):
        word = rest[i]
        if word.startswith('-'):
            name = word.split('=', 1)[0]
            if name not in GH_REPO_CREATE_ALLOWED_FLAGS:
                return True
            if name in GH_REPO_CREATE_VALUE_FLAGS and '=' not in word:
                i += 1  # consume el valor de la forma `--flag valor`
        else:
            positional.append(word)
        i += 1
    return len(positional) != 1
```

Y dentro de `segment_allowed`, inmediatamente DESPUÉS del bloque `if (len(words) >= 2 and
(command_word, words[1]) in BARE_TWO_WORD_DENIED ...): return False` y ANTES de
`denied_flags = INTERP_DENIED_FLAGS.get(command_word)`:

```python
    if len(words) >= 2 and (command_word, words[1]) == ('git', 'push'):
        if push_segment_denied(words):
            return False
    if len(words) >= 2:
        group = (command_word, words[1])
        allowed_sub = SUBCOMMAND_ALLOWED_ARGS.get(group)
        denied_sub = SUBCOMMAND_DENIED_ARGS.get(group)
        if allowed_sub is not None or denied_sub is not None:
            sub, rest = subcommand_and_rest(words)
            if allowed_sub is not None and sub not in allowed_sub:
                return False  # `gh repo` a secas, o con un subcomando que no sea `create`
            if denied_sub is not None and sub in denied_sub:
                return False
            if group == ('git', 'remote') and sub == 'add':
                if remote_add_segment_denied(rest):
                    return False
            if group == ('gh', 'repo') and sub == 'create':
                if gh_repo_create_denied(rest):
                    return False
```

- [ ] **Step 4: Añadir las 3 entradas nuevas a `hooks/bash-allowlist.json`**

Inserta estos tres bloques dentro del objeto `"agents"`, tras `"swarm:dependency-installer"` (el
orden no importa; así el fichero sigue la cronología de fases):

```json
    "swarm:delivery-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:release-manager": [
      "git status", "git log", "git diff", "git show", "git rev-parse", "git remote",
      "git push",
      "gh auth", "gh pr", "gh repo",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh",
      "php vendor/bin/phpunit", "php vendor/bin/paratest",
      "composer test", "npm test", "make test", "go test", "cargo test", "pytest"
    ],
    "swarm:handoff-writer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
```

Notas deliberadas:
- `swarm:release-manager` es el ÚNICO agente del plugin con `git push` y con `gh` — a propósito
  (ruling 2). `delivery-orchestrator` NO los tiene: el orquestador secuencia, no ejecuta trabajo de
  hoja (spec §3.2 regla 4). **La raíz tampoco los tiene** (`swarm:orchestrator` en el mismo fichero:
  `git status|log|diff|show|rev-parse`, `cd`, `ls|cat|head|tail|wc|grep`, `scripts/mem-*`) — por eso
  el `gh repo create` del ruling 3 lo ejecuta la hoja y no la raíz, aunque sea la raíz quien pregunta.
- `gh repo` entra por el bootstrap de remoto (ruling 3), y entra ACOTADO: el prefijo de dos palabras
  del allowlist solo abre la puerta, y `SUBCOMMAND_ALLOWED_ARGS` + `gh_repo_create_denied` la
  estrechan a `gh repo create <nombre>` con su conjunto cerrado de flags. Sin esas dos reglas, "gh
  repo" en el allowlist habría dado también `gh repo delete`.
- Los runners de test van por prefijo de DOS palabras (`php vendor/bin/phpunit`, `composer test`,
  `npm test`…), nunca `php`/`composer`/`npm` a secas (ruling 13): darle ejecución arbitraria al
  agente que además empuja sería regalar la llave entera. `pytest` es de una palabra porque el
  binario ES el runner.
- Ni `git add`, ni `git commit`, ni `git merge`, ni `git checkout`/`switch`, ni `git tag`, ni
  `git worktree` para nadie de este dominio (ruling 5).

- [ ] **Step 5: Escribir el test de allowlist por agente**

```bash
cat > tests/test_bash_allowlist_delivery.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_bash_allowlist_delivery.sh — allowlist de los 3 agentes del dominio delivery (fase 6),
# y la aserción estructural que importa: `git push` y `gh` existen en UN solo agente de todo el
# plugin. Un futuro autor que copie/pegue una entrada de allowlist rompe este test, no la producción.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"
ALLOWLIST="$PLUGIN_ROOT/hooks/bash-allowlist.json"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# --- release-manager: lee el repo, corre la suite del pack, empuja UNA rama, abre UN PR ---
assert_eq "allow" "$(guard swarm:release-manager 'git status --porcelain')" "release-manager can read the working tree state"
assert_eq "allow" "$(guard swarm:release-manager 'git remote -v')" "release-manager can list remotes"
assert_eq "allow" "$(guard swarm:release-manager 'git rev-parse --abbrev-ref HEAD')" "release-manager can read the current branch"
assert_eq "allow" "$(guard swarm:release-manager 'git log --no-merges --format=%s master..HEAD')" "release-manager can read the commit list"
assert_eq "allow" "$(guard swarm:release-manager 'php vendor/bin/phpunit')" "release-manager can run the pack test command"
assert_eq "allow" "$(guard swarm:release-manager 'composer test')" "release-manager can run composer test"
assert_eq "allow" "$(guard swarm:release-manager 'npm test')" "release-manager can run npm test"
assert_eq "allow" "$(guard swarm:release-manager 'make test')" "release-manager can run make test"
assert_eq "deny"  "$(guard swarm:release-manager 'php src/anything.php')" "release-manager does NOT get bare php (ruling 13)"
assert_eq "deny"  "$(guard swarm:release-manager 'composer install')" "release-manager does not touch dependencies"
assert_eq "deny"  "$(guard swarm:release-manager 'npm run build')" "release-manager does not get npm run (arbitrary scripts)"
assert_eq "deny"  "$(guard swarm:release-manager 'git commit -m x')" "release-manager NEVER creates commits (ruling 5)"
assert_eq "deny"  "$(guard swarm:release-manager 'git add -A')" "release-manager never stages anything"
assert_eq "deny"  "$(guard swarm:release-manager 'git merge feature/x')" "release-manager never merges"
assert_eq "deny"  "$(guard swarm:release-manager 'git checkout feature/x')" "release-manager never moves the working tree"
assert_eq "deny"  "$(guard swarm:release-manager 'git switch -c release/x')" "release-manager never creates/switches branches"
assert_eq "deny"  "$(guard swarm:release-manager 'git tag v1.0.0')" "release-manager creates no tags in v1"
assert_eq "deny"  "$(guard swarm:release-manager 'git worktree remove /tmp/x')" "release-manager owns no worktree"
# bootstrap de remoto (ruling 3): las dos formas mutantes que necesita, y nada más
assert_eq "allow" "$(guard swarm:release-manager 'gh repo create owner/repo --private --source=. --remote=origin --push')" "release-manager can create the repo the owner approved"
assert_eq "allow" "$(guard swarm:release-manager 'git remote add origin https://example.com/x.git')" "release-manager can add the origin the owner approved"
assert_eq "deny"  "$(guard swarm:release-manager 'gh repo delete owner/repo')" "…and nothing else under gh repo"
assert_eq "deny"  "$(guard swarm:release-manager 'git remote set-url origin https://example.com/x.git')" "…and never rewrites an existing remote URL (ruling 14)"

# --- delivery-orchestrator: secuencia, no ejecuta trabajo de hoja (spec §3.2 regla 4) ---
assert_eq "allow" "$(guard swarm:delivery-orchestrator 'git status --porcelain')" "delivery-orchestrator can read state"
assert_eq "allow" "$(guard swarm:delivery-orchestrator 'git rev-parse --show-toplevel')" "delivery-orchestrator can anchor to the repo root"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git push origin feature/x')" "delivery-orchestrator has NO push"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'gh pr create --base master --head feature/x')" "delivery-orchestrator opens no PR itself"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git merge feature/x')" "delivery-orchestrator merges nothing"
assert_eq "deny"  "$(guard swarm:delivery-orchestrator 'git commit -m x')" "delivery-orchestrator commits nothing"

# --- handoff-writer: read-only + Write nativo, cero mutación por shell ---
assert_eq "allow" "$(guard swarm:handoff-writer 'git log --oneline -20')" "handoff-writer can read recent history"
assert_eq "allow" "$(guard swarm:handoff-writer 'ls docs/superpowers/handoffs')" "handoff-writer can look for the handoffs directory"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git add -A')" "handoff-writer never stages (ruling 9)"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git commit -m x')" "handoff-writer never commits (ruling 9)"
assert_eq "deny"  "$(guard swarm:handoff-writer 'git push origin feature/x')" "handoff-writer never pushes"
assert_eq "deny"  "$(guard swarm:handoff-writer 'composer install')" "handoff-writer touches no package manager"

# --- aserción estructural: el privilegio vive en UN solo sitio ---
holders="$(python3 - "$ALLOWLIST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
buckets = dict(data.get('agents', {}))
buckets['default'] = data.get('default', [])
for name, prefixes in sorted(buckets.items()):
    for p in prefixes:
        if p == 'git push' or p == 'gh' or p.startswith('gh '):
            print("%s|%s" % (name, p))
PYEOF
)"
push_holders="$(echo "$holders" | grep -c '|git push$' || true)"
assert_eq "1" "$push_holders" "exactly ONE allowlist entry in the whole plugin grants git push"
assert_eq "0" "$(echo "$holders" | grep '|git push$' | grep -qx 'swarm:release-manager|git push' && echo 0 || echo 1)" "and that entry is swarm:release-manager"
gh_others="$(echo "$holders" | grep '|gh' | grep -v '^swarm:release-manager|' | wc -l | tr -d ' ')"
assert_eq "0" "$gh_others" "no agent other than release-manager gets any gh prefix"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_bash_allowlist_delivery.sh
```

- [ ] **Step 6: Añadir `release-manager` a la columna `ejecutor` de la fila `test` del pack**

En `skills/pack-php-ddd-symfony8/commands.md`, la fila `test` con PHPUnit declara hoy
`test-writer + implementer` como ejecutores. `release-manager` ejecuta ese MISMO comando para el
verde del ruling 4, así que la tabla tiene que nombrarlo (`tests/test_stack_pack.sh` valida fila a
fila que cada ejecutor declarado puede correr el comando de su fila):

```
| test | existe `phpunit.xml.dist` o `phpunit.xml` | `php vendor/bin/phpunit` | test-writer + implementer + release-manager |
| test | además existe `vendor/bin/paratest` (suite grande) | `php vendor/bin/paratest --processes=4` | implementer + release-manager |
```

(Los dos prefijos ya están en el allowlist del Step 4; sin este step, `tests/test_stack_pack.sh`
seguiría verde pero `release-manager` no aparecería como consumidor real del pack en su propio
contrato — y el paso 3 del arranque de Task 2 quedaría sin respaldo en la tabla.)

- [ ] **Step 7: Confirmar que los dos tests pasan**

Run: `bash tests/test_push_guard.sh && bash tests/test_bash_allowlist_delivery.sh`
Expected: sin `FAIL` en ninguno de los dos, exit 0.

- [ ] **Step 8: Grep de regresión (lección 8) — que el backstop no tenga un segundo sitio sin cubrir**

Run:
```bash
grep -n "push\|PROTECTED_REFS\|SUBCOMMAND_\|remote\|gh_repo" hooks/bash-guard.py
```
Expected: las constantes nuevas, las cuatro funciones (`_push_dst`, `push_segment_denied`,
`subcommand_and_rest`, `remote_add_segment_denied`, `gh_repo_create_denied`), y **exactamente un**
punto de llamada de cada una dentro de `segment_allowed`. Si aparece cualquier otra rama de código
que trate `git push`, `git remote` o `gh repo` por separado (no debería haberla), se unifica antes de
continuar — el bug de fase 5b fue exactamente esto: un fix aplicado en un sitio de dos.

Comprobación específica de esta versión del step (la que cierra el agujero de forma que la primera
redacción tenía): **el subcomando se resuelve con `subcommand_and_rest`, no con `words[2]`**. Con
`words[2]` fijo, `git remote -v set-url origin <url>` habría pasado por delante de
`SUBCOMMAND_DENIED_ARGS` (su tercera palabra es `-v`, no `set-url`) y `set-url` habría quedado
alcanzable pese a estar denegado — justo lo que el ruling 14 prohíbe. El test lo fija con la
aserción `git remote -v set-url … is denied`.

- [ ] **Step 9: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 44, failed: 0`.

- [ ] **Step 10: Commit**

```bash
git config user.email
git add hooks/bash-guard.py hooks/bash-allowlist.json skills/pack-php-ddd-symfony8/commands.md tests/test_push_guard.sh tests/test_bash_allowlist_delivery.sh
git commit -m "feat(delivery): backstop determinista de git push/gh + allowlist de los 3 agentes de fase 6"
```

(El `git config user.email` es la comprobación de identidad de las Global Constraints: debe imprimir
`garcia.gordo.david@gmail.com` ANTES de commitear.)

---

### Task 2: `release-manager` — la hoja que publica (y el gate de aprobación de push)

**Files:**
- Create: `agents/release-manager.md`
- Create: `tests/test_delivery_agents.sh`
- Modify: `hooks/validate-output.py` (exención por FORMA para las líneas de preview/PR)
- Modify: `tests/test_agent_bash_blocks_allowed.sh:41` (`AGENT_FILES`)
- Modify: `tests/test_verdict_templates_valid.sh:38` (`AGENT_FILES`)

**Interfaces:**
- Consumes: los prefijos de allowlist y el backstop de guard de Task 1. La forma de push permitida
  es exactamente `git push <remote> <rama>`.
- Produces (contrato que Tasks 4 y 6 deben respetar LITERALMENTE):
  - Cabecera de lanzamiento:
    ```
    run-id: <uuid|adhoc>
    swarm-root: <ruta absoluta de .swarm>
    operation: prepare-release | publish-release
    base: <rama base>                                  ← OPCIONAL
    pack: <ruta absoluta del pack>                     ← omitir si no hay pack
    approved-push: remote=<remote> branch=<branch> base=<base>   ← SOLO en publish-release
    ```
  - Líneas de salida que el orquestador y la raíz reenvían tal cual:
    `- preview push: …`, `- preview pr: …`, `- remote: …`, `- commits: …`, `- verde: …`,
    `- warn: sin suite ejecutable — verde NO verificado`, `- pushed: …`, `- pr: …`,
    `- pr manual: …`, `- pr comando: …`, `- notas: <ruta>`, `- hint: …`, y —solo en el camino "sin
    remoto"— `- cuenta gh: …` y `- remoto propuesto: …` (el preview del ruling 3, que la raíz
    convierte en su `AskUserQuestion` de §12.2bis).
  - Ruta del artefacto de notas: `<swarm-root>/run/<run-id|adhoc>/release-notes.md`.
  - **Task 2b añade una TERCERA operación a esta misma cabecera** (`operation: configure-remote` +
    `approved-remote:`) y las líneas `- remoto creado:`/`- siguiente:`. El contrato de aquí no
    cambia: se extiende.

- [ ] **Step 1: Escribir el test del agente (falla primero)**

```bash
cat > tests/test_delivery_agents.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_delivery_agents.sh — contrato de las hojas del dominio delivery (fase 6, spec §7
# "Entrega"). El foco no es la prosa: son las propiedades de seguridad que este dominio introduce
# por primera vez en el proyecto (push real, PR real) y que ninguna review de lectura garantiza.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

front_of() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body_of()  { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ─────────────────────────── release-manager ───────────────────────────
F="$PLUGIN_ROOT/agents/release-manager.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/release-manager.md exists"
front="$(front_of "$F")"; body="$(body_of "$F")"

assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "release-manager is sonnet (spec §7)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "release-manager has maxTurns 15 (spec §7)"
assert_eq "0" "$(has "$front" 'Write')" "release-manager has Write (release notes go through Write, never shell)"
assert_eq "1" "$(has "$front" 'AskUserQuestion')" "release-manager CANNOT ask the owner (spec §3.2 rule 7)"

# el gate de aprobación: forma literal, exigida, no inferible
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "documents the exact approval line shape"
assert_eq "0" "$(has "$body" 'BLOCKED sin aprobación de push')" "refuses to publish without the approval line"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación de push malformada')" "refuses a malformed approval (not a yes/no)"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación no coincide con el estado real')" "re-verifies the approval against reality before pushing"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "documents phase B"

# propiedades permanentes
assert_eq "0" "$(has "$body" 'BLOCKED HEAD en rama protegida')" "never publishes from a protected branch"
assert_eq "0" "$(has "$body" 'BLOCKED sin remoto configurado')" "handles the no-remote repo honestly (ruling 3)"
assert_eq "0" "$(has "$body" '- remoto propuesto:')" "the no-remote BLOCKED carries the preview the root needs to ask the owner (ruling 3)"
assert_eq "0" "$(has "$body" '- cuenta gh:')" "…and names the authenticated gh account, so an identity mismatch is visible before approving (ruling 14)"
assert_eq "0" "$(has "$body" 'sin recortar')" "raw git/gh errors are surfaced verbatim, never trimmed or reworded (ruling 14)"
assert_eq "0" "$(has "$body" 'BLOCKED árbol sucio')" "refuses to publish a dirty tree (ruling 6)"
assert_eq "0" "$(has "$body" 'KO tests en rojo')" "a red suite blocks the preview (ruling 4)"
assert_eq "0" "$(has "$body" 'verde NO verificado')" "an unknown suite is reported as unknown, never as green (ruling 4)"
assert_eq "0" "$(has "$body" 'gh pr merge')" "explicitly names the forbidden auto-merge"
assert_eq "0" "$(has "$body" 'Nunca commiteas')" "states it creates no commits (ruling 5)"

# el veredicto DONE nunca lleva sufijo (lección 7 del handoff de fase 5b)
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere (validate-output.py rejects it)"

# Las líneas de preview llevan un COMANDO completo con valores reales y pasan de 120 chars con
# total normalidad — el cap de narración de validate-output.py las rechazaría como prosa suelta.
# La exención es por FORMA (prefijo fijo + comando), igual que DISCOVERY_Q_RE/DISCOVERY_OTHER_RE:
# se comprueba contra el hook REAL, no leyendo el regex.
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"
hook_says() { # hook_says <agent_type> <message-json> -> "accept" | "reject"
  local out root
  root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-delivery-hook.XXXXXX")"
  out="$(SWARM_ROOT="$root/.swarm" python3 "$HOOK" <<PYIN
{"agent_type": "$1", "hook_event_name": "SubagentStop", "last_assistant_message": $2}
PYIN
)"
  rm -rf "$root"
  if echo "$out" | grep -q '"decision": "block"'; then echo reject; else echo accept; fi
}
long_pr='DONE\nevidence: files=2 cmds=6 turns=7/15\n- preview pr: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/1234-5678/release-notes.md'
assert_eq "accept" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$long_pr")")" "a long '- preview pr:' line is accepted (form-based exemption, not the 120-char cap)"
long_cmd='DONE\nevidence: files=2 cmds=9 turns=12/15\n- pr comando: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/1234-5678/release-notes.md'
assert_eq "accept" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$long_cmd")")" "a long '- pr comando:' line is accepted too"
narr='DONE\nevidence: files=2 cmds=6 turns=7/15\n- he terminado de preparar la entrega y creo que lo mejor sería revisar con calma el resultado antes de seguir adelante con el push'
assert_eq "reject" "$(hook_says swarm:release-manager "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1].replace("\\n", chr(10))))' "$narr")")" "plain long prose with a '- ' prefix is STILL rejected (the exemption is by form, not by dash)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_delivery_agents.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_delivery_agents.sh`
Expected: FAIL en la primera aserción (`agents/release-manager.md exists`) y en todas las que
dependen de leerlo.

- [ ] **Step 3: Escribir `agents/release-manager.md`**

Contenido COMPLETO del fichero (usa `Write`, no un heredoc: es contenido largo y estructurado —
lección 3 de las Global Constraints):

````markdown
---
name: release-manager
description: Use when delivery-orchestrator needs a branch published — phase A previews the exact push/PR commands after checking a clean tree, a real remote and a green local suite; phase B pushes and opens the PR only with an itemised approved-push: header naming remote, branch and base. Never merges a PR, never commits, never moves the working tree.
model: sonnet
tools: Read, Grep, Write, Bash, SendMessage
maxTurns: 15
memory: project
skills: [swarm-protocol]
---

# release-manager

Hoja del dominio delivery (spec §7 "Entrega": "rama, PR, changelog, merge en verde"). Eres el
**único agente de todo el enjambre con `git push` y con `gh`**, y por eso tu contrato es el más
estrecho del proyecto, por delante incluso del de `dependency-installer`: publicar código es la
acción menos reversible que puede hacer el enjambre (un merge local se deshace; un push a un remoto
compartido, o un PR que otra persona mergea, no siempre).

Trabajas en **dos fases separadas por una decisión humana**, y nunca haces la segunda sin la
primera:

| fase | `operation:` | qué haces | qué NO haces |
|---|---|---|---|
| A | `prepare-release` | validas, corres la suite, escribes las notas, **previsualizas** los comandos | ningún push, ningún PR, ningún commit |
| B | `publish-release` | re-verificas TODO y ejecutas el push + el PR | ningún merge de PR, ningún commit, ningún checkout |

## Lo que NUNCA haces (propiedades permanentes, no diferidos a v1.1)

- **Nunca mergeas un PR.** `gh pr merge` está fuera de tu allowlist y además lo deniega
  `hooks/bash-guard.py` por regla determinista. El PR lo revisa y lo mergea una persona: si te
  auto-mergearas, el PR dejaría de ser un gate y el dominio entero perdería su sentido.
- **Nunca commiteas** (no tienes `git add` ni `git commit`): publicas EXACTAMENTE los commits que el
  owner ya tiene y pudo revisar. No puedes colar trabajo propio en una publicación.
- **Nunca cambias de rama** (no tienes `git checkout`/`git switch`): el árbol de trabajo del owner no
  se mueve bajo sus pies. Publicas la rama en la que YA estás.
- **Nunca empujas a `master`/`main`/`develop`/`trunk`**, en ninguna forma de refspec.
- **Nunca creas tags** ni decides números de versión (fuera de alcance de v1).
- **Nunca reescribes la URL de un remoto que ya existe** (no tienes `git remote set-url`, y el guard
  lo deniega). Si una URL existente está mal, lo dices con el error literal y un hint; no la
  "arreglas" (ruling 14).
- **Nunca preguntas al owner** (no tienes `AskUserQuestion`, spec §3.2 regla 7). Quien pregunta es la
  RAÍZ; quien te trae su respuesta como línea de cabecera es `delivery-orchestrator`.

## Arranque (idéntico en TODAS tus operaciones)

1. `RUN`, `swarm-root:`, `operation:` de tu cabecera (protocolo §2). `base:` es opcional;
   `pack:` puede faltar (sin stack pack); `approved-push:` SOLO existe en `publish-release`.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/release-manager.md" 2>/dev/null
   ```
3. Ánclate a la raíz del repo (mismo motivo que `implementation-orchestrator`: cualquier ruta que
   construyas después tiene que ser absoluta):
   ```bash
   git rev-parse --show-toplevel
   ```
   (cuenta para `cmds=`). Guárdalo como `<repo-root>`.

## Validaciones, en ESTE orden — fallas antes de mutar nada

El orden importa: cada comprobación es más barata que la siguiente y todas van ANTES de escribir un
solo fichero. Si alguna falla, ese es tu veredicto y no sigues.

### 1. Árbol limpio

```bash
git status --porcelain
```
(cuenta para `cmds=`). Si imprime algo, tu veredicto es `BLOCKED árbol sucio: <n> ficheros sin commitear`
— no puedes commitearlos (ver "Lo que NUNCA haces") y publicar una rama cuyo árbol local no coincide
con lo publicado engaña al owner.

### 2. Remoto configurado

```bash
git remote -v
```
(cuenta para `cmds=`). Si no imprime NADA, no hay remoto: no puedes empujar y no hay nada que
aprobar. Ese es tu veredicto, **sin haber mutado nada** — pero **no lo devuelves pelado**: es el
único `BLOCKED` de este agente que la raíz convierte en una pregunta al owner (ruling 3), y la
pregunta solo puede ser concreta si tú le das el preview. Reúne los tres datos que la raíz no puede
obtener (no tiene `gh` en su allowlist) y devuélvelos en el propio veredicto:

```bash
gh auth status
```
(cuenta para `cmds=`; si `gh` no está o no hay sesión, la línea `- cuenta gh:` dice
`sin gh autenticado` y ya está — no es un error tuyo).

```bash
git log -1 --format=%ae
```
(cuenta para `cmds=`). **No uses `git config user.email`**: `git config` no está en tu allowlist y no
va a estarlo — es un comando de ESCRITURA (`git config core.pager <cualquier cosa>` sería ejecución
arbitraria disfrazada de lectura). El email del último commit responde a la misma pregunta —qué
identidad está firmando de verdad en este repo— con un comando que ya tienes (`git log`).

El nombre propuesto para el repo es el **basename de `<repo-root>`**, tal cual, sin inventar sufijos
ni slugs. La visibilidad **no la eliges tú**: la decide el owner, y por eso el preview la muestra
como el valor por defecto que se le va a proponer (`--private`), no como un hecho.

```
BLOCKED sin remoto configurado
evidence: files=1 cmds=5 turns=4/15
- hint: git remote add origin <url> y vuelve a lanzar la entrega
- cuenta gh: <login de la cuenta ACTIVA> (activa) · último commit firmado por: <email>
- remoto propuesto: gh repo create <login>/<basename de repo-root> --private --source=. --remote=origin --push
```

**Emparejamiento esperado en este repo** (ruling 14, memoria de proyecto "Git identity personal"):
cuenta `gh` personal (`davidgarciagordo`) con email de git personal
(`garcia.gordo.david@gmail.com`), nunca la cuenta ni el email de Classlife.

La línea `- remoto propuesto:` es un **preview literal, no una ejecución**: en esta operación no
corres ese comando bajo ningún concepto. Es exactamente el mismo patrón que `- preview push:` — el
owner ve el comando entero, con sus valores resueltos, ANTES de decidir, y quien decide es él.

**Si `- cuenta gh:` muestra una cuenta y un email que no casan** (por ejemplo cuenta personal y email
corporativo), NO lo arregles y NO lo escondas: la línea ya lo hace visible, y quien decide es el
owner (ruling 14).

Si hay varios remotos, usa el del `approved-push:` en fase B; en fase A, usa `origin` si existe y si
no el PRIMERO que liste `git remote -v`, y dilo explícitamente en la línea `- remote:` para que el
owner lo vea antes de aprobar.

### 3. Rama actual y rama base

```bash
git rev-parse --abbrev-ref HEAD
```
(cuenta para `cmds=`). Ese literal es `<branch>`. Si es exactamente `master`, `main`, `develop` o
`trunk`, tu veredicto es `BLOCKED HEAD en rama protegida, nada que publicar` con la línea
`- hint: git switch -c <rama-de-trabajo> antes de entregar`. Publicar `master` sobre `master` no es
un caso de uso: es el accidente que este dominio existe para impedir.

La base sale, por orden: (a) la línea `base:` de tu cabecera si viene; (b) si no,
```bash
git rev-parse --abbrev-ref <remote>/HEAD
```
(cuenta para `cmds=`), que imprime algo como `origin/master` — la base es lo que hay tras la barra.
Si ese comando falla (el remoto no tiene HEAD resuelto), tu veredicto es
`BLOCKED base indeterminada` con la línea
`- hint: git remote set-head <remote> -a, o pasa base: en la cabecera`. **No adivines `master`**: una
base equivocada abre un PR contra la rama equivocada.

Si `<branch>` == `<base>`, tu veredicto es `BLOCKED HEAD en rama protegida, nada que publicar`
(mismo caso: no hay diferencia que publicar).

### 4. Hay algo que publicar

```bash
git log --no-merges --format=%s <base>..HEAD
```
(cuenta para `cmds=`). Si no imprime ninguna línea, tu veredicto es `DONE` con la línea
`- nada que publicar: <branch> no tiene commits sobre <base>` — no es un error, no lances nada más.
El número de líneas es `<n-commits>` y su contenido son las notas del punto siguiente.

### 5. Verde local ("merge en verde", spec §7)

**"Merge en verde" significa: la suite local pasa ANTES de empujar.** NUNCA significa esperar al CI y
auto-mergear el PR — eso destruiría el propósito del PR y sería una propiedad de seguridad peor que
todo lo que el enjambre construye. Tres estados, tres comportamientos:

- **Hay `pack:`** → `Read` de `<pack>/commands.md` (cuenta para `files=`), busca la clave `test`,
  comprueba su condición (el fichero marcador que la fila declara, con `ls`) y ejecuta el comando de
  la fila, uno por llamada:
  ```bash
  php vendor/bin/phpunit
  ```
  (cuenta para `cmds=`). Exit 0 → `- verde: php vendor/bin/phpunit OK`. Exit distinto de 0 → tu
  veredicto es `KO tests en rojo: <primera línea de fallo, ≤60 caracteres>`, **sin preview y sin
  posibilidad de aprobación**. Una rama roja no se publica.
- **No hay `pack:`, el pack no declara `test`, o su condición no se cumple** (sin `phpunit.xml`,
  etc.) → NO inventes un comando de test. Sigues, pero con la línea literal
  `- warn: sin suite ejecutable — verde NO verificado` en tu salida. La raíz está obligada a
  reproducir ese warning en el texto de la pregunta al owner: "desconocido" nunca se presenta como
  "verde".
- **El comando del pack lo deniega el guard** (no casa con ninguno de tus prefijos de dos palabras)
  → mismo tratamiento que el caso anterior, con la línea
  `- warn: sin suite ejecutable — verde NO verificado` y, además,
  `- warn: comando de test del pack fuera del allowlist: <comando>` para que el hueco sea visible.

## Notas de release (el "changelog" de tu fila del spec)

**No editas el `CHANGELOG.md` del repo.** Editar un changelog exige una política de numeración de
versiones que no puedes inferir de un repo cualquiera, y la entrada de changelog por fase ya es
responsabilidad de `doc-writer` (dominio implementation) — duplicarla rompería el principio 1 del
spec. Lo que sí haces: escribes con `Write` (nunca por shell — el mensaje de un commit lleva
backticks y `$(...)` con total normalidad)

`<swarm-root>/run/<tu-run-id-o-adhoc>/release-notes.md`

con esta forma exacta:

```
# <branch> → <base>

<n-commits> commits, generados por swarm:release-manager (run <run-id>).

- <asunto del commit 1>
- <asunto del commit 2>
- …
```

Los asuntos son las líneas literales de `git log --no-merges --format=%s <base>..HEAD` del paso 4,
una por línea, sin reinterpretar. Ese fichero es el `--body-file` del PR. Está bajo `.swarm/`, que
`/swarm:init` deja gitignorado: no ensucia el diff que publicas.

**Título del PR**: si `<n-commits>` es 1, el asunto de ese commit; si es más de 1, el literal
`<branch>`. **Los dos son texto ajeno que viaja dentro de un `--title "…"` de un shell REAL**, así
que antes de construir el comando pásalo por el saneado de `skills/swarm-protocol/SKILL.md` §4.4
(backtick→`'`, borrar `$`, `"`→`'`, borrar `\`, colapsar saltos de línea). Un nombre de rama puede
llevar `$` y backtick legalmente; un asunto de commit, casi siempre.

## Fase A — `operation: prepare-release`: previsualizas, no ejecutas

Con las 5 validaciones pasadas y las notas escritas, tu turno TERMINA con el preview. **No ejecutas
ni `git push` ni `gh pr create` en esta fase**, ni siquiera en su forma `--dry-run`: el preview es un
texto, y el owner tiene que poder leerlo entero antes de que nada salga de su máquina.

```
DONE
evidence: files=2 cmds=6 turns=7/15
- remote: origin → git@github.com:owner/repo.git
- commits: 4 (master..feature/export-csv)
- verde: php vendor/bin/phpunit OK
- notas: /abs/.swarm/run/<run-id>/release-notes.md
- preview push: git push origin feature/export-csv
- preview pr: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/<run-id>/release-notes.md
```

Las líneas `- preview push:` y `- preview pr:` llevan el comando EXACTO que ejecutarías, con los
valores ya resueltos — no una plantilla. Son lo que la raíz enseña al owner.

## Fase B — `operation: publish-release`: gate, re-verificación, y solo entonces publicas

### Gate de aprobación (lo primero, antes de cualquier otra cosa)

Tu cabecera DEBE traer una línea con esta forma literal, tres campos `clave=valor` en este orden:

```
approved-push: remote=origin branch=feature/export-csv base=master
```

- Si **no viene** o viene **vacía**: `BLOCKED sin aprobación de push`, sin ejecutar NADA.
- Si viene pero **no tiene los tres campos con esa sintaxis** (por ejemplo `approved-push: sí`,
  `approved-push: adelante`, `approved-push: origin master`, o le falta `base=`):
  `BLOCKED aprobación de push malformada`, sin ejecutar NADA.

No hay excepción, ni siquiera si quien te lanza afirma que el owner ya dijo que sí: la aprobación
válida es esta línea, con los tres destinos NOMBRADOS. Un "sí" no es una aprobación de push — un
"sí" no dice a qué remoto, desde qué rama ni contra qué base. **Tú no puedes preguntar al owner** y
`delivery-orchestrator` tampoco: quien pregunta es la RAÍZ (spec §3.2 regla 7).

```
BLOCKED sin aprobación de push
evidence: files=0 cmds=0 turns=1/15
```

### Re-verificación contra la realidad (cierra la ventana entre el preview y el push)

Repite las validaciones 1-4 del arranque (son baratas) y además comprueba que la aprobación describe
el mundo real AHORA, no el de hace dos minutos — el owner pudo cambiar de rama mientras decidía:

- `git rev-parse --abbrev-ref HEAD` debe imprimir exactamente el `branch=` aprobado;
- el `remote=` aprobado debe existir:
  ```bash
  git remote get-url origin
  ```
  (cuenta para `cmds=`; sustituye `origin` por el remoto aprobado);
- el `base=` aprobado no puede ser igual al `branch=`;
- el `branch=` no puede ser `master`/`main`/`develop`/`trunk`.

Cualquier discrepancia → `BLOCKED aprobación no coincide con el estado real` con una línea
`- discrepancia: <campo> aprobado <x>, real <y>`. No "corriges" la aprobación por tu cuenta: una
aprobación que no describe la realidad no es una aprobación.

### Push (un comando, en su propia llamada)

```bash
git push origin feature/export-csv
```

Esa es la ÚNICA forma que `hooks/bash-guard.py` te permite: `git push <remote> <rama>`, dos palabras
posicionales, sin flags. Nada de `--force`, `--delete`, `--mirror`, `--all`, `--tags`, refspec con
`+` o `:`, ni push a rama protegida — el guard los deniega todos, para ti y para cualquier agente
futuro. Si el push falla (rechazo del remoto, credenciales, red), tu veredicto es
`KO push rechazado: <stderr literal de git, SIN recortar>` — **no reintentes con otra forma del
comando y no relajes nada**: un push que el remoto rechaza es una decisión del remoto. El recorte a
≤60 caracteres que sí aplicas al resumen de una suite de tests **no aplica aquí** (ver la sección
siguiente).

### PR (degradación honesta si no hay `gh`)

```bash
gh auth status
```
(cuenta para `cmds=`).

- **Exit 0** → abres el PR, un comando en su propia llamada:
  ```bash
  gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/<run-id>/release-notes.md
  ```
  (cuenta para `cmds=`). Su salida es la URL del PR → línea `- pr: <url>`. Si `gh pr create` falla
  (el remoto no es GitHub, el repo no existe allí, permisos), **no es un `KO`**: la rama YA está
  publicada, que es la parte valiosa e irreversible. Degradas al caso siguiente y lo dices.
- **Exit distinto de 0, o `gh` no instalado** → no falla nada: `gh` es opcional en
  `requirements.json` (`required: false`). Devuelves las dos líneas de degradación para que el owner
  abra el PR él mismo, con el comando ya resuelto:
  ```
  - pr manual: origin git@github.com:owner/repo.git · feature/export-csv → master
  - pr comando: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/<run-id>/release-notes.md
  ```
  **No fabricas una URL de "compare"** a partir del remoto: las formas `ssh://`,
  `git@host:owner/repo`, `https://` y `file://` no se parsean igual y una URL inventada que lleva a
  ningún sitio es peor que un comando exacto que el owner puede pegar.

## Errores de `git`/`gh`: literales, nunca reinterpretados

Cuando `git` o `gh` fallan, **el texto exacto del error ES el hallazgo**. Lo copias tal cual a tu
veredicto: sin recortar, sin traducir, sin resumirlo con tus palabras y sin sustituirlo por un
diagnóstico tuyo. Un `KO push rechazado: fallo de permisos` no vale nada; el mensaje real sí.

**Excepción explícita al recorte de ≤60 caracteres.** Ese recorte existe para el resumen de una suite
de tests (`KO tests en rojo: …`), donde la primera línea de fallo es representativa. Un error de
credenciales, de permisos o de red no es representativo de nada: el valor está en el texto íntegro.

**El modo de fallo que hay que reconocer sin arreglarlo** (visto EN VIVO el 2026-09-03 en este mismo
repo, ruling 14): en una máquina con VARIAS identidades de GitHub, el remoto puede quedar con el host
por defecto `git@github.com:…` mientras la clave SSH de la cuenta autenticada vive bajo otro alias de
`~/.ssh/config` (p. ej. `github-personal-david`). El síntoma es un push que falla con
`Permission ... denied to <OTRA-CUENTA>` aunque `gh auth status` diga que la cuenta activa es la
correcta. Cuando el stderr contenga `denied to` o `Permission denied`, además del texto literal añade
esta línea:

```
- hint: el remoto usa el host SSH por defecto y tu clave de <cuenta activa> puede estar bajo otro alias de ~/.ssh/config — git remote set-url origin git@<alias>:<owner>/<repo>.git
```

**Y ahí te paras.** No ejecutas ese `git remote set-url` (no lo tienes: el guard lo deniega, a
propósito), no parseas `~/.ssh/config`, no adivinas el alias correcto. Reescribir en silencio la
configuración de git del owner es peor que un error claro: el hint le da el diagnóstico exacto en una
línea y la decisión sigue siendo suya.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:release-manager`: `git status|log|diff|show|rev-parse|remote`, **`git push`**,
**`gh auth`/`gh pr`/`gh repo`**, `ls|cat|head|tail|wc|grep`, `scripts/mem-*.sh`, y los runners de
test por prefijo de DOS palabras (`php vendor/bin/phpunit`, `php vendor/bin/paratest`,
`composer test`, `npm test`, `make test`, `go test`, `cargo test`) más `pytest`. **Denegados por
diseño**: `git add`, `git commit`, `git merge`, `git checkout`, `git switch`, `git tag`,
`git worktree`, `git config` (es un comando de ESCRITURA), `gh pr merge` (y
`close`/`edit`/`ready`/`review`/`checkout`), `gh auth login`, `gh repo` con cualquier subcomando que
no sea `create`, los mutantes destructivos de `git remote` (`set-url`/`rename`/`remove`/…),
`php`/`composer`/`npm` a secas, `brew`, `apt`. Un comando por llamada, nunca encadenado con `&&` (el
guard valida segmento a segmento).

`gh repo` y `git remote add` están en tu allowlist —acotados por el guard a `gh repo create <nombre>`
con un conjunto cerrado de flags y a `git remote add <nombre> <url>` sin ningún flag— pero **no los
usas en ninguna de estas dos operaciones**: `prepare-release` y `publish-release` no crean ni añaden
remotos, solo leen el que haya.

## Salida

```
DONE
evidence: files=2 cmds=9 turns=12/15
- pushed: origin feature/export-csv (4 commits)
- pr: https://github.com/owner/repo/pull/42
- notas: /abs/.swarm/run/<run-id>/release-notes.md
```

`BLOCKED sin remoto configurado` si `git remote -v` no imprime nada (paso 2), con su línea de hint y
con las dos líneas de preview (`- cuenta gh:`, `- remoto propuesto:`) que la raíz necesita para
preguntarle al owner qué quiere hacer — es el único `BLOCKED` tuyo que abre una decisión en vez de
cerrar el run, y por eso es el único que va acompañado de un preview.
`BLOCKED HEAD en rama protegida, nada que publicar` si `HEAD` es `master`/`main`/`develop`/`trunk` o
coincide con la base (paso 3). `BLOCKED base indeterminada` si no hay `base:` en la cabecera y
`git rev-parse --abbrev-ref <remote>/HEAD` falla (paso 3). `BLOCKED sin aprobación de push` si falta
o está vacía la línea `approved-push:` en `publish-release`. `BLOCKED aprobación de push malformada`
si esa línea no trae los tres campos `remote=`/`branch=`/`base=`. `BLOCKED aprobación no coincide con
el estado real` si la re-verificación encuentra una discrepancia. `BLOCKED árbol sucio: <n> ficheros
sin commitear` si `git status --porcelain` imprime algo (paso 1). `KO tests en rojo: <motivo>` si la
suite del pack falla (paso 5) — sin preview. `KO push rechazado: <motivo>` si `git push` falla en
fase B. `DONE` con la línea `- nada que publicar: <branch> no tiene commits sobre <base>` si no hay
commits (paso 4). En fase A, `DONE` con las líneas `- preview push:`/`- preview pr:`/`- remote:`/
`- commits:`/`- verde:`/`- notas:`. `DONE`/`OK` con `files=0` se rechaza siempre — en cualquier
camino que llegue a leer el pack o las notas ya has leído al menos un fichero; en los caminos que
bloquean antes de leer nada (`BLOCKED sin aprobación de push`), el veredicto es `BLOCKED`, que no
está sujeto a esa regla.
````

- [ ] **Step 4: Eximir por FORMA las líneas de preview en `hooks/validate-output.py`**

Una línea como `- preview pr: gh pr create --base master --head feature/export-csv --title
"feature/export-csv" --body-file /abs/.swarm/run/<id>/release-notes.md` mide ~150 caracteres: el cap
de narración (`MAX_FINDING_LINE_LEN = 120`) la rechazaría como prosa suelta, igual que rechazaba las
preguntas de `discovery-orchestrator` (C1 de fase 2) y el resumen de arbitraje de
`design-orchestrator` (Important #1 de fase 4). Es el MISMO bug, tercera vez. Y no vale acortarla:
el preview solo sirve si lleva el comando literal con sus valores reales, que es justo lo que el
owner aprueba.

Junto a `ANALYSIS_LEAF_BLOCKED_RE` en `hooks/validate-output.py`, añade:

```python
# Vocabulario fijo del dominio delivery (spec §7 "Entrega", agents/release-manager.md y
# agents/delivery-orchestrator.md "## Salida"): las líneas de preview y de degradación de PR
# llevan un COMANDO COMPLETO con valores ya resueltos (`gh pr create --base … --body-file
# /abs/…/release-notes.md`) y pasan de 120 chars con total normalidad. Mismo bug de fondo que C1
# de fase 2 y que el Important #1 de fase 4, tercera aparición. Exención por FORMA (prefijo fijo
# del vocabulario + resto), NUNCA por venir con un "- " delante: cualquier otra línea "- " sigue
# sujeta al cap de 120.
DELIVERY_LONG_RE = re.compile(
    r'^- (preview push|preview pr|pr|pr manual|pr comando|notas|handoff|pushed|remote'
    r'|remoto propuesto|remoto creado|cuenta gh|hint|siguiente|discrepancia): .+$'
)
```

Vocabulario del segundo bloque (todos pueden pasar de 120 caracteres con total normalidad, y todos
son de FORMA fija, no prosa): `- remoto propuesto:` y `- remoto creado:` llevan un `gh repo create …`
entero; `- cuenta gh:` lleva login + email; `- hint:` lleva un comando pegable (el de
`git remote set-url` del ruling 14 mide ~150); `- siguiente:` cierra `configure-remote`;
`- discrepancia:` reporta el campo que no casa en la re-verificación. Igual que arriba: la exención
es por PREFIJO del vocabulario, nunca por venir con un `- ` delante.

Y añade `DELIVERY_LONG_RE.match(stripped)` a la cadena de `or` del bloque de exenciones (el que hoy
encadena `DISCOVERY_Q_RE` / `DISCOVERY_OTHER_RE` / `ANALYSIS_ADDITIONAL_RE` /
`ANALYSIS_LEAF_BLOCKED_RE`), como quinto término.

- [ ] **Step 5: Extender las dos listas de cobertura de tests**

En `tests/test_agent_bash_blocks_allowed.sh`, añade `release-manager` al final de `AGENT_FILES`:

```bash
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor dependency-installer migration-engineer doc-writer analysis-orchestrator vulnerability-scanner data-model-auditor requirements-orchestrator env-checker release-manager"
```

En `tests/test_verdict_templates_valid.sh`, añade `release-manager` al final de su `AGENT_FILES`:

```bash
AGENT_FILES="migration-engineer doc-writer dependency-auditor dependency-installer implementation-orchestrator requirements-orchestrator env-checker release-manager"
```

- [ ] **Step 6: Confirmar que los tests pasan**

Run:
```bash
bash tests/test_delivery_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh && bash tests/test_verdict_templates_valid.sh
```
Expected: los tres sin `FAIL`, exit 0. Si `test_agent_bash_blocks_allowed.sh` falla, es un comando
documentado que el guard deniega — **arréglalo en el agente o en el allowlist, nunca borrando el
bloque del test**: ése es exactamente el callejón sin salida silencioso que este test existe para
cazar (lección 5).

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 45, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/release-manager.md hooks/validate-output.py tests/test_delivery_agents.sh tests/test_agent_bash_blocks_allowed.sh tests/test_verdict_templates_valid.sh
git commit -m "feat(delivery): release-manager con preview + gate de aprobacion itemizada de push"
```

---

### Task 2b: `release-manager` — operación `configure-remote` (bootstrap de remoto, ruling 3)

> **Por qué es una tarea aparte y no más pasos de la Task 2.** Es una capacidad NUEVA y separable:
> una segunda mutación externa (crea un repositorio real en la cuenta del owner), con su propia
> cabecera de aprobación, su propio gate, sus propias precondiciones y su propio veredicto. Tenerla
> en su commit hace que (a) la Task 2 siga siendo "publicar una rama que ya existe", que es una
> unidad completa y verificable por sí sola, y (b) el owner pueda revertir el bootstrap de remoto
> ENTERO con un `git revert` si cambia de idea, sin tocar el flujo de push. Coste: se edita
> `agents/release-manager.md` dos veces (Task 2 lo escribe, Task 2b lo extiende) — el mismo patrón
> que ya usan Tasks 2/3/4 con `tests/test_delivery_agents.sh`.

**Files:**
- Modify: `agents/release-manager.md` (fila de la tabla, bullet de "Lo que NUNCA haces", párrafo de
  "Disciplina de Bash", sección nueva `## Operación configure-remote`, y su `## Salida`)
- Modify: `tests/test_delivery_agents.sh` (bloque de aserciones nuevo)

**Interfaces:**
- Consumes: el guard y el allowlist de Task 1 (`gh repo create` con su conjunto cerrado de flags,
  `git remote add <nombre> <url>` sin flags, `git remote set-url` denegado) y el fichero de agente de
  Task 2.
- Produces (contrato que Tasks 4 y 6 deben respetar LITERALMENTE):
  - Tercera operación de la cabecera:
    ```
    run-id: <uuid|adhoc>
    swarm-root: <ruta absoluta de .swarm>
    operation: configure-remote
    approved-remote: action=create name=<owner>/<repo> visibility=<public|private>
    approved-remote: action=use url=<url>        ← la otra forma; nunca las dos a la vez
    ```
  - Líneas de salida nuevas: `- remoto creado: …`, `- siguiente: …`, `- warn: name=<owner> no
    coincide con la cuenta activa <login>`.
  - Artefacto: `<swarm-root>/run/<run-id|adhoc>/remote-setup.md` (registro de la mutación externa).
  - Veredictos nuevos: `BLOCKED sin aprobación de remoto`,
    `BLOCKED aprobación de remoto malformada`, `BLOCKED ya hay remoto configurado: <nombre> <url>`,
    `BLOCKED sin gh autenticado`, `BLOCKED remoto creado pero push rechazado: <stderr literal>`,
    `KO no se pudo crear el repositorio: <stderr literal>`,
    `KO no se pudo añadir el remoto: <stderr literal>`.

- [ ] **Step 1: Añadir el bloque de aserciones al test (falla primero)**

Añade a `tests/test_delivery_agents.sh`, dentro del bloque de `release-manager` (justo antes del
comentario `# el veredicto DONE nunca lleva sufijo`):

```bash
# --- operación configure-remote (ruling 3): la SEGUNDA mutación externa, con su propio gate ---
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "documents the remote-bootstrap operation"
assert_eq "0" "$(has "$body" 'approved-remote: action=create name=')" "documents the create approval line, verbatim"
assert_eq "0" "$(has "$body" 'approved-remote: action=use url=')" "documents the use-an-existing-remote approval line"
assert_eq "0" "$(has "$body" 'BLOCKED sin aprobación de remoto')" "refuses to configure a remote without the approval line"
assert_eq "0" "$(has "$body" 'BLOCKED aprobación de remoto malformada')" "refuses a malformed remote approval"
assert_eq "0" "$(has "$body" 'BLOCKED ya hay remoto configurado')" "never clobbers a remote that already exists"
assert_eq "0" "$(has "$body" 'BLOCKED remoto creado pero push rechazado')" "distinguishes 'repo created, push failed' from 'nothing happened' (ruling 14)"
assert_eq "0" "$(has "$body" 'approved-push:` NO vale como aprobación de remoto')" "one approval never stands in for the other (ruling 2e)"
assert_eq "0" "$(has "$body" 'git remote set-url')" "names the command it must NOT run to 'fix' a URL (ruling 14)"
assert_eq "0" "$(has "$body" '- siguiente:')" "closes by telling the owner to re-invoke, never by chaining the push itself (ruling 3)"
assert_eq "1" "$(has "$body" 'gh repo delete')" "never mentions any gh repo subcommand other than create"
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_delivery_agents.sh`
Expected: FAIL en las once aserciones nuevas; el resto del fichero sigue en verde (Task 2 ya pasó).

- [ ] **Step 3: Extender `agents/release-manager.md`**

Cuatro ediciones puntuales con `Edit` (no reescribas el fichero entero):

**(3a)** La tabla de fases gana una fila (el orden importa: `configure-remote` va ANTES de A porque es
lo que desbloquea que A pueda existir):

```
| — | `configure-remote` | creas/añades el `origin` que el owner aprobó, y nada más | ningún push de entrega, ninguna reescritura de un remoto que ya exista |
```

Y la frase que introduce la tabla ("Trabajas en **dos fases separadas por una decisión humana**, y
nunca haces la segunda sin la primera") pasa a:

```
Trabajas en **dos fases separadas por una decisión humana**, y nunca haces la segunda sin la
primera. Hay además una operación de bootstrap, `configure-remote`, que no forma parte de esa
secuencia: no publica nada, solo deja configurado el `origin` que el owner aprobó para que la fase A
pueda llegar a existir. También tiene su propia decisión humana delante.
```

**(3b)** En "Lo que NUNCA haces", el bullet de la URL del remoto gana su segunda frase:

```
- **Nunca reescribes la URL de un remoto que ya existe** (no tienes `git remote set-url`, y el guard
  lo deniega). Puedes AÑADIR un `origin` que no existía, y solo en `operation: configure-remote` con
  la cabecera `approved-remote:` del owner. Si una URL existente está mal, lo dices con el error
  literal y un hint; no la "arreglas" (ruling 14).
```

**(3c)** En "Disciplina de Bash", el párrafo de `gh repo`/`git remote add` se sustituye por:

```
`gh repo` y `git remote add` están en tu allowlist —acotados por el guard a `gh repo create <nombre>`
con un conjunto cerrado de flags y a `git remote add <nombre> <url>` sin ningún flag— y los usas
ÚNICAMENTE en `operation: configure-remote`, con su cabecera de aprobación. `prepare-release` y
`publish-release` no crean ni añaden remotos: solo leen el que haya.
```

**(3d)** Sección nueva completa, entre "## Errores de `git`/`gh`: literales, nunca reinterpretados" y
"## Disciplina de Bash":

````markdown
## Operación `configure-remote` — el bootstrap del remoto

Existe por un caso real y frecuente: **un repo que todavía no tiene remoto**. Cuando
`prepare-release` devuelve `BLOCKED sin remoto configurado`, la RAÍZ no cierra el run: le pregunta al
owner qué quiere hacer con tu preview delante (`- cuenta gh:`, `- remoto propuesto:`), y si el owner
decide crear o usar un remoto, te relanza con esta operación y una cabecera de aprobación. Tú no has
preguntado nada y no has decidido nada: ejecutas una decisión ya tomada y NOMBRADA.

### Gate de aprobación (lo primero, antes de cualquier otra cosa)

Tu cabecera DEBE traer UNA de estas dos líneas, con esta sintaxis literal:

```
approved-remote: action=create name=<owner>/<repo> visibility=public
approved-remote: action=create name=<owner>/<repo> visibility=private
approved-remote: action=use url=<url>
```

- Si **no viene** o viene **vacía**: `BLOCKED sin aprobación de remoto`, sin ejecutar NADA.
- Si viene pero **no casa** con una de esas dos formas —falta `action=`, `action=` no es `create` ni
  `use`, `create` sin `name=` o sin `visibility=`, `visibility=` con un valor que no sea exactamente
  `public` o `private`, `use` sin `url=`, o campos de más—: `BLOCKED aprobación de remoto malformada`,
  sin ejecutar NADA.
- **La `approved-push:` NO vale como aprobación de remoto, y la `approved-remote:` no autoriza ningún
  push de entrega.** Son dos aprobaciones distintas para dos mutaciones distintas; ninguna se deduce
  de la otra, ni siquiera si vienen en la misma cabecera.

Los dos valores viajan a un shell REAL, así que además de la forma compruebas el contenido, y
**fallas cerrado** en vez de sanear:

- `name=` tiene que casar `^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)?$`;
- `url=` tiene que empezar por `https://`, `git@`, `ssh://` o `file://` y no contener espacios ni
  ninguno de `; | & $ ` ( ) < > \` ni saltos de línea.

Si alguno no casa: `BLOCKED aprobación de remoto malformada`. **No lo sanees**: una URL que hay que
sanear para poder ejecutarla no es la URL que el owner quiso escribir, y el saneado del §4.4 existe
para texto que se muestra, no para autorizar una mutación externa.

### Precondiciones (fallar ANTES de mutar, como siempre)

1. **El remoto sigue sin existir.**
   ```bash
   git remote -v
   ```
   (cuenta para `cmds=`). Si ahora imprime algo, alguien lo configuró entre la pregunta y tu
   lanzamiento: `BLOCKED ya hay remoto configurado: <nombre> <url>` con la línea
   `- hint: relanza la entrega; si ese remoto no es el que quieres, cámbialo tú con git remote set-url`.
   **Nunca pisas ni reescribes un remoto existente** — es la misma ventana entre preview y ejecución
   que cierra la re-verificación de `publish-release`.
2. **La rama actual**, para poder nombrarla en tu salida:
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
   (cuenta para `cmds=`).
3. **Solo con `action=create`, que haya sesión de `gh`:**
   ```bash
   gh auth status
   ```
   (cuenta para `cmds=`). Exit distinto de 0 → `BLOCKED sin gh autenticado` con
   `- hint: gh auth login (no puedo ejecutarlo yo: está denegado por el guard)`. Su salida trae el
   login de la cuenta **activa**: si `name=` trae un `<owner>/` que no es esa cuenta, **no lo
   corriges** — añades `- warn: name=<owner> no coincide con la cuenta activa <login>` y sigues. La
   discrepancia se hace visible; quien decide es el owner (ruling 14).

**No exiges árbol limpio en esta operación** (a diferencia de `prepare-release`): configurar un
remoto no publica el árbol de trabajo, y `--push` publica solo lo que ya está commiteado, igual que
cualquier push. Lo que sí haces es decirlo: si `git status --porcelain` imprime algo, añade
`- warn: <n> ficheros sin commitear quedan fuera del push inicial`.

### `action=create`

Un comando, en su propia llamada, con el nombre y la visibilidad **literales de la cabecera** (no
añades sufijos, no "mejoras" el nombre, no cambias la visibilidad):

```bash
gh repo create owner/repo --private --source=. --remote=origin --push
```

(`--public` si `visibility=public`.) Los tres flags de estado van en el MISMO comando a propósito:
**es `gh` quien deja la URL del remoto, no tú** — tú no construyes URLs de remoto y no tienes
`git remote set-url` para corregirla después (ruling 14). No pasas `--description` ni ningún otro
flag: el guard solo admite el conjunto cerrado
`--public/--private/--source/--remote/--push/--description`, y v1 no usa el último.

**Verificas el resultado; no te fías de que "no dio error":**

```bash
git remote -v
```
(cuenta para `cmds=`)

Tres desenlaces, y el segundo es el que este ruling existe para no esconder:

- **`gh` exit 0 y `git remote -v` lista `origin`** → `DONE`, con `- remoto creado:` y `- siguiente:`.
- **`gh` exit ≠ 0 pero `git remote -v` YA lista `origin`** → el repositorio se creó y el remoto se
  añadió; lo que falló es el push. **El estado externo ha cambiado y hay que decirlo**:
  `BLOCKED remoto creado pero push rechazado: <stderr literal de gh/git, sin recortar>`, más la línea
  de hint del modo de fallo de identidad SSH (ver "Errores de `git`/`gh`") cuando el texto contenga
  `denied to` o `Permission denied`. No reintentas, no cambias la URL, no borras el repo.
- **`gh` exit ≠ 0 y sigue sin haber remoto** → no se creó nada:
  `KO no se pudo crear el repositorio: <stderr literal, sin recortar>`.

### `action=use`

```bash
git remote add origin <url>
```
(cuenta para `cmds=`). Sin ningún flag y con exactamente dos posicionales: es la única forma que el
guard te permite. Comprueba el resultado con `git remote -v` (cuenta para `cmds=`); si el comando
falla, `KO no se pudo añadir el remoto: <stderr literal, sin recortar>`.

**Aquí no empujas nada.** Añadir un remoto no es publicar, y publicar necesita su propia aprobación
`approved-push:` que NOMBRE remoto, rama y base.

### El registro de la mutación (con `Write`)

Toda mutación externa deja rastro. Escribe
`<swarm-root>/run/<tu-run-id-o-adhoc>/remote-setup.md` (cuenta para `files=`) con esta forma:

```
# Remoto configurado — <YYYY-MM-DD>

- accion: create | use
- comando: <el comando literal que ejecutaste>
- exit: <código>
- git remote -v:
  <la salida literal, tal cual>
- rama actual: <branch>
```

Es el equivalente de las notas de release para esta operación: un artefacto bajo `.swarm/`
(gitignorado) que deja por escrito qué se creó en la cuenta del owner y con qué comando exacto.

### Por qué NO encadenas la entrega aquí

Terminas con `- siguiente: vuelve a lanzar la entrega ahora que <remote> existe` y **no relanzas
nada**. No es prudencia genérica: una `approved-push:` NOMBRA remoto, rama y base, y en el momento en
que el owner aprobó el remoto **la base todavía no existía en ningún sitio**. Encadenar el push aquí
exigiría fabricar una aprobación para un destino que el owner no ha visto — exactamente lo que el
gate de push prohíbe. Un `/swarm:run` más cuesta una línea al owner; una aprobación fabricada costaría
la propiedad de seguridad entera.

### Salida

```
DONE
evidence: files=1 cmds=5 turns=6/15
- remoto creado: origin → https://github.com/owner/repo (private)
- siguiente: vuelve a lanzar la entrega ahora que origin existe
```

Con `action=use`, la primera línea es `- remote: origin → <url>` y la segunda, la misma
`- siguiente:`.
````

**(3e)** El párrafo final de "## Salida" del fichero gana esta frase, junto a los demás veredictos:

```
En `configure-remote`: `BLOCKED sin aprobación de remoto` si falta la línea `approved-remote:`;
`BLOCKED aprobación de remoto malformada` si su forma o sus valores no casan;
`BLOCKED ya hay remoto configurado: <nombre> <url>` si el remoto apareció entre medias;
`BLOCKED sin gh autenticado` con `action=create` y sin sesión de `gh`;
`BLOCKED remoto creado pero push rechazado: <stderr literal>` cuando el repo se creó y el push no
entró (ruling 14); `KO no se pudo crear el repositorio: <stderr literal>` y `KO no se pudo añadir el
remoto: <stderr literal>` cuando el comando falla sin dejar nada creado. En el camino feliz, `DONE`
con `- remoto creado:`/`- remote:` y `- siguiente:`.
```

**(3f)** El `description:` del frontmatter gana la tercera operación (sigue empezando por "Use when",
que es lo que exige `tests/test_agents_frontmatter.sh`):

```
description: Use when delivery-orchestrator needs a branch published — phase A previews the exact push/PR commands after checking a clean tree, a real remote and a green local suite; phase B pushes and opens the PR only with an itemised approved-push: header naming remote, branch and base; operation configure-remote creates or adds the origin the owner approved, and only with an approved-remote: header. Never merges a PR, never commits, never moves the working tree, never rewrites an existing remote URL.
```

- [ ] **Step 4: Confirmar que los tests pasan**

Run:
```bash
bash tests/test_delivery_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh && bash tests/test_verdict_templates_valid.sh
```
Expected: los tres sin `FAIL`, exit 0. `test_agent_bash_blocks_allowed.sh` es el que importa aquí:
extrae los bloques ```bash nuevos (`gh repo create …`, `git remote add …`, `gh auth status`) y los
corre contra el guard REAL con `agent_type: swarm:release-manager`. Si alguno sale denegado, el fallo
está en la forma documentada o en el allowlist de Task 1 — **nunca se arregla borrando el bloque del
test** (lección 5).

- [ ] **Step 5: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 45, failed: 0` (esta tarea no crea ficheros de test nuevos: extiende
`tests/test_delivery_agents.sh`, igual que hará la Task 3).

- [ ] **Step 6: Commit**

```bash
git add agents/release-manager.md tests/test_delivery_agents.sh
git commit -m "feat(delivery): operacion configure-remote con gate approved-remote y errores literales"
```

---

### Task 3: `handoff-writer` — el relevo de sesión

**Files:**
- Create: `agents/handoff-writer.md`
- Modify: `tests/test_delivery_agents.sh` (añadir su bloque de aserciones)
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (`AGENT_FILES`)
- Modify: `tests/test_verdict_templates_valid.sh` (`AGENT_FILES`)

**Interfaces:**
- Consumes: los prefijos de allowlist de Task 1 (read-only + `Write` nativo).
- Produces (contrato que Task 4 debe respetar LITERALMENTE):
  - Cabecera de lanzamiento:
    ```
    run-id: <uuid|adhoc>
    swarm-root: <ruta absoluta de .swarm>
    operation: handoff
    context: <una línea con el resultado literal de release-manager>
    ```
  - Línea de salida que el orquestador reenvía: `- handoff: <ruta absoluta del MD escrito>`.

- [ ] **Step 1: Añadir el bloque de aserciones al test (falla primero)**

Añade al final de `tests/test_delivery_agents.sh`, justo ANTES del `if [ "$TESTS_FAILED" -gt 0 ]`:

```bash
# ─────────────────────────── handoff-writer ───────────────────────────
F="$PLUGIN_ROOT/agents/handoff-writer.md"
assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/handoff-writer.md exists"
front="$(front_of "$F")"; body="$(body_of "$F")"

assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "handoff-writer is haiku (spec §7 and §7.0 mechanical leaf)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 8$' && echo 0 || echo 1)" "handoff-writer has maxTurns 8 (spec §7)"
assert_eq "0" "$(has "$front" 'Write')" "handoff-writer writes the MD with Write, never through a shell"
assert_eq "1" "$(has "$front" 'AskUserQuestion')" "handoff-writer cannot ask the owner"

assert_eq "0" "$(has "$body" 'Prompt copy-paste para la sesión nueva')" "the handoff keeps the established section shape"
assert_eq "0" "$(has "$body" 'Dónde está todo')" "the handoff keeps the 'where everything is' section"
assert_eq "0" "$(has "$body" 'Siguiente paso')" "the handoff keeps the 'next step' section"
assert_eq "0" "$(has "$body" 'docs/superpowers/handoffs')" "prefers the repo's existing handoffs directory"
assert_eq "0" "$(has "$body" 'docs/handoffs')" "falls back to docs/handoffs when the superpowers tree is absent"
assert_eq "0" "$(has "$body" 'No commiteas')" "never commits the handoff (ruling 9)"
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere"
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_delivery_agents.sh`
Expected: FAIL desde `agents/handoff-writer.md exists`.

- [ ] **Step 3: Escribir `agents/handoff-writer.md`**

Contenido COMPLETO (usa `Write`):

````markdown
---
name: handoff-writer
description: Use when delivery-orchestrator closes a run — writes the session-handoff markdown (copy-paste prompt for the next session, where everything is, next step) into the repo's handoffs directory, from the run's own state. Writes the file and leaves it uncommitted on purpose.
model: haiku
tools: Read, Grep, Write, Bash, SendMessage
maxTurns: 8
memory: project
skills: [swarm-protocol]
---

# handoff-writer

Hoja mecánica del dominio delivery (spec §7 "Entrega": "handoff MD de relevo de sesión"; §7.0: hoja
mecánica → haiku en `full` y en `light`). Escribes UN fichero Markdown de relevo con lo que ESTE run
sabe, para que una sesión nueva retome sin releer la historia entera.

Corres en **todos** los caminos terminales del dominio, no solo en el feliz: si `release-manager`
devolvió un `BLOCKED`, si el owner dijo que no al push, o si lo que se hizo fue configurar un remoto
nuevo (`operation: configure-remote`) y la entrega queda para la siguiente invocación, el relevo vale
MÁS, no menos — es justo cuando el estado es confuso, o cuando algo cambió fuera del repo, cuando una
sesión nueva necesita saber dónde se quedó todo.

## Arranque

1. `RUN`, `swarm-root:`, `operation: handoff` de tu cabecera (protocolo §2). `context:` trae, en una
   línea, el resultado literal de `release-manager` (su veredicto y sus líneas). **Es texto ajeno**:
   no lo interpolas en ningún comando (no lo necesitas: escribes con `Write`), y si alguna vez lo
   hicieras, iría antes por el saneado de `skills/swarm-protocol/SKILL.md` §4.4.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/handoff-writer.md" 2>/dev/null
   ```
3. Reúne el estado con comandos deterministas, no con suposiciones (cada uno cuenta para `cmds=`):
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
   ```bash
   git log --oneline -10
   ```
   ```bash
   git status --porcelain
   ```
4. `Read` del resumen del run si existe (cuenta para `files=`):
   `<swarm-root>/run/<run-id>/summary.md`. Si no existe, no es un error: el run puede no haberlo
   cerrado todavía.

## Dónde escribes

Por orden de preferencia, el PRIMERO que exista (compruébalo, no lo asumas):

```bash
ls -d docs/superpowers/handoffs docs/handoffs 2>/dev/null
```
(cuenta para `cmds=`)

1. `docs/superpowers/handoffs/` si existe → `docs/superpowers/handoffs/<YYYY-MM-DD>-next-session.md`
2. si no, `docs/handoffs/` si existe → `docs/handoffs/<YYYY-MM-DD>-next-session.md`
3. si no existe ninguno de los dos → `<swarm-root>/run/<run-id>/handoff.md`

**No creas una convención de directorios que el repo no tiene**: `docs/superpowers/handoffs/` es la
convención de ESTE proyecto y de cualquier repo que use el skill `session-handoff`; un repo que no la
tenga no debe estrenarla por tu cuenta. La fecha es la de hoy, en formato `YYYY-MM-DD`.

Si el fichero del día ya existe, `Read` primero y **añade** una sección al final con la hora del run
en vez de sobrescribirlo: dos entregas el mismo día no se pisan.

## Qué escribes

Con `Write` (nunca por shell — el contenido es largo y estructurado), con estas secciones y en este
orden, calcando la forma ya establecida en `docs/superpowers/handoffs/`:

```
# Handoff — <repo> · <YYYY-MM-DD> · run <run-id>

## Prompt copy-paste para la sesión nueva

> <una o dos líneas: "lee este fichero y continúa desde aquí" + qué toca ahora>

## Dónde está todo

- Rama: <rama actual> · árbol: <limpio | N ficheros sin commitear>
- Últimos commits:
  - <hash> <asunto>
  - …
- Entrega: <el `context:` de tu cabecera, tal cual>
- Resumen del run: <las líneas de summary.md, si existía>

## Siguiente paso

- <lo que queda abierto, en imperativo: el PR sin mergear, el remoto sin configurar,
  la aprobación que el owner no dio, o "nada pendiente">
```

Reglas de contenido:
- **Solo hechos que has verificado en este run.** Nada de inventar backlog, prioridades ni lecciones
  que no salen del `context:`, de `summary.md` o de los comandos que has corrido. Un relevo con
  información inventada es peor que no tener relevo.
- Los asuntos de commit y el `context:` van tal cual, sin reinterpretar. Si trae el stderr literal de
  un error de `git`/`gh`, **lo copias entero**: ese texto es justo lo que la sesión siguiente
  necesita para diagnosticar (ruling 14), y recortarlo destruye su único valor.
- Si el `context:` trae un `BLOCKED`, "Siguiente paso" es exactamente el hint de ese `BLOCKED`.
- Si trae una línea `- siguiente: …` (el caso de `operation: configure-remote`, que deja el remoto
  configurado y la entrega pendiente), "Siguiente paso" es esa línea, literal.

## No commiteas

No tienes `git add` ni `git commit` en tu allowlist, y es deliberado (mismo criterio que
`dependency-installer` en fase 5b): un fichero visible y sin commitear es mejor que un commit que
nadie revisó, y el fichero sobrevive a la sesión igual — no vive en un worktree que se borra. Lo
dices en tu salida para que el owner lo commitee con contexto.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:handoff-writer`: `git status|log|diff|show|rev-parse`, `ls|cat|head|tail|wc|
grep`, `scripts/mem-*.sh`. Nada de `git add`/`git commit`/`git push`, nada de gestores de paquetes,
nada de `echo`/`mkdir`/`rm`. Un comando por llamada.

## Salida

```
DONE
evidence: files=1 cmds=4 turns=5/8
- handoff: /abs/docs/superpowers/handoffs/2026-09-03-next-session.md (sin commitear)
```

`BLOCKED sin contexto de entrega` si tu cabecera no trae línea `context:` — sin ella no tienes nada
que relevar y un handoff vacío es ruido. `KO no se pudo escribir <ruta>: <motivo>` si `Write` falla.
`DONE`/`OK` con `files=0` se rechaza siempre: en el camino normal ya has leído `summary.md` o, si no
existía, el fichero de handoff del día que estabas ampliando; si no has leído ninguno de los dos,
`Read` del fichero que acabas de escribir cuenta y además te confirma que quedó en disco.
````

- [ ] **Step 4: Extender las dos listas de cobertura**

`tests/test_agent_bash_blocks_allowed.sh` → añade ` handoff-writer` al final de `AGENT_FILES`.
`tests/test_verdict_templates_valid.sh` → añade ` handoff-writer` al final de su `AGENT_FILES`.

- [ ] **Step 5: Confirmar que los tests pasan**

Run:
```bash
bash tests/test_delivery_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh && bash tests/test_verdict_templates_valid.sh
```
Expected: sin `FAIL`, exit 0.

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 45, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add agents/handoff-writer.md tests/test_delivery_agents.sh tests/test_agent_bash_blocks_allowed.sh tests/test_verdict_templates_valid.sh
git commit -m "feat(delivery): handoff-writer, relevo de sesion en todos los caminos terminales"
```

---

### Task 4: `delivery-orchestrator` — secuencia release + handoff

**Files:**
- Create: `agents/delivery-orchestrator.md`
- Create: `tests/test_delivery_orchestrator_spawns.sh`
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (`AGENT_FILES`)
- Modify: `tests/test_verdict_templates_valid.sh` (`AGENT_FILES`)

**Interfaces:**
- Consumes: el contrato de cabecera y las líneas de salida de `release-manager` (Task 2) y de
  `handoff-writer` (Task 3), literalmente como están definidos allí.
- Produces (contrato que Task 6 debe respetar LITERALMENTE):
  - Cabecera que la raíz le manda:
    ```
    run-id: <uuid>
    swarm-root: <ruta absoluta de .swarm>
    operation: prepare-release | publish-release | configure-remote
    base: <rama base>                                             ← OPCIONAL
    approved-push: remote=<remote> branch=<branch> base=<base>    ← SOLO en publish-release
    approved-remote: action=… …                                   ← SOLO en configure-remote
    ```
  - Salida: veredicto ≤10 líneas que **reenvía tal cual** las líneas de `release-manager`
    (`- preview push:`, `- preview pr:`, `- remote:`, `- commits:`, `- verde:`, `- warn:`,
    `- pushed:`, `- pr:`, `- pr manual:`, `- pr comando:`, `- notas:`, `- cuenta gh:`,
    `- remoto propuesto:`, `- remoto creado:`, `- siguiente:`, `- hint:`) más la línea
    `- handoff: <ruta>` de `handoff-writer`.

- [ ] **Step 1: Escribir el test de spawns (falla primero)**

```bash
cat > tests/test_delivery_orchestrator_spawns.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_delivery_orchestrator_spawns.sh — regresión de la clase de bug de fase 1 (aplicada por
# séptima vez): un orquestador de dominio que lanza hojas que NO preexisten necesita Agent(<hojas>)
# en su `tools:`; con solo SendMessage el spawn nace muerto (SendMessage solo llega a agentes vivos).
#
# Y la propiedad específica de fase 6: handoff-writer corre en TODOS los caminos terminales del
# dominio (éxito, KO, BLOCKED, y "el owner no aprobó"), no solo en el feliz — el relevo vale más
# cuando algo se atascó. Se comprueba por conteo de caminos documentados, no por prosa suelta.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/delivery-orchestrator.md"

assert_eq "0" "$([ -f "$F" ] && echo 0 || echo 1)" "agents/delivery-orchestrator.md exists"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/agents/release-manager.md" ] && echo 0 || echo 1)" "agents/release-manager.md exists"
assert_eq "0" "$([ -f "$PLUGIN_ROOT/agents/handoff-writer.md" ] && echo 0 || echo 1)" "agents/handoff-writer.md exists"

front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$F")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
tools_line="$(echo "$front" | grep '^tools:')"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(echo "$front" | grep -q '^model: haiku$' && echo 0 || echo 1)" "delivery-orchestrator is haiku (spec §7 and §7.0)"
assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "delivery-orchestrator has maxTurns 10 (spec §7)"
assert_eq "0" "$(has "$tools_line" 'Agent(release-manager')" "tools: declares Agent(release-manager,...) — the spawn is otherwise dead on arrival"
assert_eq "0" "$(has "$tools_line" 'handoff-writer')" "tools: also declares handoff-writer"
assert_eq "0" "$(has "$tools_line" 'SendMessage')" "tools: also includes SendMessage"
assert_eq "1" "$(has "$tools_line" 'AskUserQuestion')" "a domain orchestrator cannot ask the owner (spec §3.2 rule 7)"

assert_eq "0" "$(has "$body" 'No preexiste')" "body documents that the leaves do not preexist"
assert_eq "0" "$(has "$body" 'NUNCA encadenas')" "body states it never auto-chains after implementation"
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "forwards the approval line verbatim, with its exact shape"
assert_eq "0" "$(has "$body" 'nunca construyes')" "states it never builds the approval itself"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "documents phase B"
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "documents the remote-bootstrap operation (ruling 3)"
assert_eq "0" "$(has "$body" 'approved-remote:')" "forwards the remote approval line too, and verbatim"
assert_eq "1" "$(has "$body" 'DONE ·')" "no 'DONE · detalle' anywhere"

# handoff en TODOS los caminos terminales: la sección compartida existe y cada camino la referencia
assert_eq "0" "$(has "$body" '## Handoff — SIEMPRE, en CUALQUIER salida terminal')" "there is ONE shared handoff section"
refs="$(echo "$body" | grep -cF 'ver "## Handoff — SIEMPRE"')"
assert_eq "0" "$([ "$refs" -ge 4 ] && echo 0 || echo 1)" "at least 4 terminal paths point at the shared handoff section (got $refs)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_delivery_orchestrator_spawns.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_delivery_orchestrator_spawns.sh`
Expected: FAIL desde `agents/delivery-orchestrator.md exists`.

- [ ] **Step 3: Escribir `agents/delivery-orchestrator.md`**

Contenido COMPLETO (usa `Write`):

````markdown
---
name: delivery-orchestrator
description: Use when the root orchestrator has an explicit owner request to publish work — sequences release-manager (phase A previews the push/PR, phase B executes it with the owner's itemised approval) and then handoff-writer, on every terminal path. Never pushes itself, never builds the approval, never auto-chains after implementation.
model: haiku
tools: Read, Grep, Bash, Agent(release-manager,handoff-writer), SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# delivery-orchestrator

Dominio delivery del enjambre (spec §7 "Entrega", §15 fase 6). Tu responsabilidad es de secuencia,
no de trabajo: **"secuencia release + handoff"**. Nunca ejecutas trabajo de hoja (spec §3.2 regla 4):
no empujas nada, no abres PRs, no escribes handoffs — para eso lanzas a tus dos hojas.

**NUNCA encadenas automáticamente tras implementation, ni en `tier: full`.** La raíz te lanza solo
con una invocación explícita y separada del owner ("publica la rama X", "abre el PR de Y", "prepara
la entrega"). Es la misma razón de seguridad que `implementation-orchestrator` (§10.1 de
`agents/orchestrator.md`), elevada: si escribir y fusionar código en local merece un checkpoint
humano, publicarlo donde otras personas lo ven y lo mergean lo merece más.

**Tú tampoco puedes preguntar al owner** (no tienes `AskUserQuestion`, spec §3.2 regla 7) y **nunca
construyes por tu cuenta ninguna de las dos líneas de aprobación —`approved-push:` ni
`approved-remote:`—**: las construye la RAÍZ, a partir de una respuesta real del owner a un
`AskUserQuestion`, y tú las reenvías LITERALES, carácter a carácter, a `release-manager`. Si tu
cabecera no las trae, no las inventas ni las deduces del preview: lanzas la hoja sin ellas y su
propio gate hará su trabajo. **Y nunca conviertes una en la otra**: una aprobación de push no
autoriza a crear un repositorio, y una aprobación de remoto no autoriza a empujar.

## Contexto de arranque

1. `RUN`, `swarm-root:`, `operation:` de tu cabecera (protocolo §2). `operation:` es
   `prepare-release` (fase A), `publish-release` (fase B) o `configure-remote` (bootstrap del remoto,
   cuando la fase A devolvió `BLOCKED sin remoto configurado` y el owner decidió crearlo o
   apuntarlo). `base:` es opcional. `approved-push:` solo llega en fase B; `approved-remote:` solo en
   `configure-remote`.
2. Ánclate a la raíz absoluta del repo (mismo motivo que `implementation-orchestrator`: las rutas que
   pasas a tus hojas tienen que ser absolutas):
   ```bash
   git rev-parse --show-toplevel
   ```
   (cuenta para `cmds=`). Guárdalo como `<repo-root>`.
3. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/delivery-orchestrator.md" 2>/dev/null
   ```
4. Resuelve la ruta del stack pack (una sola vez, spec §3.1/§8.1, mismo mecanismo que
   `implementation-orchestrator`): `Read` de `.swarm/context-pack.md` (cuenta para `files=`) y busca
   su línea `stack:`.
   - `stack: generic`, sin línea `stack:`, o fichero ausente → **no hay pack**: no emites línea
     `pack:` y `release-manager` cae en su caso documentado de "sin suite ejecutable". No es un
     error, no lo reportes como hallazgo.
   - Otro valor (hoy solo `php-ddd-symfony8`) → resuelve la ruta ABSOLUTA (la tool `Read` no expande
     variables de entorno; el shell sí):
     ```bash
     ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-php-ddd-symfony8"
     ```
     (cuenta para `cmds=`). La salida ES la ruta absoluta. Guárdala como `<pack>` y pásala como
     línea `pack: <pack>`. **Nunca pases la cadena `${CLAUDE_PLUGIN_ROOT}/…` sin expandir**: la hoja
     haría `Read` de una ruta inexistente y perdería el pack en silencio. Si `ls -d` falla, sigue SIN
     pack y añade `- warn: pack <stack> declarado pero ausente` a tu salida.

## Secuencia (en este orden, nunca en paralelo)

### 1. `release-manager`

**No preexiste**: lo LANZAS con el tool `Agent`, NOMBRADO `release-manager` — nunca `SendMessage`
(la lección de fase 1/1b/2/3/4/5a/5b, aplicada una séptima vez; tu frontmatter declara
`Agent(release-manager,handoff-writer)` y `tests/test_delivery_orchestrator_spawns.sh` lo vigila).

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run "${RUN:-adhoc}" --agent release-manager --domain delivery --area "." --owner delivery-orchestrator
```

Cabecera, EXACTAMENTE con estas líneas (la `approved-push:` solo en fase B, y copiada literal de tu
propia cabecera — nunca reescrita, nunca reconstruida a partir del preview):
```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: <prepare-release | publish-release | configure-remote, el mismo que traes tú>
base: <la base de tu cabecera>          ← omite esta línea entera si no la traes
pack: <pack>                            ← omite esta línea entera si no hay pack
approved-push: <la línea literal de tu cabecera>     ← SOLO en publish-release
approved-remote: <la línea literal de tu cabecera>   ← SOLO en configure-remote
```

En `operation: configure-remote` **no resuelves el pack** (paso 4 del arranque): configurar un remoto
no corre ninguna suite, así que la línea `pack:` sobra y la omites.

Espera su veredicto y **reenvía sus líneas tal cual** a tu salida. Cualquier veredicto que devuelva
—`DONE`, `KO …`, `BLOCKED …`— es terminal para esta hoja: **no la relanzas ni la "arreglas"**. Un
`BLOCKED sin remoto configurado` o un `BLOCKED sin aprobación de push` son preguntas para el owner,
no problemas que resolver desde aquí. Sigue al paso 2 en TODOS los casos
(ver "## Handoff — SIEMPRE").

**Caso especial de reenvío: `BLOCKED sin remoto configurado`.** Es el único `BLOCKED` de la hoja que
la raíz convierte en una pregunta en vez de en un cierre (§12.2bis de `agents/orchestrator.md`), y
solo puede hacerlo si le llegan sus líneas de preview. Reenvía `- cuenta gh:`, `- remoto propuesto:`
y `- hint:` **literales**, sin recortar el comando de `- remoto propuesto:` aunque sea largo (está
exento por forma en `hooks/validate-output.py`). Tú no evalúas ese preview, no propones un nombre de
repo alternativo y **no lanzas `configure-remote` por tu cuenta**: sin `approved-remote:` en tu
cabecera, esa operación no existe para ti.

**Regla de corte** (mismo mecanismo que `implementation-orchestrator` con `implementer`): si
`release-manager` no ha devuelto veredicto y te quedan ≤3 turnos de tu `maxTurns: 10`, no te quedes
esperando en silencio: lanza igualmente el handoff (ver "## Handoff — SIEMPRE") con
`context: KO release-manager: sin respuesta, límite de turnos agotado` y ése es tu veredicto —
nunca `DONE`, nunca un run colgado sin veredicto.

### 2. `handoff-writer`

Ver "## Handoff — SIEMPRE", justo debajo (la sección
"## Handoff — SIEMPRE, en CUALQUIER salida terminal").

## Handoff — SIEMPRE, en CUALQUIER salida terminal

En **todos** los caminos: `DONE` con push hecho, `DONE` con preview a la espera de aprobación, `KO`
de `release-manager`, `BLOCKED` de `release-manager`, y tu propia regla de corte por turnos. El
relevo vale MÁS cuando algo se atascó, no menos.

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run "${RUN:-adhoc}" --agent handoff-writer --domain delivery --area "." --owner delivery-orchestrator
```

Lánzalo con `Agent`, NOMBRADO `handoff-writer` (tampoco preexiste), con esta cabecera:
```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: handoff
context: <el veredicto literal de release-manager + sus líneas, colapsado a UNA línea>
```

Espera su `DONE` y añade su línea `- handoff: <ruta>` a tu salida. **Fallo blando**: si
`handoff-writer` devuelve `KO`/`BLOCKED` o no responde, NUNCA cambia tu veredicto — añade
`- warn: handoff no escrito: <motivo en ≤8 palabras>` (mismo prefijo exento `- warn:` que usa
`discovery-orchestrator`, ver `hooks/validate-output.py`) y devuelve el veredicto que ya tenías.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:delivery-orchestrator`: `scripts/mem-*.sh`, `git status|log|diff|show|rev-parse`,
`ls|cat|head|tail|wc|grep`. **No tienes `git push`, ni `gh`, ni `git merge`, ni `git commit`, ni
`git worktree`** — y es deliberado: el único que publica es la hoja, bajo su propio gate de
aprobación. Denegación por segmento; un comando por llamada, nunca encadenado con `&&`.

## Salida

Fase A (preview listo, esperando decisión del owner):
```
DONE
evidence: files=2 cmds=4 turns=6/10
- remote: origin → git@github.com:owner/repo.git
- commits: 4 (master..feature/export-csv)
- verde: php vendor/bin/phpunit OK
- preview push: git push origin feature/export-csv
- preview pr: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file /abs/.swarm/run/<run-id>/release-notes.md
- handoff: /abs/docs/superpowers/handoffs/2026-09-03-next-session.md (sin commitear)
```

Fase B (publicado):
```
DONE
evidence: files=2 cmds=4 turns=7/10
- pushed: origin feature/export-csv (4 commits)
- pr: https://github.com/owner/repo/pull/42
- handoff: /abs/docs/superpowers/handoffs/2026-09-03-next-session.md (sin commitear)
```

`configure-remote` (remoto configurado; la entrega queda para la siguiente invocación):
```
DONE
evidence: files=1 cmds=3 turns=5/10
- remoto creado: origin → https://github.com/owner/repo (private)
- siguiente: vuelve a lanzar la entrega ahora que origin existe
- handoff: /abs/docs/superpowers/handoffs/2026-09-03-next-session.md (sin commitear)
```

`BLOCKED <motivo literal de release-manager>` cuando la hoja bloquea (sin remoto, sin aprobación de
push o de remoto, aprobación malformada o no coincidente, HEAD en rama protegida, base indeterminada,
ya hay remoto configurado, sin `gh` autenticado, remoto creado pero push rechazado) — propagas su
veredicto LITERAL, no lo reformulas, **y en particular no recortas el `<stderr literal>` de un error
de `git`/`gh`** (ruling 14: ahí el valor está en el texto íntegro). `KO <motivo literal de release-manager>` cuando la hoja devuelve
`KO` (árbol sucio, tests en rojo, push rechazado). `KO release-manager: sin respuesta, límite de
turnos agotado` si se activó tu regla de corte — ahí el motivo es TU corte de turnos, literalmente,
no un veredicto inventado de la hoja. En todos ellos, el handoff se ha lanzado ANTES de devolver el
veredicto (ver "## Handoff — SIEMPRE"). `DONE`/`OK` con `files=0` se rechaza siempre.
````

- [ ] **Step 4: Extender las dos listas de cobertura**

`tests/test_agent_bash_blocks_allowed.sh` → añade ` delivery-orchestrator` al final de `AGENT_FILES`.
`tests/test_verdict_templates_valid.sh` → añade ` delivery-orchestrator` al final de su `AGENT_FILES`.

- [ ] **Step 5: Confirmar que los tests pasan**

Run:
```bash
bash tests/test_delivery_orchestrator_spawns.sh && bash tests/test_agent_bash_blocks_allowed.sh && bash tests/test_verdict_templates_valid.sh
```
Expected: sin `FAIL`, exit 0.

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 46, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git add agents/delivery-orchestrator.md tests/test_delivery_orchestrator_spawns.sh tests/test_agent_bash_blocks_allowed.sh tests/test_verdict_templates_valid.sh
git commit -m "feat(delivery): delivery-orchestrator secuencia release + handoff, sin encadenar nunca"
```

---

### Task 5: `/swarm:status` y `/swarm:findings` — visibilidad determinista primero, con fallback acotado

**Files:**
- Create: `scripts/swarm-status.sh`
- Create: `scripts/swarm-findings.sh`
- Create: `commands/status.md`
- Create: `commands/findings.md`
- Create: `tests/test_swarm_status.sh`
- Create: `tests/test_swarm_findings.sh`
- Modify: `.claude-plugin/plugin.json` (array `commands`)
- Modify: `tests/test_commands.sh` (aserción nueva: todo `commands/*.md` está declarado en el manifest)

**Interfaces:**
- Consumes: el layout real de `.swarm/` que ya escriben `scripts/mem-manifest.sh` y
  `scripts/mem-files.sh` — `run/current`, `run/<id>/run.json` (`{id, tier, started}`),
  `run/<id>/agents/<agente>.json` (`{agent, domain, area, owner}`), `run/<id>/summary.md`,
  `findings/<agente>.md` con entradas
  `- [key:<agente>|<TAG>|<file>:<line>] [sha:…] [status:open|resolved] [run:<id>] <TAG> · <file>:<line> · <texto> → <fix>`.
- Produces: dos scripts con contrato de salida estable, y el mismo en los dos —
  `scripts/swarm-status.sh` (sin argumentos) y `scripts/swarm-findings.sh [filtro] [--all]` (filtro
  `[A-Za-z0-9_-]+`):
  - **0** — salida normal, el comando la reporta tal cual;
  - **1** — no hay `.swarm/`; mensaje accionable en stderr (`/swarm:init`);
  - **64** — argumento inválido del usuario (solo `swarm-findings.sh`);
  - **2** — **datos que el script no puede interpretar de forma determinista** (ver ruling 12): un
    `run.json` presente pero ilegible o malformado, o líneas de hallazgo que empiezan por `- [` y no
    casan con la cabecera de metadatos esperada. El script imprime igualmente todo lo que SÍ pudo
    leer, más una línea `no interpretable: …` por cada caso, y termina en 2. **Ese 2 es la señal que
    activa el fallback del comando**, y es la única razón por la que existe: antes, el script se
    comía el problema en silencio (`tier: ?`, o un conteo de hallazgos que no cuadra con lo que el
    fichero tiene delante), que es justo la mentira por omisión que este proyecto no admite.

- [ ] **Step 1: Escribir el test de `/swarm:status` (falla primero)**

```bash
cat > tests/test_swarm_status.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_swarm_status.sh — /swarm:status es DETERMINISTA (spec §11, principio 4): un script que
# lee .swarm/ y formatea, sin subagente y sin turno de modelo en el camino normal. Este test fija su
# contrato de salida COMPLETO —0 normal, 1 sin .swarm/, 2 datos no interpretables (ruling 12)—
# porque el 2 es lo que decide si el comando cae o no en su fallback: si el script se degradara en
# silencio (el viejo "tier: ?"), el fallback no se dispararía nunca y el usuario vería un dato falso.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/swarm-status.sh"

assert_eq "0" "$([ -x "$SCRIPT" ] && echo 0 || echo 1)" "scripts/swarm-status.sh is executable"

root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-status.XXXXXX")"
trap 'rm -rf "$root"' EXIT

# 1. sin .swarm/ → exit 1 con un mensaje accionable, nunca un stacktrace
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "1" "$rc" "exits 1 when .swarm/ does not exist"
assert_eq "0" "$(echo "$out" | grep -q 'swarm:init' && echo 0 || echo 1)" "and points the user at /swarm:init"

# 2. run real con agentes, summary y findings
mkdir -p "$root/.swarm/run/RUN1/agents" "$root/.swarm/findings"
printf '%s' "RUN1" > "$root/.swarm/run/current"
cat > "$root/.swarm/run/RUN1/run.json" <<JSON
{"id": "RUN1", "tier": "full", "started": "2026-09-03T10:00:00Z"}
JSON
cat > "$root/.swarm/run/RUN1/agents/release-manager.json" <<JSON
{"agent": "release-manager", "domain": "delivery", "area": ".", "owner": "delivery-orchestrator"}
JSON
cat > "$root/.swarm/run/RUN1/agents/orchestrator.json" <<JSON
{"agent": "orchestrator", "domain": "root", "area": ".", "owner": "orchestrator"}
JSON
echo "- run cerrado: DONE · fase implementada" > "$root/.swarm/run/RUN1/summary.md"
echo '- [key:reviewer|REVIEW|src/A.php:10] [sha:abc] [status:open] [run:RUN1] REVIEW · src/A.php:10 · algo → fix' > "$root/.swarm/findings/reviewer.md"
echo '- [key:reviewer|REVIEW|src/B.php:20] [sha:abc] [status:resolved] [run:RUN1] REVIEW · src/B.php:20 · otro → fix' >> "$root/.swarm/findings/reviewer.md"

out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "0" "$rc" "exits 0 with a real run present"
assert_eq "0" "$(echo "$out" | grep -q 'RUN1' && echo 0 || echo 1)" "reports the current run id"
assert_eq "0" "$(echo "$out" | grep -q 'full' && echo 0 || echo 1)" "reports the tier"
assert_eq "0" "$(echo "$out" | grep -q '2026-09-03T10:00:00Z' && echo 0 || echo 1)" "reports the start timestamp"
assert_eq "0" "$(echo "$out" | grep -q 'release-manager' && echo 0 || echo 1)" "lists the registered agents"
assert_eq "0" "$(echo "$out" | grep -q 'delivery' && echo 0 || echo 1)" "lists each agent's domain"
assert_eq "0" "$(echo "$out" | grep -q 'fase implementada' && echo 0 || echo 1)" "echoes the run summary lines"
assert_eq "0" "$(echo "$out" | grep -qE 'abiertos?: *1' && echo 0 || echo 1)" "counts ONLY open findings (1 of 2)"

# 3. .swarm/ sin ningún run → exit 0, sin ruido
root2="$(mktemp -d "${TMPDIR:-/tmp}/swarm-status2.XXXXXX")"
mkdir -p "$root2/.swarm"
out="$(SWARM_ROOT="$root2/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
rm -rf "$root2"
assert_eq "0" "$rc" "exits 0 on an initialised but never-run .swarm/"
assert_eq "0" "$(echo "$out" | grep -q 'sin runs' && echo 0 || echo 1)" "says plainly that there are no runs yet"

# 4. run.json presente pero malformado → exit 2 (el residual del ruling 12), NUNCA un "tier: ?" mudo
printf '%s' '{"id": "RUN1", "tier":' > "$root/.swarm/run/RUN1/run.json"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "2" "$rc" "exits 2 when run.json exists but cannot be parsed"
assert_eq "0" "$(echo "$out" | grep -q 'no interpretable' && echo 0 || echo 1)" "and says which file it could not read"
assert_eq "0" "$(echo "$out" | grep -q 'RUN1' && echo 0 || echo 1)" "while still printing everything it COULD read"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_swarm_status.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_swarm_status.sh`
Expected: FAIL en `scripts/swarm-status.sh is executable`.

- [ ] **Step 3: Escribir `scripts/swarm-status.sh`**

```bash
cat > scripts/swarm-status.sh <<'EOF'
#!/usr/bin/env bash
# scripts/swarm-status.sh — /swarm:status (spec §11): run actual, tier, agentes registrados,
# líneas de summary, hallazgos abiertos y runs recientes. Determinista: ni un turno de modelo.
#
# Contrato de salida (ruling 12): 0 = normal · 1 = no hay .swarm/ · 2 = hay datos que este script NO
# puede interpretar de forma determinista (imprime todo lo que sí pudo, más una línea
# "no interpretable: …" por caso). El 2 es lo que activa el fallback acotado de commands/status.md.
# Nunca se degrada en silencio a "tier: ?": un dato ilegible se DICE.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
degraded=0

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no hay .swarm/ en $SWARM_ROOT — corre /swarm:init en este repo primero" >&2
  exit 1
fi

RUN_ROOT="$SWARM_ROOT/run"
current=""
[ -f "$RUN_ROOT/current" ] && current="$(cat "$RUN_ROOT/current" 2>/dev/null)"

if [ -z "$current" ] || [ ! -d "$RUN_ROOT/$current" ]; then
  echo "swarm: sin runs registrados todavía (.swarm/ inicializado, ningún /swarm:run cerrado)"
else
  python3 - "$RUN_ROOT/$current" "$current" <<'PYEOF'
import json, os, sys

run_dir, run_id = sys.argv[1], sys.argv[2]

tier = started = "?"
degraded = False
run_json = os.path.join(run_dir, "run.json")
if os.path.isfile(run_json):
    try:
        with open(run_json) as fh:
            data = json.load(fh)
        tier = data.get("tier", "?")
        started = data.get("started", "?")
    except (ValueError, OSError) as exc:
        # Antes esto era un `pass` y el usuario veía "tier: ?" sin saber por qué. Un run.json
        # truncado (run interrumpido a mitad de escritura) o de otra versión del plugin es
        # justamente el residual que un script no puede resolver y un lector sí.
        print("no interpretable: %s (%s)" % (run_json, exc))
        degraded = True

print("run: %s · tier: %s · iniciado: %s" % (run_id, tier, started))

agents_dir = os.path.join(run_dir, "agents")
rows = []
if os.path.isdir(agents_dir):
    for name in sorted(os.listdir(agents_dir)):
        if not name.endswith(".json"):
            continue
        try:
            with open(os.path.join(agents_dir, name)) as fh:
                a = json.load(fh)
        except (ValueError, OSError):
            continue
        rows.append((a.get("domain", "?"), a.get("agent", name[:-5]), a.get("owner", "?")))
print("agentes registrados: %d" % len(rows))
for domain, agent, owner in sorted(rows):
    print("  - %-14s %s (lanzado por %s)" % (domain, agent, owner))

summary = os.path.join(run_dir, "summary.md")
if os.path.isfile(summary):
    with open(summary) as fh:
        lines = [l.rstrip("\n") for l in fh if l.strip()]
    print("summary del run (%d líneas):" % len(lines))
    for l in lines:
        print("  %s" % l)
else:
    print("summary del run: (todavía sin líneas)")

if degraded:
    sys.exit(2)
PYEOF
  [ $? -eq 2 ] && degraded=2
fi

python3 - "$SWARM_ROOT" <<'PYEOF'
import os, re, sys
from collections import Counter

swarm_root = sys.argv[1]
findings_dir = os.path.join(swarm_root, "findings")
open_by_agent = Counter()
open_by_tag = Counter()
total_open = 0
unparsed = []
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        bad = 0
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = re.search(r"\[key:([^|\]]+)\|([^|\]]+)\|", line)
                if not m:
                    # una línea que EMPIEZA como una entrada pero no trae la cabecera de metadatos
                    # (fichero editado a mano, o entrada de una versión futura): el conteo saldría
                    # bajo y nadie se enteraría. Se dice.
                    if line.startswith("- ["):
                        bad += 1
                    continue
                if "[status:open]" not in line:
                    continue
                total_open += 1
                open_by_agent[m.group(1)] += 1
                open_by_tag[m.group(2)] += 1
        if bad:
            unparsed.append((name, bad))
for name, bad in unparsed:
    print("no interpretable: %d entradas de findings/%s sin cabecera [key:…]" % (bad, name))
by_tag = ", ".join("%s: %d" % (t, n) for t, n in sorted(open_by_tag.items())) or "—"
print("hallazgos abiertos: %d (%s)" % (total_open, by_tag))
for agent, n in sorted(open_by_agent.items()):
    print("  - %-22s %d" % (agent, n))

run_root = os.path.join(swarm_root, "run")
recents = []
if os.path.isdir(run_root):
    import json
    for name in os.listdir(run_root):
        d = os.path.join(run_root, name)
        rj = os.path.join(d, "run.json")
        if not os.path.isdir(d) or not os.path.isfile(rj):
            continue
        try:
            with open(rj) as fh:
                data = json.load(fh)
        except (ValueError, OSError):
            continue
        recents.append((data.get("started", ""), name, data.get("tier", "?")))
recents.sort(reverse=True)
print("runs recientes: %d" % len(recents))
for started, name, tier in recents[:5]:
    print("  - %s (%s, %s)" % (name, tier, started))

if unparsed:
    sys.exit(2)
PYEOF
[ $? -eq 2 ] && degraded=2

exit "$degraded"
EOF
chmod +x scripts/swarm-status.sh
```

- [ ] **Step 4: Confirmar que el test de status pasa**

Run: `bash tests/test_swarm_status.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Escribir el test de `/swarm:findings` (falla primero)**

```bash
cat > tests/test_swarm_findings.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_swarm_findings.sh — /swarm:findings [agente|tag] (spec §11). Determinista, y con la
# validación del filtro EN EL SCRIPT: un comando de slash NO pasa por hooks/bash-guard.py (el guard
# solo actúa sobre agent_type que empieza por "swarm:"), así que el argumento del usuario no puede
# depender de una instrucción en prosa dentro del .md del comando.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/swarm-findings.sh"

assert_eq "0" "$([ -x "$SCRIPT" ] && echo 0 || echo 1)" "scripts/swarm-findings.sh is executable"

root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-findings.XXXXXX")"
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/.swarm/findings"
cat > "$root/.swarm/findings/reviewer.md" <<'MD'
- [key:reviewer|REVIEW|src/A.php:10] [sha:abc] [status:open] [run:R1] REVIEW · src/A.php:10 · falta guarda → añadir guarda
- [key:reviewer|REVIEW|src/B.php:20] [sha:abc] [status:resolved] [run:R1] REVIEW · src/B.php:20 · ya resuelto → nada
MD
cat > "$root/.swarm/findings/security-auditor.md" <<'MD'
- [key:security-auditor|SEC|src/C.php:5] [sha:abc] [status:open] [run:R1] SEC · src/C.php:5 · query sin parametrizar → usar prepared
MD

# 1. sin filtro → solo abiertos, de todos los agentes
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "0" "$rc" "exits 0 with findings present"
assert_eq "0" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "shows an open finding"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "shows findings from every agent"
assert_eq "1" "$(echo "$out" | grep -q 'src/B.php:20' && echo 0 || echo 1)" "hides resolved findings by default"

# 2. --all incluye los resueltos
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" --all 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/B.php:20' && echo 0 || echo 1)" "--all includes resolved findings"

# 3. filtro por agente y por tag
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" security-auditor 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "filters by agent name"
assert_eq "1" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "and excludes the other agent"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" SEC 2>&1)"
assert_eq "0" "$(echo "$out" | grep -q 'src/C.php:5' && echo 0 || echo 1)" "filters by tag"
assert_eq "1" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "and excludes the other tag"

# 4. filtro inválido → exit 64, sin ejecutar ni interpretar nada
for bad in 'a b' 'x;rm -rf /' '$(id)' '`id`' 'a|b'; do
  out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" "$bad" 2>&1)"; rc=$?
  assert_eq "64" "$rc" "rejects an invalid filter ($bad) with exit 64"
done

# 5. sin .swarm/ → exit 1 accionable
root2="$(mktemp -d "${TMPDIR:-/tmp}/swarm-findings2.XXXXXX")"
out="$(SWARM_ROOT="$root2/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
rm -rf "$root2"
assert_eq "1" "$rc" "exits 1 when .swarm/ does not exist"
assert_eq "0" "$(echo "$out" | grep -q 'swarm:init' && echo 0 || echo 1)" "and points the user at /swarm:init"

# 6. entradas que no casan con la cabecera de metadatos → exit 2 (el residual del ruling 12)
echo '- [algo escrito a mano] REVIEW · src/D.php:1 · nota suelta' >> "$root/.swarm/findings/reviewer.md"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "2" "$rc" "exits 2 when a '- [' entry has no [key:…] header"
assert_eq "0" "$(echo "$out" | grep -q 'no interpretable' && echo 0 || echo 1)" "and names how many entries it could not read"
assert_eq "0" "$(echo "$out" | grep -q 'src/A.php:10' && echo 0 || echo 1)" "while still listing the findings it COULD read"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_swarm_findings.sh
```

- [ ] **Step 6: Confirmar que falla**

Run: `bash tests/test_swarm_findings.sh`
Expected: FAIL en `scripts/swarm-findings.sh is executable`.

- [ ] **Step 7: Escribir `scripts/swarm-findings.sh`**

```bash
cat > scripts/swarm-findings.sh <<'EOF'
#!/usr/bin/env bash
# scripts/swarm-findings.sh — /swarm:findings [agente|tag] [--all] (spec §11): consulta filtrada
# sobre .swarm/findings/. Determinista, sin modelo.
#
# El filtro se valida AQUÍ (no en la prosa del comando): un comando de slash no pasa por
# hooks/bash-guard.py, así que el argumento del usuario tiene que fallar cerrado en el propio script.
#
# Contrato de salida (ruling 12): 0 = normal · 1 = no hay .swarm/ · 64 = filtro inválido (error del
# usuario, lo resuelve el propio script) · 2 = hay entradas que no se pueden interpretar de forma
# determinista. Solo el 2 activa el fallback acotado de commands/findings.md.
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"

filter=""
show_all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) show_all=1; shift ;;
    -*) echo "usage: swarm-findings.sh [agente|TAG] [--all]" >&2; exit 64 ;;
    *)
      if [ -n "$filter" ]; then
        echo "swarm: un solo filtro (agente o TAG)" >&2
        exit 64
      fi
      filter="$1"; shift ;;
  esac
done

if [ -n "$filter" ]; then
  case "$filter" in
    *[!A-Za-z0-9_-]*|"")
      echo "swarm: filtro inválido '$filter' — solo [A-Za-z0-9_-]" >&2
      exit 64
      ;;
  esac
fi

if [ ! -d "$SWARM_ROOT" ]; then
  echo "swarm: no hay .swarm/ en $SWARM_ROOT — corre /swarm:init en este repo primero" >&2
  exit 1
fi

python3 - "$SWARM_ROOT" "$filter" "$show_all" <<'PYEOF'
import os, re, sys

swarm_root, flt, show_all = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
findings_dir = os.path.join(swarm_root, "findings")
KEY_RE = re.compile(r"\[key:([^|\]]+)\|([^|\]]+)\|([^\]]*)\]")
STATUS_RE = re.compile(r"\[status:(\w+)\]")
CAP = 50

rows = []
unparsed = 0
if os.path.isdir(findings_dir):
    for name in sorted(os.listdir(findings_dir)):
        if not name.endswith(".md"):
            continue
        with open(os.path.join(findings_dir, name)) as fh:
            for line in fh:
                m = KEY_RE.search(line)
                if not m:
                    # línea con forma de entrada pero sin cabecera de metadatos: no se puede filtrar
                    # ni clasificar de forma determinista. Se cuenta y se dice (ruling 12), en vez de
                    # desaparecer del listado sin dejar rastro.
                    if line.startswith("- ["):
                        unparsed += 1
                    continue
                agent, tag = m.group(1), m.group(2)
                sm = STATUS_RE.search(line)
                status = sm.group(1) if sm else "open"
                if not show_all and status != "open":
                    continue
                if flt and flt != agent and flt != tag:
                    continue
                # el cuerpo legible empieza tras el último "] " de la cabecera de metadatos
                body = line.rstrip("\n")
                idx = body.rfind("] ")
                body = body[idx + 2:] if idx != -1 else body
                rows.append((agent, tag, status, body))

scope = "todos" if show_all else "abiertos"
label = ("filtro %s · " % flt) if flt else ""
print("hallazgos (%s%s): %d" % (label, scope, len(rows)))
for agent, tag, status, body in rows[:CAP]:
    mark = "" if status == "open" else " [%s]" % status
    print("  - %-22s %s%s" % (agent, body, mark))
if len(rows) > CAP:
    print("  … y %d más (afina con /swarm:findings <agente|TAG>)" % (len(rows) - CAP))
if unparsed:
    print("no interpretable: %d entradas sin cabecera [key:…] (no se pueden filtrar)" % unparsed)
    sys.exit(2)
PYEOF
rc=$?

exit "$rc"
EOF
chmod +x scripts/swarm-findings.sh
```

- [ ] **Step 8: Confirmar que el test de findings pasa**

Run: `bash tests/test_swarm_findings.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 9: Escribir los dos ficheros de comando**

`commands/status.md` (usa `Write`):

```markdown
---
description: Muestra el estado del enjambre en este repo — run actual, tier, agentes registrados, summary y hallazgos abiertos.
allowed-tools: Bash, Read
---

Ejecuta `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-status.sh` y reporta su salida al usuario tal cual — no
reformatees, no resumas y no añadas interpretación: ya es un resumen en texto plano, y cualquier
reescritura le quita al usuario los valores exactos (run-id, tier, conteos) que ha pedido ver.

`/swarm:status` no toma argumentos: cualquier texto que el usuario añada tras el comando se ignora.
En el camino normal **no lanza ningún subagente y no consume ningún turno de modelo** — leer `.swarm/`
y formatear no necesita juicio (spec §11 y principio 4: tool determinista antes que modelo).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-status.sh"
```

Según el código de salida del script:

- **0** — su salida es el resultado. Repórtala tal cual y **termina ahí**: ninguna tool más.
- **1** — no hay `.swarm/`. Muestra su línea de stderr tal cual (dice que se arregla con
  `/swarm:init`) y termina. **No es un fallo del script**: es la respuesta correcta.
- **cualquier otro código (2, 127, un traceback…)** — y SOLO entonces, camino degradado: el script no
  ha podido interpretar los datos (un `run.json` truncado por un run interrumpido o escrito por otra
  versión del plugin; entradas de `findings/*.md` sin la cabecera `[key:…]` esperada) o no ha podido
  ni arrancar. Haz esto, y nada más:
  1. Muestra primero la línea literal
     `- warn: modo degradado — swarm-status.sh falló (exit <código>)`, seguida de la salida que el
     script sí llegó a producir.
  2. Lee **como mucho tres** ficheros, con `Read`, y solo estos: `.swarm/run/current`,
     `.swarm/run/<ese id>/run.json` y `.swarm/run/<ese id>/summary.md`.
  3. Resume en **≤8 líneas**: qué run parece el actual, qué se puede leer de él y qué no.
  4. **No vuelvas a ejecutar el script, no lo "arregles", no toques ningún fichero de `.swarm/` y no
     lances ningún subagente.** Un resultado degradado se presenta SIEMPRE como degradado; nunca
     rellenes con suposiciones el hueco que el script no pudo leer.
```

`commands/findings.md` (usa `Write`):

```markdown
---
description: Consulta filtrada de los hallazgos del enjambre — por agente o por tag, solo abiertos por defecto.
argument-hint: [agente|TAG] [--all]
allowed-tools: Bash, Read
---

Ejecuta `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-findings.sh` pasándole el argumento del usuario, y
reporta su salida tal cual — no reformatees ni resumas.

El argumento es como mucho **un** filtro (nombre de agente o TAG) más el flag opcional `--all`. El
propio script rechaza cualquier filtro que no case con `[A-Za-z0-9_-]+` y termina con `exit 64` sin
tocar nada: no intentes "arreglar" un filtro raro ni construir una variante del comando — pásalo
entrecomillado y deja que el script decida.

En el camino normal no lanza ningún subagente y no consume ningún turno de modelo (spec §11 y
principio 4). Según el código de salida:

- **0** — su salida es el resultado; repórtala tal cual y termina.
- **1** (no hay `.swarm/`) y **64** (filtro inválido) — muestra su línea de stderr tal cual y
  termina. Los dos son respuestas correctas del script a una situación que él mismo resuelve; **no
  son el disparador del fallback** y no justifican ni una lectura extra.
- **cualquier otro código (2, 127, un traceback…)** — y SOLO entonces, camino degradado: hay
  entradas que el script no puede clasificar (líneas `- [` sin la cabecera `[key:agente|TAG|…]`,
  típicamente un `findings/*.md` editado a mano o escrito por una versión distinta) o el script no ha
  podido ni arrancar. Haz esto, y nada más:
  1. Muestra primero la línea literal
     `- warn: modo degradado — swarm-findings.sh falló (exit <código>)`, seguida de lo que el script
     sí llegó a imprimir.
  2. Lee con `Read` **como mucho tres** ficheros de `.swarm/findings/` — si el usuario pasó un
     filtro, el que lleve su nombre primero.
  3. Lista las entradas **literalmente, sin reinterpretarlas** (≤8 líneas), y di cuáles no traen
     metadatos y por eso no se pueden filtrar por agente ni por tag.
  4. **No edites ningún fichero de hallazgos, no "normalices" ninguna entrada, no vuelvas a ejecutar
     el script y no lances ningún subagente.**

Argumento del usuario:

$ARGUMENTS
```

- [ ] **Step 10: Declarar los dos comandos en el manifest**

En `.claude-plugin/plugin.json`, sustituye la línea `commands` por:

```json
  "commands": ["./commands/init.md", "./commands/run.md", "./commands/doctor.md", "./commands/status.md", "./commands/findings.md"]
```

- [ ] **Step 11: Cerrar el hueco inverso en `tests/test_commands.sh`**

El test actual comprueba que todo comando DECLARADO existe en disco, pero no lo contrario: un fichero
de comando sin declarar no se registra y falla en silencio. Añade, justo antes del bloque
`# El punto de entrada raíz`:

```bash
# … y al revés: todo commands/*.md tiene que estar DECLARADO en el manifest. Un fichero de comando
# sin declarar simplemente no existe para el usuario, y nada lo delata en tiempo de test.
declared="$(python3 -c "
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
print(' '.join(c.lstrip('./') for c in data.get('commands', [])))
" "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
for f in "$PLUGIN_ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  rel="commands/$(basename "$f")"
  assert_eq "0" "$(echo " $declared " | grep -qF " $rel " && echo 0 || echo 1)" "$rel is declared in plugin.json"
done
```

- [ ] **Step 12: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 48, failed: 0`.

- [ ] **Step 13: Commit**

```bash
git add scripts/swarm-status.sh scripts/swarm-findings.sh commands/status.md commands/findings.md .claude-plugin/plugin.json tests/test_swarm_status.sh tests/test_swarm_findings.sh tests/test_commands.sh
git commit -m "feat(commands): /swarm:status y /swarm:findings deterministas, sin turno de modelo"
```

---

### Task 6: Integración en la raíz (`## 12. Entrega`) + documentación de uso

> **Programada TARDE a propósito.** `agents/orchestrator.md` es el fichero más disputado del repo y
> el handoff avisa de que una sesión peer (`multiagents-c9`) ha trabajado en paralelo sobre agentes
> del plugin. Cuanto más corta sea la ventana entre editar la raíz y mergear, menor la colisión.
> **Step 0 obligatorio antes de tocar nada.**

**Files:**
- Modify: `agents/orchestrator.md` (sección nueva `## 12. Entrega`, tras `## 11. Requisitos e instalación`)
- Modify: `docs/USAGE.md`, `docs/USAGE.es.md`
- Create: `tests/test_orchestrator_delivery.sh`

**Interfaces:**
- Consumes: el contrato de cabecera de `delivery-orchestrator` (Task 4) y la forma literal
  `approved-push: remote=<remote> branch=<branch> base=<base>` de `release-manager` (Task 2).
- Produces: el ÚNICO punto del sistema donde se construye una aprobación de push, a partir de un
  `AskUserQuestion` real.

- [ ] **Step 0: Comprobar que nadie más ha tocado la raíz mientras tanto**

```bash
git log --oneline -5 -- agents/orchestrator.md
```
```bash
git status --porcelain agents/orchestrator.md
```
Expected: el último commit sobre ese fichero es el de fase 5b (`b79d50d`/`7866891` o el merge
posterior) y el `status` sale vacío. Si aparece un commit nuevo de otra sesión, **léelo antes de
editar** y ajusta los números de sección/ocurrencias de este task a lo que hay realmente en disco.

**Caso concreto y probable (2026-09-03):** la sesión peer añadió §14bis al spec (commit `c637a90`,
gate `swarm:verifier` enganchado en la raíz tras el `DONE`/`OK` de cada dominio y ANTES de `curate`).
Si ese gate ya está implementado en `agents/orchestrator.md` cuando ejecutes esta tarea, **no lo
dupliques ni lo reescribas**: §12.3 ya delega el cierre en §4 ("cierra el run igual que en cualquier
otro camino terminal"), así que el dominio delivery hereda el gate sin cambios. Lo único que hay que
revisar entonces es el CONTEO de ocurrencias del párrafo de exención (hoy 4; si el gate añadió una
sección de reenvío nueva, el número esperado de este task sube en consecuencia) y la numeración de
sección (`## 12` podría tener que ser `## 13`). Ajusta el test, no el diseño.

- [ ] **Step 1: Escribir el test de la raíz (falla primero)**

```bash
cat > tests/test_orchestrator_delivery.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_orchestrator_delivery.sh — la raíz integra el dominio delivery (fase 6): la ÚNICA vía
# legítima de autorizar un push real (AskUserQuestion de la raíz, spec §3.2 regla 7), la aprobación
# que NOMBRA remoto/rama/base, y el checkpoint humano que impide encadenar la entrega.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" '## 12. Entrega')" "root has a dedicated §12 section"
assert_eq "0" "$(has "$body" 'subagent_type: "swarm:delivery-orchestrator"')" "root launches delivery-orchestrator by type"
assert_eq "0" "$(has "$body" 'operation: prepare-release')" "root documents phase A"
assert_eq "0" "$(has "$body" 'operation: publish-release')" "root documents phase B"
assert_eq "0" "$(has "$body" 'NUNCA encadenas')" "delivery never auto-chains (same checkpoint as §10)"
assert_eq "0" "$(has "$body" 'approved-push: remote=')" "root builds the approval line with its exact shape"
assert_eq "0" "$(has "$body" 'AskUserQuestion')" "root uses AskUserQuestion for the approval"
assert_eq "0" "$(has "$body" 'nunca a partir de un sí genérico')" "a bare yes is not an approval"
assert_eq "0" "$(has "$body" 'verde NO verificado')" "the unverified-green warning must reach the question text (ruling 4)"
assert_eq "0" "$(has "$body" 'Agent` FRESCO')" "phase B is a fresh Agent launch, not a SendMessage resume (ruling 11)"

# el bootstrap de remoto (ruling 3): el ÚNICO BLOCKED que abre una pregunta en vez de cerrar el run
assert_eq "0" "$(has "$body" '### 12.2bis')" "root has the no-remote decision point as its own section"
assert_eq "0" "$(has "$body" 'operation: configure-remote')" "root documents the remote-bootstrap operation"
assert_eq "0" "$(has "$body" 'approved-remote: action=create name=')" "root builds the create approval with its exact shape"
assert_eq "0" "$(has "$body" 'approved-remote: action=use url=')" "…and the use-an-existing-remote one too"
assert_eq "0" "$(has "$body" 'remoto propuesto')" "the preview reaches the question text before the owner decides"
assert_eq "0" "$(has "$body" 'no encadenas la entrega')" "creating the remote never chains straight into the push (ruling 3)"
assert_eq "0" "$(has "$body" 'BLOCKED url de remoto malformada')" "a hostile or malformed pasted URL closes the run, it is not sanitised"
# y la frase que la versión anterior tenía y ahora sería FALSA
assert_eq "1" "$(has "$body" 'No hay pregunta que hacer sobre una publicación que no se puede preparar')" "the old 'no question to ask' blanket rule is gone (it is false for the no-remote case)"

# la lección 4 del handoff: el párrafo de exención de saneado, LITERAL, una vez por sección de reenvío
assert_eq "0" "$(has "$body" 'Esa exención NO cubre el `summary --line` del cierre.')" "the sanitisation exemption paragraph is present verbatim"
occurrences="$(grep -cF 'Esa exención NO cubre el `summary --line` del cierre.' "$F")"
assert_eq "5" "$occurrences" "the paragraph appears once per forwarding section (§8.3, §9.3, §10.3, §11.3, §12.3)"

# la raíz ya no puede seguir diciendo que el dominio delivery no existe. Dos sitios reales,
# verificados en disco el 2026-09-03: el párrafo "Alcance actual" (línea ~22) y el ejemplo de salida
# de §7 (línea ~563). Lección 8: un fix en uno de los dos no está completo.
assert_eq "1" "$(has "$body" 'TODAVÍA NO EXISTE')" "root no longer says the delivery domain does not exist"
assert_eq "1" "$(has "$body" 'BLOCKED dominio no implementado (delivery-orchestrator, fase 6)')" "the stale §7 output example is gone too"
assert_eq "0" "$(has "$body" 'delivery-orchestrator` (fase 6')" "the scope paragraph now lists delivery as an available domain"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_orchestrator_delivery.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_orchestrator_delivery.sh`
Expected: FAIL en `root has a dedicated §12 section` y en el conteo de ocurrencias (hoy 4, se esperan
5).

- [ ] **Step 3: Añadir `## 12. Entrega` a `agents/orchestrator.md`**

Con `Edit`, inserta al FINAL del fichero (después de `### 11.4 Cierre`) esta sección completa. El
párrafo de §12.3 que empieza por "**Esa exención NO cubre…**" es **copia LITERAL** del §11.3 actual,
cambiando solo el nombre del orquestador y los números de sección — no lo reescribas de memoria (esa
es exactamente la lección 4 del handoff, un bug que ya recurrió en CUATRO dominios):

````markdown
## 12. Entrega (fase 6, spec §7 "Entrega")

### 12.1 Cuándo

**NUNCA encadenas automáticamente tras implementation, ni siquiera en `tier: full`.** Es el mismo
checkpoint humano de §10.1, y por una razón más fuerte: si escribir y fusionar código en local es la
acción más consecuente del enjambre, publicarlo —donde otras personas lo ven, lo revisan y lo
mergean— es la menos reversible. Lanzas `delivery-orchestrator` solo cuando el objetivo del owner lo
pide explícitamente ("publica la rama X", "abre el PR de Y", "prepara la entrega de Z"), nunca como
continuación de otro dominio.

Tres operaciones, tres invocaciones distintas, con el owner decidiendo en medio:

- `operation: prepare-release` — la primera vez, siempre. No sale nada de la máquina del owner.
- `operation: publish-release` — solo DESPUÉS del gate de §12.2, y solo si el owner aprobó.
- `operation: configure-remote` — solo DESPUÉS del gate de §12.2bis, y solo si `prepare-release`
  devolvió `BLOCKED sin remoto configurado` y el owner eligió crear o apuntar un remoto.

### 12.2 Gate de aprobación de push — nunca autorizas una publicación por tu cuenta

Un push a un remoto compartido, o un PR que otra persona mergea, no siempre se deshace. **Nunca
autorizas una publicación por criterio propio, ni siquiera si el objetivo del owner la pide en
abstracto ("saca esto ya") y ni siquiera en `tier: full`.** El camino es siempre este:

1. Lanza `operation: prepare-release` y quédate con sus líneas de preview
   (`- preview push:`, `- preview pr:`, `- remote:`, `- commits:`, `- verde:` y cualquier `- warn:`).
   Si vuelve `BLOCKED`/`KO`, ahí termina: propaga su veredicto (§12.3) y cierra el run — **con una
   sola excepción, `BLOCKED sin remoto configurado`, que no es un fallo sino una precondición que el
   owner puede resolver ahora mismo: ese caso va a §12.2bis, no a este cierre.** Para todos los
   demás, no hay pregunta que hacer sobre una publicación que no se puede preparar: un árbol sucio,
   una suite en rojo o un `HEAD` en rama protegida los arregla el owner en su repo, no una pregunta.
2. Presenta al owner UNA sola pregunta con `AskUserQuestion` (**single-select**, `multiSelect: false`
   — hay una sola decisión: se publica o no; §11.2 usa `true` porque allí el owner marca varios
   paquetes). Eres el ÚNICO agente del plugin con `AskUserQuestion` (spec §3.2 regla 7). El texto de
   la pregunta lleva, LITERALMENTE, los valores del preview: el remoto con su URL, la rama, la base,
   el número de commits y el estado del verde. **Si el preview trajo la línea
   `- warn: sin suite ejecutable — verde NO verificado`, esa frase va DENTRO del texto de la opción
   afirmativa**, no en una nota aparte: el owner tiene que aprobar sabiendo que el verde no está
   comprobado. "Desconocido" nunca se presenta como "verde".
   Las opciones son exactamente dos: publicar con esos valores, o no publicar.
3. Si el owner elige publicar, traduce **los valores del preview** (no su respuesta en prosa) a la
   línea literal:
   ```
   approved-push: remote=origin branch=feature/export-csv base=master
   ```
   Los tres campos, con esa sintaxis `clave=valor`, en ese orden, tomados del `- remote:` y del
   `- preview push:` que devolvió la hoja — **nunca a partir de un sí genérico**, nunca de memoria,
   nunca de lo que tú creas que es la rama actual. Si el owner elige no publicar, o cancela el
   diálogo, NO lanzas la fase B: cierras con
   `- run cerrado: DONE · publicación no autorizada por el owner` (§12.4).
4. Esa línea la construyes tú a partir de texto que viene de la hoja y del owner, así que **si la
   interpolas en cualquier `--text`/`--line` de shell pasa antes por el saneado de §5.0** (un nombre
   de rama puede llevar `$` y backtick legalmente; un mensaje de commit, casi siempre).
5. Lanza la fase B con un **tool `Agent` FRESCO**, no con `SendMessage` al `delivery-orchestrator`
   que sigue vivo. Va en contra de la regla general de reusar un agente vivo, y es deliberado: la
   aprobación tiene que viajar en una CABECERA DE LANZAMIENTO que la hoja pueda verificar como dato
   de entrada, y un relanzamiento limpio garantiza que `release-manager` re-ejecuta TODAS sus
   validaciones contra el estado real en vez de confiar en lo que alguien creía tener.

### 12.2bis Sin remoto configurado — el único `BLOCKED` que abre una decisión

Cuando `delivery-orchestrator` devuelve `BLOCKED sin remoto configurado`, **no cierras el run**. No es
un error del owner ni un fallo del enjambre: es una precondición que falta y que él puede resolver en
diez segundos si se lo preguntas bien. Es el mismo patrón de §12.2 —preview primero, aprobación que
NOMBRA el destino después— aplicado a la otra mutación externa del dominio.

1. **El preview ya te lo ha dado la hoja.** Su `BLOCKED` trae `- cuenta gh: <login> (activa) · último
   commit firmado por: <email>` y `- remoto propuesto: gh repo create <login>/<repo> --private
   --source=. --remote=origin --push`. **Tú no lo recalculas**: no tienes `gh` en tu allowlist y no
   ejecutas trabajo de hoja (spec §3.2 regla 4). Si por lo que sea esas dos líneas no vienen,
   entonces sí cierras el run propagando el `BLOCKED` — sin preview no hay pregunta honesta que
   hacer.
2. **UNA sola llamada a `AskUserQuestion`** (`multiSelect: false`), con el nombre exacto del repo, la
   cuenta bajo la que se crearía y el comando literal DENTRO del texto — nunca "¿creo un repo?" a
   secas. Cuatro opciones:
   - **A)** `Crear <login>/<repo> PRIVADO en GitHub y usarlo como origin` *(Recommended)*
   - **B)** `Crear <login>/<repo> PÚBLICO en GitHub y usarlo como origin`
   - **C)** `Ya tengo un remoto: pego la URL` — el owner la escribe en "Other"
   - **D)** `Nada: lo configuro yo a mano`
   Si `- cuenta gh:` dice `sin gh autenticado`, A y B no son ofrecibles: la pregunta se queda en C y
   D, y el texto lo explica. Si `- cuenta gh:` muestra una cuenta y un email que no casan entre sí,
   **esa discrepancia va DENTRO del texto de la pregunta**, igual que el `verde NO verificado` de
   §12.2: el owner aprueba con los ojos abiertos o no aprueba.
3. **Traduces la respuesta a una línea literal**, tomando los valores del preview y no de la prosa
   del owner:
   ```
   approved-remote: action=create name=<login>/<repo> visibility=private
   approved-remote: action=use url=<la URL que pegó el owner>
   ```
   (`visibility=public` con la opción B.) Antes de construir la forma `use`, **valida la URL**: tiene
   que empezar por `https://`, `git@`, `ssh://` o `file://` y no contener espacios ni ninguno de
   `; | & $ ` ( ) < > \`. Si no cumple, **no la sanees y no vuelvas a preguntar** (una tanda, §5.3):
   tu veredicto es `BLOCKED url de remoto malformada` y cierras el run como cualquier otro camino
   terminal (§12.3). Una URL que hay que limpiar para poder ejecutarla no es la que el owner quiso.
4. Con la opción **D**, o si el owner cancela el diálogo: no lanzas nada, propagas el
   `BLOCKED sin remoto configurado` original y cierras con
   `- run cerrado: BLOCKED sin remoto configurado` (§12.4). Que el owner diga "ya lo hago yo" es una
   respuesta válida, no un fallo.
5. Con **A**, **B** o **C**: lanza `operation: configure-remote` con un **tool `Agent` FRESCO**
   (mismo motivo que en §12.2: la aprobación viaja como cabecera de lanzamiento verificable), la
   línea `approved-remote:` y **sin** `approved-push:` — una aprobación no vale por la otra.
6. **Cuando `configure-remote` vuelve en `DONE`, no encadenas la entrega.** Cierras el run con
   `- run cerrado: DONE · remoto configurado, entrega pendiente de relanzar` y le dices al owner, con
   la línea `- siguiente:` de la hoja, que vuelva a lanzar la entrega. No es prudencia genérica: una
   `approved-push:` NOMBRA remoto, rama y base, y cuando el owner aprobó el remoto **la base todavía
   no existía**; encadenar exigiría fabricar una aprobación para un destino que él no ha visto, que
   es exactamente lo que §12.2 prohíbe.

### 12.3 Lanzamiento y reenvío del resultado

```
Agent(subagent_type: "swarm:delivery-orchestrator", name: "delivery-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <ruta absoluta de .swarm>
  operation: prepare-release | publish-release | configure-remote
  base: <rama base, solo si el owner la nombró explícitamente>
  approved-push: <la línea literal de §12.2 — SOLO en operation: publish-release>
  approved-remote: <la línea literal de §12.2bis — SOLO en operation: configure-remote>)
```

Las dos líneas de aprobación **nunca viajan juntas**: cada operación lleva la suya y solo la suya.

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run <run-id> --agent delivery-orchestrator --domain delivery --area "." --owner orchestrator
```

Reenvía sus líneas (`- preview push:`, `- preview pr:`, `- remote:`, `- commits:`, `- verde:`,
`- pushed:`, `- pr:`, `- pr manual:`, `- pr comando:`, `- notas:`, `- handoff:`, `- cuenta gh:`,
`- remoto propuesto:`, `- remoto creado:`, `- siguiente:`, `- hint:`) tal cual a tu propia
salida (§7) — igual mecanismo que §8.3/§9.3/§10.3/§11.3 para analysis/design/implementation/
requirements, SIN pasarlas por el saneado de §5.0 — esa exención vale únicamente para las líneas que
van a tu OUTPUT de turno (lo que lee `hooks/validate-output.py`), que nunca pasa por un shell, así
que no hay nada que proteger ahí.

**Esa exención NO cubre el `summary --line` del cierre.** Si `delivery-orchestrator` devuelve
`BLOCKED …`/`KO …`, propagas su veredicto literal como el tuyo — pero cerrar el run (§4, §12.4)
significa construir `"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" summary --run <run-id> --line
"<veredicto literal de delivery-orchestrator>"`, y eso SÍ es un `--line` nuevo que interpolas en un
comando de Bash real, con texto ajeno (el `<motivo>` de delivery-orchestrator, que puede citar el
mensaje de rechazo de un remoto o un asunto de commit, con backticks/`$(...)`). Ese `--line` pasa por
el saneado de §5.0 igual que cualquier otro `--line` de §4 que lleve texto ajeno — la única
diferencia con discovery es de dónde sale el texto (delivery-orchestrator en vez del owner), no si se
sanea. Cierra el run igual que en cualquier otro camino terminal (§4: `summary` saneado con la línea
de este camino y después `SendMessage(memory-orchestrator, "curate")`, esperando su `DONE`, antes de
devolver el veredicto).

### 12.4 Cierre

- preview listo, esperando decisión: `- run cerrado: DONE · entrega preparada, pendiente de aprobación`
- publicado: `- run cerrado: DONE · rama publicada y PR abierto`
- publicado sin PR (sin `gh`): `- run cerrado: DONE · rama publicada, PR pendiente de abrir a mano`
- owner no autorizó: `- run cerrado: DONE · publicación no autorizada por el owner`
- remoto configurado (§12.2bis): `- run cerrado: DONE · remoto configurado, entrega pendiente de relanzar`
- owner eligió configurar el remoto a mano (§12.2bis, opción D o diálogo cancelado):
  `- run cerrado: BLOCKED sin remoto configurado`
- URL pegada inválida (§12.2bis): `- run cerrado: BLOCKED url de remoto malformada`
- `BLOCKED`/`KO` propagado (§12.3): `- run cerrado: <veredicto literal de delivery-orchestrator>`
````

- [ ] **Step 4: Grep de regresión (lección 8) — quitar TODA la prosa de "delivery no existe"**

La raíz y los agentes ya construidos declaran honestamente, desde fase 5a, que el dominio delivery no
existe todavía. Ahora existe. **Son varios sitios, no uno** — ésta es exactamente la lección 8 del
handoff (un fix en un solo punto de un bug presente en varios). Localízalos todos:

```bash
grep -rn "fase 6\|delivery-orchestrator\|todavía sin construir\|TODAVÍA NO EXISTE" agents/ commands/ skills/ docs/USAGE.md docs/USAGE.es.md README.md README.es.md
```

Los tres sitios ya identificados en disco (2026-09-03), que hay que corregir SÍ o SÍ:

1. `agents/orchestrator.md`, párrafo **"Alcance actual (honesto, no aspiracional)"** (línea ~22):
   dice "El dominio `delivery-orchestrator` es fase 6 (spec §15) — TODAVÍA NO EXISTE. Si el objetivo
   requiere delivery, responde honestamente que el enjambre aún no cubre esa fase…". Pasa a listarlo
   como disponible, en la misma forma que los demás: "`delivery-orchestrator` (fase 6, §12 de este
   fichero — SOLO por invocación explícita del owner, con gate de aprobación de push)", y la lista de
   "lo que SÍ puedes hacer" deja de existir para este caso.
2. `agents/orchestrator.md`, **ejemplo de salida de §7** (línea ~563):
   `BLOCKED dominio no implementado (delivery-orchestrator, fase 6)`. Ese ejemplo ya es falso.
   Sustitúyelo por otro dominio realmente no implementado, o —mejor— por el caso honesto que sí queda
   (un objetivo que no casa con ningún dominio), ajustando el texto que lo introduce.
3. `agents/implementation-orchestrator.md`, sección "## Merge" (línea ~231): "Empujar o abrir PR es
   responsabilidad exclusiva de `delivery-orchestrator`/`release-manager` (fase 6, todavía sin
   construir); este dominio nunca toca remoto" pierde el inciso "(fase 6, todavía sin construir)" y
   conserva el resto intacto — la frase sigue siendo verdad y sigue siendo la que documenta la
   frontera entre los dos dominios.

**No cambies el sentido de ninguna frase: solo el hecho de que ya existe.** Si el `grep` devuelve un
cuarto sitio (por ejemplo en un README o en `docs/USAGE*.md`), entra también en este step.

- [ ] **Step 5: Actualizar la documentación de uso**

En `docs/USAGE.md` §3, el párrafo de cabecera dice hoy literalmente que los comandos son 3 y que
`/swarm:status` y `/swarm:findings` no están implementados. Sustitúyelo por la versión de 5 comandos
y añade una subsección para cada uno de los dos nuevos (formato idéntico al de `/swarm:doctor`:
qué hace, bloque con la sintaxis, y qué se ve). Añade además, en §4 ("The domains"), el bloque del
dominio **delivery** con las tres propiedades que el usuario necesita saber antes de usarlo:

1. no se encadena nunca — hay que pedirlo explícitamente;
2. son dos pasos con una pregunta en medio, y la aprobación nombra remoto/rama/base;
3. el swarm **nunca mergea el PR**: lo abre y lo deja para una persona;
4. si el repo **no tiene remoto**, el swarm no se queda ahí: pregunta si crear uno nuevo en tu cuenta
   de GitHub (privado por defecto) o usar uno que ya tengas, te enseña el `gh repo create …` exacto
   ANTES de que decidas, y tras configurarlo **te pide que relances la entrega** — no encadena el
   push por su cuenta.

Y en las dos subsecciones nuevas de comandos, una línea sobre el modo degradado: si el script no
puede interpretar algún dato de `.swarm/`, el comando lo dice con `- warn: modo degradado …` y da un
resumen best-effort; nunca presenta un resultado incompleto como si fuera el normal.

Replica los mismos cambios en `docs/USAGE.es.md` (mismo contenido, en español; los dos ficheros son
traducciones el uno del otro, no versiones distintas).

- [ ] **Step 6: Confirmar que el test de la raíz pasa**

Run: `bash tests/test_orchestrator_delivery.sh`
Expected: sin `FAIL`, exit 0 — incluido el conteo de **5** ocurrencias del párrafo de exención.

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 49, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/orchestrator.md agents/implementation-orchestrator.md docs/USAGE.md docs/USAGE.es.md tests/test_orchestrator_delivery.sh
git commit -m "feat(delivery): integra el dominio delivery en la raiz (12) con gate de aprobacion de push"
```

---

### Task 7: Checklist de smoke EN VIVO (con remoto bare desechable) + cierre de fase

**Files:**
- Create: `docs/superpowers/plans/2026-09-03-phase6-smoke-checklist.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: evidencia real de ejecución. Es el gate antes de dar la fase —y v1— por cerrada.

> **El fixture es la parte nueva de este smoke.** Todas las fases anteriores se verificaron contra
> fixtures locales; ésta necesita ejercitar un `git push` REAL sin tocar ningún host de red. La
> solución es un **repo bare local** como remoto: `git init --bare` en un tmp dir y `git remote add
> origin file://<ruta>`. Un push contra él es un push de verdad (recorre el mismo camino de git, el
> mismo hook `bash-guard`, el mismo `git push <remote> <rama>`) y no sale de la máquina. Ningún paso
> de este checklist toca GitHub/GitLab ni ningún remoto real.

- [ ] **Step 1: Escribir el checklist (plantilla, se rellena en vivo)**

```bash
cat > docs/superpowers/plans/2026-09-03-phase6-smoke-checklist.md <<'EOF'
# Checklist de smoke — Fase 6 (dominio delivery + /swarm:status + /swarm:findings)

Gate. **Ninguna parte AUTOMÁTICA de este checklist toca un remoto real.** Todo el ejercicio de push
corre contra un repo bare local desechable. La única excepción está marcada como tal y es
**opcional**: el `action=create` del ítem 10, que crea un repositorio real en la cuenta del owner y
solo se ejecuta si él lo pide expresamente (y se borra después).

## Fixture (montarlo ANTES de nada, y borrarlo al final)

```bash
SMOKE="$(mktemp -d "${TMPDIR:-/tmp}/swarm-phase6.XXXXXX")"
git init --bare "$SMOKE/remote.git"
git init "$SMOKE/repo" && cd "$SMOKE/repo"
git config user.email "garcia.gordo.david@gmail.com" && git config user.name "David García Gordo"
echo "# fixture" > README.md && git add README.md && git commit -m "chore: initial"
git remote add origin "file://$SMOKE/remote.git"
git push origin master        # el humano publica la base; el agente NUNCA empuja master
git switch -c feature/smoke
echo "cambio" >> README.md && git add README.md && git commit -m "feat: cambio de smoke"
```

Limpieza al terminar: `rm -rf "$SMOKE"`. Anota la ruta usada:

## 1. Sin remoto → `BLOCKED` **con preview**, cero mutaciones

Contra un segundo fixture SIN `git remote add`: `release-manager` en adhoc con
`operation: prepare-release` → `BLOCKED sin remoto configurado` + línea de hint, y **nada escrito**
(comprobar que no existe `release-notes.md`). Comprobar además las dos líneas de preview del
ruling 3, sin las cuales la raíz no puede preguntar nada: `- cuenta gh: <login> (activa) · último
commit firmado por: <email>` y `- remoto propuesto: gh repo create <login>/<basename> --private
--source=. --remote=origin --push`. Y que **el comando propuesto NO se ha ejecutado** (`gh repo list`
a mano, o simplemente que `git remote -v` del fixture sigue vacío).

*(Nota de contexto: hasta el 2026-09-03 el propio repo del plugin era este caso — `git remote -v`
vacío. Ese mismo día se le creó su remoto a mano, `origin
git@github-personal-david:davidgarciagordo/swarm.git`, y de ahí salió el ruling 14. El caso "sin
remoto" ya solo se reproduce con un fixture.)*
Evidencia:

## 2. Árbol sucio y rama protegida → `KO`/`BLOCKED` antes de tocar el remoto

En el fixture: (a) con un fichero sin commitear → `KO árbol sucio: <n> ficheros sin commitear`;
(b) desde `master` → `BLOCKED HEAD en rama protegida, nada que publicar` con su hint.
Evidencia:

## 3. Fase A: preview real, sin que salga nada de la máquina

Desde `feature/smoke`: `operation: prepare-release`. Verificar las tres cosas a la vez:
- la salida trae `- preview push:` y `- preview pr:` con valores REALES (no plantillas);
- `.swarm/run/<id>/release-notes.md` existe y lista el commit de smoke;
- **el bare no ha recibido nada**: `git -C "$SMOKE/remote.git" branch --list` NO muestra
  `feature/smoke`. Esta última comprobación es la que demuestra que la fase A no publica.
Evidencia:

## 4. Fase B sin aprobación, y con aprobación mal formada → dos rechazos distintos

- Sin línea `approved-push:` → `BLOCKED sin aprobación de push`, `cmds=0`.
- Con `approved-push: sí` → `BLOCKED aprobación de push malformada`.
- Con `approved-push: remote=origin branch=OTRA base=master` (rama que no es HEAD) →
  `BLOCKED aprobación no coincide con el estado real`.
En los tres casos, `git -C "$SMOKE/remote.git" branch --list` sigue sin `feature/smoke`.
**Éste es el mecanismo más consecuente de todo el proyecto: no darlo por bueno por lectura de
código.**
Evidencia:

## 5. Fase B con aprobación correcta → push REAL al bare

`approved-push: remote=origin branch=feature/smoke base=master` →
`git -C "$SMOKE/remote.git" log --oneline feature/smoke` muestra el commit de smoke. `gh pr create`
fallará (el remoto es `file://`, no GitHub): comprobar que el veredicto sigue siendo `DONE`, con
`- pushed:` y con las dos líneas de degradación `- pr manual:` / `- pr comando:` — y **no** un `KO`.
Evidencia:

## 6. El guard deniega lo que la prosa promete (contra el hook REAL, con `agent_type` real)

`git push origin master`, `git push --force origin feature/smoke`, `git push` a secas,
`gh pr merge 1`, `git remote add x y` — todos denegados para `swarm:release-manager`; y
`git push origin feature/smoke` denegado para `swarm:delivery-orchestrator`.
Evidencia:

## 7. Handoff en el camino feliz y en el bloqueado

El MD de relevo aparece en las dos corridas (la del ítem 1, con `BLOCKED`, y la del ítem 5), con las
secciones "Prompt copy-paste", "Dónde está todo" y "Siguiente paso", **sin commitear**
(`git status --porcelain` lo muestra como untracked). En el caso bloqueado, "Siguiente paso" tiene
que ser el hint del `BLOCKED`, no una frase genérica.
Evidencia:

## 8. `/swarm:status` y `/swarm:findings` contra un `.swarm/` real

Sobre el repo del plugin (que ya tiene un run real de fase 2 en `.swarm/run/`): `/swarm:status`
imprime run, tier, agentes y conteo de hallazgos abiertos; `/swarm:findings value-critic` filtra;
`/swarm:findings 'a b'` termina en `exit 64` sin ejecutar nada. Verificar además que **ninguno de los
dos lanza un subagente** (no aparece agente nuevo en el manifest del run).
Evidencia:

## 9. Cadena completa por la raíz, con `AskUserQuestion` real

Sesión interactiva (no headless: `AskUserQuestion` no se simula — aprendizaje de fase 2):
`/swarm:run "publica la rama feature/smoke"` sobre el fixture. Comprobar que la raíz **no encadena**
desde ningún otro dominio, que la pregunta muestra remoto/rama/base/commits/verde, y que al elegir
"no publicar" el cierre es `- run cerrado: DONE · publicación no autorizada por el owner` con el bare
intacto.
Evidencia:

## 10. `configure-remote` — gate, `action=use` contra el bare, y el `create` MANUAL y opcional

Los tres primeros son automáticos y no tocan la red; el cuarto es opcional y lo decide el owner.

- **Gate sin cabecera**: `operation: configure-remote` sin línea `approved-remote:` →
  `BLOCKED sin aprobación de remoto`, `cmds=0`, y `git remote -v` del fixture sigue vacío.
- **Gate malformado**: `approved-remote: sí`, `approved-remote: action=create name=x` (sin
  `visibility=`), `approved-remote: action=use url=x y` (con espacio) y
  `approved-remote: action=use url=https://a.b/c;id` → los cuatro,
  `BLOCKED aprobación de remoto malformada`, sin ejecutar nada.
- **`action=use` real contra el bare**: `approved-remote: action=use url=file://$SMOKE/remote.git` en
  un fixture sin remoto → `DONE` con `- remote:` y `- siguiente:`, `git remote -v` lista `origin`,
  `remote-setup.md` existe con el comando literal, y **el bare NO ha recibido ninguna rama nueva**
  (`git -C "$SMOKE/remote.git" branch --list` igual que antes): configurar no es publicar.
- **Remoto ya existente**: repetir el paso anterior sobre el mismo fixture →
  `BLOCKED ya hay remoto configurado: origin file://…`, y la URL **no** se ha reescrito.
- **`action=create` (MANUAL, opcional, crea un repo real)**: solo si el owner quiere ejercitarlo.
  Comprobar antes que `gh auth status` da la cuenta personal (`davidgarciagordo`) y que
  `git log -1 --format=%ae` da `garcia.gordo.david@gmail.com` (ruling 14). Si el push inicial falla
  con `denied to <otra cuenta>`, el veredicto tiene que ser
  `BLOCKED remoto creado pero push rechazado:` **con el stderr literal íntegro** y la línea de hint
  del alias SSH — no un `KO` genérico ni un mensaje recortado. Borrar el repo de prueba después.
Evidencia:

## 11. Modo degradado de `/swarm:status` y `/swarm:findings` (ruling 12)

Sobre una copia desechable de `.swarm/`: truncar `run/<id>/run.json` a la mitad → el script sale con
`exit 2`, imprime `no interpretable: …` y todo lo que sí pudo leer, y el comando **antepone**
`- warn: modo degradado — swarm-status.sh falló (exit 2)` antes del resumen best-effort. Mismo
ejercicio con una línea `- [algo]` sin cabecera `[key:…]` en `findings/*.md` para
`/swarm:findings`. Verificar las dos propiedades que hacen que el fallback no sea un agujero de
coste: con `exit 0`, `1` y `64` **no se lee ni un fichero extra**, y en el degradado **no se lanza
ningún subagente** (no aparece agente nuevo en el manifest).
Evidencia:

## 12. Nada del repo del plugin se ha publicado, y el fixture está borrado

En el checkout real del plugin: `git remote -v` sigue mostrando **exactamente** el remoto que ya
tenía (`origin git@github-personal-david:davidgarciagordo/swarm.git` — el que se creó a mano el
2026-09-03), sin remotos añadidos ni URLs reescritas por ningún agente; y
`git log --all --oneline | head -5` no muestra commits inesperados. **Comprobar también que ninguna
rama del plugin ha llegado a ese remoto por accidente durante el smoke**
(`git ls-remote --heads origin`). Y el fixture borrado: `rm -rf "$SMOKE"`.
Evidencia:

## Firma

- [ ] Owner: ________________ Fecha: ________________
EOF
```

- [ ] **Step 2: Ejecutar el smoke EN VIVO**

Metodología headless (`claude -p --plugin-dir <este worktree> --permission-mode bypassPermissions`)
contra el fixture desechable, salvo el ítem 9 (necesita sesión interactiva real: `AskUserQuestion` no
se simula) y el `action=create` opcional del ítem 10 (lo lanza el owner, a mano, sobre su cuenta
real). Si aparece un
bug real, **se arregla en el momento** (regla del owner: "arregla todos los bugs que encuentres
siempre") y se anota en el checklist qué se arregló — en CADA fase anterior el smoke en vivo encontró
bugs que ninguna review de lectura pilló.

- [ ] **Step 3: Review final de rama (Opus, sobre TODO el diff de la fase)**

Mismo patrón que fases 1-5b. Foco explícito, además de lo habitual:
1. **Que no exista NINGUNA vía de push que no pase por el gate `approved-push:`, ni ninguna vía de
   crear/añadir un remoto que no pase por `approved-remote:`** — incluida la posibilidad de que
   `delivery-orchestrator` construya cualquiera de las dos líneas él mismo, de que la reconstruya a
   partir del preview en vez de copiarla de su cabecera, o de que **use una aprobación como si fuera
   la otra**.
2. **Que el backstop de `hooks/bash-guard.py` no tenga un agujero de forma** (refspecs, flags
   pegados, clusters, `refs/heads/`, `+`, `:dst`; y en las reglas nuevas: flags fuera del conjunto
   cerrado de `gh repo create`, un flag colado ANTES del subcomando —`git remote -v set-url`—, y
   cualquier `gh repo` que no sea `create`) — y que no haya un SEGUNDO punto del fichero que trate
   `git push`, `git remote` o `gh repo` sin pasar por él (lección 8).
2bis. **Que `release-manager` no reescriba ni fabrique NUNCA una URL de remoto** (ruling 14): ni
   `git remote set-url`, ni parseo de `~/.ssh/config`, ni una URL construida a mano; y que los
   errores de `git`/`gh` viajen literales hasta el veredicto de la raíz, sin recortar.
3. Que las líneas de salida de las tres piezas nuevas casen EXACTAMENTE entre agente emisor,
   orquestador que reenvía y raíz que cierra (nombres de operación, forma de `approved-push:`, rutas).
4. Que ninguna plantilla de veredicto nueva use `DONE · <detalle>` (lección 7) — más allá de lo que
   ya cubre `tests/test_verdict_templates_valid.sh`.
5. Que `/swarm:findings` no pueda ejecutar nada con un argumento hostil, por ninguna vía.

Un solo fix wave con re-review escopeada al diff del fix (el patrón que salvó las fases 5a y 5b de
bugs Critical reales).

- [ ] **Step 4: Commit del checklist relleno**

```bash
git add docs/superpowers/plans/2026-09-03-phase6-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 6 relleno con evidencia real de ejecucion en vivo"
```

- [ ] **Step 5: `finishing-a-development-branch` → merge → handoff de cierre de v1**

Verificar la suite (49/49), mergear local a `master` (instrucción permanente del owner, sin
preguntar), limpiar worktree/rama, y escribir el handoff final. Esta vez el handoff no apunta a "la
fase siguiente": apunta a **la decisión de v1**. Debe incluir:
- El roster completo cerrado: 30 agentes propios (1 raíz + 3 memoria + 5 requirements + 5 discovery +
  7 analysis + 4 diseño + 7 implementation + 3 delivery — comprobar el conteo real contra
  `ls agents/*.md`, no darlo por bueno de memoria) y 5 comandos.
- El **backlog completo acumulado** de las reviews de fases 1-6, con lo nuevo de esta fase:
  `hooks/bash-guard.py` sigue sin inspeccionar `$(...)` dentro de argumentos sin comillas (ahora más
  relevante: hay un agente con `git push` y con `gh repo create`); `release-manager` no crea tags ni
  edita `CHANGELOG.md` (ruling 7); la lista de ramas protegidas es de 4 nombres fijos, no la base
  real del remoto; `release-manager` publica la rama actual y no crea `release/<slug>` (ruling 5);
  el modo de fallo de identidad SSH se **reporta** pero no se detecta de forma estructurada (ruling
  14, opción (b) deliberada — si algún día duele, la opción (a) queda como backlog explícito); el
  `action=create` de `configure-remote` no tiene cobertura automática de extremo a extremo (crea un
  repo real), solo gates y guard.
- Qué se arregla ANTES de declarar v1 y qué queda como backlog post-v1 documentado — esa es la
  decisión que el owner tiene que tomar, y el handoff debe presentársela, no tomarla.

---

## Self-Review

**1. Cobertura del spec.**

| requisito del spec | tarea |
|---|---|
| §7 fila `delivery-orchestrator` (domain-orchestrator, haiku, 10, "secuencia release + handoff") | Task 4 |
| §7 fila `release-manager` (leaf, sonnet, 15, "rama, PR, changelog, merge en verde") | Task 2 (+ ruling 4 sobre "merge en verde" y ruling 7 sobre "changelog") |
| §7 fila `handoff-writer` (leaf, haiku, 8, "handoff MD de relevo de sesión") | Task 3 |
| §7.0 modelo por tier (delivery → haiku; `handoff-writer` hoja mecánica → haiku) | Global Constraints + `tests/test_delivery_agents.sh` / `test_delivery_orchestrator_spawns.sh` |
| §3.2 regla 4 (el orquestador de dominio nunca ejecuta trabajo de hoja) | Task 4 (sin `git push`/`gh` en su allowlist — Task 1) |
| §3.2 regla 7 (solo la raíz pregunta al owner) | Tasks 2, 3, 4 (sin `AskUserQuestion`) + Task 6 (§12.2) |
| §11 `/swarm:status` (run actual, agentes activos, tier, coste si está disponible) | Task 5 — coste: el CLI no lo expone por run, se omite honestamente (§16 lo excluye) |
| §11 `/swarm:findings [agente\|tag]` | Task 5 |
| §11 `run/<id>/summary.md` visible al usuario | Task 5 (`swarm-status.sh` lo imprime) |
| §12 `commands/status.md`, `commands/findings.md` en la estructura del plugin | Task 5 (+ declarados en `plugin.json`) |
| §15 fase 6 "3 agentes + comandos `/swarm:status`, `/swarm:findings`" | Tasks 2, 3, 4, 5 |
| §15 fase 6 "Opcional: modo Agent Teams tras flag" | **Fuera de alcance declarado** (§16 lo excluye de v1) — sección "Alcance" |
| §6 contrato de evidencia en los 3 agentes nuevos | Global Constraints + `tests/test_verdict_templates_valid.sh` extendido en Tasks 2, 3, 4 |
| §14 (smoke tests en `tests/`) | Task 7, con fixture bare-repo nuevo |
| §14bis (gate `swarm:verifier`, v2.2) | **fuera de alcance declarado** — sin fase asignada en §15, lo lleva la sesión peer; §12.3 se escribe para heredarlo vía §4 sin cambios |
| §7 "Entrega" — bootstrap del remoto (`configure-remote`) | Task 2b + Task 6 §12.2bis. **No está en el spec**: es una decisión del owner del 2026-09-03 (ruling 3), y se implementa DENTRO del dominio delivery, no como dominio nuevo — ver "¿es esto delivery o requisitos?" más abajo |

**¿El bootstrap de remoto es "delivery" o se cuela en "requisitos"?** Es una pregunta legítima:
`requirements-orchestrator` es el dominio que comprueba y arregla precondiciones del entorno
(`env-checker`, `dependency-installer`), y "no hay remoto" suena a precondición. La decisión es
**delivery**, por tres razones verificables contra el diseño existente: (a) el dato que falta solo
existe en el vocabulario de delivery —remoto, rama, base, PR—, y `requirements` no sabe nada de
publicación; (b) quien detecta la falta es `release-manager`, en su propia secuencia de validaciones,
y mover la reparación a otro dominio partiría en dos un flujo con un único gate humano; (c) el
precedente de `dependency-installer` no es "requisitos arregla cualquier precondición" sino "quien
muta algo del entorno lo hace con aprobación itemizada del owner" — y eso es exactamente lo que hace
`configure-remote`, en su propio dominio. Consecuencia asumida: el dominio delivery deja de tocar
solo el repo y pasa a poder crear un recurso en una cuenta externa; por eso el ruling 2e le exige la
misma disciplina que al push, y por eso el guard lo acota a `gh repo create` y a `git remote add`.

**Huecos conscientes, todos marcados como rulings revisables:** "changelog" se implementa como notas
de release en `.swarm/`, no editando el `CHANGELOG.md` del repo (ruling 7); "rama" se implementa como
validar/nombrar la rama actual, no crear una nueva (ruling 5); "merge en verde" se implementa como
verde local previo al push, nunca como auto-merge del PR (ruling 4 — y esto NO es revisable: es una
frontera de seguridad permanente); el coste acumulado de `/swarm:status` se omite porque el CLI no lo
expone (§16 excluye telemetría de coste de v1).

**2. Escaneo de placeholders.** Ninguna tarea contiene "TBD", "similar a la Task N", "añadir manejo
de errores apropiado" ni un paso de código sin su bloque. El contenido de los 3 agentes, los 2
scripts, los 2 comandos y los 7 tests va literal y completo. Los `<placeholders>` angulares que
aparecen (`<remote>`, `<branch>`, `<base>`, `<pack>`, `<repo-root>`, `<run-id>`) son parte deliberada
del contrato de prompt y están definidos donde se usan.

**3. Consistencia de tipos e interfaces entre tareas.**

- **Las DOS líneas de aprobación** son el interfaz crítico de toda la fase, tienen la misma forma
  (cabecera `clave=valor` que NOMBRA el destino) y cada una aparece idéntica en cinco sitios:
  `agents/release-manager.md` (quien la exige y la parsea, Tasks 2 y 2b),
  `agents/delivery-orchestrator.md` (quien la reenvía literal, Task 4), `agents/orchestrator.md`
  §12.2 / §12.2bis (quien las CONSTRUYE, Task 6), y los tests `test_delivery_agents.sh` /
  `test_delivery_orchestrator_spawns.sh` / `test_orchestrator_delivery.sh`, que las fijan con
  `grep -F 'approved-push: remote='` y `grep -F 'approved-remote: action='`. Formas únicas:
  `approved-push: remote=<remote> branch=<branch> base=<base>`,
  `approved-remote: action=create name=<owner>/<repo> visibility=<public|private>` y
  `approved-remote: action=use url=<url>`. **Ninguna de las dos vale por la otra**, y esa frase está
  escrita explícitamente en los tres ficheros que las manejan.
- **Nombres de operación**: `prepare-release`, `publish-release` y `configure-remote` viajan sin
  traducción desde la raíz (§12.3) → `delivery-orchestrator` → `release-manager`; `handoff` es el
  único de `handoff-writer`. Cada cadena aparece idéntica en el emisor, el receptor y el test.
- **El camino "sin remoto" es coherente de punta a punta**, y esa coherencia es lo que la revisión
  del owner rompió y hubo que rehacer: la hoja bloquea CON preview (Task 2), el orquestador de
  dominio reenvía el preview sin evaluarlo (Task 4), la raíz es la única que pregunta y la única que
  construye la aprobación (Task 6 §12.2bis), la hoja ejecuta bajo gate (Task 2b) y nadie encadena la
  entrega después. La frase que la versión anterior tenía en §12.2 —"no hay pregunta que hacer sobre
  una publicación que no se puede preparar"— habría contradicho todo esto, y por eso el test
  `test_orchestrator_delivery.sh` comprueba explícitamente que **ya no está** en el fichero.
- **Líneas de salida reenviadas**: `- preview push:`, `- preview pr:`, `- remote:`, `- commits:`,
  `- verde:`, `- pushed:`, `- pr:`, `- pr manual:`, `- pr comando:`, `- notas:`, `- handoff:`,
  `- warn: …`. Definidas en Task 2/Task 3 (`Produces`), reenviadas sin reformular en Task 4 y Task 6.
  Todas empiezan por `- ` y caben en 120 caracteres → las acepta `hooks/validate-output.py`.
- **Veredictos literales** que aparecen en más de un fichero y deben casar carácter a carácter:
  `BLOCKED sin remoto configurado`, `BLOCKED HEAD en rama protegida, nada que publicar`,
  `BLOCKED base indeterminada`, `BLOCKED sin aprobación de push`,
  `BLOCKED aprobación de push malformada`, `BLOCKED aprobación no coincide con el estado real`,
  `BLOCKED árbol sucio: <n> ficheros sin commitear`, `KO tests en rojo: <motivo>`,
  `KO push rechazado: <stderr literal>`, `BLOCKED sin contexto de entrega`, y los de Task 2b:
  `BLOCKED sin aprobación de remoto`, `BLOCKED aprobación de remoto malformada`,
  `BLOCKED ya hay remoto configurado: <nombre> <url>`, `BLOCKED sin gh autenticado`,
  `BLOCKED remoto creado pero push rechazado: <stderr literal>`,
  `KO no se pudo crear el repositorio: <stderr literal>`,
  `KO no se pudo añadir el remoto: <stderr literal>`, más el de la raíz
  `BLOCKED url de remoto malformada`. Todos con sufijo tras `KO`/`BLOCKED` (permitido) y **ningún
  `DONE`/`OK` con sufijo** (lección 7).
- **Recorte del motivo: dos reglas distintas, a propósito.** `KO tests en rojo:` recorta a ≤60
  caracteres (la primera línea de fallo es representativa); todo lo que venga de `git`/`gh` va
  **íntegro y literal** (ruling 14). La distinción está escrita en `agents/release-manager.md`
  ("Errores de `git`/`gh`") y repetida en el reenvío de `delivery-orchestrator`, que es donde se
  perdería si alguien la recortara "por limpieza".
- **Líneas largas y `hooks/validate-output.py`**: las nuevas (`- remoto propuesto:`,
  `- remoto creado:`, `- cuenta gh:`, `- hint:`, `- siguiente:`, `- discrepancia:`) pasan de 120
  caracteres y están exentas **por forma** en `DELIVERY_LONG_RE` (Task 2 Step 4), no por llevar
  `- ` delante. Sin esa extensión, el `- hint:` del ruling 14 (~150 caracteres) sería rechazado por
  el hook justo en el camino de error donde más falta hace — es la cuarta aparición del mismo bug de
  fondo (C1 de fase 2, Important #1 de fase 4, preview de esta fase).
- **Ruta del artefacto de notas**: `<swarm-root>/run/<run-id|adhoc>/release-notes.md`, idéntica en
  Task 2 (quien la escribe), en la línea `- notas:` que reenvían Tasks 4 y 6, y en el ítem 3 del
  smoke (Task 7).
- **Forma de push permitida**: `git push <remote> <rama>` — fijada por el guard en Task 1
  (`push_segment_denied`), documentada en Task 2, probada en `tests/test_push_guard.sh` y
  ejercitada de verdad en el ítem 5 del smoke.
- **Contrato de los scripts de visibilidad**: `swarm-status.sh` (sin argumentos; exit 0/1) y
  `swarm-findings.sh [filtro] [--all]` (exit 0/1/64) — definidos en Task 5 (`Produces`), consumidos
  con esa firma exacta por `commands/status.md`, `commands/findings.md` y sus dos tests.
- **Conteo de ficheros de test**: 42 hoy → +7 (`test_push_guard.sh`,
  `test_bash_allowlist_delivery.sh`, `test_delivery_agents.sh`,
  `test_delivery_orchestrator_spawns.sh`, `test_swarm_status.sh`, `test_swarm_findings.sh`,
  `test_orchestrator_delivery.sh`) = **49** al cerrar la fase. Los `Expected: files: N` de cada tarea
  siguen esa progresión: 44 (T1), 45 (T2), **45 (T2b)**, 45 (T3), 46 (T4), 48 (T5), 49 (T6). La Task
  2b no crea ficheros de test: extiende `tests/test_delivery_agents.sh`, igual que la Task 3.
- **Contrato de salida de los dos scripts de visibilidad**: 0 / 1 / 64 / **2**, idéntico en los dos,
  definido en Task 5 (`Produces`), implementado en los dos scripts, ejercitado por
  `test_swarm_status.sh` (caso 4) y `test_swarm_findings.sh` (caso 6), y consumido con esos mismos
  cuatro códigos por `commands/status.md` y `commands/findings.md`. El fallback se dispara con
  **exit ∉ {0,1,64}** en los dos ficheros de comando, con la misma redacción.

**4. Tamaño de las tareas tras la revisión del owner.** El bootstrap de remoto es alcance NUEVO y
real: una segunda mutación externa completa. Se decidió **partirla en la Task 2b** en vez de
engordar la Task 2 (que ya escribe un fichero de agente de ~300 líneas) — así la Task 2 sigue siendo
una unidad verificable por sí sola ("publicar una rama que ya existe") y el owner puede revertir el
bootstrap entero con un `git revert` si cambia de idea. Las otras tres tareas tocadas crecen sin
dejar de ser una unidad: **Task 1** suma dos mecanismos de guard (`SUBCOMMAND_ALLOWED_ARGS` y los dos
verificadores de forma) y ~20 aserciones, y sigue siendo "el backstop determinista"; **Task 6** suma
§12.2bis, que es una sección más en el fichero que ya iba a editar; **Task 5** suma el `exit 2` a los
dos scripts y el fallback a los dos comandos. Ninguna de ellas cambia de fichero-objetivo ni de
commit.
- **Conteo del párrafo de exención de saneado** en `agents/orchestrator.md`: 4 hoy → **5** tras Task
  6, aserción explícita en `tests/test_orchestrator_delivery.sh`.
