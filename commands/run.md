---
description: Lanza el orquestador raíz del enjambre swarm sobre un objetivo, con tier opcional.
argument-hint: <objetivo> [--tier=direct|light|full]
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

Invoca al agente `swarm:orchestrator` con el objetivo tal cual lo escribió el usuario:

$ARGUMENTS

Pásale el argumento completo sin reinterpretarlo — el propio `orchestrator` extrae el flag
`--tier=` si está presente y clasifica el resto como el objetivo.
