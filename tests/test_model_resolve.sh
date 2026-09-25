#!/usr/bin/env bash
# tests/test_model_resolve.sh — scripts/model-resolve.sh: tier -> model id, deterministic.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MR="$PLUGIN_ROOT/scripts/model-resolve.sh"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/model-resolve.XXXXXX")"
SR="$TMP/.swarm"
mkdir -p "$SR"

# plugin models.json matches the shared contract exactly
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert d == {'tiers': {'judgement': ['opus', 'fable', 'inherit'], 'standard': ['sonnet', 'inherit'], 'mechanical': ['sonnet', 'inherit']}, 'escalation': {'mechanical': 'standard', 'standard': 'judgement'}}, d
" "$PLUGIN_ROOT/models.json"
assert_eq "0" "$?" "models.json matches the tier contract"

# 1. resolution order: first candidate
assert_eq "opus" "$("$MR" judgement --swarm-root "$SR")" "judgement -> opus"
assert_eq "sonnet" "$("$MR" standard --swarm-root "$SR")" "standard -> sonnet"
assert_eq "sonnet" "$("$MR" mechanical --swarm-root "$SR")" "mechanical -> sonnet"

# 2. unavailable skips to the next candidate
assert_eq "marked: opus" "$("$MR" --mark-unavailable opus --swarm-root "$SR")" "mark opus unavailable"
assert_eq "already: opus" "$("$MR" --mark-unavailable opus --swarm-root "$SR")" "mark is idempotent"
assert_eq "1" "$(grep -c '^opus ' "$SR/models.unavailable")" "opus listed once"
assert_eq "0" "$(grep -qE '^opus [0-9]+ adhoc$' "$SR/models.unavailable" && echo 0 || echo 1)" "a mark is stamped with epoch + run-id"
assert_eq "fable" "$("$MR" judgement --swarm-root "$SR")" "opus unavailable -> fable"

# 3. judgement never downgrades: exhausted => inherit, never sonnet (standard's list)
"$MR" --mark-unavailable fable --swarm-root "$SR" >/dev/null
assert_eq "inherit" "$("$MR" judgement --swarm-root "$SR")" "judgement exhausted -> inherit, not sonnet"
assert_eq "sonnet" "$("$MR" standard --swarm-root "$SR")" "standard unaffected by judgement marks"
# same rule with a list WITHOUT inherit (else the trailing inherit hides a downgrade bug)
SRJ="$TMP/nj/.swarm"; mkdir -p "$SRJ"
echo '{"tiers":{"judgement":["opus","fable"]}}' > "$SRJ/models.json"
printf 'opus\nfable\n' > "$SRJ/models.unavailable"
assert_eq "inherit" "$("$MR" judgement --swarm-root "$SRJ")" "judgement without inherit exhausted -> inherit, never standard's sonnet"

# 4. inherit fallback for standard/mechanical
"$MR" --mark-unavailable sonnet --swarm-root "$SR" >/dev/null
assert_eq "inherit" "$("$MR" standard --swarm-root "$SR")" "standard exhausted -> inherit"
assert_eq "inherit" "$("$MR" mechanical --swarm-root "$SR")" "mechanical exhausted -> inherit"
assert_exit "64" "inherit cannot be marked unavailable" "$MR" --mark-unavailable inherit --swarm-root "$SR"

# 5. project override wins (per tier), unavailable still applies
SR2="$TMP/o/.swarm"; mkdir -p "$SR2"
cat > "$SR2/models.json" <<'JSONEOF'
{ "tiers": { "judgement": ["vendor-big", "vendor-mid", "inherit"], "mechanical": ["vendor-small"] } }
JSONEOF
assert_eq "vendor-big" "$("$MR" judgement --swarm-root "$SR2")" "override judgement wins"
assert_eq "sonnet" "$("$MR" standard --swarm-root "$SR2")" "tier absent from override keeps plugin list"
assert_eq "vendor-small" "$("$MR" mechanical --swarm-root "$SR2")" "override mechanical wins"
"$MR" --mark-unavailable vendor-small --swarm-root "$SR2" >/dev/null
assert_eq "inherit" "$("$MR" mechanical --swarm-root "$SR2")" "override list exhausted -> inherit"

# 6. SWARM_ROOT env is the default swarm-root
assert_eq "vendor-big" "$(SWARM_ROOT="$SR2" "$MR" judgement)" "SWARM_ROOT env used when no --swarm-root"

# 7. escalate
assert_eq "judgement" "$("$MR" --escalate mechanical)" "mechanical skips standard: both resolve to the same model"
SRE="$TMP/e/.swarm"; mkdir -p "$SRE"
echo '{"tiers":{"mechanical":["haiku"]}}' > "$SRE/models.json"
assert_eq "standard" "$("$MR" --escalate mechanical --swarm-root "$SRE")" "mechanical escalates to standard when their models differ"
assert_eq "judgement" "$("$MR" --escalate standard)" "standard escalates to judgement"
assert_eq "judgement" "$("$MR" --escalate judgement)" "judgement escalates to itself"
cat > "$SR2/models.json" <<'JSONEOF'
{ "tiers": {}, "escalation": { "standard": "mechanical" } }
JSONEOF
assert_eq "standard" "$("$MR" --escalate standard --swarm-root "$SR2")" "escalation never goes down"

# 8. judge independence (--avoid)
SR3="$TMP/j/.swarm"; mkdir -p "$SR3"
assert_eq "fable" "$("$MR" judgement --avoid opus --swarm-root "$SR3")" "avoid producer -> next distinct candidate"
"$MR" --mark-unavailable fable --swarm-root "$SR3" >/dev/null
note="$("$MR" judgement --avoid opus --swarm-root "$SR3" 2>&1 >/dev/null)"
assert_eq "inherit" "$("$MR" judgement --avoid opus --swarm-root "$SR3" 2>/dev/null)" "no independent candidate -> inherit"
assert_eq "0" "$(echo "$note" | grep -q 'independent' && echo 0 || echo 1)" "no independent candidate -> note on stderr"

assert_eq "opus" "$("$MR" judgement --avoid inherit --swarm-root "$TMP/j2/.swarm" 2>/dev/null)" "avoid inherit (unknown producer) -> plain resolution"
note="$("$MR" judgement --avoid inherit --swarm-root "$TMP/j2/.swarm" 2>&1 >/dev/null)"
assert_eq "0" "$(echo "$note" | grep -q 'not guaranteed' && echo 0 || echo 1)" "avoid inherit -> independence-not-guaranteed note"

# 8b. --mark-unavailable is confined and expires
assert_exit "64" "mark refuses a swarm-root not named .swarm" "$MR" --mark-unavailable opus --swarm-root "$TMP"
assert_exit "64" "mark refuses a non-existent .swarm" "$MR" --mark-unavailable opus --swarm-root "$TMP/nope/.swarm"
assert_eq "0" "$([ -e "$TMP/nope" ] && echo 1 || echo 0)" "mark never creates directories"
SRT="$TMP/t/.swarm"; mkdir -p "$SRT"
echo "opus 1000 old-run" > "$SRT/models.unavailable"
assert_eq "opus" "$("$MR" judgement --swarm-root "$SRT")" "an expired stamped mark is ignored"
assert_eq "marked: opus" "$("$MR" --mark-unavailable opus --swarm-root "$SRT")" "an expired mark can be re-marked"
assert_eq "fable" "$("$MR" judgement --swarm-root "$SRT")" "the fresh mark applies"
assert_eq "fable" "$(SWARM_MODEL_UNAVAILABLE_TTL=0 "$MR" judgement --swarm-root "$SRT")" "TTL=0 is clamped to 1: a fresh mark still applies"
echo "opus $(( $(date +%s) - 5 )) r" > "$SRT/models.unavailable"
assert_eq "opus" "$(SWARM_MODEL_UNAVAILABLE_TTL=3 "$MR" judgement --swarm-root "$SRT")" "TTL is configurable"

# 9. --show one line per tier
show="$("$MR" --show --swarm-root "$SR3")"
assert_eq "3" "$(echo "$show" | wc -l | tr -d ' ')" "--show prints 3 tiers"
assert_eq "0" "$(echo "$show" | grep -q '^judgement opus candidates=opus,fable,inherit unavailable=fable$' && echo 0 || echo 1)" "--show reports effective + unavailable"

# 10. usage errors
assert_exit "64" "unknown tier rejected" "$MR" huge --swarm-root "$SR3"
assert_exit "64" "missing tier rejected" "$MR" --swarm-root "$SR3"
echo 'not json' > "$SR3/models.json"
assert_exit "64" "malformed override rejected" "$MR" judgement --swarm-root "$SR3"
echo '{"tiers":{"judgement":[]}}' > "$SR3/models.json"
assert_exit "64" "empty candidate list rejected" "$MR" judgement --swarm-root "$SR3"

rm -rf "$TMP"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
