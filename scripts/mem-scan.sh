#!/usr/bin/env bash
# scripts/mem-scan.sh — imprime un esqueleto de context-pack a stdout (spec §8.1, §4.4)
set -u

ROOT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root)
      [ $# -ge 2 ] || { echo "mem-scan.sh: --root requires a value" >&2; exit 1; }
      ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

echo "# context-pack"

stack="generic"
warning=""
if [ -f "$ROOT/composer.json" ] && grep -q "symfony/" "$ROOT/composer.json" 2>/dev/null; then
  stack="php-ddd-symfony8"
else
  warning="warning: stack no detectado con confianza → generic"
fi
echo "stack: $stack"
[ -n "$warning" ] && echo "$warning"

covers=""
for dir in src app lib; do
  if [ -d "$ROOT/$dir" ]; then
    if [ -n "$covers" ]; then
      covers="${covers},${dir}"
    else
      covers="$dir"
    fi
  fi
done
[ -z "$covers" ] && covers="src"
echo "covers: $covers"

echo ""
echo "## Tree"
find "$ROOT" -maxdepth 3 -type d \
  ! -path "$ROOT/vendor/*" ! -path "$ROOT/node_modules/*" ! -path "$ROOT/.git/*" ! -path "$ROOT/var/*" 2>/dev/null

echo ""
echo "## Entrypoints"
grep -rn -E 'function main|#\[Route|class .*Controller|Kernel' "$ROOT" --include=*.php 2>/dev/null | head -40

echo ""
echo "## Markers"
for marker in composer.json package.json go.mod Cargo.toml Gemfile requirements.txt pyproject.toml; do
  if [ -f "$ROOT/$marker" ]; then
    echo "- $marker"
  fi
done

echo ""
echo "## SHARED-FOUND"
