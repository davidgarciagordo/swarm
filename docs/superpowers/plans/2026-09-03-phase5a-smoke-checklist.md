# Checklist de smoke — Fase 5a implementation (`implementation-orchestrator` + test-writer/implementer/quality-fixer/reviewer)

Gate. Ejecutado headless (`claude -p --plugin-dir <este worktree> --permission-mode
bypassPermissions`) contra un fixture desechable con `/swarm:init` + un plan real escrito a mano
en el formato exacto de `planner` (fase 4) — no se encadenó discovery+design completo por coste de
turnos; el plan en sí es el artefacto que `implementation-orchestrator` consume, así que probarlo
con un plan válido y honesto (marcado `**Grill:** arbitrado`) es representativo.

## 1. Ciclo completo: RED → worktree aislado → GREEN → quality → review limpio → merge → limpieza

`implementation-orchestrator` lanzado adhoc (invocación explícita, como siempre en este dominio)
sobre un plan real de un VO `Money` con invariante de moneda, en una rama de trabajo real
(`run-branch`, no `master`).
Evidencia: ✅ PASS — cadena completa real, verificada por `git log --all --oneline` tras el run:
```
a293ff5 feat: Phase 1 Money VO — add() seguro por moneda, plan marcado [x]
7e144a9 test: RED para Phase 1 Money VO con add() seguro — Money.php aun no existe
```
`test-writer` commiteó el RED directo a `run-branch` (7e144a9); `implementer` implementó en su
worktree aislado, confirmó GREEN, marcó los 2 `- [ ] Step N` del plan como `- [x]` con
`fichero:línea` reales (`src/App/Money.php:5-11`, `:13-21`), y commiteó (a293ff5) — **fusionado de
verdad** a `run-branch` (`git branch -a` tras el run: `run-branch` apunta a a293ff5). `quality-fixer`
corrió (el propio agente reportó "quality-fixer×2", iteró). `reviewer` encontró 3 hallazgos
`MINOR` reales (`currency sin validar`, `overflow PHP_INT_MAX`, `.gitignore` sin `vendor/`) —
**correctamente aparcados sin bloquear el merge**, listados explícitos en la salida final
(`- riesgo aparcado: …` ×3), no tragados en silencio.
Veredicto final real:
```
DONE
evidence: files=9 cmds=17 turns=19/25
- implementation: Phase 1 fusionada a run-branch (test-writer→implementer→quality-fixer×2→reviewer), 2 steps [x]
```

## 2. `implementer` NUNCA modifica el checkout principal — solo su worktree, y se limpia de verdad

Evidencia: ✅ PASS, con un hallazgo metodológico honesto — el propio resumen del agente coordinador
dijo inicialmente "worktree sigue existiendo, no eliminado", pero al inspeccionar el repo
DIRECTAMENTE tras el run: el directorio `.claude/worktrees/agent-<id>` ya no existía en disco, y
`git worktree prune -v` no encontró NINGÚN registro obsoleto que podar — confirma que
`git worktree remove --force` (el fix I1 de la review final de Task 6) SÍ se ejecutó correctamente
y de forma limpia (sin metadata huérfana en `.git/worktrees/`). El "sigue existiendo" del resumen
del agente fue una lectura del estado en un momento anterior a que su propio paso de limpieza
terminara, no un bug real del enjambre — confirmado con evidencia de disco, no solo confiando en
el texto del resumen.

## 3. Gate de reviewer bloquea el merge cuando hay Critical — no ejecutado en este smoke

No se provocó un hallazgo Critical real en este smoke (el VO de prueba era demasiado simple para
uno genuino) — el mecanismo de relanzamiento con `operation: implement-fix` y el cap de 2 rondas
se verificó por code review exhaustivo (Task 6, 2 rondas de review, cada rama de salida trazada a
mano por la revisora) pero no se ejercitó en vivo. Pendiente de una verificación en vivo futura si
se toca esta lógica.

## 4. El plan se marca `[x]` correctamente tras el merge

Evidencia: ✅ PASS — confirmado directamente en disco tras el run:
```
- [x] Step 1: crear src/App/Money.php con el constructor y el invariante de moneda (src/App/Money.php:5-11)
- [x] Step 2: implementar add() lanzando excepción si las monedas difieren, sumando si coinciden (src/App/Money.php:13-21)
```
`fichero:línea` reales, no genéricos — `implementer` citó las líneas reales de su propia
implementación, no una plantilla vacía.

## 5. Ningún push, ninguna rama compartida tocada — y la guardia contra `master` responde a input

`git branch -a` tras el run principal: solo `run-branch` tiene el commit nuevo, `master` intacto.
Ningún `git push` en ningún momento (confirmado también por allowlist — ningún agente del dominio
lo tiene, verificado por code review de Task 1/6).
**Guardia anti-`master` (`git rev-parse --abbrev-ref HEAD` antes del merge, fix I2 de Task 6)**: se
intentó un segundo run con `HEAD` en `master` de verdad — el run se `BLOCKED` correctamente y sin
avanzar (`git log master` sin commits nuevos, sin worktree extra), pero el motivo real fue
`test-writer` rechazando una Fase con bloque `Tests:` vacío (una guarda distinta, también correcta)
ANTES de llegar al paso de merge donde la guardia anti-`master` seguiría — la cadena nunca llegó a
abrir un worktree de `implementer`, así que la guardia anti-`master` en sí no se disparó en este
smoke. Queda verificada por trazado exhaustivo de código (re-review de Task 6, las 10 rutas de
salida posibles recorridas a mano) pero no por disparo en vivo — pendiente de una verificación
futura con un plan cuya Fase 2 tenga un bloque `Tests:` real, para forzar la cadena hasta el paso
de merge estando en `master`.

## Bugs encontrados y arreglados durante esta fase (antes de este smoke, en las reviews de tarea)

Ninguno nuevo en ESTE smoke — 3 bugs reales de test propio del plan (Task 1 `find`-differentiator,
Task 3 `\-\-fix` sobre-escapado, Task 5 `'checkbox'` inexistente) y 2 hallazgos de seguridad reales
en Task 6 (limpieza de worktree solo en camino feliz, sin guardia real contra merge en master) más
2 en Task 7 (mismo patrón de saneado que ya había fallado en fases previas, aplicado tarde a §10;
enumeración de §4 sin las líneas de §10.4) — todos se encontraron y arreglaron en las reviews de
tarea, antes de este smoke. Este smoke confirma en vivo que el mecanismo más incierto de la fase —
el ciclo completo de 5 agentes con merge real y limpieza de worktree — funciona de verdad contra
una ejecución real, no solo contra análisis estático.

## Firma

- [x] Owner: sesión autónoma nocturna — Fecha: 2026-09-03
