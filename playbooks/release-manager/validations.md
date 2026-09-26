# release-manager · validations
On demand from agents/release-manager.md — trigger: `operation: prepare-release`, or `publish-release` after its gate.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Validations, in THIS order — fail before mutating anything

Each check is cheaper than the next and all come BEFORE writing any file. First failure = your verdict; stop. Every command counts toward `cmds=`.

### 1. Clean tree

```bash
git status --porcelain
```
Any output → `BLOCKED dirty tree: <n> uncommitted files` (you can't commit them; publishing a branch whose local tree differs from what's published deceives the owner).

### 2. Remote configured

```bash
git remote -v
```
Prints NOTHING → no remote; nothing mutated. **Don't return it bare**: it's the only `BLOCKED` the root turns into an owner question, so gather what the root can't (it has no `gh`):
```bash
gh auth status
```
(no `gh` or no session → the `- gh account:` line says `no gh authenticated`; not your error).
```bash
git log -1 --format=%ae
```
**Don't use `git config user.email`**: `git config` is a WRITE command, not in your allowlist and never will be (`git config core.pager <anything>` = arbitrary execution). Proposed repo name = **basename of `<repo-root>`** as-is, no invented suffixes/slugs. Visibility is **not your choice**: `--private` is shown as the proposed default, not a fact.
```
BLOCKED no remote configured
evidence: files=1 cmds=5 turns=4/15
- hint: git remote add origin <url> and relaunch the delivery
- gh account: <login of the ACTIVE account> (active) · last commit signed by: <email>
- proposed remote: gh repo create <login>/<basename of repo-root> --private --source=. --remote=origin --push
```

**Expected pairing**: the active `gh` account and the git email of the last commit must
belong to the identity the remote expects (the remote's owner). The plugin never knows who that is:
it only shows both values. A mismatch is never fixed or hidden here — the owner decides.

`- proposed remote:` is a **literal preview, never executed** in this operation (same pattern as `- preview push:`: the owner sees the resolved command and decides). If `- gh account:` shows an account and an email that don't match, don't fix or hide it: the line makes it visible; the owner decides.

Several remotes: phase B uses the one from `approved-push:`; phase A uses `origin` if it exists, else the FIRST one `git remote -v` lists.

With `<remote>` chosen, get its PUSH URLs with a dedicated call — **never from the `git remote -v` listing, never `git remote get-url <remote>` alone, never `--push` without `--all`**:
```bash
git remote get-url --push --all origin
```
(substitute the chosen remote). Why:
1. Without `--push` (and every `(fetch)` line of `git remote -v`) you get the FETCH URL; `remote.<remote>.pushurl`, when set, is where `git push` really goes. Approving the fetch URL approves the wrong destination.
2. **`remote.<remote>.pushurl` AND `remote.<remote>.url` are MULTI-VALUED in git**: several lines in `.git/config`, and `git push` pushes to ALL. `--push` without `--all` prints only the FIRST; `--all` is the only way to see the whole set.

More than one line → unsupported (`url=` names ONE destination); do NOT keep the first line. Verdict `BLOCKED remote with multiple push destinations` + `- push destinations: <url1>, <url2>, …` listing ALL as printed; the owner fixes it (`git config --unset-all remote.<remote>.pushurl` or equivalent, outside your allowlist) and relaunches.

Exactly one line → that's the push URL. `- remote:` carries the name and that URL exactly as returned —no `(push)`/`(fetch)` marker, no reformatting, no abbreviating—: `- remote: origin → git@github.com:owner/repo.git`. The root copies it unchanged into `url=` of `approved-push:`; it's also the URL that decides whether the host is GitHub for `gh pr create`.

### 3. Current branch and base branch

```bash
git rev-parse --abbrev-ref HEAD
```
That literal is `<branch>`. Exactly `master`/`main`/`develop`/`trunk` → `BLOCKED HEAD on protected branch, nothing to publish` + `- hint: git switch -c <working-branch> before delivering`.

Base, in order: (a) the header's `base:`; (b) otherwise
```bash
git rev-parse --abbrev-ref origin/HEAD
```
(substitute the real remote from §2; prints e.g. `origin/master` — base is what follows the slash). Fails → `BLOCKED indeterminate base` + `- hint: git remote set-head <remote> -a, or pass base: in the header`. **Don't guess `master`**: a wrong base opens a PR against the wrong branch.

`<branch>` == `<base>` → `BLOCKED HEAD on protected branch, nothing to publish`.

### 4. There's something to publish

```bash
git log --no-merges --format=%s master..HEAD
```
(substitute `master` with `<base>`). No lines → `DONE` + `- nothing to publish: <branch> has no commits over <base>` (not an error; launch nothing else). Line count = `<n-commits>`; the lines are the notes.

### 5. Green locally ("merge in green")

**"Merge in green" = the local suite passes BEFORE pushing.** It NEVER means waiting for CI and auto-merging the PR.
- **`pack:` present** → `Read` `<pack>/commands.md` (counts toward `files=`), take the `test` key, check its condition (the row's marker file, with `ls`), run the row's command, one per call:
  ```bash
  php vendor/bin/phpunit
  ```
  Exit 0 → `- green: php vendor/bin/phpunit OK`. Non-zero → `KO tests in red: <first failure line, ≤60 characters>`, **with no preview and no possibility of approval**.
- **No `pack:`, no `test` key, or condition unmet** (no `phpunit.xml`, etc.) → do NOT invent a test command; continue with the literal line `- warn: no runnable suite — green NOT verified`. The root must repeat that warning in the owner question: "unknown" is never presented as "green".
- **Pack command denied by the guard** (no two-word prefix match) → same `- warn: no runnable suite — green NOT verified` plus `- warn: the pack's test command is outside the allowlist: <command>`.
