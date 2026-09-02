---
name: swarm-protocol
description: Contrato universal para todos los agentes del plugin swarm — memoria, evidencia, mailbox, modos adhoc/worktree.
---

# Protocolo swarm

Precargado (`skills: [swarm-protocol]`) en todo agente del plugin `swarm`. Este contrato es el
mismo para raíz, orquestadores de dominio y hojas — spec
`docs/superpowers/specs/2026-09-01-swarm-design.md` §5, §6, §9.2, §9.3.

## 1. Antes de actuar

1. **Lee la memoria antes de buscar.** `cat "$SWARM_ROOT/context-pack.md"` (o pide el pack a
   `memory-orchestrator` si no existe) ANTES de cualquier `Grep`/`Read` exploratorio. Abre solo el
   excerpt alrededor de la línea citada — nunca releas el fichero completo si el pack ya te dio
   `fichero:línea`.
2. **No re-reportes.** Si un hallazgo ya está en `findings/<otro-agente>.md` o en la sección
   `SHARED-FOUND` del pack, no lo repitas — cítalo o amplíalo, no lo dupliques.
3. **Lee tu buzón al arrancar.** Antes de actuar, comprueba si alguien te dejó contexto:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/<tu-nombre>.md" 2>/dev/null
   ```
   Si el fichero no existe, no hay mensajes pendientes — continúa normalmente.
   **Ojo con `$SWARM_ROOT`**: si tu frontmatter tiene `isolation: worktree`, usa la ruta ABSOLUTA
   que te dieron en el prompt de lanzamiento (ver §3) — NO el `$SWARM_ROOT` por defecto, que en un
   worktree resuelve a `$PWD/.swarm` (ruta equivocada). El `2>/dev/null` de arriba se traga el
   fallo: con la ruta mal leerías un buzón vacío creyendo que no tienes mensajes.

## 2. Modo run vs modo adhoc (§9.2)

Tu prompt de lanzamiento trae, cuando te lanza un orquestador, esta cabecera literal:

```
run-id: <uuid>
swarm-root: <ruta absoluta de .swarm>
operation: <la operación concreta que debes ejecutar en tu turno 1>
tier: <light|full>            (OPCIONAL — solo la escribe la raíz al lanzar un orquestador de dominio)
objective: <objetivo literal del owner>   (OBLIGATORIA para un orquestador de dominio; ausente en las hojas de memoria)
```

- Si incluye `run-id: <uuid>`, estás dentro de un run orquestado: usa `RUN=<ese uuid>` en todos los
  comandos de memoria. `swarm-root:` es la ruta absoluta del `.swarm/` canónico (úsala como se
  explica en §3 si tu cwd no es la raíz del repo). `operation:` dice qué tienes que hacer nada más
  arrancar, con el vocabulario de tu propio contrato (para `memory-orchestrator`:
  `query|write|build|curate`) — no lo deduzcas del resto del prompt.
- Si tu prompt NO incluye `run-id:`, te invocaron suelto (adhoc, fuera de un run orquestado): usa
  `RUN=adhoc` fijo. **No** llames a `mem-manifest.sh open` — ese comando es exclusivo de la raíz
  al abrir un run real. Tus escrituras van bajo `run/adhoc/`. **No crees directorios**: los scripts
  de escritura (`mem-files.sh write …`, `mem-manifest.sh register|summary`) ya crean por sí solos el
  árbol que necesitan (`findings/`, `run/adhoc/mailbox/`…) en la primera escritura. Sigue el
  contrato de evidencia (§4) sin excepción.
- `tier: light|full` (fase 2, spec §7.0): línea OPCIONAL que la raíz añade al lanzar un orquestador
  de dominio. Ausente ⇒ `full`. Un orquestador la usa para elegir el modelo de sus hojas de
  juicio al lanzarlas (`light` ⇒ override `model: "sonnet"` en el tool `Agent` para las hojas cuyo
  frontmatter dice `opus`); las hojas no la reciben ni la necesitan. Los orquestadores pueden añadir
  líneas propias detrás de la cabecera, siempre DESPUÉS de estas.
- `objective: <texto>` (fase 2, spec §7): el objetivo literal del owner, sin el flag `--tier`. La
  raíz la escribe SIEMPRE al lanzar un orquestador de dominio y el orquestador la reenvía tal cual a
  sus hojas; no es opcional para quien la necesita — un orquestador de dominio que la reciba vacía o
  ausente no improvisa objetivo: su veredicto es `BLOCKED objetivo vacío` (ver
  `agents/discovery-orchestrator.md`). Los agentes que no la necesitan (p. ej.
  `memory-orchestrator`) no la reciben.
- Caso particular: si eres `implementer` (fase 5, todavía no existe) y te invocan sin referencia a
  un plan concreto, tu veredicto es `BLOCKED necesita plan` — no improvises un plan.

## 2bis. Convención de nombre estable (decisión del owner, 2026-09-02)

Todo agente se lanza (`Agent(...)`) NOMBRADO — nunca anónimo — y su nombre es exactamente su rol,
sin sufijos ni variantes: el basename de su tipo (`memory-orchestrator`, `security-auditor`,
`analysis-orchestrator`…), igual en cada run. Esto es lo que permite:
- que agentes pares se manden `SendMessage(to: "<rol>", ...)` entre sí en cualquier momento (§5 del
  spec) sabiendo el nombre de antemano, sin tener que descubrirlo;
- que el owner (usuario humano) se dirija a un agente concreto por su rol — "avisa a
  security-auditor cuando termines", "pregúntale a memory-builder si ya tiene el pack" — y el
  orquestador que lo lanzó sepa exactamente a quién reenviar el mensaje.
`memory-orchestrator` es el caso ya obligatorio por spec (§4.5, instancia única por run, siempre
nombrada así). El mismo criterio se aplica a CUALQUIER otro agente que un orquestador lance, en
cualquier fase — quien lanza fija el nombre = rol, no delega el nombrado al azar.

## 3. Modo worktree (§9.3)

Si tu frontmatter tiene `isolation: worktree`, tu prompt de lanzamiento te da la ruta ABSOLUTA del
`.swarm/` del repo principal (no la de tu worktree aislado). Reglas:
- **Lee** ese `.swarm/` directamente con la ruta absoluta dada — nunca una copia dentro del
  worktree, y nunca asumas que `$SWARM_ROOT` relativo a tu cwd apunta al sitio correcto.
- **Nunca escribas ahí directamente.** Toda escritura (`finding`, `decision`, `mailbox`) va vía
  `SendMessage` a `memory-orchestrator`, que es quien tiene la ruta canónica y aplica el lock. Una
  escritura directa desde el worktree puede divergir del `.swarm/` canónico.

Nota operativa (comportamiento real de los scripts): todos leen `SWARM_ROOT` del entorno y, si no
está definida, caen a `$PWD/.swarm` — que en un worktree es la ruta EQUIVOCADA. Por eso, en modo
worktree, pasa siempre la ruta absoluta explícitamente en cada lectura, como prefijo del comando.
`hooks/bash-guard.py` reconoce UN prefijo `SWARM_ROOT=<valor>` como transparente: lo recorta y
valida el resto del segmento con las reglas normales (así que
`SWARM_ROOT=/abs/.swarm scripts/mem-files.sh health` pasa, y `SWARM_ROOT=/abs/.swarm rm -rf /`
se sigue denegando). `export SWARM_ROOT=…` como comando suelto NO está permitido — usa el prefijo:

```bash
SWARM_ROOT=/ruta/absoluta/al/repo/.swarm \
  "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "tenant" --scope findings
```

## 4. Contrato de evidencia (obligatorio, spec §6)

Toda salida de un agente `swarm:*` sigue este formato exacto:

```
<línea 1: veredicto>
evidence: files=N cmds=M turns=k/max
<líneas siguientes: hallazgos, opcional>
```

- **Línea 1 — veredicto**, una de: `OK` · `KO <peor problema>` · `DONE` · `BLOCKED <motivo>`.
- **Línea 2 — evidencia, MANDATORIA**: `evidence: files=N cmds=M turns=k/max` donde `N` = ficheros
  leídos, `M` = comandos deterministas ejecutados, `k/max` = turno actual sobre el `maxTurns` del
  frontmatter. El hook de validación es TOLERANTE con espacios extra alrededor de `=` y después de
  `:` (p. ej. `evidence:  files=2  cmds=1  turns=3/10` es válido) — pero el formato base (las
  claves `files=`, `cmds=`, `turns=.../...`) es obligatorio. El regex del hook ancla el final de
  línea (`\s*$`): la línea debe TERMINAR justo tras el valor de `turns` — nada de texto detrás
  (ni comentarios, ni un hallazgo pegado, ni puntuación).
- **`OK` con `files=0` se rechaza siempre** — un veredicto verde sin haber leído nada no es
  evidencia real.
- **Resto de líneas — hallazgos**, uno por línea, formato:
  `TAG · fichero:línea · problema → fix (≤8 palabras)`. El detalle completo (contexto largo,
  snippets) va a `findings/<tu-nombre>.md` vía `memory-orchestrator write finding`, NUNCA en la
  salida que lee el hook — cualquier prosa suelta ahí se interpreta como narración y se rechaza.

### 4.1 Cheat-sheet de invocación (rutas desde `${CLAUDE_PLUGIN_ROOT}`)

> Estas invocaciones directas son para agentes SIN `isolation: worktree`; si tu frontmatter la
> tiene, ver §3 — nunca escribas directo, todo pasa por `memory-orchestrator`.

```bash
# salud del backend files (antes de cualquier escritura, si tienes dudas)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" health

# escribir un hallazgo (dedup automático por [key:agente|tag|fichero:línea])
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 42 \
  --run "${RUN:-adhoc}" --text "clase sin interfaz" --fix "extraer interfaz"

# escribir una decisión (append a decisions.md)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write decision --text "usar sonnet para ejecución"

# dejar un mensaje en el buzón de otro agente (aunque aún no esté lanzado)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write mailbox \
  --to security-auditor --from architecture-auditor --run "${RUN:-adhoc}" \
  --text "revisa src/App/Foo.php:42 — sin interfaz, puede afectar aislamiento de tenant"

# consultar findings/decisiones/pack (cap 20 resultados)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "tenant" --scope findings

# comprobar si el context-pack está fresco antes de reconstruir (solo memory-builder)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" check

# manifest del run (solo raíz / memory-orchestrator)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register \
  --run "$RUN" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator
```

Cada llamada a `mem-files.sh write ...` y a `mem-manifest.sh register|summary|gc` ya adquiere y
libera el lock internamente (`scripts/mem-lock.sh`) — no lo llames tú directamente salvo que estés
escribiendo un script nuevo que toque `.swarm/` fuera de estos dos.

### 4.2 Firmas exactas y salidas (verificado contra los scripts commiteados)

`SWARM_ROOT` por defecto es `$PWD/.swarm` en los tres scripts; si tu cwd no es la raíz del repo,
pásala como prefijo del comando (`SWARM_ROOT=/ruta/absoluta/.swarm "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" …`),
que es la única forma que el guard admite — `export` como comando suelto se deniega (§3).

| comando | firma exacta | salida / exit |
|---|---|---|
| `mem-files.sh health` | `health` | `ok` + exit 0; exit 1 si `SWARM_ROOT` no existe o no es escribible |
| `mem-files.sh write finding` | `--agent --tag --file --line --run --text --fix` (los 7 obligatorios) | `written` o `dup` (ya había una entrada `[status:open]` con la misma key); exit 64 si falta un arg |
| `mem-files.sh write decision` | `--text` | `written` |
| `mem-files.sh write mailbox` | `--to --from --run --text` | `written` (append a `run/<run>/mailbox/<to>.md`) |
| `mem-files.sh query` | `query <regex> [--scope findings\|decisions\|pack\|all]` (default `all`) | `grep -rEn` (regex extendida, con `fichero:línea`), máximo 20 líneas |
| `mem-stale.sh check` | `check` | `fresh: …` exit 0 · `stale: …` exit 1 · `no pack-index: …` exit 2 |
| `mem-stale.sh hash` \| `seal` | sin flags | hash de 40 chars · `sealed: <hash>` (escribe `tree-hash:`/`sealed:` en `index.md`) |
| `mem-manifest.sh open` | `open --tier light\|full` (**solo la raíz**) | imprime el `run-id` nuevo, crea `run/<id>/{agents,mailbox,retries}` + `run.json` y apunta `run/current` |
| `mem-manifest.sh register` | `--run --agent --domain --area --owner` (los 5 obligatorios) | `registered` (escribe `run/<run>/agents/<agent>.json`) |
| `mem-manifest.sh summary` | `--run --line` | `written` (append a `run/<run>/summary.md`) |
| `mem-manifest.sh current` | sin flags | el run-id de `run/current`, o exit 1 si no hay |
| `mem-manifest.sh gc` | `gc [--keep N]` (default 10) | `gc: kept newest N run(s)`; nunca borra `adhoc` ni el run apuntado por `run/current` |

### 4.3 Lo que el hook comprueba literalmente (`hooks/validate-output.py`)

- Solo se aplica a `agent_type` que empieza por `swarm:`; el resto pasa sin tocar.
- Línea 1 contra `^(OK|KO .+|DONE|BLOCKED .+)$` — `KO` y `BLOCKED` **exigen** motivo detrás.
- Línea 2 contra `evidence:` + `files=` `cmds=` `turns=k/max`, tolerante a espacios.
- De la línea 3 en adelante: se acepta cualquier línea vacía, cualquier línea que empiece por `- `,
  y cualquier línea con formato de hallazgo. Una línea que no encaje y además pase de 120
  caracteres se rechaza como narración — mantén cada hallazgo en una línea corta.
- `turns=k/max` con `k == max` NO bloquea: el hook emite un `systemMessage` de `maxTurns` y acepta.
- Un rechazo se reintenta una sola vez por agente + motivo (`run/<run>/retries/`); al segundo
  rechazo por el MISMO motivo se acepta como `BLOCKED`. No hay bucle infinito, pero fallar dos
  veces gasta un turno por nada — acierta el formato a la primera.

## 5. Tool determinista antes que modelo

Antes de razonar sobre un problema, ejecuta el linter/scanner/test determinista del pack (si
aplica) y trata solo el residual con juicio de modelo. Nunca "revises a ojo" lo que un `--fix`
puede resolver solo.

## 6. Parar por saturación

Deja de explorar cuando dejes de encontrar patrones nuevos, no cuando llegues a un número fijo de
hallazgos. `maxTurns` de tu frontmatter es el límite duro — si lo alcanzas sin cerrar, tu veredicto
es igualmente `OK`/`DONE`/`KO`/`BLOCKED` con la evidencia que tengas; el hook se encarga de anotar
`maxTurns` si corresponde, tú no necesitas mencionarlo aparte.

## 7. Frontmatter obligatorio

Todo agente de este plugin declara, sin excepción: `name`, `description` (frase "Use when…" que
dispare uso proactivo), `model`, `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`.
Nunca declares `hooks`, `mcpServers` ni `permissionMode` en el frontmatter — se ignoran para
subagentes de plugin (spec §3.1) y su presencia solo confunde a quien lea el fichero.

## 8. Ejemplos de salida completa

### Ejemplo A — `OK` con evidencia y hallazgos

```
OK
evidence: files=4 cmds=2 turns=6/15
ARCH · src/App/Foo.php:42 · clase sin interfaz → extraer interfaz
ARCH · src/App/Bar.php:10 · lógica de dominio en controller → mover a servicio
```

### Ejemplo B — `BLOCKED`

```
BLOCKED necesita plan
evidence: files=1 cmds=0 turns=1/30
```
