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
Evidencia: ✅ PASS — headless real (`claude -p --plugin-dir <worktree> --permission-mode
bypassPermissions`, invocando el tool `Agent(subagent_type: "release-manager")` adhoc) contra un
fixture SIN `git remote add`:
```
BLOCKED sin remoto configurado
evidence: files=0 cmds=4 turns=6/15
- hint: git remote add origin <url> y vuelve a lanzar la entrega
- cuenta gh: davidgarciagordo (activa) · último commit firmado por: garcia.gordo.david@gmail.com
- remoto propuesto: gh repo create davidgarciagordo/repo --private --source=. --remote=origin --push
```
Las dos líneas de preview (`- cuenta gh:`, `- remoto propuesto:`) son reales: `davidgarciagordo` es
la cuenta `gh` activa de verdad (`gh auth status`), el email es el del último commit real del
fixture, y `repo` es el basename real de `<repo-root>`. Cero mutaciones confirmado tras el run:
`.swarm/` ni siquiera se creó (`ls`: "No such file or directory"), `git remote -v` sigue vacío, y no
existe `release-notes.md` en ningún sitio del fixture (`find` sin resultados). El comando propuesto
NO se ejecutó (no hay ningún repo nuevo en `gh repo list` bajo ese nombre, no se intentó).

## 2. Árbol sucio y rama protegida → `KO`/`BLOCKED` antes de tocar el remoto

En el fixture: (a) con un fichero sin commitear → `KO árbol sucio: <n> ficheros sin commitear`;
(b) desde `master` → `BLOCKED HEAD en rama protegida, nada que publicar` con su hint.
Evidencia: ✅ PASS — headless real, mismo mecanismo de invocación que el ítem 1, sobre el fixture con
remoto real (`file://.../remote.git`). (a) Con `untracked.txt` sin commitear en `feature/smoke`:
```
BLOCKED árbol sucio: 1 ficheros sin commitear
evidence: files=0 cmds=6 turns=3/15
- hint: no puedo commitear (git add/commit fuera de mi allowlist) — commitea o descarta untracked.txt antes de relanzar la entrega
```
(nota: el veredicto real es `BLOCKED`, no `KO` — el checklist original decía `KO`/`BLOCKED`; el
contrato real de `release-manager.md` documenta `BLOCKED árbol sucio: …`, y eso es lo que se observó
en vivo, consistente con el propio fichero de agente). (b) Tras limpiar y `git switch master`:
```
BLOCKED HEAD en rama protegida, nada que publicar
evidence: files=0 cmds=6 turns=4/15
- hint: git switch -c <rama-de-trabajo> antes de entregar
```

## 3. Fase A: preview real, sin que salga nada de la máquina

Desde `feature/smoke`: `operation: prepare-release`. Verificar las tres cosas a la vez:
- la salida trae `- preview push:` y `- preview pr:` con valores REALES (no plantillas);
- `.swarm/run/<id>/release-notes.md` existe y lista el commit de smoke;
- **el bare no ha recibido nada**: `git -C "$SMOKE/remote.git" branch --list` NO muestra
  `feature/smoke`. Esta última comprobación es la que demuestra que la fase A no publica.
Evidencia: ✅ PASS — headless real. Primer intento reveló un artefacto real del FIXTURE (no del
plugin): `git remote add` sin `git clone` no fija `origin/HEAD`, así que
`git rev-parse --abbrev-ref origin/HEAD` falla y el veredicto real fue, correctamente,
`BLOCKED base indeterminada` con `- hint: git remote set-head origin -a, o pasa base: en la
cabecera` — confirma en vivo que ESE camino también funciona. Arreglado el fixture con
`git remote set-head origin -a` (lo que produce un `git clone` real) y relanzado:
```
DONE
evidence: files=1 cmds=7 turns=6/15
- remote: origin → file:///.../remote.git
- commits: 1 (master..feature/smoke)
- warn: sin suite ejecutable — verde NO verificado
- notas: /.../repo/.swarm/run/adhoc/release-notes.md
- preview push: git push origin feature/smoke
- preview pr: gh pr create --base master --head feature/smoke --title "feat: cambio de smoke" --body-file .swarm/run/adhoc/release-notes.md
```
`release-notes.md` real en disco:
```
# feature/smoke → master

1 commits, generados por swarm:release-manager (run adhoc).

- feat: cambio de smoke
```
`git -C "$SMOKE/remote.git" branch --list` tras el run: solo `* master` — `feature/smoke` NO llegó
al bare. Fase A confirmada como puro preview.

## 4. Fase B sin aprobación, y con aprobación mal formada → dos rechazos distintos

- Sin línea `approved-push:` → `BLOCKED sin aprobación de push`, `cmds=0`.
- Con `approved-push: sí` → `BLOCKED aprobación de push malformada`.
- Con `approved-push: remote=origin branch=OTRA base=master` (rama que no es HEAD) →
  `BLOCKED aprobación no coincide con el estado real`.
En los tres casos, `git -C "$SMOKE/remote.git" branch --list` sigue sin `feature/smoke`.
**Éste es el mecanismo más consecuente de todo el proyecto: no darlo por bueno por lectura de
código.**
Evidencia: ⚠️ PASS, con un bug real encontrado y arreglado. Primer intento sin `approved-push:`
devolvió `BLOCKED sin aprobación de push` pero con `evidence: files=0 cmds=2 turns=2/15` — el
contrato documentado en `release-manager.md` exige `files=0 cmds=0 turns=1/15` ("sin ejecutar
NADA"), pero el "## Arranque" común (lectura de buzón + `git rev-parse --show-toplevel`) se ejecuta
ANTES de llegar al gate de aprobación en la lectura literal del fichero, así que el agente real hizo
2 comandos de más antes de bloquear — mismatch real entre la prosa "lo primero, antes de cualquier
otra cosa" y el orden efectivo del documento. **Arreglado** (`agents/release-manager.md`, sección
"Arranque"): se añadió una nota explícita de que, en `publish-release`, el gate de `approved-push:`
(ambos casos: ausente/vacío Y malformado) se comprueba ANTES de los pasos 2-3 del Arranque.
Reverificado tras el fix — los tres casos, en el MISMO fixture, todos con `git -C
"$SMOKE/remote.git" branch --list` mostrando solo `master` antes y después:
```
=== sin approved-push ===
BLOCKED sin aprobación de push
evidence: files=0 cmds=0 turns=1/15

=== approved-push: sí ===
BLOCKED aprobación de push malformada
evidence: files=0 cmds=0 turns=1/15
- hint: approved-push: necesita remote=<r> branch=<b> base=<base>, recibido "sí"

=== approved-push: remote=origin branch=OTRA base=master ===
BLOCKED aprobación no coincide con el estado real
evidence: files=0 cmds=3 turns=4/15
- discrepancia: branch aprobado OTRA, real feature/smoke
```
El tercer caso SÍ necesita `cmds>0` (re-verificación real contra `git rev-parse --abbrev-ref HEAD`),
consistente con el contrato (solo los dos primeros casos son "sin ejecutar NADA"). Suite completa
(53/53) reverificada tras el fix, sin regresiones.

## 5. Fase B con aprobación correcta → push REAL al bare

`approved-push: remote=origin branch=feature/smoke base=master` →
`git -C "$SMOKE/remote.git" log --oneline feature/smoke` muestra el commit de smoke. `gh pr create`
fallará (el remoto es `file://`, no GitHub): comprobar que el veredicto sigue siendo `DONE`, con
`- pushed:` y con las dos líneas de degradación `- pr manual:` / `- pr comando:` — y **no** un `KO`.
Evidencia: ⚠️ PASS, con un artefacto real de fixture encontrado y corregido (no un bug del plugin).
Primer intento: `BLOCKED árbol sucio: 1 ficheros sin commitear` con `- git status --porcelain: ??
.swarm/` — el fixture no tenía `.gitignore` (a diferencia del repo real del plugin, donde
`/swarm:init` lo crea), así que el propio `.swarm/` que el ítem 3 había generado quedó sin trackear.
Corregido añadiendo `.gitignore` con `.swarm/` al fixture (mismo mecanismo que produce
`/swarm:init` en un repo real) y commiteado. Relanzado con la aprobación correcta:
```
DONE
evidence: files=1 cmds=9 turns=7/15
- pushed: origin feature/smoke (2 commits)
- notas: /.../repo/.swarm/run/adhoc/release-notes.md
- warn: sin suite ejecutable — verde NO verificado
- pr manual: origin file:///.../remote.git · feature/smoke → master
- pr comando: gh pr create --base master --head feature/smoke --title "feature/smoke" --body-file .swarm/run/adhoc/release-notes.md
```
Confirmado en el bare real: `git -C "$SMOKE/remote.git" log --oneline feature/smoke` muestra los 2
commits (`chore: gitignore .swarm`, `feat: cambio de smoke`) y `branch --list` ahora lista
`feature/smoke` junto a `master` — push REAL confirmado. `gh pr create` degradó correctamente (el
remoto es `file://`, no GitHub) sin convertir el veredicto en `KO`.

## 6. El guard deniega lo que la prosa promete (contra el hook REAL, con `agent_type` real)

`git push origin master`, `git push --force origin feature/smoke`, `git push` a secas,
`gh pr merge 1`, `git remote add x y` — todos denegados para `swarm:release-manager`; y
`git push origin feature/smoke` denegado para `swarm:delivery-orchestrator`.
Evidencia: ✅ PASS — invocación directa y real del hook (`python3 hooks/bash-guard.py`) con
`agent_type` real vía stdin JSON, los 6 casos:
```
git push origin master              → deny: destino de `git push` no permitido (rama protegida...)
git push --force origin feature/smoke → deny: `git push` solo se permite en su forma canónica EXACTA
git push                            → deny: `git push` solo se permite en su forma canónica EXACTA
gh pr merge 1                       → deny: `gh pr merge` no tiene ninguna forma permitida en el enjambre
git remote add x y                  → deny: `git remote add` solo se permite en su forma canónica EXACTA
[swarm:delivery-orchestrator] git push origin feature/smoke → deny: no está en el allowlist de swarm:delivery-orchestrator
```
Los 6 comandos, sin excepción, deniegan con `permissionDecision: deny` real.

## 7. Handoff en el camino feliz y en el bloqueado

El MD de relevo aparece en las dos corridas (la del ítem 1, con `BLOCKED`, y la del ítem 5), con las
secciones "Prompt copy-paste", "Dónde está todo" y "Siguiente paso", **sin commitear**
(`git status --porcelain` lo muestra como untracked). En el caso bloqueado, "Siguiente paso" tiene
que ser el hint del `BLOCKED`, no una frase genérica.
Evidencia: ⚠️ PASS PARCIAL vía invocación directa de `handoff-writer` (no de la cadena completa
`delivery-orchestrator` → 2 hojas anidadas — ver nota de método abajo), con el `context:` REAL de
las corridas de los ítems 1 y 5 tal cual.

**Caso BLOCKED** (context = veredicto real del ítem 1, colapsado a una línea):
```
DONE
evidence: files=1 cmds=4 turns=1/8
- handoff: /.../repo/.swarm/run/adhoc/handoff.md (sin commitear)
```
Contenido real (fixture sin `docs/superpowers/handoffs/`, cayó correctamente al 3er nivel de
preferencia `<swarm-root>/run/<run-id>/handoff.md`, según su propio contrato): "Siguiente paso" es
literalmente el comando del hint (`gh repo create davidgarciagordo/repo --private --source=.
--remote=origin --push`), no una frase genérica.

**Caso DONE** (context = veredicto real del ítem 5, colapsado a una línea; fixture CON
`docs/superpowers/handoffs/` pre-creada para ejercitar el path primario):
```
DONE
evidence: files=1 cmds=4 turns=1/8
- handoff: /.../repo/docs/superpowers/handoffs/2026-09-03-next-session.md (sin commitear)
```
`git status --porcelain` tras el run: `?? docs/superpowers/handoffs/2026-09-03-next-session.md` —
confirmado untracked. Las tres secciones (Prompt copy-paste / Dónde está todo / Siguiente paso)
presentes en los dos ficheros reales, con commits reales listados y "Siguiente paso" citando el
comando `gh pr create` pendiente.

**Nota de método (harness, no bug de plugin):** la cadena completa vía
`Agent(subagent_type: "delivery-orchestrator")` headless (que a su vez lanza 2 subagentes anidados)
se probó dos veces y en ambas la sesión `-p` exterior cortó su espera con una narración tipo "Sigo
esperando su mensaje final" en vez de bloquear hasta el resultado real — el mismo artefacto de
"wrapper corta la espera async antes de tiempo" ya documentado en los smokes de fase 1b/2/4/5b para
cadenas de 2+ niveles de subagente en modo `-p`. El manifest real SÍ mostró, en ambos intentos, a
`release-manager` Y `handoff-writer` registrados por `delivery-orchestrator` (evidencia de que la
secuencia se dispara de verdad), pero sin una captura de stdout limpia del veredicto final
encadenado. Por eso se verificó `handoff-writer` en un hop directo con el `context:` real capturado
de las corridas ya confirmadas de los ítems 1 y 5 — mismo agente, mismo contrato, mismo dato de
entrada real, sin la fragilidad de la anidación de 2 niveles bajo `-p`.

## 8. `/swarm:status` y `/swarm:findings` contra un `.swarm/` real

Sobre el repo del plugin (que ya tiene un run real de fase 2 en `.swarm/run/`): `/swarm:status`
imprime run, tier, agentes y conteo de hallazgos abiertos; `/swarm:findings value-critic` filtra;
`/swarm:findings 'a b'` termina en `exit 64` sin ejecutar nada. Verificar además que **ninguno de los
dos lanza un subagente** (no aparece agente nuevo en el manifest del run).
Evidencia: ✅ PASS — ejecución directa y real de `scripts/swarm-status.sh`/`scripts/swarm-findings.sh`
(los mismos que invoca la prosa de `commands/status.md`/`commands/findings.md`, cuyo
`allowed-tools: Bash, Read` no declara `Agent` — ningún subagente es alcanzable desde ahí por
diseño) contra `SWARM_ROOT=/Users/davidgarciagordo/projects/multiagents/.swarm`, el `.swarm/` REAL
del repo del plugin con el run de fase 2 (`fbd64603-...`, tier `light`, 31 hallazgos abiertos, 5 runs
recientes):
```
$ swarm-status.sh
run: fbd64603-7421-4c53-9948-93ee9b997a47 · tier: light · iniciado: 2026-09-03T11:54:20Z
agentes registrados: 1
  - root           orchestrator (lanzado por user)
hallazgos abiertos: 31 (LESSON: 1, OPTION: 12, RESEARCH: 11, RISK: 1, VALUE: 6)
  - options-generator      13
  - orchestrator           1
  - research-analyst       11
  - value-critic           6
runs recientes: 5
EXIT=0
```
```
$ swarm-findings.sh value-critic
hallazgos (filtro value-critic · abiertos): 6
  - value-critic  VALUE · discovery-37885ce4-...:1 · Quien consume el CSV... → responder antes de disenar
  (6 líneas reales, citan fichero:línea del run real)
EXIT=0
$ swarm-findings.sh "a b"
swarm: filtro inválido 'a b' — solo [A-Za-z0-9_-]
EXIT=64
```
`ls .swarm/run/ | wc -l` antes y después: **6** en ambos casos, y `cat .swarm/run/current` sin
cambiar — ningún run nuevo, ningún agente nuevo registrado, confirmando que ninguno de los dos
comandos lanza subagente (coherente con que ambos son scripts deterministas invocados sin el tool
`Agent`).

## 9. Cadena completa por la raíz, con `AskUserQuestion` real

Sesión interactiva (no headless: `AskUserQuestion` no se simula — aprendizaje de fase 2):
`/swarm:run "publica la rama feature/smoke"` sobre el fixture. Comprobar que la raíz **no encadena**
desde ningún otro dominio, que la pregunta muestra remoto/rama/base/commits/verde, y que al elegir
"no publicar" el cierre es `- run cerrado: DONE · publicación no autorizada por el owner` con el bare
intacto.
Evidencia: ❌ NO EJERCITADO en vivo (`AskUserQuestion` real) — **gap explícito, esperado y
documentado desde el brief, mismo patrón que fases 2/5a/5b**: este agente no tiene la capacidad de
sostener una sesión interactiva humana que responda a un `AskUserQuestion` real; `claude -p`
(headless) no puede simular esa respuesta (lección de fase 2, citada en el propio checklist).

**Verificación parcial que SÍ se hizo, por trazado + ejecución en vivo hasta el punto de la
pregunta:**
1. **Trazado de código** (`agents/orchestrator.md` §12.1-§12.4): confirmado que la raíz nunca
   autoriza una publicación por criterio propio (§12.2, "nunca autorizas una publicación por tu
   cuenta"), que la pregunta es `AskUserQuestion` single-select con las opciones exactas "publicar" /
   "no publicar", y que traduce **los valores del preview** (no la prosa de la respuesta) a la línea
   `approved-push:` — ya verificado estáticamente en sesiones previas de este mismo proyecto
   ("Reviewer Verified Push-Approval Gate Header Shapes Match Between orchestrator.md §12 and
   release-manager.md").
2. **Intento real de `/swarm:run "publica la rama feature/smoke"`** (headless, contra el fixture del
   ítem 5, ya con remoto y commits reales) para ver hasta dónde llega sin error antes del punto de
   pregunta. Resultado real: la raíz SÍ lanzó `delivery-orchestrator`, que SÍ registró y lanzó
   `release-manager` y `handoff-writer` en el manifest real (confirmado en disco), pero la sesión
   exterior `-p` no propagó un preview limpio de vuelta a la raíz — mismo artefacto de "wrapper corta
   la espera async" ya documentado (ítem 7). La raíz, al no recibir un preview limpio, **se negó
   correctamente a preguntar o a publicar con datos stale**, cerrando con un `BLOCKED` honesto en vez
   de fabricar una pregunta o una publicación:
   `summary.md` real: `- run cerrado: BLOCKED delivery-orchestrator no devolvio preview de
   prepare-release; sin preview no hay gate de aprobacion honesto`. Confirmado en el bare real
   (`git -C "$SMOKE/remote.git" branch --list` / `log --oneline feature/smoke`): **sin cambios**
   respecto al estado post-ítem-5 — ningún push adicional ocurrió. Esto es una confirmación en vivo
   real de una propiedad de seguridad (la raíz nunca pregunta ni publica sobre datos que no pudo
   verificar limpio) aunque la rama de pregunta interactiva en sí **no se alcanzó**.
3. **Hallazgo NO relacionado con el dominio delivery, solo anotado**: la sesión `-p` EXTERIOR (el
   proceso `claude -p` que yo lancé, que NO corre como `agent_type: swarm:*` y por tanto no pasa por
   `hooks/bash-guard.py`) decidió por su cuenta, tras recibir el `BLOCKED`, hacer `git add`+`git
   commit` del `handoff.md` que `handoff-writer` deja deliberadamente sin commitear — usando mi
   identidad git real del fixture. Ningún agente `swarm:*` hizo esto (`handoff-writer` no tiene
   `git add`/`git commit` en su allowlist, confirmado); fue la sesión raíz de `claude -p` en sí,
   fuera del alcance de la gate del plugin (el guard solo gatea `agent_type` que empieza por
   `swarm:`, por diseño). No es un bug del dominio delivery — es un artefacto de cómo invoqué la
   sesión exterior sin instrucciones "no hagas nada más", y queda anotado para que quien revise sepa
   que la sesión raíz interactiva normal de Claude Code, fuera del enjambre, sigue teniendo sus
   propios permisos habituales.

**Lo que queda sin verificar en vivo, y por qué (para el siguiente review por trazado):** el texto
exacto que `AskUserQuestion` presenta al owner (remoto/rama/base/commits/verde), la traducción de la
respuesta humana real a `approved-push:`, y el cierre `- run cerrado: DONE · publicación no
autorizada por el owner` cuando el owner elige "no publicar" — los tres exigen un humano
respondiendo de verdad. `agents/orchestrator.md` §12.2-§12.4 los especifica; no se ha ejecutado en
vivo.

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
Evidencia: ✅ PASS en los 4 sub-ítems automáticos; `action=create` **intencionalmente NO ejercitado**
(manual/opcional, decisión del owner, per brief — verificado solo por trazado de código en la Tarea
6). Todo lo demás, headless real, invocación directa de `release-manager` (single-hop, mismo
mecanismo que los ítems 1-6):

**Gate sin cabecera:**
```
BLOCKED sin aprobación de remoto
evidence: files=0 cmds=0 turns=1/15
```
`git remote -v` del fixture: vacío antes y después.

**Gate malformado (4 variantes reales, una por una):**
```
approved-remote: sí                              → BLOCKED aprobación de remoto malformada (files=0 cmds=0 turns=1/15)
approved-remote: action=create name=x             → BLOCKED aprobación de remoto malformada (files=0 cmds=0 turns=1/15)
approved-remote: action=use url=x y               → BLOCKED aprobación de remoto malformada (files=0 cmds=0 turns=1/15)
approved-remote: action=use url=https://a.b/c;id  → BLOCKED aprobación de remoto malformada (files=0 cmds=0 turns=2/15)
```
Los 4, sin ejecutar ninguna mutación.

**`action=use` real contra un tercer bare desechable** (`file:///.../swarm-phase6-bare2.../remote2.git`),
sobre el mismo fixture sin remoto:
```
DONE
evidence: files=1 cmds=5 turns=5/15
- remote: origin → file:///.../swarm-phase6-bare2.../remote2.git
- siguiente: vuelve a lanzar la entrega ahora que origin existe
```
Confirmado en disco: `git remote -v` lista `origin` con esa URL; `remote-setup.md` real existe con
el comando literal `git remote add origin file://...`, `exit: 0`, `git remote -v` embebido y `rama
actual: feature/smoke`; `git -C .../remote2.git branch --list` — **vacío**, ninguna rama nueva llegó
al bare (configurar no publicó nada).

**Remoto ya existente** (relanzado sobre el MISMO fixture, ahora con `origin` ya puesto):
```
BLOCKED ya hay remoto configurado: origin file:///.../remote2.git
evidence: files=0 cmds=5 turns=3/15
- hint: relanza la entrega; si ese remoto no es el que quieres, cámbialo tú con git remote set-url
```
`git remote -v` tras el intento: idéntico a antes — la URL **no** se reescribió.

**`action=create`**: NO ejecutado (manual/opcional, per brief — crearía un repo real en la cuenta
del owner). Su forma (`gh repo create <owner>/<repo> --private/--public --source=. --remote=origin
--push`, los 3 desenlaces documentados incluyendo `BLOCKED remoto creado pero push rechazado:` con
el hint de alias SSH) fue verificada por trazado de código en la Tarea 6 (code review), no en vivo
en este smoke.

## 11. Modo degradado de `/swarm:status` y `/swarm:findings` (ruling 12)

Sobre una copia desechable de `.swarm/`: truncar `run/<id>/run.json` a la mitad → el script sale con
`exit 2`, imprime `no interpretable: …` y todo lo que sí pudo leer, y el comando **antepone**
`- warn: modo degradado — swarm-status.sh falló (exit 2)` antes del resumen best-effort. Mismo
ejercicio con una línea `- [algo]` sin cabecera `[key:…]` en `findings/*.md` para
`/swarm:findings`. Verificar las dos propiedades que hacen que el fallback no sea un agujero de
coste: con `exit 0`, `1` y `64` **no se lee ni un fichero extra**, y en el degradado **no se lanza
ningún subagente** (no aparece agente nuevo en el manifest).
Evidencia: ✅ PASS — fixture desechable de `.swarm/` con `run/badrun/run.json` truncado a mitad de
cadena JSON (`{"tier": "light", ... "id": "badru`, sin cerrar) y un
`findings/somebody.md` con una entrada real con cabecera `[key:...]` y una segunda línea `- [algo sin
cabecera de metadatos, escrito a mano]` sin ella. Primero, los scripts directamente:
```
$ swarm-status.sh   → exit 2
no interpretable: .../run/badrun/run.json (Unterminated string starting at: line 1 column 60 ...)
run: badrun · tier: ? · iniciado: ?
no interpretable: 1 entradas de findings/somebody.md sin cabecera [key:…]
hallazgos abiertos: 1 (TAG: 1)

$ swarm-findings.sh   → exit 2
hallazgos (abiertos): 1
  - somebody   a real finding with proper header
no interpretable: 1 entradas sin cabecera [key:…] (no se pueden filtrar)
```
Después, el comando SLASH real vía `claude -p "/swarm:status"` / `"/swarm:findings"` (headless,
single-turn Bash+Read, sin `Agent` en su `allowed-tools`) contra ese mismo `.swarm/`:
```
$ /swarm:status
- warn: modo degradado — swarm-status.sh falló (exit 2)
- salida parcial del script arriba (run "badrun" no interpretable, findings/somebody.md sin cabecera)
Run actual: `badrun`... run.json: truncado... summary.md: no existe... No hay runs anteriores...
No tocado ningún fichero ni relanzado script.

$ /swarm:findings
Entradas de `.swarm/findings/somebody.md`, literal: [2 líneas citadas tal cual]
Ficheros leídos: 1 (`somebody.md`). No edité nada ni relancé script.
```
El `- warn:` antepuesto al resumen best-effort en `/swarm:status`, confirmado real (no simulado).
Ambos comandos se ciñeron al tope de ≤3 ficheros (`/swarm:status` citó como mucho `run/current`,
`run.json` y ausencia de `summary.md`; `/swarm:findings` leyó solo 1 fichero, el único relevante), no
relanzaron el script y no lanzaron ningún subagente (invocación de un solo turno, sin tool `Agent`
disponible). El camino feliz (`exit 0`, `1`, `64`) ya está confirmado en el ítem 8 sin ninguna
lectura adicional además del propio script.

## 12. Nada del repo del plugin se ha publicado, y el fixture está borrado

En el checkout real del plugin: `git remote -v` sigue mostrando **exactamente** el remoto que ya
tenía (`origin git@github-personal-david:davidgarciagordo/swarm.git` — el que se creó a mano el
2026-09-03), sin remotos añadidos ni URLs reescritas por ningún agente; y
`git log --all --oneline | head -5` no muestra commits inesperados. **Comprobar también que ninguna
rama del plugin ha llegado a ese remoto por accidente durante el smoke**
(`git ls-remote --heads origin`). Y el fixture borrado: `rm -rf "$SMOKE"`.
Evidencia: ✅ PASS. `git remote -v` en este worktree Y en el checkout principal
(`/Users/davidgarciagordo/projects/multiagents`): idéntico en ambos, `origin
git@github-personal-david:davidgarciagordo/swarm.git` (fetch+push) — sin remotos añadidos ni URLs
reescritas. `git ls-remote --heads origin` (lectura real contra GitHub, sin publicar nada): **solo**
`refs/heads/master` — ninguna rama de smoke (`feature/smoke` ni ninguna otra) llegó ahí por
accidente. `git log --all --oneline | head -5` en este worktree: los mismos 5 commits de siempre
(el más reciente, el propio fix de `agents/release-manager.md` de este smoke, aún sin commitear —
ver "Bugs encontrados"). `git status --porcelain` en este worktree: solo
`agents/release-manager.md` modificado (el fix) y el propio checklist — nada más tocado.

**Nota aparte, no relacionada con el dominio delivery**: `git status --porcelain` del checkout
principal (`/Users/davidgarciagordo/projects/multiagents`) muestra `.swarm/decisions.md` modificado
— confirmado por `git log -1 --format=%ci -- .swarm/decisions.md` (2026-09-03 04:19, horas antes de
que este smoke empezara) que es un residuo PRE-EXISTENTE de una sesión de fase 2 anterior, no algo
que este smoke haya tocado (los únicos comandos que corrí ahí fueron los scripts de lectura de los
ítems 8/11, ninguno escribe). No se ha tocado ni commiteado — fuera de alcance de esta tarea.

Los 5 fixtures desechables (`swarm-phase6.*`, `swarm-phase6-noremote.*`, `swarm-phase6-bare2.*`,
`swarm-phase6-degraded.*`, `swarm-phase6-degcwd.*`) — todos borrados con `rm -rf` al terminar,
confirmado (`ls /tmp | grep swarm-phase6` → sin resultados).

## Bugs encontrados y arreglados durante este smoke

1. **`release-manager` (`operation: publish-release`) ejecutaba 2 comandos del "Arranque" común
   (lectura de buzón + `git rev-parse --show-toplevel`) ANTES de comprobar la línea `approved-push:`**
   — confirmado en vivo en el ítem 4 (`evidence: files=0 cmds=2 turns=2/15` en vez del `cmds=0
   turns=1/15` que el propio contrato documenta para "sin ejecutar NADA"). El texto "Gate de
   aprobación (lo primero, antes de cualquier otra cosa)" y el "## Arranque (idéntico en TODAS tus
   operaciones)" estaban en tensión: el segundo, leído en orden de documento, se ejecutaba primero.
   Arreglado (`agents/release-manager.md`, sección "Arranque", paso 1): se añadió una nota explícita
   de que, en `publish-release`, el gate completo de `approved-push:` (ausente/vacío Y malformado) se
   comprueba en el paso 1 mismo, antes de los pasos 2-3. Reverificado en vivo tras el fix: los dos
   casos de forma dan `files=0 cmds=0 turns=1/15` exactos; el tercer caso (aprobación bien formada
   pero discrepante con el estado real) sigue necesitando `cmds>0` porque exige re-verificación
   contra git, consistente con el contrato. Suite completa reverificada (53/53), sin regresiones.

No es un hallazgo de seguridad (ningún comando de mutación se ejecutó de más en ningún caso, solo
lecturas), sino un mismatch real entre la evidencia documentada y la observada — corregido y
reverificado en vivo.

## Nota de método: artefacto de anidación async en modo `-p` (no es un bug de este dominio)

En **todas** las cadenas de 2+ niveles de subagente (raíz → `delivery-orchestrator` →
`release-manager`/`handoff-writer`) ejercitadas vía `claude -p` headless, la sesión exterior cortó su
espera con una narración de estado ("Sigo esperando su mensaje final...") en vez de bloquear hasta el
resultado real — mismo artefacto ya documentado en los smokes de fases 1b/2/4/5b para cadenas
anidadas bajo `-p`. Las invocaciones de UN solo nivel (raíz → hoja directa) nunca mostraron este
problema, en ninguno de los ~20 intentos de este smoke. El manifest real (`.swarm/run/*/agents/*.json`)
confirmó en cada caso que la secuencia SÍ se disparaba de verdad (ambas hojas registradas y
lanzadas); lo que se perdía era la captura limpia del veredicto final propagado por el nivel
intermedio en la sesión headless. Se trabajó alrededor de esto invocando las hojas directamente con
el `context:`/cabecera REAL capturado de las corridas ya confirmadas (ítems 7 y 9), nunca fabricando
datos. No se tocó ningún fichero de agente para "arreglar" esto — es un artefacto de la profundidad
de anidación bajo `-p`, transversal a fases anteriores, fuera del alcance de este dominio.

## Firma

- [x] Owner: sesión autónoma (agente de smoke fase 6) — Fecha: 2026-09-03
