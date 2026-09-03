# boundaries — php-ddd-symfony8

Qué NO se toca. Aplica a TODA hoja con `Write`/`Edit` (`implementer`, `test-writer`,
`quality-fixer`, `migration-engineer`, `doc-writer`) y a cualquier `--fix` automático. Si tu tarea
parece exigir tocar algo de esta lista, tu veredicto es `BLOCKED <qué límite y por qué>` — no lo
tocas "solo un poco".

## Nunca se edita a mano

| ruta / patrón | por qué |
|---|---|
| `vendor/` | lo genera `composer`; cualquier edición se pierde en el siguiente `install` |
| `node_modules/`, `public/build/`, `public/bundles/` | artefactos de build/assets |
| `var/` (`var/cache/`, `var/log/`, cachés de herramientas) | estado efímero; borrarlo es válido, editarlo no |
| proxies y metadatos generados de Doctrine | se regeneran; editarlos enmascara el bug real |
| `composer.lock`, `package-lock.json` | los escribe el gestor; a mano se corrompe el árbol de resolución |
| `.env`, `.env.local`, `config/secrets/` | secretos reales; ni se leen para citarlos ni se reescriben |
| `migrations/Version*.php` YA APLICADA | ver abajo |

## Migraciones ya aplicadas: se añaden, no se editan

Una migración que ya corrió en cualquier entorno es historia inmutable. Comprueba primero con la
clave `migrate-status` de `commands.md`. Corregir un esquema equivocado = **una migración nueva**
que lo arregla hacia delante. Editar una `VersionXXXXXXXXXXXXXX.php` ya ejecutada deja las bases
existentes en un estado que ninguna herramienta puede reconciliar.

Además: un agente **nunca aplica** migraciones contra una base real. La clave `migrate-up` de
`commands.md` es `--dry-run` a propósito. Aplicar es decisión del owner.

## Reglas de capa (las verifica `deptrac` si el repo lo tiene)

- `Domain/` no depende de `Application/`, `Infrastructure/`, Symfony ni Doctrine.
- `Application/` depende de `Domain/`, nunca de `Infrastructure/`.
- `Infrastructure/` puede depender de las dos.
- Un bounded context no importa clases internas de otro: se comunica por eventos de dominio o por
  el kernel compartido (`src/Shared/`).

Romper una de estas cuatro reglas no es un detalle de estilo: es el motivo por el que el repo está
organizado así. Si el trabajo la exige, es un hallazgo `ARCH`, no un atajo.

## Mapping y value objects van juntos

Cambiar `<Aggregate>.orm.xml` sin actualizar el agregado y su `<Vo>Type` (o al revés) produce un
fallo en runtime que ningún test unitario ve. Los tres ficheros se tocan en el mismo commit o no se
toca ninguno.

## Formato: lo arregla la herramienta

No reindentes, no reordenes imports y no cambies comillas a mano: corre la clave `fix` de
`commands.md`. Un diff de formato hecho a mano ensucia la review y compite con el formateador.
