---
name: swarm-protocol
description: Universal contract for every agent in the swarm plugin — memory, evidence, mailbox, adhoc/worktree modes.
---

# Swarm protocol

Preloaded (`skills: [swarm-protocol]`) in every agent of the `swarm` plugin. This contract is the
same for root, domain orchestrators and leaves — spec
`docs/superpowers/specs/2026-09-01-swarm-design.md` §5, §6, §9.2, §9.3.

## 1. Before acting

**`$SWARM_ROOT` and `$RUN` in this skill's examples are PLACEHOLDERS, never real shell
variables.** Every call to `Bash` opens a new process: nothing exported in one survives to the
next (`export` isn't in your allowlist either — §6/§4.3). No hook injects them into the
environment. **Substitute LITERALLY** the absolute path of `.swarm/` and the `run-id` (or `adhoc`)
from your launch header (§2) into every command, as text — never `"$SWARM_ROOT/..."` nor
`"${RUN:-adhoc}"` as written, that expands to empty or to `$PWD/.swarm` (the wrong path outside
the repo root) and the script fails with `exit 64` or reads/writes where it shouldn't, almost
always silently (`2>/dev/null` swallows the error). Same rule already followed by
`agents/orchestrator.md` §2.1.

1. **Read memory before searching.** `cat "<swarm-path>/context-pack.md"` (or ask
   `memory-orchestrator` for the pack if it doesn't exist) BEFORE any exploratory `Grep`/`Read`.
   Open only the excerpt around the cited line — never re-read the whole file if the pack already
   gave you `file:line`.
2. **Don't re-report.** If a finding is already in `findings/<other-agent>.md` or in the
   `SHARED-FOUND` section of the pack, don't repeat it — cite it or extend it, never duplicate it.
3. **Read your mailbox on startup.** Before acting, check whether someone left you context:
   ```bash
   cat "<swarm-path>/run/<your-run-id-or-adhoc>/mailbox/<your-name>.md" 2>/dev/null
   ```
   If the file doesn't exist, there are no pending messages — continue normally.
   **Watch the `.swarm/` path**: if your frontmatter has `isolation: worktree`, use the ABSOLUTE
   path given to you in the launch prompt (see §3) — NOT a path relative to your cwd, which
   resolves to the wrong place in a worktree. The `2>/dev/null` above swallows the failure: with
   the wrong path you'd read an empty mailbox believing you have no messages.

## 2. Run mode vs adhoc mode (§9.2)

When an orchestrator launches you, your launch prompt carries this literal header:

```
run-id: <uuid>
swarm-root: <absolute path of .swarm>
operation: <the concrete operation you must run in your turn 1>
tier: <light|full>            (OPTIONAL — only the root writes it when launching a domain orchestrator)
objective: <owner's literal objective>   (only for the domain orchestrator whose own contract declares it mandatory — today `discovery-orchestrator`; every other one, including other domain orchestrators like `requirements-orchestrator`, never receives it)
```

- If it includes `run-id: <uuid>`, you're inside an orchestrated run: substitute that uuid
  LITERALLY (as text, never as a shell variable — §1) in every `--run` of your memory commands.
  `swarm-root:` is the absolute path of the canonical `.swarm/` (substitute it the same way,
  LITERAL — use it as explained in §3 if your cwd isn't the repo root). `operation:` says what you
  must do as soon as you start, using your own contract's vocabulary (for `memory-orchestrator`:
  `query|write|build|curate`) — don't infer it from the rest of the prompt.
- If your prompt does NOT include `run-id:`, you were invoked standalone (adhoc, outside an
  orchestrated run): use the literal text `adhoc` in every `--run`. **Don't** call
  `mem-manifest.sh open` — that command is exclusive to the root when opening a real run. Your
  writes go under `run/adhoc/`. **Don't create directories**: the write scripts (`mem-files.sh
  write …`, `mem-manifest.sh register|summary`) already create the tree they need
  (`findings/`, `run/adhoc/mailbox/`…) on their own, on the first write. Follow the evidence
  contract (§4) with no exception.
- `tier: light|full` (phase 2, spec §7.0): OPTIONAL line the root adds when launching a domain
  orchestrator. Absent ⇒ `full`. An orchestrator uses it to pick the model for its judgment
  leaves when launching them (`light` ⇒ override `model: "sonnet"` in the `Agent` tool for leaves
  whose frontmatter says `opus`); leaves don't receive it and don't need it. Orchestrators may add
  their own lines after the header, always AFTER these.
- `objective: <text>` (phase 2, spec §7): the owner's literal objective, without the `--tier`
  flag. The root ONLY writes it when launching the domain orchestrator whose own contract declares
  it mandatory (today `discovery-orchestrator`, which forwards it verbatim to its leaves and whose
  verdict is `BLOCKED empty objective` if it arrives empty or absent — see
  `agents/discovery-orchestrator.md`). It is NOT a generic obligation for "every domain
  orchestrator": other domains (`memory-orchestrator`, `requirements-orchestrator` — the latter
  launched by `/swarm:doctor`, which takes no objective at all) never receive it and never need it.
- Special case: if you're `implementer` (phase 5a, `agents/implementer.md`) and you're invoked
  without a reference to a concrete plan (missing `plan:` in your header), your verdict is
  `BLOCKED needs plan` — don't improvise a plan.

## 2bis. Stable naming convention (owner decision, 2026-09-02)

Every agent is launched (`Agent(...)`) NAMED — never anonymous — and its name is exactly its role,
with no suffixes or variants: the basename of its type (`memory-orchestrator`, `security-auditor`,
`analysis-orchestrator`…), the same on every run. This is what allows:
- peer agents to send each other `SendMessage(to: "<role>", ...)` at any time (spec §5) knowing
  the name in advance, without having to discover it;
- the owner (human user) to address a specific agent by its role — "tell security-auditor when
  you're done", "ask memory-builder whether it already has the pack" — and have the orchestrator
  that launched it know exactly who to forward the message to.
`memory-orchestrator` is the case already mandatory per spec (§4.5, single instance per run,
always named this way). The same criterion applies to ANY other agent an orchestrator launches, in
any phase — whoever launches it fixes the name = role, it doesn't leave naming to chance.

## 3. Worktree mode (§9.3)

If your frontmatter has `isolation: worktree`, your launch prompt gives you the ABSOLUTE path of
the main repo's `.swarm/` (not the one in your isolated worktree). Rules:
- **Read** that `.swarm/` directly with the given absolute path — never a copy inside the
  worktree, and never assume `$SWARM_ROOT` relative to your cwd points to the right place.
- **Never write there directly.** Every write (`finding`, `decision`, `mailbox`) goes via
  `SendMessage` to `memory-orchestrator`, which holds the canonical path and applies the lock. A
  direct write from the worktree could diverge from the canonical `.swarm/`.

Operational note (the scripts' real behavior): all of them read `SWARM_ROOT` from the environment
and, if it isn't set, fall back to `$PWD/.swarm` — which in a worktree is the WRONG path. That's
why, in worktree mode, always pass the absolute path explicitly on every read, as a prefix to the
command. `hooks/bash-guard.py` recognizes ONE `SWARM_ROOT=<value>` prefix as transparent: it
trims it and validates the rest of the segment with the normal rules (so
`SWARM_ROOT=/abs/.swarm scripts/mem-files.sh health` passes, and `SWARM_ROOT=/abs/.swarm rm -rf /`
is still denied). `export SWARM_ROOT=…` as a standalone command is NOT allowed — use the prefix,
and **on ONE single line, with no `\` continuation**: `bash-guard` splits the command into tokens
with `shlex` before checking the allowlist, and a line continuation becomes a stray `\n` token
that's in no allowlist — the ENTIRE command is denied, including the otherwise-valid prefix:

```bash
SWARM_ROOT=/absolute/path/to/repo/.swarm "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "tenant" --scope findings
```

## 4. Evidence contract (mandatory, spec §6)

Every `swarm:*` agent's output follows this exact format:

```
<line 1: verdict>
evidence: files=N cmds=M turns=k/max
<following lines: findings, optional>
```

**Your LAST message of the turn (the one `hooks/validate-output.py` reads) starts LITERALLY at
the verdict — zero preamble.** Real evidence from a live smoke test (phase 2, 2026-09-02): all
SIX agents in the same run failed their first attempt — four for writing a sentence before the
verdict ("line 1 must be a verdict"), two for leaving loose prose after a finding ("narration
detected"); the hook's retry saved them, but each agent paid a whole extra turn,
systematically, without exception. This isn't a rare case: it's the default habit of writing a
closing message — "Done, ", "I've finished and ", "The result is " — before the keyword. This
turn is NOT an explanation to a human: it's a value a script parses. No preceding sentence, no
closing remark after the last finding. If you need to reason out loud, do it in earlier turns —
the turn that ends the agent is only these lines.

- **Line 1 — verdict**, one of: `OK` · `KO <worst problem>` · `DONE` · `BLOCKED <reason>`.
- **Line 2 — evidence, MANDATORY**: `evidence: files=N cmds=M turns=k/max` where `N` = files
  read, `M` = deterministic commands run, `k/max` = current turn over the frontmatter's
  `maxTurns`. The validation hook is TOLERANT of extra spaces around `=` and after
  `:` (e.g. `evidence:  files=2  cmds=1  turns=3/10` is valid) — but the base format (the
  `files=`, `cmds=`, `turns=.../...` keys) is mandatory. The hook's regex anchors the end of the
  line (`\s*$`): the line must END right after the `turns` value — no text after it
  (no comments, no finding tacked on, no punctuation).
- **`OK` with `files=0` is always rejected** — a green verdict without having read anything isn't
  real evidence.
- **Remaining lines — findings**, one per line, format:
  `TAG · file:line · problem → fix (≤8 words)`. Full detail (long context, snippets)
  goes to `findings/<your-name>.md` via `memory-orchestrator write finding`, NEVER in the
  output the hook reads — any loose prose there is interpreted as narration and rejected.

### 4.1 Invocation cheat-sheet (paths from `${CLAUDE_PLUGIN_ROOT}`)

> These direct invocations are for agents WITHOUT `isolation: worktree`; if your frontmatter has
> it, see §3 — never write directly, everything goes through `memory-orchestrator`.

`<your-run-id-or-adhoc>` is the uuid from your header (or the text `adhoc`), substituted
LITERALLY — never `$RUN` (§1). Line-continuation `\` DOES work here (verified against
`bash-guard.py`) — it's ONLY the `SWARM_ROOT=<value>` prefix from worktree mode (§3) that breaks
with continuation; without that prefix, a normal multi-line call passes the guard fine.

```bash
# backend files health (before any write, if in doubt)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" health

# write a finding (auto dedup by [key:agent|tag|file:line])
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 42 \
  --run "<your-run-id-or-adhoc>" --text "class without interface" --fix "extract interface"

# write a decision (append to decisions.md)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write decision --text "use sonnet for execution"

# leave a message in another agent's mailbox (even if not launched yet)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write mailbox \
  --to security-auditor --from architecture-auditor --run "<your-run-id-or-adhoc>" \
  --text "review src/App/Foo.php:42 — no interface, may affect tenant isolation"

# query findings/decisions/pack (capped at 20 results)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "tenant" --scope findings

# check whether the context-pack is fresh before rebuilding (memory-builder only)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" check

# run manifest (root / memory-orchestrator only)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register \
  --run "<run-id>" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator
```

Every call to `mem-files.sh write ...` and `mem-manifest.sh register|summary|gc` already acquires
and releases the lock internally (`scripts/mem-lock.sh`) — don't call it directly yourself unless
you're writing a new script that touches `.swarm/` outside these two.

### 4.2 Exact signatures and outputs (verified against the committed scripts)

`SWARM_ROOT` defaults to `$PWD/.swarm` in all three scripts; if your cwd isn't the repo root,
pass it as a prefix to the command (`SWARM_ROOT=/absolute/path/.swarm "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" …`),
which is the only form the guard allows — `export` as a standalone command is denied (§3).

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
- Line 1 against `^(OK|KO .+|DONE|BLOCKED .+)$` — `KO` and `BLOCKED` **require** a reason after
  them.
- Line 2 against `evidence:` + `files=` `cmds=` `turns=k/max`, tolerant of spaces.
- From line 3 onward: any empty line is accepted, any line starting with `- `,
  and any line with finding format. A line that doesn't match and is also over 120
  characters is rejected as narration — keep every finding on a short line.
- `turns=k/max` with `k == max` does NOT block: the hook emits a `maxTurns` `systemMessage` and
  accepts.
- A rejection is retried exactly once per agent + reason (`run/<run>/retries/`); on a second
  rejection for the SAME reason it's accepted as `BLOCKED`. There's no infinite loop, but failing
  twice wastes a turn for nothing — get the format right the first time.

### 4.4 Mandatory sanitization of all third-party text (BEFORE building any `--text`/`--fix`/`--line`)

Rule SHARED by every `swarm:*` agent — root, domain orchestrators and leaves. Any text you did not
write yourself literally in your own agent file is UNTRUSTED: the objective the owner typed, the
free text they write in "Other", the question or approach another leaf generated, whatever reached
you via mailbox or `SendMessage`, the output of a command you ran and — the extreme case — whatever
`WebSearch`/`WebFetch` brings back from the public web. That text ends up inside a `--text "…"` (or
a `--fix`, or a `--line`) that runs against a REAL shell.

`hooks/bash-guard.py` **does not protect you here**: its `split_segments` only splits the command
on `&&`, `||`, `;` and `|` **outside** quotes, so a backtick, a `$(...)` or a `$VAR` **inside** the
quotes passes the guard intact and the shell substitutes it before the script ever sees anything. A
question as ordinary as "should we migrate the old parseCSV()?" written with the identifier in
backticks, or a free-text answer containing a `$(...)`, would execute as a command.

That's why, BEFORE interpolating any third-party text into a `--text` (or a `--fix`, or a
`--line`), apply these substitutions literally, in this order:

1. **replace every backtick `` ` `` with a single quote `'`**
2. **delete every `$`** (don't replace it with anything: it just disappears)
3. **replace every double quote `"` with a single quote `'`** — it's REMOVED, never escaped
   as `\"`
4. **delete every backslash `\`** (it disappears; it isn't escaped either)
5. collapse any line break to a single space (a finding, a decision and a summary line are ONE
   line)

**Why they're DELETED and not escaped (steps 3 and 4 are the same bug):** `hooks/bash-guard.py`'s
`split_segments` has NO handling of backslashes at all — its quote state machine sees a `\"` and
considers the quote CLOSED, while the real shell keeps it open. With a `"` escaped as `\"`, any
`|`, `;` or `&&` later in the text (which for the shell is still inside the string) the guard reads
as OUTSIDE quotes: it splits the command there, doesn't recognize the remaining segment and
**DENIES the entire call**. The write is silently lost — it fails closed, yes, but leaves nothing
durable, which is exactly what the evidence contract exists to prevent. And a trailing `\` in the
text would eat the closing quote of the real command. By deleting both characters, what the
guard's parser sees and what the shell sees are exactly the same.

No exceptions and no judgment call on whether "that text looks harmless": if the text isn't a
literal of your own, it gets sanitized. This applies to ANY `--text`/`--fix`/`--line` you build,
and also to the body of a `SendMessage` with which you request a write from `memory-orchestrator`
(it's the one running the shell, with your text inside: you can't delegate the sanitization to it).

## 5. Deterministic tool before model

Before reasoning about a problem, run the pack's deterministic linter/scanner/test (if
applicable) and only treat the residual with model judgment. Never "eyeball" what a `--fix`
can resolve on its own.

## 6. Stop by saturation

Stop exploring when you stop finding new patterns, not when you hit a fixed number of
findings. `maxTurns` from your frontmatter is the hard limit — if you reach it without closing,
your verdict is still `OK`/`DONE`/`KO`/`BLOCKED` with whatever evidence you have; the hook takes
care of noting `maxTurns` if applicable, you don't need to mention it separately.

## 7. Mandatory frontmatter

Every agent in this plugin declares, without exception: `name`, `description` (a "Use when…"
phrase that triggers proactive use), `model`, `tools`, `maxTurns`, `memory: project`,
`skills: [swarm-protocol]`. Never declare `hooks`, `mcpServers` or `permissionMode` in the
frontmatter — they're ignored for plugin subagents (spec §3.1) and their presence only confuses
whoever reads the file.

## 8. Complete output examples

### Example A — `OK` with evidence and findings

```
OK
evidence: files=4 cmds=2 turns=6/15
ARCH · src/App/Foo.php:42 · class without interface → extract interface
ARCH · src/App/Bar.php:10 · domain logic in controller → move to service
```

### Example B — `BLOCKED`

```
BLOCKED needs plan
evidence: files=1 cmds=0 turns=1/30
```
