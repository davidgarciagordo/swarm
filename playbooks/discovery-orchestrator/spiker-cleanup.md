# discovery-orchestrator · spiker cleanup
On demand from agents/discovery-orchestrator.md — trigger: `feasibility-spiker` reported `DONE`/`BLOCKED`, or you reached `maxTurns` with it silent while holding its `agentId`.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

Generic mechanics (why `--force`, branch guard shape, soft failure):
`<plugin-root>/playbooks/_shared/worktree-cleanup.md`. The spiker's paths are RELATIVE to your cwd
(the repo root you run in): `.claude/worktrees/agent-<agentId>` and branch `worktree-agent-<agentId>`.

### 1-timeout. Spiker launched (agentId in hand) but never reported (`maxTurns` exhausted)

Same orphan as 1bis by another route (the platform never auto-cleans a worktree with `spike/`
inside). Alongside `- warn: feasibility-spiker no response`, still attempt the deletion, with the
same soft failure as 1bis (one line `- warn: spiker's worktree not deleted: <reason>` if it fails,
never a verdict change):
```bash
git worktree remove .claude/worktrees/agent-<agentId del spawn> --force
```
and, in its OWN call, the orphaned branch (same soft failure, line `- warn: spiker's branch not
deleted: <reason>`), with the REAL agentId:
```bash
git branch -D worktree-agent-<agentId del spawn>
```
If its `agentId` never arrived (launch failed), there's no path or branch: skip it without a warn.

### 1bis. Delete the spiker's worktree as soon as it reports `DONE` or `BLOCKED`

With either verdict its work is finished. This is YOUR responsibility, not the spiker's: it has no
`git worktree` in its allowlist and runs inside the worktree. Safe to delete: the spiker only returns
`DONE` after `memory-orchestrator` confirmed its finding in writing (agents/feasibility-spiker.md,
"Persisting the detail"), so the detail is ALREADY in `.swarm/`; `spike/` is disposable by design.
```bash
git worktree remove .claude/worktrees/agent-<agentId del spawn> --force
```
`--force` is mandatory (uncommitted `spike/`). **Soft failure**: if the deletion fails for whatever
reason (no longer exists, race, locked), do NOT retry, do NOT change your verdict, do NOT block the
merge — note ONE line `- warn: spiker's worktree not deleted: <reason in ≤8 words>` and continue.

Then delete the `worktree-agent-<agentId>` branch too, in its OWN call, same soft failure (line
`- warn: spiker's branch not deleted: <reason in ≤8 words>`):
```bash
git branch -D worktree-agent-<agentId del spawn>
```
If you didn't launch the spiker or its `agentId` never arrived, there's nothing to delete: skip the
step without a warn.
