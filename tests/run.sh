#!/usr/bin/env bash
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1

total_files=0
failed_files=0

for f in tests/test_*.sh; do
  [ -f "$f" ] || continue
  total_files=$((total_files + 1))
  echo "== $f =="
  if bash "$f"; then
    echo "PASS: $f"
  else
    echo "FAIL: $f"
    failed_files=$((failed_files + 1))
  fi
done

echo ""
echo "files: $total_files, failed: $failed_files"
if [ "$failed_files" -gt 0 ]; then
  exit 1
fi
exit 0
