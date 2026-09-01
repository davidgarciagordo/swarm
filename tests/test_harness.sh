#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

fixture="$(make_fixture)"

assert_eq "0" "$( [ -d "$fixture/.git" ]; echo $? )" "fixture is a git repo"
assert_file_contains "$fixture/composer.json" "symfony/framework-bundle" "composer.json has symfony marker"
assert_eq "0" "$( [ -f "$fixture/src/App/Foo.php" ]; echo $? )" "Foo.php exists"
line_count="$(wc -l < "$fixture/src/App/Foo.php" | tr -d ' ')"
assert_eq "20" "$line_count" "Foo.php is 20 lines"

rm -rf "$fixture"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
