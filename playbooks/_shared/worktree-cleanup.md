# _shared · worktree cleanup
On demand from agents/discovery-orchestrator.md (via its spiker-cleanup playbook) and agents/implementation-orchestrator.md — trigger: a cleanup command (`git worktree remove` / `git branch -D`) is denied or fails; implementation-orchestrator comes here directly, discovery-orchestrator via its spiker-cleanup playbook.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Why the parent cleans up

- A child with `isolation: worktree` gets `.claude/worktrees/agent-<agentId>` plus branch
  `worktree-agent-<agentId>` from the platform. The platform only auto-cleans the worktree of a
  subagent that changed NOTHING; a child that wrote anything leaves an orphan in `git worktree list`.
- The child cannot clean itself: it runs INSIDE the worktree and has no `git worktree`/`git branch`
  in its allowlist. The parent that launched it (and holds its `agentId`) does it.
- `agentId` comes ONLY from the spawn result (`agentId: <id>` line). Never deduce or invent it. No
  `agentId` (launch failed) ⇒ no path, no branch: skip the cleanup, no warn.

## The two commands (each in its OWN call, never chained with `&&`)

1. Remove the worktree directory. `--force` is mandatory: the worktree holds uncommitted/untracked
   files and `git` refuses without it (`contains modified or untracked files`):
   `git worktree remove <worktree-path> --force`
2. Delete the branch — `git worktree remove` only deletes the directory, never the branch; without
   this step it stays orphaned in `git branch` forever:
   `git branch -D worktree-agent-<agentId>`
   `hooks/bash-guard.py` accepts ONLY this exact form: one branch, uppercase `-D`, the
   `worktree-agent-` prefix. Any other branch (`master`/`main` included), lowercase `-d`, bare
   `git branch` or several branches are denied. Substitute the REAL `agentId` (a placeholder left
   literal is denied too).

## Soft failure (both commands)

If a command fails for any reason (already gone, race, worktree locked): do NOT retry, do NOT
change your verdict, do NOT block the merge/batch. Add ONE `- warn:` line with the reason in ≤8
words (the `- warn:` prefix is exempt in `hooks/validate-output.py`) and continue. The exact warn
text is defined by the calling agent.

## Timing

Attempt the cleanup right BEFORE returning the verdict — never after, never conditional on success.
