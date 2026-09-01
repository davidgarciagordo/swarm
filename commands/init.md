---
description: Inicializa .swarm/ en este repo (memoria, gitignore, health-gate del backend files).
allowed-tools: Bash
---

Ejecuta `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh` y reporta su salida al usuario tal cual — no
reformatees ni resumas, ya es un resumen en texto plano. Si el script termina con código distinto
de 0, informa que `/swarm:init` abortó y muestra el motivo (línea de stderr del health check).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh"
```
