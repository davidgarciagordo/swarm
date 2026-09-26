# orchestrator · route delivery
On demand from agents/orchestrator.md — trigger: the route is delivery (§12).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 12.2 Push approval gate — you never authorize a publish on your own

A push to a shared remote, or a PR someone merges, doesn't always get undone. Never on your own judgment, not for an
abstract "just ship this already", not in `tier: full`. The path is always:
1. Launch `operation: prepare-release` and keep its preview lines (`- preview push:`, `- preview pr:`, `- remote:`,
   `- commits:`, `- green:` and any `- warn:`). If it comes back `BLOCKED`/`KO`, propagate it (§12.3) and close the run —
   **except `BLOCKED no remote configured`, a precondition the owner can resolve now: that goes to §12.2bis.** For
   everything else (dirty tree, red suite, `HEAD` on a protected branch) the owner fixes it in the repo, not by a question.
2. ONE single question with `AskUserQuestion` (**single-select**, `multiSelect: false` — one decision: publish or not).
   You're the ONLY agent in the plugin with `AskUserQuestion`. The question text carries, LITERALLY, the preview's
   values: the remote with its URL, the branch, the base, the number of commits and the green status. **If the preview
   carried `- warn: no runnable suite — green NOT verified`, that phrase goes INSIDE the text of the affirmative
   option** — "unknown" is never presented as "green". Exactly two options: publish with those values, or don't publish.
3. If the owner chooses to publish, translate **the preview's values** (not their prose answer) into the literal line:
   ```
   approved-push: remote=origin branch=feature/export-csv base=master url=git@github.com:owner/repo.git
   ```
   The four fields, `key=value`, in that order, taken from the `- remote:` (name AND URL, as the leaf showed them) and
   the `- preview push:` the leaf returned — **never from a generic yes**, never from memory, never from what you believe
   the branch or URL to be. `url=` lets phase B confirm the remote didn't change URL between preview and push, by ANY
   means. Owner chooses not to publish, or cancels ⇒ do NOT launch phase B; close with
   `- run closed: DONE · publishing not authorized by the owner` (§12.4).
4. That line is built from leaf and owner text: **if you interpolate it into any shell `--text`/`--line` it goes through
   §5.0's sanitization first** (branch names can carry `$` and backticks; commit messages almost always do).
5. Launch phase B with a **FRESH `Agent` call**, not `SendMessage` to the live `delivery-orchestrator` (deliberate
   exception to reusing a live agent): the approval must travel in a LAUNCH HEADER the leaf verifies as input, and a
   clean relaunch makes `release-manager` re-run ALL its checks against the real state.

### 12.2bis No remote configured — the only `BLOCKED` that opens a decision

When `delivery-orchestrator` returns `BLOCKED no remote configured`, **you don't close the run**: it's a missing
precondition, resolved with the same pattern as §12.2 (preview first, an approval that NAMES the destination after).
1. **The leaf already gave you the preview**: `- gh account: <login> (active) · last commit signed by: <email>` and
   `- proposed remote: gh repo create <login>/<repo> --private --source=. --remote=origin --push`. **Don't recompute
   it** (no `gh` in your allowlist, no leaf work). If those two lines don't come, close the run propagating the `BLOCKED`
   — without a preview there's no honest question.
2. **ONE `AskUserQuestion` call** (`multiSelect: false`) with the exact repo name, the account, and the literal command
   INSIDE the text — never a bare "should I create a repo?". Four options:
   - **A)** `Create <login>/<repo> PRIVATE on GitHub and use it as origin` *(Recommended)*
   - **B)** `Create <login>/<repo> PUBLIC on GitHub and use it as origin`
   - **C)** `I already have a remote: let me paste the URL` — the owner types it into "Other"
   - **D)** `Nothing: I'll configure it by hand`
   If `- gh account:` says `no gh authenticated`, only C and D are offered and the text explains why. If account and
   email don't match, **that discrepancy goes INSIDE the question text** (same as `green NOT verified` in §12.2).
3. **Translate the answer into a literal line**, values from the preview, not the owner's prose:
   ```
   approved-remote: action=create name=<login>/<repo> visibility=private
   approved-remote: action=use url=<the URL the owner pasted>
   ```
   (`visibility=public` with option B.) Before the `use` form, **validate the URL**: it starts with `https://`, `git@`,
   `ssh://` or `file://` and contains no spaces nor any of `; | & $ ` ( ) < > \`. If not, **don't sanitize it and don't
   ask again** (one round): verdict `BLOCKED malformed remote url`, close the run like any terminal path (§12.3).
4. Option **D**, or the owner cancels: launch nothing, propagate `BLOCKED no remote configured`, close with
   `- run closed: BLOCKED no remote configured` (§12.4) — "I'll do it myself" is a valid answer.
5. Options **A**, **B**, **C**: launch `operation: configure-remote` with a **FRESH `Agent` call** carrying the
   `approved-remote:` line and **without** `approved-push:` — one approval doesn't count for the other.
6. **When `configure-remote` comes back `DONE`, you don't chain the delivery.** Close with
   `- run closed: DONE · remote configured, delivery pending relaunch` and point the owner at the leaf's `- next:` line.
   An `approved-push:` NAMES remote, branch and base, and the base didn't exist when the owner approved the remote:
   chaining would fabricate an approval for a destination they haven't seen.

### 12.3 Launch and forwarding the result

Register it beforehand in the manifest, then launch. The two approval lines **never travel together**: each operation
carries its own and only its own.
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent delivery-orchestrator --domain delivery --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:delivery-orchestrator", name: "delivery-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: prepare-release | publish-release | configure-remote
  base: <base branch, only if the owner named it explicitly>
  approved-push: <the literal line from §12.2 — ONLY in operation: publish-release>
  approved-remote: <the literal line from §12.2bis — ONLY in operation: configure-remote>)
```
Forward its lines (`- preview push:`, `- preview pr:`, `- remote:`, `- commits:`, `- green:`, `- pushed:`, `- pr:`,
`- manual pr:`, `- pr command:`, `- notes:`, `- handoff:`, `- gh account:`, `- proposed remote:`, `- remote created:`,
`- next:`, `- hint:`) as-is (§4 forwarding rule: no §5.0 in output). Its `BLOCKED …`/`KO …` is propagated literally,
and the closing `summary --line` goes through §5.0's sanitization (its reason can cite a remote's rejection message or a
commit subject with backticks/`$(...)`); then `curate`, wait for `DONE`, return.

### 12.4 Close

- preview ready, waiting for decision: `- run closed: DONE · delivery prepared, pending approval`
- published: `- run closed: DONE · branch published and PR opened`
- published with no PR (no `gh`): `- run closed: DONE · branch published, PR pending manual opening`
- owner did not authorize: `- run closed: DONE · publishing not authorized by the owner`
- remote configured (§12.2bis): `- run closed: DONE · remote configured, delivery pending relaunch`
- owner chose to configure the remote by hand, or cancelled (§12.2bis): `- run closed: BLOCKED no remote configured`
- pasted URL invalid (§12.2bis): `- run closed: BLOCKED malformed remote url`
- propagated `BLOCKED`/`KO` (§12.3): `- run closed: <literal verdict from delivery-orchestrator>`
