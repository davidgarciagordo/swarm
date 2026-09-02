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
