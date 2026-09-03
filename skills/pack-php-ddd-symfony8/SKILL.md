---
name: pack-php-ddd-symfony8
description: Stack pack for PHP + DDD + Symfony 8 repositories — detection marker, canonical tool commands, layering and naming conventions, untouchable boundaries, and in-use precedents. Read by swarm leaves when .swarm/context-pack.md declares stack php-ddd-symfony8.
---

# pack-php-ddd-symfony8

Primer stack pack del plugin `swarm` (spec §8, §8.1 fila 1). **No se invoca: se LEE.** El
orquestador de dominio resuelve la ruta absoluta de este directorio y la pasa como línea de
cabecera `pack: <ruta>` en el prompt de la hoja; la hoja hace `Read` de los ficheros que necesita
(spec §3.1 — nunca se muta frontmatter en runtime, nunca se precarga como skill).

## Detección

| marcador | condición exacta | resultado |
|---|---|---|
| `composer.json` | existe en la raíz del repo **y** contiene una referencia a `symfony/` en CUALQUIER parte del fichero (no solo dentro de `require`) | `stack: php-ddd-symfony8` |

Es exactamente lo que ya implementa `scripts/mem-scan.sh` (un `grep -q "symfony/"` sobre el
fichero entero, sin acotarlo a ninguna sección) y lo que `memory-builder` escribe como línea
`stack:` en `.swarm/context-pack.md`. Sin ese marcador, el stack es `generic` y ninguna hoja
recibe la línea `pack:` — cada una cae en su modo genérico documentado.

## Qué contiene

| fichero | para quién | contenido |
|---|---|---|
| `commands.md` | `quality-fixer`, `test-writer`, `implementer`, `migration-engineer`, `vulnerability-scanner`, `dependency-auditor` | forma canónica de cada comando determinista, con su condición de detección y su ejecutor |
| `conventions.md` | `implementer`, `test-writer`, `migration-engineer`, `data-model-auditor`, `doc-writer` | capas, layout de directorios, naming, estilo, extensiones de PHP esperadas |
| `boundaries.md` | TODA hoja que escriba, más `data-model-auditor` (read-only) | qué NO se toca nunca |
| `precedents.md` | `doc-writer` | patrones ya en uso que se reutilizan antes de introducir uno nuevo |
| `requirements.json` | `requirements-orchestrator` → `env-checker` | requisitos de OS/proyecto/librerías que este stack añade a los del plugin |

**Dos patrones de consumo distintos** (no confundirlos): `data-model-auditor`,
`vulnerability-scanner`, `dependency-auditor`, `quality-fixer`, `test-writer`, `implementer`,
`migration-engineer`, `doc-writer` reciben la ruta ya resuelta del pack como línea `pack:` de su
propia cabecera de lanzamiento (el orquestador de dominio la inyecta) y hacen `Read` directo de
los ficheros que necesitan. `pattern-advisor`/`domain-modeler` NO reciben ninguna línea `pack:` —
solo honran el `stack:` que ya viene declarado en `.swarm/context-pack.md` (spec §8), sin resolver
ni leer ningún fichero del pack directamente.

## Regla de precedencia

Lo que diga este pack GANA sobre el conocimiento genérico de la hoja, y las entradas de su
`requirements.json` ganan sobre las homónimas del `requirements.json` del plugin (spec §7:
misma clave de identidad → gana el pack). Lo que el pack NO cubre, la hoja lo resuelve con su
criterio genérico — un pack incompleto nunca bloquea, solo deja de aportar.
