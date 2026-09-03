#!/usr/bin/env bash
# tests/test_verdict_templates_valid.sh — every verdict template an agent's own body documents
# must actually be ACCEPTED by hooks/validate-output.py for THAT agent's real agent_type.
#
# Real bug this catches (final whole-branch review of fase 5b, Critical finding): agents/
# doc-writer.md documented `DONE · nada observable que documentar` as its own verdict for the
# most common path (nothing to document) -- but hooks/validate-output.py's VERDICT_RE is
# `^(OK|KO .+|DONE|BLOCKED .+)$`, so a bare `DONE` with a `·` suffix on line 1 does NOT match
# (only KO/BLOCKED allow a suffix after a space) and gets rejected as narration. The same bug
# class was independently present in agents/implementation-orchestrator.md
# (`DONE · fase ya implementada`). Three prior task-level reviews shipped this undetected because
# nothing ever ran a documented template through the REAL hook -- reading the agent file and
# trusting the prose was the whole verification. This is the systemic fix: extract every verdict
# template an agent documents and run it through the real hook, don't trust reading it.
#
# Method: for each agent file, take its `name:` frontmatter field as `swarm:<name>`, then extract
# two kinds of candidates from the body:
#   1. Fenced ``` blocks (no language tag -- ```bash blocks are shell examples, covered by
#      tests/test_agent_bash_blocks_allowed.sh, not verdict templates) whose first line looks
#      like a verdict (OK / KO <x> / DONE / BLOCKED <x>). The whole block is already a complete
#      multi-line message (verdict + evidence: + optional finding lines) -- fed to the hook as-is.
#   2. Single backtick-quoted spans on one line whose content looks like a verdict. These are
#      inline mentions of the exact literal shape ("tu veredicto es `DONE`") with no evidence
#      line nearby -- a synthetic `evidence: files=1 cmds=1 turns=1/10` line is appended so the
#      hook has something structurally complete to validate line 1 against.
# Candidates immediately preceded by "NUNCA" (case-insensitive, within ~20 chars) are skipped:
# that's an agent file explicitly documenting the WRONG shape as a caution (e.g. doc-writer.md's
# own "(NUNCA `DONE · nada observable que documentar` -- ...)" callout right next to the fix this
# test exists to pin) -- asserting THAT text is accepted would defeat the callout's purpose.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"

# The 4 new phase-5b leaf agents (minimum required) plus the orchestrators this same review pass
# touched for the identical bug class -- extending coverage costs nothing once the harness exists.
AGENT_FILES="migration-engineer doc-writer dependency-auditor dependency-installer implementation-orchestrator requirements-orchestrator env-checker"

validate() { # validate <agent_type> <message-json-string> -> "accept" | "reject"
  # Fresh, isolated SWARM_ROOT PER CALL (protocol §1.3 retry counter lives under
  # run/<run>/retries/<agent>-<hash(reason)>). Reusing one root across candidates -- or worse,
  # a real repo checkout's own .swarm/ -- means the SECOND rejection for the same agent+reason
  # (e.g. doc-writer.md documented the exact same broken shape twice before the fix this test
  # pins) gets converted by validate-output.py into an accepted-with-systemMessage response,
  # silently flipping this test's own "reject" assertion to "accept" on exactly the case it
  # exists to catch. A throwaway root per call means every candidate is always a "first offense".
  local out
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-verdict-check.XXXXXX")"
  out="$(SWARM_ROOT="$root/.swarm" python3 "$HOOK" <<PYIN
{"agent_type": "$1", "hook_event_name": "SubagentStop", "last_assistant_message": $2}
PYIN
)"
  rm -rf "$root"
  if echo "$out" | grep -q '"decision": "block"'; then echo reject; else echo accept; fi
}

for stem in $AGENT_FILES; do
  f="$PLUGIN_ROOT/agents/$stem.md"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$stem.md exists"
  [ -f "$f" ] || continue

  agent_type="swarm:$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f")"
  assert_eq "swarm:$stem" "$agent_type" "$stem.md frontmatter name matches its filename"

  candidates="$(python3 - "$f" <<'PYEOF'
import re, sys, json

VERDICT_START_RE = re.compile(r'^(OK\b|KO\s|DONE\b|BLOCKED\s)')
NEGATION_RE = re.compile(r'nunca', re.I)

text = open(sys.argv[1]).read()
parts = text.split('---\n', 2)
body = parts[2] if len(parts) >= 3 else text

messages = []

# 1. Fenced blocks with no language tag whose first line looks like a verdict. Markdown list
# items indent fenced blocks (e.g. 2 spaces for a "- " item) -- that indentation is real in the
# source but not part of the message an agent would actually emit, so it is dedented before the
# verdict-line regex (anchored at column 0) gets to see it.
for m in re.finditer(r'```(\w*)\n(.*?)```', body, re.S):
    lang, block = m.group(1), m.group(2)
    if lang:
        continue
    lines = block.rstrip('\n').split('\n')
    indent = len(lines[0]) - len(lines[0].lstrip(' ')) if lines else 0
    dedented = [(l[indent:] if l[:indent].strip() == '' else l) for l in lines]
    first = dedented[0].strip() if dedented else ''
    if VERDICT_START_RE.match(first):
        messages.append('\n'.join(dedented))

# 2. Single backtick-quoted spans on one line whose content looks like a verdict.
for m in re.finditer(r'`([^`\n]+)`', body):
    content = m.group(1)
    if not VERDICT_START_RE.match(content):
        continue
    before = body[max(0, m.start() - 20):m.start()]
    if NEGATION_RE.search(before):
        continue
    messages.append(content + '\nevidence: files=1 cmds=1 turns=1/10')

for msg in messages:
    print(json.dumps(msg))
PYEOF
)"

  assert_eq "0" "$([ -n "$candidates" ] && echo 0 || echo 1)" "$stem.md has at least one documented verdict template to check"

  while IFS= read -r msg_json; do
    [ -n "$msg_json" ] || continue
    result="$(validate "$agent_type" "$msg_json")"
    assert_eq "accept" "$result" "$stem.md ($agent_type) documented verdict template is accepted by validate-output.py: $msg_json"
  done <<EOF
$candidates
EOF
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
