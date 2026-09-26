# memory-builder · pack format
On demand from agents/memory-builder.md — trigger: step 0 says a rebuild is needed (stale, no pack-index, or fresh but no pack).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## §2 Enrichment (cheap, optional)

If the repo has a `CLAUDE.md` (or rules referenced from it), add ONE `## Conventions` section with
≤15 lines in bullets — actionable rules, not prose or a copy of the file:

`Edit` `.swarm/context-pack.md`: insert it right BEFORE the `## SHARED-FOUND` line (which stays last):

```
## Conventions
- <actionable rule 1>
- <actionable rule 2>
```
No heredoc: the Bash guard refuses `<` for every role.

If your launch prompt carries `hint: …` lines (historical observations `memory-orchestrator` pulled
from claude-mem for you), add them under `## Historical notes` (same `Edit`, before `## SHARED-FOUND`), max 5 lines. You intentionally have no
MCP tools: the only backend access is through the orchestrator. **Don't `SendMessage` it mid-build to
ask for a query**: it's waiting for your `DONE` and you'd deadlock each other. With no hints, omit the
section — it's not a `BLOCKED`.

## §4 index.md (before sealing)

`mem-stale.sh` decides which directories to watch by reading `covers:` from `.swarm/index.md`; if that
line is missing it falls back to `src`, so a repo whose code lives in `app/` or `lib/` would be judged
against the wrong directory. Propagate the scanner's `covers:` BEFORE sealing: `Write` `.swarm/index.md`
with exactly two lines —

```
# index
covers: <the exact list from the pack's covers: line>
```

`seal` keeps the rest of the file and only rewrites `tree-hash:` and `sealed:`.
