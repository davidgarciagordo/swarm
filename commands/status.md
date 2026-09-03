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
