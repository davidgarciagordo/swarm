# release-manager · git-errors
On demand from agents/release-manager.md — trigger: `git push`, `git remote add`, `gh repo create` or `gh pr create` exits non-zero.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## `git`/`gh` errors: literal, never reinterpreted

**The exact error text IS the finding.** Copy it into the verdict untrimmed, untranslated, not summarized, not replaced by your own diagnosis (`KO push rejected: permissions failure` is worthless).

**Explicit exception to the ≤60-character trim**: that trim is only for a test suite's summary (`KO tests in red: …`). Credential/permission/network errors: the value is in the full text.

**Failure mode to recognize without fixing it**: with SEVERAL GitHub identities, the remote may use the default host `git@github.com:…` while the active account's SSH key lives under another alias in `~/.ssh/config` (e.g. `github-work`); the push fails with `Permission ... denied to <OTHER-ACCOUNT>` though `gh auth status` shows the right account. When stderr contains `denied to` or `Permission denied`, add besides the literal text:
```
- hint: the remote uses the default SSH host and your key for <active account> may be under another alias in ~/.ssh/config — git remote set-url origin git@<alias>:<owner>/<repo>.git
```

**Additive extension (always on top of the literal error, never in its place):** read `~/.ssh/config` (local, static, non-sensitive: `Host` aliases, not keys) to make the hint concrete:
```bash
cat ~/.ssh/config
```
(counts toward `cmds=`; read-only. Missing file or failure → add nothing more; the generic hint stands.) Find `Host <alias>` blocks whose `Hostname` matches the remote's real host (e.g. `github.com`). If ONE OR MORE aliases other than the default host exist, add, literal and in file order:
```
- candidate aliases in ~/.ssh/config for github.com: <alias1>, <alias2>
```
None found, or no `Hostname` matches → no line; never invent an alias.

**And you stop there.** You don't run `git remote set-url` (guard-denied for every agent_type) and **you don't pick the correct alias**: only NAME candidates (several may exist, or none may be right). The decision and its command stay the owner's. Read no other file under `~/.ssh/` (no private key, no `known_hosts`).

Aliases are THIRD-PARTY text: if ever interpolated into a shell `--text`/`--line` (e.g. someone forwards `- candidate aliases:` to a real command), sanitize per protocol §4.4 first — by rule, not by how harmless it looks.
