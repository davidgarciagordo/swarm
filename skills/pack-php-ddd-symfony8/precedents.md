# precedents — php-ddd-symfony8

Patrones ya en uso en repos de este stack. **Se reutilizan antes de introducir uno nuevo**
(`pattern-advisor` devuelve `reuse <x>` por defecto; `introduce <y>` exige justificación). Esta
lista es el punto de partida genérico del stack; `memory-builder` la complementa con los
precedentes REALES del repo concreto en `.swarm/context-pack.md` — cuando ambos digan cosas
distintas, **gana el repo**.

| patrón | dónde vive | cuándo se reutiliza |
|---|---|---|
| **Agregado + value objects** | `Domain/Model/`, `Domain/ValueObject/` | toda invariante de negocio; un dato con reglas propias (importe, email, identificador) es un VO, no un `string` |
| **Repositorio: interfaz en dominio, implementación en infraestructura** | `Domain/<Aggregate>Repository.php` + `Infrastructure/Persistence/Doctrine/Repository/` | todo acceso a persistencia; el handler depende de la interfaz |
| **Comando + handler por caso de uso** | `Application/<UseCase>/` | toda acción de escritura; un handler nuevo, nunca un método más en uno existente |
| **Consulta separada de la escritura (CQRS ligero)** | `Application/Find/`, `Application/Search/` | lecturas que no necesitan cargar el agregado completo |
| **Evento de dominio + `EVENT_NAME`** | `Domain/Event/` | efecto colateral que cruza agregados o contextos; nunca una llamada directa entre contextos |
| **Kernel compartido** | `src/Shared/` | identidad, criteria, excepciones base, bus de eventos — se extiende, no se duplica por contexto |
| **Tipo DBAL por value object** | `Infrastructure/Persistence/Doctrine/Mapping/<Aggregate>/Type/` | persistir un VO sin filtrar Doctrine al dominio |
| **Mapping XML en vez de atributos** | `Mapping/<Aggregate>/<Aggregate>.orm.xml` | mantener `Domain/` libre de anotaciones de framework |
| **Object Mother en tests** | `tests/…/<Aggregate>Mother.php` | construir agregados/comandos de prueba; evita el constructor desnudo repetido |
| **Un controlador por caso de uso** | `Infrastructure/Symfony/Controller/` | endpoint nuevo; nunca un controlador con seis acciones |
| **Excepción de dominio tipada** | `Domain/Exception/` | error de negocio; nunca `\Exception` genérica ni códigos HTTP en el dominio |
| **Pipeline de calidad encadenado** | `Makefile` / `grumphp.yml` / CI | orden `rector → formateador → phpstan → deptrac → tests`; añadir un paso se hace ahí, no en un agente |

## Antipatrones que este stack ya rechazó

- **Entidad anémica**: agregado con solo getters/setters y la lógica en el handler. Si el handler
  decide reglas de negocio, esas reglas van al agregado.
- **Repositorio genérico gigante** con métodos ad-hoc por consulta. Se usan criteria/specification.
- **Contexto que importa clases de otro contexto**. Va por evento o por el kernel compartido.
- **`array` como parámetro de dominio** en vez de un VO o una colección tipada.
- **Migración editada a posteriori** para "arreglar" un esquema (ver `boundaries.md`).
