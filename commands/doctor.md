---
description: Verifica los requisitos de entorno del repo (OS/proyecto) contra requirements.json — health-gate de dependencias del enjambre.
allowed-tools: Agent, Read, Bash, SendMessage
---

SIEMPRE invoca el tool `Agent` con `subagent_type: swarm:requirements-orchestrator`, `name:
"requirements-orchestrator"` y el siguiente `prompt`, EXACTAMENTE así, sin excepción — nunca
respondas tú mismo, nunca pidas aclaración antes de invocar: el propio
`requirements-orchestrator` decide si los requisitos están satisfechos y devuelve su propio
veredicto.

```
operation: check
```

`/swarm:doctor` no toma argumentos: cualquier texto que el usuario añada tras el comando se
ignora (el chequeo de requisitos no tiene parámetros). Como no viene de un run abierto por la
raíz, `requirements-orchestrator` se lanza sin `run-id:` en la cabecera — él mismo lo detecta y
opera en modo adhoc (protocolo §2), igual que cualquier hoja invocada suelta.
