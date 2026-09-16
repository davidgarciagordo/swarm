# conventions — php-ddd-symfony8

Conventions for a PHP repo with tactical DDD on Symfony 8. Examples use fictional names
(`Billing`, `Invoice`, `Order`) — replace them with the real repo's, already available in
`.swarm/context-pack.md`.

## Layout: context → aggregate → layer

```
src/<BoundedContext>/<Aggregate>/<Layer>
```

Bounded contexts are the top-level directories under `src/`; inside each one, a
directory per aggregate; inside each aggregate, the three layers. Example:

```
src/Billing/Invoice/Domain
src/Billing/Invoice/Application
src/Billing/Invoice/Infrastructure
src/Shared/Core/Domain          ← shared kernel (identity, events, criteria, base exceptions)
```

It is not `src/<Layer>/<Context>` nor `src/Domain/<Context>`: the unit of cohesion is the
aggregate, and the three layers live together because they change together.

### `Domain/`

```
Domain/Model/<Aggregate>.php                 aggregate root (+ <Aggregate>Collection.php)
Domain/ValueObject/<Vo>.php                  one file per value object
Domain/Event/<Aggregate><PastParticiple>.php domain events
Domain/Service/<Something>.php               stateless domain services
Domain/Exception/<Aggregate>NotFoundException.php
Domain/<Aggregate>Repository.php             repository INTERFACE, at the Domain/ root
```

Hard rule: `Domain/` imports NOTHING from Symfony, Doctrine or `Infrastructure/`. If you need a
framework type in the domain, the design is wrong, not the rule.

### `Application/` — one folder per use case

```
Application/Create/CreateInvoiceCommand.php
Application/Create/CreateInvoiceCommandHandler.php
Application/Find/FindById/FindInvoiceByIdQuery.php
Application/Search/ByCriteria/SearchInvoicesByCriteriaQuery.php
```

Verbs from the closed set `Create | Update | Patch | Delete | Find | Search`. Each use case is
a command/query pair + its handler; the handler orchestrates, it doesn't hold business rules
(those live in the aggregate).

### `Infrastructure/`

```
Infrastructure/Persistence/Doctrine/Repository/Doctrine<Aggregate>Repository.php
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/<Aggregate>.orm.xml
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/<Vo>Type.php
Infrastructure/Persistence/Doctrine/Fixture/<Aggregate>Fixture.php
Infrastructure/Symfony/Controller/<Verb><Aggregate>Controller.php
```

XML mapping (not attributes) keeps the domain free of framework annotations. Every persisted
value object has its own DBAL type (`<Vo>Type`), registered in Doctrine's configuration.

## Naming

| element | pattern | example |
|---|---|---|
| aggregate | bare noun, same as its folder | `Invoice` |
| collection | `<Aggregate>Collection` | `InvoiceCollection` |
| value object | bare noun, WITHOUT a `VO`/`ValueObject` suffix | `Id`, `Amount`, `Title` |
| domain event | `<Aggregate><PastParticiple>`, no `Event` suffix, with a dotted-snake `EVENT_NAME` | `InvoiceCreated` → `public const string EVENT_NAME = 'invoice.created';` |
| repository interface | `<Aggregate>Repository` (in `Domain/`) | `InvoiceRepository` |
| implementation | `Doctrine<Aggregate>Repository` (in `Infrastructure/`) | `DoctrineInvoiceRepository` |
| command / handler | `<Verb><Aggregate>Command` + `…CommandHandler` | `CreateInvoiceCommand` |
| controller | `<Verb><Aggregate>Controller` (plural for searches) | `SearchInvoicesController` |
| exception | `<Aggregate>NotFoundException`, extends the shared base | `InvoiceNotFoundException` |
| DBAL type | `<Vo>Type` | `AmountType` |
| migration | `Version<YYYYMMDDHHMMSS>.php` | `Version20260903120000.php` |

## Tests

```
tests/Unit/<Context>/<Aggregate>/Application/<UseCase>/<Handler>Test.php   unit, repos mocked
tests/Unit/<Context>/<Aggregate>/Infrastructure/Persistence/…Test.php
tests/Application/<Context>/<Aggregate>/Controller/<Verb><Aggregate>ControllerTest.php  functional
```

- Always the `*Test.php` suffix. The `tests/` tree is split first by test TYPE (`Unit/`,
  `Application/`) and only then replicates context/aggregate.
- **Object Mother** (`<Aggregate>Mother`, `<Command>Mother`) to build test data — never
  bare constructors repeated in every test.
- Unit tests don't touch the database; `Application/` tests boot the real kernel and are
  isolated per transaction.

## Style

- `declare(strict_types=1);` in every new PHP file, no exceptions.
- PSR-4 for autoloading, PSR-12 as the formatting baseline (enforced by the `fix` tool from
  `commands.md`, not by hand).
- Explicit types in every signature, including the return type; `readonly` on value objects.
- Private constructors + named constructors (`::create()`, `::fromPrimitives()`) on aggregates and
  VOs when the repo already does it that way (see `precedents.md`).
- Constructor injection; no service locators, no `static` with state.

## PHP extensions this stack assumes

`ext-json`, `ext-pdo` (+ the database driver: `ext-pdo_mysql`/`ext-pdo_pgsql`), `ext-mbstring`,
`ext-intl` if there's formatting/localization, `ext-openssl` if there's JWT. **Not declared in
`requirements.json`**: its schema (`os` = binaries, `libs` = packages of a manager) doesn't model
them, and `composer` already requires them on its own. They're listed here so whoever diagnoses an
environment failure knows where to look.
