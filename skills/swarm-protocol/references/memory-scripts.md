# swarm-protocol · memory scripts
On demand from skills/swarm-protocol/SKILL.md — trigger: you need a memory-script call other than `write finding`, a memory script exits non-zero, or `hooks/validate-output.py` rejects your stop.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 4.1 Invocation cheat-sheet (paths from `<plugin-root>`)

> For agents WITHOUT `isolation: worktree`; with it, see protocol §3 — never write directly,
> everything goes through `memory-orchestrator`.

`<run>` is the uuid from your header (or the text `adhoc`), substituted LITERALLY — never `$RUN`.
One line per command: `bash-guard` bans `\` and newlines anywhere, so a line continuation is denied (protocol §3).

```bash
# backend files health (before any write, if in doubt)
"<plugin-root>/scripts/mem-files.sh" health

# write a finding (auto dedup by [key:agent|tag|file:line])
"<plugin-root>/scripts/mem-files.sh" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 42 --run "<run>" --text "class without interface" --fix "extract interface"

# write a decision (append to decisions.md)
"<plugin-root>/scripts/mem-files.sh" write decision --text "use the standard tier for execution"

# leave a message in another agent's mailbox (even if not launched yet)
"<plugin-root>/scripts/mem-files.sh" write mailbox --to security-auditor --from architecture-auditor --run "<run>" --text "review src/App/Foo.php:42 — no interface, may affect tenant isolation"

# query findings/decisions/pack (capped at 20 results)
"<plugin-root>/scripts/mem-files.sh" query "tenant" --scope findings

# check whether the context-pack is fresh before rebuilding (memory-builder only)
"<plugin-root>/scripts/mem-stale.sh" check

# run manifest (root / memory-orchestrator only)
"<plugin-root>/scripts/mem-manifest.sh" register --run "<run-id>" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator
```

Every `mem-files.sh write ...` and `mem-manifest.sh register|summary|gc` acquires and releases the lock
internally (`scripts/mem-lock.sh`) — never call it yourself unless you write a new script that touches
`.swarm/` outside these two.

### 4.2 Exact signatures and outputs (verified against the committed scripts)

`SWARM_ROOT` defaults to `$PWD/.swarm` in all three scripts; if your cwd isn't the repo root, pass it as a
prefix (`SWARM_ROOT=/absolute/path/.swarm "<plugin-root>/scripts/mem-files.sh" …`), the only form the
guard allows — `export` as a standalone command is denied (protocol §3).

| command | exact signature | output / exit |
|---|---|---|
| `mem-files.sh health` | `health` | `ok` + exit 0; exit 1 if `SWARM_ROOT` doesn't exist or isn't writable |
| `mem-files.sh write finding` | `--agent --tag --file --line --run --text --fix` (all 7 mandatory) | `written` or `dup` (an entry `[status:open]` with the same key already existed); exit 64 if an arg is missing |
| `mem-files.sh write decision` | `--text` | `written` |
| `mem-files.sh write mailbox` | `--to --from --run --text` | `written` (appends to `run/<run>/mailbox/<to>.md`) |
| `mem-files.sh query` | `query <regex> [--scope findings\|decisions\|pack\|all]` (default `all`) | `grep -rEn` (extended regex, with `file:line`), max 20 lines |
| `mem-stale.sh check` | `check` | `fresh: …` exit 0 · `stale: …` exit 1 · `no pack-index: …` exit 2 |
| `mem-stale.sh hash` \| `seal` | no flags | 40-char hash · `sealed: <hash>` (writes `tree-hash:`/`sealed:` in `index.md`) |
| `mem-manifest.sh open` | `open --tier light\|full` (**root only**) | prints the new `run-id`, creates `run/<id>/{agents,mailbox,retries}` + `run.json` and points `run/current` |
| `mem-manifest.sh register` | `--run --agent --domain --area --owner` (all 5 mandatory) | `registered` (writes `run/<run>/agents/<agent>.json`) |
| `mem-manifest.sh summary` | `--run --line` | `written` (appends to `run/<run>/summary.md`) |
| `mem-manifest.sh current` | no flags | the run-id from `run/current`, or exit 1 if none |
| `mem-manifest.sh gc` | `gc [--keep N]` (default 10) | `gc: kept newest N run(s)`; never deletes `adhoc` nor the run pointed to by `run/current` |

### 4.3 What the hook literally checks (`hooks/validate-output.py`)

- Applies only to `agent_type` starting with `swarm:`; everything else passes untouched.
- Line 1 against `^(OK|KO .+|DONE|BLOCKED .+)$` — `KO` and `BLOCKED` **require** a reason after them.
- Line 2 against `evidence:` + `files=` `cmds=` `turns=k/max`, tolerant of spaces; the regex anchors the
  end of the line (`\s*$`): nothing after the `turns` value.
- From line 3 onward: any empty line is accepted, any line starting with `- `, and any line with finding
  format. A line that doesn't match and is also over 120 characters is rejected as narration.
- `turns=k/max` with `k == max` does NOT block: the hook emits a `maxTurns` `systemMessage` and accepts.
- A rejection is retried exactly once per agent + reason (`run/<run>/retries/`); a second rejection for the
  SAME reason is accepted as `BLOCKED`. Failing twice wastes a turn — get the format right the first time.
- The most common rejection is a sentence before the verdict ("Done, ", "The result is ") or loose prose
  after a finding: the final turn is a value a script parses, not an explanation to a human.
