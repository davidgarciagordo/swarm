#!/usr/bin/env bash
# tests/test_swarm_status.sh — /swarm:status es DETERMINISTA (spec §11, principio 4): un script que
# lee .swarm/ y formatea, sin subagente y sin turno de modelo en el camino normal. Este test fija su
# contrato de salida COMPLETO —0 normal, 1 sin .swarm/, 2 datos no interpretables (ruling 12)—
# porque el 2 es lo que decide si el comando cae o no en su fallback: si el script se degradara en
# silencio (el viejo "tier: ?"), el fallback no se dispararía nunca y el usuario vería un dato falso.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SCRIPT="$PLUGIN_ROOT/scripts/swarm-status.sh"

assert_eq "0" "$([ -x "$SCRIPT" ] && echo 0 || echo 1)" "scripts/swarm-status.sh is executable"

root="$(mktemp -d "${TMPDIR:-/tmp}/swarm-status.XXXXXX")"
trap 'rm -rf "$root"' EXIT

# 1. sin .swarm/ → exit 1 con un mensaje accionable, nunca un stacktrace
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "1" "$rc" "exits 1 when .swarm/ does not exist"
assert_eq "0" "$(echo "$out" | grep -q 'swarm:init' && echo 0 || echo 1)" "and points the user at /swarm:init"

# 2. run real con agentes, summary y findings
mkdir -p "$root/.swarm/run/RUN1/agents" "$root/.swarm/findings"
printf '%s' "RUN1" > "$root/.swarm/run/current"
cat > "$root/.swarm/run/RUN1/run.json" <<JSON
{"id": "RUN1", "tier": "full", "started": "2026-09-03T10:00:00Z"}
JSON
cat > "$root/.swarm/run/RUN1/agents/release-manager.json" <<JSON
{"agent": "release-manager", "domain": "delivery", "area": ".", "owner": "delivery-orchestrator"}
JSON
cat > "$root/.swarm/run/RUN1/agents/orchestrator.json" <<JSON
{"agent": "orchestrator", "domain": "root", "area": ".", "owner": "orchestrator"}
JSON
echo "- run cerrado: DONE · fase implementada" > "$root/.swarm/run/RUN1/summary.md"
echo '- [key:reviewer|REVIEW|src/A.php:10] [sha:abc] [status:open] [run:RUN1] REVIEW · src/A.php:10 · algo → fix' > "$root/.swarm/findings/reviewer.md"
echo '- [key:reviewer|REVIEW|src/B.php:20] [sha:abc] [status:resolved] [run:RUN1] REVIEW · src/B.php:20 · otro → fix' >> "$root/.swarm/findings/reviewer.md"

out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "0" "$rc" "exits 0 with a real run present"
assert_eq "0" "$(echo "$out" | grep -q 'RUN1' && echo 0 || echo 1)" "reports the current run id"
assert_eq "0" "$(echo "$out" | grep -q 'full' && echo 0 || echo 1)" "reports the tier"
assert_eq "0" "$(echo "$out" | grep -q '2026-09-03T10:00:00Z' && echo 0 || echo 1)" "reports the start timestamp"
assert_eq "0" "$(echo "$out" | grep -q 'release-manager' && echo 0 || echo 1)" "lists the registered agents"
assert_eq "0" "$(echo "$out" | grep -q 'delivery' && echo 0 || echo 1)" "lists each agent's domain"
assert_eq "0" "$(echo "$out" | grep -q 'fase implementada' && echo 0 || echo 1)" "echoes the run summary lines"
assert_eq "0" "$(echo "$out" | grep -qE 'abiertos?: *1' && echo 0 || echo 1)" "counts ONLY open findings (1 of 2)"

# 3. .swarm/ sin ningún run → exit 0, sin ruido
root2="$(mktemp -d "${TMPDIR:-/tmp}/swarm-status2.XXXXXX")"
mkdir -p "$root2/.swarm"
out="$(SWARM_ROOT="$root2/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
rm -rf "$root2"
assert_eq "0" "$rc" "exits 0 on an initialised but never-run .swarm/"
assert_eq "0" "$(echo "$out" | grep -q 'sin runs' && echo 0 || echo 1)" "says plainly that there are no runs yet"

# 4. run.json presente pero malformado → exit 2 (el residual del ruling 12), NUNCA un "tier: ?" mudo
printf '%s' '{"id": "RUN1", "tier":' > "$root/.swarm/run/RUN1/run.json"
out="$(SWARM_ROOT="$root/.swarm" bash "$SCRIPT" 2>&1)"; rc=$?
assert_eq "2" "$rc" "exits 2 when run.json exists but cannot be parsed"
assert_eq "0" "$(echo "$out" | grep -q 'no interpretable' && echo 0 || echo 1)" "and says which file it could not read"
assert_eq "0" "$(echo "$out" | grep -q 'RUN1' && echo 0 || echo 1)" "while still printing everything it COULD read"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
