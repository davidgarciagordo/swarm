# Plan Fase 1b — Dominio de Requisitos (`requirements-orchestrator` + `env-checker`)

> **Para agentes:** SUB-SKILL REQUERIDA — usa `superpowers:subagent-driven-development`
> (recomendado) o `superpowers:executing-plans` para ejecutar este plan tarea a tarea. Los pasos
> usan sintaxis de checkbox (`- [ ]`) para seguimiento.

**Objetivo:** Construir el dominio "Requisitos" del plugin `swarm` — `requirements-orchestrator`,
`env-checker`, `scripts/req-check.sh`, `requirements.json` propio del plugin y el comando
`/swarm:doctor` — exactamente el alcance de spec §15 fase "1b". `dependency-auditor` y
`dependency-installer` son fase 5 (cuando exista el primer stack pack) y NO se tocan en este plan:
ni se construyen, ni se estuban, ni se mencionan en frontmatter alguno.

**Arquitectura:** `scripts/req-check.sh` es la herramienta determinista (spec §2 principio 4,
"tool determinista antes que modelo"): dado un `requirements.json`, comprueba presencia de tools
de OS (`command -v` vía `shutil.which`), best-effort de versión mínima, y presencia de ficheros de
proyecto — nunca falla duro, siempre imprime un informe JSON a stdout y sale 0/1 según haya
`required` ausente. `env-checker` es una hoja de una sola responsabilidad: invocar ese script y
traducir su JSON al contrato de evidencia (protocolo §4) — el modelo nunca reimplementa el
chequeo. `requirements-orchestrator` es el orquestador de dominio: NO preexiste `env-checker`
cuando lo necesita, así que lo LANZA con el tool `Agent` (nunca `SendMessage`, que solo alcanza
agentes ya vivos) — esta es exactamente la clase de bug real que rompió `memory-orchestrator` en
fase 1 (ver `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md` ítem 2), y este plan la
evita desde el diseño, no como parche posterior. `/swarm:doctor` invoca a
`swarm:requirements-orchestrator` de forma incondicional, siguiendo el mismo patrón que
`commands/run.md` ya aplica (invocación SIEMPRE, sin dejar que la sesión exterior conteste por su
cuenta).

**Tech Stack:** bash 3.2 compatible con macOS (sin arrays asociativos, sin `mapfile`), Python 3
stdlib puro (sólo dentro de `req-check.sh`, vía heredoc `python3 - ... <<'PYEOF'`, para parsear
JSON y comparar versiones — ningún hook nuevo), formato de agente/comando/skill de Claude Code ya
establecido en fase 1.

**Spec:** `docs/superpowers/specs/2026-09-01-swarm-design.md` (v2.1) — esta fase implementa
exactamente §15 fase "1b. Requisitos": `requirements-orchestrator` + `env-checker` (+
`req-check.sh`, `requirements.json` del propio plugin, `/swarm:doctor`); `dependency-auditor`/
`dependency-installer` quedan explícitamente para fase 5 junto al primer stack pack. Contrato
`requirements.json` en §7 "Roster completo → Requisitos".

## Global Constraints

- Mismas restricciones de plataforma ya probadas en fase 1: scripts bash 3.2-compatibles (sin
  arrays asociativos, sin `mapfile` — `/bin/bash` 3.2.57 por defecto en macOS); frontmatter de
  agente NUNCA lleva `hooks:`/`mcpServers:`/`permissionMode:`; `tools:` lista nombres de tool
  planos + `Agent(nombre,...)` con alcance + `SendMessage`, nunca sintaxis de restricción
  `Bash(cmd:*)` (la restricción real la impone `hooks/bash-guard.py` + `hooks/bash-allowlist.json`
  por `agent_type`); sin trailer de atribución en los commits.
- **Cualquier agente que lance hijos necesita `Agent(...)` en sus `tools` — verificado
  explícitamente para `requirements-orchestrator` (T3), no se repite el bug de
  `memory-orchestrator`.** `requirements-orchestrator` lanza `env-checker`, que NO preexiste:
  `Agent(env-checker)` va en su frontmatter Y el cuerpo del agente lo explica en prosa
  (§"Operación `check`" de T3) — la lección se aplica en los DOS sitios, no solo en el
  frontmatter, porque quien edite el fichero a mano después debe entender por qué esa línea no se
  puede quitar. Un test nuevo (`tests/test_requirements_orchestrator_spawns.sh`, T3) hace
  `grep -qF 'Agent(env-checker'` sobre la línea `tools:` del fichero — regresión mecánica para
  esta clase exacta de bug.
- Enrutado de modelo (regla del owner, establecida esta sesión): Fable/Opus decide y revisa;
  Sonnet ejecuta planes/scripts/agentes de spec ya cerrada; Haiku para lo trivial/mecánico. Cada
  tarea de este plan lleva línea `**Modelo:**`/`**Review:**`. Nada en este plan es lo bastante
  crítico-de-contrato como para exigir Opus (a diferencia de `swarm-protocol`/`orchestrator` en
  fase 1, que SÍ lo fueron): toda esta fase es ejecución mecánica de una sección de spec ya
  aprobada — scripts y cuerpos de agente sencillos van en **Sonnet** con review de
  **`caveman:cavecrew-reviewer`** (agente de review ligero ya existente en este repo).
- `hooks/bash-guard.py` NO hace matching por prefijo genérico salvo para entradas que empiezan por
  literalmente `scripts/mem` (caso especial `is_mem_script`, ver `hooks/bash-guard.py:91-94` y
  `:110-120`). Para cualquier otro prefijo, el match es por IGUALDAD EXACTA de la primera palabra
  del segmento (`first_raw == prefix`, `hooks/bash-guard.py:117`). Por eso las entradas nuevas de
  `hooks/bash-allowlist.json` para `swarm:requirements-orchestrator` y `swarm:env-checker` usan el
  nombre de fichero LITERAL `scripts/req-check.sh` — un prefijo suelto tipo `"scripts/req-"` NO
  matchearía nunca contra `hooks/bash-guard.py` tal y como está commiteado hoy (a diferencia de
  `scripts/mem-*`, que sí tiene ese caso especial). T3 añade un test de regresión explícito para
  esto (dos casos más en `tests/test_requirements_orchestrator_spawns.sh`, invocando
  `hooks/bash-guard.py` directamente igual que hace `tests/test_bash_guard.sh` ítem 7).
- Cada tarea corre solo su(s) propio(s) fichero(s) de test nuevo/modificado en el paso RED/GREEN
  (`bash tests/test_X.sh`), nunca la suite completa a mitad de plan — igual que fase 1. Nota de
  alcance: entre T1 (que añade `./commands/doctor.md` al manifest) y T4 (que crea ese fichero),
  `tests/run.sh` mostraría `tests/test_commands.sh` en FAIL de forma transitoria y esperada (el
  manifest referencia un comando que aún no existe en disco) — no es una regresión, es la propia
  guarda de `test_commands.sh` haciendo de RED para T4. La suite completa solo se corre entera al
  cierre de T4 en adelante.
- Commit tras CADA tarea individualmente: `git commit -m "<type>: <desc>"`
  (feat/test/chore/docs). Sin trailer de atribución.

## Estructura de ficheros (nuevos/modificados en esta fase)

```
requirements.json                          NUEVO — requisitos propios del plugin (T1)
.claude-plugin/plugin.json                 MODIFICADO — añade ./commands/doctor.md (T1)
scripts/
  req-check.sh                             NUEVO — verificación determinista (T2)
agents/
  requirements-orchestrator.md             NUEVO (T3)
  env-checker.md                           NUEVO (T3)
hooks/
  bash-allowlist.json                      MODIFICADO — 2 entradas nuevas (T3)
commands/
  doctor.md                                NUEVO (T4)
tests/
  test_requirements_json.sh                NUEVO (T1)
  test_req_check.sh                        NUEVO (T2)
  test_requirements_orchestrator_spawns.sh NUEVO (T3)
docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md   NUEVO (T5)
```

---

### Task 1: `requirements.json` (propio del plugin) + registro en `.claude-plugin/plugin.json`

**Files:**
- Create: `requirements.json`
- Modify: `.claude-plugin/plugin.json`
- Test: `tests/test_requirements_json.sh`

**Interfaces:**
- Produces: `requirements.json` en la raíz del plugin — mismo esquema del spec §7 (`os`/
  `project`/`libs`, cada item `{"tool"|"file"|"name", "min"?, "required", "install"?}`).
  Consumido por `scripts/req-check.sh` (T2, ruta por defecto) y por `env-checker` (T3, prompt de
  lanzamiento de `requirements-orchestrator`).
- Produces: `.claude-plugin/plugin.json` con `"./commands/doctor.md"` añadido al array
  `commands` — consumido por la carga del plugin y por `tests/test_commands.sh` (ya existente,
  glob dinámico) a partir de T4.

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
# tests/test_requirements_json.sh — requirements.json del plugin (T1, spec §7) + registro de
# /swarm:doctor en el manifest.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
assert set(['os', 'project', 'libs']) <= set(d.keys()), 'missing top-level keys'
assert isinstance(d['os'], list) and isinstance(d['project'], list) and isinstance(d['libs'], list)
tools = [i.get('tool') for i in d['os']]
for required_tool in ('git', 'python3', 'uuidgen'):
    assert required_tool in tools, 'missing os entry: ' + required_tool
    item = [i for i in d['os'] if i.get('tool') == required_tool][0]
    assert item.get('required') is True, required_tool + ' must be required: true'
for optional_tool in ('jq', 'gh', 'docker'):
    assert optional_tool in tools, 'missing os entry: ' + optional_tool
    item = [i for i in d['os'] if i.get('tool') == optional_tool][0]
    assert item.get('required') is False, optional_tool + ' must be required: false'
" "$PLUGIN_ROOT/requirements.json"
assert_eq "0" "$?" "requirements.json is valid JSON with os/project/libs and the expected entries"

python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if './commands/doctor.md' in d.get('commands', []) else 1)
" "$PLUGIN_ROOT/.claude-plugin/plugin.json"
assert_eq "0" "$?" "plugin.json commands array includes ./commands/doctor.md"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_requirements_json.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_requirements_json.sh`
Expected: FAIL — `requirements.json` no existe todavía (`FileNotFoundError`) y `plugin.json` no
trae `./commands/doctor.md`.

- [ ] **Paso 3: crear `requirements.json`**

```json
{
  "os": [
    { "tool": "git", "required": true, "install": { "brew": "git", "apt": "git" } },
    { "tool": "python3", "required": true, "install": { "brew": "python3", "apt": "python3" } },
    { "tool": "uuidgen", "required": true, "install": { "apt": "uuid-runtime" } },
    { "tool": "jq", "required": false, "install": { "brew": "jq", "apt": "jq" } },
    { "tool": "gh", "required": false, "install": { "brew": "gh", "apt": "gh" } },
    { "tool": "docker", "required": false, "install": { "brew": "docker", "apt": "docker.io" } }
  ],
  "project": [],
  "libs": []
}
```

Guarda lo anterior en `requirements.json` (raíz del plugin, junto a `.claude-plugin/`). `git`,
`python3` y `uuidgen` son `required: true` porque `orchestrator`/hooks los usan de verdad
(`git rev-parse` en varios agentes, hooks en `python3` puro, `uuidgen` en
`scripts/mem-manifest.sh open`). `jq`, `gh`, `docker` van `required: false`: el plugin no los usa
todavía, pero son los optionals de ejemplo que el propio spec §7 nombra como comúnmente útiles a
comprobar. `project` y `libs` quedan vacíos — el plugin no depende de ningún fichero de proyecto
concreto ni de ninguna librería (eso es responsabilidad de cada `skills/pack-<stack>/
requirements.json`, fase 5).

- [ ] **Paso 4: registrar `/swarm:doctor` en el manifest**

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
  "commands": ["./commands/init.md", "./commands/run.md", "./commands/doctor.md"]
}
```

Reemplaza el contenido de `.claude-plugin/plugin.json` por lo anterior (único cambio: el tercer
elemento del array `commands`). `commands/doctor.md` todavía no existe en disco — eso es
esperado, lo crea T4; hasta entonces `tests/test_commands.sh` (ya existente) fallará en su
comprobación "manifest command $rel exists" si se corre la suite completa (ver nota de alcance en
Global Constraints).

- [ ] **Paso 5: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_requirements_json.sh`
Expected: PASS.

- [ ] **Paso 6: commit**

```bash
git add requirements.json .claude-plugin/plugin.json tests/test_requirements_json.sh
git commit -m "feat: requirements.json del plugin + registro de /swarm:doctor en el manifest"
```

---

### Task 2: `scripts/req-check.sh`

**Files:**
- Create: `scripts/req-check.sh`
- Test: `tests/test_req_check.sh`

**Interfaces:**
- Consumes: `requirements.json` (Task 1, o cualquier fichero con el mismo esquema pasado con
  `--file`).
- Produces:
  ```
  req-check.sh [--file PATH] [--root DIR]
  # PATH por defecto: requirements.json en la raíz del plugin (dirname de scripts/).
  # DIR por defecto: $PWD (usado para resolver los "file" de la sección "project").
  # stdout: {"ok": true|false, "missing_required": [{"tool":"...", "hint":"..."}],
  #          "missing_optional": [...], "checked": N}
  # exit 0 si ok (ningún required ausente); exit 1 si algún required falta;
  # exit 64 en uso incorrecto (fichero no encontrado, --file/--root sin valor).
  ```
  Consumido por `env-checker` (Task 3).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
# tests/test_req_check.sh — scripts/req-check.sh (Task 2, spec §7)
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
REQ_CHECK="$PLUGIN_ROOT/scripts/req-check.sh"

fixture="$(make_fixture)"

# 1. tool siempre presente, required -> ok:true, exit 0
cat > "$fixture/req-ok.json" <<'JSONEOF'
{ "os": [ {"tool":"ls","required":true} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-ok.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "always-present required tool -> exit 0"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": true' && echo 0 || echo 1)" "ok:true in report"

# 2. tool inventada, required -> ok:false, exit 1, hint presente
cat > "$fixture/req-missing-required.json" <<'JSONEOF'
{ "os": [ {"tool":"swarm-fake-tool-zzz","required":true,"install":{"brew":"swarm-fake","apt":"swarm-fake"}} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-missing-required.json" --root "$fixture")"
rc=$?
assert_eq "1" "$rc" "missing required tool -> exit 1"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": false' && echo 0 || echo 1)" "ok:false in report"
assert_eq "0" "$(echo "$out" | grep -q 'swarm-fake-tool-zzz' && echo 0 || echo 1)" "missing tool named in report"
assert_eq "0" "$(echo "$out" | grep -q 'missing_required' && echo 0 || echo 1)" "missing_required key present"

# 3. tool inventada, NOT required -> ok:true, aparece en missing_optional
cat > "$fixture/req-missing-optional.json" <<'JSONEOF'
{ "os": [ {"tool":"swarm-fake-tool-yyy","required":false} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-missing-optional.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "missing optional tool -> still exit 0"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": true' && echo 0 || echo 1)" "ok:true when only optional missing"
assert_eq "0" "$(echo "$out" | grep -q 'missing_optional' && echo 0 || echo 1)" "missing_optional key present"
assert_eq "0" "$(echo "$out" | grep -q 'swarm-fake-tool-yyy' && echo 0 || echo 1)" "optional missing tool named"

# 4. project file presente/ausente, con --root
cat > "$fixture/req-project.json" <<'JSONEOF'
{ "os": [], "project": [ {"file":"composer.json","required":true}, {"file":"nope-does-not-exist.txt","required":false} ], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-project.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "present required project file passes; absent one is only optional"
assert_eq "0" "$(echo "$out" | grep -q 'nope-does-not-exist.txt' && echo 0 || echo 1)" "absent optional project file listed in report"

# 5. min version por debajo de lo instalado -> ok:false, exit 1 (python3 siempre presente aqui)
cat > "$fixture/req-version-fail.json" <<'JSONEOF'
{ "os": [ {"tool":"python3","required":true,"min":"99.0"} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-version-fail.json" --root "$fixture")"
rc=$?
assert_eq "1" "$rc" "python3 present but below an inflated min -> exit 1"
assert_eq "0" "$(echo "$out" | grep -q '\"ok\": false' && echo 0 || echo 1)" "ok:false when version below min"
assert_eq "0" "$(echo "$out" | grep -q 'python3' && echo 0 || echo 1)" "python3 named in missing_required for version failure"

# 6. min version trivial -> ok:true
cat > "$fixture/req-version-ok.json" <<'JSONEOF'
{ "os": [ {"tool":"python3","required":true,"min":"1.0"} ], "project": [], "libs": [] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-version-ok.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "python3 present and above a trivial min -> exit 0"

# 7. libs: stub que nunca falla, siempre "unknown" en missing_optional
cat > "$fixture/req-libs.json" <<'JSONEOF'
{ "os": [], "project": [], "libs": [ {"name":"phpstan/phpstan","manager":"composer","min":"2.1","required":false} ] }
JSONEOF
out="$("$REQ_CHECK" --file "$fixture/req-libs.json" --root "$fixture")"
rc=$?
assert_eq "0" "$rc" "libs entries never fail (no pack yet, fase 5)"
assert_eq "0" "$(echo "$out" | grep -q 'phpstan/phpstan' && echo 0 || echo 1)" "libs entry named as unknown"

# 8. fichero de requirements inexistente -> exit 64 (uso incorrecto)
"$REQ_CHECK" --file "$fixture/does-not-exist.json" >/dev/null 2>&1
assert_eq "64" "$?" "missing requirements file -> exit 64"

# 9. --file sin valor no revienta bajo set -u, sale con exit no-cero limpio
"$REQ_CHECK" --file >/dev/null 2>&1
file_flag_exit=$?
assert_eq "0" "$([ "$file_flag_exit" -ne 0 ] && echo 0 || echo 1)" "--file with no value exits non-zero cleanly"

# 10. default --file (requirements.json del propio plugin, Task 1) produce JSON bien formado
out="$("$REQ_CHECK" --root "$fixture")"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert set(['ok', 'missing_required', 'missing_optional', 'checked']) <= set(d.keys())
" "$out"
assert_eq "0" "$?" "default --file (plugin's own requirements.json) produces well-shaped JSON"

rm -rf "$fixture"
if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_req_check.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_req_check.sh`
Expected: FAIL — `scripts/req-check.sh: No such file or directory` (exit 127).

- [ ] **Paso 3: implementar `scripts/req-check.sh`**

```bash
#!/usr/bin/env bash
# scripts/req-check.sh — verificación determinista de requirements.json (env-checker, spec §7)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FILE="$PLUGIN_ROOT/requirements.json"
ROOT="$PWD"

while [ $# -gt 0 ]; do
  case "$1" in
    --file)
      [ $# -ge 2 ] || { echo "req-check.sh: --file requires a value" >&2; exit 64; }
      FILE="$2"; shift 2 ;;
    --root)
      [ $# -ge 2 ] || { echo "req-check.sh: --root requires a value" >&2; exit 64; }
      ROOT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ ! -f "$FILE" ]; then
  echo "req-check.sh: requirements file not found: $FILE" >&2
  exit 64
fi

UNAME="$(uname -s 2>/dev/null || echo unknown)"

python3 - "$FILE" "$ROOT" "$UNAME" <<'PYEOF'
import json
import os
import re
import shutil
import subprocess
import sys

req_file, root, uname = sys.argv[1], sys.argv[2], sys.argv[3]

with open(req_file) as fh:
    data = json.load(fh)

checked = 0
missing_required = []
missing_optional = []


def install_hint(item):
    install = item.get("install") or {}
    brew = install.get("brew")
    apt = install.get("apt")
    if uname == "Darwin" and brew:
        return "brew install %s" % brew
    if uname != "Darwin" and apt:
        return "apt install %s" % apt
    parts = []
    if brew:
        parts.append("brew install %s" % brew)
    if apt:
        parts.append("apt install %s" % apt)
    if parts:
        return " / ".join(parts)
    return "sin hint de instalacion en requirements.json"


def version_tuple(text):
    m = re.search(r"(\d+)\.(\d+)(?:\.(\d+))?", text or "")
    if not m:
        return None
    return tuple(int(g) if g else 0 for g in m.groups())


def check_os_item(item):
    global checked
    tool = item.get("tool")
    required = bool(item.get("required"))
    checked += 1
    if shutil.which(tool) is None:
        return required, tool, install_hint(item)
    min_version = item.get("min")
    if min_version:
        # Best-effort: una tool sin flag de version fiable, o una salida que no
        # podemos parsear, se trata como presente-y-version-desconocida — nunca
        # es un fallo duro (YAGNI: no se construye un parser de versiones robusto).
        try:
            out = subprocess.run(
                [tool, "--version"], capture_output=True, text=True, timeout=5
            )
            found = version_tuple(out.stdout) or version_tuple(out.stderr)
            wanted = version_tuple(min_version)
            if found and wanted and found < wanted:
                return required, tool, "version %s < min %s" % (
                    ".".join(str(part) for part in found), min_version,
                )
        except Exception:
            pass
    return None


for item in data.get("os", []):
    result = check_os_item(item)
    if result:
        required, tool, hint = result
        entry = {"tool": tool, "hint": hint}
        (missing_required if required else missing_optional).append(entry)

for item in data.get("project", []):
    checked += 1
    path = item.get("file")
    required = bool(item.get("required"))
    if not os.path.isfile(os.path.join(root, path)):
        entry = {"tool": path, "hint": "fichero de proyecto ausente"}
        (missing_required if required else missing_optional).append(entry)

# libs: fase 1b no tiene stack pack todavia, asi que nada es verificable contra
# un gestor de paquetes real. Cada entrada se reporta como "unknown" y NUNCA
# hace fallar el chequeo — este stub es el limite YAGNI hasta la fase 5.
for item in data.get("libs", []):
    checked += 1
    missing_optional.append({
        "tool": item.get("name"),
        "hint": "unknown - requiere stack pack para verificar (fase 5)",
    })

ok = len(missing_required) == 0
report = {
    "ok": ok,
    "missing_required": missing_required,
    "missing_optional": missing_optional,
    "checked": checked,
}
print(json.dumps(report))
sys.exit(0 if ok else 1)
PYEOF
```

Guarda lo anterior en `scripts/req-check.sh` y hazlo ejecutable: `chmod +x scripts/req-check.sh`.

- [ ] **Paso 4: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_req_check.sh`
Expected: PASS.

- [ ] **Paso 5: commit**

```bash
git add scripts/req-check.sh tests/test_req_check.sh
git commit -m "feat: scripts/req-check.sh — verificacion determinista de requirements.json"
```

---

### Task 3: `agents/requirements-orchestrator.md` + `agents/env-checker.md`

**Files:**
- Create: `agents/requirements-orchestrator.md`
- Create: `agents/env-checker.md`
- Modify: `hooks/bash-allowlist.json`
- Test: `tests/test_requirements_orchestrator_spawns.sh`

**Interfaces:**
- Consumes: `scripts/req-check.sh` (Task 2), `requirements.json` (Task 1),
  `skills/swarm-protocol/SKILL.md` (contrato universal ya existente).
- Produces: dos agentes de plugin, `swarm:requirements-orchestrator` (domain-orchestrator, spawn
  vía `Agent`/`SendMessage`, consumido por `commands/doctor.md` en Task 4) y `swarm:env-checker`
  (leaf, spawn exclusivo vía `Agent(env-checker)` desde `requirements-orchestrator` — nunca
  preexiste).
- Nota de cobertura: `tests/test_agents_frontmatter.sh` (ya existente, glob dinámico sobre
  `agents/*.md`) cubre automáticamente los dos ficheros nuevos sin cambios — se confirma en el
  Paso 4 de este task, no hace falta tocar ese fichero.

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: escribir el test (RED)**

```bash
#!/usr/bin/env bash
# tests/test_requirements_orchestrator_spawns.sh — regresion para la clase exacta de bug real
# encontrada en fase 1: memory-orchestrator se envio sin `Agent` en su frontmatter, dejando
# memory-builder/memory-curator estructuralmente inalcanzables (SendMessage solo llega a agentes
# YA vivos). requirements-orchestrator lanza env-checker, que TAMPOCO preexiste: su frontmatter
# tiene que declarar Agent(env-checker...) o el spawn nace muerto.
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib.sh"
PLUGIN_ROOT="$(cd "$DIR/.." && pwd)"
AGENT_FILE="$PLUGIN_ROOT/agents/requirements-orchestrator.md"
ENV_CHECKER_FILE="$PLUGIN_ROOT/agents/env-checker.md"

assert_eq "0" "$([ -f "$AGENT_FILE" ] && echo 0 || echo 1)" "agents/requirements-orchestrator.md exists"
assert_eq "0" "$([ -f "$ENV_CHECKER_FILE" ] && echo 0 || echo 1)" "agents/env-checker.md exists"

frontmatter="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$AGENT_FILE")"
tools_line="$(echo "$frontmatter" | grep '^tools:')"

assert_eq "0" "$(echo "$tools_line" | grep -qF 'Agent(env-checker' && echo 0 || echo 1)" "tools: declares Agent(env-checker...) -- the spawn is otherwise dead on arrival (phase 1 bug class)"
assert_eq "0" "$(echo "$tools_line" | grep -qF 'SendMessage' && echo 0 || echo 1)" "tools: also includes SendMessage"

# La leccion tiene que estar TAMBIEN en la prosa del cuerpo, no solo en el frontmatter -- quien
# edite este fichero a mano despues no debe poder quitar el Agent sin verlo documentado ahi mismo.
body="$(awk '/^---$/{n++; next} n>=2{print}' "$AGENT_FILE")"
assert_eq "0" "$(echo "$body" | grep -qF 'no preexiste' && echo 0 || echo 1)" "body explicitly documents that env-checker does not preexist"
assert_eq "0" "$(echo "$body" | grep -qF 'Agent' && echo 0 || echo 1)" "body prose mentions the Agent tool explicitly, not just the frontmatter"

# Regresion de allowlist: hooks/bash-guard.py matchea entradas NO prefijadas por "scripts/mem" por
# IGUALDAD EXACTA de la primera palabra del segmento (ver hooks/bash-guard.py:97-121) -- una
# entrada suelta "scripts/req-" nunca matchearia. Confirma que las entradas reales anadidas usan
# el nombre de fichero literal "scripts/req-check.sh" y que ambos agentes pueden invocarlo.
HOOK="$PLUGIN_ROOT/hooks/bash-guard.py"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:env-checker", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh --file /x/requirements.json"}}
EOF
)"
assert_eq "" "$out" "env-checker can run scripts/req-check.sh via CLAUDE_PLUGIN_ROOT prefix"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:requirements-orchestrator", "tool_name": "Bash", "tool_input": {"command": "${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh --file /x/requirements.json"}}
EOF
)"
assert_eq "" "$out" "requirements-orchestrator can run scripts/req-check.sh via CLAUDE_PLUGIN_ROOT prefix"

out="$(python3 "$HOOK" <<'EOF'
{"agent_type": "swarm:env-checker", "tool_name": "Bash", "tool_input": {"command": "rm -rf /"}}
EOF
)"
assert_eq "0" "$(echo "$out" | grep -q '\"permissionDecision\": \"deny\"' && echo 0 || echo 1)" "env-checker cannot run rm -rf / (not in its allowlist)"

if [ "$TESTS_FAILED" -gt 0 ]; then exit 1; fi
exit 0
```

Guarda lo anterior en `tests/test_requirements_orchestrator_spawns.sh` y hazlo ejecutable.

- [ ] **Paso 2: ejecutar para confirmar que falla (RED)**

Run: `bash tests/test_requirements_orchestrator_spawns.sh`
Expected: FAIL — ni `agents/requirements-orchestrator.md` ni `agents/env-checker.md` existen
todavía, y las dos entradas del allowlist tampoco.

- [ ] **Paso 3: implementar `agents/requirements-orchestrator.md`**

```markdown
---
name: requirements-orchestrator
description: Use when the root or /swarm:doctor needs to verify the repo's OS/project requirements are satisfied before running the swarm — merges the plugin's own requirements.json with the active stack pack's (if any), spawns env-checker, and reports BLOCKED with the exact missing tool + install hint, or OK.
model: haiku
tools: Read, Grep, Bash, Agent(env-checker), SendMessage
maxTurns: 10
memory: project
skills: [swarm-protocol]
---

# requirements-orchestrator

Dominio de requisitos del enjambre (spec §7 "Requisitos", §15 fase 1b). Verificas que el repo
target cumple los requisitos de OS/proyecto del propio plugin ANTES de que el resto del enjambre
haga ningún trabajo. En esta fase (1b) tu única hoja es `env-checker`; `dependency-auditor` y
`dependency-installer` son fase 5 (primer stack pack) — NO existen todavía, ver "Operación
`install`" más abajo.

## Contexto de arranque (siempre, antes de la primera operación)

1. `RUN`: si tu prompt de lanzamiento trae `run-id: <uuid>`, ese es tu `RUN` (te lanzó la raíz
   dentro de un run real). Si no lo trae —caso normal en fase 1b, `/swarm:doctor` te lanza
   directo, sin abrir run— usa `RUN=adhoc` (protocolo §2). `swarm-root:` es la ruta absoluta de
   `.swarm/`; úsala como prefijo `SWARM_ROOT=<esa ruta>` si tu cwd no fuera la raíz del repo.
   `operation:` es lo que ejecutas en tu turno 1 — en fase 1b, siempre `check`.
2. Lee tu buzón (protocolo §1.3):
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/requirements-orchestrator.md" 2>/dev/null
   ```
3. Lee el `requirements.json` del propio plugin con la tool `Read` (esto cuenta para tu
   `files=` de evidencia — no cierres nunca con `OK`/`files=0`):
   ```
   Read: ${CLAUDE_PLUGIN_ROOT}/requirements.json
   ```

## Fusión de `requirements.json` (documentación de futuro — no hay pack todavía)

Tu fuente en fase 1b es SIEMPRE `${CLAUDE_PLUGIN_ROOT}/requirements.json` (el propio plugin,
Task 1 de este plan) — no hay ningún `skills/pack-<stack>/requirements.json` que fusionar todavía
(el primer pack, `php-ddd-symfony8`, es fase 5). Cuando exista un pack activo, la fusión será:
mismos tres arrays top-level (`os`/`project`/`libs`), concatenados; si una entrada del pack y una
del plugin comparten la misma clave de identidad (`tool` para `os`, `file` para `project`, `name`
para `libs`), la entrada del PACK gana (se queda esa, se descarta la del plugin) — así un pack
puede subir el `min` de una tool que el plugin ya declara, o marcar `required` una lib que el
plugin no conocía. Esto es prosa de contrato para cuando exista fase 5: NO implementes lógica de
fusión ahora, no hay segundo fichero que leer ni pack activo que detectar.

## Operación `check` (única implementada en fase 1b)

1. Lanza `env-checker` NOMBRADO exactamente `env-checker` (convención §2bis del skill
   `swarm-protocol`) con el tool `Agent` — **`env-checker` NO preexiste, nunca lo alcanzas con
   `SendMessage`**. Esta es exactamente la causa del bug real de fase 1: `memory-orchestrator`
   intentaba `SendMessage(memory-builder, ...)` para reconstruir el pack, pero su frontmatter
   nunca tenía el tool `Agent` — solo podía `SendMessage` a agentes YA vivos, y
   `memory-builder`/`memory-curator` nunca se lanzan solos (ver
   `docs/superpowers/plans/2026-09-01-phase1-smoke-checklist.md` ítem 2). Tu frontmatter YA
   declara `Agent(env-checker)` — si alguna vez editas este fichero, esa es la línea que más
   importa de todo el documento; quitarla deja el spawn muerto en llegada sin que ningún test de
   humo lo note hasta ejecutar el flujo real.
   ```
   Agent(subagent_type: "swarm:env-checker", name: "env-checker", prompt: <cabecera abajo>)
   ```
   Prompt del spawn, tres líneas literales (protocolo §2bis / `agents/orchestrator.md` §2.2):
   ```
   run-id: <tu RUN, o literal "adhoc" si tú mismo estás en adhoc>
   swarm-root: <tu swarm-root>
   operation: check --file ${CLAUDE_PLUGIN_ROOT}/requirements.json
   ```
2. Espera su salida (`OK` o `BLOCKED <tool>`). NO reinterpretes su JSON ni repitas el chequeo tú
   mismo — `env-checker` es la única hoja que toca `req-check.sh`; tú solo propagas.
3. Propagación:
   - Su `OK` → tu `OK`.
   - Su `BLOCKED <tool>` → tu `BLOCKED <tool>` LITERAL, con el mismo hallazgo/hint que él trajo
     (no lo resumas, no lo reformules — quien lee tu veredicto necesita el comando de instalación
     exacto para poder actuar).

## Operación `install` (fuera de alcance en fase 1b — `BLOCKED` explícito)

`dependency-installer` no existe todavía (fase 5, primer stack pack). Solo autorizarías un
`install` con aprobación explícita del owner vía raíz — pero como la hoja mutante ni siquiera
existe, si tu prompt trae `operation: install`, o cualquier hoja/usuario te pide instalar algo,
tu veredicto es SIEMPRE:
```
BLOCKED dependency-installer no implementado aún (fase 5)
```
No inventes una instalación tú mismo (no tienes tools de mutación de paquetes), y no lo intentes
vía `env-checker` (es read-only por contrato — su único trabajo es leer, nunca escribir ni
instalar). Esto aplica incluso si el owner lo pide directamente vía raíz — la mutación de
dependencias es fase 5, sin excepción en fase 1b.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:requirements-orchestrator`: `scripts/req-check.sh`, `git status|log|diff|
show|rev-parse`, `ls`, `cat`, `head`, `tail`, `wc`, `grep`. Todo lo demás se DENIEGA, segmento a
segmento (mismas reglas que el resto del enjambre — ver `agents/memory-orchestrator.md`
"Disciplina de Bash" para el detalle completo de por qué `; echo $?` rompe un comando entero y
cómo funciona el prefijo `SWARM_ROOT=`). En la práctica casi no usas Bash directamente: el
chequeo real lo hace `env-checker` vía `req-check.sh`; tú solo lo lanzas y lees tu buzón.

## Salida

Formato de evidencia del protocolo §4 (la línea de `turns` cierra la línea, sin texto detrás):

```
OK
evidence: files=1 cmds=0 turns=3/10
```
o
```
BLOCKED git
evidence: files=1 cmds=0 turns=3/10
REQ · requirements.json:0 · falta git → brew install git
```
`OK` con `files=0` se rechaza siempre por el hook: la lectura de `requirements.json` en tu paso
de arranque ya cuenta, así que cuéntala.
```

Guarda lo anterior en `agents/requirements-orchestrator.md`.

- [ ] **Paso 4: implementar `agents/env-checker.md`**

```markdown
---
name: env-checker
description: Use when requirements-orchestrator needs the repo's OS/project requirements verified against requirements.json — runs the deterministic scripts/req-check.sh and formats its JSON report as the evidence contract. Never re-implements the check itself.
model: haiku
tools: Read, Bash, SendMessage
maxTurns: 6
memory: project
skills: [swarm-protocol]
---

# env-checker

Hoja determinista (spec §7 "Requisitos"). Tu única responsabilidad es correr
`scripts/req-check.sh` y traducir su JSON al contrato de evidencia — el chequeo en sí YA está
resuelto por el script, tú no reimplementas nada de lógica de versión/presencia (regla "tool
determinista antes que modelo", protocolo §5). El modelo es solo para leer el JSON e invocar el
comando correcto; nunca "revisas a ojo" lo que el script ya te dio.

## Arranque

1. `RUN`: de tu cabecera de lanzamiento (`run-id:` o `adhoc`), igual que cualquier hoja
   (protocolo §2).
2. Lee tu buzón:
   ```bash
   cat "$SWARM_ROOT/run/${RUN:-adhoc}/mailbox/env-checker.md" 2>/dev/null
   ```
3. Lee con la tool `Read` el fichero de requisitos que te pasaron en `operation:` (ver abajo) —
   esto cuenta para tu `files=` de evidencia además de lo que abra el propio script.

## Chequeo

Tu prompt de lanzamiento trae `operation: check --file <ruta>` — el `<ruta>` es SIEMPRE la que
`requirements-orchestrator` resolvió (fase 1b: `${CLAUDE_PLUGIN_ROOT}/requirements.json`; ver su
fichero para la lógica de fusión futura con packs). Corre:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/req-check.sh" --file "<ruta del prompt>"
```

Sin `--root`: `req-check.sh` por defecto usa `$PWD` para las comprobaciones de `project`, y tu
cwd ya es la raíz del repo target (igual que el resto del enjambre — nunca lo cambies tú).

Lee el JSON de stdout directamente de la salida del `Bash` — no hace falta invocar `python3` tú
mismo (el hook te lo denegaría igual, ver "Disciplina de Bash"). Tres campos que te importan:
`ok`, `missing_required` (lista de `{tool, hint}`), `missing_optional`.

## Formato del veredicto

- `ok: true` → tu línea 1 es `OK`.
- `ok: false` → tu línea 1 es `BLOCKED <primer tool de missing_required>` (el primero de la
  lista si hay varios — un solo `BLOCKED` por invocación; el resto queda como hallazgos
  adicionales, no en la línea 1).
- Un hallazgo por cada entrada de `missing_required` (nunca por `missing_optional` — eso no
  bloquea nada, spec §7):
  ```
  REQ · requirements.json:0 · falta <tool> → <hint>
  ```
  `requirements.json:0` porque el JSON de `req-check.sh` no trae número de línea del fichero
  fuente y no vale la pena parsearlo solo para eso — `0` es la convención del enjambre para "no
  aplica línea concreta"; nunca inventes un número que parezca una línea real.

## Disciplina de Bash (`hooks/bash-guard.py`)

Allowlist de `swarm:env-checker`: `scripts/req-check.sh`, `git status|log|diff|show|rev-parse`,
`ls`, `cat`, `head`, `tail`, `wc`, `grep`. Nada de `python3`, `jq`, `mkdir`, `echo` sueltos —
`req-check.sh` ya hace todo el trabajo (incluida su propia llamada interna a `python3`, que corre
DENTRO del script y no pasa por este hook, porque quien invoca `python3` ahí es el script, no tú
directamente). El prefijo `${CLAUDE_PLUGIN_ROOT}/` está permitido igual que en el resto del
enjambre.

## Salida

```
OK
evidence: files=1 cmds=1 turns=2/6
```
o
```
BLOCKED git
evidence: files=1 cmds=1 turns=2/6
REQ · requirements.json:0 · falta git → brew install git
```
`files=0` en un `OK` se rechaza siempre: la lectura del fichero de requisitos en tu paso de
arranque ya cuenta, así que cuéntala.
```

Guarda lo anterior en `agents/env-checker.md`.

- [ ] **Paso 5: añadir las dos entradas nuevas a `hooks/bash-allowlist.json`**

```json
{
  "default": [
    "git status", "git log", "git diff", "git show", "git rev-parse",
    "ls", "cat", "head", "tail", "wc", "grep", "find",
    "scripts/mem-", "scripts/mem-lock.sh"
  ],
  "agents": {
    "swarm:memory-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:memory-builder": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:memory-curator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep", "find",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "cd", "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/mem-", "scripts/mem-lock.sh"
    ],
    "swarm:requirements-orchestrator": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/req-check.sh"
    ],
    "swarm:env-checker": [
      "git status", "git log", "git diff", "git show", "git rev-parse",
      "ls", "cat", "head", "tail", "wc", "grep",
      "scripts/req-check.sh"
    ]
  }
}
```

Reemplaza el contenido de `hooks/bash-allowlist.json` por lo anterior. Nota deliberada: se usa el
nombre de fichero LITERAL `scripts/req-check.sh` (no un prefijo suelto `scripts/req-`) en las dos
entradas nuevas — `hooks/bash-guard.py` solo hace matching por prefijo fuzzy para entradas que
empiezan literalmente por `scripts/mem` (caso especial `is_mem_script`); cualquier otra entrada se
compara por igualdad EXACTA de la primera palabra del segmento (`hooks/bash-guard.py:97-121`). Un
`"scripts/req-"` suelto aquí nunca habría matcheado nada — el test de este task (Paso 1) lo
comprueba invocando el hook directamente.

- [ ] **Paso 6: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_requirements_orchestrator_spawns.sh`
Expected: PASS.

Confirma además (sin modificar el fichero, glob dinámico ya los cubre):

Run: `bash tests/test_agents_frontmatter.sh`
Expected: PASS — `agents/requirements-orchestrator.md` y `agents/env-checker.md` traen
`name`/`description`/`model`/`tools`/`maxTurns`/`memory`/`skills`, incluyen `SendMessage` en
`tools`, y no declaran `hooks:`/`mcpServers:`/`permissionMode:` ni sintaxis `Bash(`.

- [ ] **Paso 7: commit**

```bash
git add agents/requirements-orchestrator.md agents/env-checker.md hooks/bash-allowlist.json \
  tests/test_requirements_orchestrator_spawns.sh
git commit -m "feat: dominio de requisitos -- requirements-orchestrator + env-checker"
```

---

### Task 4: `commands/doctor.md`

**Files:**
- Create: `commands/doctor.md`

**Interfaces:**
- Consumes: `agents/requirements-orchestrator.md` (Task 3).
- Produces: comando `/swarm:doctor` — sin argumentos, invoca incondicionalmente a
  `swarm:requirements-orchestrator` en modo adhoc (`operation: check`).

**Modelo:** sonnet · **Review:** cavecrew-reviewer

- [ ] **Paso 1: confirmar el RED heredado de Task 1**

`tests/test_commands.sh` (ya existente, sin modificar — glob dinámico sobre `commands/*.md` +
comprobación de que cada comando del manifest existe en disco) ya falla desde que Task 1 añadió
`./commands/doctor.md` al manifest sin que el fichero existiera todavía.

Run: `bash tests/test_commands.sh`
Expected: FAIL — `"manifest command commands/doctor.md exists"` falla (el fichero no está en
disco).

- [ ] **Paso 2: implementar `commands/doctor.md`**

```markdown
---
description: Verifica los requisitos de entorno del repo (OS/proyecto) contra requirements.json — health-gate de dependencias del enjambre.
allowed-tools: Agent, Read, Bash, SendMessage
---

SIEMPRE invoca el tool `Agent` con `subagent_type: swarm:requirements-orchestrator`, `name:
"requirements-orchestrator"` y el siguiente `prompt`, EXACTAMENTE así, sin excepción — nunca
respondas tú mismo, nunca pidas aclaración antes de invocar: el propio
`requirements-orchestrator` decide si los requisitos están satisfechos y devuelve su propio
veredicto.

```
operation: check
```

`/swarm:doctor` no toma argumentos: cualquier texto que el usuario añada tras el comando se
ignora (el chequeo de requisitos no tiene parámetros). Como no viene de un run abierto por la
raíz, `requirements-orchestrator` se lanza sin `run-id:` en la cabecera — él mismo lo detecta y
opera en modo adhoc (protocolo §2), igual que cualquier hoja invocada suelta.
```

Guarda lo anterior en `commands/doctor.md`.

- [ ] **Paso 3: ejecutar de nuevo, confirmar que pasa (GREEN)**

Run: `bash tests/test_commands.sh`
Expected: PASS — `commands/doctor.md` existe en disco, trae `description` y `allowed-tools`, y el
comando declarado en el manifest ya resuelve.

- [ ] **Paso 4: correr la suite completa (cierre de las fases 1b de código)**

Run: `bash tests/run.sh`
Expected: PASS — todos los ficheros `tests/test_*.sh`, incluidos los cuatro nuevos de este plan
(`test_requirements_json.sh`, `test_req_check.sh`,
`test_requirements_orchestrator_spawns.sh`) y todos los heredados de fase 1.

- [ ] **Paso 5: commit**

```bash
git add commands/doctor.md
git commit -m "feat: comando /swarm:doctor"
```

---

### Task 5: Checklist de smoke (gate manual del owner)

**Files:**
- Create: `docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`

**Interfaces:** ninguna — este task no produce código, produce el documento que el owner ejecuta
a mano contra una sesión real de `claude`.

**Modelo:** sesión real del owner (no un agente) · **Review:** N/A — este task ES el gate.

- [ ] **Paso 1: escribir y commitear el checklist**

```markdown
# Checklist de smoke — Fase 1b requisitos (`requirements-orchestrator` + `env-checker`)

Gate manual del owner. Ejecutar contra un repo fixture (el propio checkout de `swarm` sirve, ya
trae `git`/`python3`/`uuidgen`) con:
`claude -p "/swarm:doctor" --plugin-dir /Users/davidgarciagordo/projects/multiagents --permission-mode bypassPermissions`

Cada ítem lleva un campo **Evidencia:** para pegar la salida real — no marcar sin pegarla.

## 1. `/swarm:doctor` — repo con todos los requisitos presentes

Se espera: `requirements-orchestrator` lanzado, SPAWNS (nunca `SendMessage`) a `env-checker`
NOMBRADO exactamente `env-checker`, y el veredicto final es `OK` (la máquina real tiene `git`,
`python3` y `uuidgen` — los tres `required: true` del `requirements.json` del propio plugin).
Evidencia:

## 2. `/swarm:doctor` — requisito requerido ausente (tool inventada)

Copia `requirements.json` a un fichero temporal fuera del repo del plugin, añade a mano una
entrada `os` con un `tool` inventado (`"swarm-fake-tool-zzz"`) y `"required": true`, y apunta a
esa copia editando el `requirements.json` real de un checkout de PRUEBA (nunca el del repo del
plugin en producción). Se espera: `BLOCKED swarm-fake-tool-zzz` con el hint de instalación exacto,
propagado literal desde `env-checker` hasta el veredicto final que ve el usuario.
Evidencia:

## 3. `env-checker` nunca reimplementa el chequeo

Confirma en el transcript que `env-checker` invoca `scripts/req-check.sh` (Bash) y NO escribe
lógica de presencia/versión por su cuenta (nada de `command -v` suelto fuera del script, nada de
comparación de versión a mano en su prompt/razonamiento).
Evidencia:

## Firma

- [ ] Owner: ________________  Fecha: ________________
```

Guarda lo anterior en `docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md`.

- [ ] **Paso 2: commit**

```bash
git add docs/superpowers/plans/2026-09-02-phase1b-smoke-checklist.md
git commit -m "docs: checklist de smoke fase 1b (gate manual del owner)"
```

---

## Alcance — lo que este plan NO construye

`dependency-auditor` y `dependency-installer` (spec §7 "Requisitos", fase 5 en §15) no aparecen
en ningún fichero de este plan: ni como agente, ni como stub, ni mencionados en `tools:` de
ningún frontmatter, ni en `hooks/bash-allowlist.json`. `requirements-orchestrator` documenta en
prosa (Task 3, "Operación `install`") que cualquier petición de instalación se responde con
`BLOCKED dependency-installer no implementado aún (fase 5)` — es la única forma en que este plan
"toca" esos dos agentes: para decir explícitamente que no existen todavía.

## Ejecución

Tras guardar este plan, dos opciones:

1. **Subagent-Driven (recomendado)** — un subagente fresco por tarea, review entre tareas,
   iteración rápida. SUB-SKILL REQUERIDA: `superpowers:subagent-driven-development`.
2. **Ejecución inline** — ejecutar las tareas en esta misma sesión con checkpoints de revisión.
   SUB-SKILL REQUERIDA: `superpowers:executing-plans`.
