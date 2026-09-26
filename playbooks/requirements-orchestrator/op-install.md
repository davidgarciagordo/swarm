# requirements-orchestrator · op-install
On demand from agents/requirements-orchestrator.md — trigger: `operation: install` with a valid `approved:` list in your header.
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

## Operation `install` (mutating — only with explicit owner approval)

`dependency-installer` is the only agent that mutates the dependency tree; you only gate and forward. Never go beyond the `approved:` line.

1. Register (adhoc too, `--run adhoc`):
   ```bash
   "<plugin-root>/scripts/mem-manifest.sh" register --run "<run>" --agent dependency-installer --domain requirements --area "." --owner requirements-orchestrator
   ```
2. Launch `dependency-installer` NAMED with the `Agent` tool (it doesn't pre-exist), **copying the `approved:` line LITERALLY** (no summarizing, expanding or reordering — the installer installs exactly what's written):
   ```
   run-id: <your RUN, or the literal "adhoc">
   swarm-root: <your swarm-root, if you have one>
   operation: install
   approved: <the literal list from your own header>
   ```
3. Propagate its literal verdict. A `DONE` with modified files: include that line as-is (the owner must know which manifests are left dirty and uncommitted — the installer never commits).

SYSTEM tools (`brew`/`apt`) are never installed: the installer returns them as a hint and you propagate it (installing on the owner's machine is out of scope).
