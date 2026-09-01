#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
LOCK_SCRIPT="$PLUGIN_ROOT/scripts/mem-lock.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

# --- 1. acquire+release cycle works ---
"$LOCK_SCRIPT" acquire
assert_eq "0" "$?" "acquire succeeds when lock free"
assert_eq "0" "$( [ -d "$SWARM_ROOT/.lock.d" ]; echo $? )" "lock dir exists after acquire"
"$LOCK_SCRIPT" release
assert_eq "1" "$( [ -d "$SWARM_ROOT/.lock.d" ]; echo $? )" "lock dir absent after release"

# --- 2. concurrent acquire: one waits, succeeds after the other releases ---
(
  "$LOCK_SCRIPT" acquire
  sleep 2
  "$LOCK_SCRIPT" release
) &
holder_pid=$!
sleep 0.2
start="$(date +%s)"
"$LOCK_SCRIPT" acquire
second_rc=$?
end="$(date +%s)"
"$LOCK_SCRIPT" release
wait "$holder_pid"
assert_eq "0" "$second_rc" "second acquire eventually succeeds"
waited=$((end - start))
assert_eq "0" "$( [ "$waited" -ge 1 ] && echo 0 || echo 1 )" "second acquire waited for first release (waited=${waited}s)"

# --- 3. orphaned lock older than 30s is reclaimed with a warning ---
mkdir -p "$SWARM_ROOT/.lock.d"
past=$(( $(date +%s) - 40 ))
backdate_stamp="$(date -r "$past" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$past" +%Y%m%d%H%M.%S)"
touch -t "$backdate_stamp" "$SWARM_ROOT/.lock.d"
warn_output="$("$LOCK_SCRIPT" acquire 2>&1 1>/dev/null)"
reclaim_rc=$?
"$LOCK_SCRIPT" release
assert_eq "0" "$reclaim_rc" "stale lock is reclaimed, acquire succeeds"
assert_eq "0" "$(echo "$warn_output" | grep -qi "stale" && echo 0 || echo 1)" "warning printed to stderr on reclaim"

# --- 4. a killed holder releases via trap; next acquire is fast (<2s), not 10s ---
cat > "$fixture/holder.sh" <<HOLDEREOF
#!/usr/bin/env bash
"$LOCK_SCRIPT" acquire
trap '"$LOCK_SCRIPT" release' EXIT INT TERM
sleep 5
HOLDEREOF
chmod +x "$fixture/holder.sh"
"$fixture/holder.sh" &
holder_pid=$!
sleep 0.2
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
start="$(date +%s)"
"$LOCK_SCRIPT" acquire
third_rc=$?
end="$(date +%s)"
"$LOCK_SCRIPT" release
elapsed=$((end - start))
assert_eq "0" "$third_rc" "acquire after killed holder succeeds"
assert_eq "0" "$( [ "$elapsed" -lt 2 ] && echo 0 || echo 1 )" "acquire after killed holder is fast (${elapsed}s, expected <2s not ~10s)"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
