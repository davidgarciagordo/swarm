---
description: "/swarm:run — punto de entrada único del enjambre: describe lo que quieres en lenguaje natural, sin pasos previos."
argument-hint: "<objetivo>"
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

SIEMPRE invoca el tool `Agent` con `subagent_type: swarm:orchestrator` y `prompt` igual a lo que
escribió el usuario, EXACTAMENTE así, sin excepción — incluso si `$ARGUMENTS` está vacío o es solo
espacios. Nunca respondas tú mismo, nunca pidas aclaración antes de invocar: el propio
`orchestrator` decide si el objetivo es válido (incluida la guarda de objetivo vacío) y devuelve su
propio veredicto. Pásale el argumento completo sin reinterpretarlo — el propio `orchestrator`
extrae el flag `--tier=` si está presente y clasifica el resto como el objetivo.

Argumento del usuario:

$ARGUMENTS
