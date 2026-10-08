# Changelog

## 0.2.5

Second pass over the same real run, this time on plumbing.

### Added
- `scripts/swarm-cost.sh`: per-agent tokens, turns, tool calls and model of a run, read from the
  session transcripts. `/swarm:status` runs it when asked what a run cost.
- `tests/routing/`: routing evals. A real headless `/swarm:run` in a scratch repo, with assertions
  on which agents ran. Opt-in and budget-capped; not part of `tests/run.sh`.

### Changed
- **No agent runs in background.** `research-analyst` and `feasibility-spiker` reported to the main
  session, not to their orchestrator, so someone had to relay their results by hand.
- **The root writes decisions with the script**, not through a message to `memory-orchestrator`:
  no model turn per write, and no message to lose.
- **claude-mem is read-only.** The memory orchestrator called write tools claude-mem does not have,
  so every run closed with a warning. Queries use its `search` tool; `swarm-init` no longer warns
  about an environment variable nothing sets.

### Fixed
- A spike whose finding never reached `.swarm/` left its worktree and branch behind:
  `discovery-orchestrator` now persists the finding from the spiker's verdict before the cleanup.
- `mem-scan.sh` wrote `covers: src` in repos without `src/`; it now lists the top-level directories
  that exist.

## 0.2.4

Found by running the plugin on a real plan-only goal: 18 agents and two panel rounds for one plan,
which the root wrote itself.

### Added
- **Plan route.** A goal whose deliverable is a written plan now pulls `design-orchestrator` with
  `tier: light`: the planner alone plus one panel round (`playbooks/design-orchestrator/light.md`).
  A panel `KO` gets one revision and is reported as not re-judged; a second round is the owner's call.
- `sizing.md`: the root never authors the artifact, and an unattended run pulls discovery only for
  research the plan depends on.
- **Research-only discovery.** A `leaves:` header line makes `discovery-orchestrator` launch only
  `research-analyst` (and `feasibility-spiker` when asked): no question batch, no `value-critic`,
  no `options-generator` (`playbooks/discovery-orchestrator/leaves.md`).

### Changed
- **Round 2 of the panel is a delta review.** Round 1's blocking findings are stored
  (`review-dedup.sh prior`) and handed to every lens: check they are resolved, report new findings
  only where the revision introduced them or they block the objective. Round 2 used to re-review
  from scratch and return a different set of blockers.
- A near-empty repository (5 files or fewer) gets its context pack from `mem-stale.sh stub`; no
  `memory-builder` is launched to describe nothing.

### Fixed
- `/swarm:run` resolves the root's `judgement` tier before launching it; it used to run on the
  default subagent model.
- Memory scripts called from a subdirectory planted a second `.swarm/` there. They now use the
  nearest existing `.swarm/` up to the repository top (`scripts/lib/root.sh`).
- The output hook names the offending line and its length when it rejects narration, so the one
  retry fixes that line instead of guessing.

## 0.2.3

### Removed
- **`reviewer` agent.** The retired alias only returned a `BLOCKED` redirect to
  `review-orchestrator`, yet its description loaded in every session. The pre-merge gate is the
  review panel on `artifact-type: diff`, as before. 44 agents.
- Internal dogfood files (`.forge/grill-context.md`, `.swarm/decisions.md`, `.swarm/memory.json`)
  no longer ship with the plugin; they were gitignored but still tracked.

### Changed
- Docs and playbooks no longer mention the `reviewer` alias or a leftover `v1` tag.

## 0.2.2

### Changed
- **Proportional routing, native first.** A headless `/swarm:run` on a read-only analysis question
  cost 356 s / $4.28 (discovery, lenses, panel, `swarm-init`) vs 144 s / $0.87 for plain Claude.
  Now `/swarm:run` answers questions, "analysis only" goals and small reversible edits natively
  (no subagent), and the root's new §1.1 Step 0 SIZING pulls each swarm component à la carte, only
  when its value beats its cost, logging `- spawn <component>: <why>` and listing `- ran:` /
  `- skipped:`. Detail in `playbooks/orchestrator/sizing.md`. `--tier=direct|light|full` is an
  optional override; `analysis-orchestrator` accepts a `lenses:` header to launch only those.
- **Read-only goals never write.** No `swarm-init`, no `.swarm/`, no edit to a tracked file
  (`.gitignore` included). `swarm-init.sh` touches `.gitignore` only after `.swarm/` is written and
  healthy, and gains `--read-only` (writes nothing, exit 0; unknown argument exits 64).
- **Bash-denied resilience** (protocol §6bis): a Bash call denied by the session's permissions is
  never retried; agents read with `Read`/`Grep`/`Glob` and report `BLOCKED needs Bash: <cmd>` once.
- Root gains `Grep`/`Glob` and `git ls-files` (repo probe). Tests: structural checks for the sizing
  step, the read-only rule, the `--tier` override and the Bash-denied rule; behavioural checks for
  `swarm-init.sh --read-only`.

## 0.2.1

### Changed
- **Always-on cost ~3,581 → ~1,196 tok** per session (`claude plugin details`). Agents spawned only
  by an orchestrator carry a one-line description (what it does; internal, spawned by whom); the
  root `orchestrator` and the `/swarm:*` entry points keep a trigger description. The stack pack is
  read by path and sets `disable-model-invocation`.
- **Commands are skills.** `commands/*.md` → `skills/<name>/SKILL.md`, same `/swarm:init`, `run`,
  `doctor`, `status`, `findings` names; `plugin.json` drops `commands`. `/swarm:init` writes files,
  so it sets `disable-model-invocation`. `tests/test_structure.py` §7 checks command skills vs
  background skills (`user-invocable: false`).
- Low-confidence prompt-audit items, style only: English example plan slugs, example `PLAN` lines
  say phases, no `v1` tag in the install scope note, one default in the planner's revise step.

## 0.2.0

Model tiers, the review panel and a blind judge, the infra/CI route, and hardened hooks — plus a
slim pass that cut what every agent pays on every turn without dropping a rule. See the README's
"Cost" section for the measured before→after numbers.

### Added
- **Model tiers.** No agent names a model: every agent declares `model: inherit` + `tier:
  judgement|standard|mechanical`. `models.json` maps tiers to ordered candidates and an
  `escalation` map; `.swarm/models.json` overrides it per tier. `scripts/model-resolve.sh` resolves,
  marks unavailable models (stamped, expiring after 24h, only inside an existing `.swarm/`),
  escalates to the next tier with a DIFFERENT model, and picks an independent blind judge
  (`--avoid`; `--avoid inherit` warns that independence can't be proven). Every orchestrator,
  including memory-, requirements- and delivery-orchestrator, resolves its children this way.
  Resolve-then-spawn is inline in every orchestrator's own file now — reading the on-demand
  `model-tiers.md` reference is reserved for an actual failure (missing model, escalated retry),
  not spent on every run.
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

### Changed — the slim pass (core vs on-demand, new test philosophy)
- **Core vs on-demand split.** `swarm-protocol` `SKILL.md` (preloaded into every agent) shrank from
  398 to 114 lines; memory-script signatures, hook details, guard quoting rationale, `WAITING`,
  model-tier resolution, worktree mode and authoring rules moved to
  `skills/swarm-protocol/references/` (one new file, `worktree.md`, split out of SKILL.md §3 itself),
  each reached from a core file by an explicit `WHEN <condition> → Read <path>` trigger line — never
  inlined. Agent-specific rare material moved to `playbooks/<agent>/` (e.g. `memory-orchestrator`
  claude-mem mirror, `memory-builder` pack format, `memory-curator` MEMORY.md trim). No rule was
  dropped; generic Bash traps now live once in the protocol (§6bis). **The rule going forward:** new
  rare behaviour (a new error path, a new tool's quirk, a new edge case) is a new or extended
  on-demand file plus one trigger line, never a paragraph added to a core file — enforced mechanically
  by `tests/test_structure.py` (line/byte budgets per role, and an on-demand file with no core file
  pointing at it fails the suite as an orphan).
- **Test philosophy: structural + generative, never wording.** ~60 `test_*.sh` files that asserted a
  literal sentence or a hardcoded scenario were replaced by `tests/test_structure.py` (frontmatter
  schema, the `Agent(...)` spawn graph, line/byte budgets per role, on-demand-trigger wiring,
  allowlist↔agent consistency, commands↔`plugin.json` consistency, `requirements.json` schema, every
  documented verdict through `hooks/validate-output.py`, and every documented ` ```bash ` line —
  agent, playbook, or a stack-pack's `commands.md` row — through the real `hooks/bash-guard.py` for
  the agent that actually runs it) plus `tests/test_guard.py` and
  `tests/test_bash_guard_generative.sh` (seeded fuzzers exercising the guard's properties, backed by
  `tests/fixtures/guard_cases.jsonl`, a regression table captured from the previous guard's suite: a
  rewrite may loosen nothing that table calls DENY). No test asserts a fixed sentence — the suite
  stays green as long as the real structure and behaviour it enforces hold, wording included.
- `memory-builder` gains the `Edit` tool: the enrichment step now inserts into
  `.swarm/context-pack.md` with `Edit` instead of `cat >> … <<EOF`, because the guard refuses `<`
  (heredocs) for every role. Its `Write`/`Edit` scope is unchanged (`.swarm/context-pack.md`,
  `.swarm/index.md`).
- Design's grill×3 now runs inside the review panel; `reviewer` is a thin alias of the diff panel.
- The root reads the child tier map with `grep -m1` (frontmatter only).
- `swarm-init.sh` upgrades an existing `.gitignore` block entry by entry.

### Security — the guard's model: deny-by-default, metacharacters included
- `hooks/bash-guard.py` denies output redirection to a file (`>`, `>>`, `>|`, `&>`, `>(…)`) and git
  `--output` for every agent without `Write`/`Edit` (`file_writers` in `bash-allowlist.json`); a
  read-only role's command is denied outright if it contains ANY shell metacharacter anywhere
  (`| & > ( ) ; $ \` \ { } <`, an unquoted glob, `~`), quoted or not — one command, no chaining, no
  redirection, no `docker exec`.
- The redirect guard uses the same quote automaton as the segment splitter (`$'…'` with escaped
  quotes no longer hides a `> file`); `find -fprint/-fprint0/-fprintf/-fls` are denied; plugin
  scripts (`scripts/mem-*.sh`, `model-resolve.sh`, `review-dedup.sh`…) are accepted only
  plugin-rooted (`${CLAUDE_PLUGIN_ROOT}/…`), never a target repo's own `scripts/`.
- `docker exec` is no longer in the `default` allowlist, runs only read-only inner commands, and only
  into containers listed in the repo's `.swarm/docker-containers`.
- `design-orchestrator` lost `claude plugin` (working-methods detection moved to
  `review-orchestrator`).
- `rg --hostname-bin` denied (ran any repo executable); read-only roles can no longer run `npm audit
  fix`, switch registry/prefix/working dir (`--registry`, `--prefix`, `composer -d/--working-dir`) or
  write reports (`phpmd --reportfile*`, `deptrac --output/-o`); `SWARM_ROOT=` must be a `.swarm` path
  without `..` that already exists (absolute, or relative to `cwd`); `dev`/`development` are
  protected push targets; redirects may not target `.git/` or `.claude/` in any letter case (except
  `.claude/agent-memory/`); `node -r/--require/--import/--loader`, `php -B/-R/-E` and `php -d
  auto_prepend_file|auto_append_file|extension|zend_extension` join `INTERP_DENY`, documented as
  advisory for writers (they can write a file and run it).
- **A `|` may only feed a text filter** (`cat`, `head`, `tail`, `wc`, `grep`, `rg`, `jq`, `sort`,
  `uniq`, `cut`, `tr`, `cmp`, `diff` — `PIPE_OK`): nothing else a pipe hands a command executes, for
  writer or read-only role alike.
- **A writer's `cd` goes only into an existing LINKED git worktree root** (`.git` is a file there,
  never a directory) — never back into the main checkout.
- **Interpreters need a script file, not a REPL or a bare call.** No REPL flag (`python3 -i`, `node
  -i`, `php -a`…), no `-`/`/dev/...` script argument, no bare invocation left to read stdin; `npm`/
  `npx` take no `-c`/`--call` (a shell string), `-y`/`--yes` or `-p`/`--package` (fetch-and-run) —
  singly or in a short flag cluster.
- `uniq`'s second positional argument is denied — under BSD getopt it's an *output* file, not a
  second input; `make` denies `-`, a `/dev/...` argument, and a trailing `f-`.
- **Positive shapes instead of deny prefixes.** `bash-allowlist.json` `shapes` lists, per argv prefix, the
  exact flags (no abbreviations), their value shapes and the positionals accepted (`every` role;
  `read_only` roles on top; `npm`/`composer` run by a read-only role only through such an entry).
  `dependency-installer`: `npm install|ci` require `--ignore-scripts` and take registry names only (no
  git/URL/tarball/path/`file:` spec, `-g`, `-C`/`--prefix`, `--git`, `--node-gyp`, `--script-shell`,
  any `*config*`); `composer install|require|update` require `--no-scripts --no-plugins`.
  `vulnerability-scanner`: `deptrac analyse` without `--config-file`/`--cache-file`, `phpmd` rulesets
  from a fixed list (built-ins + the repo's `phpmd.xml`). Orchestrators: `git worktree
  list|prune|remove <.claude/worktrees/agent-*>` and `git merge [--no-ff] worktree-agent-*|--abort` only
  (no `add`, `--no-verify`, `-s`). `git push`, `git remote`, `gh repo|pr|auth`, `claude plugin` moved
  from code to the same table. `jq` refuses `env`/`$ENV` and `-f`; git `--output` is denied for every
  role; redirects may not target `.husky/`, `.githooks/`, `.vscode/`, `.mcp.json` or `.envrc`; a
  read-only role's `cd` goes only up to the git toplevel holding its cwd (never `/`, `~/.ssh`, another
  repo). The guard is back under 250 lines.
- **The memory scripts are the boundary for their own paths** (`scripts/lib/validate.sh`): `--agent`,
  `--to` must match `^[a-z0-9][a-z0-9-]{0,63}$`, `--run` a uuid or `adhoc`, `--line` a positive integer
  (it reached `sed`: `1w <file>` wrote a file), `--file` a relative path without `..`, `--days`/`--keep`
  an integer (they reached `$((…))`: `now[$(cmd)]` ran `cmd`), every record field one line.
  `review-dedup.sh --swarm-root` must be a `.swarm` dir without `..`. Seeded traversal payloads in
  `tests/test_mem_paths_fuzz.py` assert exit ≠ 0 and nothing written outside `.swarm/`.

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

### Known gaps (documented, not silently swept under the rug)
- A writer's `cd` can still enter a *different* linked worktree, such as another agent's — the guard
  can tell a linked worktree from the main checkout, but not which worktree belongs to which agent.
- Short combined `npx`/`npm` flags are now denied even where they'd be safe — `npx tsc -p x` is
  denied; spell it `npx tsc --project x`.
- A pipe into a non-filter command is now denied even where it would have been harmless — `… | git
  …` or `… | php vendor/bin/phpunit` — because no shipped contract uses that shape.
- Writers keep bare `npm`/`composer`/`php`: package scripts and plugins run there by design (a writer
  can write a file and run it anyway); the positive npm/composer shapes bind read-only roles only.
- A read-only `cd` may climb to ANY git toplevel above its cwd (a submodule's superproject included);
  it cannot leave that ancestry.
- `swarm-status.sh` trusts `run/current` (it only reads, and only `mem-manifest.sh open` writes it).
- `jq` refuses the bare word `env` in any argument (`.env` and `"env"` pass): an input file literally
  named `env` is refused too.
