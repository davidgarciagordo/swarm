#!/usr/bin/env bash
# tests/test_bash_allowlist_verify.sh — read-only verification commands (jq, cmp, diff, sort, uniq,
# cut, tr, `php -l`; `docker exec` only in named buckets) are allowed, and each one's write/exec escape
# hatch is denied by shape (hooks/bash-guard.py, "Read-only verification commands").
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"
ALLOWLIST="$PLUGIN_ROOT/hooks/bash-allowlist.json"

# repo with a container allowlist (.swarm/docker-containers) — docker exec needs it
REPO="$(make_fixture)"
mkdir -p "$REPO/.swarm"
printf '# containers agents may docker exec into\nquantum\n' > "$REPO/.swarm/docker-containers"
NOCFG="$(make_fixture)"

guard() { # guard <agent_type> <command> [cwd] -> "allow" | "deny"
  local out
  out="$(python3 -c 'import json,sys; print(json.dumps({"agent_type": sys.argv[1], "tool_name": "Bash", "tool_input": {"command": sys.argv[2]}, "cwd": sys.argv[3]}))' "$1" "$2" "${3:-$REPO}" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# every bucket (agents + default) carries the full read-only verification set
missing="$(python3 - "$ALLOWLIST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
buckets = dict(data['agents'])
need = ['jq', 'cmp', 'diff', 'sort', 'uniq', 'cut', 'tr', 'php -l', 'docker exec', 'head', 'tail', 'wc']
if 'docker exec' in data['default']:
    print('default|docker exec must NOT be in default')
buckets['default'] = data['default'] + ['docker exec']
for name, prefixes in sorted(buckets.items()):
    for n in need:
        if n not in prefixes:
            print('%s|%s' % (name, n))
PYEOF
)"
assert_eq "" "$missing" "every allowlist bucket has the read-only verification set"
assert_eq "1" "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(int(any("php -r" in v for v in list(d["agents"].values())+[d["default"]])))' "$ALLOWLIST" | grep -qx 1 && echo 0 || echo 1)" "php -r is never allowlisted (inline code cannot be validated)"

A=swarm:verifier  # a strictly read-only agent

# --- positives: one per addition ---
assert_eq "allow" "$(guard $A 'jq -S . composer.json')" "jq read"
assert_eq "allow" "$(guard $A 'jq -r .version package.json | head -1')" "jq piped to head"
assert_eq "allow" "$(guard $A 'cmp a.json b.json')" "cmp"
assert_eq "allow" "$(guard $A 'diff -u a.txt b.txt')" "diff"
assert_eq "allow" "$(guard $A 'sort -u -k2,2 -t: list.txt')" "sort with read-only flags"
assert_eq "allow" "$(guard $A 'grep -h use src/A.php | sort | uniq -c')" "uniq -c on a pipe"
assert_eq "allow" "$(guard $A 'uniq -f 1 in.txt')" "uniq with a value flag and ONE operand"
assert_eq "allow" "$(guard $A 'cut -d: -f1 /etc/hosts')" "cut"
assert_eq "allow" "$(guard $A 'cat a | tr a-z A-Z')" "tr"
assert_eq "allow" "$(guard $A 'wc -l a | tail -1')" "wc + tail"
assert_eq "allow" "$(guard $A 'php -l src/App/Foo.php')" "php -l on a file"
assert_eq "allow" "$(guard $A 'docker exec quantum php -l src/App/Foo.php')" "docker exec with an allowed inner command"
assert_eq "allow" "$(guard $A 'docker exec quantum cat composer.json')" "docker exec cat"

assert_eq "allow" "$(guard $A 'git status 2>&1 | head -5')" "fd dup redirection stays allowed"
assert_eq "allow" "$(guard $A 'grep -rn x src 2>/dev/null')" "redirection to /dev/null stays allowed"
assert_eq "allow" "$(guard $A "grep -c '>' src/A.php")" "a quoted > is not a redirection"

# --- negatives: the escape hatch of each addition ---
assert_eq "deny" "$(guard swarm:blind-judge 'sort a > f')" "read-only agent cannot redirect output to a file"
assert_eq "deny" "$(guard swarm:blind-judge 'cat a >> f')" "read-only agent cannot append to a file"
assert_eq "deny" "$(guard swarm:blind-judge 'cat a >| f')" "read-only agent cannot clobber a file"
assert_eq "deny" "$(guard swarm:blind-judge 'cat a &> f')" "read-only agent cannot &> to a file"
assert_eq "deny" "$(guard swarm:blind-judge 'cat a >f')" "redirection without a space"
assert_eq "deny" "$(guard swarm:blind-judge 'cat a > >(tee f)')" "process substitution"
assert_eq "deny" "$(guard swarm:blind-judge 'docker exec quantum cat /x > y')" "docker exec output redirected to a file"
assert_eq "deny" "$(guard swarm:blind-judge 'git diff --output=F')" "git diff --output writes a file"
assert_eq "deny" "$(guard swarm:blind-judge 'git log -p --output F')" "git log --output writes a file"
assert_eq "deny" "$(guard swarm:blind-judge 'docker exec quantum git diff --output=F')" "git --output inside docker exec"
assert_eq "allow" "$(guard swarm:memory-builder 'cat a >> .swarm/context-pack.md')" "a file_writers agent keeps redirection"
assert_eq "deny" "$(guard swarm:some-unknown-agent 'docker exec quantum cat x')" "docker exec is not in the default bucket"
assert_eq "deny" "$(guard swarm:implementer 'docker exec quantum make')" "docker exec inner commands are read-only even for implementer"
assert_eq "allow" "$(guard swarm:implementer 'docker exec quantum cat composer.json')" "implementer docker exec read-only inner"
assert_eq "deny" "$(guard $A 'docker exec other cat composer.json')" "container not listed in .swarm/docker-containers"
assert_eq "deny" "$(guard $A 'docker exec quantum cat composer.json' "$NOCFG")" "no .swarm/docker-containers means no container is allowed"
assert_eq "deny" "$(guard $A 'sort -o out.txt in.txt')" "sort -o writes a file"
assert_eq "deny" "$(guard $A 'sort -uo out.txt in.txt')" "sort -o hidden in a short cluster"
assert_eq "deny" "$(guard $A 'sort --output=out.txt in.txt')" "sort --output"
assert_eq "deny" "$(guard $A 'sort --out=x in.txt')" "sort --output abbreviated"
assert_eq "deny" "$(guard $A 'sort --compress-program=/tmp/evil in.txt')" "sort --compress-program executes a program"
assert_eq "deny" "$(guard $A 'sort -T /tmp in.txt')" "sort -T writes temp files"
assert_eq "deny" "$(guard $A 'uniq in.txt out.txt')" "uniq OUTPUT operand overwrites a file"
assert_eq "deny" "$(guard $A 'uniq -c in.txt out.txt')" "uniq OUTPUT operand after flags"
assert_eq "deny" "$(guard $A 'php src/App/Foo.php')" "bare php (execution) stays denied"
assert_eq "deny" "$(guard $A 'php -l')" "php -l without a file"
assert_eq "deny" "$(guard $A 'php -l -d auto_prepend_file=/tmp/x.php src/A.php')" "php -l with extra flags"
assert_eq "deny" "$(guard $A 'php -r "system(1);"')" "php -r stays denied"
assert_eq "deny" "$(guard $A 'docker exec quantum rm -rf /app')" "docker exec with a disallowed inner command"
assert_eq "deny" "$(guard $A 'docker exec quantum sh -c "cat x"')" "docker exec into a shell"
assert_eq "deny" "$(guard $A 'docker exec -u root quantum cat /etc/shadow')" "docker exec with a flag"
assert_eq "deny" "$(guard $A 'docker exec --privileged quantum cat x')" "docker exec --privileged"
assert_eq "deny" "$(guard $A 'docker exec quantum docker exec other cat x')" "docker exec cannot nest"
assert_eq "deny" "$(guard $A 'docker exec quantum php x.php')" "docker exec cannot run php (only php -l)"
assert_eq "deny" "$(guard $A 'docker exec quantum')" "docker exec without an inner command"
assert_eq "deny" "$(guard $A 'docker run alpine cat x')" "docker run is not docker exec"
assert_eq "deny" "$(guard $A 'docker exec quantum cat "$(rm -rf x)"')" "outer substitution inside docker exec is still checked"
assert_eq "deny" "$(guard $A 'jq . a.json | sponge a.json')" "no in-place wrapper for jq"

# --- model tiers: every agent that spawns children can resolve a model; leaves cannot ---
for agent in orchestrator memory-orchestrator requirements-orchestrator discovery-orchestrator analysis-orchestrator design-orchestrator implementation-orchestrator delivery-orchestrator review-orchestrator; do
  assert_eq "allow" "$(guard "swarm:$agent" '${CLAUDE_PLUGIN_ROOT}/scripts/model-resolve.sh judgement --swarm-root /abs/.swarm')" "$agent can run model-resolve.sh"
done
for agent in delivery-orchestrator memory-orchestrator requirements-orchestrator; do
  for flag in '--swarm-root' '--mark-unavailable' '--escalate'; do
    assert_eq "0" "$(grep -F 'model-resolve.sh' "$PLUGIN_ROOT/agents/$agent.md" | grep -qF -- "$flag" && echo 0 || echo 1)" "$agent documents model-resolve.sh $flag (tier contract applied to its children)"
  done
done
assert_eq "deny" "$(guard swarm:security-auditor '${CLAUDE_PLUGIN_ROOT}/scripts/model-resolve.sh --mark-unavailable opus')" "a leaf cannot mark models unavailable"

# --- review panel buckets exist (no silent fallback to default, which allows find) ---
for agent in review-orchestrator completeness-critic fact-checker simplicity-critic refuter blind-judge; do
  assert_eq "deny" "$(guard "swarm:$agent" 'find . -name x')" "$agent has its own bucket (not the default fallback)"
  assert_eq "allow" "$(guard "swarm:$agent" 'jq -S . a.json')" "$agent can verify with jq"
done
assert_eq "allow" "$(guard swarm:review-orchestrator '${CLAUDE_PLUGIN_ROOT}/scripts/review-dedup.sh dedup --blocking')" "review-orchestrator can run review-dedup.sh"
assert_eq "deny" "$(guard swarm:fact-checker '${CLAUDE_PLUGIN_ROOT}/scripts/review-dedup.sh record --score 9')" "a lens cannot write judgements.jsonl"

# --- claude plugin: detection only ---
assert_eq "allow" "$(guard swarm:review-orchestrator 'claude plugin list')" "claude plugin list (working-methods detection)"
assert_eq "deny" "$(guard swarm:review-orchestrator 'claude plugin install evil@market')" "claude plugin install loads third-party code"
assert_eq "deny" "$(guard swarm:design-orchestrator 'claude plugin enable x')" "claude plugin enable"
assert_eq "deny" "$(guard swarm:design-orchestrator 'claude plugin list')" "design-orchestrator no longer detects plugins (review-orchestrator does)"

# --- file_writers == the agents whose tools: include Write or Edit ---
expected="$(for f in "$PLUGIN_ROOT"/agents/*.md; do awk '/^---$/{c++;next} c==1 && /^tools:/{print; exit}' "$f" | grep -qE '\b(Write|Edit)\b' && echo "swarm:$(basename "$f" .md)"; done | sort | tr '\n' ' ')"
actual="$(python3 -c 'import json,sys; print(" ".join(sorted(json.load(open(sys.argv[1]))["file_writers"])))' "$ALLOWLIST") "
assert_eq "$expected" "$actual" "file_writers lists exactly the agents with Write/Edit tools"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
