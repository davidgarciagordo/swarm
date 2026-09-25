# Changelog

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
