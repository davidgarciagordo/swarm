# Cómo usar swarm

Guía de uso completa y autocontenida para alguien que nunca ha visto este plugin. Si solo quieres
el estado del proyecto (qué está construido, qué está planeado), lee `README.es.md` — este
documento es sobre cómo ejecutarlo de verdad.

## 1. Qué es

`swarm` es un plugin de Claude Code: ejecuta un enjambre de subagentes de responsabilidad única que
te ayudan a lo largo del ciclo de desarrollo de software sobre un repo real — entender un código
existente, auditarlo, diseñar un cambio e implementarlo. Cada agente tiene un solo trabajo (un
auditor de seguridad nunca escribe código, un planificador nunca implementa), y un orquestador raíz
los coordina y te devuelve un veredicto corto respaldado por evidencia, en vez de un muro de
narración. El humano se queda al mando de lo que realmente se construye: el enjambre hace preguntas
reales cuando una decisión necesita a una persona, y nunca empuja nada a ningún sitio por su cuenta.

## 2. Instalación

Todavía no hay listing en ningún marketplace, así que hoy la única vía real de instalación es
local: apuntar Claude Code directamente al checkout.

```bash
claude --plugin-dir /ruta/a/multiagents
```

Sustituye `/ruta/a/multiagents` por dondequiera que hayas clonado este repo (por ejemplo
`/Users/davidgarciagordo/projects/multiagents`). Esto carga los comandos, agentes, skills y hooks
del plugin para esa sesión — los tres comandos `/swarm:*` quedan disponibles, y sus definiciones de
agente se pueden invocar desde cualquier punto de la conversación. No hay nada que compilar ni
`npm install`: es un conjunto de ficheros markdown de agente/comando/skill más unos pocos scripts de
shell, leídos directamente por Claude Code.

Una vez cargado, ejecuta `/swarm:init` una vez dentro del repo target (el repo sobre el que
realmente quieres trabajar — no tiene por qué ser este) antes de hacer cualquier otra cosa. Eso crea
el directorio `.swarm/` que usa este plugin como memoria. Ver §3 más abajo.

Si algún día este plugin se publica en un marketplace, la instalación pasaría por el flujo normal de
marketplace de plugins de Claude Code (`/plugin install swarm` o equivalente) — pero esa vía todavía
no existe, así que no sigas instrucciones que la den por hecha.

## 3. Los 3 comandos

Estos son los *únicos* tres comandos de barra que define este plugin — ficheros reales bajo
`commands/`: `commands/init.md`, `commands/run.md`, `commands/doctor.md`. Nada más
(`/swarm:status`, `/swarm:findings`, etc.) está implementado todavía, aunque el spec de diseño los
esboza para una fase posterior — no los escribas esperando que funcionen.

### `/swarm:init`

Crea `.swarm/` en el repo actual: el árbol de directorios, `memory.json` (declarando el backend
`files` como requerido), `decisions.md` con su cabecera, y un bloque `# swarm` añadido a
`.gitignore` para que el estado de trabajo del enjambre nunca se comitee. También ejecuta un
health-gate sobre el backend antes de declarar éxito. No toma argumentos.

```
/swarm:init
```

Se ejecuta una vez por repo, antes de tu primer `/swarm:run`. Internamente solo lanza
`${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh` y reporta el resumen en texto plano del propio script
tal cual — si el script termina con código distinto de cero, el comando informa que `/swarm:init`
abortó y muestra la línea de stderr que explica por qué (de
`docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`, ítem 1: el resultado esperado es
`.swarm/` creado, `memory.json` con el backend `files` requerido, `decisions.md` con su cabecera, el
bloque `.gitignore` marcado `# swarm`, y el health-gate en verde).

### `/swarm:run`

El punto de entrada principal. Lanza el agente raíz `orchestrator` sobre un objetivo que describes
en lenguaje natural, con un flag de tier opcional.

```
/swarm:run <objetivo> [--tier=direct|light|full]
```

Por ejemplo: `/swarm:run "añadir export CSV del listado de facturas" --tier=full`. El comando
SIEMPRE invoca el subagente `swarm:orchestrator` con tu texto exacto de argumento, incluso si está
vacío — el propio orquestador decide si el objetivo es válido y devuelve su propio veredicto; la
sesión exterior nunca responde en tu lugar ni pide aclaración antes de lanzarlo.

**Tiers** (de `agents/orchestrator.md` §1.1 y el spec §9.1):

- `direct` — un objetivo trivial, de un solo fichero, sin decisión arquitectónica. La raíz te
  responde directamente, sin abrir un run ni lanzar ningún dominio. No se escribe nada bajo
  `.swarm/run/`.
- `light` — un solo dominio. Las hojas de juicio (auditores, planner, pattern-advisor, etc.) corren
  en `sonnet` en vez de `opus`, sin grill adversarial, y el pack de memoria solo se reconstruye si
  está desactualizado.
- `full` — trabajo multi-dominio o explícitamente crítico. Las hojas de juicio corren en `opus`, y
  el diseño pasa por la revisión adversarial grill×3 antes de darse por terminado.

Si no pasas `--tier`, el orquestador lo clasifica por ti según el alcance. Siempre puedes forzarlo
explícitamente con el flag — un valor inválido (cualquier cosa que no sea exactamente `direct`,
`light` o `full`, sensible a mayúsculas) se rechaza directamente en vez de adivinarse.

**Enrutado — cómo tu objetivo elige un dominio.** La raíz nunca corre todo a la vez; lee tu objetivo
y elige el/los dominio(s) que aplican:
- Un objetivo **de producto** ("añade X", "construye una Y nueva", cualquier cambio de
  comportamiento visible para el usuario) enruta primero a **discovery** — y, solo en `tier: full`,
  encadena a **design** después, una vez respondidas las preguntas de discovery.
- Un objetivo **de análisis** ("audita X", "revisa la seguridad de Y", "busca problemas de
  rendimiento en Z") enruta en su lugar a **analysis** — read-only, sin preguntas. Discovery y
  analysis son mutuamente excluyentes en el mismo run: si tu objetivo se lee como "de producto",
  analysis nunca corre, y viceversa.
- Un bugfix, un refactor, un cambio de docs o una tarea de infraestructura se saltan discovery y
  analysis — la raíz simplemente lo dice en la salida (`- discovery omitido: ...`) y, en `tier:
  full` sin decisiones de producto contra las que diseñar, design también se salta.
- **Implementation** nunca encadena automáticamente tras discovery o design, en ningún tier — solo
  corre cuando pides explícitamente al enjambre que construya un plan que ya existe ("implementa el
  plan de X", "construye X según el diseño ya escrito"). Es un checkpoint humano deliberado: escribir
  y fusionar código real es la acción más consecuente del enjambre, así que un run de
  discovery+design siempre se detiene con un fichero de plan revisable en vez de proceder en
  silencio a construir código.

**Ejemplo real** (`docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`, ítems 2, 6 y 7 —
verificado en vivo):

```
/swarm:run "audita memoria" --tier=light
```
Resultado (tras un fix real de un bug a mitad de smoke): pack reconstruido de verdad
(`context-pack.md` con una línea real `stack: php-ddd-symfony8`), `index.md` sellado, run cerrado
con `curate`. Un segundo run idéntico contra el mismo repo sin cambios NO reconstruye el pack — el
chequeo de staleness lo evita (ítem 3).

```
/swarm:run
```
(sin ningún argumento) devuelve, sin abrir ningún run:
```
BLOCKED objetivo vacío — describe qué quieres que haga el enjambre
```

```
/swarm:run "audita memoria" --tier=medium
```
(`medium` no es un tier válido) devuelve, de nuevo sin abrir run:
```
BLOCKED --tier inválido: medium (usa direct, light o full)
```

### `/swarm:doctor`

Verifica los requisitos de entorno del repo — las herramientas de nivel de sistema operativo que
necesita el plugin (y cualquier stack pack activo) — contra `requirements.json`. No toma
argumentos; cualquier texto que escribas después del comando se ignora.

```
/swarm:doctor
```

SIEMPRE invoca el subagente `swarm:requirements-orchestrator` con `operation: check`, que a su vez
lanza `env-checker` para ejecutar el chequeo determinista (`scripts/req-check.sh`) en vez de
reimplementar la lógica de presencia de herramientas él mismo. El `requirements.json` propio del
plugin declara hoy `git`, `python3` y `uuidgen` como `required: true`, y `jq`, `gh`, `docker` como
opcionales. Ejemplo real, ejecutado contra el propio checkout del plugin (que tiene las tres
herramientas requeridas):
`docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`, ítem 1, confirma que
`requirements-orchestrator` lanza a `env-checker` (nombrado exactamente `env-checker`, con `Agent`,
nunca `SendMessage`) y el veredicto final es `OK`. Si falta una herramienta requerida, el veredicto
es `BLOCKED <tool>` con el hint de instalación de `requirements.json` (comando `brew`/`apt`),
propagado literalmente desde `env-checker` hasta lo que ves — verificado directamente contra el
script en el ítem 2 de ese mismo checklist.

## 4. Los dominios

Cada dominio de abajo es una parte real, construida y funcionando hoy del enjambre — verificada en
un smoke test en vivo, no solo diseñada sobre el papel. `/swarm:run` enruta a estos automáticamente
según el §3 de arriba; nunca invocas un orquestador de dominio por su nombre de subagente tú mismo
en uso normal.

### Memoria

**Qué hace por ti:** mantiene un entendimiento compacto y reutilizable de tu repo (`.swarm/`) para
que cada dominio lea el mismo contexto compartido en vez de re-escanear el código desde cero cada
vez, y registra cada decisión y hallazgo para que un run posterior sobre el mismo objetivo no
vuelva a preguntar lo mismo. Es la dueña de `.swarm/context-pack.md` (la instantánea del repo:
stack, estructura, extractos clave), `.swarm/decisions.md` (cada respuesta de discovery, indexada
por el texto literal del objetivo) y `.swarm/findings/` (cada hallazgo de auditoría/diseño/review,
deduplicado por agente+tag+fichero:línea).

**Qué lo dispara:** automáticamente, en cada `/swarm:run` en tier `light`/`full` — no lo invocas
directamente. `memory-orchestrator` es el primer orquestador de dominio que la raíz lanza tras abrir
un run, antes de discovery, analysis, design o implementation, y dirige a su vez dos hojas propias:
`memory-builder` (reconstruye el pack) y `memory-curator` (compacta hallazgos, hace GC de runs
antiguos).

**Qué recibes:** nada visible por sí solo en uso normal — su trabajo es hacer que la salida de
cualquier otro dominio sea mejor y más barata. Sí ves su efecto: un pack reconstruido se anuncia en
el resumen del run, y un segundo run idéntico contra un repo sin cambios se salta visiblemente la
reconstrucción.

**Ejemplo real** (checklist de smoke de fase 1, ítems 2–3): el primer `/swarm:run "audita memoria"
--tier=light` reconstruyó `context-pack.md` con una línea real `stack: php-ddd-symfony8` y selló
`index.md`; el run idéntico repetido justo después, con el repo sin tocar, dejó la fecha de
modificación de `context-pack.md` sin cambios — confirmando que el chequeo de staleness
(`mem-stale.sh check`, un hash del estado del árbol) evitó relanzar al constructor del pack.

### Requisitos

**Qué hace por ti:** verifica las herramientas que tu sistema operativo realmente tiene contra lo
que el plugin (y cualquier stack pack activo) declara necesitar, y te dice exactamente qué falta y
cómo instalarlo — antes de que te encuentres con un fallo críptico tres dominios dentro de un run.

**Qué lo dispara:** `/swarm:doctor` (ver §3). No forma parte del pipeline de `/swarm:run` en sí —
compruebas los requisitos como un paso explícito aparte, típicamente una vez tras `/swarm:init`.

**Qué recibes:** `OK` si todo lo `required: true` está presente, o `BLOCKED <tool>` nombrando la
herramienta exacta que falta más su hint de instalación (un comando `brew`/`apt`) si no.

**Ejemplo real** (`docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`, ítem 1): ejecutado
contra el propio checkout del plugin, `requirements-orchestrator` lanza `env-checker`, que invoca
`scripts/req-check.sh`, y el veredicto vuelve `OK` porque `git`, `python3` y `uuidgen` están todos
presentes en la máquina real.

### Discovery

**Qué hace por ti:** convierte un objetivo de producto vago en un pequeño conjunto de decisiones
concretas. `discovery-orchestrator` corre cuatro hojas en paralelo — una hace la pregunta de mayor valor primero
(`value-critic`), una investiga prior art (`research-analyst`), una genera 2-3 enfoques reales con
sus trade-offs (`options-generator`), y una ejecuta un spike desechable para responder una pregunta
de viabilidad concreta (`feasibility-spiker`) — y luego fusiona todo en un único batch de hasta
cuatro preguntas que Claude Code te presenta directamente con `AskUserQuestion`.

**Qué lo dispara:** un objetivo con forma de producto ("añade X", "construye una funcionalidad
nueva que haga Y", cualquier cambio de comportamiento visible para el usuario) en tier `light` o
`full`. Se salta para bugfixes, refactors, docs, tests y tareas de infraestructura, y se salta (sin
volver a preguntar) si `.swarm/decisions.md` ya cerró el mismo objetivo exacto en un run anterior.

**Qué recibes:** un diálogo interactivo de preguntas (es el único punto de todo el enjambre donde se
pausa y te espera), y después una única línea de decisión registrada en `.swarm/decisions.md` con
cada pregunta y tu respuesta, con el texto literal del objetivo delante para que un run posterior lo
reconozca. Si cierras el diálogo sin responder, tu batch (sin responder) se guarda igualmente,
marcado `[pendiente]`, en vez de perderse en silencio.

**Ejemplo real** (`docs/superpowers/plans/2026-09-02-phase2-smoke-checklist.md`, ítem 1, ejecutado
en vivo por el owner): `/swarm:run "añadir export CSV del listado de facturas" --tier=full` produjo
un batch real de 4 preguntas, presentado vía `AskUserQuestion`, respondido, y registrado en
`decisions.md` con el campo `objective:` literal incluido. El run además detectó un conflicto real
entre dos de las respuestas (histórico completo vs. un endpoint síncrono) que `value-critic` ya
había avisado a `options-generator` por buzón — resuelto por el owner eligiendo un job async en
cola, registrado como una línea `SUPERSEDE`/`CONFLICTO RESUELTO`.

### Análisis

**Qué hace por ti:** una auditoría read-only de tu código. `analysis-orchestrator` elige un
subconjunto de hasta seis lentes — arquitectura (`architecture-auditor`), seguridad (`security-auditor`), escaneo de dependencias/
secretos (`vulnerability-scanner`), rendimiento (`performance-analyst`), drift de esquema/modelo de
datos (`data-model-auditor`), y deuda técnica/oportunidades ROI (`opportunity-analyst`) — elegidas
por coincidencia de palabras clave con tu objetivo, corridas en paralelo, y reenviadas a ti como
hallazgos.

**Qué lo dispara:** un objetivo explícitamente con forma de análisis ("audita X", "revisa la
seguridad de Y", "busca problemas de rendimiento", "audita todo") en tier `light` o `full`. Nunca
corre en el mismo run que discovery — un objetivo es "de producto" (discovery) o "de análisis"
(este dominio), nunca ambos.

**Qué recibes:** una lista de hallazgos, cada uno en una línea: `TAG · fichero:línea · problema →
fix`, más una línea nombrando qué lentes corrieron y por qué. Sin preguntas — analysis nunca invoca
`AskUserQuestion`.

**Ejemplo real** (`docs/superpowers/plans/2026-09-02-phase3-smoke-checklist.md`, ítem 1):
`/swarm:run "audita la seguridad de InvoiceController" --tier=full` seleccionó
`security-auditor` + `vulnerability-scanner` (el objetivo casó con "seguridad") y devolvió
hallazgos reales sobre el fixture: `CRITICO` aislamiento de tenant ausente en
`InvoiceController.php:12`, `ALTO` inyección SQL en `:14`, `ALTO` falta de comprobación de
autorización en `:9`. El run cerró con `- run cerrado: DONE · análisis completado, 3 hallazgos`.

### Diseño

**Qué hace por ti:** convierte decisiones de producto ya cerradas en un plan de implementación real
y revisable. `pattern-advisor` y `domain-modeler` corren juntos primero (encaje de patrón y
modelado de dominio), luego `planner` escribe un fichero de plan real bajo
`docs/superpowers/plans/` con fases, áreas disjuntas y riesgos. En `tier: full` el plan pasa después
por una revisión adversarial de tres lentes externas
(`working-methods:grill-architect/operator/engineer` — la lente de arquitectura de plataforma, la
lente de usuario real, y la lente de ingeniería técnica), y `design-orchestrator` mismo arbitra sus
hallazgos y revisa el plan — sin preguntarte nada nunca durante el diseño.

**Qué lo dispara:** solo `tier: full`, y solo después de que discovery haya cerrado sus decisiones
(ya sea en este mismo run, o en uno anterior sobre el mismo objetivo). Nunca se lanza en `tier:
light` (light es de un solo dominio por diseño), y se salta siempre que discovery también se
saltó.

**Qué recibes:** una única línea `PLAN · <ruta>:1 · <resumen corto>` apuntando al fichero de plan
real en disco, más una línea `- grill: ...` resumiendo qué cambió o se marcó en la revisión
adversarial. Tampoco hay preguntas aquí.

**Ejemplo real** (`docs/superpowers/plans/2026-09-03-phase4-smoke-checklist.md`, ítem 1): con el
objetivo "añadir export CSV del listado de facturas" ya cerrado en `decisions.md`,
`design-orchestrator` lanzó `pattern-advisor` + `domain-modeler` (hallazgos reales: `PATTERN ·
src/Controller/InvoiceController.php:11 · introduce Repository...`, `MODEL · ...Invoice raíz de
agregado...`), y luego `planner` escribió un plan real de 154 líneas en
`docs/superpowers/plans/2026-09-03-export-csv-facturas.md`. Los tres lentes grill corrieron de
verdad y encontraron problemas P1 sustanciosos (falta de BOM UTF-8 para compatibilidad con Excel,
un bug de truncado de `StreamedResponse` tras enviarse ya las cabeceras, una incoherencia de
bounded-context entre el agregado y su mapper) — `design-orchestrator` relanzó correctamente
`planner` con `operation: revise` para incorporarlos.

### Implementación

**Qué hace por ti:** ejecuta exactamente una fase de un plan ya diseñado y ya arbitrado — de
verdad, con tests reales y un merge local real, nunca a medias. La secuencia es estricta:
`test-writer` comitea un test que falla (RED) a la rama del run, `implementer` corre en un worktree
de git aislado para hacerlo pasar (GREEN) y comitea ahí, `quality-fixer` ejecuta el `--fix`
determinista del stack (lint/format) y parchea lo que no puede auto-arreglar, y `reviewer` hace de
gate con hallazgos etiquetados por severidad *antes* de que nada se fusione. Solo después de que ese
gate pasa, `implementation-orchestrator` fusiona el commit del worktree localmente a la rama propia
del run y limpia el worktree.

**Qué lo dispara:** solo una petición explícita que nombre un plan ("implementa el plan de X",
"construye X según el diseño ya escrito") — nunca automáticamente tras discovery o design, en
ningún tier. Es un checkpoint de seguridad deliberado: escribir y fusionar código real es la acción
más consecuente del enjambre, así que un plan siempre se detiene para revisión humana antes de
construirse.

**Qué recibes:** una línea de resumen `- implementation: ...` nombrando qué fase se fusionó, a qué
rama, a través de qué cadena de agentes, y cuántos pasos del plan se marcaron. Además, si el
reviewer encontró algo por debajo de la severidad que bloquea el merge, líneas explícitas
`- riesgo aparcado: ...` para que nada se trague en silencio.

**Ejemplo real** (`docs/superpowers/plans/2026-09-03-phase5a-smoke-checklist.md`, ítem 1):
`implementation-orchestrator`, invocado adhoc sobre un plan real para un value object `Money` con un
invariante de moneda, produjo dos commits reales en `run-branch` (el commit RED de `test-writer`,
`7e144a9`; el commit GREEN de `implementer`, `a293ff5`, con citas reales `fichero:línea` para cada
paso marcado), `quality-fixer` iteró dos veces, y `reviewer` encontró tres problemas reales `MINOR`
(moneda sin validar, overflow de `PHP_INT_MAX`, `.gitignore` sin `vendor/`) que quedaron aparcados
explícitamente sin bloquear el merge. El veredicto final:
```
DONE
evidence: files=9 cmds=17 turns=19/25
- implementation: Phase 1 fusionada a run-branch (test-writer→implementer→quality-fixer×2→reviewer), 2 steps [x]
```
Nunca toca `master` ni una rama compartida, y nunca ejecuta `git push` — ningún agente de este
dominio tiene siquiera esa herramienta en su lista permitida.

**Qué falta por construir:** el dominio `delivery` (automatización de release/PR/handoff) y el stack
pack `php-ddd-symfony8` siguen planeados, no disponibles. Consulta la sección "Estado actual" de
`README.es.md` para el desglose exacto y actualizado de construido/planeado — este documento no lo
duplica para no arriesgarse a que diverjan.

## 5. Cómo interpretar la salida

Todo agente de este enjambre —orquestador raíz, orquestadores de dominio y hojas por igual— reporta
a través del mismo contrato de evidencia
(`docs/superpowers/specs/2026-09-01-swarm-design.md` §6, validado en vivo por un hook,
`skills/swarm-protocol/SKILL.md` §4). Conociendo este formato, puedes leer la salida de *cualquier*
dominio de la misma manera:

```
<veredicto>
evidence: files=N cmds=M turns=k/max
<líneas de hallazgo, opcional>
```

- **La línea 1 es siempre el veredicto**, una de exactamente cuatro formas:
  - `OK` — el agente comprobó algo y está bien, no hace falta ningún cambio.
  - `KO <motivo>` — el agente comprobó algo y el peor problema encontrado es `<motivo>`.
  - `DONE` — el agente hizo el trabajo que se le pidió, con éxito.
  - `BLOCKED <motivo>` — el agente no pudo continuar, y `<motivo>` dice por qué.
- **La línea 2 es obligatoria**: `evidence: files=N cmds=M turns=k/max` — `N` ficheros realmente
  leídos, `M` comandos deterministas realmente ejecutados, y `k/max` el turno actual sobre el
  presupuesto de turnos de ese agente. Un veredicto sin esta línea se rechaza automáticamente por un
  hook antes de que llegue a ti — y lo mismo un `OK` que declare `files=0` (un veredicto verde sin
  evidencia detrás no se da por bueno).
- **Todo lo que sigue son hallazgos**, uno por línea, con la forma fija
  `TAG · fichero:línea · problema → fix` — una etiqueta corta (`SEC`, `ARCH`, `PATTERN`, `PLAN`…),
  el fichero y línea exactos sobre los que trata el hallazgo, el problema en pocas palabras, y el
  fix en ocho palabras o menos. El detalle completo (contexto largo, snippets) vive en
  `.swarm/findings/<agente>.md`, nunca en línea — lo que ves en la salida es deliberadamente terso
  por diseño, no truncado por accidente.

Así que una salida de un run de diseño como
```
DONE
evidence: files=3 cmds=7 turns=15/30
PLAN · docs/superpowers/plans/2026-09-03-export-csv-facturas.md:1 · plan listo, 4 tareas → revisar antes de fase 5
- grill: 1 P1 incorporado (idempotencia del export), 2 P2 anotados como riesgo
```
se lee así: el run tuvo éxito (`DONE`), está respaldado por evidencia real (3 ficheros leídos, 7
comandos ejecutados, terminó en el turno 15 de un presupuesto de 30), el plan está en esa ruta y
línea exactas, y la revisión adversarial incorporó un fix de alta prioridad mientras marcaba dos
riesgos de menor prioridad para más adelante.

## 6. Preguntas frecuentes / limitaciones honestas

**¿El enjambre alguna vez hace push a git, o toca `master`/una rama remota por su cuenta?** No,
nunca. `implementation-orchestrator` siempre fusiona localmente, a la propia rama del run — nunca a
`master` ni a ninguna rama compartida/remota, y ningún agente del dominio de implementación tiene
`git push` en su lista permitida de herramientas. Una guarda comprueba que `HEAD` no sea `master`
antes de fusionar nada.

**¿Puedo correr esto de forma totalmente headless / no interactiva?** En su mayoría sí, pero
discovery no. El sentido entero de discovery es hacerte preguntas reales vía `AskUserQuestion`, así
que un run que enruta a discovery se pausa y espera a un humano en una sesión interactiva — no
puede completarse en una invocación programada, sin TTY (`claude -p`) como sí pueden analysis,
design o implementation, porque no hay nadie ahí para responder. Si cierras el diálogo en vez de
responder, el enjambre no pierde tu sitio: registra el batch sin responder como una decisión
`[pendiente]` para que un run posterior pueda retomarlo en vez de volver a hacer las mismas cuatro
preguntas.

**¿Qué pasa cuando algo vuelve `BLOCKED`?** El run igualmente se cierra limpio — se escribe una
línea de resumen en `.swarm/run/<id>/summary.md` y se curata la capa de memoria antes de que el
veredicto llegue a ti, así que un run `BLOCKED` nunca queda a medio abrir. El `<motivo>` tras
`BLOCKED` está pensado para ser accionable: una herramienta que falta se nombra a sí misma junto con
su comando de instalación (`/swarm:doctor`), un `/swarm:run` con objetivo vacío te dice que
describas qué quieres, un `--tier` inválido lista los tres valores válidos. Si un orquestador de
dominio devuelve `BLOCKED`/`KO` él mismo, la raíz propaga ese mensaje exacto en vez de
parafrasearlo, así que lo que lees es literalmente lo que dijo el dominio que falló.

**¿Vuelve a leer todo mi código cada vez?** No — para eso existe el dominio de memoria (§4).
`.swarm/context-pack.md` se construye una vez y se reutiliza entre runs; solo se reconstruye cuando
el hash del estado del árbol del repo muestra que realmente está desactualizado. Los hallazgos
también se deduplican por `agente+tag+fichero:línea` entre runs, así que repetir la misma auditoría
dos veces seguidas no produce hallazgos duplicados (verificado en vivo en
`docs/superpowers/plans/2026-09-02-phase3-smoke-checklist.md`, ítem 6).
