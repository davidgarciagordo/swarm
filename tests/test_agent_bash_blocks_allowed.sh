#!/usr/bin/env bash
# tests/test_agent_bash_blocks_allowed.sh — every ```bash example an agent's own body documents
# must actually be allowed by hooks/bash-guard.py for THAT agent's agent_type.
#
# Real bug this catches (fase 5a final review, C1): agents/quality-fixer.md documented
# `cd <ruta> && vendor/bin/php-cs-fixer fix --diff` and `cd <ruta> && git add -A && git commit …`
# as the commands the agent runs — but `cd` was missing from swarm:quality-fixer's allowlist entry
# in hooks/bash-allowlist.json, and `vendor/bin/php-cs-fixer` doesn't match anything (the guard
# matches by first-word basename, and only `php` was allowlisted, not `php-cs-fixer` — same reason
# `php vendor/bin/phpunit`, not bare `vendor/bin/phpunit`, is the documented pattern in
# test-writer.md/implementer.md). A documented command an agent can never actually run is a silent
# dead end discovered only in production. This is a GENERAL test class, not specific to
# quality-fixer/reviewer: any agent added to AGENT_FILES below gets the same check for free.
#
# Method: for each agent file, take its `name:` frontmatter field as `swarm:<name>`, extract every
# fenced ```bash block from the body, join backslash-continued lines into one logical command
# (mem-files.sh/mem-manifest.sh calls span several physical lines), skip blank/comment lines, and
# assert hooks/bash-guard.py allows that exact line for that agent_type. No block in these files
# is a documented intentional deny, so every extracted line must allow.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

# The agents listed in AGENT_FILES (implementation, fase 5a + requirements/pack, fase 5b). Add
# future agents here to extend the same coverage — no other change needed.
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor dependency-installer migration-engineer doc-writer analysis-orchestrator vulnerability-scanner data-model-auditor requirements-orchestrator env-checker verifier release-manager handoff-writer delivery-orchestrator"

guard() { # guard <agent_type> <command> -> "allow" | "deny"
  local out
  out="$(python3 "$HOOK" <<PYIN
{"agent_type": "$1", "tool_name": "Bash", "tool_input": {"command": $2}}
PYIN
)"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

for stem in $AGENT_FILES; do
  f="$PLUGIN_ROOT/agents/$stem.md"
  assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/$stem.md exists"
  [ -f "$f" ] || continue

  agent_type="swarm:$(awk '/^---$/{n++; next} n==1 && /^name:/{print $2; exit}' "$f")"
  assert_eq "swarm:$stem" "$agent_type" "$stem.md frontmatter name matches its filename"

  # Extract every ```bash ... ``` block body (may be several per file), join backslash line
  # continuations into one logical command per resulting line, drop blanks/comments.
  commands="$(python3 - "$f" <<'PYEOF'
import re, sys, json

text = open(sys.argv[1]).read()
for block in re.findall(r'```bash\n(.*?)```', text, re.S):
    logical = []
    for line in block.split("\n"):
        stripped = line.rstrip()
        if logical and logical[-1].endswith("\\"):
            logical[-1] = logical[-1][:-1].rstrip() + " " + stripped.strip()
        else:
            logical.append(stripped)
    for cmd in logical:
        cmd = cmd.strip()
        if not cmd or cmd.startswith("#"):
            continue
        print(json.dumps(cmd))
PYEOF
)"

  assert_eq "0" "$([ -n "$commands" ] && echo 0 || echo 1)" "$stem.md has at least one fenced bash example to check"

  while IFS= read -r cmd_json; do
    [ -n "$cmd_json" ] || continue
    result="$(guard "$agent_type" "$cmd_json")"
    assert_eq "allow" "$result" "$stem.md ($agent_type) documented command is allowed: $cmd_json"
  done <<EOF
$commands
EOF
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
