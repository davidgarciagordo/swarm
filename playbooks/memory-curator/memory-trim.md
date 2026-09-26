# memory-curator · MEMORY.md trim
On demand from agents/memory-curator.md — trigger: step 4 `find` returned ≥1 `MEMORY.md` over 25KB.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### Step 4 — MEMORY.md trimming (>25KB)

For EACH file the `find` returned:

1. Locate the sections and the cut point:
   ```bash
   wc -c .claude/agent-memory/<agent>/MEMORY.md
   grep -n '^## ' .claude/agent-memory/<agent>/MEMORY.md
   ```
   Sections are written in arrival order: the ones at the TOP are the oldest. Choose the cut on the
   line right BEFORE a `## ` such that what remains drops below 25KB, moving the minimum necessary
   (top to bottom, not the whole file).

2. Archive the oldest block into the sibling `MEMORY-archive.md` (the `>>` creates it if it doesn't
   exist and preserves what was archived in earlier passes):
   ```bash
   head -n <cut-line> .claude/agent-memory/<agent>/MEMORY.md >> .claude/agent-memory/<agent>/MEMORY-archive.md
   ```

3. Remove that same block from `MEMORY.md` with `Edit` (surgical trim: `Read` the header range and
   an `Edit` that replaces exactly the archived block with nothing). Don't rewrite the whole file or
   reorder what remains.

4. Verify the trim dropped below the threshold:
   ```bash
   wc -c .claude/agent-memory/<agent>/MEMORY.md
   ```

Order matters: archive BEFORE deleting. If `head` fails, don't touch `MEMORY.md` — losing an agent's
memory is worse than leaving it large for one more run.

