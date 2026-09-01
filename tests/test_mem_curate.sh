#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_FILES="$PLUGIN_ROOT/scripts/mem-files.sh"
MEM_CURATE="$PLUGIN_ROOT/scripts/mem-curate.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 6 \
  --run adhoc --text "comentario cambiante" --fix "sin fix real" >/dev/null
"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 7 \
  --run adhoc --text "otro comentario" --fix "sin cambios" >/dev/null

sed -i.bak '6s/.*/    \/\/ line 1 EDITADA/' "$fixture/src/App/Foo.php"
rm -f "$fixture/src/App/Foo.php.bak"

"$MEM_CURATE" resolve >/dev/null

findings_file="$SWARM_ROOT/findings/architecture-auditor.md"
line6_status="$(grep 'Foo.php:6' "$findings_file")"
line7_status="$(grep 'Foo.php:7' "$findings_file")"

assert_eq "0" "$(echo "$line6_status" | grep -q '\[status:resolved\]' && echo 0 || echo 1)" "changed cited line becomes resolved"
assert_eq "0" "$(echo "$line7_status" | grep -q '\[status:open\]' && echo 0 || echo 1)" "unchanged cited line stays open"

# --- prune: drops resolved findings older than N days, keeps recent resolved and open ---
old_date="$(date -u -v-40d +"%Y-%m-%d" 2>/dev/null || date -u -d '40 days ago' +"%Y-%m-%d")"
recent_date="$(date -u -v-1d +"%Y-%m-%d" 2>/dev/null || date -u -d '1 day ago' +"%Y-%m-%d")"

cat > "$findings_file" <<EOF
- [key:architecture-auditor|ARCH|src/App/Foo.php:6] [sha:deadbeef] [status:resolved] [resolved:${old_date}] ARCH · src/App/Foo.php:6 · viejo resuelto → fix
- [key:architecture-auditor|ARCH|src/App/Foo.php:7] [sha:cafebabe] [status:resolved] [resolved:${recent_date}] ARCH · src/App/Foo.php:7 · reciente resuelto → fix
- [key:architecture-auditor|ARCH|src/App/Foo.php:8] [sha:12345678] [status:open] [run:adhoc] ARCH · src/App/Foo.php:8 · abierto → fix
EOF

"$MEM_CURATE" prune --days 30 >/dev/null

assert_eq "1" "$(grep -q 'Foo.php:6' "$findings_file" && echo 0 || echo 1)" "prune drops resolved entry older than N days"
assert_eq "0" "$(grep -q 'Foo.php:7' "$findings_file" && echo 0 || echo 1)" "prune keeps resolved entry within N days"
assert_eq "0" "$(grep -q 'Foo.php:8' "$findings_file" && echo 0 || echo 1)" "prune keeps open entries regardless of age"

# --- gc: delegates to mem-manifest.sh gc --keep 10 ---
mkdir -p "$SWARM_ROOT/run/adhoc"
for i in $(seq 1 12); do
  rid="fixture-run-$i"
  mkdir -p "$SWARM_ROOT/run/$rid"
  printf '{"id": "%s", "tier": "light", "started": "2026-01-%02dT00:00:00Z"}\n' "$rid" "$i" > "$SWARM_ROOT/run/$rid/run.json"
done

"$MEM_CURATE" gc >/dev/null

remaining="$(find "$SWARM_ROOT/run" -maxdepth 1 -type d -name 'fixture-run-*' | wc -l | tr -d ' ')"
assert_eq "10" "$remaining" "gc keeps the 10 most recent fixture runs"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/adhoc" ]; echo $? )" "gc never removes adhoc"
assert_eq "1" "$( [ -d "$SWARM_ROOT/run/fixture-run-1" ]; echo $? )" "gc removes oldest run (fixture-run-1)"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/fixture-run-12" ]; echo $? )" "gc keeps newest run (fixture-run-12)"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
