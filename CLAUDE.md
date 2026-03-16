# NovaVision Docs

## Alcance

- Este repo es la fuente de verdad de arquitectura, contratos, changelogs y planes de NovaVision.
- Responder y documentar siempre en español.

## Reglas operativas

- Este repo NO contiene código ejecutable; contiene documentación de arquitectura, changelogs operativos, planes y decisiones técnicas.
- Todo cambio en API, Admin, Web o E2E debe tener su changelog correspondiente en `changes/YYYY-MM-DD-<slug>.md`.
- Los planes van en `plans/` y se crean/actualizan desde cualquier repo vía `plansDirectory`.
- No hacer `git commit`, `git push` sin confirmación explícita.
- Mantener `architecture/OVERVIEW.md` y `architecture/system_flows_and_persistence.md` actualizados cuando se cambie un contrato o flujo.

## Flujo recomendado con agentes

1. Ejecutar `context-mapper` para localizar documentos afectados antes de editar.
2. Ejecutar `docs-engineer` para redactar o actualizar changelogs, arquitectura o planes.
3. Ejecutar `quality-gate` para validar estructura, links rotos y consistencia.

## Estructura clave

- `architecture/` — documentos de arquitectura y contratos
- `changes/` — changelogs operativos por fecha
- `plans/` — planes de implementación compartidos entre repos
- `audit/` — auditorías de código y seguridad
- `e2e/` — documentación de tests E2E
