# Plan Fase 1 — Núcleo del plugin `swarm`

> **Para agentes:** SUB-SKILL REQUERIDA — usa `superpowers:subagent-driven-development`
> (recomendado) o `superpowers:executing-plans` para ejecutar este plan tarea a tarea. Los pasos
> usan sintaxis de checkbox (`- [ ]`) para seguimiento.

**Objetivo:** Construir el núcleo del plugin `swarm` — orquestador raíz, subsistema de memoria
(`memory-orchestrator` + `memory-builder` + `memory-curator` + backend `files`), skill de
contrato universal `swarm-protocol`, hooks de evidencia y de allowlist de Bash, comando
`/swarm:init`, y los smoke tests 1–8 del spec (más 10 y 11), sobre macOS con bash 3.2 y sin
dependencias fuera de `git`/`python3`/`uuidgen`.

**Arquitectura:** Backend `files` = scripts bash puros sobre `.swarm/` en el repo target, con un
lock atómico `mkdir` propio (`mem-lock.sh`) porque `flock` no está en macOS por defecto. Los
hooks de plataforma (`SubagentStop` para el contrato de evidencia, `PreToolUse` para el allowlist
de Bash) son Python 3 stdlib puro. Los tres agentes de memoria y el orquestador raíz son ficheros
de agente de plugin planos en `agents/`, precargando la skill `swarm-protocol` que documenta el
contrato que todos comparten. Todo se prueba con bash plano (`tests/run.sh` + `tests/test_*.sh`),
sin framework.

**Tech Stack:** bash 3.2 (compatible macOS), Python 3 stdlib (sin `jq`), git, `uuidgen`, formato
de agente/plugin de Claude Code.

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — esta fase implementa
exactamente §15 fase "1. Núcleo": `orchestrator`, subsistema memoria (3 agentes + backends
files/claude-mem), `swarm-protocol`, hooks (evidencia §6.1 + `bash-allowlist`), `/swarm:init`,
smoke tests 1–8. La fase "1b. Requisitos" (`requirements-orchestrator`, `env-checker`,
`dependency-auditor`, `dependency-installer`, `/swarm:doctor`) es un plan POSTERIOR y separado —
no se toca aquí.

## Global Constraints

- Nombre del plugin `swarm`; manifest `.claude-plugin/plugin.json` (schema
  `https://json.schemastore.org/claude-code-plugin-manifest.json`; keys: `name`, `displayName`,
  `version` `"0.1.0"`, `description`, `author {name:"David García Gordo"}`, `license` `MIT`,
  `"skills": "./skills/"`, `"commands": ["./commands/init.md","./commands/run.md"]`; `agents/` y
  `hooks/hooks.json` se auto-descubren).
- Agentes en `agents/` plano → registran como `swarm:<nombre>`. Frontmatter SOLO: `name`,
  `description`, `model`, `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`,
  opcionalmente `background`/`isolation`/`color`. NUNCA `hooks`/`mcpServers`/`permissionMode` en
  frontmatter de agente (se ignoran para subagentes de plugin, spec §3.1). `tools:` lista nombres
  planos (`Bash`, no `Bash(x:*)`), más `SendMessage` en todo agente que se comunique.
- Portabilidad macOS, bash 3.2 (sin arrays asociativos, sin `mapfile`), SIN `flock` (no está en
  macOS por defecto) → lock = `mkdir "$SWARM_ROOT/.lock.d"` atómico con spin-wait (sleep 0.05,
  timeout total 10s), con un `trap` que libera (`rmdir`) el lock al EXIT/INT/TERM del script que
  lo sostiene, MÁS un chequeo de lock huérfano: si `.lock.d` existe pero su mtime tiene más de 30s,
  se trata como huérfano (de un subagente muerto a media escritura), se elimina y se continúa —
  con un aviso de una línea a stderr cuando esto ocurre. Riesgo señalado por el owner: un
  subagente muerto a media escritura no puede bloquear para siempre las escrituras futuras.
  Implementado exactamente así en `scripts/mem-lock.sh`.
- Scripts de hooks en Python 3 stdlib puro (sin dependencia de `jq` para los hooks; `jq` es
  opcional y se declarará como tool de OS no requerida en fase 1b, no se usa aquí).
  `hooks/validate-output.py` (SubagentStop) y `hooks/bash-guard.py` (PreToolUse).
  - El regex de línea de evidencia de `validate-output.py` debe ser TOLERANTE con espacios (riesgo
    señalado por el owner: no romper agentes válidos por variación de espaciado) — acepta espacios
    opcionales alrededor de `=` y tras `:`, p. ej. matcheando con
    `re.match(r'^evidence:\s*files\s*=\s*(\d+)\s+cmds\s*=\s*(\d+)\s+turns\s*=\s*(\d+)\s*/\s*(\d+)\s*$', line.strip())`.
    Regex de línea de veredicto: `^(OK|KO .+|DONE|BLOCKED .+)$`, también sobre `.strip()`.
  - `bash-guard.py` hace prefix-matching (riesgo señalado por el owner: no dar falso positivo con
    comandos legítimos que usan comillas o pipes) — divide el comando completo en `&&`, `||`, `;`,
    `|` FUERA de comillas (estado de comilla carácter a carácter); para cada segmento, toma sus dos
    primeras shell-words (vía `shlex.split`) y las compara contra prefijos del allowlist (un
    prefijo como `"git log"` matchea un segmento cuyas dos primeras palabras son `git log`; un
    prefijo como `scripts/mem-` matchea si la primera palabra del segmento empieza por esa cadena o
    si el basename de la primera palabra, tras quitar cualquier prefijo `${CLAUDE_PLUGIN_ROOT}/`,
    empieza por `mem-`). Se escriben 6+ casos de test unitario para esto, incluyendo una cadena
    entrecomillada que contiene `&&` dentro de comillas (p. ej. `git commit -m "a && b"`) que NO
    debe partirse ahí.
- `SWARM_ROOT` variable de entorno = `.swarm/` del repo target (por defecto `$PWD/.swarm`). Todos
  los scripts la aceptan/por-defectean.
- Tests: bash plano, sin framework. `tests/lib.sh` aporta `make_fixture` (crea repo git temporal
  con commit inicial, `composer.json` con `"symfony/framework-bundle"`, `src/App/Foo.php` de 20
  líneas), `assert_eq`, `assert_file_contains`, `assert_exit`. `tests/run.sh` corre cada
  `tests/test_*.sh`, imprime PASS/FAIL por fichero, sale con 1 si alguno falla. Los tests de hooks
  Python alimentan JSON por stdin vía heredoc desde ficheros de test bash.
- Commit tras CADA tarea individualmente: `git commit -m "<type>: <desc>"` (feat/test/chore/docs).
  Sin trailer de atribución (el repo ya está configurado, no añadir Co-Authored-By).
- Enrutado de modelo (regla explícita del owner esta sesión: "ejecuta cada tarea con el mejor
  modelo, no mates moscas a cañonazos"): scaffolding/scripts/mecánico → ejecución en sonnet, review
  en haiku donde es trivial; los dos ficheros que SON el contrato central del sistema
  (`agents/orchestrator.md` cuerpo del prompt, `skills/swarm-protocol/SKILL.md`) llevan
  **Modelo: opus** para su autoría porque un mal contrato envenena a todo agente downstream, con
  review de nivel sonnet; el resto **Modelo: sonnet**, **Review: cavecrew-reviewer** (agente de
  review ligero ya existente). Nunca opus para un script o fichero de test.

## Estructura de ficheros (vista completa al terminar fase 1)

```
.claude-plugin/plugin.json
.gitignore
README.md
agents/
  memory-orchestrator.md
  memory-builder.md
  memory-curator.md
  orchestrator.md
commands/
  init.md
  run.md
skills/
  swarm-protocol/SKILL.md
scripts/
  mem-lock.sh
  mem-files.sh
  mem-stale.sh
  mem-manifest.sh
  mem-curate.sh
  mem-scan.sh
  swarm-init.sh
hooks/
  validate-output.py
  bash-guard.py
  bash-allowlist.json
  hooks.json
tests/
  lib.sh
  run.sh
  test_harness.sh
  test_mem_lock.sh
  test_mem_files.sh
  test_mem_stale.sh
  test_mem_manifest.sh
  test_validate_output.sh
  test_bash_guard.sh
  test_skill_protocol.sh
  test_swarm_init.sh
  test_mem_scan.sh
  test_mem_curate.sh
  test_agents_frontmatter.sh
  test_commands.sh
docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md
```

---

### Task 1: Scaffold + arnés de tests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.gitignore`
- Create: `README.md`
- Create: `tests/lib.sh`
- Create: `tests/run.sh`
- Test: `tests/test_harness.sh`

**Interfaces:**
- Produces: `make_fixture [DIR]` → imprime a stdout la ruta de un repo git temporal con
  `composer.json` (marcador `symfony/framework-bundle`) y `src/App/Foo.php` de 20 líneas. Usado
  por TODAS las tareas siguientes.
- Produces: `assert_eq EXPECTED ACTUAL [MSG]`, `assert_file_contains FILE PATTERN [MSG]`,
  `assert_exit EXPECTED_CODE MSG CMD...` — usados por todo `tests/test_*.sh` posterior.
- Produces: `tests/run.sh` — ejecuta cada `tests/test_*.sh`, imprime PASS/FAIL, exit 1 si alguno
  falla. Toda tarea posterior añade un fichero `tests/test_*.sh` que este runner recoge sin
  cambios en `run.sh`.

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: crear el scaffold de directorios y ficheros de configuración (no vía TDD — son
  config, no lógica)**

```bash
mkdir -p .claude-plugin agents commands skills/swarm-protocol scripts hooks tests
```

```json
{
  "$schema": "https://json.schemastore.org/claude-code-plugin-manifest.json",
  "name": "swarm",
  "displayName": "Swarm",
  "version": "0.1.0",
  "description": "Enjambre de agentes Claude Code con responsabilidad única para el ciclo de desarrollo, optimizado en calidad por token.",
  "author": { "name": "David García Gordo" },
  "license": "MIT",
  "skills": "./skills/",
  "commands": ["./commands/init.md", "./commands/run.md"]
}
```

Guarda lo anterior en `.claude-plugin/plugin.json`.

```
.forge/
*.log
```

Guarda lo anterior en `.gitignore`.

````markdown
# swarm

Plugin de Claude Code: enjambre de agentes con responsabilidad única para el ciclo de desarrollo,
optimizado en calidad por token. Ver spec completa en
`docs/superpowers/specs/2026-09-01-swarm-design.md`.

## Instalación (desarrollo local)

```bash
claude --plugin-dir /ruta/a/multiagents
```

## Comandos disponibles (fase 1 — núcleo)

- `/swarm:init` — crea `.swarm/` en el repo target, backend `files` health-gated.
- `/swarm:run <objetivo> [--tier=direct|light|full]` — lanza el orquestador raíz.

## Tests

```bash
bash tests/run.sh
```

Fases posteriores (requisitos, discovery, análisis, diseño, implementación, entrega) — ver
`docs/superpowers/specs/2026-09-01-swarm-design.md` §15.
````

Guarda lo anterior en `README.md`.

- [ ] **Paso 2: escribir el test de arnés ANTES de que exista `tests/lib.sh` (RED)**

```bash
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
```

Guarda lo anterior en `tests/test_harness.sh` y hazlo ejecutable: `chmod +x tests/test_harness.sh`.

- [ ] **Paso 3: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_harness.sh`
Expected: FAIL — `tests/lib.sh: No such file or directory` (o error de "command not found:
make_fixture").

- [ ] **Paso 4: implementar `tests/lib.sh`**

```bash
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
```

Guarda lo anterior en `tests/lib.sh`.

```bash
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
```

Guarda lo anterior en `tests/run.sh` y hazlo ejecutable: `chmod +x tests/run.sh`.

- [ ] **Paso 5: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_harness.sh`
Expected: PASS (sin líneas `FAIL:` en stderr, exit 0).

- [ ] **Paso 6: commit**

```bash
git add .claude-plugin/plugin.json .gitignore README.md tests/lib.sh tests/run.sh tests/test_harness.sh
git commit -m "feat: scaffold plugin swarm + arnés de tests bash"
```

---

### Task 2: `scripts/mem-lock.sh`

**Files:**
- Create: `scripts/mem-lock.sh`
- Test: `tests/test_mem_lock.sh`

**Interfaces:**
- Consumes: `tests/lib.sh` (Task 1) — `make_fixture`, `assert_eq`.
- Produces: `mem-lock.sh acquire` (exit 0 en cuanto el lock queda tomado; exit 1 tras 10s de
  timeout, imprimiendo el motivo a stderr), `mem-lock.sh release` (exit 0 siempre, libera si
  existe). Consumido por `mem-files.sh` (Task 3), `mem-manifest.sh` (Task 5) y `mem-curate.sh`
  (Task 11) — todos envuelven cada escritura en `acquire` ... `release` con un `trap` propio.

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
LOCK_SCRIPT="$PLUGIN_ROOT/scripts/mem-lock.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

# --- 1. acquire+release cycle works ---
"$LOCK_SCRIPT" acquire
assert_eq "0" "$?" "acquire succeeds when lock free"
assert_eq "0" "$( [ -d "$SWARM_ROOT/.lock.d" ]; echo $? )" "lock dir exists after acquire"
"$LOCK_SCRIPT" release
assert_eq "1" "$( [ -d "$SWARM_ROOT/.lock.d" ]; echo $? )" "lock dir absent after release"

# --- 2. concurrent acquire: one waits, succeeds after the other releases ---
(
  "$LOCK_SCRIPT" acquire
  sleep 1
  "$LOCK_SCRIPT" release
) &
holder_pid=$!
sleep 0.2
start="$(date +%s)"
"$LOCK_SCRIPT" acquire
second_rc=$?
end="$(date +%s)"
"$LOCK_SCRIPT" release
wait "$holder_pid"
assert_eq "0" "$second_rc" "second acquire eventually succeeds"
waited=$((end - start))
assert_eq "0" "$( [ "$waited" -ge 1 ] && echo 0 || echo 1 )" "second acquire waited for first release (waited=${waited}s)"

# --- 3. orphaned lock older than 30s is reclaimed with a warning ---
mkdir -p "$SWARM_ROOT/.lock.d"
past=$(( $(date +%s) - 40 ))
backdate_stamp="$(date -r "$past" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$past" +%Y%m%d%H%M.%S)"
touch -t "$backdate_stamp" "$SWARM_ROOT/.lock.d"
warn_output="$("$LOCK_SCRIPT" acquire 2>&1 1>/dev/null)"
reclaim_rc=$?
"$LOCK_SCRIPT" release
assert_eq "0" "$reclaim_rc" "stale lock is reclaimed, acquire succeeds"
assert_eq "0" "$(echo "$warn_output" | grep -qi "stale" && echo 0 || echo 1)" "warning printed to stderr on reclaim"

# --- 4. a killed holder releases via trap; next acquire is fast (<2s), not 10s ---
cat > "$fixture/holder.sh" <<HOLDEREOF
#!/usr/bin/env bash
"$LOCK_SCRIPT" acquire
trap '"$LOCK_SCRIPT" release' EXIT INT TERM
sleep 5
HOLDEREOF
chmod +x "$fixture/holder.sh"
"$fixture/holder.sh" &
holder_pid=$!
sleep 0.2
kill "$holder_pid" 2>/dev/null
wait "$holder_pid" 2>/dev/null
start="$(date +%s)"
"$LOCK_SCRIPT" acquire
third_rc=$?
end="$(date +%s)"
"$LOCK_SCRIPT" release
elapsed=$((end - start))
assert_eq "0" "$third_rc" "acquire after killed holder succeeds"
assert_eq "0" "$( [ "$elapsed" -lt 2 ] && echo 0 || echo 1 )" "acquire after killed holder is fast (${elapsed}s, expected <2s not ~10s)"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_lock.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_mem_lock.sh`
Expected: FAIL — `scripts/mem-lock.sh: No such file or directory` (exit 127) en el primer
`assert_eq`.

- [ ] **Paso 3: implementar `scripts/mem-lock.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-lock.sh — atomic mkdir-based lock (macOS bash 3.2, no flock)
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
LOCK_DIR="$SWARM_ROOT/.lock.d"
STALE_SECONDS=30
TIMEOUT_SECONDS=10
SLEEP_INTERVAL=0.05

_now() { date +%s; }

_lock_mtime() {
  if stat -f %m "$LOCK_DIR" >/dev/null 2>&1; then
    stat -f %m "$LOCK_DIR"
  else
    stat -c %Y "$LOCK_DIR" 2>/dev/null
  fi
}

_reclaim_if_stale() {
  [ -d "$LOCK_DIR" ] || return 0
  local mtime now age
  mtime="$(_lock_mtime 2>/dev/null || echo 0)"
  now="$(_now)"
  age=$((now - mtime))
  if [ "$age" -gt "$STALE_SECONDS" ]; then
    echo "swarm: mem-lock.sh — lock stale (${age}s) at $LOCK_DIR, reclaiming" >&2
    rmdir "$LOCK_DIR" 2>/dev/null
  fi
}

cmd_acquire() {
  mkdir -p "$SWARM_ROOT"
  local start elapsed
  start="$(_now)"
  while true; do
    _reclaim_if_stale
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      return 0
    fi
    elapsed=$(( $(_now) - start ))
    if [ "$elapsed" -ge "$TIMEOUT_SECONDS" ]; then
      echo "swarm: mem-lock.sh — timeout after ${TIMEOUT_SECONDS}s waiting for $LOCK_DIR" >&2
      return 1
    fi
    sleep "$SLEEP_INTERVAL"
  done
}

cmd_release() {
  rmdir "$LOCK_DIR" 2>/dev/null
  return 0
}

case "${1:-}" in
  acquire) cmd_acquire ;;
  release) cmd_release ;;
  *)
    echo "usage: mem-lock.sh {acquire|release}" >&2
    exit 64
    ;;
esac
```

Guarda lo anterior en `scripts/mem-lock.sh` y hazlo ejecutable: `chmod +x scripts/mem-lock.sh`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_mem_lock.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/mem-lock.sh tests/test_mem_lock.sh
git commit -m "feat: lock atómico mkdir con reclaim de huérfanos (mem-lock.sh)"
```

---

### Task 3: `scripts/mem-files.sh`

**Files:**
- Create: `scripts/mem-files.sh`
- Test: `tests/test_mem_files.sh`

**Interfaces:**
- Consumes: `scripts/mem-lock.sh acquire|release` (Task 2).
- Produces:
  ```
  mem-files.sh health
  mem-files.sh write finding --agent A --tag T --file F --line N --run R --text "problema" --fix "fix"
  mem-files.sh write decision --text "..."
  mem-files.sh write mailbox --to B --from A --run R --text "..."
  mem-files.sh query "<regex>" [--scope findings|decisions|pack|all]
  ```
  Formato de línea de finding (exacto, usado también por `mem-curate.sh` en Task 11):
  `- [key:A|T|F:N] [sha:<8-hex>] [status:open] [run:R] T · F:N · problema → fix`. Formato de línea
  de decision: `- YYYY-MM-DD · texto`. Formato de línea de mailbox:
  `- [from:A] [ts:ISO8601] texto`. Estas tres firmas son consumidas literalmente por
  `skills/swarm-protocol/SKILL.md` (Task 8) y por los tres agentes de memoria (Task 11).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"

PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_FILES="$PLUGIN_ROOT/scripts/mem-files.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

# health fails without .swarm
"$MEM_FILES" health >/dev/null 2>&1
assert_eq "1" "$?" "health fails when .swarm absent"

mkdir -p "$SWARM_ROOT"
"$MEM_FILES" health >/dev/null 2>&1
assert_eq "0" "$?" "health passes once .swarm exists"

# finding written once
"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 3 \
  --run adhoc --text "clase sin interfaz" --fix "extraer interfaz" >/dev/null
lines="$(wc -l < "$SWARM_ROOT/findings/architecture-auditor.md" | tr -d ' ')"
assert_eq "1" "$lines" "finding written once yields 1 line"
assert_file_contains "$SWARM_ROOT/findings/architecture-auditor.md" "\[status:open\]" "finding has open status"

# duplicate key -> dup, still 1 line
out="$("$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 3 \
  --run adhoc --text "clase sin interfaz" --fix "extraer interfaz")"
assert_eq "dup" "$out" "duplicate finding reports dup"
lines="$(wc -l < "$SWARM_ROOT/findings/architecture-auditor.md" | tr -d ' ')"
assert_eq "1" "$lines" "duplicate finding does not append"

# 20 parallel writers of distinct findings -> exactly 20 lines, no torn lines
for i in $(seq 1 20); do
  "$MEM_FILES" write finding --agent concurrency-test --tag CONC --file src/App/Foo.php --line "$i" \
    --run adhoc --text "hallazgo $i" --fix "fix $i" >/dev/null &
done
wait
concurrent_lines="$(wc -l < "$SWARM_ROOT/findings/concurrency-test.md" | tr -d ' ')"
assert_eq "20" "$concurrent_lines" "20 concurrent writers yield exactly 20 lines"
malformed="$(grep -cv '^- \[key:' "$SWARM_ROOT/findings/concurrency-test.md")"
assert_eq "0" "$malformed" "no torn/interleaved lines among concurrent writes"

# mailbox to not-yet-existing agent creates file
"$MEM_FILES" write mailbox --to late-agent --from orchestrator --run adhoc --text "hola" >/dev/null
assert_eq "0" "$( [ -f "$SWARM_ROOT/run/adhoc/mailbox/late-agent.md" ]; echo $? )" "mailbox file created for late agent"
assert_file_contains "$SWARM_ROOT/run/adhoc/mailbox/late-agent.md" "\[from:orchestrator\]" "mailbox entry has from tag"

# query returns expected match
"$MEM_FILES" write decision --text "usar sonnet para ejecucion" >/dev/null
result="$("$MEM_FILES" query "sonnet" --scope decisions)"
assert_eq "0" "$( echo "$result" | grep -q "sonnet" && echo 0 || echo 1 )" "query finds decision text"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_files.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_mem_files.sh`
Expected: FAIL — `scripts/mem-files.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/mem-files.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-files.sh — files backend for swarm memory (.swarm/)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
REPO_ROOT="$(dirname "$SWARM_ROOT")"

_with_lock() {
  "$LOCK_SCRIPT" acquire || return 1
  trap '"$LOCK_SCRIPT" release' EXIT INT TERM
  "$@"
  local rc=$?
  "$LOCK_SCRIPT" release
  trap - EXIT INT TERM
  return $rc
}

_iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_sha8_of_line() {
  local file="$1" line="$2"
  local target="$REPO_ROOT/$file"
  if [ ! -f "$target" ]; then
    echo "00000000"
    return
  fi
  local content
  content="$(sed -n "${line}p" "$target" 2>/dev/null)"
  if [ -z "$content" ]; then
    echo "00000000"
    return
  fi
  printf '%s' "$content" | shasum -a 1 | cut -c1-8
}

cmd_health() {
  if [ ! -d "$SWARM_ROOT" ]; then
    echo "swarm: mem-files.sh health — SWARM_ROOT not found: $SWARM_ROOT" >&2
    return 1
  fi
  if [ ! -w "$SWARM_ROOT" ]; then
    echo "swarm: mem-files.sh health — SWARM_ROOT not writable: $SWARM_ROOT" >&2
    return 1
  fi
  echo "ok"
  return 0
}

_write_finding() {
  local agent="" tag="" file="" line="" run="" text="" fix=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --agent) agent="$2"; shift 2 ;;
      --tag) tag="$2"; shift 2 ;;
      --file) file="$2"; shift 2 ;;
      --line) line="$2"; shift 2 ;;
      --run) run="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      --fix) fix="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write finding — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$agent" ] || [ -z "$tag" ] || [ -z "$file" ] || [ -z "$line" ] || [ -z "$run" ] || [ -z "$text" ] || [ -z "$fix" ]; then
    echo "swarm: mem-files.sh write finding — missing required arg" >&2
    return 64
  fi
  mkdir -p "$SWARM_ROOT/findings"
  local out="$SWARM_ROOT/findings/${agent}.md"
  touch "$out"
  local key="key:${agent}|${tag}|${file}:${line}"
  local existing
  existing="$(grep -F "[${key}]" "$out" 2>/dev/null | grep "\[status:open\]" | head -1)"
  if [ -n "$existing" ]; then
    echo "dup"
    return 0
  fi
  local sha
  sha="$(_sha8_of_line "$file" "$line")"
  local entry="- [${key}] [sha:${sha}] [status:open] [run:${run}] ${tag} · ${file}:${line} · ${text} → ${fix}"
  echo "$entry" >> "$out"
  echo "written"
  return 0
}

_write_decision() {
  local text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --text) text="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write decision — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$text" ]; then
    echo "swarm: mem-files.sh write decision — missing --text" >&2
    return 64
  fi
  local out="$SWARM_ROOT/decisions.md"
  [ -f "$out" ] || printf '# Decisiones\n' > "$out"
  local today
  today="$(date -u +"%Y-%m-%d")"
  echo "- ${today} · ${text}" >> "$out"
  echo "written"
  return 0
}

_write_mailbox() {
  local to="" from="" run="" text=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --to) to="$2"; shift 2 ;;
      --from) from="$2"; shift 2 ;;
      --run) run="$2"; shift 2 ;;
      --text) text="$2"; shift 2 ;;
      *) echo "swarm: mem-files.sh write mailbox — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$to" ] || [ -z "$from" ] || [ -z "$run" ] || [ -z "$text" ]; then
    echo "swarm: mem-files.sh write mailbox — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/${run}/mailbox"
  mkdir -p "$dir"
  local out="$dir/${to}.md"
  touch "$out"
  echo "- [from:${from}] [ts:$(_iso_now)] ${text}" >> "$out"
  echo "written"
  return 0
}

cmd_write() {
  local kind="${1:-}"; shift || true
  case "$kind" in
    finding) _with_lock _write_finding "$@" ;;
    decision) _with_lock _write_decision "$@" ;;
    mailbox) _with_lock _write_mailbox "$@" ;;
    *)
      echo "usage: mem-files.sh write {finding|decision|mailbox} ..." >&2
      return 64
      ;;
  esac
}

cmd_query() {
  local pattern="${1:-}"; shift || true
  local scope="all"
  while [ $# -gt 0 ]; do
    case "$1" in
      --scope) scope="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  if [ -z "$pattern" ]; then
    echo "usage: mem-files.sh query <regex> [--scope findings|decisions|pack|all]" >&2
    return 64
  fi
  local targets=""
  case "$scope" in
    findings) targets="$SWARM_ROOT/findings" ;;
    decisions) targets="$SWARM_ROOT/decisions.md" ;;
    pack) targets="$SWARM_ROOT/context-pack.md" ;;
    all) targets="$SWARM_ROOT/findings $SWARM_ROOT/decisions.md $SWARM_ROOT/context-pack.md" ;;
    *) echo "swarm: mem-files.sh query — unknown scope $scope" >&2; return 64 ;;
  esac
  grep -rEn -- "$pattern" $targets 2>/dev/null | head -20
  return 0
}

case "${1:-}" in
  health) shift; cmd_health "$@" ;;
  write) shift; cmd_write "$@" ;;
  query) shift; cmd_query "$@" ;;
  *)
    echo "usage: mem-files.sh {health|write|query} ..." >&2
    exit 64
    ;;
esac
```

Guarda lo anterior en `scripts/mem-files.sh` y hazlo ejecutable: `chmod +x scripts/mem-files.sh`.
Si ya existe un `scripts/mem-files.sh` de una tanda previa incompleta, SOBRESCRÍBELO con este
contenido exacto — esta es la versión canónica de la interfaz.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_mem_files.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/mem-files.sh tests/test_mem_files.sh
git commit -m "feat: backend files — findings/decisions/mailbox con dedup y lock (mem-files.sh)"
```

---

### Task 4: `scripts/mem-stale.sh`

**Files:**
- Create: `scripts/mem-stale.sh`
- Test: `tests/test_mem_stale.sh`

**Interfaces:**
- Produces:
  ```
  mem-stale.sh hash     # imprime el sha1 de (HEAD + git status --porcelain + mtimes de dirs cubiertos)
  mem-stale.sh check    # exit 0 fresh / 1 stale / 2 sin pack-index; imprime el motivo a stdout
  mem-stale.sh seal     # escribe/reemplaza `tree-hash: <hash>` y `sealed: <ISO>` en $SWARM_ROOT/index.md
  ```
  Consumido por `memory-builder` (Task 11) y `memory-orchestrator` (Task 11) para decidir si
  reconstruir el pack.

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_STALE="$PLUGIN_ROOT/scripts/mem-stale.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

"$MEM_STALE" check >/dev/null 2>&1
assert_eq "2" "$?" "check with no index.md returns 2"

"$MEM_STALE" seal >/dev/null
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "0" "$?" "check after seal is fresh"

echo "// dirty edit" >> "$fixture/src/App/Foo.php"
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "1" "$?" "uncommitted edit to covered file marks stale"

( cd "$fixture" && git add -A && git commit -q -m "chore: dirty edit" )
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "1" "$?" "still stale until reseal, even after commit"

"$MEM_STALE" seal >/dev/null
"$MEM_STALE" check >/dev/null 2>&1
assert_eq "0" "$?" "fresh again after reseal"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_stale.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_mem_stale.sh`
Expected: FAIL — `scripts/mem-stale.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/mem-stale.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-stale.sh — tree-state hash staleness check for context-pack
set -u

SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
REPO_ROOT="$(dirname "$SWARM_ROOT")"
INDEX="$SWARM_ROOT/index.md"

_covers_dirs() {
  if [ -f "$INDEX" ]; then
    local line
    line="$(grep '^covers:' "$INDEX" 2>/dev/null | head -1 | sed 's/^covers:[[:space:]]*//')"
    if [ -n "$line" ]; then
      echo "$line" | tr ',' ' '
      return
    fi
  fi
  echo "src"
}

cmd_hash() {
  local head_sha status_sha ls_sha dir dirs combined
  head_sha="$(cd "$REPO_ROOT" && git rev-parse HEAD 2>/dev/null)"
  [ -z "$head_sha" ] && head_sha="no-head"
  status_sha="$(cd "$REPO_ROOT" && git status --porcelain 2>/dev/null | shasum -a 1 | cut -c1-40)"
  dirs="$(_covers_dirs)"
  ls_sha=""
  for dir in $dirs; do
    if [ -d "$REPO_ROOT/$dir" ]; then
      ls_sha="${ls_sha}$(cd "$REPO_ROOT" && find "$dir" -type f -exec stat -f '%N %m' {} \; 2>/dev/null | shasum -a 1 | cut -c1-40)"
    fi
  done
  ls_sha="$(printf '%s' "$ls_sha" | shasum -a 1 | cut -c1-40)"
  combined="${head_sha}:${status_sha}:${ls_sha}"
  printf '%s' "$combined" | shasum -a 1 | cut -c1-40
}

cmd_check() {
  if [ ! -f "$INDEX" ]; then
    echo "no pack-index: $INDEX"
    return 2
  fi
  local sealed_hash current_hash
  sealed_hash="$(grep '^tree-hash:' "$INDEX" 2>/dev/null | head -1 | sed 's/^tree-hash:[[:space:]]*//')"
  if [ -z "$sealed_hash" ]; then
    echo "no pack-index: missing tree-hash in $INDEX"
    return 2
  fi
  current_hash="$(cmd_hash)"
  if [ "$sealed_hash" = "$current_hash" ]; then
    echo "fresh: tree-hash matches ($current_hash)"
    return 0
  fi
  echo "stale: tree-hash changed (sealed=$sealed_hash current=$current_hash)"
  return 1
}

cmd_seal() {
  mkdir -p "$SWARM_ROOT"
  local hash iso tmp
  hash="$(cmd_hash)"
  iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  tmp="$(mktemp "$SWARM_ROOT/.index.md.XXXXXX")"
  if [ -f "$INDEX" ]; then
    grep -v '^tree-hash:' "$INDEX" | grep -v '^sealed:' > "$tmp" || true
  else
    printf '# index\ncovers: src\n' > "$tmp"
  fi
  {
    echo "tree-hash: $hash"
    echo "sealed: $iso"
  } >> "$tmp"
  mv "$tmp" "$INDEX"
  echo "sealed: $hash"
  return 0
}

case "${1:-}" in
  hash) shift; cmd_hash "$@" ;;
  check) shift; cmd_check "$@" ;;
  seal) shift; cmd_seal "$@" ;;
  *)
    echo "usage: mem-stale.sh {hash|check|seal}" >&2
    exit 64
    ;;
esac
```

Guarda lo anterior en `scripts/mem-stale.sh` y hazlo ejecutable: `chmod +x scripts/mem-stale.sh`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_mem_stale.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/mem-stale.sh tests/test_mem_stale.sh
git commit -m "feat: staleness por tree-state hash (mem-stale.sh)"
```

---

### Task 5: `scripts/mem-manifest.sh`

**Files:**
- Create: `scripts/mem-manifest.sh`
- Test: `tests/test_mem_manifest.sh`

**Interfaces:**
- Consumes: `scripts/mem-lock.sh` (Task 2).
- Produces:
  ```
  mem-manifest.sh open --tier light|full
  mem-manifest.sh register --run R --agent A --domain D --area X --owner O
  mem-manifest.sh summary --run R --line "..."
  mem-manifest.sh current
  mem-manifest.sh gc --keep 10
  ```
  `open` imprime el `run-id` (uuid en minúsculas) a stdout. Consumido por `orchestrator` (Task 12)
  y `mem-curate.sh` (`gc`, Task 11).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_MANIFEST="$PLUGIN_ROOT/scripts/mem-manifest.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

run_id="$("$MEM_MANIFEST" open --tier light)"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/$run_id/agents" ] && [ -d "$SWARM_ROOT/run/$run_id/mailbox" ] && [ -d "$SWARM_ROOT/run/$run_id/retries" ]; echo $? )" "open creates full run layout"
current="$("$MEM_MANIFEST" current)"
assert_eq "$run_id" "$current" "current points at opened run"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('tier')=='light' else 1)" "$SWARM_ROOT/run/$run_id/run.json"
assert_eq "0" "$?" "run.json has correct tier"

"$MEM_MANIFEST" register --run "$run_id" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator >/dev/null
"$MEM_MANIFEST" register --run "$run_id" --agent security-auditor --domain analysis --area "src/App" --owner orchestrator >/dev/null
assert_eq "0" "$( [ -f "$SWARM_ROOT/run/$run_id/agents/architecture-auditor.json" ] && [ -f "$SWARM_ROOT/run/$run_id/agents/security-auditor.json" ]; echo $? )" "register writes distinct per-agent files"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('agent')=='architecture-auditor' else 1)" "$SWARM_ROOT/run/$run_id/agents/architecture-auditor.json"
assert_eq "0" "$?" "architecture-auditor.json not clobbered by security-auditor registration"

# gc keeps 10 most recent + always keeps adhoc
mkdir -p "$SWARM_ROOT/run/adhoc"
for i in $(seq 1 12); do
  rid="fixture-run-$i"
  mkdir -p "$SWARM_ROOT/run/$rid"
  printf '{"id": "%s", "tier": "light", "started": "2026-01-%02dT00:00:00Z"}\n' "$rid" "$i" > "$SWARM_ROOT/run/$rid/run.json"
done
"$MEM_MANIFEST" gc --keep 10 >/dev/null
remaining="$(find "$SWARM_ROOT/run" -maxdepth 1 -type d -name 'fixture-run-*' | wc -l | tr -d ' ')"
assert_eq "10" "$remaining" "gc keeps the 10 most recent fixture runs"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/adhoc" ]; echo $? )" "gc never removes adhoc"
assert_eq "1" "$( [ -d "$SWARM_ROOT/run/fixture-run-1" ]; echo $? )" "gc removes oldest run (fixture-run-1)"
assert_eq "0" "$( [ -d "$SWARM_ROOT/run/fixture-run-12" ]; echo $? )" "gc keeps newest run (fixture-run-12)"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_manifest.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_mem_manifest.sh`
Expected: FAIL — `scripts/mem-manifest.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/mem-manifest.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-manifest.sh — per-run manifest management
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"
SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"

_with_lock() {
  "$LOCK_SCRIPT" acquire || return 1
  trap '"$LOCK_SCRIPT" release' EXIT INT TERM
  "$@"
  local rc=$?
  "$LOCK_SCRIPT" release
  trap - EXIT INT TERM
  return $rc
}

cmd_open() {
  local tier=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --tier) tier="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  case "$tier" in
    light|full) ;;
    *) echo "usage: mem-manifest.sh open --tier light|full" >&2; return 64 ;;
  esac
  local run_id
  run_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  local run_dir="$SWARM_ROOT/run/$run_id"
  mkdir -p "$run_dir/agents" "$run_dir/mailbox" "$run_dir/retries"
  local started
  started="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  python3 -c "
import json, sys
data = {'id': sys.argv[1], 'tier': sys.argv[2], 'started': sys.argv[3]}
with open(sys.argv[4], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$run_id" "$tier" "$started" "$run_dir/run.json"
  mkdir -p "$SWARM_ROOT/run"
  printf '%s' "$run_id" > "$SWARM_ROOT/run/current"
  echo "$run_id"
  return 0
}

_register() {
  local run="" agent="" domain="" area="" owner=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run="$2"; shift 2 ;;
      --agent) agent="$2"; shift 2 ;;
      --domain) domain="$2"; shift 2 ;;
      --area) area="$2"; shift 2 ;;
      --owner) owner="$2"; shift 2 ;;
      *) echo "swarm: mem-manifest.sh register — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$run" ] || [ -z "$agent" ] || [ -z "$domain" ] || [ -z "$area" ] || [ -z "$owner" ]; then
    echo "swarm: mem-manifest.sh register — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/$run/agents"
  mkdir -p "$dir"
  python3 -c "
import json, sys
data = {'agent': sys.argv[1], 'domain': sys.argv[2], 'area': sys.argv[3], 'owner': sys.argv[4]}
with open(sys.argv[5], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "$agent" "$domain" "$area" "$owner" "$dir/${agent}.json"
  echo "registered"
  return 0
}

_summary() {
  local run="" line=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --run) run="$2"; shift 2 ;;
      --line) line="$2"; shift 2 ;;
      *) echo "swarm: mem-manifest.sh summary — unknown arg $1" >&2; return 64 ;;
    esac
  done
  if [ -z "$run" ] || [ -z "$line" ]; then
    echo "swarm: mem-manifest.sh summary — missing required arg" >&2
    return 64
  fi
  local dir="$SWARM_ROOT/run/$run"
  mkdir -p "$dir"
  echo "$line" >> "$dir/summary.md"
  echo "written"
  return 0
}

cmd_current() {
  local f="$SWARM_ROOT/run/current"
  [ -f "$f" ] || return 1
  cat "$f"
  return 0
}

cmd_gc() {
  local keep=10
  while [ $# -gt 0 ]; do
    case "$1" in
      --keep) keep="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local run_root="$SWARM_ROOT/run"
  [ -d "$run_root" ] || return 0
  local tmp_list
  tmp_list="$(mktemp)"
  for d in "$run_root"/*/; do
    [ -d "$d" ] || continue
    local name
    name="$(basename "$d")"
    [ "$name" = "adhoc" ] && continue
    local run_json="$d/run.json"
    [ -f "$run_json" ] || continue
    local started
    started="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('started',''))" "$run_json" 2>/dev/null)"
    [ -n "$started" ] || continue
    echo "$started|$name" >> "$tmp_list"
  done
  local total
  total="$(sort "$tmp_list" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$total" -gt "$keep" ]; then
    local to_remove=$((total - keep))
    sort "$tmp_list" | head -n "$to_remove" | while IFS='|' read -r started name; do
      rm -rf "${run_root:?}/${name}"
    done
  fi
  rm -f "$tmp_list"
  echo "gc: kept newest $keep run(s)"
  return 0
}

case "${1:-}" in
  open) shift; cmd_open "$@" ;;
  register) shift; _with_lock _register "$@" ;;
  summary) shift; _with_lock _summary "$@" ;;
  current) shift; cmd_current "$@" ;;
  gc) shift; _with_lock cmd_gc "$@" ;;
  *)
    echo "usage: mem-manifest.sh {open|register|summary|current|gc} ..." >&2
    exit 64
    ;;
esac
```

Guarda lo anterior en `scripts/mem-manifest.sh` y hazlo ejecutable:
`chmod +x scripts/mem-manifest.sh`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_mem_manifest.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/mem-manifest.sh tests/test_mem_manifest.sh
git commit -m "feat: manifest per-agente append-only + gc de runs (mem-manifest.sh)"
```

---

### Task 6: `hooks/validate-output.py` + `hooks/hooks.json` (SubagentStop)

**Files:**
- Create: `hooks/validate-output.py`
- Create: `hooks/hooks.json`
- Test: `tests/test_validate_output.sh`

**Interfaces:**
- Consumes (contrato de stdin, JSON): `{"agent_type": "swarm:<name>", "output": "<texto completo>"}`.
  Este es el contrato de entrada que el runtime de hooks entrega al script; se documenta aquí
  porque `skills/swarm-protocol/SKILL.md` (Task 8) describe la salida que produce esta entrada.
- Produces (stdout): nada si el output es válido (exit 0); `{"decision":"block","reason":"..."}`
  si se rechaza (exit 0); `{"systemMessage":"..."}` si `turns==max` o si es el segundo fallo del
  mismo agente en el mismo run (exit 0, nunca bloquea dos veces seguidas).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/validate-output.py"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

# missing evidence line -> block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "output": "OK"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "missing evidence line is blocked"

# OK + evidence files=0 -> block (spec smoke test 8)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:architecture-auditor", "output": "OK\nevidence: files=0 cmds=1 turns=2/10"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "OK with files=0 is blocked"

# valid OK+evidence with extra spaces -> NO block (regression: lenient whitespace)
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:extra-spacing-agent", "output": "OK\nevidence:  files=2  cmds=1  turns=3/10\nARCH · src/App/Foo.php:3 · sin interfaz → extraer interfaz"}
EOF
)"
assert_eq "" "$out" "lenient whitespace evidence line is accepted (no output)"

# valid minimal -> no output, exit 0
out_file="$fixture/valid-out.txt"
python3 "$HOOK" > "$out_file" 2>&1 <<'EOF'
{"agent_type": "swarm:vulnerability-scanner", "output": "DONE\nevidence: files=1 cmds=3 turns=1/10\nSEC · src/App/Foo.php:1 · secreto en claro → mover a env"}
EOF
rc=$?
assert_eq "0" "$rc" "valid minimal output exits 0"
assert_eq "0" "$(wc -l < "$out_file" | tr -d ' ')" "valid minimal output prints nothing"

# repeat failing input twice -> 2nd time accepted with systemMessage
bad_input='{"agent_type": "swarm:flaky-agent", "output": "OK"}'
first="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$first" | grep -q '"decision": "block"' && echo 0 || echo 1)" "first failure is blocked"
second="$(printf '%s' "$bad_input" | python3 "$HOOK")"
assert_eq "0" "$(echo "$second" | grep -q 'systemMessage' && echo 0 || echo 1)" "second failure is accepted with systemMessage"
assert_eq "1" "$(echo "$second" | grep -q '"decision": "block"' && echo 0 || echo 1)" "second failure is not a block"

# non-swarm agent_type -> no output
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "some-other-agent", "output": "garbage output with no structure at all"}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type produces no output"

# turns==max -> systemMessage present, decision not block
out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:reviewer", "output": "OK\nevidence: files=3 cmds=2 turns=15/15\nREV · src/App/Foo.php:5 · falta validacion → anadir guard"}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q 'systemMessage' && echo 0 || echo 1)" "turns==max produces systemMessage"
assert_eq "1" "$(echo "$out" | grep -q '"decision": "block"' && echo 0 || echo 1)" "turns==max is not a block"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_validate_output.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_validate_output.sh`
Expected: FAIL — `can't open file '.../hooks/validate-output.py': No such file or directory`.

- [ ] **Paso 3: implementar `hooks/validate-output.py`**

```python
#!/usr/bin/env python3
"""hooks/validate-output.py — SubagentStop hook: valida el contrato de evidencia swarm (spec §6.1).

Contrato de stdin (JSON):
  {"agent_type": "swarm:<name>", "output": "<texto completo producido por el subagente>"}

Comportamiento:
  - agent_type que no empieza por "swarm:" -> exit 0, sin salida (no es de nuestra incumbencia).
  - línea 1 debe ser un veredicto: OK | KO <motivo> | DONE | BLOCKED <motivo>.
  - línea 2 debe ser `evidence: files=N cmds=M turns=k/max` (tolerante a espacios).
  - OK con files=0 se rechaza (verdicto verde sin evidencia real).
  - narración (prosa larga en vez del formato de hallazgo) se rechaza.
  - si turns == max: NO es un bloqueo; se emite un systemMessage y se sale con 0.
  - un rechazo se reintenta como máximo una vez (contador en run/<run>/retries/<agente>); al
    SEGUNDO rechazo del mismo agente en el mismo run, se acepta como BLOCKED (con systemMessage)
    en vez de rechazar de nuevo -- nunca bucle infinito.
"""
import json
import os
import re
import sys

VERDICT_RE = re.compile(r'^(OK|KO .+|DONE|BLOCKED .+)$')
EVIDENCE_RE = re.compile(
    r'^evidence:\s*files\s*=\s*(\d+)\s+cmds\s*=\s*(\d+)\s+turns\s*=\s*(\d+)\s*/\s*(\d+)\s*$'
)
FINDING_RE = re.compile(r'^[A-Z0-9_-]+\s*·\s*\S+:\d+\s*·\s.+→.+$')
MAX_FINDING_LINE_LEN = 120


def _swarm_root():
    return os.environ.get('SWARM_ROOT', os.path.join(os.getcwd(), '.swarm'))


def _current_run(swarm_root):
    current_file = os.path.join(swarm_root, 'run', 'current')
    try:
        with open(current_file) as f:
            run_id = f.read().strip()
            if run_id:
                return run_id
    except OSError:
        pass
    return 'adhoc'


def _retry_count(swarm_root, run_id, agent_type):
    agent_basename = agent_type.split(':')[-1]
    retries_dir = os.path.join(swarm_root, 'run', run_id, 'retries')
    path = os.path.join(retries_dir, agent_basename)
    try:
        with open(path) as f:
            return int(f.read().strip() or '0'), path, retries_dir
    except (OSError, ValueError):
        return 0, path, retries_dir


def _bump_retry(path, retries_dir, count):
    os.makedirs(retries_dir, exist_ok=True)
    with open(path, 'w') as f:
        f.write(str(count + 1))


def _block(reason):
    print(json.dumps({'decision': 'block', 'reason': reason}))
    sys.exit(0)


def _system_message(message):
    print(json.dumps({'systemMessage': message}))
    sys.exit(0)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    agent_type = data.get('agent_type', '') or ''
    if not agent_type.startswith('swarm:'):
        sys.exit(0)

    output = data.get('output', '') or ''
    lines = output.split('\n')

    swarm_root = _swarm_root()
    run_id = _current_run(swarm_root)
    retry_count, retry_path, retries_dir = _retry_count(swarm_root, run_id, agent_type)

    verdict_line = lines[0].strip() if len(lines) >= 1 else ''
    evidence_line = lines[1].strip() if len(lines) >= 2 else ''

    reason = None

    if not VERDICT_RE.match(verdict_line):
        reason = 'línea 1 debe ser un veredicto: OK | KO <motivo> | DONE | BLOCKED <motivo>'

    evidence_match = None
    if reason is None:
        evidence_match = EVIDENCE_RE.match(evidence_line)
        if not evidence_match:
            reason = 'línea 2 obligatoria: evidence: files=N cmds=M turns=k/max'

    turns_k = turns_max = None
    if reason is None:
        files_n = int(evidence_match.group(1))
        turns_k = int(evidence_match.group(3))
        turns_max = int(evidence_match.group(4))

        if verdict_line == 'OK' and files_n == 0:
            reason = 'OK con files=0 — verdict verde sin evidencia real'

        if reason is None:
            for line in lines[2:]:
                stripped = line.strip()
                if not stripped:
                    continue
                if stripped.startswith('- '):
                    continue
                if FINDING_RE.match(stripped):
                    continue
                if len(stripped) > MAX_FINDING_LINE_LEN:
                    reason = 'narración detectada fuera del formato TAG · file:línea · problema → fix'
                    break

    if reason is None:
        if turns_k is not None and turns_k == turns_max:
            _system_message(
                'swarm: %s alcanzó maxTurns → tratar como BLOCKED maxTurns' % agent_type
            )
        sys.exit(0)

    if retry_count >= 1:
        _system_message(
            'swarm: %s falló la validación dos veces (%s) → aceptado como BLOCKED' % (agent_type, reason)
        )

    _bump_retry(retry_path, retries_dir, retry_count)
    _block(reason)


if __name__ == '__main__':
    main()
```

Guarda lo anterior en `hooks/validate-output.py` y hazlo ejecutable:
`chmod +x hooks/validate-output.py`.

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "^swarm:",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/validate-output.py\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Guarda lo anterior en `hooks/hooks.json`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_validate_output.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add hooks/validate-output.py hooks/hooks.json tests/test_validate_output.sh
git commit -m "feat: hook SubagentStop — contrato de evidencia con reintento y regex tolerante"
```

---

### Task 7: `hooks/bash-guard.py` + `hooks/bash-allowlist.json` (PreToolUse)

**Files:**
- Create: `hooks/bash-guard.py`
- Create: `hooks/bash-allowlist.json`
- Modify: `hooks/hooks.json` (Task 6) — añade la entrada `PreToolUse`
- Test: `tests/test_bash_guard.sh`

**Interfaces:**
- Consumes (contrato de stdin, JSON):
  `{"agent_type": "swarm:<name>", "tool_name": "Bash", "tool_input": {"command": "<comando>"}}`.
- Produces (stdout): nada si se permite (exit 0);
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}`
  si se deniega (exit 0).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

_run_hook() {
  python3 "$HOOK"
}

# 1. allowed `git log --oneline` for any agent -> no output/allow
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:reviewer", "tool_name": "Bash", "tool_input": {"command": "git log --oneline -5"}}
EOF
)"
assert_eq "" "$out" "git log --oneline is allowed, no output"

# 2. `rm -rf /` for swarm:memory-curator -> deny
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-curator", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "rm -rf / is denied for memory-curator"

# 3. chained `git status && rm x` -> deny (identifies the disallowed second segment)
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git status && rm x"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "chained command with disallowed second segment is denied"
assert_eq "0" "$(echo "$out" | grep -qF 'rm x' && echo 0 || echo 1)" "deny reason names the disallowed segment (rm x)"

# 4. quoted `&&` inside a string is NOT treated as a chain break
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "git commit -m \"a && b\""}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '"permissionDecision": "deny"' && echo 0 || echo 1)" "quoted && is not split; whole segment evaluated"
assert_eq "0" "$(echo "$out" | grep -qF 'git commit -m' && echo 0 || echo 1)" "deny reason cites the full unsplit segment, not a fragment"

# 5. non-swarm agent_type or missing agent_type -> no output/allow silently
out="$(_run_hook <<'EOF'
{"agent_type": "some-other-agent", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "" "$out" "non-swarm agent_type is not policed"

out="$(_run_hook <<'EOF'
{"tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "" "$out" "missing agent_type is not policed"

# 6. piped `find . | grep x` where both prefixes allowed -> allow
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-builder", "tool_name": "Bash", "tool_input": {"command": "find . -name '*.php' | grep Foo"}}
EOF
)"
assert_eq "" "$out" "piped find | grep with both segments allowlisted is allowed"

# 7. mem- script invoked via ${CLAUDE_PLUGIN_ROOT} prefix is allowed
out="$(_run_hook <<'EOF'
{"agent_type": "swarm:memory-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh health"}}
EOF
)"
assert_eq "" "$out" "scripts/mem-*.sh via CLAUDE_PLUGIN_ROOT prefix is allowed"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_bash_guard.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_bash_guard.sh`
Expected: FAIL — `can't open file '.../hooks/bash-guard.py': No such file or directory`.

- [ ] **Paso 3: implementar `hooks/bash-allowlist.json` y `hooks/bash-guard.py`**

```json
{
  "default": [
    "git status", "git log", "git diff", "git show", "git rev-parse",
    "ls", "cat", "head", "tail", "wc", "grep", "find",
    "uuidgen", "python3", "scripts/mem-", "scripts/mem-lock.sh"
  ],
  "agents": {
    "swarm:memory-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "uuidgen", "python3", "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:memory-builder": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "python3", "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:memory-curator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "python3", "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "uuidgen", "python3", "scripts/mem-", "scripts/mem-lock.sh"
    ]
  }
}
```

Guarda lo anterior en `hooks/bash-allowlist.json`.

```python
#!/usr/bin/env python3
"""hooks/bash-guard.py — PreToolUse hook: allowlist de Bash por agent_type (spec §3.1).

Contrato de stdin (JSON):
  {"agent_type": "swarm:<name>", "tool_name": "Bash", "tool_input": {"command": "<comando>"}}
"""
import json
import os
import shlex
import sys

ALLOWLIST_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'bash-allowlist.json')


def load_allowlist():
    with open(ALLOWLIST_PATH) as f:
        return json.load(f)


def split_segments(command):
    """Divide `command` en &&, ||, ;, | FUERA de comillas (estado de comilla char a char)."""
    segments = []
    current = []
    i = 0
    n = len(command)
    quote = None
    while i < n:
        ch = command[i]
        if quote:
            current.append(ch)
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ('"', "'"):
            quote = ch
            current.append(ch)
            i += 1
            continue
        if command[i:i + 2] in ('&&', '||'):
            segments.append(''.join(current))
            current = []
            i += 2
            continue
        if ch in (';', '|'):
            segments.append(''.join(current))
            current = []
            i += 1
            continue
        current.append(ch)
        i += 1
    segments.append(''.join(current))
    return [s.strip() for s in segments if s.strip()]


def segment_words(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def strip_plugin_root(word):
    prefix = '${CLAUDE_PLUGIN_ROOT}/'
    if word.startswith(prefix):
        return word[len(prefix):]
    return word


def segment_allowed(segment, allowlist):
    words = segment_words(segment)
    if not words:
        return False
    first_raw = strip_plugin_root(words[0])
    first_two = ' '.join(words[:2])
    basename = os.path.basename(first_raw)
    for prefix in allowlist:
        if ' ' in prefix:
            if first_two == prefix or first_two.startswith(prefix + ' '):
                return True
            continue
        if first_raw.startswith(prefix):
            return True
        if prefix.startswith('scripts/mem') and basename.startswith('mem-'):
            return True
    return False


def deny(reason):
    print(json.dumps({
        'hookSpecificOutput': {
            'hookEventName': 'PreToolUse',
            'permissionDecision': 'deny',
            'permissionDecisionReason': reason,
        }
    }))
    sys.exit(0)


def main():
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    agent_type = data.get('agent_type', '') or ''
    if not agent_type.startswith('swarm:'):
        sys.exit(0)

    tool_name = data.get('tool_name', '') or ''
    if tool_name != 'Bash':
        sys.exit(0)

    command = (data.get('tool_input') or {}).get('command', '') or ''
    if not command.strip():
        sys.exit(0)

    allowlists = load_allowlist()
    agent_allowlist = allowlists.get('agents', {}).get(agent_type, allowlists.get('default', []))

    for segment in split_segments(command):
        if not segment_allowed(segment, agent_allowlist):
            deny('%s no está en el allowlist de %s' % (segment, agent_type))
            return

    sys.exit(0)


if __name__ == '__main__':
    main()
```

Guarda lo anterior en `hooks/bash-guard.py` y hazlo ejecutable: `chmod +x hooks/bash-guard.py`.

Edita `hooks/hooks.json` (Task 6) para añadir la entrada `PreToolUse` junto a `SubagentStop`:

```json
{
  "hooks": {
    "SubagentStop": [
      {
        "matcher": "^swarm:",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/validate-output.py\"",
            "timeout": 10
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"${CLAUDE_PLUGIN_ROOT}/hooks/bash-guard.py\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_bash_guard.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add hooks/bash-guard.py hooks/bash-allowlist.json hooks/hooks.json tests/test_bash_guard.sh
git commit -m "feat: hook PreToolUse — allowlist de Bash con tokenizer consciente de comillas"
```

---

### Task 8: `skills/swarm-protocol/SKILL.md`

**Files:**
- Create: `skills/swarm-protocol/SKILL.md`
- Test: `tests/test_skill_protocol.sh`

**Interfaces:**
- Consumes: firmas exactas de `mem-files.sh`/`mem-stale.sh`/`mem-manifest.sh` (Tasks 3–5) — el
  cheat-sheet de esta skill debe citarlas literalmente.
- Produces: el contrato (§4 del fichero) que consumen `agents/memory-orchestrator.md`,
  `agents/memory-builder.md`, `agents/memory-curator.md` (Task 11) y `agents/orchestrator.md`
  (Task 12) vía `skills: [swarm-protocol]`.

**Modelo:** opus (contrato central del plugin) · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
SKILL_FILE="$PLUGIN_ROOT/skills/swarm-protocol/SKILL.md"

assert_eq "0" "$( [ -f "$SKILL_FILE" ]; echo $? )" "SKILL.md exists"
assert_file_contains "$SKILL_FILE" "evidence: files=" "mentions evidence contract format"
assert_file_contains "$SKILL_FILE" "run/adhoc" "mentions adhoc run mode"
assert_file_contains "$SKILL_FILE" "mailbox" "mentions mailbox"
assert_file_contains "$SKILL_FILE" "SWARM_ROOT" "mentions SWARM_ROOT"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_skill_protocol.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_skill_protocol.sh`
Expected: FAIL — `SKILL.md exists` falla (fichero no existe todavía).

- [ ] **Paso 3: implementar `skills/swarm-protocol/SKILL.md`**

````markdown
---
name: swarm-protocol
description: Contrato universal para todos los agentes del plugin swarm — memoria, evidencia, mailbox, modos adhoc/worktree.
---

# Protocolo swarm

Precargado (`skills: [swarm-protocol]`) en todo agente del plugin `swarm`. Este contrato es el
mismo para raíz, orquestadores de dominio y hojas — spec
`docs/superpowers/specs/2026-09-01-swarm-design.md` §5, §6, §9.2, §9.3.

## 1. Antes de actuar

1. **Lee la memoria antes de buscar.** `cat "$SWARM_ROOT/context-pack.md"` (o pide el pack a
   `memory-orchestrator` si no existe) ANTES de cualquier `Grep`/`Read` exploratorio. Abre solo el
   excerpt alrededor de la línea citada — nunca releas el fichero completo si el pack ya te dio
   `fichero:línea`.
2. **No re-reportes.** Si un hallazgo ya está en `findings/<otro-agente>.md` o en la sección
   `SHARED-FOUND` del pack, no lo repitas — cítalo o amplíalo, no lo dupliques.
3. **Lee tu buzón al arrancar.** Antes de actuar, comprueba si alguien te dejó contexto:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/<tu-nombre>.md" 2>/dev/null
   ```
   Si el fichero no existe, no hay mensajes pendientes — continúa normalmente.

## 2. Modo run vs modo adhoc (§9.2)

- Si tu prompt de lanzamiento incluye una línea `run-id: <uuid>`, estás dentro de un run
  orquestado: usa `RUN=<ese uuid>` en todos los comandos de memoria.
- Si tu prompt NO incluye `run-id:`, te invocaron suelto (adhoc, fuera de un run orquestado): usa
  `RUN=adhoc` fijo. **No** llames a `mem-manifest.sh open` — ese comando es exclusivo de la raíz
  al abrir un run real. Crea los subdirectorios de `run/adhoc/` si faltan (`mkdir -p`) y sigue el
  contrato de evidencia (§4) sin excepción.
- Caso particular: si eres `implementer` (fase 5, todavía no existe) y te invocan sin referencia a
  un plan concreto, tu veredicto es `BLOCKED necesita plan` — no improvises un plan.

## 3. Modo worktree (§9.3)

Si tu frontmatter tiene `isolation: worktree`, tu prompt de lanzamiento te da la ruta ABSOLUTA del
`.swarm/` del repo principal (no la de tu worktree aislado). Reglas:
- **Lee** ese `.swarm/` directamente con la ruta absoluta dada — nunca una copia dentro del
  worktree, y nunca asumas que `$SWARM_ROOT` relativo a tu cwd apunta al sitio correcto.
- **Nunca escribas ahí directamente.** Toda escritura (`finding`, `decision`, `mailbox`) va vía
  `SendMessage` a `memory-orchestrator`, que es quien tiene la ruta canónica y aplica el lock. Una
  escritura directa desde el worktree puede divergir del `.swarm/` canónico.

## 4. Contrato de evidencia (obligatorio, spec §6)

Toda salida de un agente `swarm:*` sigue este formato exacto:

```
<línea 1: veredicto>
evidence: files=N cmds=M turns=k/max
<líneas siguientes: hallazgos, opcional>
```

- **Línea 1 — veredicto**, una de: `OK` · `KO <peor problema>` · `DONE` · `BLOCKED <motivo>`.
- **Línea 2 — evidencia, MANDATORIA**: `evidence: files=N cmds=M turns=k/max` donde `N` = ficheros
  leídos, `M` = comandos deterministas ejecutados, `k/max` = turno actual sobre el `maxTurns` del
  frontmatter. El hook de validación es TOLERANTE con espacios extra alrededor de `=` y después de
  `:` (p. ej. `evidence:  files=2  cmds=1  turns=3/10` es válido) — pero el formato base (las
  claves `files=`, `cmds=`, `turns=.../...`) es obligatorio.
- **`OK` con `files=0` se rechaza siempre** — un veredicto verde sin haber leído nada no es
  evidencia real.
- **Resto de líneas — hallazgos**, uno por línea, formato:
  `TAG · fichero:línea · problema → fix (≤8 palabras)`. El detalle completo (contexto largo,
  snippets) va a `findings/<tu-nombre>.md` vía `memory-orchestrator write finding`, NUNCA en la
  salida que lee el hook — cualquier prosa suelta ahí se interpreta como narración y se rechaza.

### 4.1 Cheat-sheet de invocación (rutas desde `${CLAUDE_PLUGIN_ROOT}`)

```bash
# salud del backend files (antes de cualquier escritura, si tienes dudas)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" health

# escribir un hallazgo (dedup automático por [key:agente|tag|fichero:línea])
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write finding \
  --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 42 \
  --run "${RUN:-adhoc}" --text "clase sin interfaz" --fix "extraer interfaz"

# escribir una decisión (append a decisions.md)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write decision --text "usar sonnet para ejecución"

# dejar un mensaje en el buzón de otro agente (aunque aún no esté lanzado)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write mailbox \
  --to security-auditor --from architecture-auditor --run "${RUN:-adhoc}" \
  --text "revisa src/App/Foo.php:42 — sin interfaz, puede afectar aislamiento de tenant"

# consultar findings/decisiones/pack (cap 20 resultados)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "tenant" --scope findings

# comprobar si el context-pack está fresco antes de reconstruir (solo memory-builder)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" check

# manifest del run (solo raíz / memory-orchestrator)
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register \
  --run "$RUN" --agent architecture-auditor --domain analysis --area "src/App" --owner orchestrator
```

Cada llamada a `mem-files.sh write ...` y a `mem-manifest.sh register|summary|gc` ya adquiere y
libera el lock internamente (`scripts/mem-lock.sh`) — no lo llames tú directamente salvo que estés
escribiendo un script nuevo que toque `.swarm/` fuera de estos dos.

## 5. Tool determinista antes que modelo

Antes de razonar sobre un problema, ejecuta el linter/scanner/test determinista del pack (si
aplica) y trata solo el residual con juicio de modelo. Nunca "revises a ojo" lo que un `--fix`
puede resolver solo.

## 6. Parar por saturación

Deja de explorar cuando dejes de encontrar patrones nuevos, no cuando llegues a un número fijo de
hallazgos. `maxTurns` de tu frontmatter es el límite duro — si lo alcanzas sin cerrar, tu veredicto
es igualmente `OK`/`DONE`/`KO`/`BLOCKED` con la evidencia que tengas; el hook se encarga de anotar
`maxTurns` si corresponde, tú no necesitas mencionarlo aparte.

## 7. Frontmatter obligatorio

Todo agente de este plugin declara, sin excepción: `name`, `description` (frase "Use when…" que
dispare uso proactivo), `model`, `tools`, `maxTurns`, `memory: project`, `skills: [swarm-protocol]`.
Nunca declares `hooks`, `mcpServers` ni `permissionMode` en el frontmatter — se ignoran para
subagentes de plugin (spec §3.1) y su presencia solo confunde a quien lea el fichero.

## 8. Ejemplos de salida completa

### Ejemplo A — `OK` con evidencia y hallazgos

```
OK
evidence: files=4 cmds=2 turns=6/15
ARCH · src/App/Foo.php:42 · clase sin interfaz → extraer interfaz
ARCH · src/App/Bar.php:10 · lógica de dominio en controller → mover a servicio
```

### Ejemplo B — `BLOCKED`

```
BLOCKED necesita plan
evidence: files=1 cmds=0 turns=1/30
```
````

Guarda lo anterior en `skills/swarm-protocol/SKILL.md`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_skill_protocol.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add skills/swarm-protocol/SKILL.md tests/test_skill_protocol.sh
git commit -m "docs: contrato universal swarm-protocol (evidencia, mailbox, adhoc, worktree)"
```

---

### Task 9: `commands/init.md` + `scripts/swarm-init.sh`

**Files:**
- Create: `scripts/swarm-init.sh`
- Create: `commands/init.md`
- Test: `tests/test_swarm_init.sh`

**Interfaces:**
- Consumes: `scripts/mem-files.sh health` (Task 3).
- Produces: `.swarm/memory.json`, `.swarm/decisions.md`, bloque `.gitignore` marcado `# swarm`.
  Ejecutado por `/swarm:init` (invocado por el usuario o por `orchestrator`, Task 12, si detecta
  que `.swarm/` no existe todavía — aunque en fase 1 `orchestrator` no auto-invoca init, solo lo
  documenta).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
INIT_SCRIPT="$PLUGIN_ROOT/scripts/swarm-init.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"

"$INIT_SCRIPT" >/dev/null 2>&1
rc=$?
assert_eq "0" "$rc" "fresh init succeeds"
assert_eq "0" "$( [ -f "$SWARM_ROOT/memory.json" ]; echo $? )" "memory.json created"
assert_eq "0" "$( [ -f "$SWARM_ROOT/decisions.md" ]; echo $? )" "decisions.md created"
assert_file_contains "$fixture/.gitignore" "# swarm" "gitignore has swarm marker"
assert_file_contains "$fixture/.gitignore" ".swarm/run/" "gitignore ignores run/"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
files = [b for b in d['backends'] if b['name'] == 'files'][0]
sys.exit(0 if files['required'] is True else 1)
" "$SWARM_ROOT/memory.json"
assert_eq "0" "$?" "memory.json is valid JSON with files.required == true"

# second run is idempotent
"$INIT_SCRIPT" >/dev/null 2>&1
marker_count="$(grep -c '^# swarm$' "$fixture/.gitignore")"
assert_eq "1" "$marker_count" "gitignore swarm block appears exactly once after 2nd init"
decisions_header_count="$(grep -c '^# Decisiones$' "$SWARM_ROOT/decisions.md")"
assert_eq "1" "$decisions_header_count" "decisions.md not duplicated after 2nd init"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_swarm_init.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_swarm_init.sh`
Expected: FAIL — `scripts/swarm-init.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/swarm-init.sh`**

```bash
#!/usr/bin/env bash
# scripts/swarm-init.sh — /swarm:init: bootstrap de .swarm/ en el repo target (spec §4.6)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
REPO_ROOT="$(dirname "$SWARM_ROOT")"
GITIGNORE="$REPO_ROOT/.gitignore"
MARKER="# swarm"

mkdir -p "$SWARM_ROOT/findings" "$SWARM_ROOT/run"

if [ ! -f "$SWARM_ROOT/memory.json" ]; then
  cat > "$SWARM_ROOT/memory.json" <<'JSONEOF'
{
  "backends": [
    { "name": "files", "type": "files", "root": ".swarm", "default": true, "required": true },
    { "name": "claude-mem", "type": "mcp", "server": "plugin_claude-mem_mcp-search", "scope": "historical", "required": false }
  ],
  "policy": {
    "read": ["files", "claude-mem"],
    "write": ["files", "claude-mem"],
    "stale": { "mode": "tree-hash" }
  }
}
JSONEOF
fi

if [ ! -f "$SWARM_ROOT/decisions.md" ]; then
  printf '# Decisiones\n' > "$SWARM_ROOT/decisions.md"
fi

if [ -f "$GITIGNORE" ] && grep -qF "$MARKER" "$GITIGNORE" 2>/dev/null; then
  :
else
  {
    echo "$MARKER"
    echo ".swarm/context-pack.md"
    echo ".swarm/index.md"
    echo ".swarm/findings/"
    echo ".swarm/run/"
    echo ".swarm/.lock.d"
  } >> "$GITIGNORE"
fi

if ! "$SCRIPT_DIR/mem-files.sh" health >/dev/null 2>&1; then
  echo "swarm: init — backend 'files' health check falló, abortando" >&2
  exit 1
fi

if [ -z "${CLAUDE_MEM_AVAILABLE:-}" ]; then
  echo "swarm: init — aviso: claude-mem no confirmado disponible (best-effort, no bloquea)" >&2
fi

echo "swarm: init completo"
echo "  .swarm/memory.json      backend 'files' requerido (ok) + 'claude-mem' best-effort"
echo "  .swarm/decisions.md     esqueleto creado"
echo "  .gitignore              bloque swarm añadido/idempotente"
exit 0
```

Guarda lo anterior en `scripts/swarm-init.sh` y hazlo ejecutable: `chmod +x scripts/swarm-init.sh`.

````markdown
---
description: Inicializa .swarm/ en este repo (memoria, gitignore, health-gate del backend files).
allowed-tools: Bash
---

Ejecuta `${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh` y reporta su salida al usuario tal cual — no
reformatees ni resumas, ya es un resumen en texto plano. Si el script termina con código distinto
de 0, informa que `/swarm:init` abortó y muestra el motivo (línea de stderr del health check).

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/swarm-init.sh"
```
````

Guarda lo anterior en `commands/init.md`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_swarm_init.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/swarm-init.sh commands/init.md tests/test_swarm_init.sh
git commit -m "feat: /swarm:init — bootstrap de .swarm con health-gate del backend files"
```

---

### Task 10: `scripts/mem-scan.sh`

**Files:**
- Create: `scripts/mem-scan.sh`
- Test: `tests/test_mem_scan.sh`

**Interfaces:**
- Produces: `mem-scan.sh [--root DIR]` — imprime a stdout un esqueleto markdown de context-pack:
  `# context-pack`, `stack: <php-ddd-symfony8|generic>` (+ línea `warning:` si generic),
  `covers: <lista>`, `## Tree`, `## Entrypoints`, `## Markers`, `## SHARED-FOUND`. Consumido por
  `memory-builder` (Task 11).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_SCAN="$PLUGIN_ROOT/scripts/mem-scan.sh"

fixture="$(make_fixture)"
out="$("$MEM_SCAN" --root "$fixture")"
assert_eq "0" "$(echo "$out" | grep -q '^stack: php-ddd-symfony8$' && echo 0 || echo 1)" "symfony fixture detects php-ddd-symfony8"
assert_eq "0" "$(echo "$out" | grep -q '^## Markers$' && echo 0 || echo 1)" "has Markers section"

generic_fixture="$(mktemp -d "${TMPDIR:-/tmp}/swarm-generic.XXXXXX")"
mkdir -p "$generic_fixture/src"
out2="$("$MEM_SCAN" --root "$generic_fixture")"
assert_eq "0" "$(echo "$out2" | grep -q '^stack: generic$' && echo 0 || echo 1)" "no composer.json falls back to generic"
assert_eq "0" "$(echo "$out2" | grep -q 'warning: stack no detectado' && echo 0 || echo 1)" "generic fallback includes warning line"

rm -rf "$fixture" "$generic_fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_scan.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_mem_scan.sh`
Expected: FAIL — `scripts/mem-scan.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/mem-scan.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-scan.sh — imprime un esqueleto de context-pack a stdout (spec §8.1, §4.4)
set -u

ROOT="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
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
  ! -path '*/vendor/*' ! -path '*/node_modules/*' ! -path '*/.git/*' ! -path '*/var/*' 2>/dev/null

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
```

Guarda lo anterior en `scripts/mem-scan.sh` y hazlo ejecutable: `chmod +x scripts/mem-scan.sh`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_mem_scan.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/mem-scan.sh tests/test_mem_scan.sh
git commit -m "feat: detección de stack + esqueleto de context-pack (mem-scan.sh)"
```

---

### Task 11: agentes de memoria + `scripts/mem-curate.sh`

**Files:**
- Create: `scripts/mem-curate.sh`
- Create: `agents/memory-orchestrator.md`
- Create: `agents/memory-builder.md`
- Create: `agents/memory-curator.md`
- Test: `tests/test_mem_curate.sh`
- Test: `tests/test_agents_frontmatter.sh`

**Interfaces:**
- Consumes: `scripts/mem-lock.sh` (Task 2), `scripts/mem-files.sh` (Task 3),
  `scripts/mem-stale.sh` (Task 4), `scripts/mem-manifest.sh gc` (Task 5), `scripts/mem-scan.sh`
  (Task 10), `skills/swarm-protocol/SKILL.md` (Task 8).
- Produces:
  ```
  mem-curate.sh resolve       # recalcula sha de cada finding [status:open] citado; si cambió -> [status:resolved] [resolved:ISO-date]
  mem-curate.sh prune --days N # elimina líneas resolved con más de N días
  mem-curate.sh gc            # delega en mem-manifest.sh gc --keep 10
  ```
  Los tres agentes (`memory-orchestrator`, `memory-builder`, `memory-curator`) son consumidos por
  `agents/orchestrator.md` (Task 12) vía `SendMessage`.

**Modelo:** `mem-curate.sh` → sonnet · los 3 cuerpos de prompt de agente → **opus** (son el
contrato del subsistema de memoria, envenenarlos envenena todo agente downstream que dependa de
memoria) · **Review:** cavecrew-reviewer para el script, `working-methods:grill-engineer` para los
3 prompts

- [ ] **Paso 1: escribir el test de `mem-curate.sh` (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
MEM_FILES="$PLUGIN_ROOT/scripts/mem-files.sh"
MEM_CURATE="$PLUGIN_ROOT/scripts/mem-curate.sh"

fixture="$(make_fixture)"
export SWARM_ROOT="$fixture/.swarm"
mkdir -p "$SWARM_ROOT"

"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 6 \
  --run adhoc --text "comentario cambiante" --fix "sin fix real" >/dev/null
"$MEM_FILES" write finding --agent architecture-auditor --tag ARCH --file src/App/Foo.php --line 7 \
  --run adhoc --text "otro comentario" --fix "sin cambios" >/dev/null

sed -i.bak '6s/.*/    \/\/ line 1 EDITADA/' "$fixture/src/App/Foo.php"
rm -f "$fixture/src/App/Foo.php.bak"

"$MEM_CURATE" resolve >/dev/null

findings_file="$SWARM_ROOT/findings/architecture-auditor.md"
line6_status="$(grep 'Foo.php:6' "$findings_file")"
line7_status="$(grep 'Foo.php:7' "$findings_file")"

assert_eq "0" "$(echo "$line6_status" | grep -q '\[status:resolved\]' && echo 0 || echo 1)" "changed cited line becomes resolved"
assert_eq "0" "$(echo "$line7_status" | grep -q '\[status:open\]' && echo 0 || echo 1)" "unchanged cited line stays open"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_mem_curate.sh` y hazlo ejecutable.

- [ ] **Paso 2: escribir el test de frontmatter de agentes (RED, cubre agentes de este task y de
  Task 12 vía glob dinámico)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

for f in "$PLUGIN_ROOT"/agents/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f")"

  assert_eq "0" "$(echo "$frontmatter" | grep -q '^name:' && echo 0 || echo 1)" "$name has name"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^description:' && echo 0 || echo 1)" "$name has description"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^model:' && echo 0 || echo 1)" "$name has model"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^tools:' && echo 0 || echo 1)" "$name has tools"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^maxTurns:' && echo 0 || echo 1)" "$name has maxTurns"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^memory:' && echo 0 || echo 1)" "$name has memory"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^skills:' && echo 0 || echo 1)" "$name has skills"
  assert_eq "0" "$(echo "$frontmatter" | grep -q 'SendMessage' && echo 0 || echo 1)" "$name tools include SendMessage"

  assert_eq "1" "$(echo "$frontmatter" | grep -q '^hooks:' && echo 0 || echo 1)" "$name frontmatter has no hooks:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q '^mcpServers:' && echo 0 || echo 1)" "$name frontmatter has no mcpServers:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q '^permissionMode:' && echo 0 || echo 1)" "$name frontmatter has no permissionMode:"
  assert_eq "1" "$(echo "$frontmatter" | grep -q 'Bash(' && echo 0 || echo 1)" "$name frontmatter has no Bash( subcommand syntax"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_agents_frontmatter.sh` y hazlo ejecutable.

- [ ] **Paso 3: ejecutar ambos para confirmar que fallan (RED)**

Run: `bash tests/test_mem_curate.sh`
Expected: FAIL — `scripts/mem-curate.sh: No such file or directory` (exit 127).

Run: `bash tests/test_agents_frontmatter.sh`
Expected: PASS trivialmente vacío si `agents/*.md` no matchea nada (glob sin ficheros) — para que
sea una RED real, este test debe ejecutarse DESPUÉS de escribir los 3 ficheros de agente del Paso
4 y ANTES de que su contenido sea correcto; en la práctica, escribe primero el Paso 4 con
frontmatter deliberadamente incompleto (sin `skills:`) para ver el FAIL, luego corrígelo en el
Paso 5. Alternativa más simple y la que se sigue aquí: procede directo a implementar el frontmatter
completo en el Paso 4 (los tres agentes nuevos) y confirma GREEN en el Paso 5 — el valor de este
test es de regresión permanente (protege contra un futuro agente mal formado), no exige un ciclo
RED artificial sobre frontmatter ya completo.

- [ ] **Paso 4: implementar `scripts/mem-curate.sh`**

```bash
#!/usr/bin/env bash
# scripts/mem-curate.sh — ciclo de vida de findings + GC de runs (spec §10)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_SCRIPT="$SCRIPT_DIR/mem-lock.sh"
MANIFEST_SCRIPT="$SCRIPT_DIR/mem-manifest.sh"
SWARM_ROOT="${SWARM_ROOT:-$PWD/.swarm}"
REPO_ROOT="$(dirname "$SWARM_ROOT")"

_with_lock() {
  "$LOCK_SCRIPT" acquire || return 1
  trap '"$LOCK_SCRIPT" release' EXIT INT TERM
  "$@"
  local rc=$?
  "$LOCK_SCRIPT" release
  trap - EXIT INT TERM
  return $rc
}

_sha8_of_line() {
  local file="$1" line="$2"
  local target="$REPO_ROOT/$file"
  if [ ! -f "$target" ]; then
    echo "00000000"
    return
  fi
  local content
  content="$(sed -n "${line}p" "$target" 2>/dev/null)"
  if [ -z "$content" ]; then
    echo "00000000"
    return
  fi
  printf '%s' "$content" | shasum -a 1 | cut -c1-8
}

_resolve_one_file() {
  local f="$1"
  [ -f "$f" ] || return 0
  local tmp today
  tmp="$(mktemp "${f}.XXXXXX")"
  today="$(date -u +"%Y-%m-%d")"
  while IFS= read -r line; do
    case "$line" in
      '- [key:'*'[status:open]'*)
        local file_line cited_file cited_line old_sha new_sha
        file_line="$(echo "$line" | sed -n 's/.*\] \[sha:[0-9a-f]*\] \[status:open\] \[run:[^]]*\] .* · \([^ ]*\) ·.*/\1/p')"
        cited_file="${file_line%%:*}"
        cited_line="${file_line##*:}"
        old_sha="$(echo "$line" | sed -n 's/.*\[sha:\([0-9a-f]*\)\].*/\1/p')"
        if [ -n "$cited_file" ] && [ -n "$cited_line" ]; then
          new_sha="$(_sha8_of_line "$cited_file" "$cited_line")"
        else
          new_sha="$old_sha"
        fi
        if [ "$old_sha" != "$new_sha" ]; then
          echo "$line" | sed "s/\[status:open\]/[status:resolved] [resolved:${today}]/" >> "$tmp"
        else
          echo "$line" >> "$tmp"
        fi
        ;;
      *)
        echo "$line" >> "$tmp"
        ;;
    esac
  done < "$f"
  mv "$tmp" "$f"
  return 0
}

_resolve() {
  local dir="$SWARM_ROOT/findings"
  [ -d "$dir" ] || return 0
  local f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    _resolve_one_file "$f"
  done
  echo "resolved"
  return 0
}

_prune_one_file() {
  local f="$1" cutoff_epoch="$2"
  [ -f "$f" ] || return 0
  local tmp
  tmp="$(mktemp "${f}.XXXXXX")"
  while IFS= read -r line; do
    case "$line" in
      '- [key:'*'[status:resolved]'*'[resolved:'*)
        local resolved_date resolved_epoch
        resolved_date="$(echo "$line" | sed -n 's/.*\[resolved:\([0-9-]*\)\].*/\1/p')"
        resolved_epoch="$(date -j -f "%Y-%m-%d" "$resolved_date" +%s 2>/dev/null || date -d "$resolved_date" +%s 2>/dev/null || echo 0)"
        if [ "$resolved_epoch" -gt 0 ] && [ "$resolved_epoch" -lt "$cutoff_epoch" ]; then
          :
        else
          echo "$line" >> "$tmp"
        fi
        ;;
      *)
        echo "$line" >> "$tmp"
        ;;
    esac
  done < "$f"
  mv "$tmp" "$f"
  return 0
}

_prune() {
  local days=30
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) days="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  local dir="$SWARM_ROOT/findings"
  [ -d "$dir" ] || return 0
  local now cutoff_epoch
  now="$(date +%s)"
  cutoff_epoch=$((now - days * 86400))
  local f
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    _prune_one_file "$f" "$cutoff_epoch"
  done
  echo "pruned"
  return 0
}

cmd_gc() {
  "$MANIFEST_SCRIPT" gc --keep 10
}

case "${1:-}" in
  resolve) shift; _with_lock _resolve "$@" ;;
  prune) shift; _with_lock _prune "$@" ;;
  gc) shift; cmd_gc "$@" ;;
  *)
    echo "usage: mem-curate.sh {resolve|prune --days N|gc}" >&2
    exit 64
    ;;
esac
```

Guarda lo anterior en `scripts/mem-curate.sh` y hazlo ejecutable: `chmod +x scripts/mem-curate.sh`.

- [ ] **Paso 5: implementar `agents/memory-orchestrator.md`**

```markdown
---
name: memory-orchestrator
description: Use when a swarm agent needs to read, write, build, or curate .swarm/ memory — the single gate to the memory subsystem (files backend + best-effort claude-mem). Exactly one instance per run.
model: haiku
tools: Read, Grep, Bash, SendMessage, mcp__plugin_claude-mem_mcp-search__*
maxTurns: 12
memory: project
skills: [swarm-protocol]
---

# memory-orchestrator

Eres la ÚNICA puerta al subsistema de memoria (spec §4.2, §4.4, §4.5). La raíz te lanza NOMBRADO
una vez por run — nunca hay una segunda instancia viva en el mismo run; toda hoja que necesite
memoria te manda un `SendMessage` a TI (resume tu contexto), nunca relanza otra copia.

## Operaciones (`query | write | build | curate`)

Recibes en el prompt una de estas cuatro operaciones, con `RUN=<run-id o adhoc>`.

### `query <texto>`
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" query "<texto>" --scope all
```
Si `memory.json` tiene `claude-mem` en `policy.read`, intenta también
`mcp__plugin_claude-mem_mcp-search__memory_search` con el mismo texto — envuelto en best-effort: si
el MCP falla o no responde, añade una línea de warning y sigue solo con `files`. Fusiona ambas
fuentes, responde en ≤5 líneas citando la fuente (`files` o `claude-mem`) de cada resultado.

### `write finding|decision|mailbox ...`
Reenvía los argumentos literalmente a `mem-files.sh write <tipo> ...` (ver cheat-sheet en
`skills/swarm-protocol/SKILL.md`). El script ya dedup y ya bloquea con `mem-lock.sh` — tú no
añades lógica encima, solo despachas.

**Espejo de mailbox obligatorio:** cuando reenvías un `SendMessage` peer-to-peer entre dos hojas
(no una escritura explícita de `write mailbox`), TÚ escribes además la copia en el buzón del
destinatario:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-files.sh" write mailbox \
  --to <destinatario> --from <remitente> --run "$RUN" --text "<mensaje>"
```
Así el orquestador de dominio conserva visibilidad y una hoja lanzada tarde lee su buzón al
arrancar (spec §5).

### `build`
Antes de reconstruir, comprueba si hace falta:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" check
```
- exit 0 (fresh) → no hagas nada, responde `OK` con evidencia y termina — la reconstrucción NO se
  invoca si el pack ya está fresco (spec §4.4, smoke test 2).
- exit 1 (stale) o exit 2 (sin index) → `SendMessage(memory-builder, "build run:$RUN")` y espera su
  `DONE`/`BLOCKED`.

### `curate`
`SendMessage(memory-curator, "curate run:$RUN")` y espera su `DONE`.

## Política y health-gating

Lee `.swarm/memory.json` para saber qué backends aplican:
```bash
python3 -c "
import json
d = json.load(open('.swarm/memory.json'))
print(d['policy'])
for b in d['backends']:
    print(b['name'], b['type'], b.get('required'))
"
```
Un backend `required: false` (p. ej. `claude-mem`) que falle health nunca bloquea la operación —
añade una línea de warning al `summary.md` del run vía
`mem-manifest.sh summary --run "$RUN" --line "..."` y continúa solo con `files`. El backend
`files` es `required: true` — si su `health` falla, tu veredicto es `BLOCKED backend files caído`.

## Regla de instancia única

No lances una segunda copia de ti mismo. Si recibes un `SendMessage` mientras estás ocupado,
respóndelo en tu turno actual o en cuanto liberes turno — nunca le digas al remitente "lanza otra
instancia".

## Salida

```
OK
evidence: files=N cmds=M turns=k/12
```
(o `BLOCKED <motivo>` si el backend `files` falla health).
```

Guarda lo anterior en `agents/memory-orchestrator.md`.

- [ ] **Paso 6: implementar `agents/memory-builder.md`**

```markdown
---
name: memory-builder
description: Use when memory-orchestrator needs the context-pack rebuilt because mem-stale.sh reports it missing or stale — scans the repo once and writes .swarm/context-pack.md.
model: sonnet
tools: Read, Grep, Glob, Bash, SendMessage
maxTurns: 20
memory: project
skills: [swarm-protocol]
---

# memory-builder

Construyes/refrescas `context-pack.md` UNA vez por run cuando hace falta — nunca por iniciativa
propia, siempre porque `memory-orchestrator` te lo pidió tras comprobar staleness (spec §4.4).

## Pasos

1. Comprueba staleness tú también (defensivo, evita trabajo si alguien te invocó sin comprobar):
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" check
   ```
   Si el resultado es "fresh" (exit 0), NO reconstruyas — responde `OK` con evidencia y termina
   (spec smoke test 2: query con pack presente responde sin invocar builder; esta early-exit es la
   mitad de esa garantía, la otra mitad vive en `memory-orchestrator`).

2. Si stale o sin index, escanea el repo:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-scan.sh" --root "$PWD" > /tmp/swarm-scan.$$
   ```

3. Enriquece ligeramente el esqueleto (no lo reescribas desde cero): si existen `CLAUDE.md` o
   `~/.claude/rules/` referenciados desde el repo, añade una sección `## Convenciones` con un
   resumen de ≤15 líneas (bullets, no prosa). El pack final debe quedarse en ≤200 líneas — si el
   escaneo + convenciones exceden eso, recorta el `## Tree` primero (es el que menos aporta por
   línea).

4. Consulta el backend histórico best-effort (nunca bloqueante):
   ```
   mcp__plugin_claude-mem_mcp-search__get_observations o memory_search sobre "<stack detectado>"
   ```
   Si falla o no hay MCP disponible, omite la sección — no es un `BLOCKED`.

5. Escribe el resultado final:
   ```bash
   mkdir -p .swarm
   mv /tmp/swarm-scan.$$ .swarm/context-pack.md
   ```

6. Sella el hash de staleness:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-stale.sh" seal
   ```

## Salida

Pack ya fresco (no reconstruido):
```
OK
evidence: files=1 cmds=1 turns=2/20
```

Pack reconstruido:
```
DONE
evidence: files=N cmds=M turns=k/20
```
```

Guarda lo anterior en `agents/memory-builder.md`.

- [ ] **Paso 7: implementar `agents/memory-curator.md`**

```markdown
---
name: memory-curator
description: Use when memory-orchestrator closes a run — resolves stale findings, prunes old ones, garbage-collects run/ history, and trims oversized agent memory files.
model: haiku
tools: Read, Edit, Bash, SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# memory-curator

Cierras el ciclo de vida de memoria al final de un run (spec §10). Puramente mecánico — no hay
juicio que ejercer aquí, por eso vas en haiku.

## Pasos

1. Resuelve hallazgos cuyo fichero:línea citado cambió de contenido:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-curate.sh" resolve
   ```

2. Poda hallazgos `resolved` con más de 30 días:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-curate.sh" prune --days 30
   ```

3. GC de runs — conserva los 10 más recientes, nunca `run/adhoc/`:
   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/mem-curate.sh" gc
   ```

4. Trimming de memoria nativa por agente: para cada `.claude/agent-memory/*/MEMORY.md` mayor de
   25KB, mueve las secciones más antiguas (bajo el primer `## ` que exceda el presupuesto, de
   arriba hacia abajo hasta bajar de 25KB) a un fichero hermano `MEMORY-archive.md` en el mismo
   directorio — usa `Edit` para el recorte quirúrgico, no reescribas el fichero entero si no hace
   falta.
   ```bash
   find .claude/agent-memory -name 'MEMORY.md' -size +25k 2>/dev/null
   ```

## Salida

```
DONE
evidence: files=N cmds=3 turns=k/10
```
```

Guarda lo anterior en `agents/memory-curator.md`.

- [ ] **Paso 8: ejecutar ambos tests, confirmar que pasan (GREEN)**

Run: `bash tests/test_mem_curate.sh`
Expected: PASS.

Run: `bash tests/test_agents_frontmatter.sh`
Expected: PASS (los 3 ficheros de agente cumplen el contrato de frontmatter).

- [ ] **Paso 9: commit**

```bash
git add scripts/mem-curate.sh agents/memory-orchestrator.md agents/memory-builder.md agents/memory-curator.md tests/test_mem_curate.sh tests/test_agents_frontmatter.sh
git commit -m "feat: subsistema de memoria — memory-orchestrator/builder/curator + mem-curate.sh"
```

---

### Task 12: `agents/orchestrator.md` + `commands/run.md`

**Files:**
- Create: `agents/orchestrator.md`
- Create: `commands/run.md`
- Test: `tests/test_commands.sh`

**Interfaces:**
- Consumes: `scripts/mem-manifest.sh open|register` (Task 5), `agents/memory-orchestrator.md`
  (Task 11) vía `SendMessage`.
- Produces: agente `swarm:orchestrator`, invocado por `/swarm:run <objetivo> [--tier=...]`.

**Modelo:** opus (contrato del punto de entrada raíz) · **Review:** `working-methods:grill-operator`

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

for f in "$PLUGIN_ROOT"/commands/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$f")"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^description:' && echo 0 || echo 1)" "$name has description"
  assert_eq "0" "$(echo "$frontmatter" | grep -q '^allowed-tools:' && echo 0 || echo 1)" "$name has allowed-tools"
done

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_commands.sh` y hazlo ejecutable. Este test ya cubre
`commands/init.md` (Task 9); su segunda mitad de valor llega cuando este task añade `run.md`.

- [ ] **Paso 2: ejecutar para confirmar el estado previo (ya debería pasar solo con `init.md`)**

Run: `bash tests/test_commands.sh`
Expected: PASS (con solo `init.md` presente) — este task añade `run.md`, que el mismo test debe
seguir validando tras el Paso 4 sin cambios en el test.

- [ ] **Paso 3: implementar `agents/orchestrator.md`**

```markdown
---
name: orchestrator
description: Use when the user asks for any non-trivial development work in this repo — root agent for the swarm plugin. Classifies tier, opens a run, launches memory-orchestrator, and (fase 1) has no other domains to dispatch to yet.
model: opus
tools: Agent, Read, Bash, SendMessage, AskUserQuestion
maxTurns: 30
memory: project
skills: [swarm-protocol]
---

# orchestrator (raíz)

Único punto de entrada del enjambre (`/swarm:run`). Hablas solo con orquestadores de dominio,
nunca con hojas directamente (spec §3.2 regla 1).

**Alcance de fase 1 (honesto, no aspiracional):** en esta fase del plugin el único dominio
disponible es `memory-orchestrator` (§4.2). Los dominios `discovery-orchestrator`,
`analysis-orchestrator`, `design-orchestrator`, `implementation-orchestrator`,
`delivery-orchestrator` y `requirements-orchestrator` son fases 1b/2-6 (spec §15) — TODAVÍA NO
EXISTEN. Si el objetivo del usuario requiere alguno de esos dominios, responde honestamente que el
enjambre aún no cubre esa fase y ofrece lo que SÍ puedes hacer con memoria (`query`/`write`/pack).

## 1. Clasificación de tier (spec §9.1)

- `direct`: objetivo trivial, un fichero, sin decisión arquitectónica → respondes tú misma, SIN
  abrir run ni lanzar `memory-orchestrator`.
- `light`: un solo dominio.
- `full`: multi-dominio o explícitamente crítico.

El usuario puede forzar el tier con `--tier=direct|light|full` en la invocación de `/swarm:run` —
si viene ese flag, úsalo tal cual, no reclasifiques.

## 2. Apertura de run (si no es `direct`)

```bash
RUN="$("${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" open --tier "$TIER")"
```

Lanza `memory-orchestrator` NOMBRADO exactamente `memory-orchestrator` (instancia única del run,
spec §4.5) en la misma tanda en que lances cualquier otra hoja/orquestador de dominio — el roster
de hermanos es un snapshot al inicio (spec §3.1).

Registra tu propio rol en el manifest:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mem-manifest.sh" register \
  --run "$RUN" --agent orchestrator --domain root --area "." --owner user
```

## 3. Política de pack (lazy, spec §9.1)

Nunca construyas el pack antes de clasificar el tier. `direct` nunca construye pack. Para
`light`/`full`, tras abrir el run, pide a `memory-orchestrator` que compruebe staleness:
```
SendMessage(memory-orchestrator, "build run:$RUN")
```
`memory-orchestrator` decide internamente si hace falta reconstruir (delega en `memory-builder`
solo si stale) — tú no llamas a `mem-stale.sh` directamente.

## 4. Cierre

Al terminar el trabajo del run:
```
SendMessage(memory-orchestrator, "curate run:$RUN")
```

## 5. Discovery (fase 2, no implementado aún)

Cuando exista `discovery-orchestrator`, tu rol será presentar su batch único de preguntas con
`AskUserQuestion` (multi-select, una sola tanda) — documentado aquí para que la interfaz no cambie
cuando se añada esa fase (spec §3.2 regla 7). En fase 1 esta sección es solo referencia.

## 6. Salida

```
OK
evidence: files=N cmds=M turns=k/30
```
o, si el objetivo pide un dominio que aún no existe:
```
BLOCKED dominio no implementado en fase 1 (<nombre-dominio>)
evidence: files=N cmds=M turns=k/30
```
```

Guarda lo anterior en `agents/orchestrator.md`.

- [ ] **Paso 4: implementar `commands/run.md`**

```markdown
---
description: Lanza el orquestador raíz del enjambre swarm sobre un objetivo, con tier opcional.
argument-hint: <objetivo> [--tier=direct|light|full]
allowed-tools: Agent, Read, Bash, SendMessage, AskUserQuestion
---

Invoca al agente `swarm:orchestrator` con el objetivo tal cual lo escribió el usuario:

$ARGUMENTS

Pásale el argumento completo sin reinterpretarlo — el propio `orchestrator` extrae el flag
`--tier=` si está presente y clasifica el resto como el objetivo.
```

Guarda lo anterior en `commands/run.md`.

- [ ] **Paso 5: ejecutar de nuevo, confirmar que sigue pasando (GREEN, cubriendo ya `run.md`)**

Run: `bash tests/test_commands.sh`
Expected: PASS.

Run también la suite de frontmatter de agentes, que ahora cubre `orchestrator.md` sin cambios en
el test:

Run: `bash tests/test_agents_frontmatter.sh`
Expected: PASS.

- [ ] **Paso 6: commit**

```bash
git add agents/orchestrator.md commands/run.md tests/test_commands.sh
git commit -m "feat: orchestrator raíz + /swarm:run — clasificación de tier y apertura de run"
```

---

### Task 13: Checklist de smoke tests (gate del owner, manual)

**Files:**
- Create: `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`

**Interfaces:** ninguna — este task no produce código, produce el documento que el owner ejecuta
a mano contra una sesión real de `claude`.

**Modelo:** sesión real del owner (no un agente) · **Review:** N/A — este task ES el gate.

- [ ] **Paso 1: escribir y commitear el checklist**

```markdown
# Checklist de smoke — Fase 1 núcleo (`swarm`)

Gate manual del owner. Ejecutar contra un repo fixture con:
`claude --plugin-dir /Users/davidgarciagordo/projects/multiagents`

Cada ítem lleva un campo **Evidencia:** para pegar la salida real — no marcar sin pegarla.

## 1. `/swarm:init`

```
/swarm:init
```
Evidencia:

## 2. `/swarm:run "audita memoria" --tier=light` — primera vez

Se espera: directorio de run creado bajo `.swarm/run/<uuid>/`, `context-pack.md` construido,
`summary.md` presente al cierre.
Evidencia:

## 3. `/swarm:run "audita memoria" --tier=light` — segunda vez, mismo repo sin cambios

Se espera: `memory-builder` NO reconstruye (staleness fresh) — valida de extremo a extremo el
smoke test 2 del spec (`query con pack presente responde sin invocar builder`).
Evidencia:

## 4. Visibilidad de hermanos + espejo de buzón

Lanza dos hojas de prueba nombradas en el mismo mensaje y haz que A mande `SendMessage` a B.
Anota si el roster de hermanos funcionó y si el espejo de mailbox también apareció en
`run/<id>/mailbox/B.md` (spec smoke tests 3 y 6, a nivel de ejecución real de agentes).
Evidencia:

## 5. Clasificación `direct`

```
/swarm:run "corrige un typo en el README"
```
Se espera: tier `direct`, la raíz responde ella misma, NINGÚN directorio de run nuevo creado bajo
`.swarm/run/` (spec smoke test 10).
Evidencia:

## Firma

- [ ] Owner: ________________  Fecha: ________________
```

Guarda lo anterior en `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md`.

- [ ] **Paso 2: commit**

```bash
git add docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 1 (gate manual del owner)"
```

---

## Ejecución

Tras guardar este plan, dos opciones:

1. **Subagent-Driven (recomendado)** — un subagente fresco por tarea, review entre tareas,
   iteración rápida. SUB-SKILL REQUERIDA: `superpowers:subagent-driven-development`.
2. **Ejecución inline** — ejecutar las tareas en esta misma sesión con checkpoints de revisión.
   SUB-SKILL REQUERIDA: `superpowers:executing-plans`.
