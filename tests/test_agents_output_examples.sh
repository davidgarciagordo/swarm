#!/usr/bin/env bash
# tests/test_agents_output_examples.sh — cada bloque de código dentro de la sección "## Salida"
# de agents/*.md que empiece por un veredicto (OK|KO|DONE|BLOCKED) se pasa LITERALMENTE por
# hooks/validate-output.py. Si el hook lo rechazaría en runtime, el ejemplo miente y el agente
# que lo copie fallará su primera salida. Glob dinámico: cubre agentes futuros.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/swarm-outex.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
# SWARM_ROOT apunta a un dir inexistente a propósito: el hook no debe sembrar retries en el repo.
export SWARM_ROOT="$TMP/no-swarm"

for f in "$PLUGIN_ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f" .md)"
  blkdir="$TMP/$name"
  mkdir -p "$blkdir"
  awk -v dir="$blkdir" '
    /^## ([0-9]+\.[ ]+)?Salida/ { insec=1; next }
    insec && /^## / { insec=0 }
    insec && /^```/ {
      if (inblk) { inblk=0; close(out) }
      else { inblk=1; n++; out=sprintf("%s/block-%02d.txt", dir, n) }
      next
    }
    insec && inblk { print > out }
  ' "$f"
  found=0
  for blk in "$blkdir"/block-*.txt; do
    [ -f "$blk" ] || continue
    first="$(head -1 "$blk")"
    case "$first" in
      OK|KO\ *|DONE|BLOCKED\ *) ;;
      *) continue ;;
    esac
    found=$((found + 1))
    out="$(python3 -c 'import json,sys; print(json.dumps({"agent_type": "swarm:"+sys.argv[1], "last_assistant_message": open(sys.argv[2]).read()}))' "$name" "$blk" | python3 "$HOOK")"
    assert_eq "1" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "$name: ejemplo $(basename "$blk") pasa validate-output.py (salida del hook: ${out:-<vacía>})"
  done
  assert_eq "0" "$([ "$found" -ge 1 ] && echo 0 || echo 1)" "$name: la sección '## Salida' tiene al menos un ejemplo con veredicto"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
