# precedents — php-ddd-symfony8

Patterns already in use in repos of this stack. **They're reused before introducing a new one**
(`pattern-advisor` returns `reuse <x>` by default; `introduce <y>` requires justification). This
list is the stack's generic starting point; `memory-builder` complements it with the REAL
precedents of the specific repo in `.swarm/context-pack.md` — when the two disagree,
**the repo wins**.

| pattern | where it lives | when it's reused |
|---|---|---|
| **Aggregate + value objects** | `Domain/Model/`, `Domain/ValueObject/` | every business invariant; a piece of data with its own rules (amount, email, identifier) is a VO, not a `string` |
| **Repository: interface in domain, implementation in infrastructure** | `Domain/<Aggregate>Repository.php` + `Infrastructure/Persistence/Doctrine/Repository/` | every persistence access; the handler depends on the interface |
| **Command + handler per use case** | `Application/<UseCase>/` | every write action; a new handler, never one more method on an existing one |
| **Query separated from write (lightweight CQRS)** | `Application/Find/`, `Application/Search/` | reads that don't need to load the full aggregate |
| **Domain event + `EVENT_NAME`** | `Domain/Event/` | a side effect crossing aggregates or contexts; never a direct call between contexts |
| **Shared kernel** | `src/Shared/` | identity, criteria, base exceptions, event bus — it's extended, never duplicated per context |
| **DBAL type per value object** | `Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/` | persisting a VO without leaking Doctrine into the domain |
| **XML mapping instead of attributes** | `Mapping/<Aggregate>/<Aggregate>.orm.xml` | keeping `Domain/` free of framework annotations |
| **Object Mother in tests** | `tests/…/<Aggregate>Mother.php` | building test aggregates/commands; avoids the repeated bare constructor |
| **One controller per use case** | `Infrastructure/Symfony/Controller/` | a new endpoint; never a controller with six actions |
| **Typed domain exception** | `Domain/Exception/` | a business error; never a generic `\Exception` nor HTTP codes in the domain |
| **Chained quality pipeline** | `Makefile` / `grumphp.yml` / CI | order `rector → formatter → phpstan → deptrac → tests`; adding a step happens there, not in an agent |

## Antipatterns this stack already rejected

- **Anemic entity**: an aggregate with only getters/setters and the logic in the handler. If the
  handler decides business rules, those rules belong in the aggregate.
- **Giant generic repository** with ad-hoc methods per query. Criteria/specification are used
  instead.
- **A context that imports classes from another context**. Goes through an event or the shared
  kernel.
- **`array` as a domain parameter** instead of a VO or a typed collection.
- **A migration edited after the fact** to "fix" a schema (see `boundaries.md`).
