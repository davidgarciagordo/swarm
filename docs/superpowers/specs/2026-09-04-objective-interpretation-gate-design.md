# Gate de interpretación de objetivo — Design Spec

> **Origen:** brainstorming con el owner (2026-09-04), motivado por la pregunta "¿consideras tener
> un agente que traduzca y optimice lo que escribe el usuario? ¿como un prompt master?". Decisión
> del owner tras explorar el espacio: **no es un agente nuevo** — es un paso condicional dentro del
> propio `orchestrator` raíz.

## Objetivo

Cuando el owner escribe un objetivo vago, mal redactado, o difícil de clasificar con confianza en
`/swarm:run "<objetivo>"`, el `orchestrator` debe poder **mostrar su interpretación optimizada,
dejar que el owner la confirme o corrija, y usar esa versión confirmada** — en vez de clasificar a
ciegas sobre texto ambiguo o, peor, dejar que discovery haga las preguntas equivocadas por partir de
una lectura errónea del objetivo.

**Caso feliz intacto:** un objetivo ya claro (el 90%+ de los casos hoy) no ve NINGÚN cambio de
comportamiento — cero fricción nueva, cero línea de output nueva, cero turno extra.

## No objetivos (explícitamente fuera de alcance)

- **No es un agente nuevo.** El `orchestrator` ya es un LLM con `AskUserQuestion` real; añadir un
  agente dedicado costaría un roundtrip de modelo en cada run sin necesidad.
- **No traduce el `objective:` persistido de forma que rompa la detección de "ya cerrado" entre
  runs** (spec §9.1, `agents/orchestrator.md` §5.1) — ver "Idempotencia" abajo, es la restricción
  dura de todo este diseño.
- **No aplica a `tier: direct`** — ese tier nunca abre run ni toca memoria; el objetivo es siempre
  trivial por definición de ese tier.
- **No es interrogatorio libre** — sigue el mismo patrón de UNA tanda de discovery, nunca múltiples
  rondas de preguntas.

## Arquitectura

Nueva sub-sección `agents/orchestrator.md` **§1.0bis "Interpretación del objetivo"**, entre §1.0
("Guardas de invocación") y §1.1 ("Tiers") — corre ANTES de clasificar tier, porque una
interpretación mejor también mejora esa clasificación.

### Por qué no un agente

El `orchestrator` es el ÚNICO punto de todo el enjambre con `AskUserQuestion` real (spec §3.2 regla
7 — ningún subagente puede preguntar al owner). Cualquier agente dedicado a "interpretar el
objetivo" tendría que devolver su interpretación al orchestrator de todos modos para que este la
presente — un roundtrip completo (spawn + espera + resultado) por algo que el propio orchestrator ya
puede juzgar en su propio turno, sin coste adicional de modelo.

## Flujo de interacción

```
1. Objetivo no vacío (§1.0 ya pasó).
2. El orchestrator forma su interpretación del objetivo + nivel de confianza propio
   (juicio del LLM, no una métrica calculada — el mismo tipo de juicio que ya aplica
   en la clasificación de tier y en las tablas de keywords "ilustrativas, no exhaustivas"
   de §5.1/§8.1/§9.1).
3. SI confianza alta:
   → sigue directo a §1.1 (clasificación de tier), sin línea de output nueva.
4. SI confianza baja / objetivo ambiguo:
   → UNA AskUserQuestion, formato igual que discovery (una sola tanda):
     - la interpretación optimizada del orchestrator
     - hasta 2 alternativas si las hay
     - opción "quiero re-escribirlo yo" (free text, vía "Other" de AskUserQuestion)
   a. Owner confirma la interpretación, o elige una alternativa, o escribe la suya:
      → ESE texto final es el `objective:` de aquí en adelante — clasificación de tier,
        discovery, analysis, design, todo lo que ya consume `objective:` sigue igual,
        solo que ahora lee el texto confirmado en vez del crudo.
   b. Owner cancela el diálogo (mismo patrón que discovery §5.3/§5.4):
      → se registra `[pendiente]`, el run no sigue más allá de esta línea:
        `- run cerrado: BLOCKED interpretación de objetivo sin confirmar`
5. Continúa el resto del run (§1.1 en adelante) con el objetivo ya resuelto.
```

## Idempotencia — la restricción dura

**El problema:** `agents/orchestrator.md` §5.1 detecta "¿este objetivo ya se cerró en un run
anterior?" con un `Grep` EXACTO contra el campo `objective:` guardado en `.swarm/decisions.md`
(formato real, verificado: `- <fecha> · objective: <texto> · ...`, una línea plana por decisión).
Si el texto que se compara es la interpretación de un LLM no determinista, el MISMO objetivo crudo
del owner podría generar dos interpretaciones ligeramente distintas en dos runs distintos → el
match nunca encuentra el run anterior → el owner respondería el mismo batch de discovery una y otra
vez. Esto es exactamente el bug que §5.1 existe para prevenir (y el motivo por el que TODO el resto
del fichero insiste en "objetivo literal, sin resumir, sin traducir").

**Decisión del owner (tras ver la tensión):** la versión confirmada SÍ se convierte en el
`objective:` real — es lo que el owner quiere ver y lo que el resto del sistema debe consumir.

**Mitigación (aprobada por el owner):** `decisions.md` guarda DOS campos en la misma línea de
decisión en vez de uno:

- `raw:` — el texto crudo del owner, byte a byte, tal como llegó a `/swarm:run`. Invisible al owner
  en el uso normal (no aparece en ningún output de turno). Es la ÚNICA clave contra la que §5.1 hace
  el match de idempotencia — determinista, exacto, sin depender del juicio del LLM.
- `objective:` — la versión confirmada por el owner (interpretada+aceptada, o alternativa elegida, o
  re-escrita libremente). Es lo que clasificación de tier, discovery, analysis, design, y
  persistencia de decisiones consumen de aquí en adelante — sin cambio respecto a como funciona hoy,
  solo que la fuente de ese texto ya no es siempre el argumento crudo de `/swarm:run`.

Ejemplo de línea con ambos campos:
```
- 2026-09-04 · raw: arregla lo del csv que va lento · objective: optimiza la generación del
  CSV de facturas para que no haga N+1 queries · discovery <run-id> · ...
```

Cuando la interpretación no se disparó (confianza alta, caso feliz), `raw:` y `objective:` son
idénticos — se escribe el campo `raw:` de todos modos (coste cero, mismo texto dos veces) para que
el formato de la línea sea uniforme y el parser de §5.1 no necesite dos caminos distintos.

## Testing

Mismo patrón que refactor-routing y push-url= (ambos mergeados hoy en esta misma sesión): TDD desde
el principio, y 2-3 rondas de review Opus adversarial antes de merge — `agents/orchestrator.md` es
el fichero con más historial de regresión del proyecto (listas enumeradas desactualizadas en un
sitio y no en otro, ya documentado 3+ veces).

Casos que la implementación DEBE cubrir con test (no exhaustivo, el plan de implementación lo
detalla):
- Objetivo claro → cero línea nueva de output, cero `AskUserQuestion`, comportamiento idéntico a
  hoy (regresión negativa — lo más fácil de romper por accidente).
- Objetivo ambiguo → se dispara la pregunta, formato de UNA tanda como discovery.
- Owner confirma la interpretación tal cual → `raw:` ≠ vacío, `objective:` = la interpretación.
- Owner elige una alternativa → `objective:` = la alternativa, no la interpretación original.
- Owner re-escribe libre → `objective:` = su texto, no ninguna sugerencia del orchestrator.
- Owner cancela → `[pendiente]`, `BLOCKED`, el run no sigue.
- Un run posterior con el MISMO texto crudo (`raw:`) que un run ya cerrado → detecta "ya cerró"
  contra `raw:`, no contra `objective:`, incluso si una interpretación hipotética distinta se
  hubiera generado esta vez.
- `tier: direct` → el gate no se dispara nunca (no aplica, ver "No objetivos").
- `--tier=` explícito del owner → el gate SÍ se dispara igual si el objetivo es ambiguo (el flag
  fija el tier, no exime de la interpretación — la clasificación de tier y la interpretación del
  objetivo son cosas distintas).

## Impacto en otros ficheros

- `agents/orchestrator.md` — nueva §1.0bis; §5.1 debe leerse actualizado para explicar que compara
  contra `raw:`, no contra `objective:` (una frase, no una reescritura de la lógica existente).
- `scripts/mem-files.sh` (o el script que escriba decisiones — verificar el nombre real al
  implementar) — la escritura de una línea de decisión necesita el nuevo campo `raw:` además de
  `objective:`.
- Documentación: `docs/USAGE.md`/`.es.md` — una mención breve de que un objetivo ambiguo puede
  disparar una pregunta de aclaración antes de clasificar tier (bilingüe, como el resto del repo).
- `README.md`/`.es.md` — el diagrama mermaid de `/swarm:run` (ya existe, tocado hoy mismo por
  refactor-routing) probablemente necesita un nuevo paso opcional antes de la clasificación de tier.

## Riesgos y desviaciones conscientes

- **No determinismo del LLM al juzgar "confianza".** Un mismo objetivo podría disparar el gate una
  vez y no otra en ejecuciones distintas de la MISMA versión del prompt. Aceptado: el peor caso es
  una pregunta de más o de menos, nunca un run incorrecto (la idempotencia sigue protegida por
  `raw:`, que es determinista).
- **Coste de una `AskUserQuestion` adicional en el caso ambiguo.** Aceptado explícitamente por el
  owner como el punto entero del diseño — mejor una pregunta de más que un run mal clasificado o
  discovery preguntando sobre la interpretación equivocada.
