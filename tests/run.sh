#!/usr/bin/env bash
# tests/run.sh — runs every tests/test_*.sh and tests/test_*.py; exit 1 if any file fails.
# Tests check STRUCTURE and BEHAVIOUR, never wording: see tests/test_structure.py and the seeded
# generative tests (*_fuzz.py, test_guard.py). SWARM_TEST_SEED / SWARM_FUZZ_N widen a fuzz run.
set -u
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PLUGIN_ROOT" || exit 1
export PYTHONDONTWRITEBYTECODE=1

total_files=0
failed_files=0
start=$(date +%s)

for f in tests/test_*.sh tests/test_*.py; do
  [ -f "$f" ] || continue
  total_files=$((total_files + 1))
  echo "== $f =="
  case "$f" in
    *.py) runner=python3 ;;
    *) runner=bash ;;
  esac
  if "$runner" "$f"; then
    echo "PASS: $f"
  else
    echo "FAIL: $f"
    failed_files=$((failed_files + 1))
  fi
done

echo ""
echo "files: $total_files, failed: $failed_files, seconds: $(( $(date +%s) - start ))"
if [ "$failed_files" -gt 0 ]; then
  exit 1
fi
exit 0
