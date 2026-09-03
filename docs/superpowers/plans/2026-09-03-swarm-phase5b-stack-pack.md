# Fase 5b — Stack pack `php-ddd-symfony8` + sus 4 hojas consumidoras Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir el PRIMER stack pack del plugin (`skills/pack-php-ddd-symfony8/`, spec §8, los
6 ficheros del contrato con contenido real) junto con las 4 hojas que lo consumen y sin las cuales
no se puede probar contra nada — `migration-engineer`, `doc-writer` (dominio implementation),
`dependency-auditor`, `dependency-installer` (dominio requirements) — y cablear la RUTA del pack a
través de los orquestadores ya construidos (`implementation-orchestrator`, `analysis-orchestrator`,
`requirements-orchestrator`), convirtiendo la fusión de `requirements.json` de prosa-de-futuro a
lógica real y ejecutada.

**Architecture:** El pack es DATOS, no código: seis ficheros Markdown/JSON en
`skills/pack-php-ddd-symfony8/` que las hojas LEEN. Nadie muta frontmatter en runtime (spec §3.1).
El camino de la ruta es: `memory-builder` ya detecta el stack con `scripts/mem-scan.sh` y escribe
`stack: php-ddd-symfony8` en `.swarm/context-pack.md` → el orquestador de dominio lee esa línea,
**resuelve la ruta absoluta del pack una sola vez** con `ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-<stack>"`
(el shell expande la variable; `ls` está en todos los allowlists; la salida ES la ruta absoluta
resuelta) → pasa esa ruta ya resuelta como una quinta línea de cabecera `pack: <ruta>` en el prompt
de cada hoja consumidora → la hoja hace `Read` de `<pack>/commands.md` / `conventions.md` /
`boundaries.md` / `precedents.md` (spec §3.1: "la hoja hace `Read` del pack"). Sin `stack:` confiable
en el context-pack, la línea `pack:` NO se emite y la hoja cae en su modo genérico ya existente.
Las 4 hojas nuevas siguen los patrones ya cerrados de fase 5a: `migration-engineer` y `doc-writer`
trabajan dentro del worktree de `implementer` por ruta absoluta en el prompt (mismo mecanismo que
`quality-fixer`/`reviewer`, sin `isolation:` propia, sin worktree nuevo que limpiar);
`dependency-auditor` es read-only puro; `dependency-installer` es el PRIMER leaf mutante del dominio
requirements y solo se autoriza con aprobación explícita del owner obtenida por la RAÍZ con
`AskUserQuestion` (ningún subagente puede preguntar, spec §3.2 regla 7).

**Tech Stack:** Markdown (frontmatter YAML) para pack y agentes, JSON (`requirements.json` del pack,
`hooks/bash-allowlist.json`), Bash 3.2 + Python 3 stdlib para tests y para la fusión determinista de
`requirements.json` dentro de `scripts/req-check.sh`. Herramientas reales del stack objetivo
(documentadas, no ejecutadas por este repo): `composer`, `php vendor/bin/phpunit`,
`php vendor/bin/phpstan`, `php vendor/bin/ecs` / `php vendor/bin/php-cs-fixer`,
`php vendor/bin/deptrac`, `php bin/console doctrine:migrations:*`.

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — §7 (filas
`migration-engineer`, `doc-writer`, `dependency-auditor`, `dependency-installer` + contrato
`requirements.json`), §7.0 (modelo por tier), §8 y §8.1 (contrato del pack y tabla de detección),
§3.1 (paso de pack por prompt, nunca mutación de frontmatter), §9.3 (aislamiento), §12 (estructura
del plugin), §15 fase 5.

## Alcance — qué NO entra en esta fase (para que nadie lo busque aquí)

- `/swarm:status` y `/swarm:findings` → **fase 6** (spec §11/§15).
- `delivery-orchestrator` / `release-manager` / `handoff-writer` → **fase 6**, primer dominio con
  `git push` real. Este plan sigue sin tocar remoto ni rama compartida en ningún camino.
- **Un segundo stack pack** → fuera de alcance de v1 por decisión explícita del spec (§16: "más de
  un stack pack"; §8.1: "siguientes packs, según se añadan"). La tabla de detección de
  `scripts/mem-scan.sh` se deja como está, con una sola fila real y el fallback `generic`.
- **Construir contra un proyecto concreto.** El plugin es agnóstico de stack (spec §1). El estudio
  de un repo PHP/DDD/Symfony real se usa SOLO como referencia de patrones para redactar
  `conventions.md`/`precedents.md`; su nombre, su dominio de negocio y cualquier detalle propietario
  NO aparecen en el contenido que se commitea. El pack se escribe en términos genéricos que
  cualquier proyecto PHP-DDD-Symfony reconocería.
- **Multi-stack por ruta** (monorepo con stacks distintos por subcarpeta) → spec §16, fuera de v1.

## Global Constraints

- Frontmatter obligatorio en cada agente nuevo: `name`, `description` ("Use when…"), `model`,
  `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`. Nunca `hooks:`/`mcpServers:`/
  `permissionMode:` (spec §3.1: se IGNORAN en subagentes de plugin), nunca sintaxis `Bash(cmd:*)`.
  `tests/test_agents_frontmatter.sh` lo vigila con glob dinámico — cubre los agentes nuevos gratis.
- Todo agente nuevo lleva `SendMessage` en `tools` (spec §7, nota de cabecera del roster).
- Modelo y `maxTurns` EXACTOS de la tabla del spec §7: `migration-engineer` sonnet/15,
  `doc-writer` sonnet/15, `dependency-auditor` sonnet/12, `dependency-installer` sonnet/10. Ninguno
  es hoja de juicio ni hoja mecánica de la tabla §7.0, así que **ninguno recibe override de `model`
  por tier** — ni en `light` ni en `full`.
- Ninguna hoja tiene `AskUserQuestion` (spec §3.2 regla 7). La aprobación del owner para
  `dependency-installer` la obtiene la RAÍZ, único agente del plugin con esa tool.
- `dependency-auditor` es **read-only por construcción** (spec §7: "read-only"): sin `Write`, sin
  `Edit`, y sin ningún prefijo de Bash mutante en su allowlist.
- Restricción de allowlist derivada de `hooks/bash-guard.py`: un prefijo de UNA palabra casa por
  igualdad exacta de la primera palabra (`composer` habilitaría `composer update`), mientras que un
  prefijo de DOS palabras casa contra `' '.join(words[:2])`. **Todo comando no mutante de un gestor
  de paquetes se allowlista con prefijo de dos palabras** (`composer audit`, `npm outdated`,
  `php vendor/bin/deptrac`), nunca con el binario a secas.
- Saneado obligatorio (`skills/swarm-protocol/SKILL.md` §4.4) para CUALQUIER texto ajeno interpolado
  en un `--text`/`--fix`/`--line` de shell: backtick→`'`, borrar `$`, `"`→`'`, borrar `\`, colapsar
  saltos de línea. Contenido largo o estructurado (ficheros de documentación, migraciones) va SIEMPRE
  por `Write`/`Edit` nativos, nunca por argumento de shell (lección de fase 4).
- **Lección de fase 5a (aplicada ya TRES veces: §8.3→§9.3→§10.3).** La exención de saneado para el
  OUTPUT de turno NUNCA cubre el `summary --line` del cierre de run. Este plan añade UNA sección de
  reenvío nueva en la raíz (Task 9, `## 11`): su párrafo de exención se **copia LITERAL** del §10.3
  actual de `agents/orchestrator.md`, sustituyendo únicamente el nombre del orquestador y los
  números de sección. No se reescribe de memoria.
- **Lección de fase 5a (allowlist sin probar = allowlist sin verificar).** Cada tarea que añada un
  agente con `Bash` termina con sus bloques ```bash reales pasados por `hooks/bash-guard.py` con su
  `agent_type` verdadero, y añade el agente a `AGENT_FILES` en
  `tests/test_agent_bash_blocks_allowed.sh`. Un comando documentado que el guard deniega es un
  callejón sin salida silencioso — así se coló el único Critical de fase 5a.
- **Lección de fase 5a (limpieza en todos los caminos de salida + test, no prosa).** Verificado para
  esta fase: ninguna hoja nueva crea un recurso que haya que liberar. `migration-engineer` y
  `doc-writer` REUSAN el worktree de `implementer` (limpieza ya cubierta por la sección "Limpieza del
  worktree" de `implementation-orchestrator` y por `tests/test_implementation_worktree_cleanup.sh`);
  `dependency-auditor` no muta nada; `dependency-installer` muta ficheros de manifiesto versionados
  (recuperables con git), no un recurso con ciclo de vida. **Por eso este plan NO añade un test de
  limpieza nuevo** — pero Task 7 sí verifica que la sección de limpieza existente siga alcanzando
  todos los caminos terminales tras insertar dos pasos nuevos en la secuencia.
- Cada tarea termina en su propio commit, con identidad git personal
  (`git config user.email` debe ser `garcia.gordo.david@gmail.com` — comprobar ANTES del primer
  commit de la fase, no después).
- `bash tests/run.sh` en verde al final de CADA tarea (36 ficheros hoy + los nuevos de esta fase).
- "Cero preámbulo" (`skills/swarm-protocol/SKILL.md` §4): el último mensaje de cualquier agente
  nuevo empieza literalmente en el veredicto, con la línea `evidence: files=N cmds=M turns=k/max`
  como línea 2 y hallazgos `TAG · fichero:línea · problema → fix` después.
- El pack NO menciona ningún proyecto, empresa ni término de negocio concreto. Los ejemplos usan
  nombres ficticios (`Billing`, `Invoice`, `Order`).

## Rulings de esta sesión (decisiones tomadas al escribir el plan — el owner puede revertirlas)

1. **Resolución de la ruta del pack: `ls -d`, no `${CLAUDE_PLUGIN_ROOT}` crudo en el prompt.** La
   tool `Read` no expande variables de entorno, y ningún agente puede hacer `echo` (no está en
   ningún allowlist). El único comando allowlistado que devuelve la ruta ya expandida es
   `ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-<stack>"` (el shell expande antes de que `ls` la vea, y
   `ls -d` imprime el argumento resuelto). El orquestador la resuelve UNA vez y pasa el literal
   absoluto; ninguna hoja recibe jamás una cadena con `${CLAUDE_PLUGIN_ROOT}` sin expandir.
2. **`dependency-installer` v1 instala dependencias de PROYECTO, no del sistema.** El spec §7 dice
   "brew/apt, composer/npm…", pero `brew`/`apt` mutan la máquina del owner fuera del repo, no son
   reversibles con git y `apt` exige `sudo` (imposible sin interacción). En v1 el installer solo
   toca gestores de proyecto (`composer install|require|update`, `npm install|ci`); lo de OS se
   reporta como hint accionable para que lo ejecute el owner. Coste si el ruling está mal: el owner
   teclea un `brew install` a mano.
3. **`dependency-installer` NO commitea.** No pertenece al dominio implementation, no tiene plan ni
   fase de referencia, y auto-commitear un cambio de dependencias sin pasar por `reviewer` es peor
   que dejar el árbol sucio y visible. Reporta exactamente qué ficheros de manifiesto cambió.
4. **`composer remove` / `npm uninstall` fuera del allowlist del installer.** El spec dice
   "instala/actualiza lo que el owner aprobó" — desinstalar no es ninguna de las dos. Las
   dependencias sin uso que encuentre `dependency-auditor` se reportan como hallazgo, no se borran.
5. **Verificación de `libs` repartida por SRP.** `scripts/req-check.sh` (y por tanto `env-checker`)
   sigue SIN verificar entradas `libs` contra un gestor real: las reporta como no bloqueantes. Quien
   verifica librerías de proyecto de verdad es `dependency-auditor` con los comandos del pack. Se
   actualiza el texto del stub (hoy dice "requiere stack pack para verificar (fase 5)", que a partir
   de esta fase es falso) para que apunte a `dependency-auditor`.
6. **Extensiones de PHP no van en `requirements.json`.** El esquema del spec §7 tiene `os` (binarios,
   verificados con `which`) y `libs` (paquetes de un gestor). Una extensión (`ext-pdo`, `ext-intl`)
   no es ninguna de las dos y `req-check.sh` la marcaría como ausente siempre. Se documentan en
   `conventions.md` del pack y NO se extiende el esquema en 5b (YAGNI: sin consumidor real).
7. **Piso de PHP conservador (`min: "8.2"`) en el `requirements.json` del pack.** El pack se llama
   `symfony8`, pero el piso exacto de PHP que exige Symfony 8 no se ha verificado contra la
   documentación oficial en esta sesión, y un piso demasiado alto BLOQUEA un repo válido (un `min`
   incumplido es un `BLOCKED` del health-gate). `8.2` no bloquea a nadie razonable y el propio
   `composer` ya impone el piso real del proyecto. Subirlo es un cambio de una línea.
8. **`vulnerability-scanner` recibe los comandos de scan por prefijo de dos palabras, no `php` a
   secas.** Dar `php` completo a una hoja read-only en haiku equivale a permitir la ejecución de
   cualquier script del repo. Con `php vendor/bin/deptrac` y `php vendor/bin/phpmd` como prefijos de
   dos palabras se consigue SAST real sin abrir esa puerta.
9. **`migration-engineer` y `doc-writer` corren ANTES de `quality-fixer`/`reviewer`**, no después,
   para que el gate de calidad y el gate de review cubran también su salida y todo entre en el mismo
   merge. Ambos son condicionales (solo si la fase toca esquema / documentación).
10. **El estudio del repo PHP/DDD/Symfony de referencia SÍ se hizo** (sonda acotada, read-only), y
    `conventions.md`/`precedents.md` están calcados de estructuras reales observadas — layout
    `src/<Context>/<Aggregate>/<Capa>`, mapping XML de Doctrine con tipos DBAL por value object,
    Object Mother en tests, pipeline rector→ecs→phpstan→deptrac→tests — pero redactados en genérico
    y con nombres ficticios. Ningún término de negocio real viaja al repo.

---
### Task 1: Allowlist de Bash para las 4 hojas nuevas + comandos de scanner para `vulnerability-scanner`

**Files:**
- Modify: `hooks/bash-allowlist.json`
- Create: `tests/test_bash_allowlist_pack.sh`

**Interfaces:**
- Consumes: nada de tareas previas.
- Produces: entradas de allowlist para `swarm:migration-engineer`, `swarm:doc-writer`,
  `swarm:dependency-auditor`, `swarm:dependency-installer`, y los prefijos de scanner añadidos a
  `swarm:vulnerability-scanner`. Las Tasks 2-6 escriben comandos documentados que dependen
  EXACTAMENTE de estos prefijos.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_bash_allowlist_pack.sh <<'EOF'
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
assert_eq "deny"  "$(guard swarm:migration-engineer 'php -r "unlink(1);"')" "migration-engineer cannot run inline php"

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
EOF
chmod +x tests/test_bash_allowlist_pack.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_bash_allowlist_pack.sh`
Expected: muchos `FAIL` (los cuatro `agent_type` nuevos no existen en el allowlist, así que caen al
bloque `default`, que no trae `cd`, ni `git commit`, ni ningún gestor de paquetes).

- [ ] **Step 3: Añadir las 4 entradas nuevas a `hooks/bash-allowlist.json`**

Inserta estos cuatro bloques dentro del objeto `"agents"` (el orden no importa; ponlos tras
`"swarm:implementation-orchestrator"` para que el fichero siga la cronología de fases):

```json
    "swarm:migration-engineer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git add", "git commit",
      "cd",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh",
      "php", "composer", "make"
    ],
    "swarm:doc-writer": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "git add", "git commit",
      "cd",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:dependency-auditor": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh", "scripts/req-check.sh",
      "composer audit", "composer outdated", "composer show", "composer licenses",
      "npm audit", "npm outdated", "npm ls"
    ],
    "swarm:dependency-installer": [
      "git status", "git diff", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh",
      "composer install", "composer require", "composer update",
      "npm install", "npm ci"
    ],
```

Nota deliberada sobre `swarm:migration-engineer`: recibe `php` de UNA palabra (igual que
`implementer`/`test-writer`/`quality-fixer` de fase 5a) porque necesita `php bin/console
doctrine:migrations:diff` con rutas y flags variables; el guard ya le deniega `php -r` por
`INTERP_DENIED_FLAGS`. `dependency-auditor`/`dependency-installer`/`vulnerability-scanner` NO lo
reciben: sus comandos son un conjunto cerrado y caben en prefijos de dos palabras.

- [ ] **Step 4: Añadir los prefijos de scanner a `swarm:vulnerability-scanner`**

Localiza la entrada existente `"swarm:vulnerability-scanner"` y añade estos cinco prefijos al final
de su array (sin quitar ninguno de los que ya tiene):

```json
      "composer audit", "composer outdated", "composer licenses",
      "npm audit",
      "php vendor/bin/deptrac", "php vendor/bin/phpmd"
```

Esto cierra la "Nota de futuro" que `agents/vulnerability-scanner.md` dejó escrita en fase 3
("cuando el primer stack pack aterrice, añade sus comandos de scanner al allowlist de esta hoja como
parte de esa fase, no antes") — Task 7 actualiza también esa prosa.

- [ ] **Step 5: Confirmar que el test pasa**

Run: `bash tests/test_bash_allowlist_pack.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 6: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 37, failed: 0`.

- [ ] **Step 7: Commit**

```bash
git config user.email
git add hooks/bash-allowlist.json tests/test_bash_allowlist_pack.sh
git commit -m "feat(pack): allowlist de Bash para las 4 hojas de fase 5b + scanners del pack"
```

(El `git config user.email` del primer step del commit es la comprobación de identidad exigida por
las Global Constraints: debe imprimir `garcia.gordo.david@gmail.com` ANTES de commitear.)

---

### Task 2: El stack pack `skills/pack-php-ddd-symfony8/` (6 ficheros del contrato §8)

**Files:**
- Create: `skills/pack-php-ddd-symfony8/SKILL.md`
- Create: `skills/pack-php-ddd-symfony8/commands.md`
- Create: `skills/pack-php-ddd-symfony8/conventions.md`
- Create: `skills/pack-php-ddd-symfony8/boundaries.md`
- Create: `skills/pack-php-ddd-symfony8/precedents.md`
- Create: `skills/pack-php-ddd-symfony8/requirements.json`
- Create: `tests/test_stack_pack.sh`

**Interfaces:**
- Consumes: los prefijos de allowlist de Task 1 (cada comando de `commands.md` debe ser ejecutable
  por el agente que la propia tabla nombra como ejecutor).
- Produces:
  - La ruta `skills/pack-php-ddd-symfony8/` que Tasks 3-8 pasan como cabecera `pack:`.
  - El **esquema de la tabla de `commands.md`**: cabecera exacta
    `| clave | condición | comando | ejecutor |`, una fila por comando, `clave` de un conjunto
    cerrado (`lint`, `fix`, `typecheck`, `test`, `test-one`, `scan-deps`, `outdated`, `licenses`,
    `scan-secrets`, `sast`, `migrate-diff`, `migrate-status`, `migrate-up`), `comando` entre
    backticks, `ejecutor` = uno o más nombres de agente separados por `+`. `tests/test_stack_pack.sh`
    parsea exactamente ese formato: cambiarlo rompe el test a propósito.
  - `requirements.json` del pack con el mismo esquema `os`/`project`/`libs` del plugin, que Task 8
    fusiona.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_stack_pack.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_stack_pack.sh — contrato del primer stack pack (spec §8): los 6 ficheros, el esquema
# de requirements.json, y —lo importante— que CADA comando documentado en commands.md sea
# realmente ejecutable por el agente que la propia tabla nombra como ejecutor (lección de fase 5a:
# un comando documentado que el guard deniega es un callejón sin salida silencioso).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
PACK="$PLUGIN_ROOT/skills/pack-php-ddd-symfony8"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

for f in SKILL.md commands.md conventions.md boundaries.md precedents.md requirements.json; do
  assert_eq "0" "$([ -f "$PACK/$f" ] && echo 0 || echo 1)" "pack has $f (spec §8 file contract)"
done

# Marcador de detección: el mismo que scripts/mem-scan.sh ya implementa (spec §8.1 fila 1).
assert_file_contains "$PACK/SKILL.md" "composer.json" "SKILL.md documents the composer.json marker"
assert_file_contains "$PACK/SKILL.md" "symfony/" "SKILL.md documents the symfony/* require marker"
assert_file_contains "$PACK/SKILL.md" "php-ddd-symfony8" "SKILL.md names the stack id used in context-pack.md"

# El pack es material de estudio generalizado: ningún nombre de proyecto/empresa real.
assert_eq "0" "$(grep -ril 'quantum' "$PACK" | wc -l | tr -d ' ')" "pack content names no real project (ruling 10)"

# requirements.json del pack: mismo esquema que el del plugin (spec §7).
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert set(['os','project','libs']) <= set(d.keys()), 'missing top-level keys'
for k in ('os','project','libs'):
    assert isinstance(d[k], list), k + ' must be a list'
tools = [i.get('tool') for i in d['os']]
assert 'php' in tools and 'composer' in tools, 'pack must require php and composer'
for i in d['os']:
    assert 'required' in i, 'os entry without required: ' + str(i)
    if i.get('required'):
        assert i.get('install'), 'required os entry needs an install hint: ' + str(i)
files = [i.get('file') for i in d['project']]
assert 'composer.json' in files, 'pack must declare composer.json as a project file'
for i in d['libs']:
    assert i.get('name') and i.get('manager'), 'lib entry needs name+manager: ' + str(i)
" "$PACK/requirements.json"
assert_eq "0" "$?" "pack requirements.json matches the §7 schema"

# --- el corazón: cada comando de la tabla, contra el guard del ejecutor que la tabla declara ---
guard() {
  local out
  out="$(python3 "$HOOK" <<PYIN
{"agent_type": "$1", "tool_name": "Bash", "tool_input": {"command": $2}}
PYIN
)"
  if echo "$out" | grep -q '"permissionDecision": "deny"'; then echo deny; else echo allow; fi
}

rows="$(python3 - "$PACK/commands.md" <<'PYEOF'
import json, re, sys

KEYS = {"lint","fix","typecheck","test","test-one","scan-deps","outdated","licenses",
        "scan-secrets","sast","migrate-diff","migrate-status","migrate-up"}
rows = 0
for line in open(sys.argv[1]):
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) != 4 or cells[0] in ("clave", "---") or set(cells[0]) <= set("- :"):
        continue
    key, _cond, cmd, execs = cells
    assert key in KEYS, "unknown command key: " + key
    m = re.match(r"^`(.+)`$", cmd)
    assert m, "command cell must be wrapped in backticks: " + cmd
    # Los <placeholders> se sustituyen por un token inocuo antes de pasar por el guard.
    real = re.sub(r"<[^>]+>", "PLACEHOLDER", m.group(1))
    for agent in [e.strip() for e in execs.split("+")]:
        print(json.dumps([("swarm:" + agent), real]))
    rows += 1
assert rows >= 12, "expected the full §8 command set, got %d rows" % rows
PYEOF
)"
assert_eq "0" "$?" "commands.md table parses and covers the §8 command set"

while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  agent="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])[0])' "$pair")"
  cmd="$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[1]))' "$pair")"
  assert_eq "allow" "$(guard "$agent" "$cmd")" "$agent may run its documented pack command: $cmd"
done <<EOF
$rows
EOF

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_stack_pack.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_stack_pack.sh`
Expected: `FAIL` en los 6 ficheros (el directorio no existe todavía).

- [ ] **Step 3: Escribir `skills/pack-php-ddd-symfony8/SKILL.md`**

```bash
mkdir -p skills/pack-php-ddd-symfony8
cat > skills/pack-php-ddd-symfony8/SKILL.md <<'EOF'
---
name: pack-php-ddd-symfony8
description: Stack pack for PHP + DDD + Symfony 8 repositories — detection marker, canonical tool commands, layering and naming conventions, untouchable boundaries, and in-use precedents. Read by swarm leaves when .swarm/context-pack.md declares stack php-ddd-symfony8.
---

# pack-php-ddd-symfony8

Primer stack pack del plugin `swarm` (spec §8, §8.1 fila 1). **No se invoca: se LEE.** El
orquestador de dominio resuelve la ruta absoluta de este directorio y la pasa como línea de
cabecera `pack: <ruta>` en el prompt de la hoja; la hoja hace `Read` de los ficheros que necesita
(spec §3.1 — nunca se muta frontmatter en runtime, nunca se precarga como skill).

## Detección

| marcador | condición exacta | resultado |
|---|---|---|
| `composer.json` | existe en la raíz del repo **y** contiene `symfony/` dentro de `require` | `stack: php-ddd-symfony8` |

Es exactamente lo que ya implementa `scripts/mem-scan.sh` y lo que `memory-builder` escribe como
línea `stack:` en `.swarm/context-pack.md`. Sin ese marcador, el stack es `generic` y ninguna hoja
recibe la línea `pack:` — cada una cae en su modo genérico documentado.

## Qué contiene

| fichero | para quién | contenido |
|---|---|---|
| `commands.md` | `quality-fixer`, `test-writer`, `implementer`, `migration-engineer`, `vulnerability-scanner`, `dependency-auditor` | forma canónica de cada comando determinista, con su condición de detección y su ejecutor |
| `conventions.md` | `implementer`, `test-writer`, `migration-engineer`, `domain-modeler`, `doc-writer` | capas, layout de directorios, naming, estilo, extensiones de PHP esperadas |
| `boundaries.md` | TODA hoja que escriba | qué NO se toca nunca |
| `precedents.md` | `pattern-advisor`, `implementer`, `domain-modeler` | patrones ya en uso que se reutilizan antes de introducir uno nuevo |
| `requirements.json` | `requirements-orchestrator` → `env-checker` | requisitos de OS/proyecto/librerías que este stack añade a los del plugin |

## Regla de precedencia

Lo que diga este pack GANA sobre el conocimiento genérico de la hoja, y las entradas de su
`requirements.json` ganan sobre las homónimas del `requirements.json` del plugin (spec §7:
misma clave de identidad → gana el pack). Lo que el pack NO cubre, la hoja lo resuelve con su
criterio genérico — un pack incompleto nunca bloquea, solo deja de aportar.
EOF
```

- [ ] **Step 4: Escribir `skills/pack-php-ddd-symfony8/commands.md`**

```bash
cat > skills/pack-php-ddd-symfony8/commands.md <<'EOF'
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
| scan-secrets | siempre | `grep -rnE "(APP_SECRET|DATABASE_URL|MAILER_DSN|JWT_[A-Z_]*|[A-Z_]*_PASSWORD|[A-Z_]*_TOKEN|BEGIN (RSA|OPENSSH) PRIVATE KEY)" --include=*.php --include=*.yaml --include=*.yml --include=*.env --include=*.dist ." | vulnerability-scanner |
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
EOF
```

- [ ] **Step 5: Escribir `skills/pack-php-ddd-symfony8/conventions.md`**

```bash
cat > skills/pack-php-ddd-symfony8/conventions.md <<'EOF'
# conventions — php-ddd-symfony8

Convenciones de un repo PHP con DDD táctico sobre Symfony 8. Los ejemplos usan nombres ficticios
(`Billing`, `Invoice`, `Order`) — sustitúyelos por los del repo real, que ya están en
`.swarm/context-pack.md`.

## Layout: contexto → agregado → capa

```
src/<BoundedContext>/<Aggregate>/<Layer>
```

Los bounded contexts son los directorios de primer nivel bajo `src/`; dentro de cada uno, un
directorio por agregado; dentro de cada agregado, las tres capas. Ejemplo:

```
src/Billing/Invoice/Domain
src/Billing/Invoice/Application
src/Billing/Invoice/Infrastructure
src/Shared/Core/Domain          ← kernel compartido (identidad, eventos, criteria, excepciones base)
```

No es `src/<Capa>/<Contexto>` ni `src/Domain/<Contexto>`: la unidad de cohesión es el agregado, y
las tres capas viven juntas porque cambian juntas.

### `Domain/`

```
Domain/Model/<Aggregate>.php                 raíz del agregado (+ <Aggregate>Collection.php)
Domain/ValueObject/<Vo>.php                  un fichero por value object
Domain/Event/<Aggregate><PastParticiple>.php eventos de dominio
Domain/Service/<Algo>.php                    servicios de dominio sin estado
Domain/Exception/<Aggregate>NotFoundException.php
Domain/<Aggregate>Repository.php             INTERFAZ del repositorio, en la raíz de Domain/
```

Regla dura: `Domain/` no importa NADA de Symfony, Doctrine ni de `Infrastructure/`. Si necesitas un
tipo de framework en el dominio, el diseño está mal, no la regla.

### `Application/` — una carpeta por caso de uso

```
Application/Create/CreateInvoiceCommand.php
Application/Create/CreateInvoiceCommandHandler.php
Application/Find/FindById/FindInvoiceByIdQuery.php
Application/Search/ByCriteria/SearchInvoicesByCriteriaQuery.php
```

Verbos del conjunto cerrado `Create | Update | Patch | Delete | Find | Search`. Cada caso de uso es
un par comando/consulta + su handler; el handler orquesta, no contiene reglas de negocio (esas viven
en el agregado).

### `Infrastructure/`

```
Infrastructure/Persistence/Doctrine/Repository/Doctrine<Aggregate>Repository.php
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/<Aggregate>.orm.xml
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/<Vo>Type.php
Infrastructure/Persistence/Doctrine/Fixture/<Aggregate>Fixture.php
Infrastructure/Symfony/Controller/<Verb><Aggregate>Controller.php
```

El mapping XML (no atributos) mantiene el dominio libre de anotaciones de framework. Cada value
object persistido tiene su tipo DBAL propio (`<Vo>Type`), registrado en la configuración de Doctrine.

## Naming

| elemento | patrón | ejemplo |
|---|---|---|
| agregado | sustantivo desnudo, igual que su carpeta | `Invoice` |
| colección | `<Aggregate>Collection` | `InvoiceCollection` |
| value object | sustantivo desnudo, SIN sufijo `VO`/`ValueObject` | `Id`, `Amount`, `Title` |
| evento de dominio | `<Aggregate><ParticipioPasado>`, sin sufijo `Event`, con `EVENT_NAME` en snake punteado | `InvoiceCreated` → `public const string EVENT_NAME = 'invoice.created';` |
| interfaz de repositorio | `<Aggregate>Repository` (en `Domain/`) | `InvoiceRepository` |
| implementación | `Doctrine<Aggregate>Repository` (en `Infrastructure/`) | `DoctrineInvoiceRepository` |
| comando / handler | `<Verb><Aggregate>Command` + `…CommandHandler` | `CreateInvoiceCommand` |
| controlador | `<Verb><Aggregate>Controller` (plural en búsquedas) | `SearchInvoicesController` |
| excepción | `<Aggregate>NotFoundException`, extiende la base compartida | `InvoiceNotFoundException` |
| tipo DBAL | `<Vo>Type` | `AmountType` |
| migración | `Version<YYYYMMDDHHMMSS>.php` | `Version20260903120000.php` |

## Tests

```
tests/Unit/<Context>/<Aggregate>/Application/<UseCase>/<Handler>Test.php   unitario, repos mockeados
tests/Unit/<Context>/<Aggregate>/Infrastructure/Persistence/…Test.php
tests/Application/<Context>/<Aggregate>/Controller/<Verb><Aggregate>ControllerTest.php  funcional
```

- Sufijo `*Test.php` siempre. El árbol de `tests/` se parte primero por TIPO de test (`Unit/`,
  `Application/`) y solo después replica contexto/agregado.
- **Object Mother** (`<Aggregate>Mother`, `<Command>Mother`) para construir datos de prueba — nunca
  constructores desnudos repetidos en cada test.
- Los tests unitarios no tocan base de datos; los de `Application/` levantan el kernel real y se
  aíslan por transacción.

## Estilo

- `declare(strict_types=1);` en todo fichero PHP nuevo, sin excepción.
- PSR-4 para autoload, PSR-12 como base de formato (lo impone la herramienta `fix` de
  `commands.md`, no tú a mano).
- Tipos explícitos en todas las firmas, incluido el retorno; `readonly` en value objects.
- Constructores privados + named constructors (`::create()`, `::fromPrimitives()`) en agregados y
  VOs cuando el repo ya lo haga así (ver `precedents.md`).
- Inyección por constructor; nada de service locators ni de `static` con estado.

## Extensiones de PHP que este stack asume

`ext-json`, `ext-pdo` (+ el driver de la base: `ext-pdo_mysql`/`ext-pdo_pgsql`), `ext-mbstring`,
`ext-intl` si hay formateo/localización, `ext-openssl` si hay JWT. **No se declaran en
`requirements.json`**: su esquema (`os` = binarios, `libs` = paquetes de un gestor) no las modela, y
`composer` ya las exige por su cuenta. Se listan aquí para que quien diagnostique un fallo de
entorno sepa dónde mirar.
EOF
```

- [ ] **Step 6: Escribir `skills/pack-php-ddd-symfony8/boundaries.md`**

```bash
cat > skills/pack-php-ddd-symfony8/boundaries.md <<'EOF'
# boundaries — php-ddd-symfony8

Qué NO se toca. Aplica a TODA hoja con `Write`/`Edit` (`implementer`, `test-writer`,
`quality-fixer`, `migration-engineer`, `doc-writer`) y a cualquier `--fix` automático. Si tu tarea
parece exigir tocar algo de esta lista, tu veredicto es `BLOCKED <qué límite y por qué>` — no lo
tocas "solo un poco".

## Nunca se edita a mano

| ruta / patrón | por qué |
|---|---|
| `vendor/` | lo genera `composer`; cualquier edición se pierde en el siguiente `install` |
| `node_modules/`, `public/build/`, `public/bundles/` | artefactos de build/assets |
| `var/` (`var/cache/`, `var/log/`, cachés de herramientas) | estado efímero; borrarlo es válido, editarlo no |
| proxies y metadatos generados de Doctrine | se regeneran; editarlos enmascara el bug real |
| `composer.lock`, `package-lock.json` | los escribe el gestor; a mano se corrompe el árbol de resolución |
| `.env`, `.env.local`, `config/secrets/` | secretos reales; ni se leen para citarlos ni se reescriben |
| `migrations/Version*.php` YA APLICADA | ver abajo |

## Migraciones ya aplicadas: se añaden, no se editan

Una migración que ya corrió en cualquier entorno es historia inmutable. Comprueba primero con la
clave `migrate-status` de `commands.md`. Corregir un esquema equivocado = **una migración nueva**
que lo arregla hacia delante. Editar una `VersionXXXXXXXXXXXXXX.php` ya ejecutada deja las bases
existentes en un estado que ninguna herramienta puede reconciliar.

Además: un agente **nunca aplica** migraciones contra una base real. La clave `migrate-up` de
`commands.md` es `--dry-run` a propósito. Aplicar es decisión del owner.

## Reglas de capa (las verifica `deptrac` si el repo lo tiene)

- `Domain/` no depende de `Application/`, `Infrastructure/`, Symfony ni Doctrine.
- `Application/` depende de `Domain/`, nunca de `Infrastructure/`.
- `Infrastructure/` puede depender de las dos.
- Un bounded context no importa clases internas de otro: se comunica por eventos de dominio o por
  el kernel compartido (`src/Shared/`).

Romper una de estas cuatro reglas no es un detalle de estilo: es el motivo por el que el repo está
organizado así. Si el trabajo la exige, es un hallazgo `ARCH`, no un atajo.

## Mapping y value objects van juntos

Cambiar `<Aggregate>.orm.xml` sin actualizar el agregado y su `<Vo>Type` (o al revés) produce un
fallo en runtime que ningún test unitario ve. Los tres ficheros se tocan en el mismo commit o no se
toca ninguno.

## Formato: lo arregla la herramienta

No reindentes, no reordenes imports y no cambies comillas a mano: corre la clave `fix` de
`commands.md`. Un diff de formato hecho a mano ensucia la review y compite con el formateador.
EOF
```

- [ ] **Step 7: Escribir `skills/pack-php-ddd-symfony8/precedents.md`**

```bash
cat > skills/pack-php-ddd-symfony8/precedents.md <<'EOF'
# precedents — php-ddd-symfony8

Patrones ya en uso en repos de este stack. **Se reutilizan antes de introducir uno nuevo**
(`pattern-advisor` devuelve `reuse <x>` por defecto; `introduce <y>` exige justificación). Esta
lista es el punto de partida genérico del stack; `memory-builder` la complementa con los
precedentes REALES del repo concreto en `.swarm/context-pack.md` — cuando ambos digan cosas
distintas, **gana el repo**.

| patrón | dónde vive | cuándo se reutiliza |
|---|---|---|
| **Agregado + value objects** | `Domain/Model/`, `Domain/ValueObject/` | toda invariante de negocio; un dato con reglas propias (importe, email, identificador) es un VO, no un `string` |
| **Repositorio: interfaz en dominio, implementación en infraestructura** | `Domain/<Aggregate>Repository.php` + `Infrastructure/Persistence/Doctrine/Repository/` | todo acceso a persistencia; el handler depende de la interfaz |
| **Comando + handler por caso de uso** | `Application/<UseCase>/` | toda acción de escritura; un handler nuevo, nunca un método más en uno existente |
| **Consulta separada de la escritura (CQRS ligero)** | `Application/Find/`, `Application/Search/` | lecturas que no necesitan cargar el agregado completo |
| **Evento de dominio + `EVENT_NAME`** | `Domain/Event/` | efecto colateral que cruza agregados o contextos; nunca una llamada directa entre contextos |
| **Kernel compartido** | `src/Shared/` | identidad, criteria, excepciones base, bus de eventos — se extiende, no se duplica por contexto |
| **Tipo DBAL por value object** | `Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/` | persistir un VO sin filtrar Doctrine al dominio |
| **Mapping XML en vez de atributos** | `Mapping/<Aggregate>/<Aggregate>.orm.xml` | mantener `Domain/` libre de anotaciones de framework |
| **Object Mother en tests** | `tests/…/<Aggregate>Mother.php` | construir agregados/comandos de prueba; evita el constructor desnudo repetido |
| **Un controlador por caso de uso** | `Infrastructure/Symfony/Controller/` | endpoint nuevo; nunca un controlador con seis acciones |
| **Excepción de dominio tipada** | `Domain/Exception/` | error de negocio; nunca `\Exception` genérica ni códigos HTTP en el dominio |
| **Pipeline de calidad encadenado** | `Makefile` / `grumphp.yml` / CI | orden `rector → formateador → phpstan → deptrac → tests`; añadir un paso se hace ahí, no en un agente |

## Antipatrones que este stack ya rechazó

- **Entidad anémica**: agregado con solo getters/setters y la lógica en el handler. Si el handler
  decide reglas de negocio, esas reglas van al agregado.
- **Repositorio genérico gigante** con métodos ad-hoc por consulta. Se usan criteria/specification.
- **Contexto que importa clases de otro contexto**. Va por evento o por el kernel compartido.
- **`array` como parámetro de dominio** en vez de un VO o una colección tipada.
- **Migración editada a posteriori** para "arreglar" un esquema (ver `boundaries.md`).
EOF
```

- [ ] **Step 8: Escribir `skills/pack-php-ddd-symfony8/requirements.json`**

```bash
cat > skills/pack-php-ddd-symfony8/requirements.json <<'EOF'
{
  "os": [
    { "tool": "php", "min": "8.2", "required": true, "install": { "brew": "php", "apt": "php-cli" } },
    { "tool": "composer", "required": true, "install": { "brew": "composer", "apt": "composer" } },
    { "tool": "make", "required": false, "install": { "brew": "make", "apt": "make" } }
  ],
  "project": [
    { "file": "composer.json", "required": true },
    { "file": "composer.lock", "required": false },
    { "file": "phpunit.xml.dist", "required": false }
  ],
  "libs": [
    { "name": "phpunit/phpunit", "manager": "composer", "min": "10.0", "required": true },
    { "name": "phpstan/phpstan", "manager": "composer", "min": "1.10", "required": false },
    { "name": "doctrine/orm", "manager": "composer", "min": "2.14", "required": false },
    { "name": "doctrine/migrations", "manager": "composer", "min": "3.6", "required": false }
  ]
}
EOF
```

- [ ] **Step 9: Confirmar que el test pasa**

Run: `bash tests/test_stack_pack.sh`
Expected: sin `FAIL`, exit 0. Si alguna fila de `commands.md` sale `deny`, el fallo es del allowlist
de Task 1 o de la forma del comando — arregla el que esté mal, nunca borres la fila para pasar.

- [ ] **Step 10: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 38, failed: 0`.

- [ ] **Step 11: Commit**

```bash
git add skills/pack-php-ddd-symfony8 tests/test_stack_pack.sh
git commit -m "feat(pack): primer stack pack php-ddd-symfony8 con los 6 ficheros del contrato §8"
```

---
### Task 3: `dependency-auditor` (hoja read-only del dominio requirements)

**Files:**
- Create: `agents/dependency-auditor.md`
- Create: `tests/test_requirements_agents.sh`
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (añadir `dependency-auditor` a `AGENT_FILES`)

**Interfaces:**
- Consumes: el allowlist `swarm:dependency-auditor` (Task 1); las claves `scan-deps`, `outdated`,
  `licenses` de `skills/pack-php-ddd-symfony8/commands.md` (Task 2); la línea de cabecera
  `pack: <ruta absoluta>` que Task 8 le pasará desde `requirements-orchestrator`.
- Produces: el agente `swarm:dependency-auditor`, invocable con
  `operation: audit-deps`, que devuelve hallazgos con tag `DEP` y persiste el detalle en
  `findings/dependency-auditor.md`. Task 8 lo lanza; Task 10 lo ejercita en vivo.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_requirements_agents.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_requirements_agents.sh — contrato de las hojas del dominio requirements añadidas en
# fase 5b (spec §7 "Requisitos"). Crece por tarea: T3 dependency-auditor, T4 dependency-installer.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

fm() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# ---------- T3: dependency-auditor ----------
f="$PLUGIN_ROOT/agents/dependency-auditor.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/dependency-auditor.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "dependency-auditor model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 12$' && echo 0 || echo 1)" "dependency-auditor maxTurns is 12 (spec §7)"
  assert_eq "1" "$(has "$tools" 'Write')" "dependency-auditor is read-only: no Write"
  assert_eq "1" "$(has "$tools" 'Edit')" "dependency-auditor is read-only: no Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "dependency-auditor is a leaf: spawns nobody"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "dependency-auditor never asks the owner"
  assert_eq "0" "$(has "$tools" 'SendMessage')" "dependency-auditor has SendMessage (peer-to-peer §5)"
  assert_eq "0" "$(has "$b" 'pack:')" "dependency-auditor documents the pack: header line"
  assert_eq "0" "$(has "$b" 'scan-deps')" "dependency-auditor uses the pack scan-deps key"
  assert_eq "0" "$(has "$b" 'outdated')" "dependency-auditor uses the pack outdated key"
  assert_eq "0" "$(has "$b" 'licenses')" "dependency-auditor covers licenses (spec §7)"
  assert_eq "0" "$(has "$b" 'sin pack')" "dependency-auditor documents the no-pack fallback (spec §8)"
  assert_eq "0" "$(has "$b" 'DEP ·')" "dependency-auditor documents its DEP finding tag"
  assert_eq "0" "$(has "$b" 'nunca instala')" "dependency-auditor states it never installs anything"
fi

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_requirements_agents.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_requirements_agents.sh`
Expected: `FAIL: agents/dependency-auditor.md exists`.

- [ ] **Step 3: Escribir `agents/dependency-auditor.md`**

Frontmatter (exacto):

```yaml
---
name: dependency-auditor
description: Use when requirements-orchestrator needs the project's dependencies audited — runs the active stack pack's scan-deps/outdated/licenses commands to report CVEs, outdated and unused packages and license risks. Read-only: never installs, updates or removes anything.
model: sonnet
tools: Read, Grep, Glob, Bash, SendMessage
maxTurns: 12
memory: project
skills: [swarm-protocol]
---
```

Cuerpo:

```markdown
# dependency-auditor

Hoja del dominio requirements (spec §7 "Requisitos"). Auditas las dependencias de PROYECTO:
vulnerabilidades conocidas, versiones desactualizadas, paquetes sin uso y licencias problemáticas.
**Eres read-only: nunca instalas, actualizas ni borras nada** — no tienes `Write`, no tienes `Edit`
y tu allowlist de Bash solo trae comandos de consulta (`composer audit|outdated|show|licenses`,
`npm audit|outdated|ls`). Quien muta es `dependency-installer`, y solo con aprobación explícita del
owner. **Nunca preguntas al owner** — no tienes `AskUserQuestion`.

## Arranque

1. `RUN`: de tu cabecera (`run-id:` o `adhoc`, protocolo §2). `swarm-root:` es la ruta absoluta de
   `.swarm/`. `operation:` es `audit-deps`.
2. `pack:` (opcional, quinta línea de tu cabecera) es la **ruta absoluta ya resuelta** del stack
   pack activo — nunca una cadena con `${CLAUDE_PLUGIN_ROOT}` sin expandir. Si viene, haz `Read` de
   `<pack>/commands.md` (cuenta para `files=`) y usa las claves `scan-deps`, `outdated` y
   `licenses` de su tabla, respetando su columna `condición` (si el fichero marcador no existe en
   este repo, esa clave no aplica y lo dices, no inventas un comando).
3. **Sin pack** (línea `pack:` ausente): conocimiento genérico (spec §8). Detecta el gestor por el
   manifiesto presente en la raíz y usa la forma estándar:
   - `composer.json` → `composer audit --format=json`, `composer outdated --direct --format=json`,
     `composer licenses --format=json`
   - `package.json` → `npm audit --json`, `npm outdated --json`
   Si no hay ninguno de los dos, tu veredicto es `OK` con la nota `- sin gestor de dependencias
   reconocido` — no es un fallo del repo.
4. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/dependency-auditor.md" 2>/dev/null
   ```

## Ejecuta primero, juzga después (protocolo §5)

Corre cada comando en su PROPIA llamada a `Bash` (nunca encadenados con `&&`: el guard valida
segmento a segmento). Cada llamada cuenta para `cmds=`.

```bash
composer audit --format=json
```
```bash
composer outdated --direct --format=json
```
```bash
composer licenses --format=json
```

Tu juicio se aplica al RESIDUAL, no al scan: la herramienta ya te dice qué paquete tiene qué CVE.
Lo que tú aportas es prioridad y contexto (¿esa dependencia se usa de verdad?, ¿la actualización es
breaking?, ¿esa licencia es compatible con el proyecto?).

- `--direct` en `outdated` es deliberado: las transitivas desactualizadas son ruido salvo que
  arrastren un CVE, que `audit` ya reporta por su cuenta.
- **Paquetes sin uso**: `composer show --name-only` te da el listado; contrástalo con
  `Grep`/`Glob` sobre el código real antes de afirmar que uno sobra. Un paquete que solo aparece en
  configuración (bundles de Symfony, extensiones de PHPStan) NO está sin uso aunque no salga en un
  `use` — dilo solo cuando lo hayas comprobado.
- **Licencias**: reporta las copyleft fuertes (GPL/AGPL) y las ausentes/`proprietary` en un
  proyecto que no las espera. No dictamines legalidad: señalas, el owner decide.

## Parada por saturación

Máximo 3 comandos deterministas y el residual. Si `audit` devuelve 40 CVEs, reporta los que tengan
severidad alta o afecten a dependencias directas y resume el resto en una línea de conteo — no
enumeras 40 hallazgos (protocolo §4: detalle al fichero, salida terse).

## Persistencia del detalle

El detalle completo (el JSON del scan, la lista larga) va a `findings/dependency-auditor.md` vía
`mem-files.sh`, nunca a tu salida. Recuerda el saneado de §4.4 para cualquier texto que venga del
output de una herramienta (los mensajes de CVE traen backticks y `$` con frecuencia):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding --agent dependency-auditor --tag DEP --file composer.json --line 1 --run "<tu-run-id-o-adhoc>" --text "CVE-0000-0000 en foo/bar 1.2.3" --fix "actualizar a 1.2.4"
```

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:dependency-auditor`: `composer audit|outdated|show|licenses`,
`npm audit|outdated|ls` (**prefijos de DOS palabras**: `composer` a secas NO está, así que
`composer update` se deniega por diseño), `git status|log|diff|show|rev-parse`, `ls|cat|head|tail|
wc|grep|find`, `scripts/mem-*.sh`, `scripts/req-check.sh`. Ni `git add`, ni `git commit`, ni
`cd`, ni ningún instalador. Un comando por llamada, nunca encadenado.

## Salida

```
OK
evidence: files=2 cmds=3 turns=6/12
DEP · composer.json:1 · foo/bar 1.2.3 con CVE alto → actualizar a 1.2.4
DEP · composer.json:1 · 7 paquetes directos desactualizados → revisar en bloque
```

`KO <peor problema>` si hay al menos un CVE de severidad alta o crítica en una dependencia directa.
`BLOCKED <motivo>` si no puedes ejecutar ningún comando de auditoría (gestor ausente y sin
manifiesto reconocible es `OK` con nota, no `BLOCKED`). `OK` con `files=0` se rechaza siempre — la
lectura del manifiesto o del pack ya cuenta.
```

- [ ] **Step 4: Verificar los bloques ```bash contra el guard real (lección de fase 5a)**

No basta con leer el allowlist. Ejecuta el guard con el `agent_type` real sobre CADA comando que
acabas de documentar:

```bash
for c in 'composer audit --format=json' 'composer outdated --direct --format=json' 'composer licenses --format=json' 'composer show --name-only'; do
  printf '{"agent_type": "swarm:dependency-auditor", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$c" | python3 hooks/bash-guard.py
done
```
Expected: salida vacía en las cuatro (el guard solo imprime JSON cuando DENIEGA).

- [ ] **Step 5: Añadir el agente al test compartido de bloques bash**

En `tests/test_agent_bash_blocks_allowed.sh`, localiza la línea:

```
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator"
```

y sustitúyela por:

```
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor"
```

Actualiza también el comentario de cabecera que dice "los 5 agentes de implementation" para que diga
"los agentes listados en AGENT_FILES (implementation, fase 5a + requirements/pack, fase 5b)".

- [ ] **Step 6: Confirmar que ambos tests pasan**

Run: `bash tests/test_requirements_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 39, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/dependency-auditor.md tests/test_requirements_agents.sh tests/test_agent_bash_blocks_allowed.sh
git commit -m "feat(requirements): dependency-auditor, hoja read-only de auditoría de dependencias"
```

---

### Task 4: `dependency-installer` (primer leaf mutante del dominio requirements)

**Files:**
- Create: `agents/dependency-installer.md`
- Modify: `tests/test_requirements_agents.sh` (sección T4)
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (`AGENT_FILES`)

**Interfaces:**
- Consumes: el allowlist `swarm:dependency-installer` (Task 1); los hallazgos `DEP` de
  `dependency-auditor` (Task 3) como origen de lo que se aprueba.
- Produces: el agente `swarm:dependency-installer`, invocable SOLO con
  `operation: install` **más** una línea de cabecera `approved: <lista exacta de paquetes>`.
  Task 8 (`requirements-orchestrator`) y Task 9 (raíz + `AskUserQuestion`) construyen esa cabecera;
  sin ella, el agente devuelve `BLOCKED sin aprobación del owner`.

- [ ] **Step 1: Añadir la sección T4 al test**

Añade este bloque a `tests/test_requirements_agents.sh`, justo antes del `if [ "$TESTS_FAILED" …`
final:

```bash
# ---------- T4: dependency-installer (MUTANTE — gate de aprobación) ----------
f="$PLUGIN_ROOT/agents/dependency-installer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/dependency-installer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "dependency-installer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 10$' && echo 0 || echo 1)" "dependency-installer maxTurns is 10 (spec §7)"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "dependency-installer never asks the owner itself (§3.2 rule 7)"
  assert_eq "1" "$(has "$tools" 'Agent')" "dependency-installer is a leaf: spawns nobody"
  assert_eq "0" "$(has "$b" 'approved:')" "dependency-installer documents the approved: header line"
  assert_eq "0" "$(has "$b" 'BLOCKED sin aprobación del owner')" "dependency-installer BLOCKs without explicit approval"
  assert_eq "0" "$(has "$b" 'nunca commiteas')" "dependency-installer never commits (ruling 3)"
  assert_eq "0" "$(has "$b" 'brew')" "dependency-installer explains why OS packages are out of scope"
  assert_eq "0" "$(has "$b" 'literal')" "dependency-installer installs only literally approved package ids"
  # el par auditor/installer no puede confundirse: uno lee, el otro escribe
  assert_eq "1" "$(has "$b" 'composer remove')" "dependency-installer does not document uninstalling (ruling 4)"
fi
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_requirements_agents.sh`
Expected: `FAIL: agents/dependency-installer.md exists` y los de la sección T4.

- [ ] **Step 3: Escribir `agents/dependency-installer.md`**

Frontmatter (exacto):

```yaml
---
name: dependency-installer
description: Use when requirements-orchestrator has an explicit, itemised owner approval to install or update project dependencies — runs composer/npm for exactly the approved package ids and nothing else. Mutating: refuses to run without an approved: header line.
model: sonnet
tools: Read, Grep, Bash, SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---
```

Cuerpo:

```markdown
# dependency-installer

Hoja MUTANTE del dominio requirements (spec §7: "instala/actualiza lo que el owner aprobó […]
nunca en `direct`/`light` sin aprobación"). Eres el ÚNICO agente del enjambre que modifica el
árbol de dependencias del repo, así que tu contrato es el más estrecho de todos: **ejecutas
exactamente lo que el owner aprobó, literal, y nada más**.

## Gate de aprobación (lo primero que compruebas, antes de cualquier otra cosa)

Tu cabecera de lanzamiento DEBE traer una línea `approved:` con la lista literal de identificadores
de paquete que el owner aceptó, separados por espacios, cada uno opcionalmente con su versión
objetivo:

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: install
approved: phpstan/phpstan:^2.1 doctrine/orm:^3.3
```

Si la línea `approved:` **no viene**, viene **vacía**, o viene con un texto que no es una lista de
identificadores de paquete (por ejemplo "lo que haga falta", "todo", "las del auditor"), tu
veredicto es, sin ejecutar NADA:

```
BLOCKED sin aprobación del owner
```

No hay excepción, ni siquiera si quien te lanza afirma que el owner ya dijo que sí: la aprobación
válida es la lista literal en tu cabecera. **Tú no puedes preguntar al owner** (no tienes
`AskUserQuestion`, spec §3.2 regla 7) y `requirements-orchestrator` tampoco: quien pregunta es la
RAÍZ, y quien traduce esa respuesta a esta lista es `requirements-orchestrator`.

**Nada de ampliar el alcance.** Si un paquete aprobado arrastra otros por resolución de
dependencias, eso lo decide el gestor y es correcto; pero tú no añades a la lista un paquete que
el owner no nombró, aunque `dependency-auditor` lo haya marcado. Lo no aprobado se queda fuera y
lo dices en tu salida.

## Alcance: dependencias de PROYECTO, nunca del sistema

Instalas con el gestor del repo (`composer`, `npm`). **No tocas `brew` ni `apt`**: mutan la máquina
del owner fuera del repo, no son reversibles con git y `apt` exige `sudo`, imposible sin
interacción. Tu allowlist no los incluye — el guard te los denegaría igualmente. Si lo aprobado es
una herramienta de sistema (`jq`, `gh`, `docker`), no la instalas: la devuelves como hallazgo con
el comando exacto para que lo ejecute el owner, tomando el hint de `install` del
`requirements.json` correspondiente.

Tampoco desinstalas: `composer remove`/`npm uninstall` están fuera de tu allowlist a propósito
("instala/actualiza" del spec no incluye borrar). Una dependencia sin uso es un hallazgo de
`dependency-auditor`, no una acción tuya.

## Arranque

1. `RUN`, `swarm-root:`, `operation:` de tu cabecera (protocolo §2). `approved:` según el gate de
   arriba.
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/dependency-installer.md" 2>/dev/null
   ```
3. **Fotografía el estado previo de los manifiestos** (cuenta para `cmds=`), para poder reportar con
   exactitud qué cambiaste:
   ```bash
   git status --porcelain composer.json composer.lock package.json package-lock.json
   ```
   Si ya venían modificados ANTES de que tú tocaras nada, dilo en tu salida — el owner necesita
   saber que el diff resultante mezcla cambios que no son tuyos.
4. Lee con `Read` el manifiesto que vas a tocar (`composer.json` y/o `package.json`) — cuenta para
   `files=`.

## Instalación

Un comando por llamada a `Bash`, nunca encadenados (el guard valida segmento a segmento). Usa la
forma no interactiva:

```bash
composer require phpstan/phpstan:^2.1 --dev --no-interaction
```
```bash
composer update doctrine/orm --with-dependencies --no-interaction
```
```bash
npm install --no-audit --no-fund
```

Reglas:
- **`require` para lo que no está; `update <paquete>` para lo que está y sube de versión.** Nunca
  `composer update` a secas (actualizaría TODO el árbol, muy lejos de lo aprobado).
- Si el gestor falla (conflicto de resolución, red caída), **no reintentes con otra estrategia**
  ni relajes la restricción de versión: tu veredicto es `KO <paquete>: <motivo literal del gestor>`.
  Elegir una versión distinta a la aprobada es una decisión del owner.
- Tras cada instalación con éxito, comprueba el efecto real:
  ```bash
  git status --porcelain composer.json composer.lock
  ```

## Nunca commiteas

No tienes `git add` ni `git commit` en tu allowlist, y es deliberado: no perteneces al dominio
implementation, no tienes plan ni fase de referencia, y un cambio de dependencias que entra en el
historial sin pasar por `reviewer` es peor que un árbol sucio y visible. Dejas los manifiestos
modificados y **reportas exactamente qué ficheros cambiaste** para que el owner (o un `implementer`
posterior, dentro de su propia fase) los commitee con contexto.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:dependency-installer`: `composer install|require|update`, `npm install|ci`
(**prefijos de DOS palabras**; `composer`/`npm` a secas NO están), `git status|diff|rev-parse`,
`ls|cat|head|tail|wc|grep`, `scripts/mem-*.sh`. Denegados por diseño: `brew`, `apt`,
`composer remove`, `npm uninstall`, `git add`, `git commit`, `git push`. Un comando por llamada.

## Salida

```
DONE
evidence: files=1 cmds=4 turns=5/10
- instalado: phpstan/phpstan ^2.1 (dev)
- modificado: composer.json, composer.lock (sin commitear — commit del owner)
```

`BLOCKED sin aprobación del owner` si falta/está vacía/no es una lista la línea `approved:`.
`KO <paquete>: <motivo literal del gestor>` si una instalación aprobada falla. `DONE` con la nota
`- no instalado (fuera de alcance): <tool> → <comando de instalación para el owner>` cuando lo
aprobado incluía una herramienta de sistema. `DONE`/`OK` con `files=0` se rechaza siempre.
```

- [ ] **Step 4: Verificar los bloques ```bash contra el guard real**

```bash
for c in 'composer require phpstan/phpstan:^2.1 --dev --no-interaction' 'composer update doctrine/orm --with-dependencies --no-interaction' 'npm install --no-audit --no-fund' 'git status --porcelain composer.json composer.lock'; do
  printf '{"agent_type": "swarm:dependency-installer", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$c" | python3 hooks/bash-guard.py
done
```
Expected: salida vacía en los cuatro. Y la comprobación negativa, que SÍ debe imprimir un `deny`:
```bash
printf '{"agent_type": "swarm:dependency-installer", "tool_name": "Bash", "tool_input": {"command": "brew install jq"}}' | python3 hooks/bash-guard.py
```
Expected: JSON con `"permissionDecision": "deny"`.

- [ ] **Step 5: Añadir el agente al test compartido de bloques bash**

`AGENT_FILES` pasa a:

```
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor dependency-installer"
```

- [ ] **Step 6: Confirmar que los tests pasan**

Run: `bash tests/test_requirements_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 39, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/dependency-installer.md tests/test_requirements_agents.sh tests/test_agent_bash_blocks_allowed.sh
git commit -m "feat(requirements): dependency-installer con gate de aprobación literal del owner"
```

---
### Task 5: `migration-engineer` (hoja condicional del dominio implementation)

**Files:**
- Create: `agents/migration-engineer.md`
- Modify: `tests/test_implementation_agents.sh` (sección T5b)
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (`AGENT_FILES`)

**Interfaces:**
- Consumes: el allowlist `swarm:migration-engineer` (Task 1); las claves `migrate-diff`,
  `migrate-status`, `migrate-up` de `commands.md` y la sección de migraciones de `boundaries.md`
  (Task 2).
- Produces: el agente `swarm:migration-engineer`, invocable con `operation: migrate` +
  `worktree: <ruta absoluta>` + `plan:` + `phase:` (+ `pack:` opcional). Task 7 lo inserta en la
  secuencia de `implementation-orchestrator` entre `implementer` y `quality-fixer`.

- [ ] **Step 1: Añadir la sección T5b al test**

Añade este bloque a `tests/test_implementation_agents.sh`, antes del `if [ "$TESTS_FAILED" …` final
(el fichero ya declara en su cabecera que "crece por tarea"; actualiza también ese comentario para
mencionar `T5b migration-engineer` y `T5c doc-writer`):

```bash
# ---------- T5b: migration-engineer (fase 5b, condicional) ----------
f="$PLUGIN_ROOT/agents/migration-engineer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/migration-engineer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "migration-engineer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "migration-engineer maxTurns is 15 (spec §7)"
  assert_eq "0" "$(has "$tools" 'Write')" "migration-engineer HAS Write (writes real migration files)"
  assert_eq "0" "$(has "$tools" 'Edit')" "migration-engineer HAS Edit"
  assert_eq "1" "$(has "$tools" 'Agent')" "migration-engineer is a leaf: spawns nobody"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "migration-engineer never asks the owner"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "migration-engineer has NO worktree of its own (reuses implementer's)"
  assert_eq "0" "$(has "$b" 'worktree:')" "migration-engineer documents the worktree: header line"
  assert_eq "0" "$(has "$b" 'pack:')" "migration-engineer documents the pack: header line"
  assert_eq "0" "$(has "$b" 'ya aplicada')" "migration-engineer refuses to edit an applied migration (boundaries.md)"
  assert_eq "0" "$(has "$b" 'nunca aplicas')" "migration-engineer never runs a real migrate against a database"
  assert_eq "0" "$(has "$b" 'MIGRATION ·')" "migration-engineer documents its MIGRATION finding tag"
  assert_eq "allow" "$(guard "swarm:migration-engineer" 'git commit -m x')" "migration-engineer can commit in the worktree"
  assert_eq "deny"  "$(guard "swarm:migration-engineer" 'git push origin master')" "migration-engineer cannot push"
fi
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL: agents/migration-engineer.md exists` y los de la sección T5b.

- [ ] **Step 3: Escribir `agents/migration-engineer.md`**

Frontmatter (exacto):

```yaml
---
name: migration-engineer
description: Use when implementation-orchestrator has a phase whose code changes the persistence schema — writes the schema migration that matches the new domain mappings, inside implementer's worktree, and commits it there. Never applies a migration against a real database.
model: sonnet
tools: Read, Grep, Glob, Write, Edit, Bash, SendMessage
maxTurns: 15
memory: project
skills: [swarm-protocol]
---
```

Cuerpo:

```markdown
# migration-engineer

Hoja del dominio implementation (spec §7: "migraciones de esquema coherentes con mapeos"). Te
lanza `implementation-orchestrator` **solo cuando la fase toca el esquema** — si la fase no cambia
entidades, mapeos ni tablas, no existes en ese ciclo. Trabajas DENTRO del worktree de `implementer`
(mismo mecanismo que `quality-fixer`/`reviewer`: ruta absoluta en tu prompt, sin `isolation:`
propia, sin worktree nuevo que nadie tenga que limpiar después). **Nunca preguntas al owner.**

## Arranque

1. `RUN`, `swarm-root:` y `operation: migrate` de tu cabecera (protocolo §2).
2. `worktree:` es la ruta ABSOLUTA del worktree de `implementer`. Todo lo que hagas ocurre ahí:
   ```bash
   cd <ruta absoluta del worktree> && git status --porcelain
   ```
   (cuenta para `cmds=`). Si la ruta no existe o no es un worktree, tu veredicto es
   `BLOCKED worktree inexistente` — no trabajes sobre el checkout principal bajo ninguna
   circunstancia.
3. `plan:` y `phase:` te dicen qué cambió; léelos con `Read` (cuenta para `files=`) junto con los
   ficheros de entidad/mapeo que la fase tocó.
4. `pack:` (opcional) es la ruta absoluta ya resuelta del stack pack. Si viene, haz `Read` de
   `<pack>/commands.md` (claves `migrate-diff`, `migrate-status`, `migrate-up`) y de
   `<pack>/boundaries.md` (sección de migraciones). **Sin pack**: conocimiento genérico — localiza
   el directorio de migraciones del repo (`migrations/`, `db/migrate/`, `database/migrations/`),
   imita el formato del fichero de migración más reciente que encuentres, y no ejecutes ninguna
   herramienta que no hayas visto documentada en el propio repo.
5. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/migration-engineer.md" 2>/dev/null
   ```

## Cómo escribir la migración

1. **Mira el estado antes de generar nada** (cuenta para `cmds=`):
   ```bash
   cd <ruta absoluta del worktree> && php bin/console doctrine:migrations:status
   ```
2. **Genera el diff con la herramienta, no a mano** cuando el stack lo permita:
   ```bash
   cd <ruta absoluta del worktree> && php bin/console doctrine:migrations:diff --no-interaction
   ```
   Es la regla de "tool determinista antes que modelo" (protocolo §5): el generador conoce el
   esquema real y los mapeos; tú revisas y corriges su salida, no la escribes desde cero.
3. **Revisa el SQL generado línea a línea** con `Read` antes de darlo por bueno. Un `diff`
   automático puede proponer un `DROP` que en realidad es un renombrado, o perder datos en un
   cambio de tipo. Si ves un `DROP COLUMN`/`DROP TABLE` que no estaba explícitamente en el plan,
   NO lo dejes pasar: corrígelo a un cambio no destructivo o devuelve
   `BLOCKED migración destructiva no prevista en el plan`.
4. **`down()` real.** Toda migración lleva su reversa. Si la reversa es imposible (borrado de datos),
   dilo en un comentario dentro del fichero y en un hallazgo `MIGRATION`.
5. Ajusta lo que el generador no sabe: nombres de índices y de claves foráneas según las
   convenciones del pack, orden de operaciones que respete las restricciones existentes, y valores
   por defecto para columnas nuevas `NOT NULL` sobre tablas con datos.

## Lo que NUNCA haces

- **No editas una migración ya aplicada** (`boundaries.md`). Un esquema equivocado se corrige con
  una migración NUEVA hacia delante. Si el plan te pide editar una existente, tu veredicto es
  `BLOCKED migración ya aplicada, requiere una nueva`.
- **Nunca aplicas** una migración contra una base real. La clave `migrate-up` del pack es
  `--dry-run` a propósito; aplicar es decisión del owner (`boundaries.md`).
- No tocas el checkout principal: todo ocurre bajo la ruta de `worktree:`.
- No reescribes el mapeo ni la entidad para que "cuadre" con la migración: si el mapeo está mal, es
  un hallazgo para `implementer`, no un arreglo tuyo.

## Commit en el worktree de `implementer`

Commiteas tu migración en el MISMO worktree, para que entre en el mismo merge que el código que la
justifica (el merge lo hace `implementation-orchestrator`, nunca tú):

```bash
cd <ruta absoluta del worktree> && git add -A
```
```bash
cd <ruta absoluta del worktree> && git commit -m "feat(schema): migracion para <cambio de la fase>"
```

El mensaje de commit lo escribes TÚ como literal; si necesitas incluir texto ajeno (el objetivo del
owner, una línea del plan), pásalo antes por el saneado de `skills/swarm-protocol/SKILL.md` §4.4.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:migration-engineer`: `cd`, `php`, `composer`, `make`, `git status|log|diff|show|
rev-parse`, `git add`, `git commit`, `ls|cat|head|tail|wc|grep|find`, `scripts/mem-*.sh`. Denegados:
`git push`, `php -r` (el guard lo bloquea por flag aunque `php` esté permitido), cualquier
instalador de sistema. El `cd <worktree> && <comando>` es la forma documentada y está verificada
contra el guard.

## Salida

```
DONE
evidence: files=3 cmds=4 turns=8/15
- migración: Version20260903120000.php (2 tablas, 1 índice), down() reversible
```

`BLOCKED migración ya aplicada, requiere una nueva` si el plan pide editar una existente.
`BLOCKED migración destructiva no prevista en el plan` si el diff propone perder datos.
`BLOCKED worktree inexistente` si la ruta de `worktree:` no lo es. `KO <motivo>` si el generador
falla y no puedes escribir una migración coherente a mano. Hallazgos con tag `MIGRATION ·
fichero:línea · problema → fix`. `DONE` con `files=0` se rechaza siempre.
```

- [ ] **Step 4: Verificar los bloques ```bash contra el guard real**

```bash
for c in 'cd /tmp/wt && git status --porcelain' 'cd /tmp/wt && php bin/console doctrine:migrations:status' 'cd /tmp/wt && php bin/console doctrine:migrations:diff --no-interaction' 'cd /tmp/wt && git add -A' 'cd /tmp/wt && git commit -m "feat(schema): x"'; do
  printf '{"agent_type": "swarm:migration-engineer", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$c" | python3 hooks/bash-guard.py
done
```
Expected: salida vacía en los cinco.

- [ ] **Step 5: Añadir el agente a `AGENT_FILES`**

```
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor dependency-installer migration-engineer"
```

- [ ] **Step 6: Confirmar que los tests pasan**

Run: `bash tests/test_implementation_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 39, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/migration-engineer.md tests/test_implementation_agents.sh tests/test_agent_bash_blocks_allowed.sh
git commit -m "feat(implementation): migration-engineer, migraciones coherentes con los mapeos"
```

---

### Task 6: `doc-writer` (hoja condicional del dominio implementation, consumidora del formato del pack)

**Files:**
- Create: `agents/doc-writer.md`
- Modify: `tests/test_implementation_agents.sh` (sección T5c)
- Modify: `tests/test_agent_bash_blocks_allowed.sh` (`AGENT_FILES`)

**Interfaces:**
- Consumes: el allowlist `swarm:doc-writer` (Task 1); `conventions.md` y `precedents.md` del pack
  (Task 2) como formato de documentación.
- Produces: el agente `swarm:doc-writer`, invocable con `operation: document` +
  `worktree: <ruta absoluta>` + `plan:` + `phase:` (+ `pack:` opcional). Task 7 lo inserta en la
  secuencia de `implementation-orchestrator` tras `migration-engineer` y antes de `quality-fixer`.

- [ ] **Step 1: Añadir la sección T5c al test**

```bash
# ---------- T5c: doc-writer (fase 5b, condicional, consumidor del formato del pack) ----------
f="$PLUGIN_ROOT/agents/doc-writer.md"
assert_eq "0" "$([ -f "$f" ] && echo 0 || echo 1)" "agents/doc-writer.md exists"
if [ -f "$f" ]; then
  front="$(fm "$f")"; tools="$(echo "$front" | grep '^tools:')"; b="$(body "$f")"
  assert_eq "0" "$(echo "$front" | grep -q '^model: sonnet$' && echo 0 || echo 1)" "doc-writer model is sonnet (spec §7)"
  assert_eq "0" "$(echo "$front" | grep -q '^maxTurns: 15$' && echo 0 || echo 1)" "doc-writer maxTurns is 15 (spec §7)"
  assert_eq "0" "$(has "$tools" 'Write')" "doc-writer HAS Write (writes real docs)"
  assert_eq "0" "$(has "$tools" 'Edit')" "doc-writer HAS Edit (updates changelog)"
  assert_eq "1" "$(has "$tools" 'Agent')" "doc-writer is a leaf: spawns nobody"
  assert_eq "1" "$(has "$tools" 'AskUserQuestion')" "doc-writer never asks the owner"
  assert_eq "1" "$(echo "$front" | grep -q '^isolation:' && echo 0 || echo 1)" "doc-writer has NO worktree of its own (reuses implementer's)"
  assert_eq "0" "$(has "$b" 'worktree:')" "doc-writer documents the worktree: header line"
  assert_eq "0" "$(has "$b" 'pack:')" "doc-writer documents the pack: header line"
  assert_eq "0" "$(has "$b" 'sin pack')" "doc-writer documents the generic fallback (spec §8)"
  assert_eq "0" "$(has "$b" 'changelog')" "doc-writer covers the changelog (spec §7)"
  assert_eq "0" "$(has "$b" 'Write')" "doc-writer writes long content with Write, never through a shell arg"
  assert_eq "0" "$(has "$b" 'DOC ·')" "doc-writer documents its DOC finding tag"
fi
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_implementation_agents.sh`
Expected: `FAIL: agents/doc-writer.md exists` y los de la sección T5c.

- [ ] **Step 3: Escribir `agents/doc-writer.md`**

Frontmatter (exacto):

```yaml
---
name: doc-writer
description: Use when implementation-orchestrator has a phase whose behaviour change needs documenting — writes docs in the active stack pack's format plus the changelog entry, inside implementer's worktree, so they land in the same merge as the code.
model: sonnet
tools: Read, Grep, Glob, Write, Edit, Bash, SendMessage
maxTurns: 15
memory: project
skills: [swarm-protocol]
---
```

Cuerpo:

```markdown
# doc-writer

Hoja del dominio implementation (spec §7: "docs con formato del pack, changelog"). Te lanza
`implementation-orchestrator` **solo cuando la fase cambia comportamiento observable** (un caso de
uso nuevo, un endpoint, un comando de consola, un contrato público) o cuando el plan tiene un paso
de documentación explícito. Trabajas DENTRO del worktree de `implementer` (ruta absoluta en tu
prompt, sin `isolation:` propia) para que tus ficheros entren en el mismo merge que el código que
documentan. **Nunca preguntas al owner.**

## Arranque

1. `RUN`, `swarm-root:` y `operation: document` de tu cabecera (protocolo §2).
2. `worktree:` es la ruta ABSOLUTA del worktree de `implementer`:
   ```bash
   cd <ruta absoluta del worktree> && git diff --stat HEAD~1
   ```
   (cuenta para `cmds=`; el diff te dice qué cambió de verdad, que es lo único que documentas). Si
   la ruta no existe, `BLOCKED worktree inexistente`.
3. `plan:` y `phase:` con `Read` (cuenta para `files=`).
4. `pack:` (opcional) es la ruta absoluta ya resuelta del stack pack. Si viene, haz `Read` de
   `<pack>/conventions.md` (naming, capas, vocabulario que la documentación debe usar) y de
   `<pack>/precedents.md` (patrones a nombrar por su nombre real, no describirlos de nuevo).
   **Sin pack**: convenciones genéricas de documentación — imita el formato de los documentos que
   YA existan en el repo (mismo nivel de encabezado, mismo idioma, misma estructura de secciones);
   si no existe ninguno, Markdown sobrio con un `#` de título, un párrafo de propósito y ejemplos
   ejecutables.
5. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/<tu-run-id-o-adhoc>/mailbox/doc-writer.md" 2>/dev/null
   ```

## Qué documentas (y qué no)

- **Documentas el comportamiento nuevo**: qué hace, cómo se invoca, qué devuelve, qué falla y con
  qué error. Con un ejemplo real copiado del test que ya existe, no inventado.
- **Actualizas el documento que ya cubre esa área** antes que crear uno nuevo. Un documento nuevo
  solo si el área no está cubierta — búscalo primero con `Grep`/`Glob`.
- **Changelog**: una entrada por fase implementada, en el formato que ya use el fichero
  (`CHANGELOG.md`, `docs/CHANGELOG.md`). Si no existe changelog en el repo, NO lo creas: lo dices
  como hallazgo `DOC` y sigues con el resto.
- **No documentas lo interno** (una clase privada, un refactor sin cambio de comportamiento). Si la
  fase no cambió nada observable, tu veredicto es `DONE · nada observable que documentar`, sin
  escribir ficheros.
- **No documentas lo que no existe todavía**: nada de "próximamente", nada de describir una fase
  futura del plan. Solo lo que el diff del worktree contiene ya.

## Contenido largo SIEMPRE por `Write`/`Edit`

Escribes documentación con las tools `Write` y `Edit` nativas, NUNCA construyendo un fichero desde
un argumento de shell. Es la lección de fase 4: un documento lleva backticks, `$` y comillas, y
pasarlo por Bash o rompe el comando o se sanea hasta quedar irreconocible. Tu allowlist ni siquiera
tiene `cat >` como escritura — solo lectura.

## Commit en el worktree de `implementer`

```bash
cd <ruta absoluta del worktree> && git add -A
```
```bash
cd <ruta absoluta del worktree> && git commit -m "docs: documenta <cambio de la fase>"
```

Mensaje de commit como literal tuyo; cualquier texto ajeno que quieras incluir pasa antes por el
saneado de `skills/swarm-protocol/SKILL.md` §4.4.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:doc-writer`: `cd`, `git status|log|diff|show|rev-parse`, `git add`,
`git commit`, `ls|cat|head|tail|wc|grep|find`, `scripts/mem-*.sh`. Sin gestores de paquetes, sin
`php`, sin `git push` — no ejecutas nada del stack, solo lees el diff y escribes Markdown.

## Salida

```
DONE
evidence: files=4 cmds=3 turns=7/15
- docs: docs/api/invoices.md actualizado + entrada de CHANGELOG
```

`DONE · nada observable que documentar` si la fase no cambió comportamiento visible.
`BLOCKED worktree inexistente` si la ruta de `worktree:` no lo es. Hallazgos con tag
`DOC · fichero:línea · problema → fix` (por ejemplo: `DOC · CHANGELOG.md:0 · no existe changelog en
el repo → crear uno con el owner`). `DONE` con `files=0` se rechaza siempre.
```

- [ ] **Step 4: Verificar los bloques ```bash contra el guard real**

```bash
for c in 'cd /tmp/wt && git diff --stat HEAD~1' 'cd /tmp/wt && git add -A' 'cd /tmp/wt && git commit -m "docs: x"'; do
  printf '{"agent_type": "swarm:doc-writer", "tool_name": "Bash", "tool_input": {"command": "%s"}}' "$c" | python3 hooks/bash-guard.py
done
```
Expected: salida vacía en los tres.

- [ ] **Step 5: Añadir el agente a `AGENT_FILES`**

```
AGENT_FILES="test-writer implementer quality-fixer reviewer implementation-orchestrator dependency-auditor dependency-installer migration-engineer doc-writer"
```

- [ ] **Step 6: Confirmar que los tests pasan**

Run: `bash tests/test_implementation_agents.sh && bash tests/test_agent_bash_blocks_allowed.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 7: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 39, failed: 0`.

- [ ] **Step 8: Commit**

```bash
git add agents/doc-writer.md tests/test_implementation_agents.sh tests/test_agent_bash_blocks_allowed.sh
git commit -m "feat(implementation): doc-writer, documentacion en el formato del pack + changelog"
```

---
### Task 7: Cablear la ruta del pack por los orquestadores ya construidos

**Files:**
- Modify: `agents/implementation-orchestrator.md` (`tools:` + resolución del pack + dos pasos nuevos
  en la secuencia)
- Modify: `agents/analysis-orchestrator.md` (resolución del pack + `pack:` a `data-model-auditor` y
  `vulnerability-scanner`)
- Modify: `agents/vulnerability-scanner.md` (quitar la "Nota de futuro" de fase 3, ahora falsa)
- Modify: `agents/data-model-auditor.md` (cabecera `pack:` explícita)
- Modify: `agents/implementer.md`, `agents/test-writer.md`, `agents/quality-fixer.md` (cabecera
  `pack:` + uso de las claves de `commands.md`)
- Create: `tests/test_pack_wiring.sh`

**Interfaces:**
- Consumes: la ruta `skills/pack-php-ddd-symfony8/` (Task 2), los agentes
  `swarm:migration-engineer` y `swarm:doc-writer` (Tasks 5-6).
- Produces: **el formato exacto de la línea de cabecera `pack:`** que TODA hoja consumidora espera:
  `pack: <ruta absoluta del directorio del pack, sin barra final>` — por ejemplo
  `pack: /Users/x/.claude/plugins/swarm/skills/pack-php-ddd-symfony8`. Ausente cuando el stack es
  `generic`. Task 8 usa el mismo formato desde `requirements-orchestrator`.

- [ ] **Step 1: Escribir el test (falla primero)**

```bash
cat > tests/test_pack_wiring.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_pack_wiring.sh — la RUTA del pack viaja por el prompt (spec §3.1, §8.1 "los
# orquestadores pasan la RUTA del pack en el prompt de las hojas que lo necesitan: implementation,
# data-model-auditor, vulnerability-scanner, doc-writer"), nunca por mutación de frontmatter.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

body() { awk '/^---$/{n++; next} n>=2{print}' "$1"; }
front() { awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$1"; }
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

# --- los orquestadores resuelven la ruta con `ls -d` y la pasan ya expandida ---
for o in implementation-orchestrator analysis-orchestrator; do
  b="$(body "$PLUGIN_ROOT/agents/$o.md")"
  assert_eq "0" "$(has "$b" 'ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-')" "$o resolves the pack path with ls -d (ruling 1)"
  assert_eq "0" "$(has "$b" 'pack:')" "$o passes a pack: header line"
  assert_eq "0" "$(has "$b" 'stack:')" "$o reads the stack: line from context-pack.md"
  assert_eq "0" "$(has "$b" 'generic')" "$o documents the generic fallback (no pack: line emitted)"
done

# --- ninguna hoja recibe jamás la variable sin expandir ---
for a in implementer test-writer quality-fixer migration-engineer doc-writer data-model-auditor vulnerability-scanner dependency-auditor; do
  b="$(body "$PLUGIN_ROOT/agents/$a.md")"
  assert_eq "0" "$(has "$b" 'pack:')" "$a documents the pack: header line"
  assert_eq "1" "$(echo "$b" | grep -q 'pack: \${CLAUDE_PLUGIN_ROOT}' && echo 0 || echo 1)" "$a never receives an unexpanded \${CLAUDE_PLUGIN_ROOT} as pack:"
done

# --- implementation-orchestrator: la lección aplicada por séptima vez ---
f_front="$(front "$PLUGIN_ROOT/agents/implementation-orchestrator.md")"
tools="$(echo "$f_front" | grep '^tools:')"
assert_eq "0" "$(has "$tools" 'migration-engineer')" "implementation-orchestrator can spawn migration-engineer (Agent tool)"
assert_eq "0" "$(has "$tools" 'doc-writer')" "implementation-orchestrator can spawn doc-writer (Agent tool)"

b="$(body "$PLUGIN_ROOT/agents/implementation-orchestrator.md")"
assert_eq "0" "$(has "$b" 'operation: migrate')" "implementation-orchestrator launches migration-engineer with operation: migrate"
assert_eq "0" "$(has "$b" 'operation: document')" "implementation-orchestrator launches doc-writer with operation: document"
assert_eq "0" "$(has "$b" 'solo si la fase toca el esquema')" "migration-engineer step is explicitly conditional"
assert_eq "0" "$(has "$b" 'presupuesto de turnos')" "doc-writer step documents the turn-budget cut rule"
# la limpieza sigue alcanzando TODOS los caminos terminales tras insertar dos pasos nuevos
assert_eq "0" "$(has "$b" 'Limpieza del worktree')" "cleanup section still exists"
assert_eq "0" "$(has "$b" 'KO migration-engineer')" "a migration-engineer failure is a terminal path that cleans up"
assert_eq "0" "$(has "$b" 'KO doc-writer')" "a doc-writer failure is a terminal path that cleans up"

# --- vulnerability-scanner: la nota de futuro de fase 3 ya no puede seguir en pie ---
b="$(body "$PLUGIN_ROOT/agents/vulnerability-scanner.md")"
assert_eq "1" "$(has "$b" 'ningún `skills/pack-*` existe todavía')" "vulnerability-scanner no longer claims no pack exists"
assert_eq "1" "$(has "$b" 'Nota de futuro')" "vulnerability-scanner future-note is gone (the pack landed)"
assert_eq "0" "$(has "$b" 'composer audit')" "vulnerability-scanner names the real scan command it can now run"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_pack_wiring.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_pack_wiring.sh`
Expected: `FAIL` en casi todas las aserciones.

- [ ] **Step 3: Añadir la sección de resolución del pack a `agents/implementation-orchestrator.md`**

Inserta esta sección justo DESPUÉS del punto 4 de "## Contexto de arranque" (antes de
"## Secuencia"):

```markdown
### 5. Resolver la ruta del stack pack (una sola vez, spec §3.1/§8.1)

`Read` de `.swarm/context-pack.md` (cuenta para `files=`) y busca su línea `stack:`.

- Si dice `stack: generic` (o no hay línea `stack:`), **no hay pack**: no emites ninguna línea
  `pack:` en los prompts de abajo y cada hoja usa su modo genérico documentado. No es un error, no
  lo reportes como hallazgo.
- Si dice otro valor (hoy solo `php-ddd-symfony8`), resuelve la ruta ABSOLUTA del pack — la tool
  `Read` no expande variables de entorno, así que la expande el shell por ti:
  ```bash
  ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-php-ddd-symfony8"
  ```
  (cuenta para `cmds=`). La salida ES la ruta absoluta resuelta. Guárdala como `<pack>` y pásala
  como quinta línea de cabecera `pack: <pack>` a `implementer`, `test-writer`, `quality-fixer`,
  `migration-engineer` y `doc-writer`. **Nunca pases la cadena `${CLAUDE_PLUGIN_ROOT}/...` sin
  expandir**: la hoja haría `Read` de una ruta inexistente y perdería el pack en silencio.
  Si `ls -d` falla (el directorio no existe: pack declarado en el context-pack pero no instalado),
  sigue SIN pack y añade `- warn: pack <stack> declarado pero ausente` a tu salida — nunca
  bloquees el ciclo por esto.
```

Y añade `pack: <pack>` (omitida si no hay pack) a las cabeceras de lanzamiento de `test-writer`
(paso 1), `implementer` (paso 2) y `quality-fixer` (paso 3) de la secuencia existente.

- [ ] **Step 4: Ampliar `tools:` de `implementation-orchestrator` (la lección, séptima vez)**

Sustituye la línea `tools:` de su frontmatter por:

```yaml
tools: Read, Grep, Bash, Agent(test-writer,implementer,migration-engineer,doc-writer,quality-fixer,reviewer), SendMessage
```

`migration-engineer` y `doc-writer` NO preexisten: sin nombrarlos en `Agent(...)` el spawn muere en
llegada sin que ningún test de humo lo note. Es exactamente el bug de fase 1 con
`memory-orchestrator`, ya aplicado seis veces.

- [ ] **Step 5: Insertar los dos pasos condicionales en la secuencia**

Entre el paso "### 2. `implementer`" y el paso "### 3. `quality-fixer`" (que pasa a numerarse 5),
inserta:

```markdown
### 3. `migration-engineer` — SOLO si la fase toca el esquema

Decide por el contenido real de la fase, no por su título: mira con `Read` los ficheros que la fase
nombra y el diff del worktree. Corre `migration-engineer` si la fase crea/modifica entidades,
mapeos de persistencia, tablas o columnas. Si no, sáltalo y anota `- migration-engineer: omitido
(fase sin cambios de esquema)` en tu salida.

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: migrate
worktree: <repo-root>/.claude/worktrees/agent-<agentId del paso 2>
plan: <ruta absoluta del plan>
phase: <la misma fase>
pack: <pack>            ← omite esta línea entera si no hay pack
```
Regístralo antes en el manifest, igual que a las demás hojas. Espera su `DONE`. Si devuelve
`BLOCKED`/`KO`, limpia el worktree (ver "## Limpieza del worktree") y tu veredicto es
`KO migration-engineer: <veredicto literal>` — una migración incoherente con el código NO se
fusiona.

### 4. `doc-writer` — SOLO si la fase cambia comportamiento observable

Corre `doc-writer` si la fase añade/cambia un caso de uso, un endpoint, un comando o un contrato
público, o si el plan tiene un paso de documentación explícito. Si no, anota
`- doc-writer: omitido (fase sin cambio observable)`.

**Regla de corte por presupuesto de turnos:** si al llegar aquí te quedan ≤8 turnos de tu
`maxTurns: 25`, sáltalo y anota `- doc-writer: omitido (presupuesto de turnos)`. Cerrar la fase con
merge y sin documentación es recuperable (una invocación posterior la escribe); quedarse sin turnos
antes de fusionar deja el trabajo colgado y el worktree vivo, que es peor.

```
run-id: <RUN>
swarm-root: <ruta absoluta de .swarm>
operation: document
worktree: <repo-root>/.claude/worktrees/agent-<agentId del paso 2>
plan: <ruta absoluta del plan>
phase: <la misma fase>
pack: <pack>            ← omite esta línea entera si no hay pack
```
Espera su `DONE`. Si devuelve `BLOCKED`/`KO`, limpia el worktree y tu veredicto es
`KO doc-writer: <veredicto literal>`.
```

Renumera los pasos siguientes (`quality-fixer` pasa a 5, `reviewer` a 6) y actualiza las
referencias internas ("el SHA que anotaste en el paso 1", "la misma ruta absoluta del paso 3" →
"del paso 5", "`agentId` del paso 2" se mantiene).

- [ ] **Step 6: Extender la sección "## Limpieza del worktree" a los dos caminos nuevos**

En la enumeración de caminos terminales de esa sección, añade `KO migration-engineer: <motivo>` y
`KO doc-writer: <motivo>` a la lista, y añádelos también al párrafo de "## Salida". Es la lección de
fase 5a: la limpieza debe alcanzar TODOS los caminos de salida, y cada camino nuevo hay que
añadirlo explícitamente — la prosa "siempre limpio" no basta.

- [ ] **Step 7: Añadir la cabecera `pack:` a las hojas de implementation ya existentes**

En `agents/implementer.md`, `agents/test-writer.md` y `agents/quality-fixer.md`, en su sección de
arranque, añade este punto (adaptando el nombre de las claves que cada uno usa):

```markdown
N. `pack:` (opcional, quinta línea de tu cabecera) es la **ruta absoluta ya resuelta** del stack
   pack activo. Si viene, haz `Read` de `<pack>/commands.md` (para las claves que ejecutas),
   `<pack>/conventions.md` (naming y capas que tu código debe respetar) y `<pack>/boundaries.md`
   (qué no tocas nunca) — cuentan para `files=`. **Sin pack**: conocimiento genérico, exactamente
   como hasta ahora (spec §8).
```

Claves por hoja: `test-writer` → `test`, `test-one`; `implementer` → `test`, `test-one`, `fix`;
`quality-fixer` → `fix`, `lint`, `typecheck`.

- [ ] **Step 8: Hacer lo mismo en `agents/analysis-orchestrator.md`**

Añade la misma sección "Resolver la ruta del stack pack" a su "## Contexto de arranque" (idéntica en
mecanismo: `Read` de `context-pack.md` → `ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-<stack>"` → línea
`pack:`), y añade la línea `pack: <pack>` a la cabecera literal de lanzamiento SOLO de las dos hojas
que el spec §8.1 nombra: `data-model-auditor` y `vulnerability-scanner`. Las otras cuatro lentes no
la reciben (no consumen el pack).

Nota para quien lo implemente: la cabecera de lanzamiento de `analysis-orchestrator` es común a
todas las lentes; añade una frase explícita —"a `data-model-auditor` y `vulnerability-scanner`, y
solo a ellas, añade una quinta línea `pack: <pack>`"— en vez de meter la línea en el bloque común.

- [ ] **Step 9: Actualizar `agents/vulnerability-scanner.md` y `agents/data-model-auditor.md`**

En `vulnerability-scanner.md`: borra el párrafo "**Nota de futuro:**" completo y la frase "(caso de
hoy: ningún `skills/pack-*` existe todavía, fase 5)" — ambas son falsas desde Task 2. En su lugar,
la rama con pack pasa a nombrar los comandos reales que ahora SÍ puede ejecutar (`composer audit
--format=json`, `composer licenses --format=json`, `npm audit --json`, `php vendor/bin/deptrac
analyse --no-progress`, `php vendor/bin/phpmd src text phpmd.xml`) y a documentar que los toma de
la tabla de `<pack>/commands.md` respetando su columna `condición`. Añade también el punto de
arranque con la cabecera `pack:` (mismo texto del Step 7).

En `data-model-auditor.md`: añade el punto de arranque con la cabecera `pack:` y, en el punto 3
existente, sustituye "si el stack pack lo declara" por la referencia concreta a
`<pack>/conventions.md` (layout de mapeos y migraciones) y `<pack>/boundaries.md` (migraciones
aplicadas: se añaden, no se editan).

- [ ] **Step 10: Confirmar que el test pasa**

Run: `bash tests/test_pack_wiring.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 11: Re-verificar los bloques bash de los agentes tocados**

Run: `bash tests/test_agent_bash_blocks_allowed.sh`
Expected: sin `FAIL` — el `ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-php-ddd-symfony8"` que acabas de
añadir a dos orquestadores pasa por el guard como cualquier otro bloque documentado (`ls` está en
ambos allowlists). Si falla, el problema es el comando, no el test.

- [ ] **Step 12: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 40, failed: 0`.

- [ ] **Step 13: Commit**

```bash
git add agents/ tests/test_pack_wiring.sh
git commit -m "feat(pack): cablea la ruta del pack por implementation/analysis + migration-engineer y doc-writer en la secuencia"
```

---

### Task 8: Fusión real de `requirements.json` (plugin + pack) y roster nuevo de `requirements-orchestrator`

**Files:**
- Modify: `scripts/req-check.sh` (flag `--pack`, fusión determinista, validación de entrada)
- Modify: `agents/requirements-orchestrator.md` (fusión real, `Agent(...)` ampliado, operaciones
  `audit-deps` e `install`)
- Modify: `agents/env-checker.md` (documenta `--pack` en su `operation: check`)
- Modify: `tests/test_req_check.sh` (casos de fusión + validación)
- Modify: `tests/test_requirements_orchestrator_spawns.sh` (roster nuevo)

**Interfaces:**
- Consumes: `skills/pack-php-ddd-symfony8/requirements.json` (Task 2), los agentes
  `swarm:dependency-auditor` (Task 3) y `swarm:dependency-installer` (Task 4), el formato de la
  cabecera `pack:` (Task 7).
- Produces: `scripts/req-check.sh --file <plugin.json> --pack <pack.json> [--root <dir>]`, que
  imprime el MISMO JSON de informe de hoy (`{"ok", "missing_required", "missing_optional",
  "checked"}`) sobre el conjunto ya fusionado; y `requirements-orchestrator` con tres operaciones:
  `check`, `audit-deps`, `install`. Task 9 (raíz) construye la aprobación que `install` exige.

- [ ] **Step 1: Escribir los casos nuevos en `tests/test_req_check.sh` (fallan primero)**

Añade al final del fichero, antes del `if [ "$TESTS_FAILED" …`:

```bash
# --- fusión plugin + pack (fase 5b, spec §7: misma clave de identidad → gana el PACK) ---
TMP="$(mktemp -d "${TMPDIR:-/tmp}/req-merge.XXXXXX")"
cat > "$TMP/plugin.json" <<'JSONEOF'
{ "os": [ {"tool":"git","required":true,"install":{"brew":"git","apt":"git"}},
          {"tool":"php","required":false,"install":{"brew":"php","apt":"php-cli"}} ],
  "project": [],
  "libs": [ {"name":"phpstan/phpstan","manager":"composer","required":false} ] }
JSONEOF
cat > "$TMP/pack.json" <<'JSONEOF'
{ "os": [ {"tool":"php","min":"8.2","required":true,"install":{"brew":"php","apt":"php-cli"}},
          {"tool":"composer","required":true,"install":{"brew":"composer","apt":"composer"}} ],
  "project": [ {"file":"composer.json","required":true} ],
  "libs": [ {"name":"phpstan/phpstan","manager":"composer","min":"1.10","required":true} ] }
JSONEOF
mkdir -p "$TMP/root" && echo '{}' > "$TMP/root/composer.json"

out="$(bash "$PLUGIN_ROOT/scripts/req-check.sh" --file "$TMP/plugin.json" --pack "$TMP/pack.json" --root "$TMP/root" 2>/dev/null)"
merged="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
print(d['checked'])
" "$out")"
# git + php + composer (os, php fusionado en UNA entrada) + composer.json (project) + phpstan (libs) = 5
assert_eq "5" "$merged" "req-check merges plugin+pack without duplicating the shared php entry"

# la entrada del PACK gana: php pasa de required:false (plugin) a required:true (pack)
wins="$(python3 - "$TMP/plugin.json" "$TMP/pack.json" "$PLUGIN_ROOT/scripts/req-check.sh" <<'PYEOF'
import json, subprocess, sys, tempfile, os
plugin, pack, script = sys.argv[1], sys.argv[2], sys.argv[3]
root = tempfile.mkdtemp()
open(os.path.join(root, 'composer.json'), 'w').write('{}')
# forzamos la ausencia de la tool renombrandola a algo que no existe en el PATH
p = json.load(open(pack)); p['os'][0]['tool'] = 'swarm-tool-que-no-existe'
tmp = os.path.join(root, 'pack.json'); json.dump(p, open(tmp, 'w'))
r = subprocess.run(['bash', script, '--file', plugin, '--pack', tmp, '--root', root],
                   capture_output=True, text=True)
d = json.loads(r.stdout)
print('required' if any(m['tool'] == 'swarm-tool-que-no-existe' for m in d['missing_required']) else 'optional')
PYEOF
)"
assert_eq "required" "$wins" "pack entry wins on conflict: a tool the plugin marked optional becomes required"

# validación de entrada (backlog de fases 1-5a, ahora alcanzable de verdad)
assert_exit "64" "req-check rejects a --pack file that does not exist" bash "$PLUGIN_ROOT/scripts/req-check.sh" --file "$TMP/plugin.json" --pack "$TMP/no-existe.json"
echo 'no soy json' > "$TMP/roto.json"
assert_exit "64" "req-check rejects a malformed requirements file" bash "$PLUGIN_ROOT/scripts/req-check.sh" --file "$TMP/roto.json"
cat > "$TMP/mal-esquema.json" <<'JSONEOF'
{ "os": "no soy una lista" }
JSONEOF
assert_exit "64" "req-check rejects a requirements file whose os is not a list" bash "$PLUGIN_ROOT/scripts/req-check.sh" --file "$TMP/mal-esquema.json"
rm -rf "$TMP"
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_req_check.sh`
Expected: `FAIL` en los casos nuevos (`--pack` se ignora hoy — el bucle de parseo hace `shift` sobre
cualquier flag desconocido — y un JSON roto revienta con traza de Python, no con `exit 64`).

- [ ] **Step 3: Implementar `--pack`, la fusión y la validación en `scripts/req-check.sh`**

Cambios concretos:

1. En el bucle de parseo de argumentos, añade el caso:
   ```bash
       --pack)
         [ $# -ge 2 ] || { echo "req-check.sh: --pack requires a value" >&2; exit 64; }
         PACK_FILE="$2"; shift 2 ;;
   ```
   con `PACK_FILE=""` inicializado junto a `FILE` y `ROOT`, y la misma comprobación de existencia
   que ya hace `FILE` (`[ ! -f "$PACK_FILE" ]` → mensaje a stderr + `exit 64`) cuando no está vacío.

2. Pasa `PACK_FILE` como cuarto argumento al bloque de Python
   (`python3 - "$FILE" "$ROOT" "$UNAME" "$PACK_FILE" <<'PYEOF'`) y, dentro, sustituye la carga
   directa por una carga validada + fusión:

   ```python
   pack_file = sys.argv[4] if len(sys.argv) > 4 else ""

   def load(path):
       try:
           with open(path) as fh:
               data = json.load(fh)
       except (ValueError, OSError) as exc:
           sys.stderr.write("req-check.sh: %s no es JSON valido: %s\n" % (path, exc))
           sys.exit(64)
       if not isinstance(data, dict):
           sys.stderr.write("req-check.sh: %s no es un objeto JSON\n" % path)
           sys.exit(64)
       for key in ("os", "project", "libs"):
           value = data.get(key, [])
           if not isinstance(value, list):
               sys.stderr.write("req-check.sh: %s: '%s' debe ser una lista\n" % (path, key))
               sys.exit(64)
           data[key] = value
       return data

   IDENTITY = {"os": "tool", "project": "file", "libs": "name"}

   def merge(base, pack):
       """Concatena os/project/libs; ante la misma clave de identidad, gana el PACK (spec §7)."""
       out = {}
       for key, id_field in IDENTITY.items():
           merged = []
           pack_ids = set()
           for item in pack.get(key, []):
               if isinstance(item, dict) and item.get(id_field) is not None:
                   pack_ids.add(item[id_field])
               merged.append(item)
           for item in base.get(key, []):
               if isinstance(item, dict) and item.get(id_field) in pack_ids:
                   continue          # la entrada del pack ya la cubre
               merged.append(item)
           out[key] = merged
       return out

   data = load(req_file)
   if pack_file:
       data = merge(data, load(pack_file))
   ```

3. Actualiza el comentario del bucle de `libs` (hoy dice "fase 1b no tiene stack pack todavia […]
   requiere stack pack para verificar (fase 5)", falso desde Task 2) por el reparto de
   responsabilidad real:
   ```python
   # libs: la verificacion real contra un gestor de paquetes es responsabilidad de
   # `dependency-auditor` (comandos del pack: scan-deps/outdated), no de este script. Aqui cada
   # entrada se reporta como no bloqueante para que el health-gate nunca falle por una libreria.
   ...
       "hint": "sin verificar aqui - lo audita dependency-auditor",
   ```

- [ ] **Step 4: Confirmar que el test pasa**

Run: `bash tests/test_req_check.sh`
Expected: sin `FAIL`, exit 0.

- [ ] **Step 5: Actualizar el test de spawns de `requirements-orchestrator` (falla primero)**

En `tests/test_requirements_orchestrator_spawns.sh`, añade:

```bash
front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$PLUGIN_ROOT/agents/requirements-orchestrator.md")"
tools="$(echo "$front" | grep '^tools:')"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$PLUGIN_ROOT/agents/requirements-orchestrator.md")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$tools" 'dependency-auditor')" "requirements-orchestrator can spawn dependency-auditor"
assert_eq "0" "$(has "$tools" 'dependency-installer')" "requirements-orchestrator can spawn dependency-installer"
assert_eq "1" "$(has "$body" 'documentación de futuro')" "the requirements.json merge is no longer documented-as-future"
assert_eq "1" "$(has "$body" 'no hay pack todavía')" "requirements-orchestrator no longer claims no pack exists"
assert_eq "1" "$(has "$body" 'NO implementes lógica de fusión ahora')" "the inert merge instruction is gone"
assert_eq "0" "$(has "$body" '--pack')" "requirements-orchestrator passes --pack to the deterministic check"
assert_eq "0" "$(has "$body" 'approved:')" "requirements-orchestrator documents the approved: line it must forward"
assert_eq "0" "$(has "$body" 'BLOCKED sin aprobación del owner')" "requirements-orchestrator refuses install without owner approval"
assert_eq "1" "$(has "$body" 'dependency-installer no implementado aún')" "the phase-1b install stub is gone"
assert_eq "0" "$(has "$body" 'operation: audit-deps')" "requirements-orchestrator documents the audit-deps operation"
```

- [ ] **Step 6: Reescribir las secciones afectadas de `agents/requirements-orchestrator.md`**

1. **Frontmatter**: `tools: Read, Grep, Bash, Agent(env-checker,dependency-auditor,dependency-installer), SendMessage`.
   `description`: sustituye "spawns env-checker" por "spawns env-checker / dependency-auditor, and
   dependency-installer only with an itemised owner approval". `maxTurns` se queda en `10` (spec §7).

2. **Sustituye la sección "## Fusión de `requirements.json` (documentación de futuro — no hay pack
   todavía)"** por esta, que ya es real:

```markdown
## Fusión de `requirements.json` (plugin + pack activo)

Tus dos fuentes son `${CLAUDE_PLUGIN_ROOT}/requirements.json` (siempre) y, cuando hay stack pack
activo, `<pack>/requirements.json`. **La fusión la hace la herramienta determinista, no tú**
(principio 4 del spec): `scripts/req-check.sh` acepta `--pack <fichero>` y concatena los tres
arrays (`os`/`project`/`libs`); ante la misma clave de identidad (`tool` en `os`, `file` en
`project`, `name` en `libs`) **gana la entrada del PACK** — así un pack sube el `min` de una tool
que el plugin ya declara, o marca `required` una librería que el plugin no conocía.

Para saber si hay pack, `Read` de `.swarm/context-pack.md` y mira su línea `stack:`:
- `stack: generic` o sin línea → no pasas `--pack`, chequeas solo el del plugin.
- otro valor → resuelve la ruta absoluta (la tool `Read` no expande variables; el shell sí):
  ```bash
  ls -d "${CLAUDE_PLUGIN_ROOT}/skills/pack-php-ddd-symfony8"
  ```
  y pasa `<esa ruta>/requirements.json` como `--pack` a `env-checker`. Si `ls -d` falla, sigue sin
  pack y añade `- warn: pack declarado pero ausente` a tu salida.
```

3. **Sustituye la operación `check`** para que su cabecera de spawn incluya el `--pack` cuando
   corresponda:
   ```
   operation: check --file ${CLAUDE_PLUGIN_ROOT}/requirements.json --pack <ruta absoluta>/requirements.json
   ```
   (la línea `--pack` se omite entera si no hay pack). El resto de la operación —lanzar
   `env-checker` NOMBRADO con el tool `Agent`, no reinterpretar su JSON, propagar su veredicto
   literal— no cambia.

4. **Añade la operación `audit-deps`**:

```markdown
## Operación `audit-deps` (fase 5b)

Lanza `dependency-auditor` NOMBRADO exactamente `dependency-auditor` con el tool `Agent` (no
preexiste; `SendMessage` no lo alcanza):
```
run-id: <tu RUN, o literal "adhoc">
swarm-root: <tu swarm-root, si lo tienes>
operation: audit-deps
pack: <ruta absoluta del pack>      ← omite esta línea entera si no hay pack
```
Regístralo antes en el manifest. Espera su veredicto y **propágalo literal**, con sus hallazgos
`DEP` tal cual: quien lee tu salida necesita el paquete y la versión exactos para poder decidir.
Nunca reinterpretes su JSON ni repitas la auditoría tú mismo.
```

5. **Sustituye la sección "## Operación `install` (fuera de alcance en fase 1b — `BLOCKED`
   explícito)"** por:

```markdown
## Operación `install` (mutante — solo con aprobación explícita del owner)

`dependency-installer` es el único agente del enjambre que muta el árbol de dependencias, así que
tu papel aquí es de puerta, no de ejecutor.

**La aprobación válida es una lista literal de identificadores de paquete en TU cabecera**, en una
línea `approved:` que solo puede haber construido la RAÍZ tras preguntar al owner con
`AskUserQuestion` (`agents/orchestrator.md` §11). Ni tú ni ninguna hoja podéis preguntar (spec §3.2
regla 7).

- Sin línea `approved:`, con la línea vacía, o con un texto que no sea una lista de identificadores
  ("todo", "lo que diga el auditor"), tu veredicto es, sin lanzar a nadie:
  ```
  BLOCKED sin aprobación del owner
  ```
- Con lista válida, lanza `dependency-installer` NOMBRADO con el tool `Agent`, **copiando la línea
  `approved:` LITERAL** (no la resumas, no la amplíes, no la reordenes: el installer instala
  exactamente lo que ahí ponga):
  ```
  run-id: <tu RUN, o literal "adhoc">
  swarm-root: <tu swarm-root, si lo tienes>
  operation: install
  approved: <la lista literal de tu propia cabecera>
  ```
- Propaga su veredicto literal. Si devuelve `DONE` con ficheros modificados, incluye esa línea tal
  cual: el owner necesita saber qué manifiestos quedaron sucios sin commitear (el installer no
  commitea, por diseño).

Herramientas de SISTEMA (`brew`/`apt`) no se instalan: el installer las devuelve como hint y tú
propagas ese hint. Instalar software en la máquina del owner queda fuera de v1 (ver el plan de fase
5b, ruling 2).
```

- [ ] **Step 7: Actualizar `agents/env-checker.md`**

Documenta en su sección de arranque que `operation: check` puede traer un segundo flag `--pack
<fichero>` y que se lo pasa TAL CUAL a `scripts/req-check.sh` — sigue sin reinterpretar nada, sigue
siendo la única hoja que toca ese script. Añade un ejemplo de comando con los dos flags y verifica
que pasa el guard (`scripts/req-check.sh` ya está en su allowlist; los flags no cambian el prefijo).

- [ ] **Step 8: Confirmar que los tests pasan**

Run: `bash tests/test_req_check.sh && bash tests/test_requirements_orchestrator_spawns.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 9: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 40, failed: 0`.

- [ ] **Step 10: Commit**

```bash
git add scripts/req-check.sh agents/requirements-orchestrator.md agents/env-checker.md tests/test_req_check.sh tests/test_requirements_orchestrator_spawns.sh
git commit -m "feat(requirements): fusion real plugin+pack en req-check.sh y roster con auditor/installer"
```

---
### Task 9: Integración en la raíz (`## 11. Requisitos e instalación`), `/swarm:doctor` y documentación

**Files:**
- Modify: `agents/orchestrator.md` (§1.0 alcance, §4 líneas de cierre, nueva `## 11`)
- Modify: `commands/doctor.md` (el chequeo ya incluye el pack)
- Modify: `docs/USAGE.md`, `docs/USAGE.es.md` (dominio requirements completo + el pack)
- Modify: `README.md`, `README.es.md` (roster de agentes al día)
- Create: `tests/test_orchestrator_requirements.sh`
- Modify: `tests/test_commands.sh` (aserción del pack en doctor)

**Interfaces:**
- Consumes: `requirements-orchestrator` con sus tres operaciones (Task 8), el gate `approved:` de
  `dependency-installer` (Task 4).
- Produces: la raíz con el dominio requirements alcanzable dentro de un run (hoy solo lo alcanza
  `/swarm:doctor`), incluida la única vía legítima de aprobación de una instalación.

- [ ] **Step 1: Escribir el test de integración (falla primero)**

```bash
cat > tests/test_orchestrator_requirements.sh <<'EOF'
#!/usr/bin/env bash
# tests/test_orchestrator_requirements.sh — la raíz integra el dominio requirements dentro de un
# run (fase 5b): auditoría de dependencias, y la ÚNICA vía legítima de aprobar una instalación
# (AskUserQuestion de la raíz, spec §3.2 regla 7).
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
F="$PLUGIN_ROOT/agents/orchestrator.md"

body="$(awk '/^---$/{n++; next} n>=2{print}' "$F")"
has() { echo "$1" | grep -qF -- "$2" && echo 0 || echo 1; }

assert_eq "0" "$(has "$body" '## 11. Requisitos e instalación')" "root has a dedicated §11 section"
assert_eq "0" "$(has "$body" 'subagent_type: "swarm:requirements-orchestrator"')" "root launches requirements-orchestrator by type"
assert_eq "0" "$(has "$body" 'operation: audit-deps')" "root can ask for a dependency audit"
assert_eq "0" "$(has "$body" 'operation: install')" "root documents the install operation"
assert_eq "0" "$(has "$body" 'AskUserQuestion')" "root uses AskUserQuestion for the approval"
assert_eq "0" "$(has "$body" 'approved:')" "root builds the approved: line"
assert_eq "0" "$(has "$body" 'nunca autorizas una instalación')" "root never authorises an install on its own judgement"
assert_eq "0" "$(has "$body" 'multi-select')" "root asks with a multi-select, one batch (§5 pattern)"
# el saneado: el §11.3 tiene que llevar el mismo parrafo literal que §8.3/§9.3/§10.3
assert_eq "0" "$(has "$body" 'Esa exención NO cubre el `summary --line` del cierre.')" "the sanitisation exemption paragraph is present verbatim"
occurrences="$(grep -cF 'Esa exención NO cubre el `summary --line` del cierre.' "$F")"
assert_eq "4" "$occurrences" "the paragraph appears once per forwarding section (§8.3, §9.3, §10.3, §11.3)"
# la raiz ya no puede seguir diciendo que requirements solo lo invoca /swarm:doctor
assert_eq "1" "$(has "$body" 'lo invoca `/swarm:doctor`, tú no lo lanzas en un run')" "root no longer says it never launches requirements"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
EOF
chmod +x tests/test_orchestrator_requirements.sh
```

- [ ] **Step 2: Confirmar que falla**

Run: `bash tests/test_orchestrator_requirements.sh`
Expected: varios `FAIL`.

- [ ] **Step 3: Actualizar §1.0 "Alcance actual" de `agents/orchestrator.md`**

Sustituye el fragmento `requirements-orchestrator` (fase 1b — lo invoca `/swarm:doctor`, tú no lo
lanzas en un run)` por: `requirements-orchestrator` (fase 1b + 5b, §11 de este fichero — lo invoca
`/swarm:doctor`, y TÚ también dentro de un run para auditar o instalar dependencias)`. Deja
`delivery-orchestrator` (fase 6) como el único dominio que sigue sin existir.

- [ ] **Step 4: Añadir `## 11. Requisitos e instalación` al final del fichero**

Contenido (el §11.3 lleva el párrafo de saneado **copiado literal del §10.3 actual**, cambiando solo
el nombre del orquestador y los números de sección — es la lección de fase 5a, que ya se rompió tres
veces por reescribirlo de memoria):

```markdown
## 11. Requisitos e instalación (fase 5b, spec §7 "Requisitos")

### 11.1 Cuándo

Lanzas `requirements-orchestrator` dentro de un run en dos casos, y solo en esos dos:

- El objetivo del owner es de dependencias ("audita las dependencias", "¿qué librerías están
  desactualizadas?", "¿tenemos CVEs?") → `operation: audit-deps`.
- El owner pide instalar/actualizar algo concreto ("instala phpstan", "sube doctrine a la 3") →
  `operation: install`, **y solo tras el gate de §11.2**.

Fuera de esos dos casos NO lo lanzas: el chequeo de entorno de `/swarm:doctor` es un comando
aparte y no forma parte de un run.

### 11.2 Gate de aprobación — nunca autorizas una instalación por tu cuenta

Instalar o actualizar dependencias muta el repo fuera de cualquier worktree y sin pasar por
`reviewer`. **Nunca autorizas una instalación por criterio propio, ni siquiera si el objetivo del
owner la pide en abstracto ("pon el proyecto al día") y ni siquiera en `tier: full`.** El camino es
siempre este:

1. Lanza primero `operation: audit-deps` y quédate con sus hallazgos `DEP` (paquete + versión
   exactos).
2. Presenta al owner UN batch con `AskUserQuestion` (**multi-select, una sola tanda**, mismo patrón
   de §5.2 para discovery): una opción por paquete concreto, con su versión objetivo, más la opción
   de no instalar nada. Eres el ÚNICO agente del plugin con `AskUserQuestion` (spec §3.2 regla 7).
3. Traduce SOLO lo que el owner marcó a una línea `approved:` con los identificadores literales,
   separados por espacios:
   ```
   approved: phpstan/phpstan:^2.1 doctrine/orm:^3.3
   ```
   Nada de "todo", nada de "lo que dijo el auditor", nada de añadir un paquete que el owner no
   marcó. Si el owner no marcó ninguno o canceló el diálogo, NO lanzas `install`: cierras con
   `- instalación no autorizada por el owner`.
4. Ese texto viene del owner, así que **si lo interpolas en cualquier `--text`/`--line` de shell
   pasa antes por el saneado de §5.0** (un identificador de paquete no debería traer backticks ni
   `$`, pero el saneado no admite juicio propio sobre "parece inofensivo").

### 11.3 Lanzamiento y reenvío del resultado

```
Agent(subagent_type: "swarm:requirements-orchestrator", name: "requirements-orchestrator", prompt:
  run-id: <run-id>
  swarm-root: <ruta absoluta de .swarm>
  operation: audit-deps | install
  approved: <la lista literal de §11.2 — SOLO en operation: install>)
```

Regístralo antes en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register --run <run-id> --agent requirements-orchestrator --domain requirements --area "." --owner orchestrator
```

Reenvía sus líneas (`DEP · …`, `- instalado: …`, `- modificado: …`) tal cual a tu propia salida (§7)
— igual mecanismo que §8.3/§9.3/§10.3 para analysis/design/implementation, SIN pasarlas por el
saneado de §5.0 — esa exención vale únicamente para las líneas que van a tu OUTPUT de turno (lo que
lee `hooks/validate-output.py`), que nunca pasa por un shell, así que no hay nada que proteger ahí.

**Esa exención NO cubre el `summary --line` del cierre.** Si `requirements-orchestrator` devuelve
`BLOCKED …`/`KO …`, propagas su veredicto literal como el tuyo — pero cerrar el run (§4, §11.4)
significa construir `"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" summary --run <run-id> --line
"<veredicto literal de requirements-orchestrator>"`, y eso SÍ es un `--line` nuevo que interpolas
en un comando de Bash real, con texto ajeno (el `<motivo>` de requirements-orchestrator, que puede
citar mensajes de CVE o de un gestor de paquetes, con backticks/`$(...)`). Ese `--line` pasa por el
saneado de §5.0 igual que cualquier otro `--line` de §4 que lleve texto ajeno — la única diferencia
con discovery es de dónde sale el texto (requirements-orchestrator en vez del owner), no si se
sanea. Cierra el run igual que en cualquier otro camino terminal (§4: `summary` saneado con la
línea de este camino y después `SendMessage(memory-orchestrator, "curate")`, esperando su `DONE`,
antes de devolver el veredicto).

### 11.4 Cierre

- auditoría completada: `- run cerrado: DONE · dependencias auditadas, <n> hallazgos`
- instalación completada: `- run cerrado: DONE · <n> dependencias instaladas, manifiestos sin commitear`
- owner no autorizó: `- run cerrado: DONE · instalación no autorizada por el owner`
- `BLOCKED`/`KO` propagado (§11.3): `- run cerrado: <veredicto literal de requirements-orchestrator>`
```

Añade también esas cuatro líneas a la enumeración de líneas de cierre de §4 (donde ya están las de
discovery/analysis/design/implementation).

- [ ] **Step 5: Actualizar `commands/doctor.md`**

Añade un párrafo final: el chequeo que dispara `/swarm:doctor` incluye ahora, además del
`requirements.json` del plugin, el del stack pack activo si `.swarm/context-pack.md` declara uno —
la fusión la hace `scripts/req-check.sh --pack` y la decide `requirements-orchestrator`, no este
comando. `/swarm:doctor` **nunca instala nada**: no tiene `AskUserQuestion` en sus `allowed-tools`,
así que no puede obtener la aprobación que `dependency-installer` exige; una instalación se pide
siempre por `/swarm:run` (raíz, §11).

Y añade a `tests/test_commands.sh`:

```bash
assert_file_contains "$PLUGIN_ROOT/commands/doctor.md" "pack" "doctor documents that the check includes the active stack pack"
assert_file_contains "$PLUGIN_ROOT/commands/doctor.md" "nunca instala" "doctor states it never installs"
```

- [ ] **Step 6: Actualizar la documentación de uso y los README**

- `docs/USAGE.md` / `docs/USAGE.es.md`: el dominio requirements pasa de "solo comprueba el entorno"
  a incluir auditoría de dependencias e instalación con aprobación; el dominio implementation suma
  `migration-engineer` y `doc-writer`; y una sección nueva y corta "Stack packs" que explique en
  términos de usuario qué es un pack, que hoy hay uno (`php-ddd-symfony8`), cómo se detecta
  (`composer.json` con `symfony/*`) y qué pasa sin él (nada se rompe: conocimiento genérico). Mismo
  registro que el resto del documento, con un ejemplo real.
- `README.md` / `README.es.md`: actualizar el conteo/roster de agentes (30 del spec; construidos
  tras esta fase: raíz + 3 memoria + 2 requirements→**4** + 4 discovery + 6 análisis + 3 diseño +
  **6** implementación) y la línea de "lo que todavía no existe" (queda delivery, fase 6). No
  dupliques `USAGE.md`: los README solo apuntan.

- [ ] **Step 7: Confirmar que los tests pasan**

Run: `bash tests/test_orchestrator_requirements.sh && bash tests/test_commands.sh`
Expected: sin `FAIL`, exit 0 en los dos.

- [ ] **Step 8: Suite completa en verde**

Run: `bash tests/run.sh`
Expected: `files: 41, failed: 0`.

- [ ] **Step 9: Commit**

```bash
git add agents/orchestrator.md commands/doctor.md docs/USAGE.md docs/USAGE.es.md README.md README.es.md tests/test_orchestrator_requirements.sh tests/test_commands.sh
git commit -m "feat(requirements): integra el dominio requirements en la raiz (§11) con gate de aprobacion del owner"
```

---

### Task 10: Checklist de smoke en vivo + cierre de fase

**Files:**
- Create: `docs/superpowers/plans/2026-09-03-phase5b-smoke-checklist.md`

**Interfaces:**
- Consumes: todo lo anterior.
- Produces: evidencia real de ejecución, gate antes de dar la fase por cerrada.

- [ ] **Step 1: Escribir el checklist (plantilla, se rellena en vivo)**

```bash
cat > docs/superpowers/plans/2026-09-03-phase5b-smoke-checklist.md <<'EOF'
# Checklist de smoke — Fase 5b (stack pack `php-ddd-symfony8` + 4 hojas consumidoras)

Gate. Fixture: `tests/lib.sh::make_fixture` (ya trae `composer.json` con `symfony/framework-bundle`,
`src/App/`, `tests/Unit/FooTest.php` — es decir, ya dispara la detección `php-ddd-symfony8`).
**Riesgo real no verificado hasta este smoke**: la ruta del pack nunca ha viajado de verdad por un
prompt hasta una hoja, y ninguna hoja ha hecho `Read` de un pack real dentro de un run.

## 1. Detección → ruta resuelta → `Read` en la hoja

Un run real sobre el fixture: `memory-builder` escribe `stack: php-ddd-symfony8` en
`context-pack.md`; el orquestador de dominio resuelve la ruta con `ls -d` y la pasa; la hoja la
reporta en su `files=`. Comprobar que la ruta que llega a la hoja es ABSOLUTA y existe (nunca
`${CLAUDE_PLUGIN_ROOT}` sin expandir — el bug más probable de toda la fase).
Evidencia:

## 2. Repo sin marcadores → `generic`, sin línea `pack:`, nada se rompe

Segundo fixture sin `composer.json`. El orquestador NO emite `pack:` y cada hoja cae en su modo
genérico documentado. El summary del run debe llevar el warning de stack no detectado (spec §8.1).
Evidencia:

## 3. `dependency-auditor` corre comandos reales y es incapaz de mutar

Auditoría real sobre el fixture (`composer audit`/`outdated` fallarán si no hay `composer` en la
máquina: eso es un `BLOCKED`/nota legítima, no un fallo del agente — documentar cuál de los dos
casos ocurrió). Y la comprobación que SÍ es del diseño: `composer update` denegado por el guard con
su `agent_type` real.
Evidencia:

## 4. `dependency-installer` rechaza instalar sin aprobación

Lanzarlo en adhoc SIN línea `approved:` → `BLOCKED sin aprobación del owner`, cero comandos
ejecutados. Después, con una línea `approved:` de un paquete concreto, comprobar que solo instala
ese. **Este es el mecanismo más consecuente de la fase; no darlo por bueno por lectura de código.**
Evidencia:

## 5. Ciclo de implementation con las dos hojas nuevas

Una fase de plan que toque esquema y comportamiento: `implementation-orchestrator` lanza
`migration-engineer` y `doc-writer`, ambos commitean en el worktree de `implementer`, todo entra en
el MISMO merge, y el worktree queda limpio al final (`git worktree list` + `git worktree prune -v`
en disco, no la narración del agente — el falso positivo de fase 5a).
Evidencia:

## 6. Fase que NO toca esquema → ambas hojas omitidas

El mismo ciclo con una fase trivial: salida con `- migration-engineer: omitido (fase sin cambios de
esquema)` y sin coste de turnos por una hoja que no hacía falta.
Evidencia:

## 7. `/swarm:doctor` con el pack activo

Sobre el fixture: el chequeo incluye el `requirements.json` del pack (`php`, `composer` como
requeridos) y su veredicto lo refleja. Sobre un repo sin marcadores: solo el del plugin.
Evidencia:

## 8. Ningún push, ninguna rama compartida tocada

`git log --all --oneline` tras los runs; `git push` sigue fuera de todos los allowlists nuevos.
Evidencia:

## Firma

- [ ] Owner: ________________ Fecha: ________________
EOF
```

- [ ] **Step 2: Ejecutar el smoke en vivo**

Metodología headless (`claude -p --plugin-dir <este worktree> --permission-mode bypassPermissions`)
contra fixtures desechables, salvo el ítem 4 y el gate de `AskUserQuestion` de §11.2, que necesitan
sesión interactiva real (mismo aprendizaje que fase 2: `AskUserQuestion` no se simula headless). Si
aparece un bug real, se arregla en el momento (regla del owner: "Arregla todos los Bugs que
encuentres siempre").

- [ ] **Step 3: Review final de rama (Opus, sobre TODO el diff de la fase)**

Mismo patrón que fases 1-5a. Foco explícito, además de lo habitual:
1. **Que ninguna hoja pueda recibir una ruta de pack sin expandir** — el fallo de este tipo es
   silencioso (la hoja simplemente no encuentra el pack y sigue en genérico).
2. **Que el gate de `approved:` no tenga ninguna vía implícita de bypass** (igual que la re-review
   de fase 5a verificó que la regla de enrutado nueva no abría una vía a §10).
3. **Que la fusión de `requirements.json` no pueda ocultar un requisito del plugin** que el pack no
   redeclara (la fusión concatena; solo descarta la homónima).
4. Que cada comando de `commands.md` siga siendo ejecutable por su ejecutor declarado.

Un solo fix wave con re-review escopeada al diff del fix (el patrón que salvó fase 5a de un
Critical).

- [ ] **Step 4: Commit del checklist relleno**

```bash
git add docs/superpowers/plans/2026-09-03-phase5b-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 5b relleno con evidencia real de ejecucion en vivo"
```

- [ ] **Step 5: `finishing-a-development-branch` → merge → handoff**

Verificar tests, mergear local a master (instrucción permanente del owner, sin preguntar), limpiar
worktree/rama, y reescribir el handoff con el estado final de 5b y el siguiente paso: **fase 6
(delivery)** — `delivery-orchestrator`/`release-manager`/`handoff-writer`, el primer dominio con
`git push` real, última fase antes de poder declarar v1 estable. Dejar anotado en el backlog lo que
esta fase deliberadamente no hizo: extensiones de PHP fuera del esquema de `requirements.json`
(ruling 6), `brew`/`apt` fuera del installer (ruling 2), y el piso `php >= 8.2` conservador del pack
(ruling 7).

---

## Self-Review

**1. Cobertura del spec.**

| requisito del spec | tarea |
|---|---|
| §8 contrato del pack (6 ficheros) | Task 2 |
| §8.1 tabla de detección (`composer.json` con `symfony/*`) | Task 2 (`SKILL.md`) — `scripts/mem-scan.sh` ya lo implementaba; no se duplica |
| §8.1 "los orquestadores pasan la RUTA […] implementation, data-model-auditor, vulnerability-scanner, doc-writer" | Task 7 |
| §3.1 pack por prompt, nunca mutación de frontmatter | Task 7 (+ aserción explícita en `tests/test_pack_wiring.sh`) |
| §7 fila `migration-engineer` (sonnet, 15) | Task 5 |
| §7 fila `doc-writer` (sonnet, 15) | Task 6 |
| §7 fila `dependency-auditor` (sonnet, 12, read-only) | Task 3 |
| §7 fila `dependency-installer` (sonnet, 10, mutante, nunca sin aprobación) | Tasks 4 + 9 |
| §7 contrato `requirements.json` del pack + fusión con el del plugin | Tasks 2 + 8 |
| §7.0 modelo por tier (ninguna de las 4 es hoja de juicio ni mecánica → sin override) | Global Constraints + tests de frontmatter |
| §9.3 aislamiento (worktree ajeno por ruta absoluta, sin `isolation:` propia) | Tasks 5, 6, 7 |
| §12 `skills/pack-php-ddd-symfony8/` en la estructura del plugin | Task 2 |
| §14 ítem 11 (detección de stack con marcadores del pack; sin marcadores → `generic` + warning) | Task 10 ítems 1-2 |
| §15 fase 5 (7 agentes de implementation + el pack) | Tasks 2, 5, 6, 7 — completa el dominio implementation al 7/7 |

**Hueco consciente:** el spec §7 dice que `dependency-installer` instala también con `brew`/`apt`;
este plan lo acota a gestores de proyecto (ruling 2). Está marcado como ruling revisable, no como
omisión.

**2. Escaneo de placeholders.** Ninguna tarea contiene "TBD", "similar a la Task N", "añadir manejo
de errores apropiado" ni un paso de código sin su bloque. El contenido de los 6 ficheros del pack va
literal, igual que los frontmatter y los cuerpos de los 4 agentes nuevos. Los `<placeholders>`
angulares que sí aparecen (`<pack>`, `<repo-root>`, `<Aggregate>`) son parte deliberada del contrato
de prompt/convención y están definidos donde se usan.

**3. Consistencia de tipos e interfaces entre tareas.**

- **Formato de la ruta del pack**: definido una sola vez (Task 7, bloque *Produces*) como
  `pack: <ruta absoluta del directorio, sin barra final>`, resuelta con `ls -d` (ruling 1). Lo usan
  idéntico Tasks 3, 5, 6, 7 y 8, y `tests/test_pack_wiring.sh` prohíbe explícitamente la forma sin
  expandir.
- **Nombres de operación**: `audit-deps` (dependency-auditor y requirements-orchestrator),
  `install` + `approved:` (dependency-installer, requirements-orchestrator, raíz §11), `migrate`
  (migration-engineer), `document` (doc-writer). Cada uno aparece con la misma cadena exacta en el
  agente que la recibe, en el que la emite y en el test que la vigila.
- **Claves de `commands.md`**: el conjunto cerrado se define en Task 2 (`Produces`) y lo valida el
  parser de `tests/test_stack_pack.sh`; Tasks 3, 5, 6 y 7 solo usan claves de ese conjunto.
- **Tags de hallazgo**: `DEP` (dependency-auditor), `MIGRATION` (migration-engineer), `DOC`
  (doc-writer) — nuevos, sin colisión con los ya existentes (`ARCH`, `SEC`, `PERF`, `REVIEW`, `REQ`).
- **Veredicto de rechazo del installer**: la cadena literal `BLOCKED sin aprobación del owner`
  aparece idéntica en el agente (Task 4), en `requirements-orchestrator` (Task 8) y en sus dos
  tests.
- **Conteo de ficheros de test**: 36 hoy → +5 nuevos (`test_bash_allowlist_pack.sh`,
  `test_stack_pack.sh`, `test_requirements_agents.sh`, `test_pack_wiring.sh`,
  `test_orchestrator_requirements.sh`) = **41** al cerrar la fase. Los `Expected: files: N` de cada
  tarea siguen esa progresión (37, 38, 39, 39, 39, 39, 40, 40, 41).
