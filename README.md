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
