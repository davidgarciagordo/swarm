#!/usr/bin/env bash
# tests/test_no_model_names_in_agents.sh — MODEL TIERS contract: model ids live ONLY in
# models.json (and docs). Agents declare `model: inherit` + `tier: judgement|standard|mechanical`;
# orchestrators resolve the real id with scripts/model-resolve.sh.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

NAMES='(opus|sonnet|haiku|fable|gpt|gemini)'

files="$(find "$PLUGIN_ROOT/agents" "$PLUGIN_ROOT/skills" -type f -name '*.md' | sort)"
for f in $files; do
  rel="${f#$PLUGIN_ROOT/}"
  hits="$(grep -niwE "$NAMES" "$f" | head -3 | tr '\n' ' ')"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "$hits" ]; then
    echo "FAIL: $rel names a model (move it to models.json / use a tier): $hits" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
done

for f in "$PLUGIN_ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f")"
  assert_eq "model: inherit" "$(echo "$frontmatter" | grep '^model:' | sed 's/[[:space:]]*$//')" "$name frontmatter model: inherit"
  tier="$(echo "$frontmatter" | sed -n 's/^tier:[[:space:]]*\([a-z]*\)[[:space:]]*$/\1/p')"
  case "$tier" in
    judgement|standard|mechanical) ok=0 ;;
    *) ok=1 ;;
  esac
  assert_eq "0" "$ok" "$name frontmatter tier is judgement|standard|mechanical (got [$tier])"
done

if [ "$TESTS_FAILED" -gt 0 ]; then echo "failed: $TESTS_FAILED/$TESTS_RUN" >&2; exit 1; fi
exit 0
