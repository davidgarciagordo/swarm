#!/usr/bin/env bash
# tests/test_bash_allowlist_pack.sh — allowlist de las 4 hojas de fase 5b + los comandos de
# scanner que el stack pack le da a vulnerability-scanner (spec §7, §8).
#
# Regla de diseño que este fichero vigila (hooks/bash-guard.py): un prefijo de UNA palabra casa
# por igualdad exacta de la primera palabra, así que `composer` habilitaría `composer update`.
# Todo comando NO mutante de un gestor de paquetes se allowlista con prefijo de DOS palabras.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

guard() {
  local out
  out="$(printf '{"agent_type": "%s", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$1" "$2" | python3 "$HOOK")"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

# --- migration-engineer: escribe y commitea migraciones dentro del worktree de implementer ---
assert_eq "allow" "$(guard swarm:migration-engineer 'cd /tmp/wt && git status --porcelain')" "migration-engineer can cd into implementer worktree"
assert_eq "allow" "$(guard swarm:migration-engineer 'php bin/console doctrine:migrations:diff')" "migration-engineer can run the migrations diff"
assert_eq "allow" "$(guard swarm:migration-engineer 'php bin/console doctrine:migrations:status')" "migration-engineer can read migration status"
assert_eq "allow" "$(guard swarm:migration-engineer 'git add -A')" "migration-engineer can git add"
assert_eq "allow" "$(guard swarm:migration-engineer 'git commit -m x')" "migration-engineer can git commit"
assert_eq "deny"  "$(guard swarm:migration-engineer 'git push origin master')" "migration-engineer cannot push"
assert_eq "deny"  "$(guard swarm:migration-engineer 'php -r echo(1);')" "migration-engineer cannot run inline php"

# --- doc-writer: escribe docs y changelog en el worktree, sin tocar herramientas del stack ---
assert_eq "allow" "$(guard swarm:doc-writer 'cd /tmp/wt && git diff --stat')" "doc-writer can cd into implementer worktree"
assert_eq "allow" "$(guard swarm:doc-writer 'git add -A')" "doc-writer can git add"
assert_eq "allow" "$(guard swarm:doc-writer 'git commit -m x')" "doc-writer can git commit"
assert_eq "deny"  "$(guard swarm:doc-writer 'composer install')" "doc-writer cannot touch package managers"
assert_eq "deny"  "$(guard swarm:doc-writer 'git push origin master')" "doc-writer cannot push"

# --- dependency-auditor: READ-ONLY, prefijos de dos palabras, nunca el binario a secas ---
assert_eq "allow" "$(guard swarm:dependency-auditor 'composer audit --format=json')" "dependency-auditor can run composer audit"
assert_eq "allow" "$(guard swarm:dependency-auditor 'composer outdated --direct --format=json')" "dependency-auditor can run composer outdated"
assert_eq "allow" "$(guard swarm:dependency-auditor 'composer licenses --format=json')" "dependency-auditor can list licenses"
assert_eq "allow" "$(guard swarm:dependency-auditor 'npm audit --json')" "dependency-auditor can run npm audit"
assert_eq "allow" "$(guard swarm:dependency-auditor 'npm outdated --json')" "dependency-auditor can run npm outdated"
assert_eq "deny"  "$(guard swarm:dependency-auditor 'composer update')" "dependency-auditor CANNOT mutate deps (composer update)"
assert_eq "deny"  "$(guard swarm:dependency-auditor 'composer require foo/bar')" "dependency-auditor CANNOT install deps"
assert_eq "deny"  "$(guard swarm:dependency-auditor 'npm install')" "dependency-auditor CANNOT npm install"
assert_eq "deny"  "$(guard swarm:dependency-auditor 'git commit -m x')" "dependency-auditor never commits"

# --- dependency-installer: MUTANTE, solo gestores de proyecto, jamás OS ni borrado ni commit ---
assert_eq "allow" "$(guard swarm:dependency-installer 'composer require phpstan/phpstan --dev')" "installer can composer require"
assert_eq "allow" "$(guard swarm:dependency-installer 'composer update doctrine/orm')" "installer can composer update a named package"
# Backstop determinista (hooks/bash-guard.py BARE_TWO_WORD_DENIED): un prefijo allowlist de dos
# palabras ("composer update") también matchea el comando BARE de dos palabras -- actualización
# de TODO el árbol, muy por encima de cualquier paquete aprobado. Antes de este fix lo único que
# lo impedía era la prosa de agents/dependency-installer.md ("Nunca composer update a secas").
assert_eq "deny"  "$(guard swarm:dependency-installer 'composer update')" "installer CANNOT bare composer update (scope-escape past itemised approval)"
assert_eq "allow" "$(guard swarm:dependency-installer 'composer install --no-interaction')" "installer can composer install"
assert_eq "allow" "$(guard swarm:dependency-installer 'npm ci')" "installer can npm ci"
assert_eq "deny"  "$(guard swarm:dependency-installer 'brew install jq')" "installer CANNOT touch OS packages (ruling 2)"
assert_eq "deny"  "$(guard swarm:dependency-installer 'apt install jq')" "installer CANNOT touch OS packages (ruling 2)"
assert_eq "deny"  "$(guard swarm:dependency-installer 'composer remove foo/bar')" "installer CANNOT uninstall (ruling 4)"
assert_eq "deny"  "$(guard swarm:dependency-installer 'npm uninstall foo')" "installer CANNOT uninstall (ruling 4)"
assert_eq "deny"  "$(guard swarm:dependency-installer 'git commit -m x')" "installer never commits (ruling 3)"
assert_eq "deny"  "$(guard swarm:dependency-installer 'git push origin master')" "installer cannot push"

# --- vulnerability-scanner: scanners del pack por prefijo de dos palabras, sin `php` abierto ---
assert_eq "allow" "$(guard swarm:vulnerability-scanner 'composer audit --format=json')" "scanner can run composer audit"
assert_eq "allow" "$(guard swarm:vulnerability-scanner 'composer licenses --format=json')" "scanner can list licenses"
assert_eq "allow" "$(guard swarm:vulnerability-scanner 'npm audit --json')" "scanner can run npm audit"
assert_eq "allow" "$(guard swarm:vulnerability-scanner 'php vendor/bin/deptrac analyse --no-progress')" "scanner can run deptrac (two-word prefix)"
assert_eq "allow" "$(guard swarm:vulnerability-scanner 'php vendor/bin/phpmd src text phpmd.xml')" "scanner can run phpmd (two-word prefix)"
assert_eq "deny"  "$(guard swarm:vulnerability-scanner 'php app/anything.php')" "scanner does NOT get bare php (ruling 8)"
assert_eq "deny"  "$(guard swarm:vulnerability-scanner 'composer update')" "scanner stays read-only"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
