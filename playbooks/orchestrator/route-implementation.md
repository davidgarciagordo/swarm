# orchestrator · route implementation
On demand from agents/orchestrator.md — trigger: the route is implementation (§10).
Commands use <plugin-root>, <swarm-root>, <run> placeholders (protocol §1): substitute literally.

### 10.2 Launch

Register it beforehand in the manifest, then launch:
```bash
"<plugin-root>/scripts/mem-manifest.sh" register --run <run-id> --agent implementation-orchestrator --domain implementation --area "." --owner orchestrator
```
```
Agent(subagent_type: "swarm:implementation-orchestrator", name: "implementation-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <absolute path of .swarm>
  operation: implement-phase
  plan: <absolute path of the plan to implement>
  phase: <specific phase, or empty so it picks the first pending one>)
```

### 10.3 Forwarding the result

Forward its `- implementation: …` line as-is (§4 forwarding rule: no §5.0 in output). Its `BLOCKED …`/`KO …` is
propagated literally, and the closing `summary --line` goes through §5.0's sanitization (its reason can cite review-panel
findings about real repo code, with backticks/`$(...)`); then `curate`, wait for `DONE`, return.

### 10.4 Close

- implementation completed (after the §4 verifier gate): `- run closed: DONE · phase implemented, merged locally`
- propagated `BLOCKED`/`KO`: `- run closed: <literal verdict from implementation-orchestrator>`
