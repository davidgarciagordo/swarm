# commands — php-ddd-symfony8

Canonical forms of this stack's deterministic commands (`lint | fix | typecheck |
test | test-one | scan-deps | scan-secrets | sast`, plus the migration and license keys this
stack needs). **Every form is written to pass `hooks/bash-guard.py` with the allowlist of the
agent named in the `executor` column** — `tests/test_stack_pack.sh` verifies it row by row.
If you add a row, also add the corresponding prefix to its executor's allowlist, or the test
fails (which is exactly what should happen).

This ecosystem's tools aren't unique: the `condition` column says which one you pick. **The
first row whose condition holds wins**; if none holds for a given key, that key has
no command in this repo and the leaf says so explicitly instead of making one up.

| key | condition | command | executor |
|---|---|---|---|
| lint | `ecs.php` exists | `php vendor/bin/ecs check --no-progress-bar` | quality-fixer |
| lint | `.php-cs-fixer.dist.php` or `.php-cs-fixer.php` exists | `php vendor/bin/php-cs-fixer fix --dry-run --diff` | quality-fixer |
| fix | `ecs.php` exists | `php vendor/bin/ecs check --fix --no-progress-bar` | quality-fixer |
| fix | `.php-cs-fixer.dist.php` or `.php-cs-fixer.php` exists | `php vendor/bin/php-cs-fixer fix` | quality-fixer |
| fix | `rector.php` exists (runs BEFORE the formatter) | `php vendor/bin/rector process` | quality-fixer |
| typecheck | `phpstan.dist.neon` or `phpstan.neon` exists | `php vendor/bin/phpstan analyse --no-progress --error-format=raw` | quality-fixer |
| test | `phpunit.xml.dist` or `phpunit.xml` exists | `php vendor/bin/phpunit` | test-writer + implementer + release-manager |
| test | `vendor/bin/paratest` also exists (large suite) | `php vendor/bin/paratest --processes=4` | implementer + release-manager |
| test-one | whenever PHPUnit is present | `php vendor/bin/phpunit --filter <TestName> <path/to/Test.php>` | test-writer + implementer |
| scan-deps | `composer.lock` exists | `composer audit --format=json` | dependency-auditor + vulnerability-scanner |
| outdated | `composer.lock` exists | `composer outdated --direct --format=json` | dependency-auditor |
| licenses | `composer.lock` exists | `composer licenses --format=json` | dependency-auditor + vulnerability-scanner |
| scan-secrets | always | `grep -rnE "(APP_SECRET|DATABASE_URL|MAILER_DSN|JWT_[A-Z_]*|[A-Z_]*_PASSWORD|[A-Z_]*_TOKEN|BEGIN (RSA|OPENSSH) PRIVATE KEY)" --include=*.php --include=*.yaml --include=*.yml --include=*.env --include=*.dist .` | vulnerability-scanner |
| sast | `deptrac.yaml` or `deptrac.dist.yaml` exists | `php vendor/bin/deptrac analyse --no-progress` | vulnerability-scanner |
| sast | `phpmd.xml` exists | `php vendor/bin/phpmd src text phpmd.xml` | vulnerability-scanner |
| migrate-diff | `bin/console` exists and `doctrine/migrations` is in `composer.json` | `php bin/console doctrine:migrations:diff --no-interaction` | migration-engineer |
| migrate-status | `bin/console` exists and `doctrine/migrations` is in `composer.json` | `php bin/console doctrine:migrations:status` | migration-engineer |
| migrate-up | ONLY against a disposable test database, never against a real environment | `php bin/console doctrine:migrations:migrate --no-interaction --dry-run` | migration-engineer |

## `Makefile` shortcut (optional, never mandatory)

Many repos on this stack wrap the above in `make` (`make tests`, `make phpstan`,
`make ecs-fix`, `make dev-dry`). **If a `Makefile` exists with the equivalent target, prefer it**:
it encapsulates flags, paths and environment variables this pack can't guess. `make` is in the
allowlist of `test-writer`, `implementer`, `quality-fixer` and `migration-engineer`; it is NOT in
that of `vulnerability-scanner` or `dependency-auditor`, which always use the table's direct form.

## Usage rules (protocol §5)

1. **Run the tool before forming an opinion.** Model judgment is for the residual that
   `--fix` couldn't resolve, never for eyeballing what a linter resolves on its own.
2. **`fix` before `lint`.** Run `--fix` and re-read `lint`; whatever remains is the real
   residual.
3. **Rector before the formatter** when both exist: rector rewrites structure, the
   formatter reindents it afterward. The reverse order loses the formatting.
4. **Never chain two commands from this table with `&&`.** `hooks/bash-guard.py` validates
   segment by segment; one call per command, always.
5. **`migrate-up` is never run without `--dry-run`** from an agent. Applying migrations against a
   real database is the owner's decision, not the swarm's (see `boundaries.md`).
