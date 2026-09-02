#!/usr/bin/env bash
# tests/test_req_check.sh — scripts/req-check.sh (Task 2, spec §7)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
REQ_CHECK="$PLUGIN_ROOT/scripts/req-check.sh"

fixture="$(make_fixture)"

# 1. tool siempre presente, required -> ok:true, exit 0
cat > "$fixture/req-ok.json" <<'JSONEOF'
{ "os": [ {"tool":"ls","required":true} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-ok.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "always-present required tool -> exit 0"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": true' && echo 0 || echo 1)" "ok:true in report"

# 2. tool inventada, required -> ok:false, exit 1, hint presente
cat > "$fixture/req-missing-required.json" <<'JSONEOF'
{ "os": [ {"tool":"swarm-fake-tool-zzz","required":true,"install":{"brew":"swarm-fake","apt":"swarm-fake"}} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-missing-required.json" --root "$fixture")"
rc=$?
assert_eq "1" "$rc" "missing required tool -> exit 1"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": false' && echo 0 || echo 1)" "ok:false in report"
assert_eq "0" "$(echo "$out" | grep -q 'swarm-fake-tool-zzz' && echo 0 || echo 1)" "missing tool named in report"
assert_eq "0" "$(echo "$out" | grep -q 'missing_required' && echo 0 || echo 1)" "missing_required key present"

# 3. tool inventada, NOT required -> ok:true, aparece en missing_optional
cat > "$fixture/req-missing-optional.json" <<'JSONEOF'
{ "os": [ {"tool":"swarm-fake-tool-yyy","required":false} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-missing-optional.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "missing optional tool -> still exit 0"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": true' && echo 0 || echo 1)" "ok:true when only optional missing"
assert_eq "0" "$(echo "$out" | grep -q 'missing_optional' && echo 0 || echo 1)" "missing_optional key present"
assert_eq "0" "$(echo "$out" | grep -q 'swarm-fake-tool-yyy' && echo 0 || echo 1)" "optional missing tool named"

# 4. project file presente/ausente, con --root
cat > "$fixture/req-project.json" <<'JSONEOF'
{ "os": [], "project": [ {"file":"composer.json","required":true}, {"file":"nope-does-not-exist.txt","required":false} ], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-project.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "present required project file passes; absent one is only optional"
assert_eq "0" "$(echo "$out" | grep -q 'nope-does-not-exist.txt' && echo 0 || echo 1)" "absent optional project file listed in report"

# 5. min version por debajo de lo instalado -> ok:false, exit 1 (python3 siempre presente aqui)
cat > "$fixture/req-version-fail.json" <<'JSONEOF'
{ "os": [ {"tool":"python3","required":true,"min":"99.0"} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-version-fail.json" --root "$fixture")"
rc=$?
assert_eq "1" "$rc" "python3 present but below an inflated min -> exit 1"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": false' && echo 0 || echo 1)" "ok:false when version below min"
assert_eq "0" "$(echo "$out" | grep -q 'python3' && echo 0 || echo 1)" "python3 named in missing_required for version failure"

# 6. min version trivial -> ok:true
cat > "$fixture/req-version-ok.json" <<'JSONEOF'
{ "os": [ {"tool":"python3","required":true,"min":"1.0"} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-version-ok.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "python3 present and above a trivial min -> exit 0"

# 7. libs: stub que nunca falla, siempre "unknown" en missing_optional
cat > "$fixture/req-libs.json" <<'JSONEOF'
{ "os": [], "project": [], "libs": [ {"name":"phpstan/phpstan","manager":"composer","min":"2.1","required":false} ] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-libs.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "libs entries never fail (no pack yet, fase 5)"
assert_eq "0" "$(echo "$out" | grep -q 'phpstan/phpstan' && echo 0 || echo 1)" "libs entry named as unknown"

# 8. fichero de requirements inexistente -> exit 64 (uso incorrecto)
"$REQ_CHECK" --file "$fixture/does-not-exist.json" >/dev/null 2>&1
assert_eq "64" "$?" "missing requirements file -> exit 64"

# 9. --file sin valor no revienta bajo set -u, sale con exit no-cero limpio
"$REQ_CHECK" --file >/dev/null 2>&1
file_flag_exit=$?
assert_eq "0" "$([ "$file_flag_exit" -ne 0 ] && echo 0 || echo 1)" "--file with no value exits non-zero cleanly"

# 10. default --file (requirements.json del propio plugin, Task 1) produce JSON bien formado
out="$("$REQ_CHECK" --root "$fixture")"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert set(['ok', 'missing_required', 'missing_optional', 'checked']) <= set(d.keys())
" "$out"
assert_eq "0" "$?" "default --file (plugin's own requirements.json) produces well-shaped JSON"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
