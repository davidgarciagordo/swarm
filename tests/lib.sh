#!/usr/bin/env bash
# Helpers compartidos para smoke tests del plugin swarm (bash plano, sin framework).
set -euo pipefail

assert_eq() {
  [ "$1" = "$2" ] || { echo "FAIL: expected '$2', got '$1' (line $LINENO)"; exit 1; }
}

assert_file_contains() {
  grep -q -- "$2" "$1" || { echo "FAIL: '$2' not found in $1 (line $LINENO)"; exit 1; }
}

assert_file_not_exists() {
  [ ! -e "$1" ] || { echo "FAIL: '$1' should not exist (line $LINENO)"; exit 1; }
}

assert_exit() {
  local expected="$2"
  eval "$1" >/dev/null 2>&1
  local actual=$?
  [ "$actual" -eq "$expected" ] || { echo "FAIL: exit $actual != $expected (line $LINENO)"; exit 1; }
}

# Fixture mínimo: repo git temporal con un composer.json symfony.
# Uso: make_fixture /ruta  ->  crea y deja SWARM_FIXTURE apuntando a ella.
SWARM_FIXTURE=""
make_fixture() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@swarm.local"
  git -C "$dir" config user.name "Smoke Test"
  cat > "$dir/composer.json" <<'EOF'
{
  "require": { "symfony/framework-bundle": "^6.4" }
}
EOF
  mkdir -p "$dir/src/App"
  printf '<?php\nnamespace App;\nclass Foo { public function bar(): int { return 1; } }\n' > "$dir/src/App/Foo.php"
  git -C "$dir" add -A
  git -C "$dir" commit -qm "init"
  SWARM_FIXTURE="$dir"
}
