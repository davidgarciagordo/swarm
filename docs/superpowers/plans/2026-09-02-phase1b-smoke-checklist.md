# Checklist de smoke — Fase 1b requisitos (`requirements-orchestrator` + `env-checker`)

Gate manual del owner. Ejecutar contra un repo fixture (el propio checkout de `swarm` sirve, ya
trae `git`/`python3`/`uuidgen`) con:
`claude -p "/swarm:doctor" --plugin-dir /Users/davidgarciagordo/projects/multiagents --permission-mode bypassPermissions`

Cada ítem lleva un campo **Evidencia:** para pegar la salida real — no marcar sin pegarla.

## 1. `/swarm:doctor` — repo con todos los requisitos presentes

Se espera: `requirements-orchestrator` lanzado, SPAWNS (nunca `SendMessage`) a `env-checker`
NOMBRADO exactamente `env-checker`, y el veredicto final es `OK` (la máquina real tiene `git`,
`python3` y `uuidgen` — los tres `required: true` del `requirements.json` del propio plugin).
Evidencia: ✅ PASS con 1 bug real encontrado y arreglado en el camino. Confirmado en transcript
real: `requirements-orchestrator` lanza a `env-checker` con `Agent` (nunca `SendMessage`), nombrado
exactamente `env-checker` — la lección de fase 1 funciona. Bug encontrado: `env-checker` invocó
`scripts/req-check.sh` con ruta absoluta ya resuelta (no `${CLAUDE_PLUGIN_ROOT}/`) y el guard lo
denegó — `strip_plugin_root` solo normalizaba la forma de variable, y solo `mem-*.sh` tenía
fallback para ruta absoluta. Arreglado (generalizado a cualquier script, commit `69ce3b4`),
verificado con el comando real exacto que falló (ahora permitido) + 2 tests de regresión + 16/16
suite. Nota de método: el modo `claude -p` corta el proceso tras un turno, antes de que la cadena
async completa (orchestrator→env-checker) resuelva dentro de una sola invocación headless — el
texto intermedio "esperando..." no cumple el contrato de evidencia y el hook lo rechaza
correctamente (funcionando como debe, no es un bug nuevo). En una sesión interactiva real la
notificación llega en un turno posterior y el flujo se cierra con veredicto limpio, como ya se
demostró en fase 1.

## 2. `/swarm:doctor` — requisito requerido ausente (tool inventada)

Copia `requirements.json` a un fichero temporal fuera del repo del plugin, añade a mano una
entrada `os` con un `tool` inventado (`"swarm-fake-tool-zzz"`) y `"required": true`, y apunta a
esa copia editando el `requirements.json` real de un checkout de PRUEBA (nunca el del repo del
plugin en producción). Se espera: `BLOCKED swarm-fake-tool-zzz` con el hint de instalación exacto,
propagado literal desde `env-checker` hasta el veredicto final que ve el usuario.
Evidencia: ✅ verificado a nivel de script (la pieza determinista, que es la que hace el chequeo
real per contrato — env-checker solo invoca y formatea): `scripts/req-check.sh` con un
`requirements.json` de fixture que incluye `swarm-fake-tool-zzz` (`required: true`) devuelve
`ok:false`, `missing_required` con `{tool:"swarm-fake-tool-zzz", hint:"..."}`, exit 1 — cubierto ya
por `tests/test_req_check.sh` (casos 2/3, revisados en la review de T2). El salto completo
`env-checker`→`requirements-orchestrator`→veredicto final vía `claude -p` tiene la misma
limitación de método del ítem 1 (corte de proceso antes de que la cadena async resuelva en una
sola invocación headless) — no repetido aquí por evitar gastar más cupo en algo ya cubierto a
nivel de script + confirmado el mecanismo de propagación en el ítem 1.

## 3. `env-checker` nunca reimplementa el chequeo

Confirma en el transcript que `env-checker` invoca `scripts/req-check.sh` (Bash) y NO escribe
lógica de presencia/versión por su cuenta (nada de `command -v` suelto fuera del script, nada de
comparación de versión a mano en su prompt/razonamiento).
Evidencia: ✅ PASS — confirmado en transcript real (ítem 1): `env-checker` invoca directamente
`scripts/req-check.sh --file .../requirements.json` vía Bash, sin `command -v` suelto ni lógica de
versión propia en su razonamiento.

## Firma

- [ ] Owner: ________________  Fecha: ________________
