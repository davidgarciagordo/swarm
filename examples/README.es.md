[English](README.md) | **Español**

# swarm — Ejemplos de uso

> Prompts copy-paste que muestran qué se dispara en cada paso, para distintos tipos de objetivo.

Son prompts reales — pégalos en Claude Code con swarm instalado. Cada ejemplo muestra qué dominios se encadenan, qué gates te preguntan algo, y cómo es "hecho" en ese camino. Ver `docs/USAGE.es.md` para la guía completa y el [Cómo funciona](../README.es.md#cómo-funciona) del `README.es.md` para la arquitectura.

---

## 1. Una funcionalidad bien acotada — el camino completo tier:full

```
/swarm:run "añade export CSV al listado de facturas"
```

**Qué se dispara:** `.swarm/` se inicializa solo si no existe todavía (sin `/swarm:init` aparte). `memory-orchestrator` comprueba el hash del repo — primera vez, no hay pack aún, así que `memory-builder` escanea una vez y escribe `.swarm/context-pack.md`; todos los agentes posteriores de este run lo reusan. `discovery-orchestrator` pregunta UNA tanda en lenguaje llano (p. ej. "¿exportar solo CSV o también Excel?", recomendada premarcada) y registra las respuestas. `design-orchestrator` lanza `pattern-advisor` + `domain-modeler`, luego `planner` escribe un plan real, y luego grill×3 lo ataca — si sale un hallazgo P1 (p. ej. la lente operador pregunta "¿qué pasa si el listado de facturas está vacío?"), `planner` revisa el plan antes de marcarlo arbitrado. `implementation-orchestrator` encadena TDD (RED → GREEN en worktree aislado) → `reviewer` (con severidad, antes de fusionar) por cada fase — solo cuando pides implementación explícitamente, nunca encadenado solo. La entrega (push/PR) es una invocación aparte y explícita, con su propio gate de aprobación — swarm nunca mergea ni publica por su cuenta.

## 2. Un refactor que se salta discovery pero sigue necesitando diseño

```
/swarm:run "extrae la lógica de cálculo de facturación a su propio módulo, sin cambiar el comportamiento"
```

**Qué se dispara:** un objetivo de refactor/migración no tiene ninguna decisión de producto que preguntar, así que `discovery-orchestrator` se salta — pero el objetivo es lo bastante sustancial como para necesitar un rediseño real, así que `design-orchestrator` se lanza directamente (el segundo de sus dos caminos de entrada). `pattern-advisor` + `domain-modeler` + `planner` + grill×3 corren igual que en el ejemplo 1; la única diferencia es que no hay paso de discovery antes, y el `context:` de decisiones de `design-orchestrator` llega vacío (esperado, no un error).

## 3. Un objetivo ambiguo — el gate de interpretación pregunta primero

```
/swarm:run "mejora el dashboard"
```

**Qué se dispara:** antes de nada, el gate de interpretación del objetivo comprueba la confianza. "Mejora" no nombra ningún resultado concreto, así que en vez de adivinar, swarm pregunta en lenguaje llano — algo como: *"¿Qué es lo que más te importa mejorar del dashboard?"* con opciones como "que cargue más rápido", "que se entienda mejor de un vistazo", "que se pueda personalizar" — recomendada premarcada, más la opción de escribir la tuya. El run ni siquiera se abre hasta que respondes. Si vuelves a lanzar el mismo texto crudo más tarde, swarm reusa esta misma interpretación — no vuelve a preguntar.

## 4. El mismo objetivo crudo, ya interpretado — sin repetir la pregunta

```
/swarm:run "mejora el dashboard"
```

**Qué se dispara (la segunda vez que lanzas este mismo texto):** el gate de interpretación encuentra una decisión previa en `.swarm/decisions.md` cuyo `raw:` casa, ya resuelta — salta directo al objetivo resuelto y sigue, sin `AskUserQuestion`. Por esto la pregunta del ejemplo 3 solo cuesta una vez, no una vez por run.

## 5. Una pregunta acotada de un solo dominio — tier:light, sin encadenar

```
/swarm:run "¿qué ficheros tocan el módulo de pagos?" --tier=light
```

**Qué se dispara:** `--tier=light` corre exactamente un dominio y para ahí — sin discovery, sin diseño, sin encadenar. Para un objetivo tan acotado, `analysis-orchestrator` elige las lentes que casan ("arquitectura", aquí) y reenvía sus hallazgos directamente, citando `fichero:línea`, sin ninguna pregunta al owner. (Flag de power-user/CI — ver la sección Avanzado de `docs/USAGE.es.md`; la mayoría de objetivos no lo necesitan, swarm infiere el `tier` de lo que pediste.)

---

## Componiendo con la familia

El grill×3 de diseño reusa los agentes `grill-architect/operator/engineer` de **`working-methods`** si ese plugin está instalado, y sus propias lentes nativas equivalentes si no — mismo ataque, mismo contrato de salida, nunca las dos a la vez. Ningún otro plugin de la familia hace falta para que swarm corra de principio a fin.
