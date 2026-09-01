# Grill Context Pack
## Target artifact
```
docs/superpowers/specs/2026-09-01-swarm-design.md
```

### Content
# Swarm — enjambre de agentes Claude Code para el ciclo de desarrollo

Fecha: 2026-09-01 · Estado: borrador para revisión del owner · Plugin: `swarm`

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
├─ memory-orchestrator (haiku)      → memory-builder · memory-curator · backends
├─ analysis-orchestrator (sonnet)   → opportunity-analyst · architecture-auditor · security-auditor
│                                     · vulnerability-scanner · performance-analyst · data-model-auditor
├─ design-orchestrator (sonnet)     → planner · pattern-advisor · domain-modeler · grill×3 (externos)
├─ implementation-orchestrator (sonnet) → implementer · test-writer · migration-engineer
│                                     · quality-fixer · reviewer · doc-writer
└─ delivery-orchestrator (haiku)    → release-manager · handoff-writer
```

### 3.1 Restricciones de plataforma (docs oficiales, verificadas 2026-09-01)
- Subagente puede lanzar subagentes, solo en foreground. Subagente background no lanza hijos background.
  → Orquestadores de dominio corren foreground y lanzan hojas en paralelo dentro de un mismo turno.
- Subagentes **nombrados** reciben roster de hermanos y se mensajean con `SendMessage(to:"nombre")`.
  Roster se fija al spawn: hojas de una misma tanda deben lanzarse en el mismo mensaje.
- Agent Teams (buzón + task list compartida) es experimental (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`):
  **fuera del diseño base**; modo opcional futuro.
- Pipelines fijos y grandes (≥5 agentes) se expresan como Workflow script (determinista) cuando el
  usuario lo ha habilitado; si no, los orquesta el orquestador de dominio.
- Precedencia de agentes: proyecto > usuario > plugin. Nombres del plugin: `swarm:<agente>`.

### 3.2 Reglas de la jerarquía
1. Raíz habla solo con orquestadores de dominio; nunca con hojas.
2. Un dominio no habla con otro dominio: cruces vía raíz o vía memoria.
3. Excepción: **peer-to-peer de descubrimiento** entre hojas (§5).
4. Orquestador de dominio: contrato único — entrada `(objetivo, run-id)`, salida `(veredicto ≤10 líneas,
   rutas a findings)`. Nunca ejecuta trabajo de hoja.
5. Añadir hoja = fichero de agente + línea en el roster del orquestador de dominio. Raíz no cambia.
6. Añadir dominio = nuevo `<x>-orchestrator` + línea en el roster de la raíz.

## 4. Subsistema de memoria

### 4.1 Layout en el repo target
```
.swarm/
  memory.json          backends + política (commiteado)
  decisions.md         decisiones con fecha/PR (commiteado)
  context-pack.md      mapa repo fichero:línea, stack detectado, convenciones, entrypoints (gitignored)
  index.md             inventario + sello de validez por artefacto (gitignored)
  findings/<agente>.md hallazgos completos por agente (gitignored)
  run/<run-id>/manifest.json   agentes activos, áreas, dueños (gitignored)
```

### 4.2 Agentes
| agente | modelo | tools | responsabilidad |
|---|---|---|---|
| `memory-orchestrator` | haiku | Read, Grep, Bash(scripts/mem-*), MCP claude-mem | única puerta: `query|write|build|curate`; lee `memory.json`, despacha a backends por política, fusiona y devuelve ≤5 líneas con fuente; dedup en escritura |
| `memory-builder` | sonnet | Read, Grep, Glob, Bash(ro), Write(.swarm/) | construye/refresca `context-pack.md` + `index.md`; detecta stack; consulta backend histórico al construir |
| `memory-curator` | haiku | Read, Edit, Bash(scripts/mem-*) | compacta findings, poda decisions, controla tamaños (MEMORY.md ≤25KB), marca staleness |

### 4.3 Backends (adaptadores, no agentes)
Contrato: `query <texto>` · `write <tipo> <payload>` · `health`. Implementación = script o MCP.

| backend | tipo | por defecto |
|---|---|---|
| `files` | script `scripts/mem-files.sh` sobre `.swarm/` | sí |
| `claude-mem` | MCP `memory_search` / `get_observations` / `observation_add` | histórico cross-sesión |
| `agent-memory` | nativo `memory: project` por agente (MEMORY.md autoinyectado) | sí, por agente |
| `custom` | cualquier script/MCP declarado en `memory.json` | no |

`memory.json` (ejemplo):
```json
{
  "backends": [
    { "name": "files", "type": "files", "root": ".swarm", "default": true },
    { "name": "claude-mem", "type": "mcp", "server": "plugin_claude-mem_mcp-search", "scope": "historical" }
  ],
  "policy": {
    "read": ["files", "claude-mem"],
    "write": ["files", "claude-mem"],
    "stale_after_commits": 5
  }
}
```

### 4.4 Flujo
1. Raíz abre run → `memory-orchestrator build` → builder solo si pack ausente o stale (`git diff --stat`
   desde sello de `index.md` supera `stale_after_commits` o toca rutas del pack).
2. Hoja necesita contexto → lee `context-pack.md` directamente (prefijo estable → prompt-cache).
3. Solo si el pack no responde → `SendMessage(memory-orchestrator, "query: …")`.
4. Toda escritura de hallazgo/decisión pasa por `memory-orchestrator write` (dedup, ruta única).
5. Cierre de run → `curate` + `observation_add` en histórico.

## 5. Protocolo de comunicación
- Al lanzar una tanda, el orquestador escribe `run/<id>/manifest.json`: `{agente, dominio, área, dueño}`.
- Hoja descubre algo fuera de su área → (a) `write` vía memoria, (b) `SendMessage` directo al dueño del
  área según manifest. Mensaje ≤10 líneas, formato de hallazgo (§6).
- Continuación de trabajo = `SendMessage` al agente vivo (conserva contexto), no relanzar.
- Riesgo a validar en smoke test: visibilidad mutua de hermanos lanzados en la misma tanda. Mitigación
  si falla: reintento vía `memory-orchestrator` como relay.

## 6. Contrato universal de agente (skill `swarm-protocol`, precargado en todos)
1. Leer `.swarm/context-pack.md` antes de cualquier búsqueda; abrir solo excerpts alrededor de la línea citada.
2. No re-reportar lo que está en `findings/` de otro agente ni en SHARED-FOUND del pack.
3. Salida: línea 1 = veredicto (`OK` | `KO <peor>` | `DONE` | `BLOCKED <motivo>`), luego ≤N líneas
   `TAG · file:línea · problema → fix (≤8 palabras)`. Detalle completo → `findings/<agente>.md`.
4. Tool determinista primero; modelo para residual.
5. Parar por saturación (sin patrón nuevo), `maxTurns` explícito en frontmatter.
6. Frontmatter obligatorio: `name`, `description` (proactiva: "Use when…"), `model`, `tools`, `maxTurns`,
   `memory: project`, `skills: [swarm-protocol]`.

## 7. Roster completo

### Raíz
| agente | modelo | tools | maxTurns | responsabilidad |
|---|---|---|---|---|
| `orchestrator` | opus | Agent, Read, Bash(git ro), SendMessage | 30 | clasifica (trivial → directo, sin enjambre), elige dominios, exige pack, arbitra conflictos entre dominios |

### Análisis (read-only)
| agente | modelo | maxTurns | responsabilidad |
|---|---|---|---|
| `analysis-orchestrator` | sonnet | 20 | elige lentes por objetivo, lanza en paralelo, fusiona |
| `opportunity-analyst` | opus | 15 | deuda, oportunidades producto/arquitectura, quick wins con ROI |
| `architecture-auditor` | opus | 15 | límites/capas/dependencias, acoplamiento, invariantes arquitectónicas |
| `security-auditor` | opus | 15 | authN/authZ, aislamiento de datos (tenant/usuario), OWASP, secretos, criptografía |
| `vulnerability-scanner` | haiku | 10 | ejecuta scanners del pack (deps/CVE/secrets/SAST); modelo solo para residual |
| `performance-analyst` | sonnet | 15 | consultas N+1, índices, cache, colas, hot paths |
| `data-model-auditor` | sonnet | 15 | drift esquema ↔ mapeos ↔ migraciones; integridad referencial |

### Diseño
| agente | modelo | maxTurns | responsabilidad |
|---|---|---|---|
| `design-orchestrator` | sonnet | 20 | spec → grill → plan; arbitra actas |
| `planner` | opus | 20 | plan por fases con fichero:línea, áreas disjuntas, riesgos |
| `pattern-advisor` | opus | 10 | patrón adecuado (GoF/DDD táctico/enterprise/idiomático del pack); cita precedentes del repo; veredicto `reuse <x>` \| `introduce <y> porque…` |
| `domain-modeler` | opus | 15 | agregados, VOs, eventos, invariantes; respeta límites del pack (p. ej. código generado) |
| grill ×3 | externos | — | `working-methods:grill-architect/operator/engineer` — se invocan, no se duplican |

### Implementación
| agente | modelo | maxTurns | responsabilidad |
|---|---|---|---|
| `implementation-orchestrator` | sonnet | 25 | ejecuta plan por tareas; gate review antes de cerrar |
| `implementer` | sonnet | 30 | ejecuta UNA tarea cerrada del plan; `isolation: worktree` |
| `test-writer` | sonnet | 20 | TDD: test primero, factories/mothers del pack |
| `migration-engineer` | sonnet | 15 | migraciones de esquema coherentes con mapeos |
| `quality-fixer` | haiku | 10 | corre lint/format/typecheck `--fix` del pack; parchea residual |
| `reviewer` | opus | 15 | review de diff, severidad-tagged, gate pre-merge |
| `doc-writer` | sonnet | 15 | docs con formato del pack, changelog |

### Entrega
| agente | modelo | maxTurns | responsabilidad |
|---|---|---|---|
| `delivery-orchestrator` | haiku | 10 | secuencia release + handoff |
| `release-manager` | sonnet | 15 | rama, PR, changelog, merge en verde |
| `handoff-writer` | haiku | 8 | handoff MD de relevo de sesión |

Descartes conscientes: `api-designer` (absorbido por planner + pack), `ci-watcher` (hook/loop),
lentes de UI/diseño visual (plugin `design-review` existente).

## 8. Stack packs

`packs/<nombre>/` con contrato fijo (skill cargable):
```
SKILL.md          descripción + detección (ficheros marcadores)
commands.md       lint | fix | typecheck | test | test-one | scan-deps | scan-secrets | sast
conventions.md    estilo, arquitectura, capas, naming
boundaries.md     qué NO tocar (generado, vendor, migraciones aplicadas…)
precedents.md     patrones ya en uso (se rellena desde el pack de memoria)
```
Primer pack: `php-ddd-symfony8` (derivado del estudio de Quantum). `memory-builder` detecta stack por
marcadores → escribe `stack:` en `context-pack.md` → orquestadores añaden el pack a `skills:` de las hojas
que lo necesitan (implementation, data-model-auditor, vulnerability-scanner, doc-writer). Sin pack →
conocimiento genérico.

## 9. Estructura del plugin
```
.claude-plugin/plugin.json
agents/                 un .md por agente (§7)
skills/swarm-protocol/  contrato universal (§6)
packs/php-ddd-symfony8/ primer stack pack
scripts/mem-files.sh    backend files; mem-stale.sh; mem-manifest.sh
hooks/hooks.json        SubagentStop: valida contrato de salida (script, sin modelo)
docs/superpowers/specs/ este spec + planes
tests/                  smoke tests (§11)
```

## 10. Gestión de tokens (mecanismos, no consejos)
- Context-pack como prefijo estable compartido → prompt-cache en tandas paralelas.
- Orquestadores de dominio: sonnet/haiku; solo raíz y juicio en opus.
- `maxTurns` en todos; hojas de análisis `background: true` cuando la raíz no espera.
- Detalle a `findings/`, contexto del orquestador ≤N líneas.
- `memory-curator` mantiene MEMORY.md ≤25KB por agente.
- Hook `SubagentStop` valida formato de salida y rechaza narración.

## 11. Verificación
Smoke tests en `tests/` (repo fixture mínimo):
1. `build` crea `context-pack.md` + `index.md`; segundo `build` sin cambios = no-op.
2. `query` con pack presente responde sin invocar builder.
3. Dos hojas nombradas en la misma tanda se mensajean (SendMessage) — valida riesgo §5.
4. `write` duplicado → una sola entrada en `findings/`.
5. Hook `SubagentStop` rechaza salida sin línea de veredicto.
6. Detección de stack con marcadores del pack `php-ddd-symfony8`.

## 12. Fases de entrega
1. Núcleo: `orchestrator`, subsistema memoria (3 agentes + backends files/claude-mem), `swarm-protocol`, hooks, smoke tests 1-5.
2. Análisis: `analysis-orchestrator` + 6 lentes.
3. Diseño: `design-orchestrator`, `planner`, `pattern-advisor`, `domain-modeler`, integración grill×3.
4. Implementación: 7 agentes + pack `php-ddd-symfony8`.
5. Entrega: 3 agentes. Opcional: modo Agent Teams tras flag.

Cada fase: agente por agente, aprobación del owner, commit por agente.

## 13. Fuera de alcance (v1)
Agent Teams como base; UI/diseño visual; CI externo; más de un stack pack; 3 niveles de jerarquía.


---

## Repo map  (file:line of rules / precedents / invariants)
Anchors always included: CLAUDE.md, README, ADRs, design docs, .claude/settings.json
(+ project extras from FORGE_ANCHOR_GLOBS / .forge/anchors.json).
Domain keywords extracted from artifact: 2026, swarm, design, claude, code, fecha, estado, plugin

  docs/superpowers/specs/2026-09-01-swarm-design.md:1  # Swarm — enjambre de agentes Claude Code para el ciclo de desarrollo
  docs/superpowers/specs/2026-09-01-swarm-design.md:3  Fecha: 2026-09-01 · Estado: borrador para revisión del owner · Plugin: `swarm`
  docs/superpowers/specs/2026-09-01-swarm-design.md:7  Plugin de Claude Code instalable en cualquier repo que aporte un enjambre de agentes con

---

## SHARED-FOUND
<!-- The orchestrator fills this section with findings from the Gate-A before dispatching lenses.
     Lenses must NOT re-report what is already listed here. -->
