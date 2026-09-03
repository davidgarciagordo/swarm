#!/usr/bin/env bash
# tests/lib.sh — shared test helpers (bash 3.2 compatible, no arrays)
set -u

TESTS_RUN=0
TESTS_FAILED=0

# make_fixture [DIR]
# Creates a tmp git repo at DIR (or a fresh mktemp dir) with:
#   - an initial commit
#   - composer.json containing "symfony/framework-bundle"
#   - src/App/Foo.php, 20 lines
# Prints the fixture path to stdout.
make_fixture() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then
    dir="$(mktemp -d "${TMPDIR:-/tmp}/swarm-fixture.XXXXXX")"
  fi
  mkdir -p "$dir/src/App"
  (
    cd "$dir" || exit 1
    git init -q
    git config user.email "test@swarm.local"
    git config user.name "swarm-tests"
    cat > composer.json <<'JSONEOF'
{
  "name": "swarm/fixture",
  "require": {
    "php": "^8.2",
    "symfony/framework-bundle": "^6.4"
  }
}
JSONEOF
    {
      echo "<?php"
      echo ""
      echo "namespace App;"
      echo ""
      echo "class Foo"
      echo "{"
      for i in $(seq 1 13); do
        echo "    // line $i"
      done
      echo "}"
    } > src/App/Foo.php
    mkdir -p "$dir/src/Controller"
    {
      echo "<?php"
      echo ""
      echo "namespace App\\Controller;"
      echo ""
      echo "use App\\Foo;"
      echo ""
      echo "class InvoiceController"
      echo "{"
      echo "    public function export()"
      echo "    {"
      echo "        \$pdo = new \\PDO('sqlite::memory:');"
      echo "        \$rows = \$pdo->query('SELECT * FROM invoices')->fetchAll();"
      echo "        foreach (\$rows as \$row) {"
      echo "            \$pdo->query('SELECT * FROM tenants WHERE id = ' . \$row['tenant_id']);"
      echo "        }"
      echo "        return \$rows;"
      echo "    }"
      echo "}"
    } > src/Controller/InvoiceController.php
    mkdir -p tests/Unit
    {
      echo "<?php"
      echo ""
      echo "namespace Tests\\Unit;"
      echo ""
      echo "use PHPUnit\\Framework\\TestCase;"
      echo "use App\\Foo;"
      echo ""
      echo "class FooTest extends TestCase"
      echo "{"
      echo "    public function testFooExists(): void"
      echo "    {"
      echo "        \$this->assertTrue(class_exists(Foo::class));"
      echo "    }"
      echo "}"
    } > tests/Unit/FooTest.php
    git add -A
    git commit -q -m "chore: initial fixture commit"
  )
  echo "$dir"
}

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-assert_eq}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $msg — expected [$expected] got [$actual]" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  return 0
}

assert_file_contains() {
  local file="$1" pattern="$2" msg="${3:-assert_file_contains}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ ! -f "$file" ]; then
    echo "FAIL: $msg — file not found: $file" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  if ! grep -q -- "$pattern" "$file"; then
    echo "FAIL: $msg — pattern [$pattern] not found in $file" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  return 0
}

assert_exit() {
  local expected="$1"; shift
  local msg="$1"; shift
  TESTS_RUN=$((TESTS_RUN + 1))
  "$@"
  local actual=$?
  if [ "$expected" != "$actual" ]; then
    echo "FAIL: $msg — expected exit [$expected] got [$actual]" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
    return 1
  fi
  return 0
}
