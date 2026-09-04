# Handoff — swarm, 2026-09-03 (TODAS las fases del roster cerradas — decisión de v1)

## Prompt copy-paste para la sesión nueva

> Lee `docs/superpowers/handoffs/2026-09-02-next-session.md` en `/Users/davidgarciagordo/projects/multiagents`
> y continúa desde ahí. **No hay más fases de construcción pendientes** — las 6 fases del roster
> (1, 1b, 2, 3, 4, 5a, 5b, 6) están cerradas, mergeadas a `master` y **pusheadas al remoto real**
> (`github.com/davidgarciagordo/swarm`). Lo que queda es una **decisión del owner**: qué del backlog
> acumulado se arregla antes de llamarlo v1 estable, y qué queda documentado como backlog post-v1.
> Esta sesión NO toma esa decisión por su cuenta — la presenta con todo el contexto y espera. Si el
> owner ya la tomó en otra conversación, aplica lo que haya decidido y cierra los ítems correspondientes
> en este mismo fichero.

## Estado real (verificado, no de memoria)

- Repo: `/Users/davidgarciagordo/projects/multiagents`, rama `master`, **con remoto real**:
  `origin git@github-personal-david:davidgarciagordo/swarm.git` (creado y pusheado por primera vez
  el 2026-09-03, con la identidad SSH personal correcta tras un bug real de alias encontrado en vivo
  esa misma noche — ver "Lecciones" más abajo).
- **35 agentes** (`ls agents/*.md | wc -l`), **5 comandos** (`/swarm:init`, `/swarm:run`,
  `/swarm:doctor`, `/swarm:status`, `/swarm:findings`), **53 ficheros de test, 53/53 en verde**
  (`bash tests/run.sh`). El roster original del spec (v2.1) contaba 30 agentes propios; el total
  real es 35 porque una sesión peer añadió `swarm:verifier` (spec v2.2 §14bis, gate de verificación
  independiente) mientras esta sesión trabajaba en fase 6 — coordinado en vivo, sin conflicto,
  documentado abajo.
- **Guía de uso completa: `docs/USAGE.md` / `docs/USAGE.es.md`** — actualizada en cada fase que
  añadió comandos/dominios nuevos, incluida fase 6.

## Las 6 fases, en una frase cada una (detalle completo en `git log` o memoria persistente)

1. **Núcleo** (`orchestrator`, memoria, `/swarm:init`) — completa.
2. **Discovery** (`discovery-orchestrator` + 4 hojas, `AskUserQuestion`) — completa.
3. **Analysis** (`analysis-orchestrator` + 6 lentes read-only) — completa.
4. **Design** (`design-orchestrator`, `planner`, grill×3 cross-plugin) — completa.
5a. **Implementation** (TDD real: test-writer→implementer→quality-fixer→reviewer→merge local) —
   completa. Primera fase que escribe/fusiona código real.
5b. **Requisitos + stack pack** (`php-ddd-symfony8`, `dependency-auditor`/`installer`,
   `migration-engineer`, `doc-writer`) — completa.
6. **Delivery** (`delivery-orchestrator`/`release-manager`/`handoff-writer`,
   `/swarm:status`/`/swarm:findings`) — completa. **Primera y única fase con `git push`/creación de
   repo real** — ver detalle abajo, es la de más escrutinio de seguridad de todo el proyecto.

**Trabajo concurrente coordinado**: durante fase 6, una sesión peer diseñó y mergeó en paralelo
`swarm:verifier` (gate de verificación independiente que corre tras el cierre en verde de CUALQUIER
dominio, spec §14bis) — coordinado en vivo por mensaje cruzado de sesión para no pisar
`agents/orchestrator.md` a la vez; fase 6 tuvo que fusionar ese trabajo a mitad de camino e integrar
su propio `## 12. Entrega` alrededor de él (ver Task 6 de fase 6 en el ledger histórico).

## Fase 6 en detalle — la de más peso de todas

`release-manager` publica con **dos fases**: `prepare-release` muestra un preview real (comandos
exactos, remoto, nº de commits, estado de tests) sin tocar nada remoto; `publish-release` re-verifica
contra la realidad y solo entonces empuja, con una cabecera `approved-push: remote=… branch=… base=…`
que **solo la raíz puede construir**, tras una `AskUserQuestion` real al owner. `configure-remote`
(bootstrap de un remoto ausente) usa el mismo patrón con su propia cabecera `approved-remote:`,
nunca intercambiable con `approved-push:`. `gh pr merge` está permanentemente denegado — un humano
mergea siempre. `delivery-orchestrator` nunca encadena tras implementation, en ningún tier.

**El backstop determinista (`hooks/bash-guard.py`) se llevó 3 rondas completas de review adversarial
Opus dentro de esta misma fase** — la pieza de seguridad más escrutada de todo el proyecto:
- Ronda 1 (contra la implementación inicial): 5 Critical en un parser de shell hecho a mano.
- Ronda 2 (contra el parche de ronda 1): 6 Critical MÁS, con **force-pushes reales verificados
  contra un remoto bare desechable** — incluía RCE local vía `git push --receive-pack=`. Parchear
  un parser a mano bajo presión adversarial no converge → **cambio de arquitectura**: gate
  estructural nuevo, el comando completo tiene que casar `fullmatch` con una forma canónica muy
  estrecha por regex, o se deniega sin intentar entenderlo.
- Ronda 3 (contra el gate estructural): 0 bypasses nuevos tras 50 sondas adversariales frescas
  (percent-encoding, homoglifos, RTL, ZWSP, ReDoS) — 2 Important menores (un disparador que se
  saltaba con flags de valor separado; `--body-file` sin restringir a ruta relativa).
- **Review final de rama** (tras el smoke en vivo): 2 Important MÁS — `gh pr update-branch` y
  `gh auth switch` alcanzables sin ningún gate ni cobertura del gate estructural (mutaban un
  remoto/la identidad activa sin preview). Causa raíz: `gh pr`/`gh auth` eran denylist, el propio
  comentario del fichero ya predecía que eso envejece mal — exactamente lo que pasó. Convertidos a
  allowlist cerrado (mismo patrón que `gh repo`).
- **Smoke en vivo real** (push de verdad contra un bare local, nunca tocó red real): encontró y
  arregló 1 bug más (`release-manager` corría 2 comandos de Arranque antes de comprobar
  `approved-push:`, violando su propio contrato `cmds=0` en rechazo).

Total: **14 hallazgos Critical/Important reales encontrados y cerrados** solo en el backstop de
push de esta fase, en 4 rondas de escrutinio. No es señal de inestabilidad — es la cantidad de
escrutinio que un backstop de `git push` real merece, y el proceso (revisar, encontrar, arreglar,
re-verificar) funcionó exactamente como debía cada vez.

## Lecciones nuevas de fase 6 (súmalas a las acumuladas de fases 1-5b si tocas este dominio)

9. **Un denylist de subcomandos envejece mal y falla ABIERTO — usa allowlist cerrado siempre que el
   conjunto de comandos legítimos sea pequeño y conocido** (mismo principio ya aplicado a
   `gh repo` desde el diseño; `gh pr`/`gh auth` lo aprendieron por las malas en la review final).
10. **Un fix aplicado a UNA de dos operaciones estructuralmente idénticas no está completo** — el
    bug de orden del gate de aprobación (encontrado en vivo) solo se arregló en `publish-release`
    la primera vez; `configure-remote` tenía el mismo patrón y sobrevivió hasta la review final
    (misma clase que la lección 8 de fases anteriores, ahora confirmada una tercera vez).
11. **Cuando un parser hecho a mano para detectar comandos peligrosos lleva 2 rondas de bypasses
    reales, no sigas parcheándolo — cambia a un gate estructural** (fullmatch contra una forma
    canónica cerrada) que vuelve toda una clase de ataques irrepresentable, en vez de perseguir cada
    truco de shell uno a uno.
12. **Bug real de infraestructura de este proyecto, encontrado en vivo (no del plugin)**: el alias
    SSH por defecto de `github.com` en esta máquina resolvía a la identidad de trabajo
    (Classlife), no a la personal — `git push` fallaba con `denied to <otra cuenta>` incluso con
    `gh auth status` mostrando la cuenta correcta como activa. Arreglado apuntando el remoto al
    alias `github-personal-david` de `~/.ssh/config`. `release-manager` documenta este failure mode
    exacto (ruling 14) y surface el stderr literal para que el owner lo diagnostique — nunca lo
    reinterpreta ni intenta "arreglarlo" él mismo.

## ⚠️ Decisión pendiente del owner: qué se arregla antes de v1, qué queda de backlog

Esto es lo que esta sesión NO decide por su cuenta. Repaso completo de lo acumulado en las 6 fases:

### Pedido del owner sobre remotos NO-GitHub — RESUELTO en su alcance mínimo (2026-09-04)

David pidió (2026-09-03, antes de cerrar por la noche): *"apuntate que sino va el gh usar git
nativo que puede ser que sea gitlab o cualquier otro"*. Investigado a la mañana siguiente: el
`git push` en sí YA era agnóstico de host (nada que arreglar ahí), y `publish-release` YA degradaba
sin fallar cuando `gh pr create` no funcionaba — el hueco real era más estrecho de lo que parecía:
(1) el mensaje degradado siempre sugería literal `gh pr create ...` aunque el remoto fuera GitLab
(consejo erróneo, `gh` no funciona ahí), y (2) `action=create` (bootstrap de repo nuevo) nunca decía
explícitamente que solo crea en GitHub.

Presentadas 3 opciones de alcance (fix mínimo / soporte real de GitLab vía `glab` / arquitectura de
adaptador por host); **el owner eligió el fix mínimo** (commit `60eca27`, ya en master): el mensaje
degradado ahora detecta si el remoto es GitHub antes de intentar `gh pr create` — si no lo es, da un
mensaje genérico sin nombrar `gh`; `action=create` ahora dice explícitamente "solo crea en GitHub
(v1.1)" y apunta a `action=use` (agnóstico de host, ya funcionaba) para un repo que el owner cree él
mismo en otra plataforma.

**Review independiente confirmada (2026-09-04, agente `general-purpose`/Sonnet, dispatch separado):
APPROVED, cero hallazgos.** Verificó punto por punto: el chequeo de host se ejecuta ANTES de
`gh auth status` (no solo lo menciona en prosa); las 3 ramas de degradación (GitHub+éxito,
GitHub+fallo, no-GitHub) son completas y sin solape — cualquier URL rara cae en el caso genérico, no
hay 4º caso sin cubrir; cero regresión en `approved-push:`/re-verificación/`git push` (fuera del
diff); `agents/orchestrator.md` §12.2bis opción C referenciada correctamente; los 3 asserts nuevos de
`tests/test_delivery_agents.sh` prueban subcadenas reales introducidas por el commit, no tautologías;
53/53 en verde; identidad git personal correcta en `60eca27`. **Este ítem queda cerrado — ambos
huecos concretos que David señaló (consejo `gh` erróneo en host no-GitHub, alcance de `action=create`
sin documentar) están arreglados y verificados dos veces.**

**Lo único que sigue genuinamente abierto** (no es un gap arreglable a bajo coste, es alcance que el
owner no eligió): soporte real de creación de repo/apertura de MR en GitLab vía `glab` (mismo nivel
de escrutinio de guard que `gh` se llevó en fase 6) — era la opción 2 de las 3 presentadas, diferida
por decisión explícita del owner, no descartada. Candidato de v1.1 si algún día se quiere abordar.

### Backlog de seguridad/robustez (bajo riesgo hoy, documentado explícitamente en cada fase)

- ~~`hooks/bash-guard.py` sigue sin inspeccionar `$(...)`/backticks dentro de argumentos SIN
  COMILLAS de un comando ya permitido~~ — **RESUELTO, verificado 2026-09-04**: ya no es un hueco
  real. `all_segments()`/`_find_command_substitutions()` (endurecidas durante el hardening de fase
  6, rondas 1-2) inspeccionan `$(...)`/backticks/`<(...)`/`>(...)` en cualquier posición del texto,
  con o sin comillas, para TODO `agent_type` — no solo push/gh/remote. Confirmado con guard real:
  `git log --oneline -5 $(rm -rf /)` y su forma con backticks deniegan hoy para un agente genérico
  (`swarm:memory-orchestrator`), atribuido al cuerpo de la sustitución, no al comando externo.
  Regresión bloqueada en `tests/test_bash_guard_segments.sh` (commit `5b5c2e1`). La nota original
  quedó obsoleta tras el hardening de fase 6 sin que el backlog se actualizara — este párrafo cierra
  ese desfase.
- `release-manager` no crea tags ni edita `CHANGELOG.md` (ruling 7, fase 6) — desviación consciente
  de la letra del spec §7.
- ~~La lista de ramas protegidas de `hooks/bash-guard.py` es de 4 nombres fijos~~ — **AMPLIADA,
  2026-09-04**: extendida a 8 (`master`/`main`/`develop`/`trunk`/`stable`/`release`/`production`/
  `prod`, commit `5b5c2e1`, review Opus limpia, 54/54). El owner eligió explícitamente ampliar la
  lista estática sobre la alternativa dinámica (`git rev-parse --abbrev-ref origin/HEAD`), que
  habría sido la primera llamada a `subprocess` del fichero — riesgo/superficie nuevos frente a
  coste marginal bajo. Sigue siendo lista fija por nombre exacto (no cubre `release/<slug>` ni
  variantes con guion) — backlog genuino solo si algún día un equipo real lo pide.
- `release-manager` publica la rama actual, nunca crea `release/<slug>` (ruling 5, fase 6) —
  desviación consciente.
- El modo de fallo de identidad SSH (lección 12 arriba) se **reporta** literal pero no se detecta de
  forma estructurada — ruling 14, opción (b) deliberada. Si algún día duele de verdad, la opción (a)
  (parsear `~/.ssh/config`) queda como backlog explícito.
- `configure-remote/action=create` no tiene cobertura de extremo a extremo automática (crea un repo
  real bajo la cuenta del owner) — solo gates y guard verificados, la ejecución real es manual y
  opcional por diseño.
- `approved-push:` no lleva un campo `url=` — la re-verificación de fase B confirma que el remoto
  aprobado EXISTE, no que su URL sigue siendo la que vio el owner en el preview (mitigado porque
  `git remote set-url` está denegado para TODO agent_type, así que solo una acción humana directa en
  la máquina podría cambiarla entre fase A y B) — documentado como desviación consciente, candidato
  de v1.1 si algún día importa.
- `agents/orchestrator.md` §4 verify-gate + `hooks/bash-guard.py`: ambos ficheros con historial de
  regresión real en este proyecto (staleness, enumeraciones incompletas) — cualquier fase futura que
  los toque debe grepear el fichero ENTERO por el mismo patrón de bug, no asumir que un solo sitio
  es todo el problema (lección repetida 3+ veces).

### Backlog de producto (menor, no bloqueante)

- Extensiones de PHP (`ext-pdo` etc.) no expresables en el esquema de `requirements.json` del stack
  pack — documentado, sin consumidor real todavía.
- Piso `php >= 8.2` del stack pack es conservador, no verificado contra el floor real de Symfony 8.
- `dependency-installer` (fase 5b) acotado a gestores de proyecto, nunca `brew`/`apt` — desviación
  consciente del spec §7.
- `git worktree remove` no borra la rama `worktree-agent-<agentId>` — se acumula una rama muerta por
  fase implementada a lo largo de la vida del plugin.

### Lo que NO se construyó, fuera de alcance de v1 por diseño (spec §16)

Modo Agent Teams; UI/diseño visual; CI externo; más de un stack pack; 3 niveles de jerarquía de
agentes. Ninguno de estos bloquea v1 — están explícitamente fuera del spec v2.1/v2.2.

## Cómo tomar la decisión de v1

1. Repasa las dos secciones de backlog de arriba (seguridad/robustez y producto) con el owner.
2. Para cada ítem: ¿se arregla antes de declarar v1, o queda documentado como backlog post-v1 (este
   mismo fichero, o un fichero de backlog dedicado si el owner prefiere separarlo del handoff)?
3. El pedido de remotos no-GitHub necesita su propio ciclo (brainstorming → spec → plan) si el owner
   quiere abordarlo antes de v1 — no es parte de este backlog de fixes menores.
4. Una vez el owner decide, actualiza este fichero: mueve lo arreglado fuera de la lista, deja lo
   diferido con la decisión explícita anotada (fecha + motivo), y solo entonces se puede llamar v1
   "estable" de verdad — no antes.

## Memoria persistente relevante

Buscar con mem-search si está disponible: convención de nombres estable, routing de modelos, identidad
git personal (`garcia.gordo.david@gmail.com` para commits, `github-personal-david` como alias SSH
para el remoto), regla de saneado shell compartida (`skills/swarm-protocol/SKILL.md` §4.4), y las 12
lecciones acumuladas de las 6 fases (las últimas 4, de fase 6, están completas arriba).
