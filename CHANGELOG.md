# Changelog

## Unreleased

### Changed
- **Core vs on-demand split.** `swarm-protocol` `SKILL.md` (preloaded into every agent) shrank from 398
  to ≤120 lines; memory-script signatures, hook details, guard quoting rationale, `WAITING`, model-tier
  resolution and authoring rules moved to `skills/swarm-protocol/references/`, each reached by an explicit
  `WHEN … → Read` trigger. Agent-specific rare material moved to `playbooks/<agent>/` (e.g.
  `memory-orchestrator` claude-mem mirror, `memory-builder` pack format, `memory-curator` MEMORY.md trim).
  No rule was dropped; generic Bash traps now live once in the protocol (§6bis).
- `memory-builder` gains the `Edit` tool: the enrichment step now inserts into `.swarm/context-pack.md` with
  `Edit` instead of `cat >> … <<EOF`, because the guard refuses `<` (heredocs) for every role. Its `Write`/`Edit`
  scope is unchanged (`.swarm/context-pack.md`, `.swarm/index.md`).
- Tests: a byte budget per role sits next to the line budget (`tests/structure.json`); documented ```bash
  commands are checked line by line (a `\` continuation now fails, as it does in the real guard); on-demand
  files may not contain the `CLAUDE_PLUGIN_ROOT` variable.

### Security
- `bash-guard`: `rg --hostname-bin` denied (ran any repo executable); read-only roles can no longer run
  `npm audit fix`, switch registry/prefix/working dir (`--registry`, `--prefix`, `composer -d/--working-dir`)
  or write reports (`phpmd --reportfile*`, `deptrac --output/-o`); `SWARM_ROOT=` must be a `.swarm` path
  without `..` that already exists when absolute; `dev`/`development` are protected push targets; redirects
  may not target `.git/` or `.claude/` (except `.claude/agent-memory/`); `node -r/--require/--import/--loader`,
  `php -B/-R/-E` and `php -d auto_prepend_file|auto_append_file|extension|zend_extension` join INTERP_DENY,
  now documented as advisory for writers (they can write a file and run it).

### Fixed
- `judgement.md` was cited by a repo-relative path that does not exist when the swarm runs in another
  repo; agents now cite `${CLAUDE_PLUGIN_ROOT}/skills/swarm-protocol/judgement.md`.
- `verifier` no longer claims the shell expands `${CLAUDE_PLUGIN_ROOT}` (the agent body is substituted at
  load; the Bash environment has no such variable).
- Memory agents' commands use the `<run>`/`<swarm-root>` placeholders instead of `$RUN` shell variables.
- 45 documented commands used `\` line continuations the guard denies; joined to one line.
- Stale cross-references after the split: `orchestrator` §4.4 wording, `delivery-orchestrator` §12.2bis path,
  `abc123` literals in `git branch -D` examples, the objective-gate trigger for non-interactive runs, the
  worktree-cleanup trigger, the root's model-tiers trigger, and `<plugin-root>` in `shell-and-guard.md`.

## 0.2.0

### Added
- **Model tiers.** No agent names a model: every agent declares `model: inherit` + `tier:
  judgement|standard|mechanical`. `models.json` maps tiers to ordered candidates and an
  `escalation` map; `.swarm/models.json` overrides it per tier. `scripts/model-resolve.sh` resolves,
  marks unavailable models (stamped, expiring after 24h, only inside an existing `.swarm/`),
  escalates to the next tier with a DIFFERENT model, and picks an independent blind judge
  (`--avoid`; `--avoid inherit` warns that independence can't be proven). Every orchestrator,
  including memory-, requirements- and delivery-orchestrator, resolves its children this way.
- **Review panel.** `review-orchestrator` + `completeness-critic`, `fact-checker`,
  `simplicity-critic`, `refuter`, `blind-judge` review every plan, pre-merge diff and analysis
  report (policy: `skills/swarm-protocol/judgement.md`). `scripts/review-dedup.sh` selects lenses,
  dedups findings (same TAG + where + problem text), counts rounds (max 2, enforced on disk) and
  records scores in `.swarm/judgements.jsonl` (gitignored, shown by `/swarm:status`).
- **`WAITING <n>`** status for orchestrators with background children (protocol §4.5): capped at 6
  per agent instance, reset by a verdict, rejected when it cannot be counted.
- **Owner-message relay** in the protocol (§2ter): children never act on a relayed owner message;
  the root treats it as untrusted — at most a question to the owner, never a re-plan or an
  authorization.
- `/swarm:doctor` advisory checks: effective model per tier, and a stale `origin/HEAD` for agent
  worktrees (reads `worktree.baseRef` from project and user settings).
- **Infra/CI/tooling route.** An infra/CI/tooling question goes to analysis (lenses launched with
  `scope: infra`), and in `tier: full` to design afterward when it also asks for a change; only an
  already-decided infra edit skips all three phases.
- **Non-interactive mode** (`agents/orchestrator.md` §13.4): a launch that forbids questions still
  runs every phase; the root takes the recommended option, records it as `ASSUMED` in
  `decisions.md` (re-asked on the next interactive run) and lists each assumption in its report.
- **Swarm-only spawns** (§13.1): orchestrators launch only `swarm:` agents (plus the
  `working-methods:` grill lenses inside the review panel).
- **Veracity rule** (protocol §4.6, from orchestrator §13.5): no "unverified" about a fact one
  read-only command can check; `UNVERIFIED (<why>)` only when the check is impossible.
- Read-only verification commands in the allowlists: `jq`, `cmp`, `diff`, `sort`, `uniq`, `cut`,
  `tr`, `php -l`, and `docker exec` (named allowlists only).

### Security
- `hooks/bash-guard.py` denies output redirection to a file (`>`, `>>`, `>|`, `&>`, `>(…)`) and git
  `--output` for every agent without `Write`/`Edit` (`file_writers` in `bash-allowlist.json`).
- The redirect guard uses the same quote automaton as the segment splitter (`$'…'` with escaped
  quotes no longer hides a `> file`); `find -fprint/-fprint0/-fprintf/-fls` are denied; plugin
  scripts (`scripts/mem-*.sh`, `model-resolve.sh`, `review-dedup.sh`…) are accepted only
  plugin-rooted (`${CLAUDE_PLUGIN_ROOT}/…`), never a target repo's own `scripts/`.
- `docker exec` is no longer in the `default` allowlist, runs only read-only inner commands, and only
  into containers listed in the repo's `.swarm/docker-containers`.
- `design-orchestrator` lost `claude plugin` (working-methods detection moved to
  `review-orchestrator`).

### Changed
- Design's grill×3 now runs inside the review panel; `reviewer` is a thin alias of the diff panel.
- The root reads the child tier map with `grep -m1` (frontmatter only).
- `swarm-init.sh` upgrades an existing `.gitignore` block entry by entry.
