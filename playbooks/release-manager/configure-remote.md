# release-manager · configure-remote
On demand from agents/release-manager.md — trigger: `operation: configure-remote` and the `approved-remote:` gate passed.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Operation `configure-remote` — the remote bootstrap

For a repo with no remote yet: `prepare-release` returned `BLOCKED no remote configured`, the ROOT asked the owner with your preview (`- gh account:`, `- proposed remote:`) and relaunched you with an approval. You execute an already-made, NAMED decision. The approval gate (forms, fail-closed `name=`/`url=` checks, `approved-push:` ≠ remote approval) already ran in the core.

### Preconditions (fail BEFORE mutating, as always)

Each command counts toward `cmds=`.
1. **The remote still doesn't exist.**
   ```bash
   git remote -v
   ```
   Prints something → `BLOCKED remote already configured: <name> <url>` + `- hint: relaunch the delivery; if that remote isn't the one you want, change it yourself with git remote set-url`. **You never overwrite or rewrite an existing remote.**
2. **The current branch** (to name it in the output):
   ```bash
   git rev-parse --abbrev-ref HEAD
   ```
3. **Only with `action=create`, a `gh` session:**
   ```bash
   gh auth status
   ```
   Non-zero → `BLOCKED no gh authenticated` + `- hint: gh auth login (I can't run it myself: it's denied by the guard)`. If `name=`'s `<owner>/` isn't the active login, **don't fix it**: add `- warn: name=<owner> doesn't match the active account <login>` and continue.

**No clean tree required** (configuring a remote doesn't publish the tree; `--push` only sends commits). If `git status --porcelain` prints anything, add `- warn: <n> uncommitted files are left out of the initial push`.

### `action=create`

**`action=create` only creates on GitHub** (`gh repo create`; `gh` is a GitHub CLI). A repo on GitLab/Bitbucket/Gitea/other: the owner creates it outside the swarm and the root offers `action=use url=<the already-existing URL>` (§12.2bis, option C), host-agnostic.

One call, name and visibility **literal from the header** (no suffixes, no "improving", no visibility change):
```bash
gh repo create owner/repo --private --source=. --remote=origin --push
```
(`--public` if `visibility=public`.) The three flags go together on purpose: **`gh` sets the remote URL, not you** (you build no URLs and have no `git remote set-url`). No `--description` or other flag: the guard admits only `--public/--private/--source/--remote/--push/--description`, and the last is unused.

**Verify the result; don't trust "it didn't error out":**
```bash
git remote -v
```
- `gh` exit 0 and `origin` listed → `DONE` with `- remote created:` and `- next:`.
- `gh` exit ≠ 0 but `origin` ALREADY listed → repo created, remote added, push failed. **External state changed; say it**: `BLOCKED remote created but push rejected: <literal gh/git stderr, untrimmed>` + the SSH-identity hint (git-errors playbook) when stderr contains `denied to` or `Permission denied`. Don't retry, don't change the URL, don't delete the repo.
- `gh` exit ≠ 0 and still no remote → `KO could not create the repository: <literal stderr, untrimmed>`.

### `action=use`

```bash
git remote add origin https://github.com/owner/repo.git
```
(URL = header's `url=`; no flags, exactly two positionals — the only form the guard allows.) Check with `git remote -v`; failure → `KO could not add the remote: <literal stderr, untrimmed>`.
**You don't push anything here**: publishing needs its own `approved-push:` naming remote, branch and base.

### The mutation record (with `Write`)

Every external mutation leaves a trace: write `<swarm-root>/run/<run>/remote-setup.md` (counts toward `files=`):
```
# Remote configured — <YYYY-MM-DD>

- action: create | use
- command: <the literal command you ran>
- exit: <code>
- git remote -v:
  <the literal output, as-is>
- current branch: <branch>
```

### Why you DON'T chain the delivery here

End with `- next: relaunch the delivery now that <remote> exists` and **relaunch nothing**: `approved-push:` NAMES remote, branch and base, and when the owner approved the remote the base didn't exist yet — chaining would fabricate an approval for a destination the owner never saw.

### Output

```
DONE
evidence: files=1 cmds=5 turns=6/15
- remote created: origin → https://github.com/owner/repo (private)
- next: relaunch the delivery now that origin exists
```
With `action=use`, the first line is `- remote: origin → <url>`, then the same `- next:`.
Verdicts: `BLOCKED no remote approval`, `BLOCKED malformed remote approval` (core gate); `BLOCKED remote already configured: <name> <url>`; `BLOCKED no gh authenticated`; `BLOCKED remote created but push rejected: <literal stderr>`; `KO could not create the repository: <literal stderr>`; `KO could not add the remote: <literal stderr>`.
