#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_MANIFEST="$PLUGIN_ROOT/scripts/mem-manifest.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

run_id="$("$MEM_MANIFEST" open --tier light)"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/$run_id/agents" ] && [ -d "$SWARM_ROOT/run/$run_id/mailbox" ] && [ -d "$SWARM_ROOT/run/$run_id/retries" ]; echo $? )" "open creates full run layout"
current="$("$MEM_MANIFEST" current)"
assert_eq "$run_id" "$current" "current points at opened run"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('tier')=='light' else 1)" "$SWARM_ROOT/run/$run_id/run.json"
assert_eq "0" "$?" "run.json has correct tier"

"$MEM_MANIFEST" register --run "$run_id" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator >/dev/null
"$MEM_MANIFEST" register --run "$run_id" --agent security-auditor --domain analysis --area "src/App" --owner orchestrator >/dev/null
assert_eq "0" "$( [ -f "$SWARM_ROOT/run/$run_id/agents/architecture-auditor.json" ] && [ -f "$SWARM_ROOT/run/$run_id/agents/security-auditor.json" ]; echo $? )" "register writes distinct per-agent files"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('agent')=='architecture-auditor' else 1)" "$SWARM_ROOT/run/$run_id/agents/architecture-auditor.json"
assert_eq "0" "$?" "architecture-auditor.json not clobbered by security-auditor registration"

# gc keeps 10 most recent + always keeps adhoc
mkdir -p "$SWARM_ROOT/run/adhoc"
for i in $(seq 1 12); do
  rid="fixture-run-$i"
  mkdir -p "$SWARM_ROOT/run/$rid"
  printf '{"id": "%s", "tier": "light", "started": "2026-01-%02dT00:00:00Z"}\n' "$rid" "$i" > "$SWARM_ROOT/run/$rid/run.json"
done
"$MEM_MANIFEST" gc --keep 10 >/dev/null
remaining="$(find "$SWARM_ROOT/run" -maxdepth 1 -type d -name 'fixture-run-*' | wc -l | tr -d ' ')"
assert_eq "10" "$remaining" "gc keeps the 10 most recent fixture runs"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/adhoc" ]; echo $? )" "gc never removes adhoc"
assert_eq "1" "$( [ -d "$SWARM_ROOT/run/fixture-run-1" ]; echo $? )" "gc removes oldest run (fixture-run-1)"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/fixture-run-12" ]; echo $? )" "gc keeps newest run (fixture-run-12)"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
