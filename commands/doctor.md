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

## Advisory checks (after the verdict — never change it)

When `requirements-orchestrator` returns, run this ONE deterministic command yourself and print
its output verbatim below the verdict (it always exits 0; it is advice, not a gate):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh" --advisory
```

It runs the checks listed in `requirements.json` → `advisory`:
- `models`: the effective model of each tier (`judgement`, `standard`, `mechanical`) as
  `scripts/model-resolve.sh` resolves it from `models.json` or the project override
  `.swarm/models.json`, and a `WARN` for every candidate listed in `.swarm/models.unavailable`.
  An unavailable model is never a failure: the tier falls to its next candidate or to `inherit`.
- `worktree-base`: if `origin/HEAD` is behind `HEAD`, agent worktrees would branch from stale
  code; it prints the snippet to add to `.claude/settings.json`
  (`{ "worktree": { "baseRef": "head" } }`). Show it and let the owner decide — `/swarm:doctor`
  never writes user settings.
