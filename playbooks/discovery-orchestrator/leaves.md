# discovery-orchestrator · leaves (research-only discovery)
On demand from agents/discovery-orchestrator.md — trigger: WHEN your header carries `leaves:`.

`leaves: <names>` (comma list out of `research-analyst`, `feasibility-spiker`) means the root needs facts, not owner
questions: an unattended run, or a plan that depends on things outside the repo. The core file applies except:

1. Launch ONLY the listed leaves, in one batch, registered and named as in the core table. Never `value-critic` or
   `options-generator`. `feasibility-spiker` still needs its ONE concrete question (startup step 3); no real
   technical doubt ⇒ drop it and write `- warn: no feasibility question, spiker not launched`.
2. Wait and clean up exactly as in the core file (`WAITING`, spiker-cleanup).
3. No question batch and no `summary --line` mirror. Run the findings query (core step 2) to confirm the leaves wrote.
4. Verdict: `DONE`, evidence, `- findings: <the leaves that answered>`, plus any `- warn:` line. No `- Q…` lines.
   No listed leaf answered ⇒ `BLOCKED no leaf responded` (`BLOCKED judgment leaves unresponsive` does not apply).
   A name outside the two above ⇒ `BLOCKED unknown leaf <name>`, launch nobody.
