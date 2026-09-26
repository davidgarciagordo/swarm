# handoff-writer · template
On demand from agents/handoff-writer.md — trigger: BEFORE writing the handoff file.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## What you write

With `Write` (never via shell — long, structured content), these sections in this order (the form established in `docs/superpowers/handoffs/`):

```
# Handoff — <repo> · <YYYY-MM-DD> · run <run-id>

## Copy-paste prompt for the new session

> <one or two lines: "read this file and continue from here" + what to do now>

## Where everything is

- Branch: <current branch> · tree: <clean | N uncommitted files>
- Last commits:
  - <hash> <subject>
  - …
- Delivery: <your header's `context:`, verbatim>
- Run summary: <summary.md's lines, if it existed>

## Next step

- <what's left open, in the imperative: the unmerged PR, the unconfigured remote,
  the approval the owner didn't give, or "nothing pending">
```

Content rules:
- **Only facts you've verified in this run.** No invented backlog, priorities or lessons that don't come from `context:`, `summary.md` or your commands. A handoff with invented information is worse than none.
- Commit subjects and `context:` go verbatim. A literal `git`/`gh` stderr is copied **in full** (ruling 14): trimming it destroys its only value.
- `context:` carries a `BLOCKED` → "Next step" is exactly that `BLOCKED`'s hint.
- `context:` carries a `- next: …` line (`operation: configure-remote`: remote configured, delivery pending) → "Next step" is that line, verbatim.
