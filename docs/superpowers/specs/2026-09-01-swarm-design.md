# Swarm — enjambre de agentes Claude Code para el ciclo de desarrollo

Fecha: 2026-09-01 · Estado: v2.1 tras grill ×3 + dominio requirements (2026-09-01) · Plugin: `swarm`

## 1. Objetivo

Plugin de Claude Code instalable en cualquier repo que aporte un enjambre de agentes con
responsabilidad única para análisis, diseño, implementación, testing, documentación y entrega,
**optimizado en calidad por token**. Agnóstico de stack: lo específico vive en *stack packs*.
Caso de estudio de necesidades: proyecto Quantum (PHP/DDD/Symfony, multi-tenant), pero el
producto es genérico.

## 2. Principios (no negociables)

1. **Un agente, una responsabilidad.** Añadir capacidad = añadir agente, no engordar uno.
2. **Memoria es un fichero; el agente solo la mantiene.** Leer un pack cacheado ≈ gratis; preguntar
   a un modelo cuesta un turno. Se pregunta solo cuando hace falta interpretación.
3. **Discover-once.** El repo se escanea una vez por run (context-pack fichero:línea). Nadie re-escanea.
4. **Tool determinista antes que modelo.** Linters/scanners/tests se ejecutan; el modelo (tier más
   barato) solo trata el residual.
5. **Modelo por dificultad.** Opus decide/revisa/diseña; Sonnet ejecuta planes cerrados; Haiku enruta
   y hace lo mecánico. El juicio nunca en modelo débil.
6. **Salida terse por contrato.** Detalle a fichero, al orquestador ≤N líneas autocontenidas.
7. **Read-only por construcción** en análisis (`tools` sin Edit/Write/Bash de mutación).
8. **Jerarquía de 2 niveles máximo.** Raíz + orquestadores de dominio. Nunca 3.
9. **Evidencia antes de afirmar.** Ningún agente declara verde sin output real.

## 3. Arquitectura

```
orchestrator (raíz · opus)
├─ memory-orchestrator (haiku)          → memory-builder · memory-curator · backends [instancia única por run]
├─ requirements-orchestrator (haiku)    → env-checker · dependency-auditor · dependency-installer
├─ discovery-orchestrator (sonnet)      → value-critic · research-analyst · options-generator · feasibility-spiker
├─ analysis-orchestrator (sonnet)       → opportunity-analyst · architecture-auditor · security-auditor
│                                          · vulnerability-scanner · performance-analyst · data-model-auditor
├─ design-orchestrator (sonnet)         → planner · pattern-advisor · domain-modeler · grill×3 (externos)
├─ implementation-orchestrator (sonnet) → implementer · test-writer · migration-engineer
│                                          · quality-fixer · reviewer · doc-writer
└─ delivery-orchestrator (haiku)        → release-manager · handoff-writer
```

### 3.1 Restricciones de plataforma (verificadas contra https://code.claude.com/docs/en/sub-agents.md, 2026-09-01)
- Frontmatter soportado: `name`, `description`, `tools`, `disallowedTools`, `model`, `maxTurns`,
  `skills`, `memory` (`user|project|local`), `background`, `effort`, `isolation` (`worktree`),
  `color`, `experimental.cacheTtl`.
- **`hooks`, `mcpServers`, `permissionMode` en frontmatter se IGNORAN para subagentes de plugin.**
  Todos los hooks viven en `hooks/hooks.json` a nivel de plugin (`SubagentStart`/`SubagentStop`/
  `PreToolUse` con matcher sobre `agent_type`). MCP se hereda de la sesión, no se declara por agente.
- `tools:` acepta nombres de tool, `Agent(nombre,...)`, `mcp__<server>` / `mcp__<server>__*`. **No**
  acepta `Bash(cmd:*)` con subcomando → los agentes declaran `Bash` a secas; la restricción real la
  impone un hook `PreToolUse` de plugin, keyed por `agent_type`, con allowlist de prefijos de comando
  por agente en `hooks/bash-allowlist.json`.
- Roster de hermanos + `SendMessage` entre subagentes está documentado (v2.1.206+): requiere
  `SendMessage` en `tools` del agente, los agentes deben ir NOMBRADOS al spawn, el roster es un
  snapshot al inicio → hojas paralelas deben lanzarse en la misma tanda/mensaje.
- Subagente puede lanzar subagentes solo en foreground; un subagente en background no lanza hijos
  background → orquestadores de dominio corren foreground y lanzan hojas en paralelo en un mismo turno.
- Agentes de plugin en subcarpetas registran como `swarm:<carpeta>:<nombre>` → usamos `agents/` plano,
  los nombres quedan `swarm:<nombre>`.
- `skills:` de precarga de skills de plugin tiene sintaxis no fiable/documentada → los packs viven en
  `skills/pack-<stack>/` y los orquestadores pasan la RUTA del pack en el prompt de la hoja; la hoja
  hace `Read` del pack (nunca mutación de frontmatter en runtime).
- Agent Teams (buzón + task list compartida) es experimental
  (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`): fuera del diseño base; modo opcional futuro.
- Pipelines fijos y grandes (≥5 agentes) se expresan como Workflow script (determinista) cuando el
  usuario lo ha habilitado; si no, los orquesta el orquestador de dominio.
- Precedencia de agentes: proyecto > usuario > plugin.

### 3.2 Reglas de la jerarquía
1. Raíz habla solo con orquestadores de dominio; nunca con hojas.
2. Un dominio no habla con otro dominio: cruces vía raíz o vía memoria.
3. Excepción: **peer-to-peer entre hojas en cualquier momento** (§5), mirrored a buzón.
4. Orquestador de dominio: contrato único — entrada `(objetivo, run-id)`, salida `(veredicto ≤10 líneas,
   rutas a findings)`. Nunca ejecuta trabajo de hoja.
5. Añadir hoja = fichero de agente + línea en el roster del orquestador de dominio. Raíz no cambia.
6. Añadir dominio = nuevo `<x>-orchestrator` + línea en el roster de la raíz.
7. `discovery-orchestrator` corre antes que `design-orchestrator` (fase 2, §15). Sus hojas no pueden
   preguntar al owner: devuelven UN batch de preguntas+opciones y la raíz lo presenta con
   `AskUserQuestion` (§7 Discovery).

## 4. Subsistema de memoria

### 4.1 Layout en el repo target
```
.swarm/
  memory.json               backends + política (commiteado)
  decisions.md              decisiones con fecha/PR (commiteado)
  context-pack.md           mapa repo fichero:línea, stack detectado, convenciones, entrypoints (gitignored)
  index.md                  inventario + sello tree-hash de validez por artefacto (gitignored)
  findings/<agente>.md      hallazgos completos por agente (gitignored)
  .lock                     flock de escritura, una por repo (gitignored)
  run/<run-id>/
    agents/<agente>.json    manifest per-agente, append-only (gitignored)
    mailbox/<agente>.md     buzón persistido por agente (gitignored)
    retries/<agente>        contador de reintentos del hook de evidencia (gitignored)
    summary.md              resumen del run, visible al usuario (gitignored)
  run/adhoc/                runs de hojas invocadas sin run-id (§9.2)
```

### 4.2 Agentes
| agente | modelo | tools | responsabilidad |
|---|---|---|---|
| `memory-orchestrator` | haiku | Read, Grep, Bash (restringido por hook), SendMessage, mcp__plugin_claude-mem_mcp-search__* | única puerta: `query|write|build|curate`; lee `memory.json`, despacha a backends por política, fusiona y devuelve ≤5 líneas con fuente; dedup en escritura; **instancia única por run** |
| `memory-builder` | sonnet | Read, Grep, Glob, Bash (restringido por hook), Write(.swarm/) | construye/refresca `context-pack.md` + `index.md`; detecta stack; consulta backend histórico al construir |
| `memory-curator` | haiku | Read, Edit, Bash (restringido por hook) | compacta findings, poda decisions, controla tamaños (MEMORY.md ≤25KB), marca staleness, ciclo de vida de findings (§10), GC de `run/` |

### 4.3 Backends (adaptadores, no agentes)
Contrato: `query <texto>` · `write <tipo> <payload>` · `health`. Implementación = script o MCP.

| backend | tipo | por defecto | requerido |
|---|---|---|---|
| `files` | script `scripts/mem-files.sh` sobre `.swarm/` | sí | **sí — health-gate bloqueante** |
| `claude-mem` | MCP `memory_search` / `get_observations` / `observation_add` | histórico cross-sesión | no — best-effort |
| `agent-memory` | nativo `memory: project` por agente (MEMORY.md autoinyectado) | sí, por agente | no |
| `custom` | cualquier script/MCP declarado en `memory.json` | no | no |

`health` falla en un backend no requerido → se salta con una línea de warning en el summary del run,
nunca bloquea una escritura.

`memory.json` (ejemplo):
```json
{
  "backends": [
    { "name": "files", "type": "files", "root": ".swarm", "default": true, "required": true },
    { "name": "claude-mem", "type": "mcp", "server": "plugin_claude-mem_mcp-search", "scope": "historical", "required": false }
  ],
  "policy": {
    "read": ["files", "claude-mem"],
    "write": ["files", "claude-mem"],
    "stale": { "mode": "tree-hash" }
  }
}
```

### 4.4 Flujo
1. Raíz abre run (`run-id` = `uuidgen`) → lanza `memory-orchestrator` NOMBRADO (instancia única del
   run) → `build` solo si pack ausente o stale.
2. Staleness = **tree-state hash**: sha de (`git rev-parse HEAD:` + sha de `git status --porcelain` +
   mtimes de los directorios cubiertos por el pack), comparado contra el sello en `index.md`.
3. Hoja necesita contexto → lee `context-pack.md` directamente (prefijo estable → prompt-cache).
4. Solo si el pack no responde → `SendMessage(memory-orchestrator, "query: …")` a la instancia viva
   (nunca se lanza una segunda instancia).
5. Toda escritura de hallazgo/decisión pasa por `memory-orchestrator write`; `scripts/mem-files.sh`
   adquiere `flock` sobre `.swarm/.lock` en cada escritura.
6. Cierre de run → `curate` + `observation_add` en histórico.

### 4.5 Concurrencia
- `run-id` = `uuidgen`, generado una vez por la raíz al abrir el run.
- `scripts/mem-files.sh` adquiere `flock` sobre `.swarm/.lock` en CADA escritura (findings, decisions,
  manifest).
- Manifest = un fichero por agente: `run/<id>/agents/<nombre>.json`, append-only. Nunca un manifest
  global sobrescribible.
- Exactamente UNA instancia de `memory-orchestrator` por run: la raíz la lanza NOMBRADA al abrir el
  run. Toda hoja que necesite memoria hace `SendMessage` a esa instancia viva (resume) — nunca lanza
  una nueva.

### 4.6 Bootstrap
- Comando `/swarm:init`: crea `.swarm/`, `memory.json` por defecto, entradas de `.gitignore`
  (`context-pack.md`, `index.md`, `findings/`, `run/`, `.lock`), esqueleto de `decisions.md`.
- Backends health-gated: `files` es REQUERIDO (health falla → init aborta). El resto es best-effort
  (§4.3).

## 5. Protocolo de comunicación
- Al lanzar una tanda, el orquestador escribe `run/<id>/agents/<agente>.json`: `{agente, dominio, área, dueño}`.
- **Peer-to-peer (decisión del owner):** cualquier hoja puede `SendMessage` a cualquier otra hoja en
  cualquier momento, dentro o fuera de su área. Mensaje ≤10 líneas, formato de hallazgo (§6).
- **Buzón (mailbox):** todo `SendMessage` entre hojas se persiste ADEMÁS en
  `run/<id>/mailbox/<agente-destino>.md` vía `memory-orchestrator` (espejo, no solo el mensaje
  directo). Así los orquestadores de dominio conservan visibilidad y una hoja lanzada tarde lee su
  buzón al arrancar antes de actuar.
- Si el destinatario aún no está en el roster (no lanzado todavía), el router escribe solo al buzón; la
  hoja lo consume al arrancar.
- Continuación de trabajo = `SendMessage` al agente vivo (conserva contexto), nunca relanzar.
- Riesgo de smoke test: visibilidad mutua de hermanos lanzados en la misma tanda y entrega a hoja
  tardía — mitigado por el buzón anterior (ya no depende solo del roster).

## 6. Contrato universal de agente (skill `swarm-protocol`, precargado en todos)
1. Leer `.swarm/context-pack.md` antes de cualquier búsqueda; abrir solo excerpts alrededor de la línea citada.
2. No re-reportar lo que está en `findings/` de otro agente ni en SHARED-FOUND del pack.
3. **Contrato de evidencia (obligatorio):**
   - línea 1 — veredicto: `OK` | `KO <peor>` | `DONE` | `BLOCKED <motivo>`.
   - línea 2 — MANDATORIA: `evidence: files=N cmds=M turns=k/max`.
   - resto — hallazgos `TAG · file:línea · problema → fix (≤8 palabras)`. Detalle completo →
     `findings/<agente>.md`.
4. Tool determinista primero; modelo para residual.
5. Parar por saturación (sin patrón nuevo), `maxTurns` explícito en frontmatter.
6. Frontmatter obligatorio: `name`, `description` (proactiva: "Use when…"), `model`, `tools`, `maxTurns`,
   `memory: project`, `skills: [swarm-protocol]`.

### 6.1 Validación del contrato (hook, sin modelo)
`SubagentStop` (script en `hooks/hooks.json`) valida cada salida:
- Rechaza (`exit 2`, mensaje de vuelta al agente) si falta la línea 2 (`evidence: …`).
- Rechaza si `OK` con `files=0` (verdicto verde sin evidencia real).
- Rechaza si detecta narración (prosa fuera del formato de hallazgo).
- Si `turns == max`, reescribe el veredicto a `BLOCKED maxTurns` (corrige, no rechaza).
- Reintento gestionado por el hook: máximo 1, contador en `run/<id>/retries/<agente>`; al segundo
  fallo se acepta la salida como `BLOCKED` (nunca bucle infinito).

## 7. Roster completo

Nota: todas las hojas y todos los orquestadores llevan `SendMessage` en su `tools` (protocolo
peer-to-peer, §5) — no se repite en cada fila. `tools` completo por agente vive en `agents/<nombre>.md`.

### 7.0 Modelo por tier
| capa | tier `full` | tier `light` | tier `direct` |
|---|---|---|---|
| raíz | opus | opus | opus (responde directo, sin enjambre) |
| orquestadores de dominio | sonnet (delivery/memory: haiku) | sonnet (delivery/memory: haiku) | — |
| hojas de juicio (auditores, planner, pattern-advisor, domain-modeler, reviewer, value-critic, options-generator) | opus | sonnet | — |
| hojas mecánicas (vulnerability-scanner, quality-fixer, handoff-writer) | haiku | haiku | — |

### Raíz
| agente | rol | modelo | tools | maxTurns | responsabilidad |
|---|---|---|---|---|---|
| `orchestrator` | root | opus | Agent, Read, Bash (restringido por hook), SendMessage | 30 | clasifica tier (§9.1), elige dominios, exige pack, arbitra conflictos entre dominios, presenta el batch de discovery con `AskUserQuestion` |

### Requisitos (entorno y dependencias)
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `requirements-orchestrator` | domain-orchestrator | haiku | 10 | fusiona `requirements.json` del plugin + del pack activo; lanza checker/auditor; solo autoriza installer con aprobación explícita del owner (vía raíz) |
| `env-checker` | leaf | haiku | 6 | determinista: `scripts/req-check.sh` verifica tools de OS (`git`, `python3`, `uuidgen`; opcionales `jq`, `gh`, `docker`…) y versiones; informe JSON + hint de instalación; modelo solo para residual |
| `dependency-auditor` | leaf | sonnet | 12 | dependencias de proyecto: desactualizadas, sin uso, licencias, CVE (comandos del pack: `scan-deps`, `outdated`); read-only |
| `dependency-installer` | leaf | sonnet | 10 | instala/actualiza lo que el owner aprobó (brew/apt, composer/npm…); mutante, nunca en `direct`/`light` sin aprobación |

Contrato `requirements.json` (plugin raíz y cada `skills/pack-<stack>/requirements.json`, mismo esquema):
```json
{ "os":      [ {"tool":"git","min":"2.30","required":true,"install":{"brew":"git","apt":"git"}},
               {"tool":"jq","required":false,"install":{"brew":"jq","apt":"jq"}} ],
  "project": [ {"file":"composer.json","required":true} ],
  "libs":    [ {"name":"phpstan/phpstan","manager":"composer","min":"2.1","required":false} ] }
```
`/swarm:init` y `/swarm:doctor` invocan `env-checker`; un `required` ausente → `BLOCKED <tool>` con el hint.
Añadir requisitos = editar JSON (plugin o pack); los agentes no cambian (extensible por packs, SRP).

### Discovery (antes de diseño)
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `discovery-orchestrator` | domain-orchestrator | sonnet | 15 | lanza las 4 hojas en paralelo, fusiona en un único batch de preguntas+opciones para la raíz |
| `value-critic` | leaf | opus | 8 | pregunta de valor primero; devuelve ≤3 preguntas de alto impacto |
| `research-analyst` | leaf | sonnet | 15, `background: true` | prior art, competencia, estándares → requisitos |
| `options-generator` | leaf | opus | 10 | 2-3 enfoques con trade-offs + recomendada, disciplina YAGNI |
| `feasibility-spiker` | leaf | sonnet | 15, `background: true` | spike desechable → responde una pregunta de viabilidad concreta |

Restricción: ningún subagente puede preguntar al owner (§3.2 regla 7). `discovery-orchestrator`
devuelve UN batch (preguntas + opciones); la RAÍZ lo presenta con `AskUserQuestion`
(multi-select, una sola tanda).

### Análisis (read-only)
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `analysis-orchestrator` | domain-orchestrator | sonnet | 20 | elige lentes por objetivo, lanza en paralelo, fusiona |
| `opportunity-analyst` | leaf | opus | 15 | deuda, oportunidades producto/arquitectura, quick wins con ROI |
| `architecture-auditor` | leaf | opus | 15 | límites/capas/dependencias, acoplamiento, invariantes arquitectónicas |
| `security-auditor` | leaf | opus | 15 | authN/authZ, aislamiento de datos (tenant/usuario), OWASP, secretos, criptografía |
| `vulnerability-scanner` | leaf | haiku | 10 | ejecuta scanners del pack (deps/CVE/secrets/SAST); modelo solo para residual |
| `performance-analyst` | leaf | sonnet | 15 | consultas N+1, índices, cache, colas, hot paths |
| `data-model-auditor` | leaf | sonnet | 15 | drift esquema ↔ mapeos ↔ migraciones; integridad referencial |

### Diseño
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `design-orchestrator` | domain-orchestrator | sonnet | 20 | spec → grill → plan; arbitra actas |
| `planner` | leaf | opus | 20 | plan por fases con fichero:línea, áreas disjuntas, riesgos |
| `pattern-advisor` | leaf | opus | 10 | patrón adecuado (GoF/DDD táctico/enterprise/idiomático del pack); cita precedentes del repo; veredicto `reuse <x>` \| `introduce <y> porque…` |
| `domain-modeler` | leaf | opus | 15 | agregados, VOs, eventos, invariantes; respeta límites del pack (p. ej. código generado) |
| grill ×3 | externo | — | — | `working-methods:grill-architect/operator/engineer` — se invocan, no se duplican |

### Implementación
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `implementation-orchestrator` | domain-orchestrator | sonnet | 25 | ejecuta plan por tareas; gate review antes de cerrar |
| `implementer` | leaf | sonnet | 30 | ejecuta UNA tarea cerrada del plan; `isolation: worktree` |
| `test-writer` | leaf | sonnet | 20 | TDD: test primero, factories/mothers del pack |
| `migration-engineer` | leaf | sonnet | 15 | migraciones de esquema coherentes con mapeos |
| `quality-fixer` | leaf | haiku | 10 | corre lint/format/typecheck `--fix` del pack; parchea residual |
| `reviewer` | leaf | opus | 15 | review de diff, severidad-tagged, gate pre-merge |
| `doc-writer` | leaf | sonnet | 15 | docs con formato del pack, changelog |

### Entrega
| agente | rol | modelo | maxTurns | responsabilidad |
|---|---|---|---|---|
| `delivery-orchestrator` | domain-orchestrator | haiku | 10 | secuencia release + handoff |
| `release-manager` | leaf | sonnet | 15 | rama, PR, changelog, merge en verde |
| `handoff-writer` | leaf | haiku | 8 | handoff MD de relevo de sesión |

Descartes conscientes: `api-designer` (absorbido por planner + pack), `ci-watcher` (hook/loop),
lentes de UI/diseño visual (plugin `design-review` existente).

Total de agentes propios del plugin: **30** — 1 raíz + 3 memoria (§4.2) + 5 discovery + 7 análisis +
4 diseño + 7 implementación + 3 entrega (grill×3 es externo, no cuenta).

## 8. Stack packs

`skills/pack-<nombre>/` con contrato fijo (skill cargable):
```
SKILL.md          descripción + detección (ficheros marcadores)
commands.md       lint | fix | typecheck | test | test-one | scan-deps | scan-secrets | sast
conventions.md    estilo, arquitectura, capas, naming
boundaries.md     qué NO tocar (generado, vendor, migraciones aplicadas…)
precedents.md     patrones ya en uso (se rellena desde el pack de memoria)
requirements.json tools de OS / ficheros de proyecto / librerías que el pack necesita (§7 Requisitos)
```

### 8.1 Detección de stack (precedencia)
| orden | condición | stack |
|---|---|---|
| 1 | `composer.json` con `symfony/*` en require | `php-ddd-symfony8` |
| … | (siguientes packs, según se añadan) | — |
| fallback | ningún marcador confidente | `generic` + warning en el summary del run |

Sin match confidente → `stack: generic` en `context-pack.md`, nunca bloquea. Multi-stack por ruta
(monorepo con >1 stack en subcarpetas distintas) → fuera de alcance v2 (§16).

Primer pack: `php-ddd-symfony8` (derivado del estudio de Quantum). `memory-builder` detecta stack por
la tabla anterior → escribe `stack:` en `context-pack.md` → orquestadores pasan la RUTA del pack
(`skills/pack-<stack>/`) en el prompt de las hojas que lo necesitan (implementation, data-model-auditor,
vulnerability-scanner, doc-writer); la hoja hace `Read` (§3.1). Sin pack → conocimiento genérico.

## 9. Modos de ejecución

### 9.1 Tiers de run
| tier | cuándo | comportamiento |
|---|---|---|
| `direct` | trivial, sin enjambre | la raíz responde ella misma, sin lanzar dominios |
| `light` | un solo dominio | hojas de juicio en sonnet (no opus), sin grill, pack se construye SOLO si falta |
| `full` | multi-dominio o crítico | opus en hojas de juicio, grill ×3 activo |

La raíz clasifica por tamaño (ficheros tocados / alcance estimado); el usuario puede forzar con
`/swarm:run --tier=<t>`. Construcción de pack es LAZY: nunca antes de clasificar; `direct` nunca
construye pack.

### 9.2 Modo adhoc
Una hoja invocada directamente sin `run-id` (fuera de un run orquestado) lo detecta, construye contexto
mínimo ella misma, y escribe bajo `run/adhoc/`. Sigue aplicando el contrato de evidencia (§6) sin
excepción. Caso particular: `implementer` invocado sin referencia a un plan → `BLOCKED necesita plan`.

### 9.3 Worktrees
Hojas con `isolation: worktree` reciben en el prompt la ruta ABSOLUTA de `.swarm/` del repo principal.
Leen ese `.swarm/` directamente (nunca una copia en el worktree) y escriben solo vía
`memory-orchestrator` (nunca escritura directa desde el worktree — evita divergencia con el `.swarm/`
canónico).

## 10. Ciclo de vida de hallazgos
- Clave de hallazgo: `agente+tag+file:línea`. Cada entrada guarda el sha de la línea citada en el
  momento del hallazgo.
- `memory-curator` marca `resolved` cuando el sha de esa línea cambia (el código se movió/cambió).
- Entradas `resolved` dejan de contar para "ya reportado" (§6, punto 2).
- `memory-curator` también hace GC de `run/`: conserva los últimos 10 runs, y poda de `findings/` las
  entradas `resolved` con más de 30 días.

## 11. Visibilidad
- `/swarm:status` — run actual, agentes activos, tier, coste acumulado si está disponible.
- `/swarm:findings [agente|tag]` — consulta filtrada sobre `findings/`.
- Todo run escribe `run/<id>/summary.md` al cierre.
- Warning "pack ausente/stale → reconstruyendo" (y cualquier backend saltado por `health`) se refleja
  como línea visible en el summary para el usuario.

## 12. Estructura del plugin
```
.claude-plugin/plugin.json
agents/                        un .md por agente (§7), flat (nombres `swarm:<agente>`)
commands/                      init.md · run.md · status.md · findings.md · doctor.md
requirements.json              requisitos de OS del propio plugin (§7 Requisitos)
skills/swarm-protocol/         contrato universal (§6)
skills/pack-php-ddd-symfony8/  primer stack pack (§8)
scripts/mem-files.sh           backend files; lock atómico por escritura (mkdir; macOS sin flock)
scripts/req-check.sh           verificación determinista de requirements.json (env-checker)
scripts/mem-stale.sh           tree-state hash (§4.4)
scripts/mem-manifest.sh        manifest per-agente append-only
hooks/validate-output.py       valida contrato de evidencia (SubagentStop; python3 stdlib, sin jq)
hooks/bash-guard.py            PreToolUse: allowlist de Bash por agent_type
hooks/hooks.json               SubagentStart/SubagentStop/PreToolUse (§3.1, §6.1)
hooks/bash-allowlist.json      allowlist de prefijos Bash por agent_type (§3.1)
docs/superpowers/specs/        este spec + planes
tests/                         smoke tests (§14)
```

## 13. Gestión de tokens (mecanismos, no consejos)
- Context-pack como prefijo estable compartido → prompt-cache en tandas paralelas.
- Orquestadores de dominio: sonnet/haiku; solo raíz y juicio en opus (tier `full`, §9.1).
- `maxTurns` en todos; hojas de análisis/discovery `background: true` cuando la raíz no espera.
- Detalle a `findings/`, contexto del orquestador ≤N líneas.
- `memory-curator` mantiene MEMORY.md ≤25KB por agente.
- Staleness por tree-hash evita reconstrucciones de pack innecesarias (§4.4).
- Hook `SubagentStop` valida formato de salida y rechaza narración (§6.1).

## 14. Verificación
Smoke tests en `tests/` (repo fixture mínimo):
1. `build` crea `context-pack.md` + `index.md`; segundo `build` sin cambios = no-op.
2. `query` con pack presente responde sin invocar builder.
3. Dos hojas nombradas en la misma tanda se mensajean (`SendMessage`) — visibilidad de hermanos.
4. `write` duplicado → una sola entrada en `findings/`.
5. Escrituras concurrentes a `.swarm/` (dos hojas escribiendo a la vez) → `flock` serializa, sin
   corrupción ni pérdida de entradas.
6. Mensaje a un agente aún no lanzado → llega al buzón (`run/<id>/mailbox/<agente>.md`); el agente lo
   lee al arrancar más tarde.
7. Cambio sin commitear en el árbol → tree-state hash cambia → pack marcado stale y reconstruido.
8. Hook `SubagentStop` rechaza salida sin línea `evidence:`, y rechaza `OK` con `files=0`.
9. Hoja invocada sin `run-id` (modo adhoc) construye contexto mínimo y escribe bajo `run/adhoc/`
   cumpliendo el contrato de evidencia.
10. Clasificación de tier: objetivo trivial → `direct` sin lanzar dominios; objetivo multi-dominio →
    `full`.
11. Detección de stack con marcadores del pack `php-ddd-symfony8`; repo sin marcadores → `generic` +
    warning.
12. `implementer` invocado sin plan → `BLOCKED necesita plan`.

## 15. Fases de entrega
1. Núcleo: `orchestrator`, subsistema memoria (3 agentes + backends files/claude-mem), `swarm-protocol`,
   hooks (incl. hook de evidencia §6.1 y `bash-allowlist`), comando `/swarm:init`, smoke tests 1-8.
1b. Requisitos: `requirements-orchestrator` + `env-checker` (+ `req-check.sh`, `requirements.json` del plugin, `/swarm:doctor`); `dependency-auditor`/`installer` con el primer pack (fase 5).
2. Discovery: `discovery-orchestrator` + 4 hojas, integración `AskUserQuestion` en la raíz.
3. Análisis: `analysis-orchestrator` + 6 lentes.
4. Diseño: `design-orchestrator`, `planner`, `pattern-advisor`, `domain-modeler`, integración grill×3.
5. Implementación: 7 agentes + pack `php-ddd-symfony8` (en `skills/pack-php-ddd-symfony8/`).
6. Entrega: 3 agentes + comandos `/swarm:status`, `/swarm:findings`. Opcional: modo Agent Teams tras flag.

Cada fase: agente por agente, aprobación del owner, commit por agente.

## 16. Fuera de alcance (v1)
Agent Teams como base; UI/diseño visual; CI externo; más de un stack pack; 3 niveles de jerarquía;
multi-stack por ruta (monorepo con distintos stacks en subcarpetas); telemetría de coste más allá de
lo que expone el CLI.

## 17. Changelog v1→v2
1. §3.1 reescrito con hechos de plataforma verificados: frontmatter real, `hooks`/`mcpServers`/`permissionMode` ignorados en subagentes de plugin, límites reales de `tools`, ubicación de packs.
2. Roster: `tools` corregidas (`Bash` + hook de restricción, `mcp__plugin_claude-mem_mcp-search__*`); `SendMessage` añadido a todo agente que mensajea.
3. Concurrencia: `flock` en cada escritura de `.swarm/`, `run-id` uuid, manifest per-agente append-only, `memory-orchestrator` único por run.
4. Buzones (`mailbox/<agente>.md`) para peer-to-peer y para hojas lanzadas tarde; router escribe al buzón si el destinatario no está en roster.
5. Staleness pasa de conteo de commits a tree-state hash (`HEAD` + `git status --porcelain` + mtimes).
6. Contrato de evidencia formalizado (línea `evidence: files=N cmds=M turns=k/max` obligatoria) + hook de validación con reintento y `BLOCKED maxTurns`.
7. Bootstrap: `/swarm:init` + backends health-gated (`files` requerido, resto best-effort).
8. Tiers de run (`direct`/`light`/`full`) con clasificación de la raíz y construcción de pack lazy.
9. Ciclo de vida de hallazgos: clave `agente+tag+file:línea` con sha, resolución automática, GC de `run/` y `findings/`.
10. Visibilidad: `/swarm:status`, `/swarm:findings`, `summary.md` por run, warnings de pack/backend surfaced.
11. Worktrees: hojas aisladas reciben la ruta absoluta del `.swarm/` del repo principal.
12. Detección de stack como tabla de precedencia; sin match → `generic` + warning.
13. Modo adhoc para hojas invocadas sin `run-id`.
14. Nuevo dominio `discovery-orchestrator` (fase 2) con 4 hojas; batch único de preguntas presentado por la raíz vía `AskUserQuestion`.
15. Columna `rol` en el roster + tabla "modelo por tier" (§7.0).

## 18. Changelog v2→v2.1
1. Nuevo dominio `requirements-orchestrator` (haiku) con `env-checker`, `dependency-auditor`, `dependency-installer`; contrato `requirements.json` en plugin y en cada pack; comando `/swarm:doctor`; fase 1b.
2. Portabilidad macOS: lock atómico `mkdir` en lugar de `flock`; hooks en `python3` stdlib (sin `jq` obligatorio; `jq` opcional declarado en `requirements.json`).
