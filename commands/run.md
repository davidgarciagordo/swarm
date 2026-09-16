---
description: "/swarm:run — the swarm's single entry point: describe what you want in natural language, no prior steps needed."
argument-hint: "<goal>"
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

ALWAYS invoke the `Agent` tool with `subagent_type: swarm:orchestrator` and `prompt` equal to
exactly what the user wrote, EXACTLY as written, no exceptions — even if `$ARGUMENTS` is empty or
just whitespace. Never answer yourself, never ask for clarification before invoking: the
`orchestrator` itself decides whether the goal is valid (including the empty-goal guard) and
returns its own verdict. Pass it the full argument without reinterpreting it — the `orchestrator`
itself extracts the `--tier=` flag if present and classifies the rest as the goal.

User argument:

$ARGUMENTS
