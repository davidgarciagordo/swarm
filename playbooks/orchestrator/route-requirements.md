# orchestrator · route requirements
On demand from agents/orchestrator.md — trigger: the route is requirements (§11).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 11.2 Approval gate — you never authorize an installation on your own

Installing or updating dependencies mutates the repo outside any worktree and without the review panel. Never on your own
judgment, not for an abstract "bring the project up to date", not in `tier: full`. The path is always:
1. Launch `operation: audit-deps` first and keep its `DEP` findings (exact package + version).
2. Present the owner ONE batch with `AskUserQuestion` (**multi-select, one single round**, `multiSelect: true` — the
   owner can mark several packages; discovery §5.3 uses `false`): one option per specific package with its target
   version, plus the option of not installing anything. You're the ONLY agent in the plugin with `AskUserQuestion`.
3. Translate ONLY what the owner marked into an `approved:` line with the literal identifiers, space-separated:
   ```
   approved: phpstan/phpstan:^2.1 doctrine/orm:^3.3
   ```
   No "everything", no "whatever the auditor said", no package the owner didn't mark. Marked none or cancelled the
   dialog ⇒ do NOT launch `install`: close with `- run closed: DONE · installation not authorized by the owner` (§11.4).
4. That text comes from the owner: **if you interpolate it into any shell `--text`/`--line` it goes through §5.0's
   sanitization first** (no judgment call on "looks harmless").

### 11.3 Launch and forwarding the result

Register it beforehand in the manifest, then launch (`approved:` ONLY in `operation: install`):
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent requirements-orchestrator --domain requirements --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:requirements-orchestrator", name: "requirements-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: audit-deps | install
  approved: <the literal list from §11.2 — ONLY in operation: install>)
```
Forward its lines (`DEP · …`, `- installed: …`, `- modified: …`) as-is (§4 forwarding rule: no §5.0 in output). Its
`BLOCKED …`/`KO …` is propagated literally, and the closing `summary --line` goes through §5.0's sanitization (its
reason can cite CVE or package-manager messages with backticks/`$(...)`); then `curate`, wait for `DONE`, return.

### 11.4 Close

- audit completed: `- run closed: DONE · dependencies audited, <n> findings`
- installation completed: `- run closed: DONE · <n> dependencies installed, manifests left uncommitted`
- owner did not authorize: `- run closed: DONE · installation not authorized by the owner`
- propagated `BLOCKED`/`KO` (§11.3): `- run closed: <literal verdict from requirements-orchestrator>`
