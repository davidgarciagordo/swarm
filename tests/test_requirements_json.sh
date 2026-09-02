#!/usr/bin/env bash
# tests/test_requirements_json.sh — requirements.json del plugin (T1, spec §7) + registro de
# /swarm:doctor en el manifest.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert set(['os', 'project', 'libs']) <= set(d.keys()), 'missing top-level keys'
assert isinstance(d['os'], list) and isinstance(d['project'], list) and isinstance(d['libs'], list)
tools = [i.get('tool') for i in d['os']]
for required_tool in ('git', 'python3', 'uuidgen'):
    assert required_tool in tools, 'missing os entry: ' + required_tool
    item = [i for i in d['os'] if i.get('tool') == required_tool][0]
    assert item.get('required') is True, required_tool + ' must be required: true'
for optional_tool in ('jq', 'gh', 'docker'):
    assert optional_tool in tools, 'missing os entry: ' + optional_tool
    item = [i for i in d['os'] if i.get('tool') == optional_tool][0]
    assert item.get('required') is False, optional_tool + ' must be required: false'
" "$PLUGIN_ROOT/requirements.json"
assert_eq "0" "$?" "requirements.json is valid JSON with os/project/libs and the expected entries"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if './commands/doctor.md' in d.get('commands', []) else 1)
" "$PLUGIN_ROOT/.claude-plugin/plugin.json"
assert_eq "0" "$?" "plugin.json commands array includes ./commands/doctor.md"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
