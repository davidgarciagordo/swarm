# commands — php-ddd-symfony8

Formas canónicas de los comandos deterministas de este stack (spec §8: `lint | fix | typecheck |
test | test-one | scan-deps | scan-secrets | sast`, más las claves de migración y de licencias que
este stack necesita). **Toda forma está escrita para pasar `hooks/bash-guard.py` con el allowlist
del agente que la columna `ejecutor` nombra** — `tests/test_stack_pack.sh` lo verifica fila a fila.
Si añades una fila, añade también el prefijo correspondiente al allowlist de su ejecutor, o el test
falla (que es justo lo que debe pasar).

Las herramientas de este ecosistema no son únicas: la columna `condición` dice cuál eliges. **La
primera fila cuya condición se cumple gana**; si ninguna se cumple para una clave, esa clave no
tiene comando en este repo y la hoja lo dice explícitamente en vez de inventarse uno.

| clave | condición | comando | ejecutor |
|---|---|---|---|
| lint | existe `ecs.php` | `php vendor/bin/ecs check --no-progress-bar` | quality-fixer |
| lint | existe `.php-cs-fixer.dist.php` o `.php-cs-fixer.php` | `php vendor/bin/php-cs-fixer fix --dry-run --diff` | quality-fixer |
| fix | existe `ecs.php` | `php vendor/bin/ecs check --fix --no-progress-bar` | quality-fixer |
| fix | existe `.php-cs-fixer.dist.php` o `.php-cs-fixer.php` | `php vendor/bin/php-cs-fixer fix` | quality-fixer |
| fix | existe `rector.php` (se ejecuta ANTES del formateador) | `php vendor/bin/rector process` | quality-fixer |
| typecheck | existe `phpstan.dist.neon` o `phpstan.neon` | `php vendor/bin/phpstan analyse --no-progress --error-format=raw` | quality-fixer |
| test | existe `phpunit.xml.dist` o `phpunit.xml` | `php vendor/bin/phpunit` | test-writer + implementer |
| test | además existe `vendor/bin/paratest` (suite grande) | `php vendor/bin/paratest --processes=4` | implementer |
| test-one | siempre que haya PHPUnit | `php vendor/bin/phpunit --filter <NombreDelTest> <ruta/al/Test.php>` | test-writer + implementer |
| scan-deps | existe `composer.lock` | `composer audit --format=json` | dependency-auditor + vulnerability-scanner |
| outdated | existe `composer.lock` | `composer outdated --direct --format=json` | dependency-auditor |
| licenses | existe `composer.lock` | `composer licenses --format=json` | dependency-auditor + vulnerability-scanner |
| scan-secrets | siempre | `grep -rnE "(APP_SECRET|DATABASE_URL|MAILER_DSN|JWT_[A-Z_]*|[A-Z_]*_PASSWORD|[A-Z_]*_TOKEN|BEGIN (RSA|OPENSSH) PRIVATE KEY)" --include=*.php --include=*.yaml --include=*.yml --include=*.env --include=*.dist .` | vulnerability-scanner |
| sast | existe `deptrac.yaml` o `deptrac.dist.yaml` | `php vendor/bin/deptrac analyse --no-progress` | vulnerability-scanner |
| sast | existe `phpmd.xml` | `php vendor/bin/phpmd src text phpmd.xml` | vulnerability-scanner |
| migrate-diff | existe `bin/console` y `doctrine/migrations` en `composer.json` | `php bin/console doctrine:migrations:diff --no-interaction` | migration-engineer |
| migrate-status | existe `bin/console` y `doctrine/migrations` en `composer.json` | `php bin/console doctrine:migrations:status` | migration-engineer |
| migrate-up | SOLO contra una base desechable de test, nunca contra un entorno real | `php bin/console doctrine:migrations:migrate --no-interaction --dry-run` | migration-engineer |

## Atajo por `Makefile` (opcional, nunca obligatorio)

Muchos repos de este stack envuelven lo anterior en `make` (`make tests`, `make phpstan`,
`make ecs-fix`, `make dev-dry`). **Si existe un `Makefile` con el target equivalente, prefiérelo**:
encapsula flags, rutas y variables de entorno que este pack no puede adivinar. `make` está en el
allowlist de `test-writer`, `implementer`, `quality-fixer` y `migration-engineer`; NO lo está en el
de `vulnerability-scanner` ni en el de `dependency-auditor`, que usan siempre la forma directa de
la tabla.

## Reglas de uso (protocolo §5, spec principio 4)

1. **Ejecuta la herramienta antes de opinar.** El juicio del modelo es para el residual que el
   `--fix` no arregló, nunca para revisar a ojo lo que un linter resuelve solo.
2. **`fix` antes de `lint`.** Corre el `--fix` y vuelve a leer el `lint`; lo que quede es el
   residual real.
3. **Rector antes que el formateador** cuando ambos existen: rector reescribe estructura, el
   formateador la reindenta después. Al revés se pierde el formato.
4. **Nunca encadenes dos comandos de esta tabla con `&&`.** `hooks/bash-guard.py` valida segmento a
   segmento; una llamada por comando, siempre.
5. **`migrate-up` nunca se ejecuta sin `--dry-run`** desde un agente. Aplicar migraciones contra una
   base real es una decisión del owner, no del enjambre (ver `boundaries.md`).
