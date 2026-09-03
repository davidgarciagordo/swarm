# conventions — php-ddd-symfony8

Convenciones de un repo PHP con DDD táctico sobre Symfony 8. Los ejemplos usan nombres ficticios
(`Billing`, `Invoice`, `Order`) — sustitúyelos por los del repo real, que ya están en
`.swarm/context-pack.md`.

## Layout: contexto → agregado → capa

```
src/<BoundedContext>/<Aggregate>/<Layer>
```

Los bounded contexts son los directorios de primer nivel bajo `src/`; dentro de cada uno, un
directorio por agregado; dentro de cada agregado, las tres capas. Ejemplo:

```
src/Billing/Invoice/Domain
src/Billing/Invoice/Application
src/Billing/Invoice/Infrastructure
src/Shared/Core/Domain          ← kernel compartido (identidad, eventos, criteria, excepciones base)
```

No es `src/<Capa>/<Contexto>` ni `src/Domain/<Contexto>`: la unidad de cohesión es el agregado, y
las tres capas viven juntas porque cambian juntas.

### `Domain/`

```
Domain/Model/<Aggregate>.php                 raíz del agregado (+ <Aggregate>Collection.php)
Domain/ValueObject/<Vo>.php                  un fichero por value object
Domain/Event/<Aggregate><PastParticiple>.php eventos de dominio
Domain/Service/<Algo>.php                    servicios de dominio sin estado
Domain/Exception/<Aggregate>NotFoundException.php
Domain/<Aggregate>Repository.php             INTERFAZ del repositorio, en la raíz de Domain/
```

Regla dura: `Domain/` no importa NADA de Symfony, Doctrine ni de `Infrastructure/`. Si necesitas un
tipo de framework en el dominio, el diseño está mal, no la regla.

### `Application/` — una carpeta por caso de uso

```
Application/Create/CreateInvoiceCommand.php
Application/Create/CreateInvoiceCommandHandler.php
Application/Find/FindById/FindInvoiceByIdQuery.php
Application/Search/ByCriteria/SearchInvoicesByCriteriaQuery.php
```

Verbos del conjunto cerrado `Create | Update | Patch | Delete | Find | Search`. Cada caso de uso es
un par comando/consulta + su handler; el handler orquesta, no contiene reglas de negocio (esas viven
en el agregado).

### `Infrastructure/`

```
Infrastructure/Persistence/Doctrine/Repository/Doctrine<Aggregate>Repository.php
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/<Aggregate>.orm.xml
Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/<Vo>Type.php
Infrastructure/Persistence/Doctrine/Fixture/<Aggregate>Fixture.php
Infrastructure/Symfony/Controller/<Verb><Aggregate>Controller.php
```

El mapping XML (no atributos) mantiene el dominio libre de anotaciones de framework. Cada value
object persistido tiene su tipo DBAL propio (`<Vo>Type`), registrado en la configuración de Doctrine.

## Naming

| elemento | patrón | ejemplo |
|---|---|---|
| agregado | sustantivo desnudo, igual que su carpeta | `Invoice` |
| colección | `<Aggregate>Collection` | `InvoiceCollection` |
| value object | sustantivo desnudo, SIN sufijo `VO`/`ValueObject` | `Id`, `Amount`, `Title` |
| evento de dominio | `<Aggregate><ParticipioPasado>`, sin sufijo `Event`, con `EVENT_NAME` en snake punteado | `InvoiceCreated` → `public const string EVENT_NAME = 'invoice.created';` |
| interfaz de repositorio | `<Aggregate>Repository` (en `Domain/`) | `InvoiceRepository` |
| implementación | `Doctrine<Aggregate>Repository` (en `Infrastructure/`) | `DoctrineInvoiceRepository` |
| comando / handler | `<Verb><Aggregate>Command` + `…CommandHandler` | `CreateInvoiceCommand` |
| controlador | `<Verb><Aggregate>Controller` (plural en búsquedas) | `SearchInvoicesController` |
| excepción | `<Aggregate>NotFoundException`, extiende la base compartida | `InvoiceNotFoundException` |
| tipo DBAL | `<Vo>Type` | `AmountType` |
| migración | `Version<YYYYMMDDHHMMSS>.php` | `Version20260903120000.php` |

## Tests

```
tests/Unit/<Context>/<Aggregate>/Application/<UseCase>/<Handler>Test.php   unitario, repos mockeados
tests/Unit/<Context>/<Aggregate>/Infrastructure/Persistence/…Test.php
tests/Application/<Context>/<Aggregate>/Controller/<Verb><Aggregate>ControllerTest.php  funcional
```

- Sufijo `*Test.php` siempre. El árbol de `tests/` se parte primero por TIPO de test (`Unit/`,
  `Application/`) y solo después replica contexto/agregado.
- **Object Mother** (`<Aggregate>Mother`, `<Command>Mother`) para construir datos de prueba — nunca
  constructores desnudos repetidos en cada test.
- Los tests unitarios no tocan base de datos; los de `Application/` levantan el kernel real y se
  aíslan por transacción.

## Estilo

- `declare(strict_types=1);` en todo fichero PHP nuevo, sin excepción.
- PSR-4 para autoload, PSR-12 como base de formato (lo impone la herramienta `fix` de
  `commands.md`, no tú a mano).
- Tipos explícitos en todas las firmas, incluido el retorno; `readonly` en value objects.
- Constructores privados + named constructors (`::create()`, `::fromPrimitives()`) en agregados y
  VOs cuando el repo ya lo haga así (ver `precedents.md`).
- Inyección por constructor; nada de service locators ni de `static` con estado.

## Extensiones de PHP que este stack asume

`ext-json`, `ext-pdo` (+ el driver de la base: `ext-pdo_mysql`/`ext-pdo_pgsql`), `ext-mbstring`,
`ext-intl` si hay formateo/localización, `ext-openssl` si hay JWT. **No se declaran en
`requirements.json`**: su esquema (`os` = binarios, `libs` = paquetes de un gestor) no las modela, y
`composer` ya las exige por su cuenta. Se listan aquí para que quien diagnostique un fallo de
entorno sepa dónde mirar.
