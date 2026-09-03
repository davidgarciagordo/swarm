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
