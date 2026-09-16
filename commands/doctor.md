---
description: Verifies the repo's environment requirements (OS/project) against requirements.json — health-gate for swarm dependencies.
allowed-tools: Agent, Read, Bash, SendMessage
---

ALWAYS invoke the `Agent` tool with `subagent_type: swarm:requirements-orchestrator`, `name:
"requirements-orchestrator"` and the following `prompt`, EXACTLY as written, no exceptions — never
answer yourself, never ask for clarification before invoking: `requirements-orchestrator` itself
decides whether the requirements are satisfied and returns its own verdict.

```
operation: check
```

`/swarm:doctor` takes no arguments: any text the user adds after the command is ignored (the
requirements check has no parameters). Since it doesn't come from a run opened by the root,
`requirements-orchestrator` is launched without `run-id:` in the header — it detects this itself
and operates in adhoc mode (protocol §2), just like any leaf invoked standalone.

The check that `/swarm:doctor` triggers now includes, in addition to the plugin's own
`requirements.json`, that of the active stack pack if `.swarm/context-pack.md` declares one — the
merge is done by `scripts/req-check.sh --pack` and decided by `requirements-orchestrator` (agents/
requirements-orchestrator.md, "requirements.json Merge"), not by this command. `/swarm:doctor`
**never installs anything**: it has no `AskUserQuestion` in its `allowed-tools`, so it cannot
obtain the approval that `dependency-installer` requires; an installation is always requested via
`/swarm:run` (root, `agents/orchestrator.md` §11).
