# Cero fricción técnica — recalibración de UX — Design Spec

> **Origen:** brainstorming con el owner (2026-09-04), tras completar el gate de interpretación de
> objetivo. El owner reformuló el objetivo central del proyecto: "la idea del proyecto es que
> alguien con pocos conocimientos pueda hacer el trabajo de un departamento completo de software
> senior". Esto sube la barra de "menos fricción" a "cero fricción técnica".

## Objetivo

Un usuario SIN conocimientos técnicos debe poder usar el enjambre swarm sin aprender vocabulario
interno (`tier`, `run`, `BLOCKED`/`KO`/`OK`), sin saber que existen varios comandos separados, y
sin toparse con jerga técnica en ningún momento — ni al invocar, ni al leer resultados, ni al
responder las preguntas que el sistema le hace.

## No objetivos (explícitamente fuera de alcance)

- **No es una capa nueva por encima de Claude Code** (web app, chat propio) — decisión explícita
  del owner. Todo ocurre dentro de Claude Code.
- **No es una reescritura del motor interno.** El roster de 36 agentes, `hooks/bash-guard.py`, el
  contrato de evidencia, la lógica de clasificación de tier y todos los dominios (discovery,
  analysis, design, implementation, delivery) siguen funcionando exactamente igual. Esto es una
  capa de fachada — comando único + traducción de lo que se muestra — no un rediseño del sistema.
- **No introduce un roundtrip de modelo nuevo por run.** La traducción de vocabulario es
  determinista (tabla estática) + prosa ya existente reescrita en los agentes que ya la escriben —
  nunca una pasada de LLM dedicada a "traducir después".
- **`/swarm:status`/`/swarm:findings` no cambian** — utilidades de introspección opcionales, nadie
  sin conocimientos necesita tocarlas para que el sistema funcione end-to-end.
- **El nombre `swarm` no cambia** — decisión explícita del owner (curiosidad sobre el nombre, no
  petición de cambio).

## Arquitectura — 4 piezas

### 1. Punto de entrada único: `/swarm:run "<lo que quiero>"`

**Corrección tras revisión (2026-09-04):** los comandos de un plugin de Claude Code van SIEMPRE
namespaced como `/<plugin>:<comando>` — no existe un bare `/swarm` sin dos puntos. El "punto de
entrada único" real es `/swarm:run`, que YA es un solo comando hoy — lo que se simplifica no es su
nombre, es que deja de exigir ejecutar `/swarm:init` por separado antes. La versión anterior de
este spec (y los documentos que de ella salieron) asumía incorrectamente un alias bare `/swarm`;
esa asunción queda descartada.

Si `.swarm/` no existe, `/swarm:run` lo inicializa transparentemente — nunca bloquea con
`BLOCKED falta /swarm:init` pidiendo al usuario que sepa que existe un comando aparte.

**Implementación concreta:** `commands/run.md` (el `.md` que hoy invoca `swarm:orchestrator`) pasa
a ser el único punto de entrada documentado como `/swarm`. `agents/orchestrator.md` §2.1
(Health-gate) deja de devolver `BLOCKED falta /swarm:init` en el caso "`.swarm/` no existe" — en su
lugar, invoca la MISMA lógica que hoy ejecuta `/swarm:init` (ver `commands/init.md` y
`scripts/swarm-init.sh` — reutilizar el script real, no reimplementarlo) y continúa el run
normalmente. El caso "`.swarm/` existe pero no es escribible" (el otro camino de exit 1 del
health-gate) sigue bloqueando — eso es un problema de permisos del sistema de ficheros que
auto-inicializar no puede arreglar, y su mensaje también se traduce (pieza 2).

`--tier=direct|light|full` deja de aparecer en la documentación orientada al usuario simple
(`docs/USAGE.md`/`.es.md`'s intro/quickstart) — sigue siendo un flag funcional (el orchestrator ya
lo acepta y ya infiere tier cuando no viene, comportamiento sin cambios) para quien lo necesite,
mencionado solo en una sección "avanzado" separada de los documentos, nunca como parte del flujo
básico.

`commands/init.md` y `commands/doctor.md` como comandos independientes SIGUEN EXISTIENDO (no se
borran — hay usuarios avanzados/CI que pueden querer ejecutarlos explícitamente), pero dejan de ser
un paso obligatorio documentado para el uso normal.

### 2. Traducción de vocabulario — determinista, sin coste de modelo

Dos mecanismos combinados, ninguno añade un turno de modelo nuevo:

**2a. Tabla de sustitución estática** para las palabras-veredicto fijas que hoy se muestran tal
cual (`BLOCKED`, `DONE`, `KO`, `OK`) — una tabla en prosa dentro de `agents/orchestrator.md` (el
único agente cuyo output final llega al usuario) que instruye: antes de emitir tu línea final al
usuario, sustituye el prefijo técnico por su frase equivalente. Ejemplos concretos (el plan de
implementación fija la redacción exacta, esto es la forma, no el texto final):
- `DONE` → "Listo:"
- `BLOCKED <motivo>` → "No he podido continuar: <motivo>"
- `KO <motivo>` → "Algo no salió bien: <motivo>"

Esta sustitución es la ÚLTIMA cosa que pasa, después de que el `<motivo>`/detalle ya viene en
lenguaje llano (pieza 2b) — no reescribe el contenido, solo el prefijo.

**2b. Prosa ya existente, reescrita en su origen.** El texto libre que cada agente ya construye
(el `<motivo>` de un `BLOCKED`, las preguntas y opciones de `AskUserQuestion`) pasa a tener una
instrucción de estilo transversal: **redactar siempre pensando en el owner sin conocimientos
técnicos — impacto de negocio, nunca jerga interna del proyecto** ("tier", "run", "discovery",
"idempotencia", nombres de ficheros/funciones salvo que el propio owner los haya mencionado). Esta
instrucción se añade en los puntos donde el texto se CONSTRUYE, no en un filtro aparte:
- `agents/orchestrator.md` (sus propias líneas de output final — cierre §4, BLOCKED de §1.0/§1.0bis)
- `agents/discovery-orchestrator.md` (las preguntas que forma antes de devolverlas a la raíz)
- `agents/orchestrator.md` §1.0bis (la interpretación del objetivo, ya construido hoy — se
  reescribe el estilo, no el mecanismo)
- `agents/release-manager.md` (el gate de push, sus mensajes de error/discrepancia)

Los ficheros de hallazgos técnicos (`findings/*.md`, lo que ve `analysis-orchestrator` o
`implementation-orchestrator` internamente) NO se traducen — esos son para el propio enjambre y
para un desarrollador que revise `/swarm:findings`, no para la interacción del owner con el gate.

### 3. Gates de decisión — reformulados a impacto de negocio

Discovery, el gate de objetivo (§1.0bis), y el gate de push siguen preguntando — el owner sigue
siendo quien decide sobre SU producto — pero cada pregunta se reescribe con la misma disciplina de
la pieza 2b, y además:
- La opción recomendada SIEMPRE va marcada explícitamente como tal en el texto de la opción
  (`AskUserQuestion` ya soporta esto vía el label/description — usar ese mecanismo, no inventar
  uno nuevo), de forma que confirmar sin pensar sea una opción legítima y visible, no un atajo que
  el owner tenga que adivinar.
- Ejemplo concreto de la reformulación (no exhaustivo, el plan fija cada caso real del repo):
  "¿job asíncrono en cola o endpoint síncrono?" → "¿quieres que sea al instante, o puede tardar
  unos minutos si hay mucho volumen? (recomendado: puede tardar — así no se cae si crece)".

Este cambio vive en los MISMOS agentes que la pieza 2b (discovery, §1.0bis, release-manager) — es
la misma instrucción de estilo aplicada a sus preguntas, no un mecanismo aparte.

### 4. Qué NO cambia (motor interno intacto)

El roster completo de agentes, `hooks/bash-guard.py`, el contrato de evidencia
(`OK`/`evidence:`/`TAG · file:line`), la lógica de clasificación de tier (§1.1), y todos los
dominios (discovery/analysis/design/implementation/delivery) — sin cambios funcionales. Esta
recalibración es puramente de superficie: qué comando se escribe y qué texto se muestra.

## Impacto en otros ficheros

- `agents/orchestrator.md` — §2.1 (auto-init en vez de BLOCKED), instrucción de traducción de
  vocabulario en su cierre (§4) y en §1.0/§1.0bis's BLOCKED paths.
- `agents/discovery-orchestrator.md` — instrucción de estilo para sus preguntas.
- `agents/release-manager.md` — instrucción de estilo para sus mensajes de gate/error.
- `commands/run.md` — pasa a documentarse como `/swarm` (el nombre corto), sin mencionar `--tier=`
  en su descripción principal.
- `docs/USAGE.md`/`.es.md` — reescribir el quickstart: un solo comando, ejemplo real sin jerga;
  mover `--tier=` a una sección "avanzado" separada.
- `README.md`/`.es.md` — el ejemplo de invocación del quickstart pasa a `/swarm:run "<objetivo>"`.

## Testing

Mismo patrón que todo lo tocado hoy en `agents/orchestrator.md`: TDD (los tests de este repo
verifican PROSA, no comportamiento en runtime, vía `grep`/`has()` sobre los ficheros `.md`) + 2-3
rondas de review Opus adversarial antes de merge dado que sigue tocando el fichero más regresivo
del proyecto. Casos que el plan de implementación debe cubrir con test:
- El health-gate ya NO devuelve `BLOCKED falta /swarm:init` para el caso "no existe" — auto-inicia
  y continúa (verificar que SÍ sigue bloqueando para el caso "existe pero no escribible").
- La tabla de sustitución de vocabulario está presente y cubre los 4 prefijos (`DONE`/`BLOCKED`/
  `KO`/`OK`).
- La instrucción de estilo "lenguaje llano, impacto de negocio, sin jerga" está presente en los 4
  ficheros de la pieza 2b/3 (orchestrator, discovery-orchestrator, release-manager, §1.0bis ya
  cubierto dentro de orchestrator.md).
- `docs/USAGE.md`/`.es.md` documentan `/swarm` como el único comando del quickstart, `--tier=`
  aparece solo en una sección separada claramente marcada "avanzado"/"advanced".
- Regresión: `commands/init.md`/`doctor.md` NO se borran (siguen existiendo como comandos
  independientes, solo dejan de ser obligatorios en el flujo documentado).

## Riesgos y desviaciones conscientes

- **La reformulación de preguntas es responsabilidad de cada agente, no un validador automático.**
  No hay forma barata de verificar mecánicamente que una pregunta "suena a lenguaje llano" —
  confiamos en la instrucción de estilo + la revisión Opus adversarial del plan, igual que ya se
  confía en el juicio del LLM para el resto de prosa de este fichero (tablas "ilustrativas, no
  exhaustivas" ya usadas en §5.1/§8.1/§9.1/§1.0bis).
- **`--tier=` sigue siendo un flag real, solo se oculta de la documentación simple** — decisión
  consciente para no romper flujos de power-user/CI existentes (usados extensamente hoy mismo en
  esta sesión para smoke-testing) mientras se simplifica lo que un usuario nuevo necesita aprender.
