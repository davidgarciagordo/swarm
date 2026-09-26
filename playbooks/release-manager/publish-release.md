# release-manager · publish-release
On demand from agents/release-manager.md — trigger: `operation: publish-release` and the approval gate passed.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Phase B — `operation: publish-release`: gate, re-verification, and only then you publish

The approval gate (four fields `remote=`/`branch=`/`base=`/`url=`) already ran in the core, before anything else. `url=` is the exact push URL the owner saw in phase A's preview.

### Re-verification against reality (closes the gap between the preview and the push)

Repeat validations 1-4 (cheap) AND check the approval describes the world NOW (the owner may have switched branches while deciding; the remote may have changed by ANY means):
- `git rev-parse --abbrev-ref HEAD` must print exactly the approved `branch=`;
- the approved `remote=` must exist AND its PUSH URL(s) must match the approved `url=` EXACTLY, character for character — **use `--push --all`, never `git remote get-url <remote>` alone nor `--push` without `--all`**:
  ```bash
  git remote get-url --push --all origin
  ```
  (substitute the approved remote; counts toward `cmds=`).
  - **More than one line**: several push destinations RIGHT NOW — not representable in a single-value field, so you don't try to compare line by line nor keep the first one. Verdict `BLOCKED approval does not match real state` + `- discrepancy: url approved <the header's url=>, real <n> push destinations` (`<n>` = printed lines). No push possible.
  - **Exactly one line**: compare literally with `url=`, no normalizing or trimming (`git@github.com:o/r.git` ≠ `git@github.com:o/r`).
- approved `base=` ≠ `branch=`;
- `branch=` is not `master`/`main`/`develop`/`trunk`.

Why `--all`: `remote.<remote>.pushurl` (or `remote.<remote>.url` without it) is MULTI-VALUED; `git push` pushes to ALL lines. A second `pushurl = git@evil.example.com:...` added to `.git/config` between phase A and B (a direct human edit, invisible to any command guard) leaves the first line unchanged, so a comparison without `--all` would match while the real push ALSO goes to the attacker's host. Hence more than one destination = outright rejection.

Any discrepancy → `BLOCKED approval does not match real state` + `- discrepancy: <field> approved <x>, real <y>` (incl. `- discrepancy: url approved <x>, real <y>`, or `…, real <n> push destinations`). Never "fix" the approval: one that doesn't describe reality isn't an approval.

### Push (one command, in its own call)

```bash
git push origin feature/export-csv
```
The ONLY form the guard allows: `git push <remote> <branch>`, two positionals, no flags (no `--force`/`--delete`/`--mirror`/`--all`/`--tags`, no `+`/`:` refspec, no protected branch). Push fails (rejection, credentials, network) → `KO push rejected: <literal git stderr, UNTRIMMED>`; **don't retry with another form, don't relax anything**. The ≤60-char trim of test summaries does NOT apply here (see git-errors).

### PR (honest degradation if there's no `gh`, or if the remote isn't GitHub)

**First look at the remote's URL** — the PUSH one you already got in re-verification with `git remote get-url --push --all` (don't request it again, don't use another): re-verification guaranteed ONE line, the URL `git push` just used; checking the fetch URL could route the PR to `github.com` while the push went elsewhere. **Not containing `github.com`** → skip `gh` entirely (don't even run `gh auth status`) and use the generic-host degradation below.

GitHub URL:
```bash
gh auth status
```
- **Exit 0** → one call:
  ```bash
  gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file .swarm/run/1234-5678/release-notes.md
  ```
  (`--body-file` RELATIVE to `<repo-root>`, never `/abs/.swarm/run/<run-id>/…` — guard-denied). Output = PR URL → `- pr: <url>`. If `gh pr create` fails, **this is not a `KO`**: the branch is ALREADY published (the irreversible part); degrade to the next case and say so.
- **Non-zero exit or no `gh`, GitHub remote** → nothing fails (`gh` is `required: false` in `requirements.json`); return:
  ```
  - manual pr: origin git@github.com:owner/repo.git · feature/export-csv → master
  - pr command: gh pr create --base master --head feature/export-csv --title "feature/export-csv" --body-file .swarm/run/<run-id>/release-notes.md
  ```
- **Remote NOT GitHub** → `gh` can't work against that host by design; one generic line naming no tool:
  ```
  - manual pr: origin git@gitlab.com:owner/repo.git · feature/export-csv → master
  - open your PR/MR by hand on that remote's host — this domain doesn't know how to automate it outside GitHub (v1.1: GitHub only)
  ```
  In both degradations **don't fabricate a "compare" URL** (`ssh://`, `git@host:owner/repo`, `https://`, `file://` parse differently; a dead invented URL is worse than a pasteable command).

### Output

```
DONE
evidence: files=2 cmds=9 turns=12/15
- pushed: origin feature/export-csv (4 commits)
- pr: https://github.com/owner/repo/pull/42
- notes: /abs/.swarm/run/<run-id>/release-notes.md
```
